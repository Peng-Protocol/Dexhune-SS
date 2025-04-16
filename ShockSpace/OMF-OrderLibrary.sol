// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.13 (Updated)
// Changes:
// - From v0.0.12: Added denormalize function to handle non-18 decimal tokens (new in v0.0.13).
// - From v0.0.12: Updated executeRefundAndUpdate to denormalize refundAmount before transact (new in v0.0.13).
// - Side effects: Corrects refund amounts for tokens with non-18 decimals (e.g., USDC); aligns with MFP-OrderLibrary v0.0.8.
// - No changes to prepBuyOrder, prepSellOrder, executeBuyOrder, executeSellOrder, adjustOrder.
// - Retains fixes from v0.0.12: Fixed stack-too-deep in clearOrders/clearSingleOrder using ClearOrderState and helpers.
// - Retains alignment with OMFListingTemplate’s implicit listingId (from v0.0.9).

import "./imports/SafeERC20.sol";

interface IOMF {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IOMFListing {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function token0() external view returns (address);
    function baseToken() external view returns (address);
    function liquidityAddress() external view returns (address);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function listingPriceView() external view returns (uint256);
    function buyOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint8 status
    );
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function nextOrderId() external returns (uint256);
}

interface IOMFLiquidity {
    function addFees(address caller, bool isX, uint256 fee) external;
}

interface IOMFOrderLibrary {
    struct BuyOrderDetails {
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct SellOrderDetails {
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IOMFListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    function prepBuyOrder(
        address listingAddress,
        BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory);

    function prepSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory);

    function executeBuyOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;

    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external;

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address user
    ) external;

    function adjustOrder(
        address listing,
        bool isBuy,
        uint256 actualAmount,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external;
}

library OMFOrderLibrary {
    using SafeERC20 for IERC20;

    struct ExecutionState {
        IOMFListing listing;
        IOMFLiquidity liquidity;
        address liquidityAddress;
    }

    struct ClearOrderState {
        address makerAddress;
        address recipientAddress;
        uint256 pending;
        uint8 status;
        address refundTo;
        uint256 refundAmount;
        address token;
    }

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    // Helper functions
    function _transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = IERC20(token).balanceOf(target);
        IERC20(token).safeTransferFrom(msg.sender, target, amount);
        uint256 postBalance = IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function _normalizeAndFee(address token, uint256 amount) internal view returns (uint256 normalized, uint256 fee, uint256 principal) {
        uint8 decimals = IERC20(token).decimals();
        normalized = amount;
        if (decimals != 18) {
            if (decimals < 18) normalized = amount * (10 ** (18 - decimals));
            else normalized = amount / (10 ** (decimals - 18));
        }
        fee = (normalized * 5) / 10000; // 0.05% fee
        principal = normalized - fee;
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10**(18 - decimals);
        else return amount * 10**(decimals - 18);
    }

    function _createOrderUpdate(
        uint8 updateType,
        uint256 orderId,
        uint256 principal,
        address maker,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice
    ) internal pure returns (IOMFListing.UpdateType[] memory) {
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](1);
        updates[0] = IOMFListing.UpdateType(updateType, orderId, principal, maker, recipient, maxPrice, minPrice);
        return updates;
    }

