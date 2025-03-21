// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

// v0.0.1
// RedMarkerDAO: DAO for approving/rejecting Dexhune Markets token listings

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/ReentrancyGuard.sol";

interface IDexhuneMarkets {
    function approveListing(uint256 listingIndex) external;
    function approveDelisting(uint256 delistingIndex) external;
}

contract RedMarkerDAO is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Core Parameters
    address public markets;
    uint256 public tVolume;
    uint256 public fees;
    address public stakingToken;
    uint256 public totalStake;
    uint256 public passedProposalsCount;
    uint256 public pendingProposalsCount;
    uint256 public rejectedProposalsCount;
    uint256 public totalStakers;
    uint256 public rebaseFactor; 
    uint256 public defaultDeadline = 24 * 60 * 60; // 24 hours in seconds

    // Structs
    struct StakerSlot {
        address stakerAddress;
        uint256 stakedAmount;
        uint256 dVolume;
        uint256 lastVote;
    }

    struct Proposal {
        uint256 requestIndex;
        uint256 votes;
        uint8 proposalType; // 0 = listing, 1 = delisting
        uint256 deadline;
    }

    // Public Storage
    mapping(address => StakerSlot) public stakers;
    mapping(address => bool) public isStaker;
    address[] public stakerList;
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    // Events
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event FeesClaimed(address indexed staker, uint256 amount);
    event ProposalCreated(uint256 indexed index, address indexed proposer, uint256 requestIndex, uint8 proposalType);
    event ProposalVoted(uint256 indexed index, address indexed voter, uint256 amount);
    event ProposalPassed(uint256 indexed index, uint256 requestIndex, uint8 proposalType);

    constructor() {
        markets = address(0);
        stakingToken = address(0);
    }

    // Owner Functions
    function setMarkets(address _markets) external onlyOwner {
        require(_markets != address(0), "Invalid markets address");
        markets = _markets;
    }

    function setStakingToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        stakingToken = _token;
    }

    // Write Functions
    function stakeToken(uint256 amount) external nonReentrant {
    require(stakingToken != address(0), "Staking token not set");
    rebaseFactor = totalStakers > 0 ? (totalStake / totalStakers < 1000e18 ? 1000e18 : totalStake / totalStakers) : 1000e18;
    require(amount >= rebaseFactor, "Amount below rebase factor");
    SafeERC20.safeTransferFrom(IERC20(stakingToken), msg.sender, address(this), amount);
    StakerSlot storage slot = stakers[msg.sender];
    if (!isStaker[msg.sender]) {
        slot.stakerAddress = msg.sender;
        slot.dVolume = tVolume;
        isStaker[msg.sender] = true;
        stakerList.push(msg.sender);
        totalStakers++;
    }
    slot.stakedAmount += amount;
    totalStake += amount;
    _rebase();
    _clearProposal();
    emit Staked(msg.sender, amount);
}

    function pullStake(uint256 amount) external nonReentrant {
        require(isStaker[msg.sender], "Not a staker");
        require(amount > 0 && amount <= stakers[msg.sender].stakedAmount, "Invalid amount");
        stakers[msg.sender].stakedAmount -= amount;
        totalStake -= amount;
        if (stakers[msg.sender].stakedAmount == 0) {
            for (uint256 i = 0; i < stakerList.length; i++) {
                if (stakerList[i] == msg.sender) {
                    stakerList[i] = stakerList[stakerList.length - 1];
                    stakerList.pop();
                    break;
                }
            }
            delete stakers[msg.sender];
            isStaker[msg.sender] = false;
            totalStakers--;
        }
        SafeERC20.safeTransfer(IERC20(stakingToken), msg.sender, amount);
        _rebase();
        _clearProposal();
        emit Unstaked(msg.sender, amount);
    }

    function claimFees() external nonReentrant {
        require(isStaker[msg.sender], "Not a staker");
        require(totalStake > 0, "No stake available");
        uint256 balance = IERC20(stakingToken).balanceOf(address(this));
        fees = balance > totalStake ? balance - totalStake : 0;
        if (fees == 0) return;

        StakerSlot storage slot = stakers[msg.sender];
        uint256 contributedVolume = slot.dVolume > 0 ? ((tVolume * 1e18 / slot.dVolume * 100) - (100 * 1e18)) : 0;
        uint256 stakeContribution = (slot.stakedAmount * 100 * 1e18) / totalStake;
        uint256 amount = (fees * stakeContribution * contributedVolume) / (100 * 1e18 * 100 * 1e18);
        if (amount > fees) amount = fees;
        if (amount > 0) {
            fees -= amount;
            slot.dVolume = tVolume;
            SafeERC20.safeTransfer(IERC20(stakingToken), msg.sender, amount);
            emit FeesClaimed(msg.sender, amount);
        }
    }

    function proposeAction(uint256 requestIndex, uint8 proposalType) external nonReentrant {
        require(stakingToken != address(0), "Staking token not set");
        require(markets != address(0), "Markets not set");
        require(stakers[msg.senderpotent].stakedAmount >= 1e18, "Insufficient stake");
        require(proposalType <= 1, "Invalid proposal type");
        uint256 index = proposalCount++;
        proposals[index] = Proposal({
            requestIndex: requestIndex,
            votes: 0,
            proposalType: proposalType,
            deadline: block.timestamp + defaultDeadline
        });
        pendingProposalsCount++;
        _clearProposal();
        emit ProposalCreated(index, msg.sender, requestIndex, proposalType);
    }

    function upvote(uint256 proposalIndex, uint256 voteAmount) external nonReentrant {
        require(proposalIndex < proposalCount, "Invalid proposal index");
        require(isStaker[msg.sender], "Not a staker");
        require(voteAmount > 0 && voteAmount <= stakers[msg.sender].stakedAmount, "Invalid vote amount");
        Proposal storage proposal = proposals[proposalIndex];
        require(proposal.deadline > block.timestamp, "Proposal expired");
        stakers[msg.sender].stakedAmount -= voteAmount;
        totalStake -= voteAmount;
        tVolume += voteAmount;
        proposal.votes += voteAmount;
        stakers[msg.sender].lastVote = proposalCount;
        if (proposal.votes > totalStake * 51 / 100) {
            IDexhuneMarkets marketsContract = IDexhuneMarkets(markets);
            if (proposal.proposalType == 0) {
                marketsContract.approveListing(proposal.requestIndex);
            } else {
                marketsContract.approveDelisting(proposal.requestIndex);
            }
            passedProposalsCount++;
            pendingProposalsCount--;
            emit ProposalPassed(proposalIndex, proposal.requestIndex, proposal.proposalType);
        }
        _clearProposal();
        emit ProposalVoted(proposalIndex, msg.sender, voteAmount);
    }

    // Read Functions
    function queryInactive(uint256 maxIterations) external view returns (address[] memory) {
        address[] memory inactive = new address[](maxIterations);
        uint256 found = 0;
        for (uint256 i = 0; i < stakerList.length && found < maxIterations; i++) {
            address staker = stakerList[i];
            if (isStaker[staker] && stakers[staker].lastVote + 5 < proposalCount) {
                inactive[found++] = staker;
            }
        }
        assembly { mstore(inactive, found) } // Resize array
        return inactive;
    }

    function queryStake(address staker) external view returns (StakerSlot memory) {
        return stakers[staker];
    }

    // Private Functions
    function _clearProposal() private {
        uint256 checked = 0;
        uint256 i = 0;
        while (checked < 5 && i < proposalCount) {
            Proposal storage proposal = proposals[i];
            if (proposal.deadline > 0 && block.timestamp >= proposal.deadline) {
                proposal.deadline = 0; // Mark as expired
                pendingProposalsCount--;
                rejectedProposalsCount++;
            }
            if (proposal.deadline > 0) checked++;
            i++;
        }
    }

    function _rebase() private {
        if (totalStakers == 0 || totalStake == 0) return;
        uint256 newBalance = totalStake / totalStakers;
        for (uint256 i = 0; i < stakerList.length; i++) {
            stakers[stakerList[i]].stakedAmount = newBalance;
        }
    }
}