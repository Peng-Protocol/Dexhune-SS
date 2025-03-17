// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

// BSD 3-Clause License
// Copyright (c) 2025, Peng Protocol
// All rights reserved.

// Imports from OpenZeppelin
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/math/SafeMath.sol";

contract MarkerDAO is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Core Parameters
    address nftCollection; // Address of the NFT collection
    address fftToken;     // Address of the FFT token
    uint256 turnoutThreshold = 333; // 33.3% scaled as 333/1000
    uint256 approvalThreshold = 510; // 51% scaled as 510/1000
    uint256 finalizeTimeLimit = 24 * 3600; // Default to 24 hours (in seconds)

    // Proposal and Routine structs with separate type and status
    enum ProposalType { Regular, Routine, RoutineRemoval }
    enum ProposalStatus { Pending, Rejected, Passed }

    struct Proposal {
        uint256 index;
        string detail;
        bytes transactionData;
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
        bytes transactionData;
        address proposer;
        uint256 interval;
        uint256 runwayEnd;
        uint256 lastExecution;
        bool active;
    }

    struct RoutineParams {
        uint256 interval;
        uint256 runwayEnd;
    }

    // Storage
    mapping(uint256 => Proposal) proposals;
    uint256 proposalCount;
    mapping(uint256 => Routine) routines;
    uint256 routineCount;
    mapping(uint256 => RoutineParams) routineParams; // Temporary storage for routine params
    mapping(uint256 => mapping(uint256 => bool)) nftVoted; // proposalId => tokenId => hasVoted
    mapping(uint256 => mapping(address => uint256[])) voterTokens; // proposalId => voter => tokenIds

    // Events
    event ProposalCreated(uint256 indexed index, address indexed proposer, string detail, bytes transactionData, ProposalStatus status);
    event Voted(uint256 indexed index, address indexed voter, bool inFavor, uint256 nftTokenId, uint256 fftSpent);
    event ProposalExecuted(uint256 indexed index);
    event ProposalStatusUpdated(uint256 indexed index, ProposalStatus newStatus);
    event RoutineCreated(uint256 indexed routineId, uint256 indexed proposalId, bytes transactionData, uint256 interval, uint256 runwayEnd);
    event RoutineExecuted(uint256 indexed routineId, uint256 executionTime);
    event RoutineExpired(uint256 indexed routineId);
    event NFTCollectionSet(address indexed newCollection);
    event FFTTokenSet(address indexed newToken);
    event FinalizeTimeLimitSet(uint256 newLimit);

    // Constructor
    constructor() {
        // Initialize owner via Ownable
    }

    // Helper to fetch decimals with fallback
    function tryDecimals(IERC20Metadata token) internal view returns (uint8) {
        try token.decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18; // Fallback to 18 decimals
        }
    }

    // Setter for finalizeTimeLimit (owner-only)
    function setFinalizeTimeLimit(uint256 newLimit) external onlyOwner {
        require(newLimit > 0, "Invalid time limit");
        finalizeTimeLimit = newLimit;
        emit FinalizeTimeLimitSet(newLimit);
    }

    // Initialization Functions
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

    // Core Proposal Functions
    function propose(bytes calldata transactionData, string calldata detail) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");
        require(transactionData.length > 0, "Empty transaction data");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken)));
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = proposalCount++;
        Proposal storage newProposal = proposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.transactionData = transactionData;
        newProposal.proposalType = ProposalType.Regular;
        newProposal.status = ProposalStatus.Pending;
        newProposal.proposer = msg.sender;
        newProposal.fftSpent = fftFee;
        newProposal.deadline = block.timestamp + 604800; // 1 week
        newProposal.createdAt = block.timestamp;

        emit ProposalCreated(index, msg.sender, detail, transactionData, ProposalStatus.Pending);
    }

    function upvoteProposal(uint256 index, uint256 fftAmount, uint256 tokenId) external {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.proposalType == ProposalType.Regular || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
        require(proposal.status != ProposalStatus.Rejected, "Proposal rejected");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");

        require(IERC721(nftCollection).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!nftVoted[index][tokenId], "Token already voted");

        require(fftAmount > 0, "Invalid FFT amount");
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftAmount);

        nftVoted[index][tokenId] = true;
        voterTokens[index][msg.sender].push(tokenId);
        proposal.votesFor = proposal.votesFor.add(1);
        proposal.turnout = proposal.turnout.add(1);
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);

        emit Voted(index, msg.sender, true, tokenId, fftAmount);
    }

    function downvoteProposal(uint256 index, uint256 fftAmount, uint256 tokenId) external {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.proposalType == ProposalType.Regular || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
        require(proposal.status != ProposalStatus.Rejected, "Proposal rejected");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");

        require(IERC721(nftCollection).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!nftVoted[index][tokenId], "Token already voted");

        require(fftAmount > 0, "Invalid FFT amount");
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftAmount);

        nftVoted[index][tokenId] = true;
        voterTokens[index][msg.sender].push(tokenId);
        proposal.votesAgainst = proposal.votesAgainst.add(1);
        proposal.turnout = proposal.turnout.add(1);
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);

        emit Voted(index, msg.sender, false, tokenId, fftAmount);
    }

    function updateProposalStatus(uint256 index) internal {
        Proposal storage proposal = proposals[index];
        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();
        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                proposal.status = ProposalStatus.Passed;
                emit ProposalStatusUpdated(index, ProposalStatus.Passed);
            } else if (block.timestamp >= proposal.deadline) {
                proposal.status = ProposalStatus.Rejected;
                emit ProposalStatusUpdated(index, ProposalStatus.Rejected);
            }
        } else if (block.timestamp >= proposal.deadline) {
            proposal.status = ProposalStatus.Rejected;
            emit ProposalStatusUpdated(index, ProposalStatus.Rejected);
        }
    }

    function finalizeProposal(uint256 index) external {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(block.timestamp >= proposal.createdAt + finalizeTimeLimit, "Time limit not elapsed");

        if (proposal.turnout >= (IERC721Enumerable(nftCollection).totalSupply() * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                proposal.status = ProposalStatus.Passed;
                emit ProposalStatusUpdated(index, ProposalStatus.Passed);

                (bool success, ) = address(this).call(proposal.transactionData);
                require(success, "Transaction execution failed");
                proposal.executed = true;
                emit ProposalExecuted(index);

                if (proposal.proposalType == ProposalType.Routine) {
                    uint256 routineId = routineCount++;
                    Routine storage routine = routines[routineId];
                    routine.index = index;
                    routine.detail = proposal.detail;
                    routine.transactionData = proposal.transactionData;
                    routine.proposer = proposal.proposer;
                    routine.interval = routineParams[index].interval;
                    routine.runwayEnd = routineParams[index].runwayEnd;
                    routine.active = true;
                    emit RoutineCreated(routineId, index, proposal.transactionData, routine.interval, routine.runwayEnd);
                }
            } else {
                proposal.status = ProposalStatus.Rejected;
                emit ProposalStatusUpdated(index, ProposalStatus.Rejected);
            }
        } else if (block.timestamp >= proposal.deadline) {
            proposal.status = ProposalStatus.Rejected;
            emit ProposalStatusUpdated(index, ProposalStatus.Rejected);
        }
    }

    // Routine Proposal Functions
    function proposeRoutine(bytes calldata transactionData, string calldata detail, uint256 interval, uint256 runway) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");
        require(transactionData.length > 0, "Empty transaction data");
        require(interval > 0, "Invalid interval");
        require(runway > block.timestamp, "Runway must be in the future");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken)));
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = proposalCount++;
        Proposal storage newProposal = proposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.transactionData = transactionData;
        newProposal.proposalType = ProposalType.Routine;
        newProposal.status = ProposalStatus.Pending;
        newProposal.proposer = msg.sender;
        newProposal.fftSpent = fftFee;
        newProposal.deadline = block.timestamp + 604800;
        newProposal.createdAt = block.timestamp;

        routineParams[index] = RoutineParams(interval, runway);

        emit ProposalCreated(index, msg.sender, detail, transactionData, ProposalStatus.Pending);
    }

    function upvoteRoutineProposal(uint256 index, uint256 fftAmount, uint256 tokenId) external {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.proposalType == ProposalType.Routine || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
        require(proposal.status != ProposalStatus.Rejected, "Proposal rejected");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");

        require(IERC721(nftCollection).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!nftVoted[index][tokenId], "Token already voted");

        require(fftAmount > 0, "Invalid FFT amount");
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftAmount);

        nftVoted[index][tokenId] = true;
        voterTokens[index][msg.sender].push(tokenId);
        proposal.votesFor = proposal.votesFor.add(1);
        proposal.turnout = proposal.turnout.add(1);
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);

        emit Voted(index, msg.sender, true, tokenId, fftAmount);
    }

    function downvoteRoutineProposal(uint256 index, uint256 fftAmount, uint256 tokenId) external {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.proposalType == ProposalType.Routine || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
        require(proposal.status != ProposalStatus.Rejected, "Proposal rejected");
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");

        require(IERC721(nftCollection).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!nftVoted[index][tokenId], "Token already voted");

        require(fftAmount > 0, "Invalid FFT amount");
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftAmount);

        nftVoted[index][tokenId] = true;
        voterTokens[index][msg.sender].push(tokenId);
        proposal.votesAgainst = proposal.votesAgainst.add(1);
        proposal.turnout = proposal.turnout.add(1);
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);

        emit Voted(index, msg.sender, false, tokenId, fftAmount);
    }

    function proposeRoutineRemoval(uint256 routineIndex, string calldata detail) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(routineIndex < routineCount, "Routine does not exist");
        Routine storage routine = routines[routineIndex];
        require(routine.active, "Routine not active");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken)));
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = proposalCount++;
        Proposal storage newProposal = proposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.transactionData = abi.encodeWithSignature("removeRoutine(uint256)", routineIndex);
        newProposal.proposalType = ProposalType.RoutineRemoval;
        newProposal.status = ProposalStatus.Pending;
        newProposal.proposer = msg.sender;
        newProposal.fftSpent = fftFee;
        newProposal.deadline = block.timestamp + 604800;
        newProposal.createdAt = block.timestamp;

        emit ProposalCreated(index, msg.sender, detail, newProposal.transactionData, ProposalStatus.Pending);
    }

    function removeRoutine(uint256 routineIndex) internal {
        require(routineIndex < routineCount, "Routine does not exist");
        Routine storage routine = routines[routineIndex];
        require(routine.active, "Routine not active");
        routine.active = false;
        emit RoutineExpired(routineIndex);
    }

    function pushRoutine(uint256 routineIndex) external {
        require(routineIndex < routineCount, "Routine does not exist");
        Routine storage routine = routines[routineIndex];
        require(routine.active, "Routine not active");

        if (block.timestamp >= routine.runwayEnd) {
            routine.active = false;
            emit RoutineExpired(routineIndex);
            revert("Runway expired");
        }

        require(block.timestamp >= routine.lastExecution + routine.interval, "Interval not elapsed");

        (bool success, ) = address(this).call(routine.transactionData);
        require(success, "Transaction execution failed");

        routine.lastExecution = block.timestamp;

        emit RoutineExecuted(routineIndex, block.timestamp);
    }

    // Query Functions for Proposals
    function queryActiveProposalByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, ProposalType, ProposalStatus, address, uint256, uint256, uint256, bool, uint256, uint256, uint256
    ) {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.status == ProposalStatus.Pending, "Proposal not active");
        return (
            proposal.index,
            proposal.detail,
            proposal.transactionData,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            proposal.createdAt
        );
    }

    function queryRejectedProposalByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, ProposalType, ProposalStatus, address, uint256, uint256, uint256, bool, uint256, uint256, uint256
    ) {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.status == ProposalStatus.Rejected, "Proposal not rejected");
        return (
            proposal.index,
            proposal.detail,
            proposal.transactionData,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            proposal.createdAt
        );
    }

    function queryPassedProposalByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, ProposalType, ProposalStatus, address, uint256, uint256, uint256, bool, uint256, uint256, uint256
    ) {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.status == ProposalStatus.Passed, "Proposal not passed");
        return (
            proposal.index,
            proposal.detail,
            proposal.transactionData,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            proposal.createdAt
        );
    }

    function queryProposalByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, ProposalType, ProposalStatus, address, uint256, uint256, uint256, bool, uint256, uint256, uint256
    ) {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        return (
            proposal.index,
            proposal.detail,
            proposal.transactionData,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            proposal.createdAt
        );
    }

    function queryLatestProposal() external view returns (
        uint256, string memory, bytes memory, ProposalType, ProposalStatus, address, uint256, uint256, uint256, bool, uint256, uint256, uint256
    ) {
        require(proposalCount > 0, "No proposals exist");
        Proposal storage proposal = proposals[proposalCount - 1];
        return (
            proposal.index,
            proposal.detail,
            proposal.transactionData,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            proposal.createdAt
        );
    }

    // Query Functions for Routines
    function queryActiveRoutineByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, address, uint256, uint256, uint256, bool
    ) {
        require(index < routineCount, "Routine does not exist");
        Routine storage routine = routines[index];
        require(routine.active && block.timestamp < routine.runwayEnd, "Routine not active");
        return (
            routine.index,
            routine.detail,
            routine.transactionData,
            routine.proposer,
            routine.interval,
            routine.runwayEnd,
            routine.lastExecution,
            routine.active
        );
    }

    function queryRejectedRoutineByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, ProposalType, ProposalStatus, address, uint256, uint256, uint256, bool, uint256, uint256, uint256
    ) {
        require(index < proposalCount, "Proposal does not exist");
        Proposal storage proposal = proposals[index];
        require(proposal.proposalType == ProposalType.Routine, "Not a routine proposal");
        require(proposal.status == ProposalStatus.Rejected, "Routine not rejected");
        return (
            proposal.index,
            proposal.detail,
            proposal.transactionData,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            proposal.createdAt
        );
    }

    function queryPassedRoutineByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, address, uint256, uint256, uint256, bool
    ) {
        require(index < routineCount, "Routine does not exist");
        Routine storage routine = routines[index];
        return (
            routine.index,
            routine.detail,
            routine.transactionData,
            routine.proposer,
            routine.interval,
            routine.runwayEnd,
            routine.lastExecution,
            routine.active
        );
    }

    function queryRemovedRoutineByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, address, uint256, uint256, uint256, bool
    ) {
        require(index < routineCount, "Routine does not exist");
        Routine storage routine = routines[index];
        require(!routine.active, "Routine not removed");
        return (
            routine.index,
            routine.detail,
            routine.transactionData,
            routine.proposer,
            routine.interval,
            routine.runwayEnd,
            routine.lastExecution,
            routine.active
        );
    }

    function queryRoutineByIndex(uint256 index) external view returns (
        uint256, string memory, bytes memory, address, uint256, uint256, uint256, bool
    ) {
        require(index < routineCount, "Routine does not exist");
        Routine storage routine = routines[index];
        return (
            routine.index,
            routine.detail,
            routine.transactionData,
            routine.proposer,
            routine.interval,
            routine.runwayEnd,
            routine.lastExecution,
            routine.active
        );
    }

    function queryLatestRoutine() external view returns (
        uint256, string memory, bytes memory, address, uint256, uint256, uint256, bool
    ) {
        require(routineCount > 0, "No routines exist");
        Routine storage routine = routines[routineCount - 1];
        return (
            routine.index,
            routine.detail,
            routine.transactionData,
            routine.proposer,
            routine.interval,
            routine.runwayEnd,
            routine.lastExecution,
            routine.active
        );
    }
}