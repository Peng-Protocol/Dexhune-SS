// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.10 (Updated)
// Changes:
// - v0.0.10: Added amountSent to UpdateType struct to separate it from maxPrice (line 198).
// - v0.0.10: Modified update function to use amountSent field instead of repurposing maxPrice for buy/sell order amounts (lines 370-390, 420-440).
// - v0.0.9: Added amountSent to BuyOrderAmounts and SellOrderAmounts structs to track real amount of opposite token sent during settlement (lines 110-111, 120-121).
// - v0.0.9: Modified update function to handle amountSent updates for buy/sell orders (lines 360-380, 410-430).
// - v0.0.9: Updated getBuyOrderAmounts and getSellOrderAmounts view functions to return amountSent (lines 670-675, 685-690).
// - v0.0.8: Renamed state variables tokenA to tokenX, tokenB to tokenY, decimalsA to decimalX, decimalsB to decimalY, set to private to resolve naming conflicts with view functions (lines 68-71).
// - v0.0.7: Defined ISSListing interface inline, removed import (lines 14-28).
// - v0.0.7: Reduced PayoutUpdate struct to payoutType, recipient, required (removed price, xBalance, yBalance, xVolume, yVolume) in ssUpdate (lines 140-144).
// - v0.0.6: Replaced lastDay with LastDayFee struct to store xFees, yFees, timestamp (line 65).
// - v0.0.6: Updated queryYield to compute yield using difference between lastDayFee.xFees/yFees and volumeBalance.xVolume/yVolume (lines 202-226).
// - v0.0.6: Modified update to set lastDayFee.xFees/yFees and timestamp when volumeBalance.xVolume/yVolume changes (lines 367-375).
// - v0.0.6: Modified transact to set lastDayFee.xFees/yFees and timestamp on volume updates (lines 549-556).
// - v0.0.5: Replaced liquidityAddresses mapping with single liquidityAddress state variable (line 47).
// - v0.0.5: Removed listingId parameters from functions, simplified mappings to use single listingId (e.g., volumeBalances to volumeBalance, lines 51-66).
// - Compatible with SS-LiquidityTemplate.sol (v0.0.3), SSAgent.sol (v0.0.2).

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ISSListing {
    function prices(uint256) external view returns (uint256); // Ignores listingId, returns price
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance); // Ignores listingId
    function liquidityAddressView(uint256) external view returns (address); // Ignores listingId
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
    }
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

interface ISSAgent {
    function globalizeOrders(
        uint256 listingId,
        address tokenA,
        address tokenB,
        uint256 orderId,
        bool isBuy,
        address maker,
        address recipient,
        uint256 amount,
        uint8 status
    ) external;
}

