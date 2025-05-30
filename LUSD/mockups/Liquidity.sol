// SPDX-License-Identifier: BSD-3-Clause
/// @title Mock liqudity contract

/*
*     __    __  _______ ____
*    / /   / / / / ___// __ \
*   / /   / / / /\__ \/ / / /
*  / /___/ /_/ /___/ / /_/ /
* /_____/\____//____/_____/
*/

pragma solidity ^0.8.28;

import "../Ownable.sol";
import "../interfaces/ILiquidity.sol";

contract Liquidity is ILiquidity, Ownable {
    uint256 public syncCount;
    
    function sync() external {
        syncCount++;
    }
}

