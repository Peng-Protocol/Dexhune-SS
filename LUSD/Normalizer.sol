// SPDX-License-Identifier: BSD-3-Clause
/// @title Base Decimal Normalizer based on work by Paul Razvan Berg
// Sources: https://github.com/PaulRBerg/prb-contracts/blob/main/src/token/erc20/ERC20Normalizer.sol

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.28;

abstract contract Normalizer {
    mapping(uint8 => uint256) private _scalars;

    function _normalize(
        uint256 amount,
        uint8 decimals
    ) internal returns (uint256) {
        if (decimals == 18) {
            return amount;
        }

        uint256 scalar = _computeScalar(decimals);
        return scalar == 1 ? amount : amount * _computeScalar(decimals);
    }

    function _denormalize(
        uint256 amount,
        uint8 decimals
    ) internal returns (uint256) {
        if (decimals == 18) {
            return amount;
        }

        uint256 scalar = _computeScalar(decimals);
        return scalar == 1 ? amount : amount / _computeScalar(decimals);
    }

    function _computeScalar(uint8 decimals) internal returns (uint256 scalar) {
        if (decimals > 18) {
            revert DecimalsGreaterThan18(decimals);
        }

        scalar = _scalars[decimals];

        if (scalar == 0) {
            unchecked {
                _scalars[decimals] = scalar = 10 ** (18 - decimals);
            }
        }
    }

    error DecimalsGreaterThan18(uint256 decimals);
}
