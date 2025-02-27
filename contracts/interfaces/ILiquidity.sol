// SPDX-License-Identifier: BSD-3-Clause
/// @title Basic liqudity interface
// Sources:
// https://docs.uniswap.org/contracts/v2/reference/smart-contracts/common-errors

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */
 
 pragma solidity ^0.8.28;

 interface ILiquidity {
    function sync() external;
 }