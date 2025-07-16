// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.2;

// Version: 0.0.62
// Changes:
// - v0.0.62: Modified withdraw, claimFees, and changeDepositor to use msg.sender instead of user parameter for enhanced security and interface simplicity.
// - v0.0.61: Modified clearSingleOrder to enforce maker-only cancellation via _clearOrderData’s maker check.
// - v0.0.61: Updated clearOrders to cancel only msg.sender’s orders using makerPendingOrdersView, respecting maxIterations.
// - v0.0.60: Fixed stack-too-deep error in settleBuyOrders and settleSellOrders by introducing _processBuyOrder and _processSellOrder helpers, reducing stack usage to ~12 variables. Ensured explicit destructuring of getBuyOrderAmounts and getSellOrderAmounts.
// - v0.0.59: Fixed TypeError in _prepBuyOrderUpdate and _prepSellOrderUpdate by using PrepOrderUpdateResult struct. Fixed tuple destructuring mismatch in settleBuyOrders, settleSellOrders, executeSingleBuyLiquid, and executeSingleSellLiquid.
// - v0.0.58: Fixed ParserError in createSellOrder by correcting OrderPrep declaration and removing redundant casts.
// - v0.0.57: Added settleLongLiquid and settleShortLiquid from v0.0.44, integrated with settleSingleLongLiquid and settleSingleShortLiquid in SSSettlementPartial.sol v0.0.51.
// - v0.0.56: Fixed TypeError by replacing liquidityContract.addresses(address(this)) with liquidityContract.routers(address(this)).
// - v0.0.55: Added amountSent to BuyOrderAmounts, SellOrderAmounts, and UpdateType structs.
// - v0.0.54: Fixed stack depth in _prepBuyLiquidUpdates and _prepSellLiquidUpdates.
// - v0.0.53: Replaced safeTransferFrom with transferFrom in _checkAndTransferPrincipal.
// - v0.0.52: Added pre/post balance checks in _checkAndTransferPrincipal.
// Compatible with SSListingTemplate.sol (v0.0.10), SSLiquidityTemplate.sol (v0.0.6), SSMainPartial.sol (v0.0.25), SSSettlementPartial.sol (v0.0.57), SSOrderPartial.sol (v0.0.19).

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
        uint256 amountSent;
    }

    struct BuyOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
    }

    function _checkAndTransferPrincipal(
        address listingAddress,
        address tokenIn,
        uint256 inputAmount,
        address liquidityAddr,
        ISSListingTemplate listingContract
    ) internal returns (uint256 actualAmount, uint8 tokenDecimals) {
        // Checks and transfers principal amount, tracking actual amounts sent/received
        tokenDecimals = tokenIn == address(0) ? 18 : IERC20(tokenIn).decimals();
        uint256 listingPreBalance = tokenIn == address(0)
            ? listingAddress.balance
            : IERC20(tokenIn).balanceOf(listingAddress);
        uint256 liquidityPreBalance = tokenIn == address(0)
            ? liquidityAddr.balance
            : IERC20(tokenIn).balanceOf(liquidityAddr);
        try listingContract.transact(address(this), tokenIn, inputAmount, liquidityAddr) {} catch {
            revert("Principal transfer failed");
        }
        uint256 listingPostBalance = tokenIn == address(0)
            ? listingAddress.balance
            : IERC20(tokenIn).balanceOf(listingAddress);
        uint256 liquidityPostBalance = tokenIn == address(0)
            ? liquidityAddr.balance
            : IERC20(tokenIn).balanceOf(liquidityAddr);
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
        // Transfers tokens and normalizes received amount based on decimals
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
        // Validates order pricing against max/min price constraints
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
        // Prepares liquidity transaction, calculating output amount
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
        // Updates liquidity pool with transferred tokens
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        uint256 actualAmount;
        uint8 tokenDecimals;
        (actualAmount, tokenDecimals) = _checkAndTransferPrincipal(
            listingAddress,
            tokenIn,
            inputAmount,
            liquidityAddr,
            listingContract
        );
        uint256 normalizedAmount = normalize(actualAmount, tokenDecimals);
        require(normalizedAmount > 0, "Normalized amount is zero");
        try liquidityContract.updateLiquidity(address(this), isX, normalizedAmount) {} catch {
            revert("Liquidity update failed");
        }
    }

    function _createBuyOrderUpdates(
        uint256 orderIdentifier,
        BuyOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        // Creates update structs for buy order processing
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: 1,
            structId: 2,
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: updateContext.amountSent
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: 1,
            structId: 0,
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _createSellOrderUpdates(
        uint256 orderIdentifier,
        SellOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        // Creates update structs for sell order processing
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: 2,
            structId: 2,
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: updateContext.amountSent
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: 2,
            structId: 0,
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Prepares updates for buy order liquidation
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
            PrepOrderUpdateResult memory prepResult = _prepBuyOrderUpdate(
                address(context.listingContract),
                orderIdentifier,
                amountOut
            );
            updateContext.makerAddress = prepResult.makerAddress;
            updateContext.recipient = prepResult.recipientAddress;
            updateContext.status = prepResult.orderStatus;
            updateContext.amountReceived = prepResult.amountReceived;
            updateContext.normalizedReceived = prepResult.normalizedReceived;
            updateContext.amountSent = prepResult.amountSent;
            uint8 tokenDecimals = prepResult.tokenDecimals;
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
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
        // Prepares updates for sell order liquidation
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
            PrepOrderUpdateResult memory prepResult = _prepSellOrderUpdate(
                address(context.listingContract),
                orderIdentifier,
                amountOut
            );
            updateContext.makerAddress = prepResult.makerAddress;
            updateContext.recipient = prepResult.recipientAddress;
            updateContext.status = prepResult.orderStatus;
            updateContext.amountReceived = prepResult.amountReceived;
            updateContext.normalizedReceived = prepResult.normalizedReceived;
            updateContext.amountSent = prepResult.amountSent;
            uint8 tokenDecimals = prepResult.tokenDecimals;
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
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
        // Creates a buy order, transfers input tokens, and executes
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
        // Creates a sell order, transfers input tokens, and executes
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        OrderPrep memory orderPrep = _handleOrderPrep(
            listingAddress,
            msg.sender,
            recipientAddress,
            inputAmount,
            maxPrice,
            minPrice,
            false
        );
        address tokenAAddress = listingContract.tokenA();
        (orderPrep.amountReceived, orderPrep.normalizedReceived) = _checkTransferAmount(
            tokenAAddress,
            msg.sender,
            listingAddress,
            inputAmount
        );
        _executeSingleOrder(listingAddress, orderPrep, false);
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate listingContract
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes a single buy order, handling token decimals and execution
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (address tokenAddr, uint8 tokenDec) = _getTokenAndDecimals(listingAddress, true);
        uint256 denormAmount = denormalize(pendingAmount, tokenDec);
        updates = executeBuyOrder(listingAddress, orderIdentifier, denormAmount);
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ISSListingTemplate listingContract
    ) internal returns (ISSListingTemplate.UpdateType[] memory updates) {
        // Processes a single sell order, handling token decimals and execution
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
        if (pendingAmount == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        (address tokenAddr, uint8 tokenDec) = _getTokenAndDecimals(listingAddress, false);
        uint256 denormAmount = denormalize(pendingAmount, tokenDec);
        updates = executeSellOrder(listingAddress, orderIdentifier, denormAmount);
    }

    function settleBuyOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple buy orders up to maxIterations, using helper to reduce stack usage
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdent = orderIdentifiers[i];
            ISSListingTemplate.UpdateType[] memory updates = _processBuyOrder(listingAddress, orderIdent, listingContract);
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
        // Settles multiple sell orders up to maxIterations, using helper to reduce stack usage
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdent = orderIdentifiers[i];
            ISSListingTemplate.UpdateType[] memory updates = _processSellOrder(listingAddress, orderIdent, listingContract);
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
        // Executes a single buy order liquidation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getBuyOrderAmounts(orderIdentifier);
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
        // Executes a single sell order liquidation
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.getSellOrderAmounts(orderIdentifier);
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

    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple buy order liquidations up to maxIterations
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
        // Settles multiple sell order liquidations up to maxIterations
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
        // Settles multiple long liquidations up to maxIterations
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
        // Settles multiple short liquidations up to maxIterations
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
        // Executes long payouts
        executeLongPayouts(listingAddress, maxIterations);
    }

    function settleShortPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Executes short payouts
        executeShortPayouts(listingAddress, maxIterations);
    }

    function deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user) external payable onlyValidListing(listingAddress) nonReentrant {
        // Deposits tokens or ETH to liquidity pool
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

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX) external onlyValidListing(listingAddress) nonReentrant {
        // Withdraws tokens from liquidity pool for msg.sender
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        ISSLiquidityTemplate.PreparedWithdrawal memory withdrawal;
        if (isX) {
            try liquidityContract.xPrepOut(msg.sender, inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.xExecuteOut(msg.sender, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        } else {
            try liquidityContract.yPrepOut(msg.sender, inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.yExecuteOut(msg.sender, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount) external onlyValidListing(listingAddress) nonReentrant {
        // Claims fees from liquidity pool for msg.sender
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        try liquidityContract.claimFees(msg.sender, listingAddress, liquidityIndex, isX, volumeAmount) {} catch {
            revert("Claim fees failed");
        }
    }

    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external onlyValidListing(listingAddress) nonReentrant {
        // Clears a single order, maker check enforced in _clearOrderData
        _clearOrderData(listingAddress, orderIdentifier, isBuyOrder);
    }

    function clearOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Clears multiple orders for msg.sender up to maxIterations
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        uint256[] memory orderIds = listingContract.makerPendingOrdersView(msg.sender);
        uint256 iterationCount = maxIterations < orderIds.length ? maxIterations : orderIds.length;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderId = orderIds[i];
            bool isBuyOrder = false;
            (address maker,,) = listingContract.getBuyOrderCore(orderId);
            if (maker == msg.sender) {
                isBuyOrder = true;
            } else {
                (,maker,) = listingContract.getSellOrderCore(orderId);
                if (maker != msg.sender) {
                    continue;
                }
            }
            _clearOrderData(listingAddress, orderId, isBuyOrder);
        }
    }

    function changeDepositor(
        address listingAddress,
        bool isX,
        uint256 slotIndex,
        address newDepositor
    ) external onlyValidListing(listingAddress) nonReentrant {
        // Changes depositor for a liquidity slot for msg.sender
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(msg.sender != address(0), "Invalid caller address");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor) {} catch {
            revert("Failed to change depositor");
        }
    }
}