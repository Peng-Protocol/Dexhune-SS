// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.44 (Updated)
// Changes:
// - v0.0.44: Modified caller handling in changeDepositor, deposit, withdraw, claimFees to pass user parameter as caller to SSLiquidityTemplate, representing the actual user (e.g., slot owner). Ensured msg.sender is router. Updated to align with SSLiquidityTemplate.sol v0.0.6.
// - v0.0.43: Removed onlyValidListing modifier, inherited from SSMainPartial.sol to resolve TypeError.
// - v0.0.43: Replaced safeTransferFrom with transferFrom in _checkTransferAmount and deposit.
// - v0.0.43: Added pre/post balance checks in deposit for fee-on-transfer tokens.
// - v0.0.43: Changed deposit to use bool isTokenA instead of tokenAddress.
// - v0.0.42: Added onlyValidListing modifier to validate listingAddress and tokens.
// - v0.0.41: Split _updateLiquidity logic to reduce stack depth. Added _checkAndTransferPrincipal helper.
// - v0.0.40: Modified _updateLiquidity to check balances before/after transfer.
// - v0.0.39: Fixed TypeError in settleSingleLongLiquid and settleSingleShortLiquid.
// - v0.0.38: Removed post-transfer balance checks in settlement functions.
// - v0.0.37: Added denormalization of amounts before transfers.
// - v0.0.36: Refactored settleLongLiquid and settleShortLiquid to use new helpers.

import "./utils/SSSettlementPartial.sol";

