// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

// BSD 3-Clause License
// Copyright (c) 2025, Peng Protocol
// All rights reserved.

// v0.0.18

// Local OpenZeppelin Imports 
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
    address public nftCollection;         // Address of the NFT collection
    address public fftToken;             // Address of the FFT token
    uint256 public turnoutThreshold = 333; // 33.3% scaled as 333/1000
    uint256 public approvalThreshold = 510; // 51% scaled as 510/1000
    uint256 public finalizeTimeLimit = 24 * 60 * 60; // 24 hours (in seconds) for finalization
    uint256 public constant MAX_VOTES_PER_CALL = 30; // Limit NFTs processed per call

    // Proposal and Routine enums and structs
    enum ProposalType { Regular, Routine, RoutineRemoval }
    enum ProposalStatus { Pending, Rejected, Passed }

    struct Proposal {
        uint256 index;            // Index within its specific mapping
        string detail;
        address target;           // Target contract or address to call
        bytes callData;           // Encoded function call data
        uint256 value;            // ETH value to send with the call
        ProposalType proposalType;
        ProposalStatus status;    // Retained for clarity
        address proposer;
        uint256 fftSpent;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 turnout;
        bool executed;
        uint256 deadline;         // Absolute end timestamp (1 week)
        uint256 createdAt;
    }

    struct Routine {
        uint256 index;            // Index within its specific mapping
        string detail;
        address target;           // Target contract or address to call
        bytes callData;           // Encoded function call data
        uint256 value;            // ETH value to send with the call
        address proposer;
        uint256 interval;
        uint256 runwayEnd;
        uint256 lastExecution;
        bool active;
        uint256 proposalIndex;    // Links to passedProposals
    }

    struct RoutineParams {
        uint256 interval;
        uint256 runwayEnd;
    }

    // New memory structs for querying
    struct ProposalData {
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
        uint256 deadline;              // Absolute end timestamp
        uint256 deadlineRemaining;     // Seconds until deadline
        uint256 finalizeTimeRemaining; // Seconds until finalization eligibility
        uint256 createdAt;
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

    // Storage: Separate mappings for each status
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

    mapping(uint256 => RoutineParams) routineParams; // Uses pending proposal index
    mapping(uint256 => mapping(uint256 => bool)) nftVoted; // pendingProposalId => tokenId => hasVoted
    mapping(uint256 => mapping(address => uint256[])) voterTokens; // pendingProposalId => voter => tokenIds

    // Events
    event ProposalCreated(uint256 indexed index, address indexed proposer, string detail, address target, bytes callData, uint256 value, ProposalStatus status);
    event Voted(uint256 indexed index, address indexed voter, bool inFavor, uint256 nftTokenId, uint256 fftSpent);
    event ProposalExecuted(uint256 indexed index);
    event ExecutionResult(uint256 indexed index, bool ethSuccess, bool callSuccess, bytes returnData); // New event for debugging
    event ProposalStatusUpdated(uint256 indexed index, ProposalStatus newStatus);
    event RoutineCreated(uint256 indexed routineId, uint256 indexed proposalId, address target, bytes callData, uint256 value, uint256 interval, uint256 runwayEnd);
    event RoutineExecuted(uint256 indexed routineId, uint256 executionTime);
    event RoutineExpired(uint256 indexed routineId);
    event NFTCollectionSet(address indexed newCollection);
    event FFTTokenSet(address indexed newToken);
    event FinalizeTimeLimitSet(uint256 newLimit);

    // Constructor
    constructor() {
        // Initialize owner via Ownable
    }

    // Allow MarkerDAO to receive ETH
    receive() external payable {}

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

    // Helper function to check FFT allowance and guide approval
    function checkFFTApproval(uint256 amount) external view returns (uint256) {
        uint256 allowance = IERC20(fftToken).allowance(msg.sender, address(this));
        if (allowance < amount) {
            revert(string(abi.encodePacked(
                "Insufficient FFT allowance. Approve at least ",
                uintToString(amount),
                " FFT tokens to MarkerDAO (",
                addressToString(address(this)),
                ") via the FFT token contract."
            )));
        }
        return allowance;
    }

    // Utility to convert uint to string for approval guidance
    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Utility to convert address to string for approval guidance
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(uint160(_addr) >> (152 - i * 8)) & 0xf];
            str[3 + i * 2] = alphabet[uint8(uint160(_addr) >> (152 - i * 8 - 4)) & 0xf];
        }
        return string(str);
    }

    // Core Proposal Functions
    function propose(address target, bytes calldata callData, uint256 value, string calldata detail) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");
        require(target != address(0), "Invalid target address");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken))); // Fixed 1 FFT with dynamic decimals
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
        newProposal.deadline = block.timestamp + 604800; // 1 week
        newProposal.createdAt = block.timestamp;

        emit ProposalCreated(index, msg.sender, detail, target, callData, value, ProposalStatus.Pending);
    }

    function upvoteProposal(uint256 index, uint256 fftAmount) external {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.proposalType == ProposalType.Regular || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
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
                proposal.votesFor = proposal.votesFor.add(1);
                proposal.turnout = proposal.turnout.add(1);
                votesCast++;
                emit Voted(index, msg.sender, true, tokenId, fftAmount / maxIterations); // Approximate FFT per vote
            }
        }
        require(votesCast > 0, "No new votes cast");
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);
    }

    function downvoteProposal(uint256 index, uint256 fftAmount) external {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.proposalType == ProposalType.Regular || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
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
                proposal.votesAgainst = proposal.votesAgainst.add(1);
                proposal.turnout = proposal.turnout.add(1);
                votesCast++;
                emit Voted(index, msg.sender, false, tokenId, fftAmount / maxIterations); // Approximate FFT per vote
            }
        }
        require(votesCast > 0, "No new votes cast");
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);
    }

    function updateProposalStatus(uint256 index) internal {
        Proposal storage proposal = pendingProposals[index];
        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();
        // Only reject if deadline passed and turnout insufficient
        if (block.timestamp >= proposal.deadline && proposal.turnout < (currentSupply * turnoutThreshold) / 1000) {
            moveToRejected(index);
        }
        // No automatic passing here; moved to finalizeProposal
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

    function finalizeProposal(uint256 index) external nonReentrant {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.status == ProposalStatus.Pending, "Proposal not pending");
        require(block.timestamp >= proposal.createdAt + finalizeTimeLimit, "Time limit not elapsed");
        require(address(this).balance >= proposal.value, "Insufficient ETH balance");

        uint256 currentSupply = IERC721Enumerable(nftCollection).totalSupply();
        if (proposal.turnout >= (currentSupply * turnoutThreshold) / 1000) {
            uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
            if (totalVotes > 0 && (proposal.votesFor * 1000) / totalVotes >= approvalThreshold) {
                // Step 1: Execute ETH transfer and calldata first
                bool ethSuccess = true;
                bool callSuccess = true;
                bytes memory returnData = "";

                // Send ETH to target (0 is valid)
                if (proposal.value > 0) {
                    (ethSuccess, ) = proposal.target.call{value: proposal.value}("");
                    require(ethSuccess, "ETH transfer failed");
                }

                // Execute calldata if provided
                if (proposal.callData.length > 0) {
                    (callSuccess, returnData) = proposal.target.call(proposal.callData);
                    require(callSuccess, "Calldata execution failed");
                }

                // Emit execution details for debugging
                emit ExecutionResult(index, ethSuccess, callSuccess, returnData);

                // Step 2: Update state after successful execution
                uint256 newIndex = passedProposalCount++;
                passedProposals[newIndex] = proposal;
                passedProposals[newIndex].index = newIndex;
                passedProposals[newIndex].status = ProposalStatus.Passed;
                passedProposals[newIndex].executed = true;
                delete pendingProposals[index];

                emit ProposalStatusUpdated(newIndex, ProposalStatus.Passed);
                emit ProposalExecuted(newIndex);

                // Handle routine creation
                if (proposal.proposalType == ProposalType.Routine) {
                    uint256 routineId = activeRoutineCount++;
                    Routine storage routine = activeRoutines[routineId];
                    routine.index = routineId;
                    routine.detail = proposal.detail;
                    routine.target = proposal.target;
                    routine.callData = proposal.callData;
                    routine.value = proposal.value;
                    routine.proposer = proposal.proposer;
                    routine.interval = routineParams[index].interval;
                    routine.runwayEnd = routineParams[index].runwayEnd;
                    routine.active = true;
                    routine.proposalIndex = newIndex;
                    emit RoutineCreated(routineId, newIndex, proposal.target, proposal.callData, proposal.value, routine.interval, routine.runwayEnd);
                }
            } else {
                moveToRejected(index);
            }
        } else if (block.timestamp >= proposal.deadline) {
            moveToRejected(index);
        }
    }

    // Routine Proposal Functions
    function proposeRoutine(address target, bytes calldata callData, uint256 value, string calldata detail, uint256 interval, uint256 runway) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");
        require(target != address(0), "Invalid target address");
        require(interval > 0, "Invalid interval");
        require(runway > block.timestamp, "Runway must be in the future");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken))); // Fixed 1 FFT with dynamic decimals
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

        routineParams[index] = RoutineParams(interval, runway);

        emit ProposalCreated(index, msg.sender, detail, target, callData, value, ProposalStatus.Pending);
    }

    function upvoteRoutineProposal(uint256 index, uint256 fftAmount) external {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.proposalType == ProposalType.Routine || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
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
                proposal.votesFor = proposal.votesFor.add(1);
                proposal.turnout = proposal.turnout.add(1);
                votesCast++;
                emit Voted(index, msg.sender, true, tokenId, fftAmount / maxIterations); // Approximate FFT per vote
            }
        }
        require(votesCast > 0, "No new votes cast");
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);
    }

    function downvoteRoutineProposal(uint256 index, uint256 fftAmount) external {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        require(proposal.proposalType == ProposalType.Routine || proposal.proposalType == ProposalType.RoutineRemoval, "Invalid proposal type");
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
                proposal.votesAgainst = proposal.votesAgainst.add(1);
                proposal.turnout = proposal.turnout.add(1);
                votesCast++;
                emit Voted(index, msg.sender, false, tokenId, fftAmount / maxIterations); // Approximate FFT per vote
            }
        }
        require(votesCast > 0, "No new votes cast");
        proposal.fftSpent = proposal.fftSpent.add(fftAmount);

        updateProposalStatus(index);
    }

    function proposeRoutineRemoval(uint256 routineIndex, string calldata detail) external {
        require(IERC721(nftCollection).balanceOf(msg.sender) > 0, "Not an NFT holder");
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        Routine storage routine = activeRoutines[routineIndex];
        require(routine.active, "Routine not active");
        require(bytes(detail).length <= 500, "Detail exceeds 500 characters");

        uint256 fftFee = 1 * (10 ** tryDecimals(IERC20Metadata(fftToken))); // Fixed 1 FFT with dynamic decimals
        SafeERC20.safeTransferFrom(IERC20(fftToken), msg.sender, address(this), fftFee);

        uint256 index = pendingProposalCount++;
        Proposal storage newProposal = pendingProposals[index];
        newProposal.index = index;
        newProposal.detail = detail;
        newProposal.target = address(this); // Call MarkerDAO's removeRoutine
        newProposal.callData = abi.encodeWithSignature("removeRoutine(uint256)", routineIndex);
        newProposal.value = 0; // No ETH needed for removal
        newProposal.proposalType = ProposalType.RoutineRemoval;
        newProposal.status = ProposalStatus.Pending;
        newProposal.proposer = msg.sender;
        newProposal.fftSpent = fftFee;
        newProposal.deadline = block.timestamp + 604800;
        newProposal.createdAt = block.timestamp;

        emit ProposalCreated(index, msg.sender, detail, newProposal.target, newProposal.callData, newProposal.value, ProposalStatus.Pending);
    }

    function removeRoutine(uint256 routineIndex) internal {
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        Routine memory routine = activeRoutines[routineIndex];
        routine.active = false;
        uint256 newIndex = removedRoutineCount++;
        removedRoutines[newIndex] = routine;
        removedRoutines[newIndex].index = newIndex;
        delete activeRoutines[routineIndex];
        emit RoutineExpired(newIndex);
    }

    function pushRoutine(uint256 routineIndex) external {
        require(routineIndex < activeRoutineCount, "Routine does not exist");
        Routine storage routine = activeRoutines[routineIndex];
        require(routine.active, "Routine not active");
        require(address(this).balance >= routine.value, "Insufficient ETH balance");
        require(block.timestamp >= routine.lastExecution + routine.interval, "Interval not elapsed");

        if (block.timestamp >= routine.runwayEnd) {
            removeRoutine(routineIndex);
            revert("Runway expired");
        }

        // Step 1: Execute ETH transfer and calldata first
        bool ethSuccess = true;
        bool callSuccess = true;
        bytes memory returnData = "";

        // Send ETH to target (0 is valid)
        if (routine.value > 0) {
            (ethSuccess, ) = routine.target.call{value: routine.value}("");
            require(ethSuccess, "ETH transfer failed");
        }

        // Execute calldata if provided
        if (routine.callData.length > 0) {
            (callSuccess, returnData) = routine.target.call(routine.callData);
            require(callSuccess, "Calldata execution failed");
        }

        // Emit execution details for debugging
        emit ExecutionResult(routineIndex, ethSuccess, callSuccess, returnData);

        // Step 2: Update state after successful execution
        routine.lastExecution = block.timestamp;

        emit RoutineExecuted(routineIndex, block.timestamp);
    }

    // Query Functions for Proposals
    function queryActiveProposalByIndex(uint256 index) external view returns (ProposalData memory) {
        require(index < pendingProposalCount, "Proposal does not exist");
        Proposal storage proposal = pendingProposals[index];
        uint256 deadlineRemaining = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;
        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRemaining,
            finalizeTimeRemaining,
            proposal.createdAt
        );
    }

    function queryRejectedProposalByIndex(uint256 index) external view returns (ProposalData memory) {
        require(index < rejectedProposalCount, "Proposal does not exist");
        Proposal storage proposal = rejectedProposals[index];
        uint256 deadlineRemaining = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;
        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRemaining,
            finalizeTimeRemaining,
            proposal.createdAt
        );
    }

    function queryPassedProposalByIndex(uint256 index) external view returns (ProposalData memory) {
        require(index < passedProposalCount, "Proposal does not exist");
        Proposal storage proposal = passedProposals[index];
        uint256 deadlineRemaining = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;
        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRemaining,
            finalizeTimeRemaining,
            proposal.createdAt
        );
    }

    function queryLatestPendingProposal() external view returns (ProposalData memory) {
        require(pendingProposalCount > 0, "No pending proposals exist");
        Proposal storage proposal = pendingProposals[pendingProposalCount - 1];
        uint256 deadlineRemaining = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;
        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRemaining,
            finalizeTimeRemaining,
            proposal.createdAt
        );
    }

    function queryLatestPassedProposal() external view returns (ProposalData memory) {
        require(passedProposalCount > 0, "No passed proposals exist");
        Proposal storage proposal = passedProposals[passedProposalCount - 1];
        uint256 deadlineRemaining = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;
        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRemaining,
            finalizeTimeRemaining,
            proposal.createdAt
        );
    }

    function queryLatestRejectedProposal() external view returns (ProposalData memory) {
        require(rejectedProposalCount > 0, "No rejected proposals exist");
        Proposal storage proposal = rejectedProposals[rejectedProposalCount - 1];
        uint256 deadlineRemaining = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;
        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRemaining,
            finalizeTimeRemaining,
            proposal.createdAt
        );
    }

    // Query Functions for Routines
    function queryActiveRoutineByIndex(uint256 index) external view returns (RoutineData memory) {
        require(index < activeRoutineCount, "Routine does not exist");
        Routine storage routine = activeRoutines[index];
        require(routine.active && block.timestamp < routine.runwayEnd, "Routine not active");
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

    function queryRejectedRoutineByIndex(uint256 index) external view returns (ProposalData memory) {
        require(index < rejectedProposalCount, "Proposal does not exist");
        Proposal storage proposal = rejectedProposals[index];
        require(proposal.proposalType == ProposalType.Routine, "Not a routine proposal");
        uint256 deadlineRemaining = (block.timestamp >= proposal.deadline) ? 0 : proposal.deadline - block.timestamp;
        uint256 finalizeTimeEnd = proposal.createdAt + finalizeTimeLimit;
        uint256 finalizeTimeRemaining = (block.timestamp >= finalizeTimeEnd) ? 0 : finalizeTimeEnd - block.timestamp;
        return ProposalData(
            proposal.index,
            proposal.detail,
            proposal.target,
            proposal.callData,
            proposal.value,
            proposal.proposalType,
            proposal.status,
            proposal.proposer,
            proposal.fftSpent,
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.turnout,
            proposal.executed,
            proposal.deadline,
            deadlineRemaining,
            finalizeTimeRemaining,
            proposal.createdAt
        );
    }

    function queryPassedRoutineByIndex(uint256 index) external view returns (RoutineData memory) {
        require(index < activeRoutineCount, "Routine does not exist");
        Routine storage routine = activeRoutines[index];
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

    function queryRemovedRoutineByIndex(uint256 index) external view returns (RoutineData memory) {
        require(index < removedRoutineCount, "Routine does not exist");
        Routine storage routine = removedRoutines[index];
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

    function queryLatestActiveRoutine() external view returns (RoutineData memory) {
        require(activeRoutineCount > 0, "No active routines exist");
        Routine storage routine = activeRoutines[activeRoutineCount - 1];
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

    function queryLatestRemovedRoutine() external view returns (RoutineData memory) {
        require(removedRoutineCount > 0, "No removed routines exist");
        Routine storage routine = removedRoutines[removedRoutineCount - 1];
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

    // Helper function to query voted NFTs for a proposal by voter
    function getVoterTokens(uint256 proposalIndex, address voter) external view returns (uint256[] memory) {
        return voterTokens[proposalIndex][voter];
    }
}