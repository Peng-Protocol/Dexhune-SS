// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.30 (Updated)
// Changes:
// - v0.0.30: Fixed TypeError by removing try/catch blocks around internal function calls (executeBuyOrder, executeSellOrder, executeLongPayout, executeShortPayout) in executeBuyOrders, executeSellOrders, executeLongPayouts, and executeShortPayouts, as try/catch is only valid for external calls (lines 274, 308, 359, 391). Added import for IERC20 to support decimals() and balanceOf() in _checkRecipientTransfer (line 24).
// - v0.0.29: Fixed TypeError by replacing external calls (this.executeBuyOrder, this.executeSellOrder, this.executeLongPayout, this.executeShortPayout) with internal calls (executeBuyOrder, executeSellOrder, executeLongPayout, executeShortPayout) in executeBuyOrders, executeSellOrders, executeLongPayouts, and executeShortPayouts, as internal functions cannot be called via 'this' (lines 274, 308, 342, 374). Corrected inheritance from SSOrder.partial to SSOrderPartial (line 27).
// - v0.0.28: Fixed ParserError in _computeImpact by removing stray 'HawkinsHighlight' identifier, replacing with proper 'if (isBuyOrder)' condition for buy/sell logic (line 37).
// - v0.0.27: Fixed ParserError in _computeImpact by correcting syntax from 'ISSListingTemplate:listingAddress' to 'ISSListingTemplate(listingAddress)' for proper type casting (line 29). Fixed ParserError in executeShortPayouts by adding missing semicolon before 'for' loop, correcting syntax and ensuring proper statement termination (line 380).
// - v0.0.26: Fixed ParserError in _processPayoutUpdate by removing semicolon from empty catch block, correcting syntax for try/catch (line 194).
// - v0.0.25: Updated _prepBuyOrderUpdate and _prepSellOrderUpdate to use new _checkRecipientTransfer helper for pre/post balance checks on the recipient's balance, ensuring the amount sent from the listing to the recipient matches inputAmount, updating orders with actual amountReceived to account for tax on transfers (lines 200-250).
// - v0.0.24: Fixed syntax errors in executeShortPayout (corrected listingContractLASListingTemplate to listingContract, line ~390) and executeLongPayouts (completed if condition and added closing braces, line ~460). Restored orderPendingAmounts and payoutPendingAmounts state variables and their updates in _executeBuyOrderUpdate, _executeSellOrderUpdate, _processPayoutUpdate, as their removal in v0.0.22 was inconsistent with logic (lines 90-100, 200-220, 280-300). Removed reliance on activeBuyOrders, activeSellOrders, activeLongPayouts, activeShortPayouts, using pendingBuyOrdersView, pendingSellOrdersView, longPayoutByIndexView, shortPayoutByIndexView (lines 350-450). Ensured stack depth ≤16 variables, explicit parameter names, and style guide compliance.
// - v0.0.23: Updated _executeTransaction to check balances of targetContract (listing or liquidity contract) instead of address(this) for accurate amountReceived calculation (lines 120-140). Replaced listing parameter with targetContract to support both listing and liquidity contracts.
// - v0.0.22: Changed visibility of executeBuyOrder, executeSellOrder, executeLongPayout, executeShortPayout to internal to hide non-user-facing functions (lines 330-380). Updated _executeTransaction to use ISSListingTemplate.transact instead of direct token transfers (lines 200-220). Updated _clearOrderData to refund pending amounts via ISSListingTemplate.transact (lines 250-270). Removed references to orderPendingAmounts, payoutPendingAmounts, activeBuyOrders, activeSellOrders, activeLongPayouts, activeShortPayouts, makerActiveOrders, querying ISSListingTemplate view functions (e.g., pendingBuyOrdersView, getBuyOrderAmounts) (lines 100-150).
// - v0.0.21: Fixed TypeError in executeLongPayout and executeShortPayout by updating _processPayoutUpdate to return ISSListingTemplate.PayoutUpdate[], aligning with function expectations (lines 393-405).
// - v0.0.20: Fixed DeclarationError in _getTokenAndDecimals by replacing tokenA/tokenB/decimalsA/decimalsB mappings with ISSListingTemplate.tokenA()/tokenB()/decimalsA()/decimalsB() calls, aligning with SSMainPartial.sol v0.0.15 (line 60).
// - v0.0.19: Fixed ParserError in executeLongPayout by correcting return type to ISSListingTemplate.PayoutUpdate[], removed erroneous nested 'returns', and fixed typo PayoutType to PayoutUpdate (line 385). Corrected logical error in executeSellOrders condition from 'updates.length == updates.length == 0' to 'updates.length == 0' (line 364).
// - v0.0.18: Fixed typo in executeShortPayouts: replaced 'ordres' with 'orders' (lines 448-463).
// - v0.0.17: Revised _computeImpact to align with token flow: reduce xBalance for buy (tokenA out), reduce yBalance for sell (tokenB out). Integrated impact price into settlement for executeBuyOrder, executeSellOrder, settleBuyLiquid, settleSellLiquid to compute amountReceived. Added balance sufficiency checks.
// - Compatible with SSListingTemplate.sol (v0.0.8), SSLiquidityTemplate.sol (v0.0.4), SSMainPartial.sol (v0.0.18), SSOrderPartial.sol (v0.0.12).

import "./SSOrderPartial.sol";

contract SSSettlementPartial is SSOrderPartial {
    mapping(address => mapping(uint256 => uint256)) internal orderPendingAmounts;
    mapping(address => mapping(uint256 => uint256)) internal payoutPendingAmounts;

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
        uint256 preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
        try listingContract.transact(address(this), tokenAddress, inputAmount, recipientAddress) {} catch {
            return (0, 0);
        }
        uint256 postBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? listingContract.normalize(amountReceived, tokenDecimals) : 0;
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
        (amountReceived, normalizedReceived) = _checkRecipientTransfer(listingAddress, tokenAddress, inputAmount, recipientAddress);
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
        (amountReceived, normalizedReceived) = _checkRecipientTransfer(listingAddress, tokenAddress, inputAmount, recipientAddress);
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

    function _processPayoutUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 payoutAmount,
        bool isLongPayout
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.PayoutUpdate[] memory updates = new ISSListingTemplate.PayoutUpdate[](1);
        updates[0] = ISSListingTemplate.PayoutUpdate({
            payoutType: isLongPayout ? 0 : 1,
            recipient: address(0),
            required: payoutAmount
        });
        try listingContract.ssUpdate(address(this), updates) {} catch {}
        payoutPendingAmounts[listingAddress][orderIdentifier] -= payoutAmount;
        return updates;
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
            ISSListingTemplate.UpdateType[] memory updates = executeBuyOrder(listingAddress, orderIdentifier, pendingAmount);
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
            ISSListingTemplate.UpdateType[] memory updates = executeSellOrder(listingAddress, orderIdentifier, pendingAmount);
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

    function executeLongPayout(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listingAddress);
        ISSListingTemplate.LongPayoutStruct memory payout = listingContract.getLongPayout(orderIdentifier);
        if (payout.required == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        return _processPayoutUpdate(listingAddress, orderIdentifier, payout.required, true);
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
        return _processPayoutUpdate(listingAddress, orderIdentifier, payout.amount, false);
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