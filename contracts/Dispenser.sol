// SPDX-License-Identifier: BSD-3-Clause
/// @title LUSD Dispenser

pragma solidity ^0.8.28;
import "./Ownable.sol";
import "./Normalizer.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IAggregator.sol";
import "./interfaces/ILUSD.sol";
import "./interfaces/ILiquidity.sol";
import "./libraries/PengMath.sol";

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
        address liquidityAddress = address(lusd.liquidity()); // Fetch liquidity address

        tokenZero.transferFrom(msg.sender, liquidityAddress, amount);

        uint256 nprice = _queryPrice();
        uint256 namount = _normalize(amount, getTokenZeroDec());
        uint256 ndohlAmount = PengMath.mul(namount, nprice);

        uint256 dohlAmount = _denormalize(ndohlAmount, lusd.decimals());

        if (dohlAmount > lusd.balanceOf(address(this))) {
            revert InsufficientBalance();
        }

        lusd.transfer(msg.sender, dohlAmount);

        // Ensure liquidity contract is valid before calling sync()
        if (liquidityAddress != address(0)) {
            try ILiquidity(liquidityAddress).sync() {} catch {}
        }
    }

    error RejectedZeroAmount();
    error InsufficientBalance();
}
