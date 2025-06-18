// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.45 (Updated)
// Changes:
// - v0.0.45: Fixed TypeError at lines 254 and 272 in _executeBuyOrderUpdate and _executeSellOrderUpdate by replacing 'return;' with 'return new ISSListingTemplate.UpdateType[](0);' to provide required return arguments. Fixed TypeError at line 119 in _computeImpact by removing 'override' keyword, as no virtual function exists in SSOrderPartial.sol.
// - v0.0.44: Fixed ParserError at line 508 in executeLongPayouts by correcting for loop condition from 'i < iterationCount; i < orderIdentifiers.length' to 'i < iterationCount'. Fixed executeLongPayouts and executeShortPayouts: replaced recursive calls with executeLongPayout/executeShortPayout, corrected payoutUpdates.length == address(0) to == 0, fixed iterationCount in executeShortPayouts, corrected loop bounds, and added updateIndex increments.
// - v0.0.43: Fixed ParserError in _transferListingPayoutAmount by correcting misplaced curly brace at line 86. Fixed _transferPayoutAmount and _transferListingPayoutAmount by replacing context.tokenAddress with context.tokenOut. Corrected _createPayoutUpdate by updating updateType to payoutType, requiredAmount to required, normalizedReceivedAmount to normalizedReceived, and struct to PayoutUpdate.
// - v0.0.42: Added _executeBuyOrderUpdate and _executeSellOrderUpdate from v0.0.38 to fix DeclarationError for undeclared identifiers in executeBuyOrder and executeSellOrder (lines 358, 394). Functions reduce orderPendingAmounts and call _createOrderUpdates.
// - v0.0.41: Skipped due to incomplete implementation of _executeBuyOrderUpdate and _executeSellOrderUpdate.
// - v0.0.40: Fixed _computeImpact to account for inputAmount already included in balances from listingVolumeBalancesView. For buy orders, inputAmount is in yBalance (tokenB), calculate amountOut as (inputAmount * xBalance) / yBalance, subtract from xBalance. For sell orders, inputAmount is in xBalance (tokenA), calculate amountOut as (inputAmount * yBalance) / xBalance, subtract from yBalance. Returns post-settlement price (newXBalance * 1e18) / newYBalance.
// - v0.0.39: Incorrectly assumed inputAmount needed re-adding in _computeImpact. Fixed in v0.0.40.
// - v0.0.38: Fixed token assignment in _prepPayoutContext to align with expected behavior: long payouts use tokenB and decimalsB, short payouts use tokenA and decimalsA.
// - v0.0.37: Removed interface declarations for ISSListingTemplate, ISSLiquidityTemplate, and IERC20, as they are in SSMainPartial.sol. Fixed DeclarationError in executeLongPayout.
// - v0.0.36: Removed post-transfer balance checks in _checkRecipientTransfer, _prepBuyOrderUpdate, and _prepSellOrderUpdate.
// - v0.0.35: Added denormalization in executeBuyOrder and executeSellOrder before _checkRecipientTransfer.
// - v0.0.34: Fixed TypeError in _prepLongPayoutLiquid, _prepShortPayoutLiquid, executeLongPayout, and executeShortPayout.
// - v0.0.33: Refactored executeLongPayout and executeShortPayout for partial settlement.
// - v0.0.32: Added _prepPayoutContext, _checkLiquidityBalance, _transferPayoutAmount, _createPayoutUpdate helpers.

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
    ) internal view returns (PayoutContext memory context) {
        // Initializes payout context with listing and liquidity details
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        context = PayoutContext({
            listingAddress: listingAddress,
            liquidityAddr: listingContract.liquidityAddressView(),
            tokenOut: isLong ? listingContract.tokenB() : listingContract.tokenA(), // tokenB for long, tokenA for short
            tokenDecimals: isLong ? listingContract.decimalsB() : listingContract.decimalsA(), // decimalsB for long, decimalsA for short
            amountOut: 0,
            recipientAddress: address(0)
        });
    }

    function _checkLiquidityBalance(
        PayoutContext memory context,
        uint256 requiredAmount,
        bool isLong
    ) internal view returns (bool sufficient) {
        // Checks if liquidity pool has sufficient balance for payout
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(context.liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        sufficient = isLong ? xAmount >= requiredAmount : yAmount >= requiredAmount;
    }

    function _transferPayoutAmount(
        PayoutContext memory context,
        uint256 amountOut
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers tokens from liquidity pool to recipient, measures actual amount
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
        // Transfers tokens from listing contract to recipient, measures actual amount
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
    ) internal pure returns (ISSListingTemplate.PayoutUpdate[] memory updates) {
        // Creates payout update struct for state changes
        updates = new ISSListingTemplate.PayoutUpdate[](1);
        updates[0] = ISSListingTemplate.PayoutUpdate({
            payoutType: isLong ? 0 : 1,
            recipient: recipientAddress,
            required: normalizedReceived
        });
    }

    function _computeImpact(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view virtual returns (uint256 price) {
        // Computes post-settlement price based on balances with inputAmount already included
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
        require(yBalance > 0, "Zero yBalance");
        uint256 amountOut;
        uint256 newXBalance = xBalance;
        uint256 newYBalance = yBalance;
        if (isBuyOrder) {
            // Buy order: inputAmount (tokenB) in yBalance, output tokenA (x)
            amountOut = (inputAmount * xBalance) / yBalance; // Constant product formula
            require(xBalance >= amountOut, "Insufficient xBalance");
            newXBalance -= amountOut; // Subtract output from xBalance
        } else {
            // Sell order: inputAmount (tokenA) in xBalance, output tokenB (y)
            amountOut = (inputAmount * yBalance) / xBalance; // Constant product formula
            require(yBalance >= amountOut, "Insufficient yBalance");
            newYBalance -= amountOut; // Subtract output from yBalance
        }
        require(newYBalance > 0, "Zero new yBalance");
        price = (newXBalance * 1e18) / newYBalance; // Post-settlement price
    }

    function _getTokenAndDecimals(
        address listingAddress,
        bool isBuyOrder
    ) internal view returns (address tokenAddress, uint8 tokenDecimals) {
        // Retrieves token address and decimals for order type
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
        // Transfers tokens to recipient, assumes success
        ISSListingTemplate listingContract = ISSListingTemplate(targetContract);
        uint8 tokenDecimals = tokenAddress == address(0) ? 18 : IERC20(tokenAddress).decimals();
        try listingContract.transact(address(this), tokenAddress, inputAmount, recipientAddress) {} catch {
            return (0, 0);
        }
        amountReceived = inputAmount; // User foots fee-on-transfer costs
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
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Creates update structs for order state changes
        updates = new ISSListingTemplate.UpdateType[](2);
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
        // Prepares buy order update, transfers output tokens
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (tokenAddress, tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (makerAddress, recipientAddress, orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(inputAmount, tokenDecimals);
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
        // Prepares sell order update, transfers output tokens
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (tokenAddress, tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (makerAddress, recipientAddress, orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(inputAmount, tokenDecimals);
        (amountReceived, normalizedReceived) = _checkRecipientTransfer(listingAddress, tokenAddress, denormalizedAmount, recipientAddress);
    }

    function _executeBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 normalizedReceivedAmount,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes buy order update, reduces pending amount
        if (normalizedReceivedAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 pendingAmount,) = ISSListingTemplate(listingAddress).getBuyOrderAmounts(orderIdentifier);
        orderPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceivedAmount;
        updates = _createOrderUpdates(orderIdentifier, normalizedReceivedAmount, makerAddress, recipientAddress, orderStatus, true, pendingAmount);
    }

    function _executeSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 normalizedReceivedAmount,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes sell order update, reduces pending amount
        if (normalizedReceivedAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 pendingAmount,) = ISSListingTemplate(listingAddress).getSellOrderAmounts(orderIdentifier);
        orderPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceivedAmount;
        updates = _createOrderUpdates(orderIdentifier, normalizedReceivedAmount, makerAddress, recipientAddress, orderStatus, false, pendingAmount);
    }

    function _prepLongPayoutLiquid(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate.LongPayoutStruct memory payout
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory updates) {
        // Processes long payout from liquidity pool
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
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, true);
    }

    function _prepShortPayoutLiquid(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate.ShortPayoutStruct memory payout
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory updates) {
        // Processes short payout from liquidity pool
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
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, false);
    }

    function executeLongPayout(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory updates) {
        // Executes long payout from listing contract
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
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, true);
    }

    function executeShortPayout(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory updates) {
        // Executes short payout from listing contract
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
        updates = _createPayoutUpdate(normalizedReceived, payout.recipientAddress, false);
    }

    function executeBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 inputAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Executes buy order with price validation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256 amountOut;
        {
            (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
            (uint256 pendingAmount,) = listingContract.getBuyOrderAmounts(orderIdentifier);
            if (pendingAmount == 0 || inputAmount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            // Calculate amountOut using constant product formula
            (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
            amountOut = (inputAmount * xBalance) / yBalance;
            require(xBalance >= amountOut, "Insufficient xBalance");
            // Validate impact price
            uint256 impactPrice = _computeImpact(listingAddress, inputAmount, true);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
        }
        (
            address tokenAddress,
            uint8 tokenDecimals,
            address makerAddress,
            address recipientAddress,
            uint8 orderStatus,
            uint256 amountReceived,
            uint256 normalizedReceived
        ) = _prepBuyOrderUpdate(listingAddress, orderIdentifier, amountOut);
        updates = _executeBuyOrderUpdate(listingAddress, orderIdentifier, normalizedReceived, makerAddress, recipientAddress, orderStatus);
    }

    function executeSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 inputAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Executes sell order with price validation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256 amountOut;
        {
            (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
            (uint256 pendingAmount,) = listingContract.getSellOrderAmounts(orderIdentifier);
            if (pendingAmount == 0 || inputAmount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            // Calculate amountOut using constant product formula
            (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
            amountOut = (inputAmount * yBalance) / xBalance;
            require(yBalance >= amountOut, "Insufficient yBalance");
            // Validate impact price
            uint256 impactPrice = _computeImpact(listingAddress, inputAmount, false);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
        }
        (
            address tokenAddress,
            uint8 tokenDecimals,
            address makerAddress,
            address recipientAddress,
            uint8 orderStatus,
            uint256 amountReceived,
            uint256 normalizedReceived
        ) = _prepSellOrderUpdate(listingAddress, orderIdentifier, amountOut);
        updates = _executeSellOrderUpdate(listingAddress, orderIdentifier, normalizedReceived, makerAddress, recipientAddress, orderStatus);
    }

    function executeBuyOrders(address listingAddress, uint256 maxIterations) internal onlyValidListing(listingAddress) {
        // Processes multiple buy orders
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
        // Processes multiple sell orders
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
        // Processes multiple long payouts
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
        // Processes multiple short payouts
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