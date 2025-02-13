// SPDX-License-Identifier: BSD-3-Clause
/// @title Dexhune ERC20 Root Implementation

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Ownable.sol";
import "./interfaces/AggregatorInterface.sol";

contract LUSD is ERC20, Ownable {
    address public tokenZero;
    address public taxCollector;
    address public liquidityAddress;
    address public oracleAddress;

    AggregatorInterface public aggregator;

    uint256 private constant INITIAL_SUPPLY = 4_000_000_000e18;
    uint256 private constant FEE_PERC = 500; // 0.5 fee * 10k

    constructor() ERC20("Link Dollar", "LUSD") {
        _mint(_owner, INITIAL_SUPPLY);
    }

    function initialize(
        address liquidityAddr,
        address oracleAddr,
        address tokenZeroAddr,
        address taxAddr
    ) external onlyOwner {
        require(liquidityAddress == address(0));
        require(tokenZero == address(0));
        require(taxCollector == address(0));

        liquidityAddress = liquidityAddr;
        tokenZero = tokenZeroAddr;
        taxCollector = taxAddr;
        oracleAddress = oracleAddr;
        aggregator = AggregatorInterface(oracleAddress);
        rebase();
    }

    function getBalances()
        external
        view
        returns (uint256 balanceZero, uint256 balanceOne)
    {
        balanceZero = IERC20(tokenZero).balanceOf(liquidityAddress);
        balanceOne = balanceOf(liquidityAddress);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);

        rebase();

        uint256 transferAmount = value;
        uint256 fee = (value * FEE_PERC) / 10_000;
        (uint256 amount, bool negative) = _absDiff(value, fee);

        if (!negative && fee > 0) {
            transferAmount = amount;
            _transfer(from, taxCollector, fee);
        }

        _transfer(from, to, transferAmount);
        rebase();
        return true;
    }

    function _absDiff(
        uint256 v1,
        uint256 v2
    ) private pure returns (uint256 diff, bool negative) {
        if (v2 > v1) {
            uint256 tmp = v1;
            v1 = v2;
            v2 = tmp;
            negative = true;
        }

        diff = v1 - v2;
    }

    function getPrice() public view returns (int256) {
        return aggregator.latestAnswer();
    }

    function rebase() public {
        uint256 price = uint256(getPrice());
        uint256 balanceZero = balanceOf(address(liquidityAddress));
        uint256 balanceOne = balanceOf(address(this));

        uint256 lastRebase = balanceZero * price;

        (uint256 rebaseFactor, bool negative) = _absDiff(
            lastRebase,
            balanceOne
        );

        if (!negative) {
            _mint(liquidityAddress, rebaseFactor);
        } else {
            _burn(liquidityAddress, rebaseFactor);
        }
    }
}