contract SSRouter is SSSettlementPartial {
    using SafeERC20 for IERC20;

    struct OrderContext {
        ISSListingTemplate listingContract;
        address tokenIn;
        address tokenOut;
        address liquidityAddr;
    }

    struct SellOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    struct BuyOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    function _checkAndTransferPrincipal(
        address listingAddress,
        address tokenIn,
        uint256 inputAmount,
        address liquidityAddr,
        ISSListingTemplate listingContract
    ) internal returns (uint256 actualAmount, uint8 tokenDecimals) {
        // Get token decimals for normalization
        tokenDecimals = tokenIn == address(0) ? 18 : IERC20(tokenIn).decimals();
        
        // Check balances before transfer
        uint256 listingPreBalance = tokenIn == address(0)
            ? listingAddress.balance
            : IERC20(tokenIn).balanceOf(listingAddress);
        uint256 liquidityPreBalance = tokenIn == address(0)
            ? liquidityAddr.balance
            : IERC20(tokenIn).balanceOf(liquidityAddr);
        
        // Attempt to transfer principal from listing to liquidity
        try listingContract.transact(address(this), tokenIn, inputAmount, liquidityAddr) {} catch {
            revert("Principal transfer failed");
        }
        
        // Check balances after transfer
        uint256 listingPostBalance = tokenIn == address(0)
            ? listingAddress.balance
            : IERC20(tokenIn).balanceOf(listingAddress);
        uint256 liquidityPostBalance = tokenIn == address(0)
            ? liquidityAddr.balance
            : IERC20(tokenIn).balanceOf(liquidityAddr);
        
        // Compute actual amount moved
        uint256 amountSent = listingPreBalance > listingPostBalance 
            ? listingPreBalance - listingPostBalance 
            : 0;
        uint256 amountReceived = liquidityPostBalance > liquidityPreBalance 
            ? liquidityPostBalance - liquidityPreBalance 
            : 0;
        require(amountSent > 0, "No amount sent from listing");
        require(amountReceived > 0, "No amount received by liquidity");
        actualAmount = amountSent < amountReceived ? amountSent : amountReceived;
    }

    function _checkTransferAmount(
        address tokenAddress,
        address from,
        address to,
        uint256 inputAmount
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        ISSListingTemplate listingContract = ISSListingTemplate(to);
        uint8 tokenDecimals = tokenAddress == address(0) ? 18 : IERC20(tokenAddress).decimals();
        uint256 preBalance = tokenAddress == address(0)
            ? to.balance
            : IERC20(tokenAddress).balanceOf(to);
        if (tokenAddress == address(0)) {
            require(msg.value == inputAmount, "Incorrect ETH amount");
            listingContract.transact{value: inputAmount}(address(this), tokenAddress, inputAmount, to);
        } else {
            IERC20(tokenAddress).transferFrom(from, to, inputAmount);
        }
        uint256 postBalance = tokenAddress == address(0)
            ? to.balance
            : IERC20(tokenAddress).balanceOf(to);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, tokenDecimals) : 0;
        require(amountReceived > 0, "No tokens received");
    }

    function _checkPricing(
        address listingAddress,
        uint256 orderIdentifier,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal view returns (bool) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256 maxPrice;
        uint256 minPrice;
        if (isBuyOrder) {
            (maxPrice, minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        } else {
            (maxPrice, minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        }
        uint256 impactPrice = _computeImpact(listingAddress, pendingAmount, isBuyOrder);
        return impactPrice <= maxPrice && impactPrice >= minPrice;
    }

    function _prepareLiquidityTransaction(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        uint256 impactPrice = _computeImpact(listingAddress, inputAmount, isBuyOrder);
        if (isBuyOrder) {
            require(xAmount >= inputAmount, "Insufficient x liquidity");
            tokenIn = listingContract.tokenB();
            tokenOut = listingContract.tokenA();
            amountOut = (inputAmount * impactPrice) / 1e18;
        } else {
            require(yAmount >= inputAmount, "Insufficient y liquidity");
            tokenIn = listingContract.tokenA();
            tokenOut = listingContract.tokenB();
            amountOut = (inputAmount * 1e18) / impactPrice;
        }
    }

    function _updateLiquidity(
        address listingAddress,
        address tokenIn,
        bool isX,
        uint256 inputAmount
    ) internal {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        
        // Use helper to check balances and transfer, reducing stack depth
        uint256 actualAmount;
        uint8 tokenDecimals;
        (actualAmount, tokenDecimals) = _checkAndTransferPrincipal(
            listingAddress,
            tokenIn,
            inputAmount,
            liquidityAddr,
            listingContract
        );
        
        // Normalize the actual amount moved for liquidity update
        uint256 normalizedAmount = normalize(actualAmount, tokenDecimals);
        require(normalizedAmount > 0, "Normalized amount is zero");
        
        // Update liquidity pool with the actual normalized amount moved
        try liquidityContract.updateLiquidity(address(this), isX, normalizedAmount) {} catch {
            revert("Liquidity update failed");
        }
    }

    function _createBuyOrderUpdates(
        uint256 orderIdentifier,
        BuyOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: 1,
            structId: 2,
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: 1,
            structId: 0,
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0
        });
        return updates;
    }

    function _createSellOrderUpdates(
        uint256 orderIdentifier,
        SellOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: 2,
            structId: 2,
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: 2,
            structId: 0,
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0
        });
        return updates;
    }

    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        if (!_checkPricing(address(context.listingContract), orderIdentifier, true, pendingAmount)) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        {
            (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
                address(context.listingContract),
                pendingAmount,
                true
            );
        }
        BuyOrderUpdateContext memory updateContext;
        {
            address tokenAddress;
            uint8 tokenDecimals;
            (tokenAddress, tokenDecimals, updateContext.makerAddress, updateContext.recipient, updateContext.status, updateContext.amountReceived, updateContext.normalizedReceived) = _prepBuyOrderUpdate(address(context.listingContract), orderIdentifier, amountOut);
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, false, pendingAmount);
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _prepSellLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        if (!_checkPricing(address(context.listingContract), orderIdentifier, false, pendingAmount)) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        {
            (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
                address(context.listingContract),
                pendingAmount,
                false
            );
        }
        SellOrderUpdateContext memory updateContext;
        {
            address tokenAddress;
            uint8 tokenDecimals;
            (tokenAddress, tokenDecimals, updateContext.makerAddress, updateContext.recipient, updateContext.status, updateContext.amountReceived, updateContext.normalizedReceived) = _prepSellOrderUpdate(address(context.listingContract), orderIdentifier, amountOut);
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, true, pendingAmount);
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function createBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        OrderPrep memory prep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            true
        );
        address tokenBAddress = listingContract.tokenB();
        (prep.amountReceived, prep.normalizedReceived) = _checkTransferAmount(
            tokenBAddress,
            msg.sender,
            listingAddress,
            inputAmount
        );
        _executeSingleOrder(listingAddress, prep, true);
    }

    function createSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        OrderPrep memory prep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            false
        );
        address tokenAAddress = listingContract.tokenA();
        (prep.amountReceived, prep.normalizedReceived) = _checkTransferAmount(
            tokenAAddress,
            msg.sender,
            listingAddress,
            inputAmount
        );
        _executeSingleOrder(listingAddress, prep, false);
    }

    function settleBuyOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
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

    function settleSellOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
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

    function executeSingleBuyLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 pendingAmount,) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenB(),
            tokenOut: listingContract.tokenA(),
            liquidityAddr: listingContract.liquidityAddressView()
        });
        return _prepBuyLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function executeSingleSellLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 pendingAmount,) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenA(),
            tokenOut: listingContract.tokenB(),
            liquidityAddr: listingContract.liquidityAddressView()
        });
        return _prepSellLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function settleSingleLongLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.LongPayoutStruct memory longPayout = listingContract.getLongPayout(orderIdentifier);
        if (longPayout.required == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, true);
        context.recipientAddress = longPayout.recipientAddress;
        context.amountOut = denormalize(longPayout.required, context.tokenDecimals);
        if (!_checkLiquidityBalance(context, longPayout.required, true)) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), context.tokenOut, context.amountOut, context.recipientAddress) {} catch {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        uint256 normalizedReceived = normalize(context.amountOut, context.tokenDecimals);
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        return _createPayoutUpdate(normalizedReceived, longPayout.recipientAddress, true);
    }

    function settleSingleShortLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.ShortPayoutStruct memory shortPayout = listingContract.getShortPayout(orderIdentifier);
        if (shortPayout.amount == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        PayoutContext memory context = _prepPayoutContext(listingAddress, orderIdentifier, false);
        context.recipientAddress = shortPayout.recipientAddress;
        context.amountOut = denormalize(shortPayout.amount, context.tokenDecimals);
        if (!_checkLiquidityBalance(context, shortPayout.amount, false)) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), context.tokenOut, context.amountOut, context.recipientAddress) {} catch {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        uint256 normalizedReceived = normalize(context.amountOut, context.tokenDecimals);
        payoutPendingAmounts[listingAddress][orderIdentifier] -= normalizedReceived;
        return _createPayoutUpdate(normalizedReceived, shortPayout.recipientAddress, false);
    }

    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            ISSListingTemplate.UpdateType[] memory updates = executeSingleBuyLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length > 0) {
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[updateIndex++] = updates[j];
                }
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

    function settleSellLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            ISSListingTemplate.UpdateType[] memory updates = executeSingleSellLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length > 0) {
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[updateIndex++] = updates[j];
                }
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

    function settleLongLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        uint256[] memory orderIdentifiers = listingContract.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            ISSListingTemplate.PayoutUpdate[] memory updates = settleSingleLongLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function settleShortLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        uint256[] memory orderIdentifiers = listingContract.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            ISSListingTemplate.PayoutUpdate[] memory updates = settleSingleShortLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function settleLongPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        executeLongPayouts(listingAddress, maxIterations);
    }

    function settleShortPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        executeShortPayouts(listingAddress, maxIterations);
    }

    function deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user) external payable onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        address tokenAddress = isTokenA ? listingContract.tokenA() : listingContract.tokenB();
        if (tokenAddress == address(0)) {
            require(msg.value == inputAmount, "Incorrect ETH amount");
            try liquidityContract.deposit{value: inputAmount}(user, tokenAddress, inputAmount) {} catch {
                revert("Deposit failed");
            }
        } else {
            uint256 preBalance = IERC20(tokenAddress).balanceOf(address(this));
            IERC20(tokenAddress).transferFrom(msg.sender, address(this), inputAmount);
            uint256 postBalance = IERC20(tokenAddress).balanceOf(address(this));
            uint256 receivedAmount = postBalance - preBalance;
            require(receivedAmount > 0, "No tokens received");
            IERC20(tokenAddress).approve(liquidityAddr, receivedAmount);
            try liquidityContract.deposit(user, tokenAddress, receivedAmount) {} catch {
                revert("Deposit failed");
            }
        }
    }

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX, address user) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        ISSLiquidityTemplate.PreparedWithdrawal memory withdrawal;
        if (isX) {
            try liquidityContract.xPrepOut(user, inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.xExecuteOut(user, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        } else {
            try liquidityContract.yPrepOut(user, inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.yExecuteOut(user, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount, address user) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        try liquidityContract.claimFees(user, listingAddress, liquidityIndex, isX, volumeAmount) {} catch {
            revert("Claim fees failed");
        }
    }

    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external onlyValidListing(listingAddress) nonReentrant {
        _clearOrderData(listingAddress, orderIdentifier, isBuyOrder);
    }

    function clearOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory buyOrderIds = listingContract.pendingBuyOrdersView();
        uint256 buyIterationCount = maxIterations < buyOrderIds.length ? maxIterations : buyOrderIds.length;
        for (uint256 i = 0; i < buyIterationCount; i++) {
            _clearOrderData(listingAddress, buyOrderIds[i], true);
        }
        uint256[] memory sellOrderIds = listingContract.pendingSellOrdersView();
        uint256 sellIterationCount = maxIterations < sellOrderIds.length ? maxIterations : sellOrderIds.length;
        for (uint256 k = 0; k < sellIterationCount; k++) {
            _clearOrderData(listingAddress, sellOrderIds[k], false);
        }
    }

    function changeDepositor(
        address listingAddress,
        bool isX,
        uint256 slotIndex,
        address newDepositor,
        address user
    ) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(user, isX, slotIndex, newDepositor) {} catch {
            revert("Failed to change depositor");
        }
    }
}