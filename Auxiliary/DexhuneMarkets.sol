// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// v0.0.5
// DexhuneMarkets: Added fullListingIndex mapping to track full listings by token address

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/IERC20Metadata.sol";
import "./imports/ReentrancyGuard.sol";

contract DexhuneMarkets is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Core Parameters
    address public feeToken;
    uint256 public listPrice;
    uint256 public totalListings;
    uint256 public defaultDeadline = 24 * 60 * 60; // 24 hours in seconds

    // Enums and Structs
    enum ListingStatus { Pending, Listed, Rejected } // 0, 1, 2

    struct Listing {
        address contractAddress;
        uint256 index;
        bytes32 ethscriptionHash;
        ListingStatus status;
        string tokenName;
        string ticker;
        string exceptions;
        uint256 deadline;
    }

    // Public Storage
    mapping(uint256 => Listing) public pendingListings;
    mapping(uint256 => Listing) public fullListings;
    mapping(uint256 => Listing) public rejectedListings;
    mapping(address => uint256) public fullListingIndex; // New mapping for token address to fullListings index
    uint256 public pendingListingCount; // Only increments
    uint256 public pendingDelistingCount; // Only increments
    mapping(address => bool) public isListed;
    mapping(address => bool) private hasPendingListing;
    mapping(address => bool) private hasPendingDelisting;

    // Events
    event ListingRequested(uint256 indexed index, address indexed requester, address contractAddress);
    event ListingApproved(uint256 indexed index, address contractAddress);
    event DelistingRequested(uint256 indexed index, address indexed requester, address contractAddress);
    event DelistingApproved(uint256 indexed index, address contractAddress);
    event FeeTokenSet(address indexed newFeeToken);
    event DeadlineSet(uint256 newDeadline);
    event ListingIndexUpdated(address indexed contractAddress, uint256 newIndex); // New event for frontend tracking

    constructor() {
        feeToken = address(0);
    }

    function setFeeToken(address _feeToken) external onlyOwner nonReentrant {
        require(_feeToken != address(0), "Invalid fee token address");
        feeToken = _feeToken;
        emit FeeTokenSet(_feeToken);
    }

    function setDeadline(uint256 _deadline) external onlyOwner nonReentrant {
        require(_deadline > 0, "Invalid deadline");
        defaultDeadline = _deadline;
        emit DeadlineSet(_deadline);
    }

    function requestListing(
        address contractAddress,
        bytes32 ethscriptionHash,
        string calldata exceptions
    ) external nonReentrant {
        require(feeToken != address(0), "Fee token not set");
        require(!isListed[contractAddress], "Token already listed");
        require(!hasPendingListing[contractAddress], "Pending request exists");
        listPrice = IERC20(feeToken).balanceOf(owner()) / (1000 + totalListings);
        if (listPrice > 0) {
            SafeERC20.safeTransferFrom(IERC20(feeToken), msg.sender, owner(), listPrice);
        }
        uint256 index = pendingListingCount++;
        pendingListings[index] = Listing({
            contractAddress: contractAddress,
            index: index,
            ethscriptionHash: ethscriptionHash,
            status: ListingStatus.Pending,
            tokenName: "",
            ticker: "",
            exceptions: exceptions,
            deadline: block.timestamp + defaultDeadline
        });
        hasPendingListing[contractAddress] = true;
        _clearRequest();
        emit ListingRequested(index, msg.sender, contractAddress);
    }

    function requestDelisting(uint256 delistingIndex) external nonReentrant {
        require(feeToken != address(0), "Fee token not set");
        Listing memory target = fullListings[delistingIndex];
        require(target.status == ListingStatus.Listed, "Token not listed");
        require(!hasPendingDelisting[target.contractAddress], "Pending delisting exists");
        listPrice = IERC20(feeToken).balanceOf(owner()) / (1000 + totalListings);
        if (listPrice > 0) {
            SafeERC20.safeTransferFrom(IERC20(feeToken), msg.sender, owner(), listPrice);
        }
        uint256 index = pendingDelistingCount++;
        pendingListings[index] = Listing({
            contractAddress: target.contractAddress,
            index: delistingIndex,
            ethscriptionHash: bytes32(0),
            status: ListingStatus.Pending,
            tokenName: "",
            ticker: "",
            exceptions: "",
            deadline: block.timestamp + defaultDeadline
        });
        hasPendingDelisting[target.contractAddress] = true;
        _clearRequest();
        emit DelistingRequested(index, msg.sender, target.contractAddress);
    }

    function approveListing(uint256 listingIndex) external onlyOwner nonReentrant {
        require(listingIndex < pendingListingCount, "Invalid index");
        Listing memory listing = pendingListings[listingIndex];
        require(listing.status == ListingStatus.Pending, "Not pending");
        try IERC20Metadata(listing.contractAddress).name() returns (string memory name) {
            listing.tokenName = name;
        } catch {}
        try IERC20Metadata(listing.contractAddress).symbol() returns (string memory symbol) {
            listing.ticker = symbol;
        } catch {}
        listing.status = ListingStatus.Listed;
        listing.deadline = 0;
        listing.index = totalListings; // Assign next available fullListings index
        fullListings[totalListings] = listing;
        fullListingIndex[listing.contractAddress] = totalListings; // Set index in new mapping
        isListed[listing.contractAddress] = true;
        hasPendingListing[listing.contractAddress] = false;
        delete pendingListings[listingIndex];
        totalListings++;
        emit ListingApproved(totalListings - 1, listing.contractAddress);
    }

    function approveDelisting(uint256 delistingIndex) external onlyOwner nonReentrant {
        require(delistingIndex < pendingDelistingCount, "Invalid index");
        Listing memory listing = pendingListings[delistingIndex];
        require(listing.status == ListingStatus.Pending, "Not pending");
        require(isListed[listing.contractAddress], "Token not listed");
        uint256 targetIndex = listing.index; // Index from fullListings
        listing.status = ListingStatus.Rejected;
        listing.deadline = 0;
        rejectedListings[targetIndex] = listing;
        isListed[listing.contractAddress] = false;
        hasPendingDelisting[listing.contractAddress] = false;
        delete pendingListings[delistingIndex];
        delete fullListingIndex[listing.contractAddress]; // Clear index for delisted token
        // Shift fullListings and update indices
        for (uint256 i = targetIndex; i < totalListings - 1; i++) {
            fullListings[i] = fullListings[i + 1];
            fullListings[i].index = i; // Update index in struct
            fullListingIndex[fullListings[i].contractAddress] = i; // Update index in mapping
            emit ListingIndexUpdated(fullListings[i].contractAddress, i); // Emit event for frontend
        }
        delete fullListings[totalListings - 1];
        totalListings--;
        emit DelistingApproved(targetIndex, listing.contractAddress);
    }

    function _clearRequest() private {
        uint256 checked = 0;
        uint256 i = 0;
        while (checked < 5 && i < pendingListingCount) {
            Listing storage listing = pendingListings[i];
            if (listing.status == ListingStatus.Pending && block.timestamp >= listing.deadline) {
                hasPendingListing[listing.contractAddress] = false;
                hasPendingDelisting[listing.contractAddress] = false;
                delete pendingListings[i];
            }
            if (listing.status == ListingStatus.Pending) {
                checked++;
            }
            i++;
        }
    }

    function queryByIndex(uint8 status, uint256 index) external view returns (Listing memory) {
        if (status == 0) {
            require(index < pendingListingCount, "Invalid pending index");
            return pendingListings[index];
        } else if (status == 1) {
            require(index < totalListings, "Invalid listed index");
            return fullListings[index];
        } else if (status == 2) {
            require(index < totalListings, "Invalid rejected index");
            return rejectedListings[index];
        } else {
            revert("Invalid status");
        }
    }

    // Frontend helper: Get listing by token address
    function getListingByToken(address token) external view returns (Listing memory) {
        require(isListed[token], "Token not listed");
        uint256 index = fullListingIndex[token];
        return fullListings[index];
    }

    // Frontend helper: Paginate full listings
    function getAllListings(uint256 start, uint256 count) external view returns (Listing[] memory) {
        require(start < totalListings, "Start index out of bounds");
        uint256 end = start + count > totalListings ? totalListings : start + count;
        Listing[] memory listings = new Listing[](end - start);
        for (uint256 i = start; i < end; i++) {
            listings[i - start] = fullListings[i];
        }
        return listings;
    }
}