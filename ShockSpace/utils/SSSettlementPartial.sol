// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.16
// Changes:
// - v0.0.16: Removed _processBuyOrderUpdate/_processSellOrderUpdate. Added _prepBuyOrderUpdate, _prepSellOrderUpdate, _executeBuyOrderUpdate, _executeSellOrderUpdate to separate data preparation and execution. Updated _createOrderUpdates to accept pendingAmount. Updated executeBuyOrder/executeSellOrder to use new prep/execute functions (lines 60-150).
// - v0.0.15: Added helper functions _getTokenAndDecimals, _executeTransaction, _createOrderUpdates. Refactored _processBuyOrderUpdate and _processSellOrderUpdate to use helpers to reduce stack depth (lines 60-120).
// - v0.0.14: Split _processOrderUpdate into _processBuyOrderUpdate and _processSellOrderUpdate to reduce stack depth. Added executeLongPayout and executeShortPayout, refactored executeLongPayouts and executeShortPayouts with try-catch to prevent stack issues (lines 60-200).
// - v0.0.13: Added executeBuyOrder and executeSellOrder functions, refactored executeBuyOrders and executeSellOrders with try-catch to reduce stack depth, updated _processOrderUpdate to return UpdateType array (lines 100-200).
// - v0.0.12: Removed ISSListingTemplate interface to avoid duplication with SSMainPartial.sol (v0.0.8). Imported ISSListingTemplate from SSMainPartial.sol. Updated normalize to pure to match SSMainPartial.sol and SSListingTemplate.sol (v0.0.7).
// - v0.0.11: Fixed TypeError in executeShortPayouts by updating ISSListingTemplate.ShortPayoutStruct to use 'amount' instead of 'required' to match SSListingTemplate.sol (v0.0.7). Updated executeShortPayouts to use payout.amount.
// - v0.0.11: Validated ISSListingTemplate interface against SSListingTemplate.sol (v0.0.7) for consistency in LongPayoutStruct, UpdateType, and function signatures.
// - v0.0.10: Fixed TypeError in executeBuyOrders and executeSellOrders by adding explicit tuple destructuring for getBuyOrderCore/getSellOrderCore to access makerAddress and recipientAddress.
// - v0.0.9: Fixed ParserError in _processOrderUpdate by correcting tuple destructuring syntax for getBuyOrderCore/getSellOrderCore to include all tuple elements explicitly.
// - v0.0.8: Fixed TypeError in _processOrderUpdate by adding missing struct fields (structId, maxPrice, minPrice) and explicit tuple destructuring for getBuyOrderCore/getSellOrderCore.
// - v0.0.7: Removed ISSAgent.globalizeOrders from _processOrderUpdate, globalization handled by SSListingTemplate.
// - v0.0.7: Fixed syntax errors from artifact (c4f5e6a7-b8c9-49bc-1234-f56789abcdef0).
// - v0.0.7: Restored _processOrderUpdate logic to match SSSettlementPartial.txt, excluding globalizeOrders.
// - v0.0.7: Corrected _processPayoutUpdate status logic (3 : 2) and parameter typing.
// - v0.0.7: Ensured compatibility with SSListingTemplate.sol (v0.0.5), SSLiquidityTemplate.sol (v0.0.4).

import "./SSOrderPartial.sol";

contract SSSettlementPartial is SSOrderPartial {
    function _computeImpact(
        address listing,
        uint256 amount,
        bool isBuy
    ) internal view returns (uint256) {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        (uint256 xBalance, uint256 yBalance, , ) = listingContract.listingVolumeBalancesView();
        if (isBuy) {
            uint256 newY = yBalance + amount;
            return newY > 0 ? (xBalance * 1e18) / newY : 0;
        } else {
            uint256 newX = xBalance + amount;
            return newX > 0 ? (yBalance * 1e18) / newX : 0;
        }
    }

    function _getTokenAndDecimals(
        address listing,
        bool isBuy
    ) internal view returns (address tokenAddress, uint8 decimals) {
        tokenAddress = isBuy ? tokenB[listing] : tokenA[listing];
        decimals = isBuy ? decimalsB[listing] : decimalsA[listing];
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
        ISSListingTemplate.PayoutUpdate[] memory payoutUpdates = new ISSListingTemplate.PayoutUpdate[](1);
        payoutUpdates[0] = ISSListingTemplate.PayoutUpdate({
            payoutType: isLong ? 0 : 1,
            recipient: address(0),
            required: amount
        });
        listingContract.ssUpdate(address(this), payoutUpdates);
        payoutPendingAmounts[listing][orderId] -= amount;
        return payoutUpdates;
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
            (uint256 xBalance, uint256 yBalance, , ) = listingContract.listingVolumeBalancesView();
            uint256 impactPrice = yBalance > 0 ? (xBalance * 1e18) / (yBalance + amount) : 0;
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
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
            (uint256 xBalance, uint256 yBalance, , ) = listingContract.listingVolumeBalancesView();
            uint256 impactPrice = xBalance > 0 ? (yBalance * 1e18) / (xBalance + amount) : 0;
            if (impactPrice > maxPrice || impactPrice < minPrice) {
                return new ISSListingTemplate.UpdateType[](0);
            }
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
            try this.executeShortPayout(listing, orderId) returns (ISSListingTemplate.PayoutUpdate[] memory payoutUpdates) {
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
}