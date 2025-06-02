/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-06-02: Updated _transferMarginToListing to call ISSListing.update for volume balances (xBalance for long, yBalance for short) and _transferLiquidityFee to call addFees for fee tracking (xFees for long, yFees for short). Added positionType parameter. Version incremented to 0.0.10 for pre-testing.
// - 2025-06-01: Extracted liquidity limit check and loan/liquidation price calculation in prepEnterLong to _checkLiquidityLimitLong and _computeLoanAndLiquidationLong to prevent stack too deep. Applied similar extraction in prepCloseLong/prepCloseShort to _deductMarginAndRemoveToken and _executePayoutUpdate. Version incremented to 0.0.9 for pre-testing.
// - 2025-06-01: Extracted liquidity limit check and loan/liquidation price calculation in prepEnterShort to _checkLiquidityLimitShort and _computeLoanAndLiquidationShort to resolve stack too deep error. Version incremented to 0.0.8 for pre-testing.
// - 2025-06-01: Added liquidityAddr validation in _transferLiquidityFee, extracted payout logic in prepCloseLong/prepCloseShort to _computePayoutLong/_computePayoutShort to prevent stack too deep in downstream calls. Version incremented to 0.0.7 for pre-testing.
// - 2025-06-01: Split liquidity fee transfer into _transferLiquidityFee helper, removed liquidityAddr from _transferMarginToListing, consolidated margin transfers. Version incremented to 0.0.6 for pre-testing.
// - 2025-05-31: Fixed stack too deep in prepEnterShort by extracting margin transfer logic to internal function _transferMarginToListing. Version incremented to 0.0.5 for pre-testing.
// - 2025-05-30: Updated prepEnterLong to use xLiquid and prepEnterShort to use yLiquid from liquidityDetailsView.
// - 2025-05-30: Version incremented to 0.0.4 for pre-testing.
// - 2025-05-29: Added margin deduction in prepCloseLong/prepCloseShort.
// - 2025-05-29: Version incremented to 0.0.2 for pre-testing.
// - 2025-05-29: Updated prepEnterLong/prepEnterShort to transfer taxedMargin and excessMargin to listingAddress, track in makerTokenMargin.
// - 2025-05-29: Updated liquidation price to use makerTokenMargin[maker][token].
// - 2025-05-29: Replaced entryPrice with minEntryPrice/maxEntryPrice.
// - 2025-05-29: Updated fee to (leverage - 1) * initialMargin / 100.
// - 2025-05-29: Updated closeLongPosition/closeShortPosition to create PayoutUpdate without margin deduction.

pragma solidity 0.8.1;

import "./CSDUtilityPartial.sol";

