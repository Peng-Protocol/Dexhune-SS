/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-06-14: Removed `override` from normalizePrice, denormalizeAmount, normalizeAmount, _validateAndInit, _setCoreData, _setPriceData, _setMarginData, and _setExitData to resolve TypeError for unneeded override. Kept `virtual` for potential overrides in derived contracts. Version incremented to 0.0.23.
// - 2025-06-14: Renamed public virtual parseEntryPrice to _parseEntryPriceHelper, removed virtual/override, made internal to resolve DeclarationError for duplicate function. Version incremented to 0.0.22.
// - 2025-06-14: Removed updateHistoricalInterest and positionToken references to resolve DeclarationError at lines 436, 491, 505, 507, 509. Moved updateHistoricalInterest to SSCrossDriver.sol. Updated _setExitData to accept token parameter, removing positionToken access. Removed positionToken from _setCoreData. Version incremented to 0.0.21.
// - 2025-06-14: Moved PrepPosition struct before function declarations to resolve DeclarationError at line 233:25 in _computeEntryParams. Version incremented to 0.0.20.
// - 2025-06-14: Added _prepareEntryContext, _validateEntry, _computeEntryParams, _storeEntryData helpers to support refactored _initiateEntry in SSCrossDriver.sol, aligning with isolatedDriver's call tree. Updated prepEnterLong/prepEnterShort to use EntryContext. Version incremented to 0.0.19.
// - 2025-06-13: Replaced safeTransferFrom with transferFrom in _transferMarginToListing and safeTransfer with transfer in _transferLiquidityFee, added balance checks. Renamed totalMargin to transferAmount. Removed SafeERC20 import. Version incremented to 0.0.18.

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

    function parseEntryPrice(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        currentPrice = ISSListing(listingAddress).prices(listingAddress);
        minPrice = minEntryPrice;
        maxPrice = maxEntryPrice;
        priceAtEntry = currentPrice >= minPrice && currentPrice <= maxPrice ? currentPrice : 0;
        return (currentPrice, minPrice, maxPrice, priceAtEntry);
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
            uint256 denormalizedFee = denormalizeAmount(token, fee);
            uint256 balanceBefore = IERC20(token).balanceOf(liquidityAddr);
            bool success = IERC20(token).transfer(liquidityAddr, denormalizedFee);
            require(success, "Transfer failed");
            uint256 balanceAfter = IERC20(token).balanceOf(liquidityAddr);
            require(balanceAfter - balanceBefore == denormalizedFee, "Fee transfer failed");
            ISSLiquidityTemplate(liquidityAddr).addFees(address(this), positionType == 0 ? true : false, denormalizedFee);
        }
    }

    function _transferMarginToListing(
        address token,
        address listingAddress,
        address maker,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint8 positionType
    ) internal {
        uint256 transferAmount = taxedMargin + excessMargin;
        _transferLiquidityFee(listingAddress, token, fee, positionType);
        if (transferAmount > 0) {
            uint256 denormalizedAmount = denormalizeAmount(token, transferAmount);
            uint256 balanceBefore = IERC20(token).balanceOf(listingAddress);
            bool success = IERC20(token).transferFrom(msg.sender, listingAddress, denormalizedAmount);
            require(success, "TransferFrom failed");
            uint256 balanceAfter = IERC20(token).balanceOf(listingAddress);
            require(balanceAfter - balanceBefore == denormalizedAmount, "Balance update failed");

            ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1);
            updates[0] = ISSListing.UpdateType({
                updateType: 0,
                index: positionType,
                value: denormalizedAmount,
                addr: address(0),
                recipient: address(0)
            });
            ISSListing(listingAddress).update(address(this), updates);
        }
        makerTokenMargin[maker][token] += transferAmount;
        if (makerTokenMargin[maker][token] == transferAmount) {
            makerMarginTokens[maker].push(token);
        }
    }

    function _computePayoutLong(
        uint256 positionId,
        address listingAddress,
        address tokenB
    ) internal view returns (uint256) {
        MarginParams1 storage margin1 = marginParams1[positionId];
        MarginParams2 storage margin2 = marginParams2[positionId];
        PriceParams1 storage price1 = priceParams1[positionId];
        uint256 currentPrice = normalizePrice(tokenB, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price");
        uint256 totalMargin = makerTokenMargin[positionCore1[positionId].makerAddress][tokenB];
        uint256 leverageAmount = uint256(price1.leverage) * margin1.initialMargin;
        return ((margin1.taxedMargin + totalMargin + leverageAmount) / currentPrice) - margin2.initialLoan;
    }

    function _computePayoutShort(
        uint256 positionId,
        address listingAddress,
        address tokenA
    ) internal view returns (uint256) {
        MarginParams1 storage margin1 = marginParams1[positionId];
        PriceParams1 storage price1 = priceParams1[positionId];
        uint256 currentPrice = normalizePrice(tokenA, ISSListing(listingAddress).prices(listingAddress));
        require(currentPrice > 0, "Invalid price");
        uint256 totalMargin = makerTokenMargin[positionCore1[positionId].makerAddress][tokenA];
        return (price1.priceAtEntry - currentPrice) * margin1.initialMargin * uint256(price1.leverage) + (margin1.taxedMargin + totalMargin) * currentPrice;
    }

    function _checkLiquidityLimitLong(
        address listingAddress,
        uint256 leverageAmount,
        uint8 leverage
    ) internal view returns (address tokenB) {
        address liquidityAddr = ISSListing(listingAddress).liquidityAddressView(listingAddress);
        (uint256 xLiquid,,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView(address(this));
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
        (, uint256 yLiquid,,) = ISSLiquidityTemplate(liquidityAddr).liquidityDetailsView(address(this));
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
        address maker,
        address token
    ) internal {
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: positionType,
            recipient: maker,
            required: denormalizeAmount(token, payout)
        });
        ISSListing(listingAddress).ssUpdate(address(this), updates);
        exitParams[positionId].exitPrice = normalizePrice(token, ISSListing(listingAddress).prices(listingAddress));
        positionCore2[positionId].status2 = 1;
    }

    function _prepareEntryContext(
        address listingAddress,
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint8 positionType
    ) internal view returns (EntryContext memory context) {
        context = EntryContext({
            positionId: positionId,
            listingAddress: listingAddress,
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            positionType: positionType,
            maker: address(0),
            token: address(0)
        });
    }

    function _validateEntry(
        EntryContext memory context
    ) internal returns (EntryContext memory) {
        require(context.initialMargin > 0, "Invalid margin");
        require(context.leverage >= 2 && context.leverage <= 100, "Invalid leverage");
        (context.maker, context.token) = _validateAndInit(
            context.positionId,
            context.listingAddress,
            context.positionType
        );
        return context;
    }

    function _computeEntryParams(
        EntryContext memory context
    ) internal returns (PrepPosition memory params) {
        uint256 normMinPrice = normalizePrice(context.token, context.minEntryPrice);
        uint256 normMaxPrice = normalizePrice(context.token, context.maxEntryPrice);
        uint256 normInitialMargin = normalizeAmount(context.token, context.initialMargin);
        uint256 normExcessMargin = normalizeAmount(context.token, context.excessMargin);
        if (context.positionType == 0) {
            params = prepEnterLong(context);
        } else {
            params = prepEnterShort(context);
        }
    }

    function _storeEntryData(
        EntryContext memory context,
        PrepPosition memory prep,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) internal {
        _setCoreData(
            context.positionId,
            context.listingAddress,
            context.maker,
            context.positionType,
            context.token
        );
        _setPriceData(
            context.positionId,
            context.minEntryPrice,
            context.maxEntryPrice,
            prep.liquidationPrice,
            context.listingAddress,
            context.leverage,
            context.token
        );
        _setMarginData(
            context.positionId,
            context.initialMargin,
            prep.taxedMargin,
            context.excessMargin,
            prep.fee,
            prep.initialLoan,
            context.token
        );
        _setExitData(
            context.positionId,
            stopLossPrice,
            takeProfitPrice,
            prep.leverageAmount,
            context.listingAddress,
            context.positionType,
            context.token
        );
    }

    function prepEnterLong(
        EntryContext memory context
    ) internal returns (PrepPosition memory params) {
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice,) = parseEntryPrice(
            normalizePrice(context.token, context.minEntryPrice),
            normalizePrice(context.token, context.maxEntryPrice),
            context.listingAddress
        );

        params.fee = computeFee(context.initialMargin, context.leverage);
        params.taxedMargin = normalizeAmount(context.token, context.initialMargin) - params.fee;
        params.leverageAmount = normalizeAmount(context.token, context.initialMargin) * uint256(context.leverage);
        address tokenB = _checkLiquidityLimitLong(context.listingAddress, params.leverageAmount, context.leverage);
        _transferMarginToListing(
            tokenB,
            context.listingAddress,
            context.maker,
            params.taxedMargin,
            normalizeAmount(context.token, context.excessMargin),
            params.fee,
            0
        );
        (params.initialLoan, params.liquidationPrice) = _computeLoanAndLiquidationLong(
            params.leverageAmount,
            minPrice,
            context.maker,
            tokenB
        );
        return params;
    }

    function prepEnterShort(
        EntryContext memory context
    ) internal returns (PrepPosition memory params) {
        (uint256 currentPrice, uint256 minPrice, uint256 maxPrice,) = parseEntryPrice(
            normalizePrice(context.token, context.minEntryPrice),
            normalizePrice(context.token, context.maxEntryPrice),
            context.listingAddress
        );

        params.fee = computeFee(context.initialMargin, context.leverage);
        params.taxedMargin = normalizeAmount(context.token, context.initialMargin) - params.fee;
        params.leverageAmount = normalizeAmount(context.token, context.initialMargin) * uint256(context.leverage);
        address tokenA = _checkLiquidityLimitShort(context.listingAddress, params.leverageAmount, context.leverage);
        _transferMarginToListing(
            tokenA,
            context.listingAddress,
            context.maker,
            params.taxedMargin,
            normalizeAmount(context.token, context.excessMargin),
            params.fee,
            1
        );
        (params.initialLoan, params.liquidationPrice) = _computeLoanAndLiquidationShort(
            params.leverageAmount,
            minPrice,
            context.maker,
            tokenA
        );
        return params;
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
        _executePayoutUpdate(positionId, listingAddress, payout, core1.positionType, core1.makerAddress, tokenB);
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
        _executePayoutUpdate(positionId, listingAddress, payout, core1.positionType, core1.makerAddress, tokenA);
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

    function normalizePrice(address token, uint256 price) internal view virtual returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    function denormalizeAmount(address token, uint256 amount) internal view virtual returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    function normalizeAmount(address token, uint256 amount) internal view virtual returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    function _validateAndInit(
        uint256 positionId,
        address listingAddress,
        uint8 positionType
    ) internal virtual returns (address maker, address token) {
        require(positionCore1[positionId].positionId == 0, "Position ID exists");
        address tokenA = ISSListing(listingAddress).tokenA();
        address tokenB = ISSListing(listingAddress).tokenB();
        address expectedListing = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(expectedListing == listingAddress, "Invalid listing");
        maker = msg.sender;
        positionCount++;
        token = positionType == 0 ? tokenB : tokenA;
    }

    function _setCoreData(
        uint256 positionId,
        address listingAddress,
        address maker,
        uint8 positionType,
        address token
    ) internal virtual {
        positionCore1[positionId] = PositionCore1({
            positionId: positionId,
            listingAddress: listingAddress,
            makerAddress: maker,
            positionType: positionType
        });
        positionCore2[positionId] = PositionCore2({ status1: false, status2: 0 });
    }

    function _setPriceData(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 liquidationPrice,
        address listingAddress,
        uint8 leverage,
        address token
    ) internal virtual {
        (, , , uint256 priceAtEntry) = parseEntryPrice(
            normalizePrice(token, minEntryPrice),
            normalizePrice(token, maxEntryPrice),
            listingAddress
        );
        priceParams1[positionId] = PriceParams1({
            minEntryPrice: normalizePrice(token, minEntryPrice),
            maxEntryPrice: normalizePrice(token, maxEntryPrice),
            minPrice: liquidationPrice,
            priceAtEntry: priceAtEntry,
            leverage: leverage
        });
        priceParams2[positionId] = PriceParams2({ liquidationPrice: liquidationPrice });
    }

    function _setMarginData(
        uint256 positionId,
        uint256 initialMargin,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint256 initialLoan,
        address token
    ) internal virtual {
        marginParams1[positionId] = MarginParams1({
            initialMargin: normalizeAmount(token, initialMargin),
            taxedMargin: taxedMargin,
            excessMargin: normalizeAmount(token, excessMargin),
            fee: fee
        });
        marginParams2[positionId] = MarginParams2({
            initialLoan: normalizeAmount(token, initialLoan)
        });
    }

    function _setExitData(
        uint256 positionId,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 leverageAmount,
        address listingAddress,
        uint8 positionType,
        address token
    ) internal virtual {
        exitParams[positionId] = ExitParams({
            stopLossPrice: normalizePrice(token, stopLossPrice),
            takeProfitPrice: normalizePrice(token, takeProfitPrice),
            exitPrice: 0
        });
        openInterest[positionId] = OpenInterest({ leverageAmount: leverageAmount, timestamp: block.timestamp });
        pendingPositions[listingAddress][positionType].push(positionId);
    }

    function _parseEntryPriceHelper(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        address listingAddress,
        address maker
    ) internal returns (PrepPosition memory) {}

    function prepEnterShort(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        address listingAddress,
        address maker
    ) internal returns (PrepPosition memory) {}

    function _parseEntryPriceHelper(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal returns (uint256, uint256, uint256, uint256) {}
}