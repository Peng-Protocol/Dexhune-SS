// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.8
// - Updated from v0.0.7: Fetch orderIds only for buyOrder/sellOrder (settleType == 0)
// - Clarified buyLiquid/sellLiquid as settlement functions, not order functions
// - Modified executeHop to skip orderId for buyLiquid/sellLiquid
// - Updated continueHop to skip order checks for settleType == 1
// - Updated cancelHop to skip order cancellation for settleType == 1
// - Retained impactPricePercents validation (max 10%)
// - Compatible with SSShockhopper v0.0.5, SS-ListingTemplate v0.0.4

import "./imports/SafeERC20.sol";

interface ISSListing {
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function prices(uint256 listingId) external view returns (uint256);
    function getNextOrderId(uint256 listingId) external view returns (uint256);
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
}

interface ISSShockhopper {
    function updateStalledHop(uint256 hopId, HopLibrary.StalledHop memory hop) external;
    function updateHopsByAddress(address maker, uint256 hopId) external;
    function updateTotalHops(uint256 hopId) external;
    function removeHopByAddress(address maker, uint256 hopId) external;
    function getHopsByAddress(address user) external view returns (uint256[] memory);
}

interface ISSProxyRouter {
    function buyOrder(address listingAddress, ISSOrderLibrary.BuyOrderDetails memory details) external payable;
    function sellOrder(address listingAddress, ISSOrderLibrary.SellOrderDetails memory details) external payable;
    function buyLiquid(address listingAddress) external;
    function sellLiquid(address listingAddress) external;
    function settleBuy(address listingAddress) external;
    function settleSell(address listingAddress) external;
    function cancelOrder(address listingAddress, uint256 orderId, bool isBuy) external;
}

interface ISSOrderLibrary {
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
}

