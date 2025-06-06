// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.33 (Updated)
// Changes:
// - v0.0.33: Fixed TypeError in withdraw by replacing ternary operator in try/catch block with if/else to explicitly call xExecuteOut or yExecuteOut, ensuring compiler recognizes external calls (line 475).
// - v0.0.32: Fixed TypeError by adding amountReceived and normalizedReceived to OrderPrep struct in SSMainPartial.sol (v0.0.19). Replaced safeTransferFrom with transferFrom in _checkTransferAmount (line 62). Made ISSListingTemplate.transact payable in SSMainPartial.sol to allow ETH transfers (line 58). Simplified _checkTransferAmount to remove redundant transact call for ERC20 tokens. Removed try/catch in settleBuyLiquid and settleSellLiquid, using direct calls to executeSingleBuyLiquid and executeSingleSellLiquid (lines 367-394).
// - v0.0.31: Added pre/post balance checks in createBuyOrder and createSellOrder using _checkTransferAmount to ensure the amount withdrawn from the user to the listing matches inputAmount, accounting for tax on transfers. Updated OrderPrep struct to include amountReceived and normalizedReceived, adjusting _executeSingleOrder to use amountReceived for order creation. Modified _prepBuyLiquidUpdates and _prepSellLiquidUpdates to check recipient balances before/after ISSLiquidityTemplate.transact, updating orders with actual amountReceived (lines 200-250, 300-350, 400-450).
// - v0.0.30: Updated _prepBuyLiquidUpdates and _prepSellLiquidUpdates to check liquidityAddr balances for ISSLiquidityTemplate.transact calls, aligning with _executeTransaction fix in SSSettlementPartial.sol v0.0.23 (lines 350-400).
// - v0.0.29: Added changeDepositor function to wrap ISSLiquidityTemplate.changeSlotDepositor, allowing users to change the depositor of a liquidity slot (lines 600-620).
// - v0.0.28: Removed initializeListing and ListingInitialized event as they are redundant with onlyValidListing modifier (lines 140-150). Removed unused functions: liquidLongPayout, liquidShortPayout, changeLiquiditySlotDepositor (lines 380-400, 480-490). Changed visibility of executeSingleBuyLiquid, executeSingleSellLiquid to internal (lines 320-360). Removed redundant mappings from SSMainPartial.sol, querying SSListingTemplate view functions (lines 100-110). Integrated ISSListingTemplate.transact for fund transfers in createBuyOrder, createSellOrder, executeBuyOrder, executeSellOrder, clearOrderData (lines 200-250, 300-350, 400-450). Added ISSLiquidityTemplate.transact and updateLiquidity for liquid settlement fund flows in executeSingleBuyLiquid, executeSingleSellLiquid (lines 320-360). Added refund logic in _clearOrderData using ISSListingTemplate.transact (lines 500-520). Updated settleBuyLiquid, settleSellLiquid to query pendingBuyOrdersView, pendingSellOrdersView (lines 360-400).
// - v0.0.27: Fixed stack-too-deep in _prepBuyLiquidUpdates by adding _createBuyOrderUpdates helper, using BuyOrderUpdateContext struct for _prepBuyOrderUpdate outputs, and applying scoped blocks (lines 305-320).
// - v0.0.26: Fixed ParserError in settleSellLiquid by removing erroneous 'yul' identifier from finalUpdates declaration (line 460).
// - v0.0.25: Fixed stack-too-deep in _prepSellLiquidUpdates by adding _createSellOrderUpdates helper, using SellOrderUpdateContext struct for _prepSellOrderUpdate outputs, reusing _checkPricing, and applying scoped blocks. Corrected import path to "./utils/SSSettlementPartial.sol" (lines 8, 335-350).
// - v0.0.24: Fixed stack-too-deep in executeSingleBuyLiquid by adding _prepBuyLiquidUpdates and _checkPricing helpers, using OrderContext struct, and applying scoped blocks, inspired by MFPRouter.sol v0.0.27 (lines 260-300).
// - v0.0.23: Fixed stack-too-deep in executeSingleSellLiquid by introducing OrderContext struct, adding _prepSellLiquidUpdates helper, using scoped blocks, and reusing _prepareLiquidityTransaction/_updateLiquidity, inspired by MFPRouter.sol v0.0.27 (lines 260-300).
// - v0.0.22: Fixed DeclarationError in createSellOrder by replacing tokenBAddress with tokenAAddress in postBalance calculation, aligning with sell order tokenA input (line 199).
// - v0.0.21: Removed isValidListing[listing] = true from initializeListing, as isValidListing mapping was removed from SSMainPartial.sol (v0.0.14). Validation now relies solely on checkValidListing via onlyValidListing modifier (line 140).
// - v0.0.6: Compatible with SSListingTemplate.sol (v0.0.8), SSLiquidityTemplate.sol (v0.0.4), SSMainPartial.sol (v0.0.19), SSOrderPartial.sol (v0.0.13), SSSettlementPartial.sol (v0.0.30).

