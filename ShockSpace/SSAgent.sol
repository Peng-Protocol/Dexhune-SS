// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.4 (Updated)
// Changes:
// - v0.0.4: Updated globalizeLiquidity to validate caller as liquidity contract by checking listing address and isValidListing.
// - v0.0.3: Added isValidListing function to check if an address is a valid listing and return its details.
// - v0.0.2: Removed taxCollector state variable, determineCollector function, taxCollector checks in listToken/listNative, and setCollector call in _initializeLiquidity.
// - v0.0.2: Added note to remove taxCollector functionality from SSListingTemplate.sol and SSLiquidityTemplate.sol.
// - v0.0.2: Split _initializePair into _initializeListing and _initializeLiquidity to avoid stack depth errors.
// - v0.0.2: Added registryAddress state variable, setRegistry function, and registry checks in listToken/listNative.
// - v0.0.2: Added OMFAgent mappings, arrays, structs, events, and functions for liquidity and order tracking.
// - v0.0.2: Updated listingLibraryAddress and liquidityLibraryAddress to listingLogicAddress and liquidityLogicAddress.
// - v0.0.1: Renamed MFPAgent to SSAgent, updated MFP to SS in interfaces and comments.
// - v0.0.1: Replaced routerAddress with proxyRouter, isolatedDriver, crossDriver; updated setRouter to setProxyRouter.
// - v0.0.1: Added queryByAddress (tokenA/tokenB to listing indices) and queryByIndex (listingAddress by index).
// - v0.0.1: Added helpers _deployPair, _initializePair, _updateState to listToken and listNative.

// Note: taxCollector functionality has been removed from SSListingTemplate.sol and SSLiquidityTemplate.sol.

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

interface ISSListingTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
    function getTokens() external view returns (address tokenA, address tokenB);
}

interface ISSLiquidityTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function getListingAddress(uint256) external view returns (address);
}

interface ISSListingLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface ISSLiquidityLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface ISSListing {
    function liquidityAddress() external view returns (address);
}