contract HopLibrary {
    using SafeERC20 for IERC20;

    struct HopRequest {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents;
        address startToken;
        address endToken;
        uint8 settleType; // 0 = market-based, 1 = liquidity-based
        uint8 driverType; // 0 = CrossDriver, 1 = IsolatedDriver
        PositionParams1 positionParams1;
        PositionParams2 positionParams2;
    }

    struct PositionParams1 {
        bool entry;
        uint8 positionType; // 0 = long, 1 = short
        uint256 amount;
        uint256 ratio;
        uint8 leverage;
    }

    struct PositionParams2 {
        uint256 positionIndex;
        string entryPrice;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
    }

    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 positionId;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus; // 0 = active, 1 = stalled, 2 = completed
        uint8 driverType;
        bool entry;
        uint8 positionType;
        uint256 payoutId;
        uint256[] orderIds; // Order IDs for market-based orders only
    }

    struct StallData {
        uint256 hopId;
        address listing;
        uint256 positionId;
        bool isLong;
        uint256 pendingMargin;
        uint256 payout;
        uint8 status;
        uint256 payoutId;
        uint256 orderId; // Order ID for current stage (0 for liquidity-based)
    }

    struct HopPrepData {
        uint256 hopId;
        uint256[] indices;
        bool[] isLong;
        address currentToken;
        uint256 principal;
    }

    // Events
    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);
    event HopCanceled(uint256 indexed hopId);

    // Compute route for hop
    function computeRoute(address[] memory listingAddresses, address startToken, address endToken)
        internal view returns (uint256[] memory indices, bool[] memory isLong)
    {
        require(listingAddresses.length > 0 && listingAddresses.length <= 4, "Invalid listing count");
        indices = new uint256[](listingAddresses.length);
        isLong = new bool[](listingAddresses.length);
        address currentToken = startToken;
        uint256 pathLength = 0;

        for (uint256 i = 0; i < listingAddresses.length; i++) {
            ISSListing listing = ISSListing(listingAddresses[i]);
            address tokenA = listing.tokenA();
            address tokenB = listing.tokenB();
            if (currentToken == tokenA) {
                indices[pathLength] = i;
                isLong[pathLength] = false;
                currentToken = tokenB;
                pathLength++;
            } else if (currentToken == tokenB) {
                indices[pathLength] = i;
                isLong[pathLength] = true;
                currentToken = tokenA;
                pathLength++;
            }
            if (currentToken == endToken) break;
        }
        require(currentToken == endToken, "No valid route to endToken");
        assembly { mstore(indices, pathLength) mstore(isLong, pathLength) }
    }

    // Calculate impact price
    function calculateImpactPrice(address listing, uint256 impactPercent, bool isLong)
        internal view returns (uint256)
    {
        require(impactPercent <= 1000, "Impact percent too high"); // Max 10%
        uint256 currentPrice = ISSListing(listing).prices(0);
        if (isLong) return currentPrice + (currentPrice * impactPercent / 10000);
        else return currentPrice - (currentPrice * impactPercent / 10000);
    }

    // Get token decimals
    function getTokenDecimals(address token) internal view returns (uint8) {
        if (token == address(0)) return 18;
        try IERC20(token).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18;
        }
    }

    // Denormalize amount
    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        uint8 decimals = getTokenDecimals(token);
        return amount * (10 ** decimals) / 1e18;
    }

    // Prepare hop
    function prepHop(HopRequest memory request, uint256 hopId, address shockhopper)
        public view returns (HopPrepData memory)
    {
        require(request.numListings > 0 && request.numListings <= 4, "Invalid numListings");
        require(
            request.numListings == request.listingAddresses.length &&
            request.numListings == request.impactPricePercents.length,
            "Array length mismatch"
        );

        (uint256[] memory indices, bool[] memory isLong) = computeRoute(
            request.listingAddresses,
            request.startToken,
            request.endToken
        );

        return HopPrepData({
            hopId: hopId,
            indices: indices,
            isLong: isLong,
            currentToken: request.startToken,
            principal: request.positionParams1.amount
        });
    }

    // Execute hop
    function executeHop(
        HopRequest memory request,
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        address proxyRouter
    ) external {
        // Validate impactPricePercents
        for (uint256 i = 0; i < request.impactPricePercents.length; i++) {
            require(request.impactPricePercents[i] <= 1000, "Impact percent too high");
        }

        HopPrepData memory prepData = prepHop(request, 0, shockhopper);
        uint256 hopId = prepData.hopId;

        StalledHop memory stalledHop = StalledHop({
            stage: 0,
            currentListing: address(0),
            positionId: 0,
            minPrice: 0,
            maxPrice: 0,
            hopMaker: user,
            remainingListings: new address[](prepData.indices.length),
            principalAmount: prepData.principal,
            startToken: request.startToken,
            endToken: request.endToken,
            settleType: request.settleType,
            hopStatus: 1,
            driverType: request.driverType,
            entry: request.positionParams1.entry,
            positionType: request.positionParams1.positionType,
            payoutId: 0,
            orderIds: new uint256[](prepData.indices.length) // Initialize orderIds
        });

        for (uint256 i = 0; i < prepData.indices.length; i++) {
            address listing = request.listingAddresses[prepData.indices[i]];
            bool isLong = prepData.isLong[i];
            uint256 priceLimit = calculateImpactPrice(listing, request.impactPricePercents[prepData.indices[i]], isLong);

            stalledHop.stage = uint8(i);
            stalledHop.currentListing = listing;
            stalledHop.minPrice = isLong ? 0 : priceLimit;
            stalledHop.maxPrice = isLong ? priceLimit : 0;
            for (uint256 j = i; j < prepData.indices.length; j++) {
                stalledHop.remainingListings[j - i] = request.listingAddresses[prepData.indices[j]];
            }

            // Order and settlement via SS-ProxyRouter
            if (request.settleType == 0) {
                // Fetch orderId for market-based orders
                ISSListing listingContract = ISSListing(listing);
                uint256 orderId = listingContract.getNextOrderId(0); // listingId = 0
                stalledHop.orderIds[i] = orderId;

                if (isLong) {
                    ISSOrderLibrary.BuyOrderDetails memory details = ISSOrderLibrary.BuyOrderDetails({
                        recipient: user,
                        amount: prepData.principal,
                        maxPrice: priceLimit,
                        minPrice: 0
                    });
                    ISSProxyRouter(proxyRouter).buyOrder(listing, details);
                    ISSProxyRouter(proxyRouter).settleBuy(listing);
                } else {
                    ISSOrderLibrary.SellOrderDetails memory details = ISSOrderLibrary.SellOrderDetails({
                        recipient: user,
                        amount: prepData.principal,
                        maxPrice: 0,
                        minPrice: priceLimit
                    });
                    ISSProxyRouter(proxyRouter).sellOrder(listing, details);
                    ISSProxyRouter(proxyRouter).settleSell(listing);
                }
            } else {
                // No orderId for liquidity-based settlement
                stalledHop.orderIds[i] = 0;
                if (isLong) {
                    ISSProxyRouter(proxyRouter).buyLiquid(listing);
                } else {
                    ISSProxyRouter(proxyRouter).sellLiquid(listing);
                }
            }

            ISSShockhopper(shockhopper).updateStalledHop(hopId, stalledHop);
            ISSShockhopper(shockhopper).updateHopsByAddress(user, hopId);
            return;
        }

        stalledHop.stage = uint8(prepData.indices.length);
        stalledHop.hopStatus = 2;
        ISSShockhopper(shockhopper).updateStalledHop(hopId, stalledHop);
        ISSShockhopper(shockhopper).updateHopsByAddress(user, hopId);
        ISSShockhopper(shockhopper).updateTotalHops(hopId);
    }

    // Prepare stalls
    function prepStalls(
        address user,
        uint256[] memory userHops,
        mapping(uint256 => StalledHop) storage hopID,
        address shockhopper
    ) external returns (StallData[] memory) {
        StallData[] memory stalls = new StallData[](userHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userHops.length && count < 20; i++) {
            StalledHop storage hop = hopID[userHops[i]];
            if (hop.hopStatus != 1) continue;

            stalls[count] = StallData({
                hopId: userHops[i],
                listing: hop.currentListing,
                positionId: hop.positionId,
                isLong: hop.maxPrice > 0,
                pendingMargin: 0,
                payout: 0,
                status: 3,
                payoutId: hop.payoutId,
                orderId: hop.stage < hop.orderIds.length ? hop.orderIds[hop.stage] : 0
            });
            count++;
        }

        assembly { mstore(stalls, count) }
        if (count > 0) {
            emit StallsPrepared(stalls[0].hopId, count);
        }
        return stalls;
    }

    // Execute stalls
    function executeStalls(
        StallData[] memory stalls,
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        address proxyRouter
    ) external {
        uint256 count = 0;
        uint256[] memory userHops = ISSShockhopper(shockhopper).getHopsByAddress(user);

        for (uint256 i = 0; i < stalls.length; i++) {
            StalledHop storage hop = hopID[stalls[i].hopId];
            if (hop.hopStatus != 1 || stalls[i].status != 3) continue;

            count++;
            uint256 nextStage = uint256(hop.stage) + 1;
            if (nextStage >= hop.remainingListings.length) {
                hop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(stalls[i].hopId);
                emit HopContinued(stalls[i].hopId, uint8(nextStage));
                continue;
            }

            hop.stage = uint8(nextStage);
            hop.currentListing = hop.remainingListings[0];
            if (hop.settleType == 0) {
                hop.orderIds[nextStage] = ISSListing(hop.currentListing).getNextOrderId(0);
            } else {
                hop.orderIds[nextStage] = 0;
            }
            address[] memory newRemaining = new address[](hop.remainingListings.length - 1);
            for (uint256 j = 0; j < newRemaining.length; j++) {
                newRemaining[j] = hop.remainingListings[j + 1];
            }
            hop.remainingListings = newRemaining;

            ISSShockhopper(shockhopper).updateStalledHop(stalls[i].hopId, hop);
            emit HopContinued(stalls[i].hopId, uint8(nextStage));
        }

        emit StallsExecuted(count > 0 ? stalls[0].hopId : 0, count);

        for (uint256 i = userHops.length; i > 0; i--) {
            if (hopID[userHops[i - 1]].hopStatus == 2) {
                ISSShockhopper(shockhopper).removeHopByAddress(user, userHops[i - 1]);
            }
        }
    }

    // Cancel hop
    function cancelHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        StalledHop memory hop,
        address proxyRouter
    ) external {
        require(hop.hopMaker == user, "Not hop maker");
        require(hop.hopStatus == 1, "Hop not stalled");

        // Cancel orders for market-based hops only
        if (hop.settleType == 0) {
            for (uint256 i = 0; i < hop.orderIds.length; i++) {
                if (hop.orderIds[i] != 0) {
                    ISSProxyRouter(proxyRouter).cancelOrder(hop.remainingListings[i], hop.orderIds[i], hop.maxPrice > 0);
                }
            }
        }

        hop.hopStatus = 2;
        ISSShockhopper(shockhopper).updateStalledHop(hopId, hop);
        ISSShockhopper(shockhopper).removeHopByAddress(user, hopId);
        emit HopCanceled(hopId);
    }

    // Cancel all hops
    function cancelAll(
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        uint256[] memory userHops,
        mapping(uint256 => StalledHop) storage hopID,
        address proxyRouter
    ) external returns (uint256 canceled) {
        canceled = 0;

        for (uint256 i = userHops.length; i > 0 && canceled < 100; i--) {
            uint256 hopId = userHops[i - 1];
            StalledHop storage hop = hopID[hopId];
            if (hop.hopStatus == 1) {
                cancelHop(
                    hopId,
                    user,
                    shockhopper,
                    crossDriver,
                    isolatedDriver,
                    crossLibrary,
                    isolatedLibrary,
                    hop,
                    proxyRouter
                );
                canceled++;
            }
        }

        emit HopCanceled(0);
        return canceled;
    }
}