// SPDX-License-Identifier: BSD-3-Clause
/// @title Basic interface for LUSD

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.28;
import "./IERC20.sol";

interface ILUSD is ERC20Interface {
    function oracle() external view returns (address);
    function tokenZero() external view returns (address);
    function liquidity() external view returns (address);
}
