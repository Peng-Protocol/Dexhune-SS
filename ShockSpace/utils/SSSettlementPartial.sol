// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.38 (Updated)
// Changes:
// - v0.0.38: Fixed token assignment in _prepPayoutContext to align with expected behavior: long payouts (isLong = true) use tokenB (tokenY) and decimalsB (decimalY), short payouts (isLong = false) use tokenA (tokenX) and decimalsA (decimalX). Swapped tokenOut and tokenDecimals assignments to correct payout token usage (lines 38-45).
// - v0.0.37: Removed interface declarations for ISSListingTemplate, ISSLiquidityTemplate, and IERC20, as they are now declared in SSMainPartial.sol. Fixed DeclarationError in executeLongPayout by correcting return type to PayoutUpdate[] from PayoutPathUpdate[] to match struct in SSMainPartial.sol.
// - v0.0.36: Removed post-transfer balance checks in _checkRecipientTransfer, _prepBuyOrderUpdate, and _prepSellOrderUpdate. Assumes denormalized input amounts are transferred correctly, with users footing any fee-on-transfer costs, not LPs.
// - v0.0.35: Added denormalization in executeBuyOrder and executeSellOrder before calling _checkRecipientTransfer to ensure correct token amounts are sent to recipients based on token decimals.
// - v0.0.34: Fixed TypeError in _prepLongPayoutLiquid, _prepShortPayoutLiquid, executeLongPayout, and executeShortPayout by adding context.amountOut as the second argument to _transferPayoutAmount and _transferListingPayoutAmount calls, aligning with their function signatures.
// - v0.0.33: Refactored executeLongPayout and executeShortPayout to support partial settlement by measuring actual amount transferred via new _transferListingPayoutAmount helper. Updates payoutPendingAmounts only for actual normalizedReceived, returns empty array if transfer fails, ensuring accurate state for insufficient balances.
// - v0.0.32: Added _prepPayoutContext, _checkLiquidityBalance, _transferPayoutAmount, _createPayoutUpdate helpers to modularize payout processing for settleLongLiquid and settleShortLiquid, reducing stack usage and improving readability. Refactored _prepLongPayoutLiquid and _prepShortPayoutLiquid to use these new helpers.

import "./SSOrderPartial.sol";

