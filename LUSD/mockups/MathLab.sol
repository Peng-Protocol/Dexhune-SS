// SPDX-License-Identifier: BSD-3-Clause
/// @title Simple math sim

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.28;
import "../Normalizer.sol";
import "../libraries/PengMath.sol";

contract MathLab is Normalizer {
    function simulateDist(
        uint256 balance,
        uint256 supply,
        uint8 dec
    ) external returns (uint256) {
        uint256 nftSupply = supply;
        uint8 tokenDec = dec;

        uint256 toShare = balance / nftSupply;
        return toShare;
    }
}
