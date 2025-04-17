// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.12 (Updated)
// Changes:
// - From v0.0.11: Updated processPayoutOrder to set PayoutUpdate.required to amountReceived for tax-on-transfer adjustments (new in v0.0.12).
// - From v0.0.11: Added getDecimals function to fallback to IERC20.decimals() if decimalsA/decimalsB are unavailable (new in v0.0.12).
// - From v0.0.11: Updated processOrder and processPayoutOrder to use getDecimals (new in v0.0.12).
// - From v0.0.11: Modified prepLongPayoutLiquid to cap amount at yBalance (tokenB) instead of xBalance.
// - From v0.0.11: Modified prepShortPayoutLiquid to cap amount at xBalance (tokenA) instead of yBalance.
// - From v0.0.11: Updated executeLongPayoutLiquid to use tokenB and yBalance for long payouts.
// - From v0.0.11: Updated executeShortPayoutLiquid to use tokenA and xBalance for short payouts.
// - From v0.0.11: Updated processPayoutOrder to use decimalsB for long, decimalsA for short payouts.
// - Side effects: Ensures tax-on-transfer adjustments are reflected in payout state updates; improves decimals handling robustness.
// - Note: decimalsA and decimalsB not implemented in SS-ListingTemplate.sol; fallback to IERC20.decimals() added.

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
        uint8 payoutType;
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
    function getBuyOrder(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint8 status
    );
    function getSellOrder(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint8 status
    );
    function liquidityAddresses(uint256 index) external view returns (address);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

interface ISSLiquidity {
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function claimFees(address caller, uint256 liquidityIndex, bool isX, uint256 volume) external;
}

