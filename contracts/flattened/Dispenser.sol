// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.22 ^0.8.28;

// src/Normalizer.sol

/// @title Base Decimal Normalizer based on work by Paul Razvan Berg
// Sources: https://github.com/PaulRBerg/prb-contracts/blob/main/src/token/erc20/ERC20Normalizer.sol

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

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

// src/Ownable.sol

/// @title Owner Base Class
/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

contract Ownable is IOwnable {
    address internal _owner;

    event OwnershipRenounced(address indexed previousOwner);

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(isOwner());
        _;
    }

    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(_owner);
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// src/interfaces/IAggregator.sol

/// @title IAggregator

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

interface IAggregator {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (int256);

    function latestTimestamp() external view returns (uint256);

    function latestRound() external view returns (uint256);

    function getAnswer(uint256 roundId) external view returns (int256);

    function getTimestamp(uint256 roundId) external view returns (uint256);

    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );
    event NewRound(
        uint256 indexed roundId,
        address indexed startedBy,
        uint256 startedAt
    );
}

// src/interfaces/IERC20.sol

/// @title Standard Interface for ERC20 tokens
// Sources:
// https://eips.ethereum.org/EIPS/eip-20
// https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

interface ERC20Interface {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @dev OPTIONAL Returns the name of the token
     */
    function name() external view returns (string memory);

    /**
     * @dev OPTIONAL Returns the symbol of the token
     */
    function symbol() external view returns (string memory);

    /**
     * @dev OPTIONAL Returns the amount of decimals supported by the token
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

// src/libraries/PengMath.sol

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

library PengMath {
    /// @dev The unit number, which the decimal precision of the fixed-point types.
    uint256 constant UNIT = 1e18;

    /// @dev The the largest power of two that divides the decimal value of `UNIT`. The logarithm of this value is the least significant
    /// bit in the binary representation of `UNIT`.
    uint256 constant UNIT_LPOTD = 262144;

    /// @dev The unit number inverted mod 2^256.
    uint256 constant UNIT_INVERSE =
        78156646155174841979727994598816262306175212592076161876661_508869554232690281;

    error MulDiv18Overflow(uint256 x, uint256 y);
    error MulDivOverflow(uint256 x, uint256 y, uint256 denominator);

    function mul(uint256 x, uint256 y) internal pure returns (uint256 result) {
        return _mulDiv18(x, y);
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256 result) {
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
    function _mulDiv18(
        uint256 x,
        uint256 y
    ) private pure returns (uint256 result) {
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
            result := mul(
                or(
                    div(sub(prod0, remainder), UNIT_LPOTD),
                    mul(
                        sub(prod1, gt(remainder, prod0)),
                        add(div(sub(0, UNIT_LPOTD), UNIT_LPOTD), 1)
                    )
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
    function _mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) private pure returns (uint256 result) {
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

// src/interfaces/ILUSD.sol

/// @title Basic interface for LUSD

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

interface ILUSD is ERC20Interface {
    function oracle() external view returns (address);
    function tokenZero() external view returns (address);
    function liquidity() external view returns (address);
}

// src/Dispenser.sol

/// @title LUSD Dispenser

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

contract LUSDDispenser is Normalizer, Ownable {
    ILUSD public lusd;

    function setLUSD(address addr) external onlyOwner {
        lusd = ILUSD(addr);
    }

    function getTokenZeroDec() private view returns (uint8) {
        uint8 decimals;
        ERC20Interface tokenZero = ERC20Interface(lusd.tokenZero());

        try tokenZero.decimals() returns (uint8 dec) {
            decimals = dec;
        } catch {
            decimals = 18;
        }

        return decimals;
    }

    function _queryPrice() private returns (uint256) {
        uint8 decimals;
        IAggregator oracle = IAggregator(lusd.oracle());

        try oracle.decimals() returns (uint8 dec) {
            decimals = dec;
        } catch {
            decimals = 18;
        }

        uint256 price = uint256(oracle.latestAnswer());

        return _normalize(price, decimals);
    }

    function convert(uint256 amount) external {
        if (amount <= 0) {
            revert RejectedZeroAmount();
        }

        ERC20Interface tokenZero = ERC20Interface(lusd.tokenZero());
        tokenZero.transferFrom(msg.sender, lusd.liquidity(), amount);

        uint256 nprice = _queryPrice();
        uint256 namount = _normalize(amount, getTokenZeroDec());
        uint256 ndohlAmount = PengMath.mul(namount, nprice);

        uint256 dohlAmount = _denormalize(ndohlAmount, lusd.decimals());

        if (dohlAmount > lusd.balanceOf(address(this))) {
            revert InsufficientBalance();
        }

        lusd.transfer(msg.sender, dohlAmount);
    }

    error RejectedZeroAmount();
    error InsufficientBalance();
}
