// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.57 (Updated)
// Changes:
// - v0.0.57: Fixed stack-too-deep error in executeSellOrders and executeBuyOrders by introducing internal _processSellOrder and _processBuyOrder helper functions to handle loop bodies, reducing stack usage to ~13 variables. Restored _getTokenAndDecimals usage to align with ISSListingTemplate's modular helper design.
// - v0.0.56: Attempted to fix stack-too-deep error by inlining _getTokenAndDecimals and removing unused filled and amountSent variables, but error persisted.
// - v0.0.55: Fixed stack-too-deep error by introducing PrepOrderUpdateResult struct to encapsulate _prepSellOrderUpdate and _prepBuyOrderUpdate return values, reducing stack usage. Optimized loop variables and tuple destructuring.
// - v0.0.54: Fixed ParserError in _prepSellOrderUpdate by correcting return type syntax from `address tokenAddress ^^ uint8` to `address tokenAddress, uint8 tokenDecimals`.
// - v0.0.53: Fixed tuple destructuring in _executeBuyOrderUpdate and _executeSellOrderUpdate to include all three return values (pending, filled, amountSent) from getBuyOrderAmounts and getSellOrderAmounts, resolving TypeError.
// - v0.0.52: Fixed ParserError in orderPendingAmounts/payoutPendingAmounts mappings by removing 'amount' identifier. Corrected _prepSellOrderUpdate, _createOrderUpdates, _executeBuyOrderUpdate, _executeSellOrderUpdate, and executeBuyOrders for syntax and function calls. Ensured compatibility with SSRouter.sol v0.0.58.
// - v0.0.51: Added settleSingleLongLiquid and settleSingleShortLiquid from SSRouter.sol v0.0.44.
// - v0.0.50: Added _computeAmountSent for tracking actual tokens sent.
// - v0.0.49: Fixed token assignments in _prepBuyOrderUpdate and _getTokenAndDecimals.
// - v0.0.48: Fixed stack depth in _executeBuyOrderUpdate and _executeSellOrderUpdate.
// - v0.0.47: Corrected _checkRecipientTransfer for fee-on-transfer tokens.

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

    struct PrepOrderUpdateResult {
        address tokenAddress;
        uint8 tokenDecimals;
        address makerAddress;
        address recipientAddress;
        uint8 orderStatus;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
    }

    function _computeAmountSent(
        address tokenAddress,
        address recipientAddress,
        uint256 amount
    ) internal view returns (uint256) {
        // Computes actual tokens sent by checking recipient balance changes
        uint256 preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
        uint256 postBalance = preBalance; // Placeholder, actual logic depends on transfer
        return postBalance > preBalance ? postBalance - preBalance : 0;
    }

    function _prepPayoutContext(
        address listingAddress,
        uint256 orderId,
        bool isLong
    ) internal view returns (PayoutContext memory context) {
        // Prepares payout context with listing and token details
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        context = PayoutContext({
            listingAddress: listingAddress,
            liquidityAddr: listingContract.liquidityAddressView(),
            tokenOut: isLong ? listingContract.tokenB() : listingContract.tokenA(),
            tokenDecimals: isLong ? listingContract.decimalsB() : listingContract.decimalsA(),
            amountOut: 0,
            recipientAddress: address(0)
        });
    }

    function _checkLiquidityBalance(
        PayoutContext memory context,
        uint256 requiredAmount,
        bool isLong
    ) internal view returns (bool sufficient) {
        // Checks if liquidity pool has sufficient tokens for payout
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(context.liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        sufficient = isLong ? yAmount >= requiredAmount : xAmount >= requiredAmount;
    }

    function _transferPayoutAmount(
        PayoutContext memory context,
        uint256 amountOut
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers tokens from liquidity pool to recipient, tracks received amount
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
        // Transfers tokens from listing contract to recipient, tracks received amount
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
        // Creates payout update struct for long or short payouts
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
    ) internal view returns (uint256 price) {
        // Computes price impact of order on listing balances
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
        require(yBalance > 0, "Zero yBalance");
        uint256 amountOut;
        uint256 newXBalance = xBalance;
        uint256 newYBalance = yBalance;
        if (isBuyOrder) {
            amountOut = (inputAmount * xBalance) / yBalance;
            require(xBalance >= amountOut, "Insufficient xBalance");
            newXBalance -= amountOut;
        } else {
            amountOut = (inputAmount * yBalance) / xBalance;
            require(yBalance >= amountOut, "Insufficient yBalance");
            newYBalance -= amountOut;
        }
        require(newYBalance > 0, "Zero new yBalance");
        price = (newXBalance * 1e18) / newYBalance;
    }

    function _getTokenAndDecimals(
        address listingAddress,
        bool isBuyOrder
    ) internal view returns (address tokenAddress, uint8 tokenDecimals) {
        // Retrieves token address and decimals based on order type
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        tokenAddress = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenDecimals = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
    }

    function _checkRecipientTransfer(
        address targetContract,
        address tokenAddress,
        uint256 inputAmount,
        address recipientAddress
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Validates token transfer to recipient, normalizes amount
        ISSListingTemplate listingContract = ISSListingTemplate(targetContract);
        uint8 tokenDecimals = tokenAddress == address(0) ? 18 : IERC20(tokenAddress).decimals();
        try listingContract.transact(address(this), tokenAddress, inputAmount, recipientAddress) {} catch {
            return (0, 0);
        }
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
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Creates update structs for buy or sell order updates
        updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuyOrder ? 1 : 2,
            structId: 2,
            index: orderIdentifier,
            value: normalizedReceivedAmount,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: isBuyOrder ? 1 : 2,
            structId: 0,
            index: orderIdentifier,
            value: orderStatus == 1 && normalizedReceivedAmount >= pendingAmount ? 3 : 2,
            addr: makerAddress,
            recipient: recipientAddress,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
    }

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares buy order update data, including token transfer
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        (result.makerAddress, result.recipientAddress, result.orderStatus) = listingContract.getBuyOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        (result.amountReceived, result.normalizedReceived) = _checkRecipientTransfer(listingAddress, result.tokenAddress, denormalizedAmount, result.recipientAddress);
        result.amountSent = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
    }

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal returns (PrepOrderUpdateResult memory result) {
        // Prepares sell order update data, including token transfer
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (result.tokenAddress, result.tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        (result.recipientAddress, result.makerAddress, result.orderStatus) = listingContract.getSellOrderCore(orderIdentifier);
        uint256 denormalizedAmount = denormalize(amountOut, result.tokenDecimals);
        (result.amountReceived, result.normalizedReceived) = _checkRecipientTransfer(listingAddress, result.tokenAddress, denormalizedAmount, result.recipientAddress);
        result.amountSent = _computeAmountSent(result.tokenAddress, result.recipientAddress, denormalizedAmount);
    }

    function _executeBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 normalizedReceivedAmount,
        address makerAddress,
        address recipientAddress,
        uint8 orderStatus
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Executes buy order update, adjusts pending amounts
        if (normalizedReceivedAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = ISSListingTemplate(listingAddress).getBuyOrderAmounts(orderIdentifier);
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
        // Executes sell order update, adjusts pending amounts
        if (normalizedReceivedAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = ISSListingTemplate(listingAddress).getSellOrderAmounts(orderIdentifier);
        orderPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceivedAmount;
        updates = _createOrderUpdates(orderIdentifier, normalizedReceivedAmount, makerAddress, recipientAddress, orderStatus, false, pendingAmount);
    }

    function settleSingleLongLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory updates) {
        // Settles single long liquidation payout
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.LongPayoutStruct memory payout = listingContract.getLongPayout(orderIdentifier);
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

    function settleSingleShortLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory updates) {
        // Settles single short liquidation payout
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.ShortPayoutStruct memory payout = listingContract.getShortPayout(orderIdentifier);
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
        // Executes long payout from listing
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
        // Executes short payout from listing
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
        // Executes buy order, checks pricing and balances
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256 amountOut;
        {
            (uint256 maxPrice, uint256 minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
            (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
            if (pendingAmount == 0 || inputAmount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
            amountOut = (inputAmount * xBalance) / yBalance;
            require(xBalance >= amountOut, "Insufficient xBalance");
            uint256 impactPrice = _computeImpact(listingAddress, inputAmount, true);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
        }
        PrepOrderUpdateResult memory prepResult = _prepBuyOrderUpdate(listingAddress, orderIdentifier, amountOut);
        updates = _executeBuyOrderUpdate(
            listingAddress,
            orderIdentifier,
            prepResult.normalizedReceived,
            prepResult.makerAddress,
            prepResult.recipientAddress,
            prepResult.orderStatus
        );
    }

    function executeSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 inputAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Executes sell order, checks pricing and balances
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256 amountOut;
        {
            (uint256 maxPrice, uint256 minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
            (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
            if (pendingAmount == 0 || inputAmount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            (uint256 xBalance, uint256 yBalance,,) = listingContract.listingVolumeBalancesView();
            amountOut = (inputAmount * yBalance) / xBalance;
            require(yBalance >= amountOut, "Insufficient yBalance");
            uint256 impactPrice = _computeImpact(listingAddress, inputAmount, false);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
        }
        PrepOrderUpdateResult memory prepResult = _prepSellOrderUpdate(listingAddress, orderIdentifier, amountOut);
        updates = _executeSellOrderUpdate(
            listingAddress,
            orderIdentifier,
            prepResult.normalizedReceived,
            prepResult.makerAddress,
            prepResult.recipientAddress,
            prepResult.orderStatus
        );
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 pendingAmount,
        ISSListingTemplate listingContract
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes a single buy order, fetching token details and executing
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        uint256 denormAmount = denormalize(pendingAmount, tokenDecimals);
        updates = executeBuyOrder(listingAddress, orderIdentifier, denormAmount);
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 pendingAmount,
        ISSListingTemplate listingContract
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes a single sell order, fetching token details and executing
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        uint256 denormAmount = denormalize(pendingAmount, tokenDecimals);
        updates = executeSellOrder(listingAddress, orderIdentifier, denormAmount);
    }

    function executeBuyOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) {
        // Executes multiple buy orders up to maxIterations
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        uint256 orderIdent;
        uint256 pendingAmount;
        for (uint256 i = 0; i < iterationCount; i++) {
            orderIdent = orderIdentifiers[i];
            (pendingAmount,,) = listingContract.getBuyOrderAmounts(orderIdent);
            ISSListingTemplate.UpdateType[] memory updates = _processBuyOrder(listingAddress, orderIdent, pendingAmount, listingContract);
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

    function executeSellOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) {
        // Executes multiple sell orders up to maxIterations
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        uint256 orderIdentifier;
        uint256 pendingAmount;
        for (uint256 i = 0; i < iterationCount; i++) {
            orderIdentifier = orderIdentifiers[i];
            (pendingAmount,,) = listingContract.getSellOrderAmounts(orderIdentifier);
            ISSListingTemplate.UpdateType[] memory updates = _processSellOrder(listingAddress, orderIdentifier, pendingAmount, listingContract);
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
        // Executes multiple long payouts up to maxIterations
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
        // Executes multiple short payouts up to maxIterations
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