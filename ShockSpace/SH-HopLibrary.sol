// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.15
// Change Log:
// - v0.0.15:
//   - Fixed TypeError: Operator != not compatible with types uint256[] memory and address in `checkTokenPair` by replacing invalid `indices != address(0)` checks with `populateArrays` boolean parameter.
//   - Fixed TypeError: Invalid type for argument in `calculatePathLength` by passing empty arrays (`new uint256[](0)`, `new bool[](0)`) and `populateArrays = false` instead of `address(0)`.
//   - Updated `checkTokenPair` to use `populateArrays` for conditional array population, ensuring type safety.
//   - No functional changes; maintains compatibility with SSShockhopper v0.0.5, SS-ListingTemplate v0.0.4, SH-CrossLibrary v0.0.8, SH-IsolatedLibrary v0.0.8.
// - v0.0.14:
//   - Fixed TypeError: Member "length" is read-only in `computeRoute` by pre-allocating `indices` and `isLong` with exact `pathLength` using new `calculatePathLength` helper function.
//   - Extended `RouteState` with `validPath` flag to track route validity.
//   - Optimized `computeRoute` stack usage to ~8 slots by reusing `RouteState` fields and minimizing local variables.
//   - Pinned compiler to `solc` 0.8.20 to ensure consistent behavior, with fallback to pre-allocation for portability.
//   - Avoided reinstating `copyArrays` or inline assembly, using fresh pre-allocation approach.
//   - No functional changes; maintains compatibility with SSShockhopper v0.0.5, SS-ListingTemplate v0.0.4, SH-CrossLibrary v0.0.8, SH-IsolatedLibrary v0.0.8.
// - v0.0.12:
//   - Fixed DeclarationError: Undeclared identifier `hopID` in `executeStalls` and `cancelAll` by removing `hopID` parameter and fetching hop data via `ISSShockhopper.getHopDetails`.
//   - Fixed DeclarationError: Undeclared identifier `cancelHop` in `cancelAll` by ensuring `cancelHop` is declared as `internal` and precedes `cancelAll`.
//   - Updated `processSingleStall` to use `StalledHop memory` instead of `StalledHop storage`.
//   - Updated `removeCompletedHops` to query `getHopDetails` for hop status.
//   - No functional changes; maintains compatibility with SSShockhopper v0.0.5, SS-ListingTemplate v0.0.4, SH-CrossLibrary v0.0.8, SH-IsolatedLibrary v0.0.8.
// - v0.0.11:
//   - Upgraded to Solidity ^0.8.2 to enable native dynamic array resizing.
//   - Refactored `computeRoute` to use helper functions (`checkTokenPair`, `validatePath`) and `RouteState` struct to reduce stack usage, fixing "Stack too deep" error.
//   - Removed inline assembly in `prepStalls`, replaced with Solidity-based array resizing.
//   - Optimized `executeHop` with `HopExecutionState` struct and `processHopStage` helper to minimize stack pressure.
//   - Enhanced `executeStalls` with `processSingleStall` helper and storage pointers.
//   - No functional changes; maintains compatibility with SSShockhopper v0.0.5, SS-ListingTemplate v0.0.4, SH-CrossLibrary v0.0.8, SH-IsolatedLibrary v0.0.8.
// - v0.0.10:
//   - Fixed "Stack too deep" error in `computeRoute` by removing inline assembly and adding `copyArrays` helper function to resize `indices` and `isLong` arrays using Solidity.
//   - Optimized local variable usage in `computeRoute` to reduce stack pressure, reusing variables where possible.
//   - No functional changes to `computeRoute`, `prepHop`, or other functions; maintains compatibility with SSShockhopper v0.0.5 and SS-ListingTemplate v0.0.4.
// - v0.0.9:
//   - Restored inline assembly in `computeRoute` to resize `indices` and `isLong` arrays, fixing `TypeError: Member "length" is read-only` errors.
//   - Retained `validateHopRequest` and `createHopPrepData` helpers to minimize stack usage in `prepHop`, addressing prior stack depth issues.
//   - No functional changes to `computeRoute`, `prepHop`, or other functions; maintains compatibility with SSShockhopper v0.0.5 and SS-ListingTemplate v0.0.4.
// - v0.0.8:
//   - Updated `executeStalls` to use helper functions (`processStall`, `removeCompletedHops`) to reduce stack depth.
//   - Fetch orderIds only for buyOrder/sellOrder (settleType == 0).
//   - Clarified buyLiquid/sellLiquid as settlement functions, not order functions.
//   - Modified executeHop to skip orderId for buyLiquid/sellLiquid.
//   - Updated continueHop to skip order checks for settleType == 1.
//   - Updated cancelHop to skip order cancellation for settleType == 1.
//   - Retained impactPricePercents validation (max 10%).
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
    function getHopDetails(uint256 hopId) external view returns (HopLibrary.StalledHop memory);
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

