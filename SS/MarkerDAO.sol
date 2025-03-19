// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

// BSD 3-Clause License
// Copyright (c) 2025, Peng Protocol
// All rights reserved.

// v0.0.22

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/IERC721.sol";
import "./imports/IERC721Enumerable.sol";
import "./imports/SafeMath.sol";
import "./imports/ReentrancyGuard.sol";

contract MarkerDAO is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public nftCollection;
    address public fftToken;
    uint256 public turnoutThreshold = 333; // 33.3% scaled as 333/1000
    uint256 public approvalThreshold = 510; // 51% scaled as 510/1000
    uint256 public constant finalizeTimeLimit = 24 * 60 * 60; // 24 hours
    uint256 public constant MAX_VOTES_PER_CALL = 30;

    enum ProposalType { Regular, Routine, RoutineRemoval }
    enum ProposalStatus { Pending, Passed, Rejected }

    struct Proposal {
        uint256 index;
        string detail;
        address target;
        bytes callData;
        uint256 value;
        ProposalType proposalType;
        ProposalStatus status;
        address proposer;
        uint256 fftSpent;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 turnout;
        bool executed;
        uint256 deadline;
        uint256 createdAt;
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

    mapping(uint256 => Proposal) pendingProposals;
    mapping(uint256 => Proposal) passedProposals;
    mapping(uint256 => Proposal) rejectedProposals;
    uint256 public pendingProposalCount;
    uint256 public passedProposalCount;
    uint256 public rejectedProposalCount;

    mapping(uint256 => Routine) activeRoutines;
    mapping(uint256 => Routine) removedRoutines;
    uint256 public activeRoutineCount;
    uint256 public removedRoutineCount;

    mapping(uint256 => RoutineParams) routineParams;
    mapping(uint256 => mapping(uint256 => bool)) nftVoted;
    mapping(uint256 => mapping(address => uint256[])) voterTokens;

    event ProposalCreated(uint256 indexed index, address indexed proposer, string detail, address target, bytes callData, uint256 value, ProposalStatus status);
    event Voted(uint256 indexed index, address indexed voter, bool inFavor, uint256 nftTokenId, uint256 fftSpent);
    event ExecutionResult(uint256 indexed index, bool ethSuccess, bool callSuccess, bytes returnData);
    event ProposalStatusUpdated(uint256 indexed index, ProposalStatus newStatus);
    event RoutineCreated(uint256 indexed routineId, uint256 indexed proposalId, address target, bytes callData, uint256 value, uint256 interval, uint256 runwayEnd);
    event RoutineExecuted(uint256 indexed routineId, uint256 executionTime);

    constructor() {}

    receive() external payable {}

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

        uint256 fftFee = 1 * 10**18;
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = pendingProposalCount++;
        Proposal storage newProposal = pendingProposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.target = target;
        newProposal.callData = callData;
        newProposal.value = value;
        newProposal.proposalType = ProposalType.Regular;
        newProposal.status = ProposalStatus.Pending;
        newProposal.proposer = msg.sender;
        newProposal.fftSpent = fftFee;
        newProposal.deadline = block.timestamp + 604800;
        newProposal.createdAt = block.timestamp;

        emit ProposalCreated(index, msg.sender, detail, target, callData, value, ProposalStatus.Pending);
    }

    function proposeRoutine(
        address target, 
        bytes calldata callData, 
        uint256 value, 
        string calldata detail, 
        uint256 interval, 
        uint256 runwayDuration
    ) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");
        require(target != address(0), "Invalid target address");
        require(interval > 0, "Invalid interval");
        require(runwayDuration > 0, "Runway duration must be positive");

        uint256 fftFee = 1 * 10**18;
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = pendingProposalCount++;
        Proposal storage newProposal = pendingProposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.target = target;
        newProposal.callData = callData;
        newProposal.value = value;
        newProposal.proposalType = ProposalType.Routine;
        newProposal.status = ProposalStatus.Pending;
        newProposal.proposer = msg.sender;
        newProposal.fftSpent = fftFee;
        newProposal.deadline = block.timestamp + 604800;
        newProposal.createdAt = block.timestamp;

        routineParams[index] = RoutineParams(interval, runwayDuration);

        emit ProposalCreated(index, msg.sender, detail, target, callData, value, ProposalStatus.Pending);
    }

    function proposeRoutineRemoval(uint256 routineIndex, string calldata detail) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        require(activeRoutines[routineIndex].active, "Routine not active");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");

        uint256 fftFee = 1 * 10**18;
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = pendingProposalCount++;
        Proposal storage newProposal = pendingProposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.target = address(this);
        newProposal.callData = abi.encodeWithSignature("removeRoutine(uint256)", routineIndex);
        newProposal.value = 0;
        newProposal.proposalType = ProposalType.RoutineRemoval;
        newProposal.status = ProposalStatus.Pending;
        newProposal.proposer = msg.sender;
        newProposal.fftSpent = fftFee;
        newProposal.deadline = block.timestamp + 604800;
        newProposal.createdAt = block.timestamp;

        emit ProposalCreated(index, msg.sender, detail, newProposal.target, newProposal.callData, newProposal.value, ProposalStatus.Pending);
    }

    function voteProposal(uint8 proposalType, uint256 index, uint256 fftAmount, bool inFavor) external {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(uint8(proposal.proposalType) == proposalType, "Invalid proposal type");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");

        uint256 voterBalance = IERC721Enumerable(nftCollection).balanceOf(msg.sender);
        require(voterBalance > 0, "Not an NFT holder");
        require(fftAmount > 0, "Invalid FFT amount");

        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftAmount);

        uint256 votesCast = 0;
        uint256 maxIterations = voterBalance > MAX_VOTES_PER_CALL ? MAX_VOTES_PER_CALL : voterBalance;
        for (uint256 i = 0; i < maxIterations && votesCast < MAX_VOTES_PER_CALL; i++) {
            uint256 tokenId = IERC721Enumerable(nftCollection).tokenOfOwnerByIndex(msg.sender, i);
            if (!nftVoted[index][tokenId]) {
                nftVoted[index][tokenId] = true;
                voterTokens[index][msg.sender].push(tokenId);
                if (inFavor) {
                    proposal.votesFor = proposal.votesFor.add(1);
                } else {
                    proposal.votesAgainst = proposal.votesAgainst.add(1);
                }
                proposal.turnout = proposal.turnout.add(1);
                votesCast++;
                emit Voted(index, msg.sender, inFavor, tokenId, fftAmount / maxIterations);
            }
        }
        require(votesCast > 0, "No new votes cast");
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);
    }

    function updateProposalStatus(uint256 index) internal {
        Proposal storage proposal = pendingProposals[index];
        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();
        if (block.timestamp >= proposal.deadline && proposal.turnout < (currentSupply * turnoutThreshold) / 1000) {
            moveToRejected(index);
        }
    }

    function moveToPassed(uint256 pendingIndex) internal {
        Proposal memory proposal = pendingProposals[pendingIndex];
        proposal.status = ProposalStatus.Passed;
        uint256 newIndex = passedProposalCount++;
        passedProposals[newIndex] = proposal;
        passedProposals[newIndex].index = newIndex;

        shiftPendingProposals(pendingIndex);
        emit ProposalStatusUpdated(newIndex, ProposalStatus.Passed);
    }

    function moveToRejected(uint256 pendingIndex) internal {
        Proposal memory proposal = pendingProposals[pendingIndex];
        proposal.status = ProposalStatus.Rejected;
        uint256 newIndex = rejectedProposalCount++;
        rejectedProposals[newIndex] = proposal;
        rejectedProposals[newIndex].index = newIndex;

        shiftPendingProposals(pendingIndex);
        emit ProposalStatusUpdated(newIndex, ProposalStatus.Rejected);
    }

    function shiftPendingProposals(uint256 movedIndex) internal {
        for (uint256 i = movedIndex; i < pendingProposalCount - 1; i++) {
            pendingProposals[i] = pendingProposals[i + 1];
            pendingProposals[i].index = i;

            // Shift nftVoted
            for (uint256 j = 0; j < IERC721Enumerable(nftCollection).totalSupply(); j++) {
                nftVoted[i][j] = nftVoted[i + 1][j];
                nftVoted[i + 1][j] = false;
            }

            // Shift voterTokens (simplified, assumes voterTokens is manageable)
            for (uint256 j = 0; j < IERC721Enumerable(nftCollection).totalSupply(); j++) {
                address voter = IERC721Enumerable(nftCollection).ownerOf(j);
                voterTokens[i][voter] = voterTokens[i + 1][voter];
                delete voterTokens[i + 1][voter];
            }

            // Shift routineParams if applicable
            if (pendingProposals[i].proposalType == ProposalType.Routine) {
                routineParams[i] = routineParams[i + 1];
                delete routineParams[i + 1];
            }
        }
        delete pendingProposals[pendingProposalCount - 1];
        pendingProposalCount--;
    }

    function finalizeProposal(uint256 index) external nonReentrant {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.proposalType == ProposalType.Regular, "Use appropriate finalize function");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(block.timestamp >= proposal.createdAt + finalizeTimeLimit, "Time limit not elapsed");
        require(address(this).balance >= proposal.value, "Insufficient ETH balance");

        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();
        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                bool ethSuccess = true;
                bool callSuccess = true;
                bytes memory returnData = "";

                if (proposal.value > 0) {
                    (ethSuccess, ) = proposal.target.call{value: proposal.value}("");
                    require(ethSuccess, "ETH transfer failed");
                }

                if (proposal.callData.length > 0) {
                    (callSuccess, returnData) = proposal.target.call(proposal.callData);
                    require(callSuccess, "Calldata execution failed");
                }

                emit ExecutionResult(index, ethSuccess, callSuccess, returnData);

                uint256 newIndex = passedProposalCount++;
                passedProposals[newIndex] = proposal;
                passedProposals[newIndex].index = newIndex;
                passedProposals[newIndex].status = ProposalStatus.Passed;
                passedProposals[newIndex].executed = true;

                shiftPendingProposals(index);

                emit ProposalStatusUpdated(newIndex, ProposalStatus.Passed);
            } else {
                moveToRejected(index);
            }
        } else if (block.timestamp >= proposal.deadline) {
            moveToRejected(index);
        }
    }

    function finalizeRoutineProposal(uint256 index) external nonReentrant {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.proposalType == ProposalType.Routine, "Not a routine proposal");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(block.timestamp >= proposal.createdAt + finalizeTimeLimit, "Time limit not elapsed");

        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();
        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                uint256 newIndex = passedProposalCount++;
                passedProposals[newIndex] = proposal;
                passedProposals[newIndex].index = newIndex;
                passedProposals[newIndex].status = ProposalStatus.Passed;

                uint256 routineId = activeRoutineCount++;
                Routine storage routine = activeRoutines[routineId];
                routine.index = routineId;
                routine.detail = proposal.detail;
                routine.target = proposal.target;
                routine.callData = proposal.callData;
                routine.value = proposal.value;
                routine.proposer = proposal.proposer;
                routine.interval = routineParams[index].interval;
                routine.runwayEnd = block.timestamp + routineParams[index].runwayDuration;
                routine.active = true;
                routine.proposalIndex = newIndex;

                shiftPendingProposals(index);

                emit ProposalStatusUpdated(newIndex, ProposalStatus.Passed);
                emit RoutineCreated(routineId, newIndex, proposal.target, proposal.callData, proposal.value, routine.interval, routine.runwayEnd);
            } else {
                moveToRejected(index);
            }
        } else if (block.timestamp >= proposal.deadline) {
            moveToRejected(index);
        }
    }

    function finalizeRoutineRemovalProposal(uint256 index) external nonReentrant {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.proposalType == ProposalType.RoutineRemoval, "Not a routine removal proposal");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(block.timestamp >= proposal.createdAt + finalizeTimeLimit, "Time limit not elapsed");

        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();
        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                bool callSuccess = true;
                bytes memory returnData = "";

                if (proposal.callData.length > 0) {
                    (callSuccess, returnData) = proposal.target.call(proposal.callData);
                    require(callSuccess, "Calldata execution failed");
                }

                emit ExecutionResult(index, true, callSuccess, returnData);

                uint256 newIndex = passedProposalCount++;
                passedProposals[newIndex] = proposal;
                passedProposals[newIndex].index = newIndex;
                passedProposals[newIndex].status = ProposalStatus.Passed;
                passedProposals[newIndex].executed = true;

                shiftPendingProposals(index);

                emit ProposalStatusUpdated(newIndex, ProposalStatus.Passed);
            } else {
                moveToRejected(index);
            }
        } else if (block.timestamp >= proposal.deadline) {
            moveToRejected(index);
        }
    }

    function removeRoutine(uint256 routineIndex) internal {
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        Routine memory routine = activeRoutines[routineIndex];
        routine.active = false;
        uint256 newIndex = removedRoutineCount++;
        removedRoutines[newIndex] = routine;
        removedRoutines[newIndex].index = newIndex;
        delete activeRoutines[routineIndex];
    }

    function pushRoutine(uint256 routineIndex) external {
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        Routine storage routine = activeRoutines[routineIndex];
        require(routine.active, "Routine not active");
        require(address(this).balance >= routine.value, "Insufficient ETH balance");
        require(block.timestamp >= routine.lastExecution + routine.interval, "Interval not elapsed");
        require(block.timestamp < routine.runwayEnd, "Runway expired");

        bool ethSuccess = true;
        bool callSuccess = true;
        bytes memory returnData = "";

        if (routine.value > 0) {
            (ethSuccess, ) = routine.target.call{value: routine.value}("");
            require(ethSuccess, "ETH transfer failed");
        }

        if (routine.callData.length > 0) {
            (callSuccess, returnData) = routine.target.call(routine.callData);
            require(callSuccess, "Calldata execution failed");
        }

        emit ExecutionResult(routineIndex, ethSuccess, callSuccess, returnData);

        routine.lastExecution = block.timestamp;

        emit RoutineExecuted(routineIndex, block.timestamp);
    }

    function queryProposal(uint256 index) external view returns (
        uint8 proposalType,
        uint8 status,
        uint256 proposalIndex,
        string memory detail,
        address target,
        bytes memory callData,
        uint256 value,
        address proposer,
        uint256 fftSpent,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 turnout,
        bool executed,
        uint256 deadline,
        uint256 deadlineRemaining,
        uint256 finalizeTimeRemaining,
        uint256 createdAt
    ) {
        Proposal memory proposal;
        if (index < pendingProposalCount) {
            proposal = pendingProposals[index];
        } else if (index < passedProposalCount) {
            proposal = passedProposals[index];
        } else if (index < rejectedProposalCount) {
            proposal = rejectedProposals[index];
        } else {
            revert("Proposal does not exist");
        }

        uint256 deadlineRem = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRem = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;

        return (
            uint8(proposal.proposalType) + 1, // 1=Regular, 2=Routine, 3=RoutineRemoval
            uint8(proposal.status) + 1,       // 1=Pending, 2=Passed, 3=Rejected
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRem,
            finalizeTimeRem,
            proposal.createdAt
        );
    }

    function queryRoutine(uint256 index) external view returns (
        uint8 status,
        uint256 routineIndex,
        string memory detail,
        address target,
        bytes memory callData,
        uint256 value,
        address proposer,
        uint256 interval,
        uint256 runwayEnd,
        uint256 lastExecution,
        bool active,
        uint256 proposalIndex
    ) {
        Routine memory routine;
        if (index < activeRoutineCount) {
            routine = activeRoutines[index];
            return (
                0, // Active
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
        } else if (index < removedRoutineCount) {
            routine = removedRoutines[index];
            return (
                1, // Removed
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
        } else {
            revert("Routine does not exist");
        }
    }

    function getVoterTokens(uint256 proposalIndex, address voter) external view returns (uint256[] memory) {
        return voterTokens[proposalIndex][voter];
    }

    // Events for external use
    event NFTCollectionSet(address indexed newCollection);
    event FFTTokenSet(address indexed newToken);
}