library SSLiquidLibrary {
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

    struct BalanceData {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    struct PayoutContext {
        ISSListing listing;
        ISSLiquidity liquidity;
        address proxy;
        address token;
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

    function processOrder(
        ISSListing listing,
        ISSLiquidity liquidity,
        address proxy,
        PreparedUpdate memory update,
        address token,
        bool isBuy
    ) internal returns (ISSListing.UpdateType memory) {
        uint8 decimals = getDecimals(token, listing, isBuy);
        uint256 rawAmount = denormalize(update.amount, decimals);

        liquidity.updateLiquidity(proxy, isBuy, update.amount);

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
        PayoutContext memory ctx,
        PreparedPayoutUpdate memory update,
        bool isLong
    ) internal returns (ISSListing.UpdateType memory, ISSListing.PayoutUpdate memory) {
        uint8 decimals = getDecimals(ctx.token, ctx.listing, !isLong);
        uint256 rawAmount = denormalize(update.amount, decimals);

        ctx.liquidity.updateLiquidity(ctx.proxy, isLong, update.amount);

        uint256 preBalance = ctx.token == address(0) ? update.recipient.balance : IERC20(ctx.token).balanceOf(update.recipient);
        ctx.listing.transact(ctx.proxy, ctx.token, rawAmount, update.recipient);
        uint256 postBalance = ctx.token == address(0) ? update.recipient.balance : IERC20(ctx.token).balanceOf(update.recipient);

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

    function appendPayoutUpdate(
        ISSListing.UpdateType[] memory updates,
        ISSListing.PayoutUpdate[] memory payoutUpdates,
        uint256 count,
        PreparedPayoutUpdate memory preparedUpdate,
        PayoutContext memory ctx,
        bool isLong
    ) internal returns (uint256) {
        (ISSListing.UpdateType memory update, ISSListing.PayoutUpdate memory payoutUpdate) = processPayoutOrder(
            ctx,
            preparedUpdate,
            isLong
        );
        updates[count] = update;
        payoutUpdates[count] = payoutUpdate;
        return count + 1;
    }

    function appendFinalUpdates(
        ISSListing.UpdateType[] memory updates,
        uint256 updateCount,
        uint256 impactPrice,
        uint256 newXBal,
        uint256 newYBal,
        uint256 xVolume,
        uint256 yVolume
    ) internal pure returns (uint256) {
        updates[updateCount] = ISSListing.UpdateType(0, 2, impactPrice, address(0), address(0), 0, 0);
        updateCount++;

        updates[updateCount] = ISSListing.UpdateType(
            3,
            0,
            impactPrice,
            address(0),
            address(0),
            newXBal << 128 | newYBal,
            xVolume << 128 | yVolume
        );
        updateCount++;

        return updateCount;
    }

    function processPayouts(
        PreparedPayoutUpdate[] memory preparedUpdates,
        PayoutContext memory ctx,
        BalanceData memory balances,
        bool isLong
    ) internal returns (ISSListing.UpdateType[] memory, ISSListing.PayoutUpdate[] memory, uint256) {
        uint256 totalAmount;
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isLong == isLong) {
                totalAmount += preparedUpdates[i].amount;
            }
        }

        require((isLong ? balances.yBalance : balances.xBalance) >= totalAmount, "Insufficient balance");

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](preparedUpdates.length);
        ISSListing.PayoutUpdate[] memory payoutUpdates = new ISSListing.PayoutUpdate[](preparedUpdates.length);
        uint256 count;

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isLong == isLong && preparedUpdates[i].amount > 0) {
                count = appendPayoutUpdate(
                    updates,
                    payoutUpdates,
                    count,
                    preparedUpdates[i],
                    ctx,
                    isLong
                );
            }
        }

        return (updates, payoutUpdates, count);
    }

    function prepBuyLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256[] memory orders = listing.pendingSellOrdersView();

        uint256 updateCount;
        PreparedUpdate[] memory updates = new PreparedUpdate[](orders.length);

        for (uint256 i = 0; i < orders.length && updateCount < 100; i++) {
            (, address recipient, , , uint256 amount, , uint8 status) = listing.getSellOrder(orders[i]);
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

    function prepSellLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256[] memory orders = listing.pendingBuyOrdersView();

        uint256 updateCount;
        PreparedUpdate[] memory updates = new PreparedUpdate[](orders.length);

        for (uint256 i = 0; i < orders.length && updateCount < 100; i++) {
            (, address recipient, , , uint256 amount, , uint8 status) = listing.getBuyOrder(orders[i]);
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

    function prepLongPayoutLiquid(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256[] memory payoutIds = listing.longPayoutByIndexView(0);
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

    function prepShortPayoutLiquid(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        uint256[] memory payoutIds = listing.shortPayoutByIndexView(0);
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

    function executeBuyLiquid(
        address listingAddress,
        address listingAgent,
        address proxy,
        PreparedUpdate[] memory preparedUpdates
    ) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        BalanceData memory balances;
        (balances.xBalance, balances.yBalance, balances.xVolume, balances.yVolume) = listing.listingVolumeBalancesView();
        address tokenA = listing.tokenA();

        uint256 totalAmount;
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isBuy) {
                totalAmount += preparedUpdates[i].amount;
            }
        }

        require(balances.xBalance >= totalAmount, "Insufficient xBalance");

        uint256 impactPrice = calculateImpactPrice(balances.xBalance, balances.yBalance, totalAmount, true);

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](preparedUpdates.length + 2);
        uint256 updateCount;

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].isBuy && preparedUpdates[i].amount > 0) {
                updates[updateCount] = processOrder(listing, liquidity, proxy, preparedUpdates[i], tokenA, true);
                updateCount++;
            }
        }

        if (updateCount > 0) {
            updateCount = appendFinalUpdates(
                updates,
                updateCount,
                impactPrice,
                balances.xBalance - totalAmount,
                balances.yBalance + totalAmount,
                balances.xVolume,
                balances.yVolume
            );

            assembly {
                mstore(updates, updateCount)
            }

            listing.update(proxy, updates);
        }
    }

    function executeSellLiquid(
        address listingAddress,
        address listingAgent,
        address proxy,
        PreparedUpdate[] memory preparedUpdates
    ) external {
        ISSListing listing = ISSListing(listingAddress);
        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        BalanceData memory balances;
        (balances.xBalance, balances.yBalance, balances.xVolume, balances.yVolume) = listing.listingVolumeBalancesView();
        address tokenB = listing.tokenB();

        uint256 totalAmount;
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (!preparedUpdates[i].isBuy) {
                totalAmount += preparedUpdates[i].amount;
            }
        }

        require(balances.yBalance >= totalAmount, "Insufficient yBalance");

        uint256 impactPrice = calculateImpactPrice(balances.xBalance, balances.yBalance, totalAmount, false);

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](preparedUpdates.length + 2);
        uint256 updateCount;

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (!preparedUpdates[i].isBuy && preparedUpdates[i].amount > 0) {
                updates[updateCount] = processOrder(listing, liquidity, proxy, preparedUpdates[i], tokenB, false);
                updateCount++;
            }
        }

        if (updateCount > 0) {
            updateCount = appendFinalUpdates(
                updates,
                updateCount,
                impactPrice,
                balances.xBalance + totalAmount,
                balances.yBalance - totalAmount,
                balances.xVolume,
                balances.yVolume
            );

            assembly {
                mstore(updates, updateCount)
            }

            listing.update(proxy, updates);
        }
    }

    function executeLongPayoutLiquid(
        address listingAddress,
        address listingAgent,
        address proxy,
        PreparedPayoutUpdate[] memory preparedUpdates
    ) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        PayoutContext memory ctx = PayoutContext({
            listing: ISSListing(listingAddress),
            liquidity: ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(0)),
            proxy: proxy,
            token: ISSListing(listingAddress).tokenB()
        });

        BalanceData memory balances;
        (, balances.yBalance, , ) = ctx.listing.listingVolumeBalancesView();

        (ISSListing.UpdateType[] memory updates, ISSListing.PayoutUpdate[] memory payoutUpdates, uint256 count) = processPayouts(
            preparedUpdates,
            ctx,
            balances,
            true
        );

        if (count > 0) {
            assembly {
                mstore(updates, count)
                mstore(payoutUpdates, count)
            }

            ctx.listing.update(ctx.proxy, updates);
            ctx.listing.ssUpdate(ctx.proxy, payoutUpdates);
        }
    }

    function executeShortPayoutLiquid(
        address listingAddress,
        address listingAgent,
        address proxy,
        PreparedPayoutUpdate[] memory preparedUpdates
    ) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        PayoutContext memory ctx = PayoutContext({
            listing: ISSListing(listingAddress),
            liquidity: ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(0)),
            proxy: proxy,
            token: ISSListing(listingAddress).tokenA()
        });

        BalanceData memory balances;
        (balances.xBalance, , , ) = ctx.listing.listingVolumeBalancesView();

        (ISSListing.UpdateType[] memory updates, ISSListing.PayoutUpdate[] memory payoutUpdates, uint256 count) = processPayouts(
            preparedUpdates,
            ctx,
            balances,
            false
        );

        if (count > 0) {
            assembly {
                mstore(updates, count)
                mstore(payoutUpdates, count)
            }

            ctx.listing.update(ctx.proxy, updates);
            ctx.listing.ssUpdate(ctx.proxy, payoutUpdates);
        }
    }

    function xClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSLiquidity liquidity = ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(0));
        liquidity.claimFees(proxy, liquidityIndex, true, 0);
    }

    function yClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSLiquidity liquidity = ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(0));
        liquidity.claimFees(proxy, liquidityIndex, false, 0);
    }
}