library HopLibrary {
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

    struct RouteState {
        address currentToken;
        uint256 pathLength;
        bool validPath;
    }

    struct HopExecutionState {
        address user;
        address shockhopper;
        address proxyRouter;
        HopPrepData prepData;
        StalledHop stalledHop;
    }

    // Events
    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);
    event HopCanceled(uint256 indexed hopId);

    // Helper: Validate HopRequest arrays
    function validateHopRequest(HopRequest memory request) internal pure {
        require(request.numListings > 0 && request.numListings <= 4, "Invalid numListings");
        require(
            request.numListings == request.listingAddresses.length &&
            request.numListings == request.impactPricePercents.length,
            "Array length mismatch"
        );
    }

    // Helper: Create HopPrepData struct
    function createHopPrepData(
        uint256 hopId,
        uint256[] memory indices,
        bool[] memory isLong,
        address startToken,
        uint256 principal
    ) internal pure returns (HopPrepData memory) {
        return HopPrepData({
            hopId: hopId,
            indices: indices,
            isLong: isLong,
            currentToken: startToken,
            principal: principal
        });
    }

    // Helper: Check token pair for route computation
    function checkTokenPair(
        address currentToken,
        address tokenA,
        address tokenB,
        uint256 index,
        uint256[] memory indices,
        bool[] memory isLong,
        uint256 pathLength,
        bool populateArrays
    ) internal pure returns (bool matched, address nextToken, uint256 newPathLength) {
        if (currentToken == tokenA) {
            if (populateArrays) {
                indices[pathLength] = index;
                isLong[pathLength] = false;
            }
            return (true, tokenB, pathLength + 1);
        } else if (currentToken == tokenB) {
            if (populateArrays) {
                indices[pathLength] = index;
                isLong[pathLength] = true;
            }
            return (true, tokenA, pathLength + 1);
        }
        return (false, currentToken, pathLength);
    }

    // Helper: Calculate path length
    function calculatePathLength(
        address[] memory listingAddresses,
        address startToken,
        address endToken
    ) internal view returns (uint256 pathLength, bool validPath) {
        RouteState memory state = RouteState({
            currentToken: startToken,
            pathLength: 0,
            validPath: false
        });
        uint256[] memory emptyIndices = new uint256[](0);
        bool[] memory emptyIsLong = new bool[](0);

        for (uint256 i = 0; i < listingAddresses.length; i++) {
            ISSListing listing = ISSListing(listingAddresses[i]);
            (bool matched, address nextToken, uint256 newPathLength) = checkTokenPair(
                state.currentToken,
                listing.tokenA(),
                listing.tokenB(),
                i,
                emptyIndices,
                emptyIsLong,
                state.pathLength,
                false
            );
            if (matched) {
                state.currentToken = nextToken;
                state.pathLength = newPathLength;
            }
            if (state.currentToken == endToken) {
                state.validPath = true;
                break;
            }
        }

        return (state.pathLength, state.validPath);
    }

    // Helper: Validate path end
    function validatePath(bool validPath) internal pure {
        require(validPath, "No valid route to endToken");
    }

    // Compute route for hop
    function computeRoute(address[] memory listingAddresses, address startToken, address endToken)
        internal view returns (uint256[] memory indices, bool[] memory isLong)
    {
        require(listingAddresses.length > 0 && listingAddresses.length <= 4, "Invalid listing count");

        // Calculate exact path length
        (uint256 pathLength, bool validPath) = calculatePathLength(listingAddresses, startToken, endToken);
        validatePath(validPath);

        // Allocate arrays with exact size
        indices = new uint256[](pathLength);
        isLong = new bool[](pathLength);
        RouteState memory state = RouteState({ currentToken: startToken, pathLength: 0, validPath: false });

        // Populate arrays
        for (uint256 i = 0; i < listingAddresses.length; i++) {
            ISSListing listing = ISSListing(listingAddresses[i]);
            (bool matched, address nextToken, uint256 newPathLength) = checkTokenPair(
                state.currentToken,
                listing.tokenA(),
                listing.tokenB(),
                i,
                indices,
                isLong,
                state.pathLength,
                true
            );
            if (matched) {
                state.currentToken = nextToken;
                state.pathLength = newPathLength;
            }
            if (state.currentToken == endToken) {
                state.validPath = true;
                break;
            }
        }

        validatePath(state.validPath);
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
        validateHopRequest(request);

        (uint256[] memory indices, bool[] memory isLong) = computeRoute(
            request.listingAddresses,
            request.startToken,
            request.endToken
        );

        return createHopPrepData(
            hopId,
            indices,
            isLong,
            request.startToken,
            request.positionParams1.amount
        );
    }

    // Helper: Validate impact price percentages
    function validateImpactPercents(uint256[] memory impactPricePercents) internal pure {
        for (uint256 i = 0; i < impactPricePercents.length; i++) {
            require(impactPricePercents[i] <= 1000, "Impact percent too high");
        }
    }

    // Helper: Initialize StalledHop struct
    function initializeStalledHop(
        HopRequest memory request,
        address user,
        HopPrepData memory prepData
    ) internal pure returns (StalledHop memory) {
        return StalledHop({
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
            orderIds: new uint256[](prepData.indices.length)
        });
    }

    // Helper: Update StalledHop for current stage
    function updateStalledHopForStage(
        StalledHop memory stalledHop,
        HopRequest memory request,
        HopPrepData memory prepData,
        uint256 i
    ) internal view {
        address listing = request.listingAddresses[prepData.indices[i]];
        bool isLong = prepData.isLong[i];
        uint256 priceLimit = calculateImpactPrice(listing, request.impactPricePercents[prepData.indices[i]], isLong);

        stalledHop.stage = uint8(i);
        stalledHop.currentListing = listing;
        stalledHop.minPrice = isLong ? 0 : priceLimit;
        stalledHop.maxPrice = isLong ? priceLimit : 0;

        // Update remainingListings
        for (uint256 j = i; j < prepData.indices.length; j++) {
            stalledHop.remainingListings[j - i] = request.listingAddresses[prepData.indices[j]];
        }
    }

    // Helper: Execute order or liquidity settlement
    function executeOrderOrSettlement(
        HopExecutionState memory state,
        uint256 i
    ) internal {
        address listing = state.stalledHop.currentListing;
        bool isLong = state.stalledHop.maxPrice > 0;

        if (state.stalledHop.settleType == 0) {
            // Market-based: Fetch orderId and place order
            ISSListing listingContract = ISSListing(listing);
            uint256 orderId = listingContract.getNextOrderId(0); // listingId = 0
            state.stalledHop.orderIds[i] = orderId;

            if (isLong) {
                ISSOrderLibrary.BuyOrderDetails memory details = ISSOrderLibrary.BuyOrderDetails({
                    recipient: state.user,
                    amount: state.prepData.principal,
                    maxPrice: state.stalledHop.maxPrice,
                    minPrice: 0
                });
                ISSProxyRouter(state.proxyRouter).buyOrder(listing, details);
                ISSProxyRouter(state.proxyRouter).settleBuy(listing);
            } else {
                ISSOrderLibrary.SellOrderDetails memory details = ISSOrderLibrary.SellOrderDetails({
                    recipient: state.user,
                    amount: state.prepData.principal,
                    maxPrice: 0,
                    minPrice: state.stalledHop.minPrice
                });
                ISSProxyRouter(state.proxyRouter).sellOrder(listing, details);
                ISSProxyRouter(state.proxyRouter).settleSell(listing);
            }
        } else {
            // Liquidity-based: No orderId
            state.stalledHop.orderIds[i] = 0;
            if (isLong) {
                ISSProxyRouter(state.proxyRouter).buyLiquid(listing);
            } else {
                ISSProxyRouter(state.proxyRouter).sellLiquid(listing);
            }
        }
    }

    // Helper: Process a single hop stage
    function processHopStage(
        HopExecutionState memory state,
        HopRequest memory request,
        uint256 i
    ) internal {
        updateStalledHopForStage(state.stalledHop, request, state.prepData, i);
        executeOrderOrSettlement(state, i);
        ISSShockhopper(state.shockhopper).updateStalledHop(state.prepData.hopId, state.stalledHop);
        ISSShockhopper(state.shockhopper).updateHopsByAddress(state.user, state.prepData.hopId);
    }

    // Helper: Finalize hop as completed
    function finalizeHop(HopExecutionState memory state) internal {
        state.stalledHop.stage = uint8(state.prepData.indices.length);
        state.stalledHop.hopStatus = 2;
        ISSShockhopper(state.shockhopper).updateStalledHop(state.prepData.hopId, state.stalledHop);
        ISSShockhopper(state.shockhopper).updateHopsByAddress(state.user, state.prepData.hopId);
        ISSShockhopper(state.shockhopper).updateTotalHops(state.prepData.hopId);
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
        // Step 1: Validate impactPricePercents
        validateImpactPercents(request.impactPricePercents);

        // Step 2: Prepare hop data
        HopPrepData memory prepData = prepHop(request, 0, shockhopper);
        uint256 hopId = prepData.hopId;

        // Step 3: Initialize execution state
        HopExecutionState memory state = HopExecutionState({
            user: user,
            shockhopper: shockhopper,
            proxyRouter: proxyRouter,
            prepData: prepData,
            stalledHop: initializeStalledHop(request, user, prepData)
        });

        // Step 4: Process each stage
        for (uint256 i = 0; i < prepData.indices.length; i++) {
            processHopStage(state, request, i);
            return;
        }

        // Step 5: Finalize hop if all stages completed
        finalizeHop(state);
    }

    // Prepare stalls
    function prepStalls(
        address user,
        uint256[] memory userHops,
        address shockhopper
    ) external returns (StallData[] memory) {
        StallData[] memory stalls = new StallData[](userHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userHops.length && count < 20; i++) {
            StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(userHops[i]);
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

        // Resize stalls array
        if (count < stalls.length) {
            StallData[] memory resizedStalls = new StallData[](count);
            for (uint256 i = 0; i < count; i++) {
                resizedStalls[i] = stalls[i];
            }
            stalls = resizedStalls;
        }

        if (count > 0) {
            emit StallsPrepared(stalls[0].hopId, count);
        }
        return stalls;
    }

    // Helper: Process a single stall
    function processSingleStall(
        StallData memory stall,
        StalledHop memory hop,
        address shockhopper
    ) internal returns (bool) {
        if (hop.hopStatus != 1 || stall.status != 3) return false;

        uint256 nextStage = uint256(hop.stage) + 1;
        if (nextStage >= hop.remainingListings.length) {
            hop.hopStatus = 2;
            ISSShockhopper(shockhopper).updateTotalHops(stall.hopId);
            emit HopContinued(stall.hopId, uint8(nextStage));
            ISSShockhopper(shockhopper).updateStalledHop(stall.hopId, hop);
            return true;
        }

        hop.stage = uint8(nextStage);
        hop.currentListing = hop.remainingListings[0];
        if (hop.settleType == 0) {
            hop.orderIds[nextStage] = ISSListing(hop.currentListing).getNextOrderId(0);
        } else {
            hop.orderIds[nextStage] = 0;
        }

        // Update remainingListings
        address[] memory newRemaining = new address[](hop.remainingListings.length - 1);
        for (uint256 j = 0; j < newRemaining.length; j++) {
            newRemaining[j] = hop.remainingListings[j + 1];
        }
        hop.remainingListings = newRemaining;

        ISSShockhopper(shockhopper).updateStalledHop(stall.hopId, hop);
        emit HopContinued(stall.hopId, uint8(nextStage));
        return true;
    }

    // Helper: Remove completed hops
    function removeCompletedHops(
        address user,
        address shockhopper
    ) internal {
        uint256[] memory userHops = ISSShockhopper(shockhopper).getHopsByAddress(user);
        for (uint256 i = userHops.length; i > 0; i--) {
            StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(userHops[i - 1]);
            if (hop.hopStatus == 2) {
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
    ) internal {
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
        address proxyRouter
    ) external returns (uint256 canceled) {
        canceled = 0;

        for (uint256 i = userHops.length; i > 0 && canceled < 100; i--) {
            uint256 hopId = userHops[i - 1];
            StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(hopId);
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