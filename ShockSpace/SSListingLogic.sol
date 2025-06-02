// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.2 (Updated)
// Changes:
// - v0.0.2: Added note to remove taxCollector functionality from SS-ListingTemplate.sol.
// - v0.0.1: Converted library to regular contract SSListingLogic.

// Note: Remove taxCollector functionality from SS-ListingTemplate.sol.

import "./utils/SSListingTemplate.sol";

contract SSListingLogic {
    function deploy(bytes32 salt) external returns (address) {
        address listingAddress = address(new SSListingTemplate{salt: salt}());
        return listingAddress;
    }
}