contract CSDPositionPartial is CSDUtilityPartial {
    struct PrepPosition {
        uint256 fee;
        uint256 taxedMargin;
        uint256 leverageAmount;
        uint256 initialLoan;
        uint256 liquidationPrice;
    }

    function computeFee(uint256 initialMargin, uint8 leverage) internal pure returns (uint256) {
        uint256 feePercent = uint256(leverage) - 1;
        return (initialMargin * feePercent * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION;
    }

    function _transferLiquidityFee(
        address listingAddress,
        address token,
        uint256 fee,
        uint8 positionType
    ) internal {
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView(listingAddress);
        require(liquidityAddr != address(0), "Invalid liquidity address");
        if (fee > 0) {
            transferMargin(liquidityAddr, token, fee);
            ISSLiquidityTemplate(liquidityAddr).addFees(address(this), positionType == 0 ? true : false, fee);
        }
    }

    // Fee switching is carried out by SSLiquidityTemplate using claimFees, no need to switch fees here
    function _transferMarginToListing(
        address token,
        address listingAddress,
        address maker,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint8 positionType
    ) internal {
        uint256 totalMargin = taxedMargin + excessMargin;
        _transferLiquidityFee(listingAddress, token, fee, positionType);
        if (totalMargin > 0) {
            transferMargin(listingAddress, token, totalMargin);
            ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1);
            updates[0] = ISSListing.UpdateType({
                updateType: 0,
                index: positionType,
                value: totalMargin,
                addr: address(0),
                recipient: address(0)
            });
            ISSListing(listingAddress).update(address(this), updates);
        }
        makerTokenMargin[maker][token] += totalMargin;
        if (makerTokenMargin[maker][token] == totalMargin) {
            makerMarginTokens[maker].push(token);
        }
    }

    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB
    ) internal view returns (uint256) {
        MarginParams1 storage margin1 = marginParams1[positionId];
        MarginParams2 storage margin2 = margin2[positionId];
        PriceParams1 storage price1 = priceParams1[positionId];
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        return (margin1.taxedMargin + makerTokenMargin[positionCore1[positionId].makerAddress][tokenB] + price1.leverage * margin1.initialMargin) / currentPrice - margin2.initialLoan;
    }

    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA
    ) internal view returns (uint256) {
        MarginParams1 storage margin1 = marginParams1[positionId];
        PriceParams1 storage price1 = priceParams1[positionId];
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        return (price1.minEntryPrice - currentPrice) * margin1.initialMargin * price1.leverage + (margin1.taxedMargin + makerTokenMargin[positionCore1[positionId].makerAddress][tokenA]) * currentPrice;
    }

    function _checkLiquidityLimitLong(
        address listingAddress,
        uint256 leverageAmount,
        uint8 leverage
    ) internal view returns (address tokenB) {
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView(listingAddress);
        (uint256 xLiquid,,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView();
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = xLiquid * limitPercent / 100;
        require(leverageAmount <= limit, "Leverage amount exceeds limit");
        return ISSListing(listingAddress).tokenB();
    }

    function _computeLoanAndLiquidationLong(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenB
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount / minPrice;
        uint256 marginRatio = makerTokenMargin[maker][tokenB] / leverageAmount;
        liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;
    }

    function _checkLiquidityLimitShort(
        address listingAddress,
        uint256 leverageAmount,
        uint8 leverage
    ) internal view returns (address tokenA) {
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView(listingAddress);
        (, uint256 yLiquid,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView();
        uint256 limitPercent = 101 - uint256(leverage);
        uint256 limit = yLiquid * limitPercent / 100;
        require(leverageAmount <= limit, "Leverage amount exceeds limit");
        return ISSListing(listingAddress).tokenA();
    }

    function _computeLoanAndLiquidationShort(
        uint256 leverageAmount,
        uint256 minPrice,
        address maker,
        address tokenA
    ) internal view returns (uint256 initialLoan, uint256 liquidationPrice) {
        initialLoan = leverageAmount * minPrice;
        uint256 marginRatio = makerTokenMargin[maker][tokenA] / leverageAmount;
        liquidationPrice = minPrice + marginRatio;
    }

    function _deductMarginAndRemoveToken(
        address maker,
        address token,
        uint256 taxedMargin,
        uint256 excessMargin
    ) internal {
        makerTokenMargin[maker][token] -= (taxedMargin + excessMargin);
        if (makerTokenMargin[maker][token] == 0) {
            _removeToken(maker, token);
        }
    }

    function _executePayoutUpdate(
        uint256 positionId,
        address listingAddress,
        uint256 payout,
        uint8 positionType,
        address maker
    ) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: positionType,
            recipient: maker,
            required: payout
        });
        ISSListing(listingAddress).ssUpdate(address(this), updates);

        exitParams[positionId].exitPrice = ISSListing(listingAddress).prices(listingAddress);
        positionCore2[positionId].status2 = 1;
    }

    function prepEnterLong(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        address listingAddress,
        address maker
    ) internal returns (PrepPosition memory prep) {
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice,) = parseEntryPrice(minEntryPrice, maxEntryPrice, listingAddress);

        prep.fee = computeFee(initialMargin, leverage);
        prep.taxedMargin = initialMargin - prep.fee;
        prep.leverageAmount = initialMargin * uint256(leverage);
        require(excessMargin <= prep.leverageAmount, "Excess margin too high");

        address tokenB = _checkLiquidityLimitLong(listingAddress, prep.leverageAmount, leverage);
        _transferMarginToListing(tokenB, listingAddress, maker, prep.taxedMargin, excessMargin, prep.fee, 0);

        (prep.initialLoan, prep.liquidationPrice) = _computeLoanAndLiquidationLong(
            prep.leverageAmount,
            minPrice,
            maker,
            tokenB
        );

        return prep;
    }

    function prepEnterShort(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        address listingAddress,
        address maker
    ) internal returns (PrepPosition memory prep) {
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice,) = parseEntryPrice(minEntryPrice, maxEntryPrice, listingAddress);

        prep.fee = computeFee(initialMargin, leverage);
        prep.taxedMargin = initialMargin - prep.fee;
        prep.leverageAmount = initialMargin * uint256(leverage);
        require(excessMargin <= prep.leverageAmount, "Excess margin too high");

        address tokenA = _checkLiquidityLimitShort(listingAddress, prep.leverageAmount, leverage);
        _transferMarginToListing(tokenA, listingAddress, maker, prep.taxedMargin, excessMargin, prep.fee, 1);

        (prep.initialLoan, prep.liquidationPrice) = _computeLoanAndLiquidationShort(
            prep.leverageAmount,
            minPrice,
            maker,
            tokenA
        );

        return prep;
    }

    function prepCloseLong(
        uint256 positionId,
        address listingAddress
    ) internal returns (uint256 payout) {
        PositionCore1 storage core1 = positionCore1[positionId];
        MarginParams1 storage margin1 = marginParams1[positionId];

        address tokenB = ISSListing(listingAddress).tokenB();
        payout = _computePayoutLong(positionId, listingAddress, tokenB);

        _deductMarginAndRemoveToken(core1.makerAddress, tokenB, margin1.taxedMargin, margin1.excessMargin);
        _executePayoutUpdate(positionId, listingAddress, payout, core1.positionType, core1.makerAddress);
    }

    function prepCloseShort(
        uint256 positionId,
        address listingAddress
    ) internal returns (uint256 payout) {
        PositionCore1 storage core1 = positionCore1[positionId];
        MarginParams1 storage margin1 = marginParams1[positionId];

        address tokenA = ISSListing(listingAddress).tokenA();
        payout = _computePayoutShort(positionId, listingAddress, tokenA);

        _deductMarginAndRemoveToken(core1.makerAddress, tokenA, margin1.taxedMargin, margin1.excessMargin);
        _executePayoutUpdate(positionId, listingAddress, payout, core1.positionType, core1.makerAddress);
    }

    function setExitParams(
        uint256 positionId,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) internal {
        ExitParams storage exit = exitParams[positionId];
        exit.stopLossPrice = stopLossPrice;
        exit.takeProfitPrice = takeProfitPrice;
    }
}