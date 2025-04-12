// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1 (Updated)
// Changes:
// - Renamed all MFP references to SS for consistency with suite (previous update).
// - Updated clearOrders to only cancel orders where msg.sender == maker, using makerPendingOrdersView (new in v0.0.1).
// - Updated clearOrders signature to include caller parameter (new in v0.0.1).
// - Fixed clearOrders status check to status == 0, aligning with pending orders (new in v0.0.1).
// - Fixed clearSingleOrder status check to status == 0 || 1, allowing partial fills (new in v0.0.1).
// - Moved BuyOrderDetails and SellOrderDetails to ISSOrderLibrary interface for type safety (new in v0.0.1).
// - Fixed clearOrders stack too deep error: Added OrderClearData struct, _processOrderClear, and _executeRefund helpers (new fix).

import "./imports/SafeERC20.sol";

interface ISS {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface ISSListing {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;
        uint256 value;
        address maker;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function buyOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function listingPriceView() external view returns (uint256);
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
}

interface ISSLiquidity {
    function addFees(address caller, bool isX, uint256 fee) external;
}

library SSOrderLibrary {
    using SafeERC20 for IERC20;

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        ISSListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    struct PrepData {
        uint256 normalized;
        uint256 fee;
        uint256 principal;
        uint256 orderId;
        ISSListing.UpdateType[] updates;
        address token;
    }

    struct OrderClearData {
        address maker;
        address recipient;
        uint256 pending;
        uint8 status;
        address token;
        bool isBuy;
        address refundTo;
    }

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    // Helper functions
    function _transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient ETH amount");
            (bool success, ) = target.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, target, amount);
        }
        uint256 postBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function _normalizeAndFee(address token, uint256 amount) internal view returns (uint256 normalized, uint256 fee, uint256 principal) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        normalized = amount;
        if (decimals != 18) {
            if (decimals < 18) normalized = amount * (10 ** (uint256(18) - uint256(decimals)));
            else normalized = amount / (10 ** (uint256(decimals) - uint256(18)));
        }
        fee = (normalized * 5) / 10000; // 0.05% fee
        principal = normalized - fee;
    }

    function _createOrderUpdate(
        uint8 updateType,
        uint256 orderId,
        uint256 principal,
        address maker,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice
    ) internal pure returns (ISSListing.UpdateType[] memory) {
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1);
        updates[0] = ISSListing.UpdateType(updateType, orderId, principal, maker, recipient, maxPrice, minPrice);
        return updates;
    }

    function _processOrderClear(
        ISSListing listing,
        uint256 orderId,
        address caller
    ) internal view returns (OrderClearData memory data, ISSListing.UpdateType memory update, bool valid) {
        OrderClearData memory result;

        // Check buy order
        {
            address maker;
            address recipient;
            uint256 pending;
            uint8 status;
            (maker, recipient, , , pending, , status) = listing.buyOrders(orderId);
            if (status == 0 && maker == caller) {
                result.isBuy = true;
                result.token = listing.tokenA();
                result.maker = maker;
                result.recipient = recipient;
                result.pending = pending;
                result.status = status;
            }
        }

        // Check sell order if buy order not valid
        if (!result.isBuy) {
            address maker;
            address recipient;
            uint256 pending;
            uint8 status;
            (maker, recipient, , , pending, , status) = listing.sellOrders(orderId);
            if (status == 0 && maker == caller) {
                result.isBuy = false;
                result.token = listing.tokenB();
                result.maker = maker;
                result.recipient = recipient;
                result.pending = pending;
                result.status = status;
            } else {
                return (result, ISSListing.UpdateType(0, 0, 0, address(0), address(0), 0, 0), false);
            }
        }

        result.refundTo = result.recipient != address(0) ? result.recipient : result.maker;
        ISSListing.UpdateType[] memory updates = _createOrderUpdate(
            result.isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0
        );
        return (result, updates[0], true);
    }

    function _executeRefund(
        ISSListing listing,
        address proxy,
        address token,
        uint256 pending,
        address refundTo
    ) internal {
        if (pending > 0) {
            listing.transact(proxy, token, pending, refundTo);
        }
    }

    // Prep functions
    function prepBuyOrder(
        address listingAddress,
        ISSOrderLibrary.BuyOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSListing listing = ISSListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.tokenA();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = orderId;
        prepData.updates = _createOrderUpdate(
            1, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    function prepSellOrder(
        address listingAddress,
        ISSOrderLibrary.SellOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSListing listing = ISSListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.tokenB();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = orderId;
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
        ISSListing listing = ISSListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses(0);
        ISSLiquidity liquidity = ISSLiquidity(liquidityAddress);

        uint256 receivedPrincipal = _transferToken(prep.token, listingAddress, prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        listing.update(proxy, prep.updates);
        liquidity.addFees(proxy, true, prep.fee);

        ISSListing.UpdateType[] memory historicalUpdate = new ISSListing.UpdateType[](1);
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        (xBalance, yBalance, xVolume, yVolume) = listing.listingVolumeBalancesView();
        historicalUpdate[0] = ISSListing.UpdateType(
            3, 0, listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, true, msg.sender);
    }

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        ISSListing listing = ISSListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses(0);
        ISSLiquidity liquidity = ISSLiquidity(liquidityAddress);

        uint256 receivedPrincipal = _transferToken(prep.token, listingAddress, prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        listing.update(proxy, prep.updates);
        liquidity.addFees(proxy, false, prep.fee);

        ISSListing.UpdateType[] memory historicalUpdate = new ISSListing.UpdateType[](1);
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        (xBalance, yBalance, xVolume, yVolume) = listing.listingVolumeBalancesView();
        historicalUpdate[0] = ISSListing.UpdateType(
            3, 0, listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

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
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSListing listing = ISSListing(listingAddress);

        address refundTo;
        uint256 refundAmount;
        address token;
        if (isBuy) {
            address maker;
            address recipient;
            uint256 pending;
            uint8 status;
            (maker, recipient, , , pending, , status) = listing.buyOrders(orderId);
            require(status == 0 || status == 1, "Order not active");
            require(maker == msg.sender, "Not order maker");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenA();
        } else {
            address maker;
            address recipient;
            uint256 pending;
            uint8 status;
            (maker, recipient, , , pending, , status) = listing.sellOrders(orderId);
            require(status == 0 || status == 1, "Order not active");
            require(maker == msg.sender, "Not order maker");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenB();
        }

        if (refundAmount > 0) {
            listing.transact(proxy, token, refundAmount, refundTo);
        }

        ISSListing.UpdateType[] memory updates = _createOrderUpdate(isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0);
        listing.update(proxy, updates);
        emit OrderCancelled(orderId);
    }

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address caller
    ) external returns (ISSListing.UpdateType[] memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSListing listing = ISSListing(listingAddress);
        uint256[] memory orderIds = listing.makerPendingOrdersView(caller);

        if (orderIds.length == 0) return new ISSListing.UpdateType[](0);

        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](orderIds.length);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 orderId = orderIds[i];
            (OrderClearData memory data, ISSListing.UpdateType memory update, bool valid) = _processOrderClear(listing, orderId, caller);
            if (!valid) continue;

            _executeRefund(listing, proxy, data.token, data.pending, data.refundTo);
            updates[updateCount] = update;
            updateCount++;
            emit OrderCancelled(orderId);
        }

        if (updateCount == 0) return new ISSListing.UpdateType[](0);

        assembly { mstore(updates, updateCount) }
        return updates;
    }
}

interface ISSOrderLibrary {
    struct BuyOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }

    struct SellOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        ISSListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    function prepBuyOrder(
        address listingAddress,
        BuyOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory);

    function prepSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory);

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
        address caller
    ) external returns (ISSListing.UpdateType[] memory);
}