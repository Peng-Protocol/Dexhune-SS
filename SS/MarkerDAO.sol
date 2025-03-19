// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

// BSD 3-Clause License
// Copyright (c) 2025, Peng Protocol
// All rights reserved.

// v0.0.20
// Changes from v0.0.19:
// - Renamed pendingProposalCount to proposalCount
// - Simplified queryProposals and queryRoutines to take only index parameter
// - Removed proposeRoutineRemoval and associated RoutineRemoval logic
// - Removed removedRoutines mapping and removedRoutineCount
// - Maintained proposalType as 1,2,3; 3 is a ghost (non-functional)

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/IERC20Metadata.sol";
import "./imports/IERC721.sol";
import "./imports/IERC721Enumerable.sol";
import "./imports/SafeMath.sol";
import "./imports/ReentrancyGuard.sol";

contract MarkerDAO is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Core Parameters
    address public nftCollection;
    address public fftToken;
    uint256 public turnoutThreshold = 333; // 33.3% scaled as 333/1000
    uint256 public approvalThreshold = 510; // 51% scaled as 510/1000
    uint256 public finalizeTimeLimit = 24 * 60 * 60; // 24 hours
    uint256 public constant MAX_VOTES_PER_CALL = 30;

    // Enums and Structs
    enum ProposalType { Regular, Routine, RoutineRemoval } // 3 is ghost
    enum ProposalStatus { Pending, Rejected, Passed }

    struct Proposal {
        uint256 index;
        string detail;
        address target;
        bytes callData;
        uint256 value;
        ProposalType proposalType;
        ProposalStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 turnout;
        uint256 deadline;
    }

    struct Routine {
        uint256 index;
        string detail;
        address target;
        bytes callData;
        uint256 value;
        address proposer;
        uint256 interval;
        uint256 runwayEnd;
        uint256 lastExecution;
        bool active;
        uint256 proposalIndex;
    }

    struct RoutineParams {
        uint256 interval;
        uint256 runwayDuration;
    }

    struct ProposalData {
        uint256 index;
        string detail;
        address target;
        bytes callData;
        uint256 value;
        ProposalType proposalType;
        ProposalStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 turnout;
        uint256 deadline;
        uint256 finalizeTimeRemaining;
    }

    struct RoutineData {
        uint256 index;
        string detail;
        address target;
        bytes callData;
        uint256 value;
        address proposer;
        uint256 interval;
        uint256 runwayEnd;
        uint256 lastExecution;
        bool active;
        uint256 proposalIndex;
    }

    // Storage
    mapping(uint256 => Proposal) pendingProposals;
    mapping(uint256 => Proposal) passedProposals;
    mapping(uint256 => Proposal) rejectedProposals;
    uint256 public proposalCount; // Renamed from pendingProposalCount
    uint256 public passedProposalCount;
    uint256 public rejectedProposalCount;

    mapping(uint256 => Routine) activeRoutines;
    uint256 public activeRoutineCount;

    mapping(uint256 => RoutineParams) routineParams;
    mapping(uint256 => mapping(uint256 => bool)) nftVoted;
    mapping(uint256 => mapping(address => uint256[])) voterTokens;

    // Events
    event ProposalCreated(uint256 indexed index, address indexed proposer, string detail, address target, bytes callData, uint256 value, ProposalStatus status);
    event Voted(uint256 indexed index, address indexed voter, bool inFavor, uint256 nftTokenId, uint256 fftSpent);
    event ExecutionResult(uint256 indexed index, bool ethSuccess, bool callSuccess, bytes returnData);
    event ProposalStatusUpdated(uint256 indexed index, ProposalStatus newStatus);
    event RoutineCreated(uint256 indexed routineId, uint256 indexed proposalId, address target, bytes callData, uint256 value, uint256 interval, uint256 runwayEnd);
    event RoutineExecuted(uint256 indexed routineId, uint256 executionTime);
    event RoutineExpired(uint256 indexed routineId);
    event NFTCollectionSet(address indexed newCollection);
    event FFTTokenSet(address indexed newToken);
    event FinalizeTimeLimitSet(uint256 newLimit);

    constructor() {}

    receive() external payable {}

    function tryDecimals(IERC20Metadata token) internal view returns (uint8) {
        try token.decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18;
        }
    }

    function setFinalizeTimeLimit(uint256 newLimit) external onlyOwner {
        require(newLimit > 0, "Invalid time limit");
        finalizeTimeLimit = newLimit;
        emit FinalizeTimeLimitSet(newLimit);
    }

    function setNFT(address _nftCollection) external onlyOwner {
        require(_nftCollection != address(0), "Invalid NFT address");
        nftCollection = _nftCollection;
        emit NFTCollectionSet(_nftCollection);
    }

    function setFFT(address _fftToken) external onlyOwner {
        require(_fftToken != address(0), "Invalid FFT address");
        fftToken = _fftToken;
        emit FFTTokenSet(_fftToken);
    }

    function propose(address target, bytes calldata callData, uint256 value, string calldata detail) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");
        require(target != address(0), "Invalid target address");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken)));
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = proposalCount++;
        Proposal storage newProposal = pendingProposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.target = target;
        newProposal.callData = callData;
        newProposal.value = value;
        newProposal.proposalType = ProposalType.Regular;
        newProposal.status = ProposalStatus.Pending;
        newProposal.votesFor = 0;
        newProposal.votesAgainst = 0;
        newProposal.turnout = 0;
        newProposal.deadline = block.timestamp + 604800;

        emit ProposalCreated(index, msg.sender, detail, target, callData, value, ProposalStatus.Pending);
    }

    function proposeRoutine(address target, bytes calldata callData, uint256 value, string calldata detail, uint256 interval, uint256 runwayDuration) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");
        require(target != address(0), "Invalid target address");
        require(interval > 0, "Invalid interval");
        require(runwayDuration > 0, "Runway duration must be positive");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken)));
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = proposalCount++;
        Proposal storage newProposal = pendingProposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.target = target;
        newProposal.callData = callData;
        newProposal.value = value;
        newProposal.proposalType = ProposalType.Routine;
        newProposal.status = ProposalStatus.Pending;
        newProposal.votesFor = 0;
        newProposal.votesAgainst = 0;
        newProposal.turnout = 0;
        newProposal.deadline = block.timestamp + 604800;

        routineParams[index] = RoutineParams(interval, runwayDuration);
        emit ProposalCreated(index, msg.sender, detail, target, callData, value, ProposalStatus.Pending);
    }

    function voteProposal(bool isUpvote, uint256 proposalId, uint8 proposalType, uint256 fftAmount) external {
        require(proposalId < proposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[proposalId];
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(uint8(proposal.proposalType) + 1 == proposalType, "Invalid proposal type");

        uint256 voterBalance = IERC721Enumerable(nftCollection).balanceOf(msg.sender);
        require(voterBalance > 0, "Not an NFT holder");
        require(fftAmount > 0, "Invalid FFT amount");

        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftAmount);
        _castVotes(proposalId, isUpvote, fftAmount, voterBalance);

        if (block.timestamp >= proposal.deadline && proposal.turnout < (IERC721Enumerable(nftCollection).totalSupply() * turnoutThreshold) / 1000) {
            moveToRejected(proposalId);
        }
    }

    function _castVotes(uint256 proposalId, bool isUpvote, uint256 fftAmount, uint256 voterBalance) internal {
        Proposal storage proposal = pendingProposals[proposalId];
        uint256 votesCast = 0;
        uint256 maxIterations = voterBalance > MAX_VOTES_PER_CALL ? MAX_VOTES_PER_CALL : voterBalance;
        for (uint256 i = 0; i < maxIterations && votesCast < MAX_VOTES_PER_CALL; i++) {
            uint256 tokenId = IERC721Enumerable(nftCollection).tokenOfOwnerByIndex(msg.sender, i);
            if (!nftVoted[proposalId][tokenId]) {
                nftVoted[proposalId][tokenId] = true;
                voterTokens[proposalId][msg.sender].push(tokenId);
                if (isUpvote) {
                    proposal.votesFor = proposal.votesFor.add(1);
                } else {
                    proposal.votesAgainst = proposal.votesAgainst.add(1);
                }
                proposal.turnout = proposal.turnout.add(1);
                votesCast++;
                emit Voted(proposalId, msg.sender, isUpvote, tokenId, fftAmount / maxIterations);
            }
        }
        require(votesCast > 0, "No new votes cast");
    }

    function finalizeProposals(uint256 proposalId, uint8 proposalType) external nonReentrant {
        require(proposalId < proposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[proposalId];
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(uint8(proposal.proposalType) + 1 == proposalType, "Invalid proposal type");

        uint256 finalizeTimeEnd = proposal.deadline - 604800 + finalizeTimeLimit;
        require(block.timestamp >= finalizeTimeEnd, "Time limit not elapsed");

        if (proposalType == 1) {
            _finalizeRegular(proposalId);
        } else if (proposalType == 2) {
            _finalizeRoutine(proposalId);
        } else if (proposalType == 3) {
            _finalizeRoutineRemoval(proposalId); // Ghost: minimal logic
        }
    }

    function _finalizeRegular(uint256 proposalId) internal {
        Proposal storage proposal = pendingProposals[proposalId];
        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();

        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                require(address(this).balance >= proposal.value, "Insufficient ETH balance");
                if (proposal.value > 0) {
                    (bool ethSuccess, ) = proposal.target.call{value: proposal.value}("");
                    require(ethSuccess, "ETH transfer failed");
                    emit ExecutionResult(proposalId, ethSuccess, true, "");
                }
                if (proposal.callData.length > 0) {
                    (bool callSuccess, bytes memory returnData) = proposal.target.call(proposal.callData);
                    require(callSuccess, "Calldata execution failed");
                    emit ExecutionResult(proposalId, true, callSuccess, returnData);
                }
                moveToPassed(proposalId);
            } else {
                moveToRejected(proposalId);
            }
        } else if (block.timestamp >= proposal.deadline) {
            moveToRejected(proposalId);
        }
    }

    function _finalizeRoutine(uint256 proposalId) internal {
        Proposal storage proposal = pendingProposals[proposalId];
        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();

        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                uint256 routineId = activeRoutineCount++;
                activeRoutines[routineId] = Routine({
                    index: routineId,
                    detail: proposal.detail,
                    target: proposal.target,
                    callData: proposal.callData,
                    value: proposal.value,
                    proposer: msg.sender,
                    interval: routineParams[proposalId].interval,
                    runwayEnd: block.timestamp + routineParams[proposalId].runwayDuration,
                    lastExecution: 0,
                    active: true,
                    proposalIndex: proposalId
                });
                emit RoutineCreated(routineId, proposalId, proposal.target, proposal.callData, proposal.value, routineParams[proposalId].interval, block.timestamp + routineParams[proposalId].runwayDuration);
                moveToPassed(proposalId);
            } else {
                moveToRejected(proposalId);
            }
        } else if (block.timestamp >= proposal.deadline) {
            moveToRejected(proposalId);
        }
    }

    function _finalizeRoutineRemoval(uint256 proposalId) internal {
        // Ghost: Minimal logic, just reject or pass without execution
        Proposal storage proposal = pendingProposals[proposalId];
        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();

        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                moveToPassed(proposalId);
            } else {
                moveToRejected(proposalId);
            }
        } else if (block.timestamp >= proposal.deadline) {
            moveToRejected(proposalId);
        }
    }

    function moveToPassed(uint256 pendingIndex) internal {
        Proposal memory proposal = pendingProposals[pendingIndex];
        proposal.status = ProposalStatus.Passed;
        uint256 newIndex = passedProposalCount++;
        passedProposals[newIndex] = proposal;
        passedProposals[newIndex].index = newIndex;
        delete pendingProposals[pendingIndex];
        emit ProposalStatusUpdated(newIndex, ProposalStatus.Passed);
    }

    function moveToRejected(uint256 pendingIndex) internal {
        Proposal memory proposal = pendingProposals[pendingIndex];
        proposal.status = ProposalStatus.Rejected;
        uint256 newIndex = rejectedProposalCount++;
        rejectedProposals[newIndex] = proposal;
        rejectedProposals[newIndex].index = newIndex;
        delete pendingProposals[pendingIndex];
        emit ProposalStatusUpdated(newIndex, ProposalStatus.Rejected);
    }

    function pushRoutine(uint256 routineIndex) external nonReentrant {
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        Routine storage routine = activeRoutines[routineIndex];
        require(routine.active, "Routine not active");
        require(address(this).balance >= routine.value, "Insufficient ETH balance");
        require(block.timestamp >= routine.lastExecution + routine.interval, "Interval not elapsed");

        if (block.timestamp >= routine.runwayEnd) {
            removeRoutine(routineIndex);
            revert("Runway expired");
        }

        if (routine.value > 0 || routine.callData.length > 0) {
            (bool success, bytes memory returnData) = routine.target.call{value: routine.value}(routine.callData);
            require(success, "Execution failed");
            emit ExecutionResult(routineIndex, success, success, returnData);
        }
        routine.lastExecution = block.timestamp;
        emit RoutineExecuted(routineIndex, block.timestamp);
    }

    function removeRoutine(uint256 routineIndex) internal {
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        delete activeRoutines[routineIndex];
        emit RoutineExpired(routineIndex);
    }

    function queryProposals(uint256 index) external view returns (ProposalData memory) {
        Proposal memory proposal;
        if (index < proposalCount) {
            proposal = pendingProposals[index];
        } else if (index < passedProposalCount) {
            proposal = passedProposals[index];
        } else if (index < rejectedProposalCount) {
            proposal = rejectedProposals[index];
        } else {
            revert("Proposal does not exist");
        }

        uint256 finalizeTimeEnd = proposal.deadline - 604800 + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;

        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.deadline,
            finalizeTimeRemaining
        );
    }

    function queryRoutines(uint256 routineIndex) external view returns (RoutineData memory) {
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        Routine memory routine = activeRoutines[routineIndex];
        return RoutineData(
            routine.index,
            routine.detail,
            routine.target,
            routine.callData,
            routine.value,
            routine.proposer,
            routine.interval,
            routine.runwayEnd,
            routine.lastExecution,
            routine.active,
            routine.proposalIndex
        );
    }

    function getVoterTokens(uint256 proposalIndex, address voter) external view returns (uint256[] memory) {
        return voterTokens[proposalIndex][voter];
    }
}