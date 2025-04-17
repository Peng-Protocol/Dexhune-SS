// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.8 (Updated)
// Changes:
// - From v0.0.7: Updated processOrder to set UpdateType.value to amountReceived for tax-on-transfer adjustments (new in v0.0.8).
// - From v0.0.7: Updated processPayoutOrder to set UpdateType.value and PayoutUpdate.required to amountReceived (new in v0.0.8).
// - From v0.0.7: Added fallback for decimalsA/decimalsB using IERC20.decimals() if not provided by ISSListing (new in v0.0.8).
// - From v0.0.7: Modified prepLongPayouts to cap amount at yBalance (tokenB) instead of xBalance.
// - From v0.0.7: Modified prepShortPayouts to cap amount at xBalance (tokenA) instead of yBalance.
// - From v0.0.7: Updated executeLongPayouts to use tokenB and yBalance for long payouts.
// - From v0.0.7: Updated executeShortPayouts to use tokenA and xBalance for short payouts.
// - From v0.0.7: Adjusted getPayoutParams to return tokenB/yBalance for isLong=true, tokenA/xBalance for isLong=false.
// - From v0.0.7: Updated processPayoutOrder to use decimalsB for long, decimalsA for short payouts.
// - Side effects: Ensures tax-on-transfer adjustments are reflected in state updates; improves decimals handling robustness.
// - Note: decimalsA and decimalsB assumed available externally; fallback to IERC20.decimals() added.

import "./imports/SafeERC20.sol";

interface ISS {
    function isValidListing(address listing) external view returns (bool);
}