contract SSSettlementPartial is SSOrderPartial {
    mapping(address => mapping(uint256 => uint256)) internal orderPendingAmounts;
    mapping(address => mapping(uint256 => uint256)) internal payoutPendingAmounts;

    struct PayoutContext {
        address listingAddress;
        address liquidityAddr;
        address tokenOut;
        uint8 tokenDecimals;
        uint256 amountOut;
        address recipientAddress;
    }

    function _prepPayoutContext(
        address listingAddress,
        uint256 orderId,
        bool isLong
    ) internal view returns (PayoutContext memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        return PayoutContext({
            listingAddress: listingAddress,
            liquidityAddr: listingContract.liquidityAddressView(),
            tokenOut: isLong ? listingContract.tokenB() : listingContract.tokenA(), // Use tokenB for long, tokenA for short
            tokenDecimals: isLong ? listingContract.decimalsB() : listingContract.decimalsA(), // Use decimalsB for long, decimalsA for short
            amountOut: 0,
            recipientAddress: address(0)
        });
    }

    function _checkLiquidityBalance(
        PayoutContext memory context,
        uint256 requiredAmount,
        bool isLong
    ) internal view returns (bool) {
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(context.liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        return isLong ? xAmount >= requiredAmount : yAmount >= requiredAmount;
    }

    function _transferPayoutAmount(
        PayoutContext memory context,
        uint256 amountOut
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(context.liquidityAddr);
        uint256 preBalance = context.tokenOut == address(0)
            ? context.recipientAddress.balance
            : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        try liquidityContract.transact(address(this), context.tokenOut, amountOut, context.recipientAddress) {} catch {
            return (0, 0);
        }
        uint256 postBalance = context.tokenOut == address(0)
            ? context.recipientAddress.balance
            : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, context.tokenDecimals) : 0;
    }

    function _transferListingPayoutAmount(
        PayoutContext memory context,
        uint256 amountOut
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        ISSListingTemplate listingContract = ISSListingTemplate(context.listingAddress);
        uint256 preBalance = context.tokenOut == address(0)
            ? context.recipientAddress.balance
            : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        try listingContract.transact(address(this), context.tokenOut, amountOut, context.recipientAddress) {} catch {
            return (0, 0);
        }
        uint256 postBalance = context.tokenOut == address(0)
            ? context.recipientAddress.balance
            : IERC20(context.tokenOut).balanceOf(context.recipientAddress);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, context.tokenDecimals) : 0;
    }

    function _createPayoutUpdate(
        uint256 normalizedReceived,
        address recipientAddress,
        bool isLong
    ) internal pure returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate.PayoutUpdate[] memory updates = new ISSListingTemplate.PayoutUpdate[](1);
        updates[0] = ISSListingTemplate.PayoutUpdate({
            payoutType: isLong ? 0 : 1,
            recipient: recipientAddress,
            required: normalizedReceived
        });
        return updates;
    }

    function _computeImpact(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view virtual returns (uint256) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
        require(yBalance > 0, "Zero yBalance");
        uint256 currentPrice = (xBalance * 1e18) / yBalance;
        uint256 amountOut;
        uint256 newXBalance = xBalance;
        uint256 newYBalance = yBalance;
        if (isBuyOrder) {
            amountOut = (inputAmount * currentPrice) / 1e18;
            require(xBalance >= amountOut, "Insufficient xBalance");
            newXBalance -= amountOut;
        } else {
            amountOut = (inputAmount * 1e18) / currentPrice;
            require(yBalance >= amountOut, "Insufficient yBalance");
            newYBalance -= amountOut;
        }
        require(newYBalance > 0, "Zero new yBalance");
        return (newXBalance * 1e18) / newYBalance;
    }

    function _getTokenAndDecimals(
        address listingAddress,
        bool isBuyOrder
    ) internal view returns (address tokenAddress, uint8 tokenDecimals) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        tokenAddress = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
        tokenDecimals = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
    }

    function _checkRecipientTransfer(
        address targetContract,
        address tokenAddress,
        uint256 inputAmount,
        address recipientAddress
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        ISSListingTemplate listingContract = ISSListingTemplate(targetContract);
        uint8 tokenDecimals = tokenAddress == address(0) ? 18 : IERC20(tokenAddress).decimals();
        try listingContract.transact(address(this), tokenAddress, inputAmount, recipientAddress) {} catch {
            return (0, 0);
        }
        // Assume transfer succeeds, user foots any fee-on-transfer costs, not LPs
        amountReceived = inputAmount;
        normalizedReceived = normalize(inputAmount, tokenDecimals);
    }

    function _createOrderUpdates(
        uint256 orderIdentifier,
        uint256 normalizedReceivedAmount,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuyOrder ? 1 : 2,
            structId: 2,
            index: orderIdentifier,
            value: normalizedReceivedAmount,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: isBuyOrder ? 1 : 2,
            structId: 0,
            index: orderIdentifier,
            value: orderStatus == 1 && normalizedReceivedAmount >= pendingAmount ? 3 : 2,
            addr: makerAddress,
            recipient: recipientAddress,
            maxPrice: 0,
            minPrice: 0
        });
        return updates;
    }

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 inputAmount
    ) internal returns (
        address tokenAddress,
        uint8 tokenDecimals,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus,
        uint256 amountReceived,
        uint256 normalizedReceived
    ) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (tokenAddress, tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (makerAddress, recipientAddress, orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(inputAmount, tokenDecimals);
        // Assume transfer succeeds, user foots any fee-on-transfer costs, not LPs
        (amountReceived, normalizedReceived) = _checkRecipientTransfer(listingAddress, tokenAddress, denormalizedAmount, recipientAddress);
    }

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 inputAmount
    ) internal returns (
        address tokenAddress,
        uint8 tokenDecimals,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus,
        uint256 amountReceived,
        uint256 normalizedReceived
    ) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (tokenAddress, tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (makerAddress, recipientAddress, orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(inputAmount, tokenDecimals);
        // Assume transfer succeeds, user foots any fee-on-transfer costs, not LPs
        (amountReceived, normalizedReceived) = _checkRecipientTransfer(listingAddress, tokenAddress, denormalizedAmount, recipientAddress);
    }

    function _prepLongPayoutLiquid(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate.LongPayoutStruct memory payout
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        if (payout.required == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, true);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.required, context.tokenDecimals);
        if (!_checkLiquidityBalance(context, payout.required, true)) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        (uint256 amountReceived, uint256 normalizedReceived) = _transferPayoutAmount(context, context.amountOut);
        if (normalizedReceived == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        return _createPayoutUpdate(normalizedReceived, payout.recipientAddress, true);
    }

    function _prepShortPayoutLiquid(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate.ShortPayoutStruct memory payout
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        if (payout.amount == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, false);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.amount, context.tokenDecimals);
        if (!_checkLiquidityBalance(context, payout.amount, false)) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        (uint256 amountReceived, uint256 normalizedReceived) = _transferPayoutAmount(context, context.amountOut);
        if (normalizedReceived == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        return _createPayoutUpdate(normalizedReceived, payout.recipientAddress, false);
    }

    function _executeBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 normalizedReceivedAmount,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        if (normalizedReceivedAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 pendingAmount,) = ISSListingTemplate(listingAddress).getBuyOrderAmounts(orderIdentifier);
        orderPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceivedAmount;
        return _createOrderUpdates(orderIdentifier, normalizedReceivedAmount, makerAddress, recipientAddress, orderStatus, true, pendingAmount);
    }

    function _executeSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 normalizedReceivedAmount,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        if (normalizedReceivedAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 pendingAmount,) = ISSListingTemplate(listingAddress).getSellOrderAmounts(orderIdentifier);
        orderPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceivedAmount;
        return _createOrderUpdates(orderIdentifier, normalizedReceivedAmount, makerAddress, recipientAddress, orderStatus, false, pendingAmount);
    }

    function executeLongPayout(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.LongPayoutStruct memory payout = listingContract.getLongPayout(orderIdentifier);
        if (payout.required == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, true);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.required, context.tokenDecimals);
        (uint256 amountReceived, uint256 normalizedReceived) = _transferListingPayoutAmount(context, context.amountOut);
        if (normalizedReceived == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        return _createPayoutUpdate(normalizedReceived, payout.recipientAddress, true);
    }

    function executeShortPayout(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.ShortPayoutStruct memory payout = listingContract.getShortPayout(orderIdentifier);
        if (payout.amount == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, false);
        context.recipientAddress = payout.recipientAddress;
        context.amountOut = denormalize(payout.amount, context.tokenDecimals);
        (uint256 amountReceived, uint256 normalizedReceived) = _transferListingPayoutAmount(context, context.amountOut);
        if (normalizedReceived == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        return _createPayoutUpdate(normalizedReceived, payout.recipientAddress, false);
    }

    function executeBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 inputAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        {
            (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
            (uint256 pendingAmount,) = listingContract.getBuyOrderAmounts(orderIdentifier);
            if (pendingAmount == 0 || inputAmount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            uint256 impactPrice = _computeImpact(listingAddress, inputAmount, true);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            inputAmount = (inputAmount * impactPrice) / 1e18;
        }
        (
            address tokenAddress,
            uint8 tokenDecimals,
            address makerAddress,
            address recipientAddress,
            uint8 orderStatus,
            uint256 amountReceived,
            uint256 normalizedReceived
        ) = _prepBuyOrderUpdate(listingAddress, orderIdentifier, inputAmount);
        return _executeBuyOrderUpdate(listingAddress, orderIdentifier, normalizedReceived, makerAddress, recipientAddress, orderStatus);
    }

    function executeSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 inputAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        {
            (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
            (uint256 pendingAmount,) = listingContract.getSellOrderAmounts(orderIdentifier);
            if (pendingAmount == 0 || inputAmount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            uint256 impactPrice = _computeImpact(listingAddress, inputAmount, false);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            inputAmount = (inputAmount * 1e18) / impactPrice;
        }
        (
            address tokenAddress,
            uint8 tokenDecimals,
            address makerAddress,
            address recipientAddress,
            uint8 orderStatus,
            uint256 amountReceived,
            uint256 normalizedReceived
        ) = _prepSellOrderUpdate(listingAddress, orderIdentifier, inputAmount);
        return _executeSellOrderUpdate(listingAddress, orderIdentifier, normalizedReceived, makerAddress, recipientAddress, orderStatus);
    }

    function executeBuyOrders(address listingAddress, uint256 maxIterations) internal onlyValidListing(listingAddress) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdentifier = orderIdentifiers[i];
            (uint256 pendingAmount,) = listingContract.getBuyOrderAmounts(orderIdentifier);
            if (pendingAmount == 0) {
                continue;
            }
            (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
            uint256 denormalizedAmount = denormalize(pendingAmount, tokenDecimals);
            ISSListingTemplate.UpdateType[] memory updates = executeBuyOrder(listingAddress, orderIdentifier, denormalizedAmount);
            if (updates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < updates.length; j++) {
                tempUpdates[updateIndex++] = updates[j];
            }
        }
        ISSListingTemplate.UpdateType[] memory finalUpdates = new ISSListingTemplate.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function executeSellOrders(address listingAddress, uint256 maxIterations) internal onlyValidListing(listingAddress) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdentifier = orderIdentifiers[i];
            (uint256 pendingAmount,) = listingContract.getSellOrderAmounts(orderIdentifier);
            if (pendingAmount == 0) {
                continue;
            }
            (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
            uint256 denormalizedAmount = denormalize(pendingAmount, tokenDecimals);
            ISSListingTemplate.UpdateType[] memory updates = executeSellOrder(listingAddress, orderIdentifier, denormalizedAmount);
            if (updates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < updates.length; j++) {
                tempUpdates[updateIndex++] = updates[j];
            }
        }
        ISSListingTemplate.UpdateType[] memory finalUpdates = new ISSListingTemplate.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function executeLongPayouts(address listingAddress, uint256 maxIterations) internal onlyValidListing(listingAddress) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdentifier = orderIdentifiers[i];
            ISSListingTemplate.PayoutUpdate[] memory payoutUpdates = executeLongPayout(listingAddress, orderIdentifier);
            if (payoutUpdates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < payoutUpdates.length; j++) {
                tempPayoutUpdates[updateIndex++] = payoutUpdates[j];
            }
        }
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function executeShortPayouts(address listingAddress, uint256 maxIterations) internal onlyValidListing(listingAddress) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdentifier = orderIdentifiers[i];
            ISSListingTemplate.PayoutUpdate[] memory payoutUpdates = executeShortPayout(listingAddress, orderIdentifier);
            if (payoutUpdates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < payoutUpdates.length; j++) {
                tempPayoutUpdates[updateIndex++] = payoutUpdates[j];
            }
        }
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }
}