import "./utils/SSSettlementPartial.sol";

contract SSRouter is SSSettlementPartial {
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
        normalizedReceived = amountReceived > 0 ? listingContract.normalize(amountReceived, tokenDecimals) : 0;
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
        try listingContract.transact(address(this), tokenIn, inputAmount, liquidityAddr) {} catch {
            revert("Principal transfer failed");
        }
        try liquidityContract.updateLiquidity(address(this), isX, inputAmount) {} catch {
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
            uint256 preBalance = tokenOut == address(0)
                ? updateContext.recipient.balance
                : IERC20(tokenOut).balanceOf(updateContext.recipient);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, context.listingContract.denormalize(amountOut, tokenDecimals), updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            uint256 postBalance = tokenOut == address(0)
                ? updateContext.recipient.balance
                : IERC20(tokenOut).balanceOf(updateContext.recipient);
            if (postBalance <= preBalance) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = postBalance - preBalance;
            updateContext.normalizedReceived = context.listingContract.normalize(updateContext.amountReceived, tokenDecimals);
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
            uint256 preBalance = tokenOut == address(0)
                ? updateContext.recipient.balance
                : IERC20(tokenOut).balanceOf(updateContext.recipient);
            try ISSLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, context.listingContract.denormalize(amountOut, tokenDecimals), updateContext.recipient) {} catch {
                return new ISSListingTemplate.UpdateType[](0);
            }
            uint256 postBalance = tokenOut == address(0)
                ? updateContext.recipient.balance
                : IERC20(tokenOut).balanceOf(updateContext.recipient);
            if (postBalance <= preBalance) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = postBalance - preBalance;
            updateContext.normalizedReceived = context.listingContract.normalize(updateContext.amountReceived, tokenDecimals);
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
        executeBuyOrders(listingAddress, maxIterations);
    }

    function settleSellOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        executeSellOrders(listingAddress, maxIterations);
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

    function settleLongPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        executeLongPayouts(listingAddress, maxIterations);
    }

    function settleShortPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        executeShortPayouts(listingAddress, maxIterations);
    }

    function deposit(address listingAddress, address tokenAddress, uint256 inputAmount) external payable onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(tokenAddress == listingContract.tokenA() || tokenAddress == listingContract.tokenB(), "Invalid token");
        if (tokenAddress == address(0)) {
            require(msg.value == inputAmount, "Incorrect ETH amount");
            try liquidityContract.deposit{value: inputAmount}(address(this), tokenAddress, inputAmount) {} catch {
                revert("Deposit failed");
            }
        } else {
            IERC20(tokenAddress).transferFrom(msg.sender, address(this), inputAmount);
            IERC20(tokenAddress).approve(liquidityAddr, inputAmount);
            try liquidityContract.deposit(address(this), tokenAddress, inputAmount) {} catch {
                revert("Deposit failed");
            }
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        try liquidityContract.claimFees(address(this), listingAddress, liquidityIndex, isX, volumeAmount) {} catch {
            revert("Claim fees failed");
        }
    }

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        ISSLiquidityTemplate.PreparedWithdrawal memory withdrawal;
        try liquidityContract.xPrepOut(address(this), inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
            withdrawal = w;
        } catch {
            try liquidityContract.yPrepOut(address(this), inputAmount, index) returns (ISSLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
        }
        if (isX) {
            try liquidityContract.xExecuteOut(address(this), index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        } else {
            try liquidityContract.yExecuteOut(address(this), index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        }
    }

    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external onlyValidListing(listingAddress) nonReentrant {
        _clearOrderData(listingAddress, orderIdentifier, isBuyOrder);
    }

    function clearOrders(address listingAddress, uint256[] memory orderIdentifiers, bool[] memory isBuyIds) external onlyValidListing(listingAddress) nonReentrant {
        require(orderIdentifiers.length == isBuyIds.length, "Array length mismatch");
        for (uint256 i = 0; i < orderIdentifiers.length; i++) {
            _clearOrderData(listingAddress, orderIdentifiers[i], isBuyIds[i]);
        }
    }

    function changeDepositor(
        address listingAddress,
        bool isX,
        uint256 slotIndex,
        address newDepositor
    ) external onlyValidListing(listingAddress) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routers(address(this)), "Router not registered");
        try liquidityContract.changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor) {} catch {
            revert("Failed to change depositor");
        }
    }
}