interface ISSListing {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address maker;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct PayoutUpdate {
        uint8 payoutType; // 0 = long payout, 1 = short payout
        address recipient;
        uint256 required;
        uint256 price;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    function update(address caller, UpdateType[] memory updates) external;
    function ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function longPayoutByIndexView(uint256 listingId) external view returns (uint256[] memory);
    function shortPayoutByIndexView(uint256 listingId) external view returns (uint256[] memory);
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function getLongPayout(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 required,
        uint256 filled,
        uint256 payoutId,
        uint8 status
    );
    function getShortPayout(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 required,
        uint256 filled,
        uint256 payoutId,
        uint8 status
    );
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    function getListingId() external view returns (uint256);
}

library SSSettlementLibrary {
    using SafeERC20 for IERC20;

    struct PreparedUpdate {
        uint256 orderId;
        bool isBuy;
        uint256 amount;
        address recipient;
    }

    struct PreparedPayoutUpdate {
        uint256 orderId;
        bool isLong;
        uint256 amount;
        address recipient;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount;
        }
        return (amount * 1e18) / (10 ** decimals);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount;
        }
        return (amount * (10 ** decimals)) / 1e18;
    }

    function getDecimals(address token, ISSListing listing, bool isBuy) internal view returns (uint8) {
        if (token == address(0)) return 18;
        try listing.decimalsA() returns (uint8 decA) {
            return isBuy ? decA : listing.decimalsB();
        } catch {
            return IERC20(token).decimals();
        }
    }

    function calculateImpactPrice(uint256 xBalance, uint256 yBalance, uint256 totalAmount, bool isBuy) internal pure returns (uint256) {
        uint256 newXBalance = isBuy ? xBalance - totalAmount : xBalance + totalAmount;
        uint256 newYBalance = isBuy ? yBalance + totalAmount : yBalance - totalAmount;

        if (newYBalance == 0) {
            return 0;
        }

        return (newXBalance * 1e18) / newYBalance;
    }

    function getListingIdFromAddress(address listingAddress, address listingAgent) internal view returns (uint256) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        return ISSListing(listingAddress).getListingId();
    }

    function prepBuyOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256[] memory orders = listing.pendingBuyOrdersView();
        (uint256 xBalance, uint256 yBalance, , ) = listing.listingVolumeBalancesView();

        uint256 updateCount;
        PreparedUpdate[] memory updates = new PreparedUpdate[](orders.length);

        for (uint256 i = 0; i < orders.length && updateCount < 100; i++) {
            (, address recipient, uint256 amount, , , uint8 status) = listing.getLongPayout(orders[i]);
            if (status == 0 && amount > 0) {
                updates[updateCount] = PreparedUpdate(orders[i], true, amount, recipient);
                updateCount++;
            }
        }

        assembly {
            mstore(updates, updateCount)
        }

        return updates;
    }

    function prepSellOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256[] memory orders = listing.pendingSellOrdersView();
        (uint256 xBalance, uint256 yBalance, , ) = listing.listingVolumeBalancesView();

        uint256 updateCount;
        PreparedUpdate[] memory updates = new PreparedUpdate[](orders.length);

        for (uint256 i = 0; i < orders.length && updateCount < 100; i++) {
            (, address recipient, uint256 amount, , , uint8 status) = listing.getShortPayout(orders[i]);
            if (status == 0 && amount > 0) {
                updates[updateCount] = PreparedUpdate(orders[i], false, amount, recipient);
                updateCount++;
            }
        }

        assembly {
            mstore(updates, updateCount)
        }

        return updates;
    }

    function prepLongPayouts(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256 listingId = getListingIdFromAddress(listingAddress, listingAgent);
        uint256[] memory payoutIds = listing.longPayoutByIndexView(listingId);
        (, uint256 yBalance, , ) = listing.listingVolumeBalancesView();

        uint256 updateCount;
        PreparedPayoutUpdate[] memory updates = new PreparedPayoutUpdate[](payoutIds.length);

        for (uint256 i = 0; i < payoutIds.length && updateCount < 100; i++) {
            (, address recipient, uint256 required, uint256 filled, , uint8 status) = listing.getLongPayout(payoutIds[i]);
            if (status == 0 && required > filled) {
                uint256 amount = required - filled;
                if (amount > yBalance) {
                    amount = yBalance;
                }
                if (amount > 0) {
                    updates[updateCount] = PreparedPayoutUpdate(payoutIds[i], true, amount, recipient);
                    updateCount++;
                }
            }
        }

        assembly {
            mstore(updates, updateCount)
        }

        return updates;
    }

    function prepShortPayouts(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256 listingId = getListingIdFromAddress(listingAddress, listingAgent);
        uint256[] memory payoutIds = listing.shortPayoutByIndexView(listingId);
        (uint256 xBalance, , , ) = listing.listingVolumeBalancesView();

        uint256 updateCount;
        PreparedPayoutUpdate[] memory updates = new PreparedPayoutUpdate[](payoutIds.length);

        for (uint256 i = 0; i < payoutIds.length && updateCount < 100; i++) {
            (, address recipient, uint256 required, uint256 filled, , uint8 status) = listing.getShortPayout(payoutIds[i]);
            if (status == 0 && required > filled) {
                uint256 amount = required - filled;
                if (amount > xBalance) {
                    amount = xBalance;
                }
                if (amount > 0) {
                    updates[updateCount] = PreparedPayoutUpdate(payoutIds[i], false, amount, recipient);
                    updateCount++;
                }
            }
        }

        assembly {
            mstore(updates, updateCount)
        }

        return updates;
    }

    function processOrder(ISSListing listing, address proxy, PreparedUpdate memory update, address token, bool isBuy)
        internal
        returns (ISSListing.UpdateType memory)
    {
        uint8 decimals = getDecimals(token, listing, isBuy);
        uint256 rawAmount = denormalize(update.amount, decimals);

        uint256 preBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);
        listing.transact(proxy, token, rawAmount, update.recipient);
        uint256 postBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);

        uint256 amountReceived = normalize(postBalance - preBalance, decimals);
        if (amountReceived < update.amount) {
            update.amount = amountReceived;
        }

        return ISSListing.UpdateType(
            isBuy ? 1 : 2,
            update.orderId,
            update.amount,
            address(0),
            update.recipient,
            0,
            0
        );
    }

    function processPayoutOrder(
        ISSListing listing,
        address proxy,
        PreparedPayoutUpdate memory update,
        address token,
        bool isLong
    ) internal returns (ISSListing.UpdateType memory, ISSListing.PayoutUpdate memory) {
        uint8 decimals = getDecimals(token, listing, !isLong);
        uint256 rawAmount = denormalize(update.amount, decimals);

        uint256 preBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);
        listing.transact(proxy, token, rawAmount, update.recipient);
        uint256 postBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);

        uint256 amountReceived = normalize(postBalance - preBalance, decimals);
        if (amountReceived < update.amount) {
            update.amount = amountReceived;
        }

        ISSListing.PayoutUpdate memory payoutUpdate = ISSListing.PayoutUpdate({
            payoutType: isLong ? 0 : 1,
            recipient: update.recipient,
            required: update.amount,
            price: 0,
            xBalance: 0,
            yBalance: 0,
            xVolume: 0,
            yVolume: 0
        });

        return (
            ISSListing.UpdateType(
                0,
                isLong ? 1 : 0,
                update.amount,
                address(0),
                update.recipient,
                0,
                0
            ),
            payoutUpdate
        );
    }

    function executeBuyOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        ISSListing listing = ISSListing(listingAddress);
        (uint256 xBalance, uint256 yBalance, , ) = listing.listingVolumeBalancesView();
        address tokenA = listing.tokenA();

        uint256 totalAmount;
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isBuy) {
                totalAmount += preparedUpdates[i].amount;
            }
        }

        require(xBalance >= totalAmount, "Insufficient xBalance");

        uint256 impactPrice = calculateImpactPrice(xBalance, yBalance, totalAmount, true);

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](preparedUpdates.length + 1);
        uint256 updateCount;

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isBuy && preparedUpdates[i].amount > 0) {
                updates[updateCount] = processOrder(listing, proxy, preparedUpdates[i], tokenA, true);
                updateCount++;
            }
        }

        if (updateCount > 0) {
            updates[updateCount] = ISSListing.UpdateType(0, 2, impactPrice, address(0), address(0), 0, 0);
            updateCount++;

            assembly {
                mstore(updates, updateCount)
            }

            listing.update(proxy, updates);
        }
    }

    function executeSellOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        ISSListing listing = ISSListing(listingAddress);
        (uint256 xBalance, uint256 yBalance, , ) = listing.listingVolumeBalancesView();
        address tokenB = listing.tokenB();

        uint256 totalAmount;
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (!preparedUpdates[i].isBuy) {
                totalAmount += preparedUpdates[i].amount;
            }
        }

        require(yBalance >= totalAmount, "Insufficient yBalance");

        uint256 impactPrice = calculateImpactPrice(xBalance, yBalance, totalAmount, false);

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](preparedUpdates.length + 1);
        uint256 updateCount;

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (!preparedUpdates[i].isBuy && preparedUpdates[i].amount > 0) {
                updates[updateCount] = processOrder(listing, proxy, preparedUpdates[i], tokenB, false);
                updateCount++;
            }
        }

        if (updateCount > 0) {
            updates[updateCount] = ISSListing.UpdateType(0, 2, impactPrice, address(0), address(0), 0, 0);
            updateCount++;

            assembly {
                mstore(updates, updateCount)
            }

            listing.update(proxy, updates);
        }
    }

    function getPayoutParams(ISSListing listing, bool isLong)
        internal
        view
        returns (uint256 xBalance, uint256 yBalance, address token, uint256 balance)
    {
        (xBalance, yBalance, , ) = listing.listingVolumeBalancesView();
        token = isLong ? listing.tokenB() : listing.tokenA();
        balance = isLong ? yBalance : xBalance;
    }

    function processPayoutUpdates(
        ISSListing listing,
        address proxy,
        PreparedPayoutUpdate[] memory preparedUpdates,
        bool isLong,
        address token,
        ISSListing.UpdateType[] memory updates,
        ISSListing.PayoutUpdate[] memory payoutUpdates
    ) internal returns (uint256 updateCount, uint256 payoutUpdateCount) {
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isLong == isLong && preparedUpdates[i].amount > 0) {
                (ISSListing.UpdateType memory update, ISSListing.PayoutUpdate memory payoutUpdate) = processPayoutOrder(
                    listing,
                    proxy,
                    preparedUpdates[i],
                    token,
                    isLong
                );
                updates[updateCount] = update;
                payoutUpdates[payoutUpdateCount] = payoutUpdate;
                updateCount++;
                payoutUpdateCount++;
            }
        }
    }

    function executeLongPayouts(address listingAddress, address proxy, PreparedPayoutUpdate[] memory preparedUpdates) external {
        ISSListing listing = ISSListing(listingAddress);
        (uint256 xBalance, uint256 yBalance, address token, uint256 balance) = getPayoutParams(listing, true);

        uint256 totalAmount;
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isLong && preparedUpdates[i].amount > 0) {
                totalAmount += preparedUpdates[i].amount;
            }
        }

        require(balance >= totalAmount, "Insufficient yBalance");

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](preparedUpdates.length);
        ISSListing.PayoutUpdate[] memory payoutUpdates = new ISSListing.PayoutUpdate[](preparedUpdates.length);
        (uint256 updateCount, uint256 payoutUpdateCount) = processPayoutUpdates(
            listing,
            proxy,
            preparedUpdates,
            true,
            token,
            updates,
            payoutUpdates
        );

        if (updateCount > 0) {
            assembly {
                mstore(updates, updateCount)
                mstore(payoutUpdates, payoutUpdateCount)
            }

            listing.update(proxy, updates);
            listing.ssUpdate(proxy, payoutUpdates);
        }
    }

    function executeShortPayouts(address listingAddress, address proxy, PreparedPayoutUpdate[] memory preparedUpdates) external {
        ISSListing listing = ISSListing(listingAddress);
        (uint256 xBalance, uint256 yBalance, address token, uint256 balance) = getPayoutParams(listing, false);

        uint256 totalAmount;
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (!preparedUpdates[i].isLong && preparedUpdates[i].amount > 0) {
                totalAmount += preparedUpdates[i].amount;
            }
        }

        require(balance >= totalAmount, "Insufficient xBalance");

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](preparedUpdates.length);
        ISSListing.PayoutUpdate[] memory payoutUpdates = new ISSListing.PayoutUpdate[](preparedUpdates.length);
        (uint256 updateCount, uint256 payoutUpdateCount) = processPayoutUpdates(
            listing,
            proxy,
            preparedUpdates,
            false,
            token,
            updates,
            payoutUpdates
        );

        if (updateCount > 0) {
            assembly {
                mstore(updates, updateCount)
                mstore(payoutUpdates, payoutUpdateCount)
            }

            listing.update(proxy, updates);
            listing.ssUpdate(proxy, payoutUpdates);
        }
    }
}