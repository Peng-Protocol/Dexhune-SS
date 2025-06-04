// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.27
// Changes:
// - v0.0.27: Fixed stack-too-deep in _prepBuyLiquidUpdates by adding _createBuyOrderUpdates helper, using BuyOrderUpdateContext struct for _prepBuyOrderUpdate outputs, and applying scoped blocks (lines 305-320).
// - v0.0.26: Fixed ParserError in settleSellLiquid by removing erroneous 'yul' identifier from finalUpdates declaration (line 460).
// - v0.0.25: Fixed stack-too-deep in _prepSellLiquidUpdates by adding _createSellOrderUpdates helper, using SellOrderUpdateContext struct for _prepSellOrderUpdate outputs, reusing _checkPricing, and applying scoped blocks. Corrected import path to "./utils/SSSettlementPartial.sol" (lines 8, 335-350).
// - v0.0.24: Fixed stack-too-deep in executeSingleBuyLiquid by adding _prepBuyLiquidUpdates and _checkPricing helpers, using OrderContext struct, and applying scoped blocks, inspired by MFPRouter.sol v0.0.27 (lines 260-300).
// - v0.0.23: Fixed stack-too-deep in executeSingleSellLiquid by introducing OrderContext struct, adding _prepSellLiquidUpdates helper, using scoped blocks, and reusing _prepareLiquidityTransaction/_updateLiquidity, inspired by MFPRouter.sol v0.0.27 (lines 260-300).
// - v0.0.22: Fixed DeclarationError in createSellOrder by replacing tokenBAddress with tokenAAddress in postBalance calculation, aligning with sell order tokenA input (line 199).
// - v0.0.21: Removed isValidListing[listing] = true from initializeListing, as isValidListing mapping was removed from SSMainPartial.sol (v0.0.14). Validation now relies solely on checkValidListing via onlyValidListing modifier (line 140).
// - v0.0.20: Fixed stack-too-deep in settleBuyLiquid and settleSellLiquid by adding helpers executeSingleBuyLiquid and executeSingleSellLiquid. Added _updateOrderCore and _updateOrderAmounts to split UpdateType creation. Updated settleBuyLiquid and settleSellLiquid to use helpers with try-catch (lines 260-380). Removed redundant mapping accesses (liquidityAddress, tokenA, tokenB, decimalsA, decimalsB), fetching from ISSListingTemplate. Simplified initializeListing to set only isValidListing (lines 140-150).
// - v0.0.19: Fixed TypeError in claimFees by changing listing parameter from uint256 to address (lines 340-343). Fixed TypeError in withdraw by reverting to xPrepOut/yPrepOut and xExecuteOut/yExecuteOut (lines 350-353).
// - v0.0.18: Fixed ParserError in checkValidListing by removing duplicate 'public' visibility, changed to 'external view' (line 371).
// - v0.0.17: Aligned settleBuyLiquid and settleSellLiquid with settleBuyOrders/settleSellOrders. Changed signatures to accept maxIterations, iterate over activeBuyOrders/activeSellOrders, use liquidity balances for settlement, transfer principal (tokenB for buy, tokenA for sell) to liquidityAddress[listing], update order states and xLiquid/yLiquid via updateLiquidity. Reused _prepBuyOrderUpdate/_executeBuyOrderUpdate and _prepSellOrderUpdate/_executeSellOrderUpdate for consistency.
// - v0.0.16: Fixed stack too deep in settleBuyLiquid and settleSellLiquid by extracting logic to helpers: _prepareLiquidityTransaction, _executeLiquidityTransaction, _updateLiquidity. Reduced local variables to ~6 per function.
// - v0.0.15: Integrated impact price into settleBuyLiquid and settleSellLiquid to compute amountOut, aligning with token flow: tokenB in/tokenA out for buy, tokenA in/tokenB out for sell.
// - v0.0.14: Added payable modifier to createBuyOrder and createSellOrder to fix TypeError for msg.value usage with ETH.
// - v0.0.13: Fixed TypeError in initializeListing by using distinct local variable names (tokenAAddress, tokenBAddress). Updated liquidityAddress assignment to call listingTemplate.liquidityAddressView().
// - v0.0.12: Removed setRegistry and registryAddress references, moved to ISSListingTemplate.
// - v0.0.11: Removed listingAgent state variable and setListingAgent, using inherited agent and setAgent from SSMainPartial.sol (v0.0.10).
// - v0.0.10: Renamed _listingAgent parameter in setListingAgent to newListingAgent for clarity.
// - v0.0.9: Fixed TypeError in liquidShortPayout by using payout.amount instead of payout.required.
// - v0.0.8: Renamed isValidListing function to checkValidListing to resolve conflict with isValidListing state variable.
// - v0.0.7: Removed ISSAgent.globalizeOrders and globalizeLiquidity calls, handled by SSListingTemplate/SSLiquidityTemplate.
// - v0.0.7: Added setRegistry, registryAddress mapping in SSMainPartial.
// - v0.0.7: Removed setRouters from initializeListing, checked via ISSLiquidityTemplate.routers.
// - v0.0.7: Added liquidity functions (deposit, withdraw, claimFees, changeSlotDepositor) for SSLiquidityTemplate v0.0.4.
// - v0.0.7: Updated initializeListing to validate listing via ISSAgent.getListing.
// Compatible with SSListingTemplate.sol (v0.0.8), SSLiquidityTemplate.sol (v0.0.4), SSSettlementPartial.sol (v0.0.21).