    function validateAndPrepareRefund(
        IOMFListing listing,
        uint256 orderId,
        bool isBuy,
        address user
    ) internal view returns (ClearOrderState memory orderState, bool isValid) {
        orderState = ClearOrderState({
            makerAddress: address(0),
            recipientAddress: address(0),
            pending: 0,
            status: 0,
            refundTo: address(0),
            refundAmount: 0,
            token: address(0)
        });

        if (isBuy) {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = listing.buyOrders(orderId);
            if (status == 1 || status == 2) {
                if (makerAddress != user) return (orderState, false);
                orderState.makerAddress = makerAddress;
                orderState.recipientAddress = recipientAddress;
                orderState.pending = pending;
                orderState.status = status;
                orderState.refundTo = recipientAddress != address(0) ? recipientAddress : makerAddress;
                orderState.refundAmount = pending;
                orderState.token = listing.token0();
                return (orderState, true);
            }
        } else {
            (
                address makerAddress,
                address recipientAddress/,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = listing.sellOrders(orderId);
            if (status == 1 || status == 2) {
                if (makerAddress != user) return (orderState, false);
                orderState.makerAddress = makerAddress;
                orderState.recipientAddress = recipientAddress;
                orderState.pending = pending;
                orderState.status = status;
                orderState.refundTo = recipientAddress != address(0) ? recipientAddress : makerAddress;
                orderState.refundAmount = pending;
                orderState.token = listing.baseToken();
                return (orderState, true);
            }
        }
        return (orderState, false);
    }

    function executeRefundAndUpdate(
        IOMFListing listing,
        address proxy,
        ClearOrderState memory orderState,
        IOMFListing.UpdateType[] memory updates,
        uint256 updateIndex,
        bool isBuy,
        uint256 orderId
    ) internal {
        if (orderState.refundAmount > 0) {
            uint8 decimals = IERC20(orderState.token).decimals();
            uint256 rawAmount = denormalize(orderState.refundAmount, decimals);
            listing.transact(proxy, orderState.token, rawAmount, orderState.refundTo);
        }
        updates[updateIndex] = IOMFListing.UpdateType(
            isBuy ? 1 : 2,
            orderId,
            0,
            address(0),
            address(0),
            0,
            0
        );
        emit OrderCancelled(orderId);
    }

    // Prep functions
    function prepBuyOrder(
        address listingAddress,
        IOMFOrderLibrary.BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.token0();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = listing.nextOrderId();
        prepData.updates = _createOrderUpdate(
            1, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    function prepSellOrder(
        address listingAddress,
        IOMFOrderLibrary.SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.baseToken();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = listing.nextOrderId();
        prepData.updates = _createOrderUpdate(
            2, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    // Execute functions
    function executeBuyOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listing = IOMFListing(listingAddress);
        address liquidityAddr = listing.liquidityAddress();
        ExecutionState memory state = ExecutionState(listing, IOMFLiquidity(liquidityAddr), liquidityAddr);
        processExecuteBuyOrder(prep, state, proxy);
    }

    function processExecuteBuyOrder(
        OrderPrep memory prep,
        ExecutionState memory state,
        address proxy
    ) internal {
        uint256 receivedPrincipal = _transferToken(prep.token, address(state.listing), prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, state.liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        state.listing.update(proxy, prep.updates);
        state.liquidity.addFees(proxy, true, prep.fee);

        IOMFListing.UpdateType[] memory historicalUpdate = new IOMFListing.UpdateType[](1);
        (
            uint256 xBalance,
            uint256 yBalance,
            uint256 xVolume,
            uint256 yVolume
        ) = state.listing.listingVolumeBalancesView();
        historicalUpdate[0] = IOMFListing.UpdateType(
            3, 0, state.listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        state.listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, true, msg.sender);
    }

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listing = IOMFListing(listingAddress);
        address liquidityAddr = listing.liquidityAddress();
        ExecutionState memory state = ExecutionState(listing, IOMFLiquidity(liquidityAddr), liquidityAddr);
        processExecuteSellOrder(prep, state, proxy);
    }

    function processExecuteSellOrder(
        OrderPrep memory prep,
        ExecutionState memory state,
        address proxy
    ) internal {
        uint256 receivedPrincipal = _transferToken(prep.token, address(state.listing), prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, state.liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        state.listing.update(proxy, prep.updates);
        state.liquidity.addFees(proxy, false, prep.fee);

        IOMFListing.UpdateType[] memory historicalUpdate = new IOMFListing.UpdateType[](1);
        (
            uint256 xBalance,
            uint256 yBalance,
            uint256 xVolume,
            uint256 yVolume
        ) = state.listing.listingVolumeBalancesView();
        historicalUpdate[0] = IOMFListing.UpdateType(
            3, 0, state.listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        state.listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, false, msg.sender);
    }

    // Clear functions
    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external {
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);

        (ClearOrderState memory orderState, bool isValid) = validateAndPrepareRefund(listing, orderId, isBuy, msg.sender);
        require(isValid, "Order not active or not maker");

        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](1);
        executeRefundAndUpdate(listing, proxy, orderState, updates, 0, isBuy, orderId);

        listing.update(proxy, updates);
    }

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address user
    ) external {
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);
        (bool success, bytes memory returnData) = listingAddress.staticcall(
            abi.encodeWithSignature("makerPendingOrdersView(address)", user)
        );
        require(success, "Failed to fetch user orders");
        uint256[] memory userOrders = abi.decode(returnData, (uint256[]));

        if (userOrders.length == 0) return;

        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](userOrders.length);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < userOrders.length; i++) {
            bool isValid;
            ClearOrderState memory orderState;

            // Try buy order
            (orderState, isValid) = validateAndPrepareRefund(listing, userOrders[i], true, user);
            if (isValid) {
                executeRefundAndUpdate(listing, proxy, orderState, updates, updateCount, true, userOrders[i]);
                updateCount++;
                continue;
            }

            // Try sell order
            (orderState, isValid) = validateAndPrepareRefund(listing, userOrders[i], false, user);
            if (isValid) {
                executeRefundAndUpdate(listing, proxy, orderState, updates, updateCount, false, userOrders[i]);
                updateCount++;
            }
        }

        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }

    // Retained for backward compatibility (optional)
    function adjustOrder(
        address listing,
        bool isBuy,
        uint256 actualAmount,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        IOMFListing listingContract = IOMFListing(listing);
        (uint256 normalized, , uint256 principal) = _normalizeAndFee(isBuy ? listingContract.token0() : listingContract.baseToken(), actualAmount);
        IOMFListing.UpdateType[] memory updates = _createOrderUpdate(
            isBuy ? 1 : 2, orderId, principal, msg.sender, recipient, maxPrice, minPrice
        );
        listingContract.update(msg.sender, updates);
    }
}