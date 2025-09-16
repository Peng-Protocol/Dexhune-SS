// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.1.0 
// Changes:
// - v0.1.0: bumped version.

import "./utils/CCLiquidityTemplate.sol";

contract CCLiquidityLogic {
    function deploy(bytes32 salt) external returns (address) {
        address liquidityAddress = address(new CCLiquidityTemplate{salt: salt}());
        return liquidityAddress;
    }
}