contract SSAgent is Ownable {
    using SafeERC20 for IERC20;

    address public proxyRouter;
    address public isolatedDriver;
    address public crossDriver;
    address public listingLogicAddress;
    address public liquidityLogicAddress;
    address public registryAddress;
    uint256 public listingCount;

    mapping(address => mapping(address => address)) public getListing;
    address[] public allListings;
    address[] public allListedTokens;
    mapping(address => uint256[]) public queryByAddress;

    mapping(address => mapping(address => mapping(address => uint256))) public globalLiquidity; // tokenA => tokenB => user => amount
    mapping(address => mapping(address => uint256)) public totalLiquidityPerPair; // tokenA => tokenB => amount
    mapping(address => uint256) public userTotalLiquidity; // user => total liquidity
    mapping(uint256 => mapping(address => uint256)) public listingLiquidity; // listingId => user => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public historicalLiquidityPerPair; // tokenA => tokenB => timestamp => amount
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) public historicalLiquidityPerUser; // tokenA => tokenB => user => timestamp => amount

    struct GlobalOrder {
        uint256 orderId;
        bool isBuy;
        address maker;
        address recipient;
        uint256 amount;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp;
    }

    mapping(address => mapping(address => mapping(uint256 => GlobalOrder))) public globalOrders; // tokenA => tokenB => orderId => GlobalOrder
    mapping(address => mapping(address => uint256[])) public pairOrders; // tokenA => tokenB => orderId[]
    mapping(address => uint256[]) public userOrders; // user => orderId[]
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8)))) public historicalOrderStatus; // tokenA => tokenB => orderId => timestamp => status
    mapping(address => mapping(address => mapping(address => uint256))) public userTradingSummaries; // user => tokenA => tokenB => volume

    struct TrendData {
        address token;
        uint256 timestamp;
        uint256 amount;
    }

    struct OrderData {
        uint256 orderId;
        bool isBuy;
        address maker;
        address recipient;
        uint256 amount;
        uint8 status;
        uint256 timestamp;
    }

    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);
    event GlobalLiquidityChanged(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit);
    event GlobalOrderChanged(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status);

    function tokenExists(address token) internal view returns (bool) {
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            if (allListedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function _deployPair(address tokenA, address tokenB, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingId));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingId));
        listingAddress = ISSListingLogic(listingLogicAddress).deploy(listingSalt);
        liquidityAddress = ISSLiquidityLogic(liquidityLogicAddress).deploy(liquiditySalt);
        return (listingAddress, liquidityAddress);
    }

    function _initializeListing(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId) internal {
        address[] memory routers = new address[](3);
        routers[0] = proxyRouter;
        routers[1] = isolatedDriver;
        routers[2] = crossDriver;
        ISSListingTemplate(listingAddress).setRouters(routers);
        ISSListingTemplate(listingAddress).setListingId(listingId);
        ISSListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress);
        ISSListingTemplate(listingAddress).setTokens(tokenA, tokenB);
        ISSListingTemplate(listingAddress).setAgent(address(this));
        ISSListingTemplate(listingAddress).setRegistry(registryAddress);
    }

    function _initializeLiquidity(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId) internal {
        address[] memory routers = new address[](3);
        routers[0] = proxyRouter;
        routers[1] = isolatedDriver;
        routers[2] = crossDriver;
        ISSLiquidityTemplate(liquidityAddress).setRouters(routers);
        ISSLiquidityTemplate(liquidityAddress).setListingId(listingId);
        ISSLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        ISSLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);
        ISSLiquidityTemplate(liquidityAddress).setAgent(address(this));
    }

    function _updateState(address tokenA, address tokenB, address listingAddress, uint256 listingId) internal {
        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);
        if (!tokenExists(tokenA)) allListedTokens.push(tokenA);
        if (!tokenExists(tokenB)) allListedTokens.push(tokenB);
        queryByAddress[tokenA].push(listingId);
        queryByAddress[tokenB].push(listingId);
    }

    function setProxyRouter(address _proxyRouter) external onlyOwner {
        require(_proxyRouter != address(0), "Invalid proxy router address");
        proxyRouter = _proxyRouter;
    }

    function setIsolatedDriver(address _isolatedDriver) external onlyOwner {
        require(_isolatedDriver != address(0), "Invalid SSD address");
        isolatedDriver = _isolatedDriver;
    }

    function setCrossDriver(address _crossDriver) external onlyOwner {
        require(_crossDriver != address(0), "Invalid CSD address");
        crossDriver = _crossDriver;
    }

    function setListingLogic(address _listingLogic) external onlyOwner {
        require(_listingLogic != address(0), "Invalid logic address");
        listingLogicAddress = _listingLogic;
    }

    function setLiquidityLogic(address _liquidityLogic) external onlyOwner {
        require(_liquidityLogic != address(0), "Invalid logic address");
        liquidityLogicAddress = _liquidityLogic;
    }

    function setRegistry(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress;
    }

    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(proxyRouter != address(0), "Proxy router not set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _initializeLiquidity(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    function listNative(address token, bool isA) external returns (address listingAddress, address liquidityAddress) {
        address nativeAddress = address(0);
        address tokenA = isA ? nativeAddress : token;
        address tokenB = isA ? token : nativeAddress;

        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(proxyRouter != address(0), "Proxy router not set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _initializeLiquidity(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    function globalizeLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) external {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(user != address(0), "Invalid user");
        require(listingId < listingCount, "Invalid listing ID");

        // Step 1: Get the listing address from the liquidity contract
        address listingAddress;
        try ISSLiquidityTemplate(msg.sender).getListingAddress(listingId) returns (address _listingAddress) {
            listingAddress = _listingAddress;
        } catch {
            revert("Failed to retrieve listing address");
        }
        require(listingAddress != address(0), "Invalid listing address");

        // Step 2: Verify the listing is valid and retrieve its details
        (bool isValid, ListingDetails memory details) = isValidListing(listingAddress);
        require(isValid, "Invalid listing");
        require(details.listingId == listingId, "Listing ID mismatch");
        require(details.tokenA == tokenA && details.tokenB == tokenB, "Token mismatch");

        // Step 3: Verify the caller is the liquidity address associated with the listing
        require(details.liquidityAddress == msg.sender, "Caller is not liquidity contract");

        _updateGlobalLiquidity(listingId, tokenA, tokenB, user, amount, isDeposit);
    }

    function _updateGlobalLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) internal {
        if (isDeposit) {
            globalLiquidity[tokenA][tokenB][user] += amount;
            totalLiquidityPerPair[tokenA][tokenB] += amount;
            userTotalLiquidity[user] += amount;
            listingLiquidity[listingId][user] += amount;
        } else {
            require(globalLiquidity[tokenA][tokenB][user] >= amount, "Insufficient user liquidity");
            require(totalLiquidityPerPair[tokenA][tokenB] >= amount, "Insufficient pair liquidity");
            require(userTotalLiquidity[user] >= amount, "Insufficient total liquidity");
            require(listingLiquidity[listingId][user] >= amount, "Insufficient listing liquidity");
            globalLiquidity[tokenA][tokenB][user] -= amount;
            totalLiquidityPerPair[tokenA][tokenB] -= amount;
            userTotalLiquidity[user] -= amount;
            listingLiquidity[listingId][user] -= amount;
        }
        historicalLiquidityPerPair[tokenA][tokenB][block.timestamp] = totalLiquidityPerPair[tokenA][tokenB];
        historicalLiquidityPerUser[tokenA][tokenB][user][block.timestamp] = globalLiquidity[tokenA][tokenB][user];
        emit GlobalLiquidityChanged(listingId, tokenA, tokenB, user, amount, isDeposit);
    }

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
    ) external {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(maker != address(0), "Invalid maker");
        require(listingId < listingCount, "Invalid listing ID");
        require(getListing[tokenA][tokenB] == msg.sender, "Not listing contract");
        GlobalOrder storage order = globalOrders[tokenA][tokenB][orderId];
        if (order.maker == address(0) && status != 0) {
            order.orderId = orderId;
            order.isBuy = isBuy;
            order.maker = maker;
            order.recipient = recipient;
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
            pairOrders[tokenA][tokenB].push(orderId);
            userOrders[maker].push(orderId);
        } else {
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
        }
        historicalOrderStatus[tokenA][tokenB][orderId][block.timestamp] = status;
        if (amount > 0) {
            userTradingSummaries[maker][tokenA][tokenB] += amount;
        }
        emit GlobalOrderChanged(listingId, tokenA, tokenB, orderId, isBuy, maker, amount, status);
    }

    function getPairLiquidityTrend(
        address tokenA,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || tokenA == address(0)) {
            return (new uint256[](0), new uint256[](0));
        }
        TrendData[] memory temp = new TrendData[](endTime - startTime + 1);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerPair[tokenA][allListedTokens[0]][t];
                if (amount > 0) {
                    temp[count] = TrendData(address(0), t, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length; i++) {
                address tokenB = allListedTokens[i];
                for (uint256 t = startTime; t <= endTime; t++) {
                    uint256 amount = historicalLiquidityPerPair[tokenB][tokenA][t];
                    if (amount > 0) {
                        temp[count] = TrendData(address(0), t, amount);
                        count++;
                    }
                }
            }
        }
        timestamps = new uint256[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            timestamps[i] = temp[i].timestamp;
            amounts[i] = temp[i].amount;
        }
    }

    function getUserLiquidityTrend(
        address user,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || user == address(0)) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }
        TrendData[] memory temp = new TrendData[]((endTime - startTime + 1) * allListedTokens.length);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address tokenA = allListedTokens[i];
            address pairToken = focusOnTokenA ? allListedTokens[0] : tokenA;
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerUser[tokenA][pairToken][user][t];
                if (amount > 0) {
                    temp[count] = TrendData(focusOnTokenA ? tokenA : pairToken, t, amount);
                    count++;
                }
            }
        }
        tokens = new address[](count);
        timestamps = new uint256[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = temp[i].token;
            timestamps[i] = temp[i].timestamp;
            amounts[i] = temp[i].amount;
        }
    }

    function getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
            address tokenA = allListedTokens[i];
            uint256 amount = globalLiquidity[tokenA][allListedTokens[0]][user];
            if (amount > 0) {
                temp[count] = TrendData(tokenA, 0, amount);
                count++;
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            amounts[i] = temp[i].amount;
        }
    }

    function getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory users, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxLimit = maxIterations < allListings.length ? maxIterations : allListings.length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;
        for (uint256 i = 0; i < allListings.length && count < maxLimit; i++) {
            address user = allListings[i];
            uint256 amount = listingLiquidity[listingId][user];
            if (amount > 0) {
                temp[count] = TrendData(user, 0, amount);
                count++;
            }
        }
        _sortDescending(temp, count);
        users = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = temp[i].token;
            amounts[i] = temp[i].amount;
        }
    }

    function getUserLiquidityShare(address user, address tokenA, address tokenB)
        external view returns (uint256 share, uint256 total)
    {
        total = totalLiquidityPerPair[tokenA][tokenB];
        uint256 userAmount = globalLiquidity[tokenA][tokenB][user];
        share = total > 0 ? (userAmount * 1e18) / total : 0;
    }

    function getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[tokenA][allListedTokens[0]];
                if (amount >= minLiquidity) {
                    temp[count] = TrendData(tokenA, 0, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[tokenA][allListedTokens[0]];
                if (amount >= minLiquidity) {
                    temp[count] = TrendData(tokenA, 0, amount);
                    count++;
                }
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            amounts[i] = temp[i].amount;
        }
    }

    function getOrderActivityByPair(
        address tokenA,
        address tokenB,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory orderIds, OrderData[] memory orders) {
        if (endTime < startTime || tokenA == address(0) || tokenB == address(0)) {
            return (new uint256[](0), new OrderData[](0));
        }
        uint256[] memory pairOrderIds = pairOrders[tokenA][tokenB];
        OrderData[] memory temp = new OrderData[](pairOrderIds.length);
        uint256 count = 0;
        for (uint256 i = 0; i < pairOrderIds.length; i++) {
            GlobalOrder memory order = globalOrders[tokenA][tokenB][pairOrderIds[i]];
            if (order.timestamp >= startTime && order.timestamp <= endTime) {
                temp[count] = OrderData(
                    order.orderId,
                    order.isBuy,
                    order.maker,
                    order.recipient,
                    order.amount,
                    order.status,
                    order.timestamp
                );
                count++;
            }
        }
        orderIds = new uint256[](count);
        orders = new OrderData[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = temp[i].orderId;
            orders[i] = temp[i];
        }
    }

    function getUserTradingProfile(address user)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        uint256 maxPairs = allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address tokenA = allListedTokens[i];
            uint256 volume = userTradingSummaries[user][tokenA][allListedTokens[0]];
            if (volume > 0) {
                temp[count] = TrendData(tokenA, 0, volume);
                count++;
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            volumes[i] = temp[i].amount;
        }
    }

    function getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory traders, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxLimit = maxIterations < allListings.length ? maxIterations : allListings.length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;
        for (uint256 i = 0; i < allListings.length && count < maxLimit; i++) {
            address trader = allListings[i];
            address tokenA;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[allListedTokens[j]][allListedTokens[0]] == trader) {
                    tokenA = allListedTokens[j];
                    break;
                }
            }
            if (tokenA != address(0)) {
                uint256 volume = userTradingSummaries[trader][tokenA][allListedTokens[0]];
                if (volume > 0) {
                    temp[count] = TrendData(trader, 0, volume);
                    count++;
                }
            }
        }
        _sortDescending(temp, count);
        traders = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            traders[i] = temp[i].token;
            volumes[i] = temp[i].amount;
        }
    }

    function getAllPairsByOrderVolume(uint256 minVolume, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[tokenA][allListedTokens[0]];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[tokenA][allListedTokens[0]][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[tokenA][allListedTokens[0]];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[tokenA][allListedTokens[0]][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                }
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            volumes[i] = temp[i].amount;
        }
    }

    function _sortDescending(TrendData[] memory data, uint256 length) internal pure {
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (data[i].amount < data[j].amount) {
                    TrendData memory temp = data[i];
                    data[i] = data[j];
                    data[j] = temp;
                }
            }
        }
    }

    function queryByIndex(uint256 index) external view returns (address) {
        require(index < allListings.length, "Invalid index");
        return allListings[index];
    }

    function queryByAddressView(address target, uint256 maxIteration, uint256 step) external view returns (uint256[] memory) {
        uint256[] memory indices = queryByAddress[target];
        uint256 start = step * maxIteration;
        uint256 end = (step + 1) * maxIteration > indices.length ? indices.length : (step + 1) * maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = indices[i];
        }
        return result;
    }

    function queryByAddressLength(address target) external view returns (uint256) {
        return queryByAddress[target].length;
    }

    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }

    function allListedTokensLength() external view returns (uint256) {
        return allListedTokens.length;
    }

    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details) {
        isValid = false;
        for (uint256 i = 0; i < allListings.length; i++) {
            if (allListings[i] == listingAddress) {
                isValid = true;
                (address tokenA, address tokenB) = ISSListingTemplate(listingAddress).getTokens();
                address liquidityAddress = ISSListing(listingAddress).liquidityAddress();
                details = ListingDetails({
                    listingAddress: listingAddress,
                    liquidityAddress: liquidityAddress,
                    tokenA: tokenA,
                    tokenB: tokenB,
                    listingId: i
                });
                break;
            }
        }
    }
}