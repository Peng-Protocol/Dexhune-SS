// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1 (new library)

import "./SS-LiquidityTemplate.sol";

contract SSLiquidityLibrary {
    function deploy(bytes32 salt) public returns (address) {
        address liquidityAddress = address(new SSLiquidityTemplate{salt: salt}());
        return liquidityAddress;
    }
} 