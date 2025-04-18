// SPDX-License-Identifier: BSD-3-Clause
/// @title Direct port of mulDiv functions from PRBMath by Paul Razvan Berg
// Sources: 
// https://2π.com/21/muldiv/
// https://github.com/PaulRBerg/prb-math/tree/main/src/ud60x18
/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.22;

library PengMath { 
    /// @dev The unit number, which the decimal precision of the fixed-point types.
    uint256 constant UNIT = 1e18;

    /// @dev The the largest power of two that divides the decimal value of `UNIT`. The logarithm of this value is the least significant
    /// bit in the binary representation of `UNIT`.
    uint256 constant UNIT_LPOTD = 262144;

    /// @dev The unit number inverted mod 2^256.
    uint256 constant UNIT_INVERSE = 78156646155174841979727994598816262306175212592076161876661_508869554232690281;

    error MulDiv18Overflow(uint256 x, uint256 y);
    error MulDivOverflow(uint256 x, uint256 y, uint256 denominator);

    function mul(uint256 x, uint256 y) internal pure returns(uint256 result) {
        return _mulDiv18(x, y);
    }

    function div(uint256 x, uint256 y) internal pure returns(uint256 result) {
        return _mulDiv(x, UNIT, y);
    }

    /// @notice Calculates x*y÷1e18 with 512-bit precision.
    ///
    /// @dev A variant of {mulDiv} with constant folding, i.e. in which the denominator is hard coded to 1e18.
    ///
    /// Notes:
    /// - The body is purposely left uncommented; to understand how this works, see the documentation in {mulDiv}.
    /// - The result is rounded toward zero.
    /// - We take as an axiom that the result cannot be `MAX_UINT256` when x and y solve the following system of equations:
    ///
    /// $$
    /// \begin{cases}
    ///     x * y = MAX\_UINT256 * UNIT \\
    ///     (x * y) \% UNIT \geq \frac{UNIT}{2}
    /// \end{cases}
    /// $$
    ///
    /// Requirements:
    /// - Refer to the requirements in {mulDiv}.
    /// - The result must fit in uint256.
    ///
    /// @param x The multiplicand as an unsigned 60.18-decimal fixed-point number.
    /// @param y The multiplier as an unsigned 60.18-decimal fixed-point number.
    /// @return result The result as an unsigned 60.18-decimal fixed-point number.
    /// @custom:smtchecker abstract-function-nondet
    function _mulDiv18(uint256 x, uint256 y) private pure returns (uint256 result) {
        uint256 prod0;
        uint256 prod1;
        assembly ("memory-safe") {
            let mm := mulmod(x, y, not(0))
            prod0 := mul(x, y)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            unchecked {
                return prod0 / UNIT;
            }
        }

        if (prod1 >= UNIT) {
            revert MulDiv18Overflow(x, y);
        }

        uint256 remainder;
        assembly ("memory-safe") {
            remainder := mulmod(x, y, UNIT)
            result :=
                mul(
                    or(
                        div(sub(prod0, remainder), UNIT_LPOTD),
                        mul(sub(prod1, gt(remainder, prod0)), add(div(sub(0, UNIT_LPOTD), UNIT_LPOTD), 1))
                    ),
                    UNIT_INVERSE
                )
        }
    }

    /// @notice Calculates x*y÷denominator with 512-bit precision.
    ///
    /// @dev Credits to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv.
    ///
    /// Notes:
    /// - The result is rounded toward zero.
    ///
    /// Requirements:
    /// - The denominator must not be zero.
    /// - The result must fit in uint256.
    ///
    /// @param x The multiplicand as a uint256.
    /// @param y The multiplier as a uint256.
    /// @param denominator The divisor as a uint256.
    /// @return result The result as a uint256.
    /// @custom:smtchecker abstract-function-nondet
    function _mulDiv(uint256 x, uint256 y, uint256 denominator) private pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
        // use the Chinese Remainder Theorem to reconstruct the 512-bit result. The result is stored in two 256
        // variables such that product = prod1 * 2^256 + prod0.
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly ("memory-safe") {
            let mm := mulmod(x, y, not(0))
            prod0 := mul(x, y)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division.
        if (prod1 == 0) {
            unchecked {
                return prod0 / denominator;
            }
        }

        // Make sure the result is less than 2^256. Also prevents denominator == 0.
        if (prod1 >= denominator) {
            revert MulDivOverflow(x, y, denominator);
        }

        ////////////////////////////////////////////////////////////////////////////
        // 512 by 256 division
        ////////////////////////////////////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0].
        uint256 remainder;
        assembly ("memory-safe") {
            // Compute remainder using the mulmod Yul instruction.
            remainder := mulmod(x, y, denominator)

            // Subtract 256 bit number from 512-bit number.
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        unchecked {
            // Calculate the largest power of two divisor of the denominator using the unary operator ~. This operation cannot overflow
            // because the denominator cannot be zero at this point in the function execution. The result is always >= 1.
            // For more detail, see https://cs.stackexchange.com/q/138556/92363.
            uint256 lpotdod = denominator & (~denominator + 1);
            uint256 flippedLpotdod;

            assembly ("memory-safe") {
                // Factor powers of two out of denominator.
                denominator := div(denominator, lpotdod)

                // Divide [prod1 prod0] by lpotdod.
                prod0 := div(prod0, lpotdod)

                // Get the flipped value `2^256 / lpotdod`. If the `lpotdod` is zero, the flipped value is one.
                // `sub(0, lpotdod)` produces the two's complement version of `lpotdod`, which is equivalent to flipping all the bits.
                // However, `div` interprets this value as an unsigned value: https://ethereum.stackexchange.com/q/147168/24693
                flippedLpotdod := add(div(sub(0, lpotdod), lpotdod), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * flippedLpotdod;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
        }
    }
}
