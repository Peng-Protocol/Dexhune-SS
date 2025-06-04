// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.21
// Changes:
// - v0.0.21: Fixed TypeError in executeLongPayout and executeShortPayout by updating _processPayoutUpdate to return ISSListingTemplate.PayoutUpdate[] memory, aligning with function expectations (lines 393, 405).
// - v0.0.20: Fixed DeclarationError in _getTokenAndDecimals by replacing tokenA/tokenB/decimalsA/decimalsB mappings with ISSListingTemplate.tokenA()/tokenB()/decimalsA()/decimalsB() calls, aligning with SSMainPartial.sol v0.0.15 (line 60).
// - v0.0.19: Fixed ParserError in executeLongPayout by correcting return type to ISSListingTemplate.PayoutUpdate[] memory, removed erroneous nested 'returns', and fixed typo PayoutType to PayoutUpdate (line 385). Corrected logical error in executeSellOrders condition from 'updates.length == updates.length == 0' to 'updates.length == 0' (line 364).
// - v0.0.18: Fixed typo in executeShortPayouts: replaced 'ordres' with 'orders' (lines 448-463).
// - v0.0.17: Revised _computeImpact to align with MFP: reduce xBalance for buy (tokenA out), reduce yBalance for sell (tokenB out). Integrated impact price into settlement for executeBuyOrder, executeSellOrder, settleBuyLiquid, settleSellLiquid to compute amountReceived. Added balance sufficiency checks. Confirmed token usage: tokenB in/tokenA out for buy, tokenA in/tokenB out for sell.
// - v0.0.16: Removed _processBuyOrderUpdate/_processSellOrderUpdate. Added _prepBuyOrderUpdate, _prepSellOrderUpdate, _executeSellOrderUpdate to separate data preparation and execution for orders and payouts. Updated _createOrderUpdates to accept pendingAmount (lines 60-150). Updated executeBuyOrderUpdate to handleBuyOrders and payouts.
// - v0.0.15: Added helper functions _getTokenAndDecimals, _executeTransaction, _createOrderUpdates for _processPayoutsUpdate to handle payouts. Refactored _processBuyPayouts and _processSellOrderUpdate to use helper functions to reduce stack depth issues (lines 60-120).
// - v0.0.14: Split _ssUpdate into _processBuyOrderUpdate and _processSellOrderUpdate to reduce stack depth issues. Added executeLongPayout and executeShortPayout, refactored executeLongPayouts and payoutSellOrders with try-catch blocks to prevent stack overflow issues (lines 60-200).
// - v0.0.13: Added executeBuyOrder and executeSellOrder functions to executeBuyOrders, refactored executeBuyOrders and executeSellOrders with try-catch to reduce stack depth errors, to handle order updates _processOrderUpdate to return UpdateType [] array (lines 100-200).
// - v0.0.12: Removed ISSListingTemplate interface to avoid duplication with SSMainPartial.sol (v0.0.8). Imported ISSListingTemplate from SSMainPartial.sol. Updated normalize to pure order to pure update to match MFP style and to match SSMainPartial.sol and SSListingTemplate.sol (v0.0.7).
// - v0.0.11: Fixed TypeError in executeBuyOrders by updating ISSListingTemplate.ShortPayoutStruct to use 'amount' instead of 'required' to match MFP for SSListingTemplate.sol (v0.0.7). Updated executeBuyPayouts to use payout.amount.
// - v0.0.11: Validated ISSListingTemplate interface against SSListingTemplate.sol (v0.0.7) for consistency with MFP's LongPayouts.OrderStruct, UpdateType order, and function signatures.
// - v0.0.10: Fixed TypeError in executeBuyOrders and executeSellOrders by adding explicit tuple destructuring for getBuyOrderCore orders and getSellOrderCore to access makerAddress and recipientAddress for updates.
// - v0.0.9: Fixed ParserError in _processOrderUpdate by correcting tuple destructuring syntax for orders getBuyOrderCore and getSellOrderCore to include all tuple fields explicitly for update struct updates.
// - v0.0.8: Fixed TypeError in _processOrderUpdate by adding missing struct fields (structId, maxPrice, minPrice) and explicit tuple struct destructuring for getBuyOrderCore orders to _update struct.
// - v0.0.7: Removed ISSAgent.globalizeOrders from _processOrder to _processPayouts globalization, globalization handled by SSListingTemplate.
// - v0.0.7: Fixed syntax errors from artifact (c4f5e6a7-b8c9f7-b6c8c9-49bc-1234-f56789abcdef0).
// - v0.0.7: Restored _processOrderUpdate logic to match MFP's SSSettlementPartial.sol, excluding globalizeOrders.
// - v0.0.7: Corrected _processPayoutUpdate status logic (3 : 2) and parameter typing for payouts.
// - v0.0.7: Ensured compatibility with SSListingTemplate.sol (v0.0.5), SSLiquidityTemplate.sol (v0.0.4).

