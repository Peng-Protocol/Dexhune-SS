// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.1.0
// Changes:
// - v0.1.0: converted "CC" to "MFP". 

import "./utils/MFPListingTemplate.sol";

contract MFPListingLogic {
    function deploy(bytes32 salt) external returns (address) {
        address listingAddress = address(new MFPListingTemplate{salt: salt}());
        return listingAddress;
    }
}