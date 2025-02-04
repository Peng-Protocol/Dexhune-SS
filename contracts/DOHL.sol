// SPDX-License-Identifier: BSD-3-Clause
/// @title Dexhune ERC20 Root Implementation

/*
 *    ||_ __  __
 *   (|| |  \/  \|__||
 *   _||)|__/\__/|  ||__
 *    ||
 */

pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Ownable.sol";
import "./interfaces/AggregatorInterface.sol";

contract DOHL is ERC20, Ownable {
    uint256 public price;
    uint256 public lastRebase;
    address public lp;
    address public tokenZero;

    AggregatorInterface public aggregator;

    uint256 private constant INITIAL_SUPPLY = 4e18;

    constructor() ERC20("Link Dollar", "DOHL") {
        _mint(_owner, INITIAL_SUPPLY);
    }

    function initialize(
        address lpAddr,
        address aggregatorAddr,
        address tokenZeroAddr 
    ) external onlyOwner {
        require(lp == address(0));
        require(tokenZero == address(0));

        lp = lpAddr;
        tokenZero = tokenZeroAddr;
        aggregator = AggregatorInterface(aggregatorAddr);

        _mint(lp, 1e18);
    }

    function getBalances() external view returns(uint256 balanceZero, uint256 balanceOne) {
        balanceZero = IERC20(tokenZero).balanceOf(lp);
        balanceOne = balanceOf(lp);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();

        // _spendAllowance(from, spender, value);
        // _transfer(from, to, value);
        return true;
    }

    function _absDiff(uint256 v1, uint256 v2) private returns(uint256 diff, bool negative) {
        if (v2 > v1) {
            uint256 tmp = v1;
            v1 = v2;
            v2 = tmp;
            negative = true;
        }

        diff = v1 - v2;
    }

    function _rebase() private {
        uint256 balanceOne = balanceOf(address(this));
        
        (uint256 diff, bool negative) = _absDiff(lastRebase, balanceOne);

        if (!negative) {

        } else {

        }
    }
}