import "./SSOrderPartial.sol";

contract SSSettlementPartial is SSOrderPartial {
    function _computeImpact(
        address listing,
        uint256 amount,
        bool isBuy
    ) internal view virtual returns (uint256) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        (uint256 xBalance, uint256 yBalance, , ) = listingContract.listingVolumeBalancesView();
        // Current price: xBalance (tokenA) / yBalance (tokenB)
        require(yBalance > 0, "Zero yBalance");
        uint256 currentPrice = (xBalance * 1e18) / yBalance;
        uint256 amountOut;
        uint256 newXBalance = xBalance;
        uint256 newYBalance = yBalance;
        
        if (isBuy) {
            // Buy: tokenB in, tokenA out; reduce xBalance
            amountOut = (amount * currentPrice) / 1e18;
            require(xBalance >= amountOut, "Insufficient xBalance");
            newXBalance = xBalance - amountOut;
        } else {
            // Sell: tokenA in, tokenB out; reduce yBalance
            amountOut = (amount * 1e18) / currentPrice;
            require(yBalance >= amountOut, "Insufficient yBalance");
            newYBalance = yBalance - amountOut;
        }
        
        // New price after tokens leave the pool
        require(newYBalance > 0, "Zero new yBalance");
        return (newXBalance * 1e18) / newYBalance;
    }

    function _getTokenAndDecimals(
        address listing,
        bool isBuy
    ) internal view returns (address tokenAddress, uint8 decimals) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        // Select input token: tokenB for buy, tokenA for sell
        tokenAddress = isBuy ? listingContract.tokenB() : listingContract.tokenA();
        decimals = isBuy ? listingContract.decimalsB() : listingContract.decimalsA();
    }

    function _executeTransaction(
        address listing,
        address tokenAddress,
        uint256 amount,
        address recipient
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint8 decimals = tokenAddress == address(0) ? 18 : IERC20(tokenAddress).decimals();
        uint256 preBalance = tokenAddress == address(0) ? address(this).balance : IERC20(tokenAddress).balanceOf(address(this));
        // Transact: tokenA out for buy, tokenB out for sell
        listingContract.transact(address(this), tokenAddress, amount, recipient);
        uint256 postBalance = tokenAddress == address(0) ? address(this).balance : IERC20(tokenAddress).balanceOf(address(this));
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? listingContract.normalize(amountReceived, decimals) : 0;
    }

    function _createOrderUpdates(
        uint256 orderId,
        uint256 normalizedReceived,
        address makerAddress,
        address recipient,
        uint8 status,
        bool isBuy,
        uint256 pendingAmount
    ) internal pure returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 2,
            index: orderId,
            value: normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: status == 1 && normalizedReceived >= pendingAmount ? 3 : 2,
            addr: makerAddress,
            recipient: recipient,
            maxPrice: 0,
            minPrice: 0
        });
        return updates;
    }

    function _prepBuyOrderUpdate(
        address listing,
        uint256 orderId,
        uint256 amount
    ) internal returns (
        address tokenAddress,
        uint8 decimals,
        address makerAddress,
        address recipient,
        uint8 status,
        uint256 amountReceived,
        uint256 normalizedReceived
    ) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        // Prep buy: tokenB in, tokenA out
        (tokenAddress, decimals) = _getTokenAndDecimals(listing, true);
        (makerAddress, recipient, status) = listingContract.getBuyOrderCore(orderId);
        (amountReceived, normalizedReceived) = _executeTransaction(listing, tokenAddress, amount, recipient);
    }

    function _prepSellOrderUpdate(
        address listing,
        uint256 orderId,
        uint256 amount
    ) internal returns (
        address tokenAddress,
        uint8 decimals,
        address makerAddress,
        address recipient,
        uint8 status,
        uint256 amountReceived,
        uint256 normalizedReceived
    ) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        // Prep sell: tokenA in, tokenB out
        (tokenAddress, decimals) = _getTokenAndDecimals(listing, false);
        (makerAddress, recipient, status) = listingContract.getSellOrderCore(orderId);
        (amountReceived, normalizedReceived) = _executeTransaction(listing, tokenAddress, amount, recipient);
    }

    function _executeBuyOrderUpdate(
        address listing,
        uint256 orderId,
        uint256 normalizedReceived,
        address makerAddress,
        address recipient,
        uint8 status
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        if (normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 pendingAmount = orderPendingAmounts[listing][orderId];
        ISSListingTemplate.UpdateType[] memory updates = _createOrderUpdates(
            orderId,
            normalizedReceived,
            makerAddress,
            recipient,
            status,
            true,
            pendingAmount
        );
        orderPendingAmounts[listing][orderId] -= normalizedReceived;
        return updates;
    }

    function _executeSellOrderUpdate(
        address listing,
        uint256 orderId,
        uint256 normalizedReceived,
        address makerAddress,
        address recipient,
        uint8 status
    ) internal returns (ISSListingTemplate.UpdateType[] memory) {
        if (normalizedReceived == 0) {
            return new ISSListingTemplate.UpdateType[](0);
        }
        uint256 pendingAmount = orderPendingAmounts[listing][orderId];
        ISSListingTemplate.UpdateType[] memory updates = _createOrderUpdates(
            orderId,
            normalizedReceived,
            makerAddress,
            recipient,
            status,
            false,
            pendingAmount
        );
        orderPendingAmounts[listing][orderId] -= normalizedReceived;
        return updates;
    }

    function _processPayoutUpdate(
        address listing,
        uint256 orderId,
        uint256 amount,
        bool isLong
    ) internal returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.PayoutUpdate[] memory updates = new ISSListingTemplate.PayoutUpdate[](1);
        updates[0] = ISSListingTemplate.PayoutUpdate({
            payoutType: isLong ? 0 : 1,
            recipient: address(0),
            required: amount
        });
        listingContract.ssUpdate(address(this), updates);
        payoutPendingAmounts[listing][orderId] -= amount;
        return updates;
    }

    function executeBuyOrder(
        address listing,
        uint256 orderId,
        uint256 amount
    ) public returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        {
            uint256 maxPrice;
            uint256 minPrice;
            (maxPrice, minPrice) = listingContract.getBuyOrderPricing(orderId);
            uint256 pending;
            (pending, ) = listingContract.getBuyOrderAmounts(orderId);
            if (pending == 0 || amount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            // Compute impact price: tokenA out for buy
            uint256 impactPrice = _computeImpact(listing, amount, true);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            // Adjust amount: tokenA received for buy
            amount = (amount * impactPrice) / 1e18;
        }
        (
            address tokenAddress,
            uint8 decimals,
            address makerAddress,
            address recipient,
            uint8 status,
            uint256 amountReceived,
            uint256 normalizedReceived
        ) = _prepBuyOrderUpdate(listing, orderId, amount);
        return _executeBuyOrderUpdate(listing, orderId, normalizedReceived, makerAddress, recipient, status);
    }

    function executeSellOrder(
        address listing,
        uint256 orderId,
        uint256 amount
    ) public returns (ISSListingTemplate.UpdateType[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        {
            uint256 maxPrice;
            uint256 minPrice;
            (maxPrice, minPrice) = listingContract.getSellOrderPricing(orderId);
            uint256 pending;
            (pending, ) = listingContract.getSellOrderAmounts(orderId);
            if (pending == 0 || amount == 0) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            // Compute impact price: tokenB out for sell
            uint256 impactPrice = _computeImpact(listing, amount, false);
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
            // Adjust amount: tokenB received for sell
            amount = (amount * 1e18) / impactPrice;
        }
        (
            address tokenAddress,
            uint8 decimals,
            address makerAddress,
            address recipient,
            uint8 status,
            uint256 amountReceived,
            uint256 normalizedReceived
        ) = _prepSellOrderUpdate(listing, orderId, amount);
        return _executeSellOrderUpdate(listing, orderId, normalizedReceived, makerAddress, recipient, status);
    }

    function executeBuyOrders(address listing, uint256 maxIterations) internal onlyValidListing(listing) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256[] storage orders = activeBuyOrders[listing];
        uint256 processed = 0;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](orders.length * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < orders.length && processed < maxIterations; ) {
            uint256 orderId = orders[i];
            uint256 pending;
            (pending, ) = listingContract.getBuyOrderAmounts(orderId);
            if (pending == 0) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                continue;
            }
            try this.executeBuyOrder(listing, orderId, pending) returns (ISSListingTemplate.UpdateType[] memory updates) {
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

    function executeSellOrders(address listing, uint256 maxIterations) internal onlyValidListing(listing) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256[] storage orders = activeSellOrders[listing];
        uint256 processed = 0;
        ISSListingTemplate.UpdateType[] memory tempUpdates = new ISSListingTemplate.UpdateType[](orders.length * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < orders.length && processed < maxIterations; ) {
            uint256 orderId = orders[i];
            uint256 pending;
            (pending, ) = listingContract.getSellOrderAmounts(orderId);
            if (pending == 0) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                continue;
            }
            try this.executeSellOrder(listing, orderId, pending) returns (ISSListingTemplate.UpdateType[] memory updates) {
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

    function executeLongPayout(
        address listing,
        uint256 orderId
    ) public returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.LongPayoutStruct memory payout = listingContract.getLongPayout(orderId);
        if (payout.required == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        return _processPayoutUpdate(listing, orderId, payout.required, true);
    }

    function executeShortPayout(
        address listing,
        uint256 orderId
    ) public returns (ISSListingTemplate.PayoutUpdate[] memory) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.ShortPayoutStruct memory payout = listingContract.getShortPayout(orderId);
        if (payout.amount == 0) {
            return new ISSListingTemplate.PayoutUpdate[](0);
        }
        return _processPayoutUpdate(listing, orderId, payout.amount, false);
    }

    function executeLongPayouts(address listing, uint256 maxIterations) internal onlyValidListing(listing) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256[] storage orders = activeLongPayouts[listing];
        uint256 processed = 0;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](orders.length);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < orders.length && processed < maxIterations; ) {
            uint256 orderId = orders[i];
            try this.executeLongPayout(listing, orderId) returns (ISSListingTemplate.PayoutUpdate[] memory payoutUpdates) {
                if (payoutUpdates.length == 0) {
                    i++;
                    continue;
                }
                for (uint256 j = 0; j < payoutUpdates.length; j++) {
                    tempPayoutUpdates[updateIndex++] = payoutUpdates[j];
                }
                processed++;
                if (payoutPendingAmounts[listing][orderId] == 0) {
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
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function executeShortPayouts(address listing, uint256 maxIterations) internal onlyValidListing(listing) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256[] storage orders = activeShortPayouts[listing];
        uint256 processed = 0;
        ISSListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](orders.length);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < orders.length && processed < maxIterations; ) {
            uint256 orderId = orders[i];
            try this.executeShortPayout(listing, orderId) returns (ISSListingTemplate.PayoutUpdate[] memory payouts) {
                if (payouts.length == 0) {
                    i++;
                    continue;
                }
                for (uint256 j = 0; j < payouts.length; j++) {
                    tempPayoutUpdates[updateIndex++] = payouts[j];
                }
                processed++;
                if (payoutPendingAmounts[listing][orderId] == 0) {
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
        ISSListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new ISSListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }
}