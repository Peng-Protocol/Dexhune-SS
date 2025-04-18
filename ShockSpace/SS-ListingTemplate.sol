// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.4 (Updated)
// Changes:
// - Added decimalsA, decimalsB state variables and view functions to fulfill ISSListing interface (new in v0.0.4).
// - Updated setTokens to initialize decimalsA, decimalsB based on tokenA, tokenB (new in v0.0.4).
// - Side effects: Resolves payout failures in SS-SettlementLibrary.sol and SS-LiquidLibrary.sol by providing decimalsA(), decimalsB().
// - No changes to update, transact, ssUpdate, or existing view functions (e.g., getBuyOrder, listingVolumeBalancesView).
// - Retained normalize, denormalize functions for transact compatibility.
// - Compatible with SS-LiquidityTemplate.sol (v0.0.3), SS-LiquidSlotLibrary.sol (v0.0.2), SS-OrderLibrary.sol (v0.0.1).

import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";

contract SSListingTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => bool) public routers;
    bool public routersSet;
    address public tokenA;
    address public tokenB;
    uint8 public decimalsA;
    uint8 public decimalsB;
    uint256 public listingId;
    mapping(uint256 => uint256) public nextOrderId;

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

    struct VolumeBalance {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    struct BuyOrder {
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 pending;
        uint256 filled;
        uint8 status;
    }

    struct SellOrder {
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 pending;
        uint256 filled;
        uint8 status;
    }

    struct LongPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }

    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }

    struct HistoricalData {
        uint256 price;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        uint256 timestamp;
    }

    mapping(uint256 => VolumeBalance) public volumeBalances;
    mapping(uint256 => address) public liquidityAddresses;
    mapping(uint256 => uint256) public prices;
    mapping(uint256 => BuyOrder) public buyOrders;
    mapping(uint256 => SellOrder) public sellOrders;
    mapping(uint256 => LongPayoutStruct) public longPayouts;
    mapping(uint256 => ShortPayoutStruct) public shortPayouts;
    mapping(uint256 => uint256[]) public pendingBuyOrders;
    mapping(uint256 => uint256[]) public pendingSellOrders;
    mapping(uint256 => uint256[]) public longPayoutByIndex;
    mapping(uint256 => uint256[]) public shortPayoutByIndex;
    mapping(address => uint256[]) public makerPendingOrders;
    mapping(address => uint256[]) public userPayoutIDs;
    mapping(uint256 => HistoricalData[]) public historicalData;

    event OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status);
    event PayoutOrderCreated(uint256 listingId, uint256 orderId, bool isLong, uint8 status);
    event BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance);

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                break;
            }
        }
    }

    function setRouters(address[] memory _routers) external {
        require(!routersSet, "Routers already set");
        require(_routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i] != address(0), "Invalid router address");
            routers[_routers[i]] = true;
        }
        routersSet = true;
    }

    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setLiquidityAddress(address _liquidityAddress) external {
        require(liquidityAddresses[listingId] == address(0), "Liquidity already set");
        require(_liquidityAddress != address(0), "Invalid liquidity address");
        liquidityAddresses[listingId] = _liquidityAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
        decimalsA = _tokenA == address(0) ? 18 : IERC20(_tokenA).decimals();
        decimalsB = _tokenB == address(0) ? 18 : IERC20(_tokenB).decimals();
    }

    function update(address caller, UpdateType[] memory updates) external nonReentrant {
        require(routers[caller], "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) {
                if (u.index == 0) balances.xBalance = u.value;
                else if (u.index == 1) balances.yBalance = u.value;
                else if (u.index == 2) balances.xVolume += u.value;
                else if (u.index == 3) balances.yVolume += u.value;
            } else if (u.updateType == 1) {
                BuyOrder storage order = buyOrders[u.index];
                if (order.makerAddress == address(0)) {
                    order.makerAddress = u.maker;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.pending = u.value;
                    order.status = 1;
                    pendingBuyOrders[listingId].push(u.index);
                    makerPendingOrders[u.maker].push(u.index);
                    balances.yBalance += u.value;
                    balances.yVolume += u.value;
                    nextOrderId[listingId] = u.index + 1;
                    emit OrderUpdated(listingId, u.index, true, 1);
                } else if (u.value == 0) {
                    order.status = 0;
                    removePendingOrder(pendingBuyOrders[listingId], u.index);
                    removePendingOrder(makerPendingOrders[u.maker], u.index);
                    emit OrderUpdated(listingId, u.index, true, 0);
                } else if (order.status == 1) {
                    require(order.pending >= u.value, "Insufficient pending");
                    order.pending -= u.value;
                    order.filled += u.value;
                    balances.xBalance -= u.value;
                    order.status = order.pending == 0 ? 3 : 2;
                    if (order.pending == 0) {
                        removePendingOrder(pendingBuyOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    emit OrderUpdated(listingId, u.index, true, order.status);
                }
            } else if (u.updateType == 2) {
                SellOrder storage order = sellOrders[u.index];
                if (order.makerAddress == address(0)) {
                    order.makerAddress = u.maker;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.pending = u.value;
                    order.status = 1;
                    pendingSellOrders[listingId].push(u.index);
                    makerPendingOrders[u.maker].push(u.index);
                    balances.xBalance += u.value;
                    balances.xVolume += u.value;
                    nextOrderId[listingId] = u.index + 1;
                    emit OrderUpdated(listingId, u.index, false, 1);
                } else if (u.value == 0) {
                    order.status = 0;
                    removePendingOrder(pendingSellOrders[listingId], u.index);
                    removePendingOrder(makerPendingOrders[u.maker], u.index);
                    emit OrderUpdated(listingId, u.index, false, 0);
                } else if (order.status == 1) {
                    require(order.pending >= u.value, "Insufficient pending");
                    order.pending -= u.value;
                    order.filled += u.value;
                    balances.yBalance -= u.value;
                    order.status = order.pending == 0 ? 3 : 2;
                    if (order.pending == 0) {
                        removePendingOrder(pendingSellOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    emit OrderUpdated(listingId, u.index, false, order.status);
                }
            } else if (u.updateType == 3) {
                historicalData[listingId].push(HistoricalData(
                    u.value,
                    u.maxPrice >> 128, u.maxPrice & ((1 << 128) - 1),
                    u.minPrice >> 128, u.minPrice & ((1 << 128) - 1),
                    block.timestamp
                ));
            }
        }

        if (balances.xBalance > 0 && balances.yBalance > 0) {
            prices[listingId] = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(listingId, balances.xBalance, balances.yBalance);
    }

    function ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates) external nonReentrant {
        require(routers[caller], "Router only");
        uint256 currentListingId = listingId;

        for (uint256 i = 0; i < payoutUpdates.length; i++) {
            PayoutUpdate memory p = payoutUpdates[i];
            uint256 orderId = nextOrderId[currentListingId];

            if (p.payoutType == 0) {
                LongPayoutStruct storage payout = longPayouts[orderId];
                payout.makerAddress = caller;
                payout.recipientAddress = p.recipient;
                payout.required = p.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = 0;
                longPayoutByIndex[currentListingId].push(orderId);
                userPayoutIDs[p.recipient].push(orderId);
                emit PayoutOrderCreated(currentListingId, orderId, true, 0);
            } else if (p.payoutType == 1) {
                ShortPayoutStruct storage payout = shortPayouts[orderId];
                payout.makerAddress = caller;
                payout.recipientAddress = p.recipient;
                payout.required = p.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = 0;
                shortPayoutByIndex[currentListingId].push(orderId);
                userPayoutIDs[p.recipient].push(orderId);
                emit PayoutOrderCreated(currentListingId, orderId, false, 0);
            } else {
                revert("Invalid payout type");
            }
            nextOrderId[currentListingId] = orderId + 1;
        }
    }

    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        require(routers[caller], "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (token == tokenA) {
            require(balances.xBalance >= normalizedAmount, "Insufficient xBalance");
            balances.xBalance -= normalizedAmount;
            balances.xVolume += normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else if (token == tokenB) {
            require(balances.yBalance >= normalizedAmount, "Insufficient yBalance");
            balances.yBalance -= normalizedAmount;
            balances.yVolume += normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else {
            revert("Invalid token");
        }
        if (balances.xBalance > 0 && balances.yBalance > 0) {
            prices[listingId] = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(listingId, balances.xBalance, balances.yBalance);
    }

    function viewDecimalsA() external view returns (uint8) {
        return decimalsA;
    }

    function viewDecimalsB() external view returns (uint8) {
        return decimalsB;
    }

    function getListingId() external view returns (uint256) {
        return listingId;
    }

    function getNextOrderId(uint256 _listingId) external view returns (uint256) {
        return nextOrderId[_listingId];
    }

    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        VolumeBalance memory bal = volumeBalances[listingId];
        return (bal.xBalance, bal.yBalance, bal.xVolume, bal.yVolume);
    }

    function listingPriceView() external view returns (uint256) {
        return prices[listingId];
    }

    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return pendingBuyOrders[listingId];
    }

    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return pendingSellOrders[listingId];
    }

    function makerPendingOrdersView(address maker) external view returns (uint256[] memory) {
        return makerPendingOrders[maker];
    }

    function longPayoutByIndexView(uint256 listingId) external view returns (uint256[] memory) {
        return longPayoutByIndex[listingId];
    }

    function shortPayoutByIndexView(uint256 listingId) external view returns (uint256[] memory) {
        return shortPayoutByIndex[listingId];
    }

    function userPayoutIDsView(address user) external view returns (uint256[] memory) {
        return userPayoutIDs[user];
    }

    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory) {
        return longPayouts[orderId];
    }

    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory) {
        return shortPayouts[orderId];
    }

    function getBuyOrder(uint256 orderId) external view returns (BuyOrder memory) {
        return buyOrders[orderId];
    }

    function getSellOrder(uint256 orderId) external view returns (SellOrder memory) {
        return sellOrders[orderId];
    }

    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory) {
        require(index < historicalData[listingId].length, "Invalid index");
        return historicalData[listingId][index];
    }

    function historicalDataLengthView() external view returns (uint256) {
        return historicalData[listingId].length;
    }

    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory) {
        require(historicalData[listingId].length > 0, "No historical data");
        uint256 minDiff = type(uint256).max;
        uint256 closestIndex = 0;
        for (uint256 i = 0; i < historicalData[listingId].length; i++) {
            uint256 diff;
            if (targetTimestamp >= historicalData[listingId][i].timestamp) {
                diff = targetTimestamp - historicalData[listingId][i].timestamp;
            } else {
                diff = historicalData[listingId][i].timestamp - targetTimestamp;
            }
            if (diff < minDiff) {
                minDiff = diff;
                closestIndex = i;
            }
        }
        return historicalData[listingId][closestIndex];
    }
}