interface ISSLiquidityTemplate {
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

contract SSListingTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => bool) public routers;
    bool public routersSet;
    address private tokenX;
    address private tokenY;
    uint8 private decimalX;
    uint8 private decimalY;
    uint256 public listingId;
    address public agent;
    address public registryAddress;
    address public liquidityAddress;
    uint256 public nextOrderId;
    struct LastDayFee {
        uint256 xFees;
        uint256 yFees;
        uint256 timestamp;
    }
    LastDayFee public lastDayFee;
    VolumeBalance public volumeBalance;
    uint256 public price;
    uint256[] public pendingBuyOrders;
    uint256[] public pendingSellOrders;
    uint256[] public longPayoutsByIndex;
    uint256[] public shortPayoutsByIndex;
    mapping(address => uint256[]) public makerPendingOrders;
    mapping(address => uint256[]) public userPayoutIDs;
    HistoricalData[] public historicalData;

    struct VolumeBalance {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    struct BuyOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct BuyOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct BuyOrderAmounts {
        uint256 pending;    // Amount of tokenY pending
        uint256 filled;     // Amount of tokenY filled
        uint256 amountSent; // Amount of tokenX sent during settlement
    }

    struct SellOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status;
    }

    struct SellOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct SellOrderAmounts {
        uint256 pending;    // Amount of tokenX pending
        uint256 filled;     // Amount of tokenX filled
        uint256 amountSent; // Amount of tokenY sent during settlement
    }

    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
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
        uint256 amount;
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

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index;    // orderId or slot index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume for type 0)
        uint256 value;    // principal or amount (normalized) or price (for historical)
        address addr;     // makerAddress
        address recipient;// recipientAddress
        uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
        uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
        uint256 amountSent; // Amount of opposite token sent during settlement
    }

    mapping(uint256 => BuyOrderCore) public buyOrderCores;
    mapping(uint256 => BuyOrderPricing) public buyOrderPricings;
    mapping(uint256 => BuyOrderAmounts) public buyOrderAmounts;
    mapping(uint256 => SellOrderCore) public sellOrderCores;
    mapping(uint256 => SellOrderPricing) public sellOrderPricings;
    mapping(uint256 => SellOrderAmounts) public sellOrderAmounts;
    mapping(uint256 => LongPayoutStruct) public longPayouts;
    mapping(uint256 => ShortPayoutStruct) public shortPayouts;

    event OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status);
    event PayoutOrderCreated(uint256 orderId, bool isLong, uint8 status);
    event BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance);

    // Normalizes amount to 18 decimals
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    // Denormalizes amount from 18 decimals to token decimals
    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    // Checks if two timestamps are on the same day
    function _isSameDay(uint256 time1, uint256 time2) internal pure returns (bool) {
        uint256 midnight1 = time1 - (time1 % 86400);
        uint256 midnight2 = time2 - (time2 % 86400);
        return midnight1 == midnight2;
    }

    // Floors timestamp to midnight
    function _floorToMidnight(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % 86400);
    }

    // Finds volume change for tokenX or tokenY since startTime
    function _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) internal view returns (uint256) {
        uint256 currentVolume = isA ? volumeBalance.xVolume : volumeBalance.yVolume;
        uint256 iterationsLeft = maxIterations;
        if (historicalData.length == 0) return 0;
        for (uint256 i = historicalData.length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = historicalData[i - 1];
            iterationsLeft--;
            if (data.timestamp >= startTime) {
                return currentVolume - (isA ? data.xVolume : data.yVolume);
            }
        }
        if (iterationsLeft == 0 || historicalData.length <= maxIterations) {
            HistoricalData memory earliest = historicalData[0];
            return currentVolume - (isA ? earliest.xVolume : earliest.yVolume);
        }
        return 0;
    }

    // Queries annualized yield for tokenX or tokenY
    function queryYield(bool isA, uint256 maxIterations) external view returns (uint256) {
        require(maxIterations > 0, "Invalid maxIterations");
        if (lastDayFee.timestamp == 0 || historicalData.length == 0 || !_isSameDay(block.timestamp, lastDayFee.timestamp)) {
            return 0;
        }
        uint256 feeDifference = isA ? volumeBalance.xVolume - lastDayFee.xFees : volumeBalance.yVolume - lastDayFee.yFees;
        if (feeDifference == 0) return 0;
        uint256 liquidity = 0;
        try ISSLiquidityTemplate(liquidityAddress).liquidityAmounts() returns (uint256 xLiquid, uint256 yLiquid) {
            liquidity = isA ? xLiquid : yLiquid;
        } catch {
            return 0;
        }
        if (liquidity == 0) return 0;
        uint256 dailyFees = (feeDifference * 5) / 10000; // 0.05% fee
        uint256 dailyYield = (dailyFees * 1e18) / liquidity;
        return dailyYield * 365; // Annualized yield
    }

    // Updates token registry with maker addresses
    function _updateRegistry() internal {
        if (registryAddress == address(0)) return;
        bool isBuy = block.timestamp % 2 == 0;
        uint256[] memory orders = isBuy ? pendingBuyOrders : pendingSellOrders;
        address token = isBuy ? tokenY : tokenX;
        if (orders.length == 0) return;
        address[] memory tempMakers = new address[](orders.length);
        uint256 makerCount = 0;
        for (uint256 i = 0; i < orders.length; i++) {
            address maker = isBuy ? buyOrderCores[orders[i]].makerAddress : sellOrderCores[orders[i]].makerAddress;
            if (maker != address(0)) {
                bool exists = false;
                for (uint256 j = 0; j < makerCount; j++) {
                    if (tempMakers[j] == maker) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    tempMakers[makerCount] = maker;
                    makerCount++;
                }
            }
        }
        address[] memory makers = new address[](makerCount);
        for (uint256 i = 0; i < makerCount; i++) {
            makers[i] = tempMakers[i];
        }
        try ITokenRegistry(registryAddress).initializeBalances(token, makers) {} catch {}
    }

    // Sets router addresses
    function setRouters(address[] memory _routers) external {
        require(!routersSet, "Routers already set");
        require(_routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i] != address(0), "Invalid router address");
            routers[_routers[i]] = true;
        }
        routersSet = true;
    }

    // Sets listing ID
    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    // Sets liquidity address
    function setLiquidityAddress(address _liquidityAddress) external {
        require(liquidityAddress == address(0), "Liquidity already set");
        require(_liquidityAddress != address(0), "Invalid liquidity address");
        liquidityAddress = _liquidityAddress;
    }

    // Sets token addresses and decimals
    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenX == address(0) && tokenY == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenX = _tokenA;
        tokenY = _tokenB;
        decimalX = _tokenA == address(0) ? 18 : IERC20(_tokenA).decimals();
        decimalY = _tokenB == address(0) ? 18 : IERC20(_tokenB).decimals();
    }

    // Sets agent address
    function setAgent(address _agent) external {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    // Sets registry address
    function setRegistry(address _registryAddress) external {
        require(registryAddress == address(0), "Registry already set");
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress;
    }

    // Updates global orders via agent
    function globalizeUpdate() internal {
        if (agent == address(0)) return;
        for (uint256 i = 0; i < pendingBuyOrders.length; i++) {
            uint256 orderId = pendingBuyOrders[i];
            BuyOrderCore memory order = buyOrderCores[orderId];
            BuyOrderAmounts memory amounts = buyOrderAmounts[orderId];
            if (order.status == 1 || order.status == 2) {
                try ISSAgent(agent).globalizeOrders(
                    listingId,
                    tokenX,
                    tokenY,
                    orderId,
                    true,
                    order.makerAddress,
                    order.recipientAddress,
                    amounts.pending,
                    order.status
                ) {} catch {}
            }
        }
        for (uint256 i = 0; i < pendingSellOrders.length; i++) {
            uint256 orderId = pendingSellOrders[i];
            SellOrderCore memory order = sellOrderCores[orderId];
            SellOrderAmounts memory amounts = sellOrderAmounts[orderId];
            if (order.status == 1 || order.status == 2) {
                try ISSAgent(agent).globalizeOrders(
                    listingId,
                    tokenX,
                    tokenY,
                    orderId,
                    false,
                    order.makerAddress,
                    order.recipientAddress,
                    amounts.pending,
                    order.status
                ) {} catch {}
            }
        }
    }

    // Removes order from pending array
    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                break;
            }
        }
    }

    // Updates balances, orders, or historical data
    function update(address caller, UpdateType[] memory updates) external nonReentrant {
        require(routers[caller], "Router only");
        VolumeBalance storage balances = volumeBalance;

        bool volumeUpdated = false;
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0 && (u.index == 2 || u.index == 3)) {
                volumeUpdated = true;
                break;
            } else if (u.updateType == 1 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
                break;
            } else if (u.updateType == 2 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
                break;
            }
        }
        if (volumeUpdated && (lastDayFee.timestamp == 0 || block.timestamp >= lastDayFee.timestamp + 86400)) {
            lastDayFee.xFees = volumeBalance.xVolume;
            lastDayFee.yFees = volumeBalance.yVolume;
            lastDayFee.timestamp = _floorToMidnight(block.timestamp);
        }

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) {
                if (u.index == 0) balances.xBalance = u.value;
                else if (u.index == 1) balances.yBalance = u.value;
                else if (u.index == 2) balances.xVolume += u.value;
                else if (u.index == 3) balances.yVolume += u.value;
            } else if (u.updateType == 1) {
                if (u.structId == 0) {
                    BuyOrderCore storage core = buyOrderCores[u.index];
                    if (core.makerAddress == address(0)) {
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingBuyOrders.push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                        nextOrderId = u.index + 1;
                        emit OrderUpdated(listingId, u.index, true, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(pendingBuyOrders, u.index);
                        removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        emit OrderUpdated(listingId, u.index, true, 0);
                    }
                } else if (u.structId == 1) {
                    BuyOrderPricing storage pricing = buyOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    BuyOrderAmounts storage amounts = buyOrderAmounts[u.index];
                    BuyOrderCore storage core = buyOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value;
                        amounts.amountSent = u.amountSent; // Set initial amountSent (tokenX)
                        balances.yBalance += u.value;
                        balances.yVolume += u.value;
                    } else if (core.status == 1) {
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent; // Add to amountSent (tokenX)
                        balances.xBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(pendingBuyOrders, u.index);
                            removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        }
                        emit OrderUpdated(listingId, u.index, true, core.status);
                    }
                }
            } else if (u.updateType == 2) {
                if (u.structId == 0) {
                    SellOrderCore storage core = sellOrderCores[u.index];
                    if (core.makerAddress == address(0)) {
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingSellOrders.push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                        nextOrderId = u.index + 1;
                        emit OrderUpdated(listingId, u.index, false, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(pendingSellOrders, u.index);
                        removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        emit OrderUpdated(listingId, u.index, false, 0);
                    }
                } else if (u.structId == 1) {
                    SellOrderPricing storage pricing = sellOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    SellOrderAmounts storage amounts = sellOrderAmounts[u.index];
                    SellOrderCore storage core = sellOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value;
                        amounts.amountSent = u.amountSent; // Set initial amountSent (tokenY)
                        balances.xBalance += u.value;
                        balances.xVolume += u.value;
                    } else if (core.status == 1) {
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent; // Add to amountSent (tokenY)
                        balances.yBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(pendingSellOrders, u.index);
                            removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        }
                        emit OrderUpdated(listingId, u.index, false, core.status);
                    }
                }
            } else if (u.updateType == 3) {
                historicalData.push(HistoricalData(
                    u.value,
                    u.maxPrice >> 128, u.maxPrice & ((1 << 128) - 1),
                    u.minPrice >> 128, u.minPrice & ((1 << 128) - 1),
                    block.timestamp
                ));
            }
        }

        if (balances.xBalance > 0 && balances.yBalance > 0) {
            price = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(listingId, balances.xBalance, balances.yBalance);
        globalizeUpdate();
    }

    // Processes payout updates
    function ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates) external nonReentrant {
        require(routers[caller], "Router only");
        for (uint256 i = 0; i < payoutUpdates.length; i++) {
            PayoutUpdate memory p = payoutUpdates[i];
            uint256 orderId = nextOrderId;
            if (p.payoutType == 0) {
                LongPayoutStruct storage payout = longPayouts[orderId];
                payout.makerAddress = caller;
                payout.recipientAddress = p.recipient;
                payout.required = p.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = 0;
                longPayoutsByIndex.push(orderId);
                userPayoutIDs[p.recipient].push(orderId);
                emit PayoutOrderCreated(orderId, true, 0);
            } else if (p.payoutType == 1) {
                ShortPayoutStruct storage payout = shortPayouts[orderId];
                payout.makerAddress = caller;
                payout.recipientAddress = p.recipient;
                payout.amount = p.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = 0;
                shortPayoutsByIndex.push(orderId);
                userPayoutIDs[p.recipient].push(orderId);
                emit PayoutOrderCreated(orderId, false, 0);
            } else {
                revert("Invalid payout type");
            }
            nextOrderId = orderId + 1;
        }
    }

    // Handles token transfers
    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        require(routers[caller], "Router only");
        VolumeBalance storage balances = volumeBalance;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (lastDayFee.timestamp == 0 || block.timestamp >= lastDayFee.timestamp + 86400) {
            lastDayFee.xFees = volumeBalance.xVolume;
            lastDayFee.yFees = volumeBalance.yVolume;
            lastDayFee.timestamp = _floorToMidnight(block.timestamp);
        }

        if (token == tokenX) {
            require(balances.xBalance >= normalizedAmount, "Insufficient xBalance");
            balances.xBalance -= normalizedAmount;
            balances.xVolume += normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else if (token == tokenY) {
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
            price = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(listingId, balances.xBalance, balances.yBalance);
        _updateRegistry();
    }

    // Returns current price
    function prices(uint256) external view returns (uint256) {
        return price;
    }

    // Returns volume balances
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance) {
        return (volumeBalance.xBalance, volumeBalance.yBalance);
    }

    // Returns liquidity address
    function liquidityAddressView(uint256) external view returns (address) {
        return liquidityAddress;
    }

    // Returns tokenX address
    function tokenA() external view returns (address) {
        return tokenX;
    }

    // Returns tokenY address
    function tokenB() external view returns (address) {
        return tokenY;
    }

    // Returns tokenX decimals
    function decimalsA() external view returns (uint8) {
        return decimalX;
    }

    // Returns tokenY decimals
    function decimalsB() external view returns (uint8) {
        return decimalY;
    }

    // Returns listing ID
    function getListingId() external view returns (uint256) {
        return listingId;
    }

    // Returns next order ID
    function getNextOrderId() external view returns (uint256) {
        return nextOrderId;
    }

    // Returns volume balance details
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        return (volumeBalance.xBalance, volumeBalance.yBalance, volumeBalance.xVolume, volumeBalance.yVolume);
    }

    // Returns current price
    function listingPriceView() external view returns (uint256) {
        return price;
    }

    // Returns pending buy orders
    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return pendingBuyOrders;
    }

    // Returns pending sell orders
    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return pendingSellOrders;
    }

    // Returns maker's pending orders
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory) {
        return makerPendingOrders[maker];
    }

    // Returns long payout indices
    function longPayoutByIndexView() external view returns (uint256[] memory) {
        return longPayoutsByIndex;
    }

    // Returns short payout indices
    function shortPayoutByIndexView() external view returns (uint256[] memory) {
        return shortPayoutsByIndex;
    }

    // Returns user payout IDs
    function userPayoutIDsView(address user) external view returns (uint256[] memory) {
        return userPayoutIDs[user];
    }

    // Returns long payout details
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory) {
        return longPayouts[orderId];
    }

    // Returns short payout details
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory) {
        return shortPayouts[orderId];
    }

    // Returns buy order core details
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        BuyOrderCore memory core = buyOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns buy order pricing details
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        BuyOrderPricing memory pricing = buyOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns buy order amounts
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        BuyOrderAmounts memory amounts = buyOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    // Returns sell order core details
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        SellOrderCore memory core = sellOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns sell order pricing details
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        SellOrderPricing memory pricing = sellOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns sell order amounts
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        SellOrderAmounts memory amounts = sellOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    // Returns historical data by index
    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory) {
        require(index < historicalData.length, "Invalid index");
        return historicalData[index];
    }

    // Returns historical data length
    function historicalDataLengthView() external view returns (uint256) {
        return historicalData.length;
    }

    // Returns historical data by nearest timestamp
    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory) {
        require(historicalData.length > 0, "No historical data");
        uint256 minDiff = type(uint256).max;
        uint256 closestIndex = 0;
        for (uint256 i = 0; i < historicalData.length; i++) {
            uint256 diff;
            if (targetTimestamp >= historicalData[i].timestamp) {
                diff = targetTimestamp - historicalData[i].timestamp;
            } else {
                diff = historicalData[i].timestamp - targetTimestamp;
            }
            if (diff < minDiff) {
                minDiff = diff;
                closestIndex = i;
            }
        }
        return historicalData[closestIndex];
    }
}