import "./utils/SSSettlementPartial.sol";

contract SSRouter is SSSettlementPartial {
    // Struct to group common variables and reduce stack usage
    struct OrderContext {
        ISSListingTemplate listingContract;
        address tokenIn;
        address tokenOut;
        address liquidityAddr;
    }

    // Struct to store _prepSellOrderUpdate outputs
    struct SellOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    // Struct to store _prepBuyOrderUpdate outputs
    struct BuyOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    event ListingInitialized(address listing);

    // Checks pricing constraints for an order
    function _checkPricing(
        address listing,
        uint256 orderId,
        bool isBuy,
        uint256 pending
    ) internal view returns (bool) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256 maxPrice;
        uint256 minPrice;
        if (isBuy) {
            (maxPrice, minPrice) = listingContract.getBuyOrderPricing(orderId);
        } else {
            (maxPrice, minPrice) = listingContract.getSellOrderPricing(orderId);
        }
        uint256 impactPrice = _computeImpact(listing, pending, isBuy);
        return impactPrice <= maxPrice && impactPrice >= minPrice;
    }

    // Prepares liquidity transaction by validating amounts and computing impact price
    function _prepareLiquidityTransaction(
        address listing,
        uint256 amount,
        bool isBuy
    ) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        uint256 impactPrice = _computeImpact(listing, amount, isBuy);
        if (isBuy) {
            // Buy: tokenB in, tokenA out
            require(yAmount >= amount, "Insufficient y liquidity");
            tokenIn = listingContract.tokenB();
            tokenOut = listingContract.tokenA();
            amountOut = (amount * impactPrice) / 1e18;
        } else {
            // Sell: tokenA in, tokenB out
            require(xAmount >= amount, "Insufficient x liquidity");
            tokenIn = listingContract.tokenA();
            tokenOut = listingContract.tokenB();
            amountOut = (amount * 1e18) / impactPrice;
        }
    }

    // Executes token transaction and returns received amount
    function _executeLiquidityTransaction(
        address listing,
        address tokenOut,
        uint256 amountOut,
        address recipient
    ) internal returns (uint256 amountReceived) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256 preBalance = tokenOut == address(0) ? address(this).balance : IERC20(tokenOut).balanceOf(address(this));
        // Transact: tokenA out for buy, tokenB out for sell
        listingContract.transact(address(this), tokenOut, amountOut, recipient);
        uint256 postBalance = tokenOut == address(0) ? address(this).balance : IERC20(tokenOut).balanceOf(address(this));
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
    }

    // Transfers principal to liquidityAddress and updates liquidity
    function _updateLiquidity(
        address listing,
        address tokenIn,
        bool isX,
        uint256 amount
    ) internal {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        address liquidityAddr = listingContract.liquidityAddressView();
        if (tokenIn == address(0)) {
            // Transfer ETH principal to liquidityAddress
            (bool success, ) = liquidityAddr.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Transfer ERC20 principal to liquidityAddress
            IERC20(tokenIn).transfer(liquidityAddr, amount);
        }
        // Update liquidity: tokenB in for buy (isX=false), tokenA in for sell (isX=true)
        ISSLiquidityTemplate(liquidityAddr).updateLiquidity(address(this), isX, amount);
    }

    // Updates order core (maker, recipient, status)
    function _updateOrderCore(
        uint256 orderId,
        address makerAddress,
        address recipient,
        uint8 status,
        bool isBuy,
        uint256 pendingAmount,
        uint256 normalizedReceived
    ) internal pure returns (ISSListingTemplate.UpdateType memory) {
        return ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: status == 1 && normalizedReceived >= pendingAmount ? 3 : 2,
            addr: makerAddress,
            recipient: recipient,
            maxPrice: 0,
            minPrice: 0
        });
    }

    // Updates order amounts (normalizedReceived)
    function _updateOrderAmounts(
        uint256 orderId,
        uint256 normalizedReceived,
        bool isBuy
    ) internal pure returns (ISSListingTemplate.UpdateType memory) {
        return ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 2,
            index: orderId,
            value: normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
    }

    // Creates buy order updates
    function _createBuyOrderUpdates(
        uint256 orderId,
        BuyOrderUpdateContext memory updateContext,
        uint256 pending
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = _updateOrderAmounts(orderId, updateContext.normalizedReceived, true);
        updates[1] = _updateOrderCore(
            orderId,
            updateContext.makerAddress,
            updateContext.recipient,
            updateContext.status,
            true,
            pending,
            updateContext.normalizedReceived
        );
        return updates;
    }

    // Creates sell order updates
    function _createSellOrderUpdates(
        uint256 orderId,
        SellOrderUpdateContext memory updateContext,
        uint256 pending
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = _updateOrderAmounts(orderId, updateContext.normalizedReceived, false);
        updates[1] = _updateOrderCore(
            orderId,
            updateContext.makerAddress,
            updateContext.recipient,
            updateContext.status,
            false,
            pending,
            updateContext.normalizedReceived
        );
        return updates;
    }

    function initializeListing(address listing) external onlyOwner {
        ISSListingTemplate listingTemplate = ISSListingTemplate(listing);
        address agentAddress = listingTemplate.agent();
        require(agentAddress != address(0), "Agent not set");
        address tokenAAddress = listingTemplate.tokenA();
        address tokenBAddress = listingTemplate.tokenB();
        require(ISSAgent(agentAddress).getListing(tokenAAddress, tokenBAddress) == listing, "Invalid listing");
        emit ListingInitialized(listing);
    }

    function createBuyOrder(
        address listing,
        address recipient,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        OrderPrep memory prep = _handleOrderPrep(
            listing,
            msg.sender,
            recipient,
            amount,
            maxPrice,
            minPrice,
            true
        );
        address tokenBAddress = listingContract.tokenB();
        uint256 preBalance = tokenBAddress == address(0) ? address(this).balance : 0;
        if (tokenBAddress == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(tokenBAddress).transferFrom(msg.sender, address(this), amount);
        }
        uint256 postBalance = tokenBAddress == address(0) ? address(this).balance : IERC20(tokenBAddress).balanceOf(address(this));
        uint256 amountReceived = postBalance - preBalance;
        require(amountReceived >= amount, "Insufficient tokens received");
        _executeSingleOrder(listing, prep, true);
    }

    function createSellOrder(
        address listing,
        address recipient,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        OrderPrep memory prep = _handleOrderPrep(
            listing,
            msg.sender,
            recipient,
            amount,
            maxPrice,
            minPrice,
            false
        );
        address tokenAAddress = listingContract.tokenA();
        uint256 preBalance = tokenAAddress == address(0) ? address(this).balance : 0;
        if (tokenAAddress == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(tokenAAddress).transferFrom(msg.sender, address(this), amount);
        }
        uint256 postBalance = tokenAAddress == address(0) ? address(this).balance : IERC20(tokenAAddress).balanceOf(address(this));
        uint256 amountReceived = postBalance - preBalance;
        require(amountReceived >= amount, "Insufficient tokens received");
        _executeSingleOrder(listing, prep, false);
    }

    function settleBuyOrders(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeBuyOrders(listing, maxIterations);
    }

    function settleSellOrders(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeSellOrders(listing, maxIterations);
    }

    // Prepares buy liquid updates, reducing stack usage
    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderId,
        uint256 pending
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Check pricing
        if (!_checkPricing(address(context.listingContract), orderId, true, pending)) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        // Prepare liquidity and compute amountOut
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        {
            (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
                address(context.listingContract),
                pending,
                true
            );
        }
        // Execute order update
        BuyOrderUpdateContext memory updateContext;
        {
            address tokenAddress;
            uint8 decimals;
            (tokenAddress, decimals, updateContext.makerAddress, updateContext.recipient, updateContext.status, updateContext.amountReceived, updateContext.normalizedReceived) = _prepBuyOrderUpdate(address(context.listingContract), orderId, amountOut);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        // Transfer principal (tokenB) and update liquidity
        _updateLiquidity(address(context.listingContract), tokenIn, false, updateContext.amountReceived);
        // Create updates
        ISSListingTemplate.UpdateType[] memory updates = _createBuyOrderUpdates(orderId, updateContext, pending);
        orderPendingAmounts[address(context.listingContract)][orderId] -= updateContext.normalizedReceived;
        return updates;
    }

    function executeSingleBuyLiquid(
        address listing,
        uint256 orderId
    ) public returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256 pending;
        (pending, ) = listingContract.getBuyOrderAmounts(orderId);
        if (pending == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenB(),
            tokenOut: listingContract.tokenA(),
            liquidityAddr: listingContract.liquidityAddressView()
        });
        return _prepBuyLiquidUpdates(context, orderId, pending);
    }

    // Prepares sell liquid updates, reducing stack usage
    function _prepSellLiquidUpdates(
        OrderContext memory context,
        uint256 orderId,
        uint256 pending
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        // Check pricing
        if (!_checkPricing(address(context.listingContract), orderId, false, pending)) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        // Prepare liquidity and compute amountOut
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        {
            (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
                address(context.listingContract),
                pending,
                false
            );
        }
        // Execute order update
        SellOrderUpdateContext memory updateContext;
        {
            address tokenAddress;
            uint8 decimals;
            (tokenAddress, decimals, updateContext.makerAddress, updateContext.recipient, updateContext.status, updateContext.amountReceived, updateContext.normalizedReceived) = _prepSellOrderUpdate(address(context.listingContract), orderId, amountOut);
        }
        if (updateContext.normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        // Transfer principal (tokenA) and update liquidity
        _updateLiquidity(address(context.listingContract), tokenIn, true, updateContext.amountReceived);
        // Create updates
        ISSListingTemplate.UpdateType[] memory updates = _createSellOrderUpdates(orderId, updateContext, pending);
        orderPendingAmounts[address(context.listingContract)][orderId] -= updateContext.normalizedReceived;
        return updates;
    }

    function executeSingleSellLiquid(
        address listing,
        uint256 orderId
    ) public returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256 pending;
        (pending, ) = listingContract.getSellOrderAmounts(orderId);
        if (pending == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.tokenA(),
            tokenOut: listingContract.tokenB(),
            liquidityAddr: listingContract.liquidityAddressView()
        });
        return _prepSellLiquidUpdates(context, orderId, pending);
    }

    function settleBuyLiquid(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256[] storage orders = activeBuyOrders[listing];
        uint256 processed = 0;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](orders.length * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < orders.length && processed < maxIterations; ) {
            uint256 orderId = orders[i];
            try this.executeSingleBuyLiquid(listing, orderId) returns (ISSListingTemplate.UpdateType[] memory updates) {
                if (updates.length == 0) {
                    i++;
                    continue;
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[updateIndex++] = updates[j];
                }
                processed++;
                if (orderPendingAmounts[listing][orderId] == 0) {
                    orders[i] = orders[orders.length - 1];
                    orders.pop();
                } else {
                    i++;
                }
            } catch {
                i++;
                continue;
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

    function settleSellLiquid(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256[] storage orders = activeSellOrders[listing];
        uint256 processed = 0;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](orders.length * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < orders.length && processed < maxIterations; ) {
            uint256 orderId = orders[i];
            try this.executeSingleSellLiquid(listing, orderId) returns (ISSListingTemplate.UpdateType[] memory updates) {
                if (updates.length == 0) {
                    i++;
                    continue;
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[updateIndex++] = updates[j];
                }
                processed++;
                if (orderPendingAmounts[listing][orderId] == 0) {
                    orders[i] = orders[orders.length - 1];
                    orders.pop();
                } else {
                    i++;
                }
            } catch {
                i++;
                continue;
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

    function settleLongPayout(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeLongPayouts(listing, maxIterations);
    }

    function settleShortPayout(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeShortPayouts(listing, maxIterations);
    }

    function liquidLongPayout(address listing, uint256 orderId) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.LongPayoutStruct memory payout = listingContract.getLongPayout(orderId);
        require(payout.required > 0, "No payout required");
        _processPayoutUpdate(listing, orderId, payout.required, true);
    }

    function liquidShortPayout(address listing, uint256 orderId) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.ShortPayoutStruct memory payout = listingContract.getShortPayout(orderId);
        require(payout.amount > 0, "No payout required");
        _processPayoutUpdate(listing, orderId, payout.amount, false);
    }

    function deposit(address listing, address token, uint256 amount) external payable onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        address tokenAAddress = listingContract.tokenA();
        address tokenBAddress = listingContract.tokenB();
        require(token == tokenAAddress || token == tokenBAddress, "Invalid token");
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            liquidityContract.deposit{value: amount}(address(this), token, amount);
        } else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
            IERC20(token).approve(address(liquidityContract), amount);
            liquidityContract.deposit(address(this), token, amount);
        }
    }

    function claimFees(address listing, uint256 liquidityIndex, bool isX, uint256 volume) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        liquidityContract.claimFees(address(this), listing, liquidityIndex, isX, volume);
    }

    function withdraw(address listing, uint256 amount, uint256 index, bool isX) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        ISSLiquidityTemplate.PreparedWithdrawal memory withdrawal = isX
            ? liquidityContract.xPrepOut(address(this), amount, index)
            : liquidityContract.yPrepOut(address(this), amount, index);
        isX
            ? liquidityContract.xExecuteOut(address(this), index, withdrawal)
            : liquidityContract.yExecuteOut(address(this), index, withdrawal);
    }

    function changeLiquiditySlotDepositor(address listing, bool isX, uint256 slotIndex, address newDepositor) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(newDepositor != address(0), "Invalid new depositor");
        liquidityContract.changeSlotDepositor(address(this), isX, slotIndex, newDepositor);
    }

    function clearSingleOrder(address listing, uint256 orderId, bool isBuy) external onlyValidListing(listing) nonReentrant {
        _clearOrderData(listing, orderId, isBuy);
    }

    function clearOrders(address listing, uint256[] memory orderIds, bool[] memory isBuyIds) external onlyValidListing(listing) nonReentrant {
        for (uint256 i = 0; i < orderIds.length; i++) {
            _clearOrderData(listing, orderIds[i], isBuyIds[i]);
        }
    }
}