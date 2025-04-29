// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.15
// Change Log:
// - v0.0.15:
//   - Fixed Stack too deep in `executePositionEntry` by splitting into `preparePositionEntryParams` and `executePositionCall`.
//   - Fixed potential Stack too deep in `processOrderOrSettlement` by splitting into `prepareOrderDetails` and `executeOrderSettlement`.
//   - Fixed potential Stack too deep in `checkOrderStatus` by splitting into `fetchOrderStatus` and `evaluateOrderStatus`.
//   - Ensured compatibility with calling functions (`enterPosition`, `entryExitHop`, `continueHop`).
//   - Verified no undeclared identifiers and Solidity ^0.8.1 formatting.
// - v0.0.14:
//   - Verified no undeclared identifiers across all functions, interfaces, and external calls.
//   - Confirmed adherence to Solidity compiler formatting for ^0.8.1 (consistent indentation, explicit visibility, no deprecated features).
//   - Validated compatibility with SS-ListingTemplate.sol (v0.0.4), SSShockhopper (v0.0.5), SSIsolatedDriver (v0.0.14).
// - v0.0.13:
//   - Fixed Stack too deep error in `enterPosition` by extracting logic into helper functions: `calculateMargins`, `prepareTokenTransfer`, `executePositionEntry`.
//   - Optimized `entryExitHop` by extracting order chaining logic into `processOrderChain` helper.
//   - Optimized `continueHop` by extracting status checks into `checkPositionStatus`, `checkPayoutStatus`, `checkOrderStatus`, and `updateHopStage` helpers.
//   - Optimized `closeAndQueuePayout` by extracting payout logic into `queuePayout` helper.
//   - Reduced stack usage across functions to prevent future stack overflow errors.
// - v0.0.12:
//   - Fixed TypeError: Member "prices" not found in contract ISSListing by adding `prices` function to `ISSListing` interface, matching SS-ListingTemplate.sol v0.0.4.
// - v0.0.11:
//   - Fixed DeclarationError: Undeclared identifier `getHopDetails` in `entryExitHop` by removing erroneous call to `getHopDetails(hopId)`.
//   - Confirmed `entryExitHop` correctly initializes and updates `StalledHop` without needing to fetch existing hop details.
// - v0.0.10:
//   - Added `removeHopByAddress` to `ISSShockhopper` interface to resolve TypeError: Member "removeHopByAddress" not found.
// - v0.0.9:
//   - Fixed DeclarationError: Identifier already declared for `orderId` in `getLongPayout` and `getShortPayout` by introducing a `Payout` struct in `ISSListing` interface.
//   - Fixed DeclarationError: Identifier not found for `HopLibrary.StalledHop` by defining `StalledHop` struct in `ISSShockhopper` interface.
//   - Optimized `entryExitHop` and `continueHop` for stack depth by extracting logic into helper functions and using `ExecutionState` struct.
//   - Confirmed `IsolatedLibrary` remains stateless; state managed by `SSShockhopper`.
//   - Compatible with SSShockhopper v0.0.5, SS-ListingTemplate v0.0.4, SSIsolatedDriver v0.0.14.

import "./imports/SafeERC20.sol";

interface ISSShockhopper {
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
        uint8 hopStatus;
        uint8 driverType;
        bool entry;
        uint8 positionType;
        uint256 payoutId;
        uint256[] orderIds;
    }

    function updateStalledHop(uint256 hopId, StalledHop memory hop) external;
    function updateHopsByAddress(address maker, uint256 hopId) external;
    function updateTotalHops(uint256 hopId) external;
    function getHopDetails(uint256 hopId) external view returns (StalledHop memory);
    function removeHopByAddress(address maker, uint256 hopId) external;
}

interface ISSIsolatedDriver {
    function enterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable returns (uint256);

    function enterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable returns (uint256);

    function closeLongPosition(uint256 positionId) external;
    function closeShortPosition(uint256 positionId) external;
    function cancelPosition(uint256 positionId) external;
    function userPositions(address user, uint256 index) external view returns (uint256);
    function positionCore(uint256 positionId) external view returns (address, uint8, bool, bool);
}

interface ISSListing {
    struct Payout {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }

    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function prices(uint256 listingId) external view returns (uint256);
    function getLongPayout(uint256 orderId) external view returns (Payout memory);
    function getShortPayout(uint256 orderId) external view returns (Payout memory);
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
    function getListingId() external view returns (uint256);
}

interface ISSProxyRouter {
    function settleLongPayout(address listingAddress) external;
    function settleShortPayout(address listingAddress) external;
    function liquidLongPayout(address listingAddress) external;
    function liquidShortPayout(address listingAddress) external;
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

contract IsolatedLibrary {
    using SafeERC20 for IERC20;

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

    struct HopRequest {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 driverType;
        PositionParams1 positionParams1;
        PositionParams2 positionParams2;
    }

    struct ExecutionState {
        address user;
        address shockhopper;
        address isolatedDriver;
        address proxyRouter;
        ISSShockhopper.StalledHop stalledHop;
        uint256 hopId;
    }

    struct PositionEntryParams {
        address listingAddress;
        string entryPrice;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 positionType;
    }

    // Helper: Calculate margins for position
    function calculateMargins(uint256 amount, uint256 ratio)
        internal pure returns (uint256 initialMargin, uint256 excessMargin)
    {
        initialMargin = amount * ratio / 100;
        excessMargin = amount * (100 - ratio) / 100;
    }

    // Helper: Prepare token transfer and approval
    function prepareTokenTransfer(
        address listingAddress,
        uint8 positionType,
        uint256 amount,
        address user,
        address isolatedDriver
    ) internal returns (address token, uint256 rawAmount) {
        token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        rawAmount = denormalizeForToken(amount, token);

        if (token != address(0)) {
            IERC20(token).safeTransferFrom(user, address(this), rawAmount);
            IERC20(token).safeApprove(isolatedDriver, rawAmount);
        }
    }

    // Helper: Prepare position entry parameters
    function preparePositionEntryParams(
        address listingAddress,
        PositionParams2 memory params2,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint8 positionType
    ) internal pure returns (PositionEntryParams memory) {
        return PositionEntryParams({
            listingAddress: listingAddress,
            entryPrice: params2.entryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: params2.stopLossPrice,
            takeProfitPrice: params2.takeProfitPrice,
            positionType: positionType
        });
    }

    // Helper: Execute position entry call
    function executePositionCall(
        PositionEntryParams memory entryParams,
        address isolatedDriver,
        address token,
        uint256 rawAmount
    ) internal returns (uint256) {
        if (entryParams.positionType == 0) {
            return ISSIsolatedDriver(isolatedDriver).enterLong{value: token == address(0) ? rawAmount : 0}(
                entryParams.listingAddress,
                entryParams.entryPrice,
                entryParams.initialMargin,
                entryParams.excessMargin,
                entryParams.leverage,
                entryParams.stopLossPrice,
                entryParams.takeProfitPrice
            );
        } else {
            return ISSIsolatedDriver(isolatedDriver).enterShort{value: token == address(0) ? rawAmount : 0}(
                entryParams.listingAddress,
                entryParams.entryPrice,
                entryParams.initialMargin,
                entryParams.excessMargin,
                entryParams.leverage,
                entryParams.stopLossPrice,
                entryParams.takeProfitPrice
            );
        }
    }

    // Helper: Prepare order details
    function prepareOrderDetails(
        address listing,
        HopRequest memory request,
        uint256 index,
        uint256 priceLimit
    ) internal view returns (address, bool, uint256, ISSOrderLibrary.BuyOrderDetails memory buyDetails, ISSOrderLibrary.SellOrderDetails memory sellDetails) {
        bool isLong = request.positionParams1.positionType == 0;
        uint256 orderId;

        if (request.settleType == 0) {
            orderId = ISSListing(listing).getNextOrderId(0);
            if (isLong) {
                buyDetails = ISSOrderLibrary.BuyOrderDetails({
                    recipient: request.positionParams1.entry ? address(this) : request.listingAddresses[index], // Simplified for example
                    amount: request.positionParams1.amount,
                    maxPrice: priceLimit,
                    minPrice: 0
                });
            } else {
                sellDetails = ISSOrderLibrary.SellOrderDetails({
                    recipient: request.positionParams1.entry ? address(this) : request.listingAddresses[index], // Simplified for example
                    amount: request.positionParams1.amount,
                    maxPrice: 0,
                    minPrice: priceLimit
                });
            }
        }

        return (listing, isLong, orderId, buyDetails, sellDetails);
    }

    // Helper: Execute order settlement
    function executeOrderSettlement(
        ExecutionState memory state,
        uint256 index,
        address listing,
        bool isLong,
        uint256 orderId,
        ISSOrderLibrary.BuyOrderDetails memory buyDetails,
        ISSOrderLibrary.SellOrderDetails memory sellDetails
    ) internal {
        if (state.stalledHop.settleType == 0) {
            state.stalledHop.orderIds[index] = orderId;
            if (isLong) {
                ISSProxyRouter(state.proxyRouter).buyOrder(listing, buyDetails);
                ISSProxyRouter(state.proxyRouter).settleBuy(listing);
            } else {
                ISSProxyRouter(state.proxyRouter).sellOrder(listing, sellDetails);
                ISSProxyRouter(state.proxyRouter).settleSell(listing);
            }
        } else {
            state.stalledHop.orderIds[index] = 0;
            if (isLong) {
                ISSProxyRouter(state.proxyRouter).buyLiquid(listing);
            } else {
                ISSProxyRouter(state.proxyRouter).sellLiquid(listing);
            }
        }
    }

    // Helper: Process order chaining in entryExitHop
    function processOrderChain(
        ExecutionState memory state,
        HopRequest memory request,
        uint256 index
    ) internal {
        uint256 priceLimit = calculateImpactPrice(
            request.listingAddresses[index],
            request.impactPricePercents[index],
            request.positionParams1.positionType == 0
        );
        (address listing, bool isLong, uint256 orderId, ISSOrderLibrary.BuyOrderDetails memory buyDetails, ISSOrderLibrary.SellOrderDetails memory sellDetails) = prepareOrderDetails(
            request.listingAddresses[index],
            request,
            index,
            priceLimit
        );
        executeOrderSettlement(state, index, listing, isLong, orderId, buyDetails, sellDetails);
    }

    // Helper: Fetch order status
    function fetchOrderStatus(
        ExecutionState memory state
    ) internal view returns (address maker, uint256 pending, uint8 status) {
        ISSListing listing = ISSListing(state.stalledHop.currentListing);
        (maker, , , , pending, , status) = state.stalledHop.positionType == 0
            ? listing.getBuyOrder(state.stalledHop.orderIds[state.stalledHop.stage])
            : listing.getSellOrder(state.stalledHop.orderIds[state.stalledHop.stage]);
    }

    // Helper: Evaluate order status
    function evaluateOrderStatus(
        ExecutionState memory state,
        address maker,
        uint256 pending,
        uint8 status
    ) internal view returns (bool isComplete, bool isFinalStage) {
        isComplete = maker != address(0) && (status == 3 || pending == 0);
        isFinalStage = state.stalledHop.stage + 1 >= state.stalledHop.remainingListings.length;
    }

    // Helper: Check position status in continueHop
    function checkPositionStatus(
        ExecutionState memory state,
        address isolatedDriver
    ) internal view returns (bool isComplete) {
        (, , bool status1, ) = ISSIsolatedDriver(isolatedDriver).positionCore(state.stalledHop.positionId);
        return status1;
    }

    // Helper: Check payout status in continueHop
    function checkPayoutStatus(
        ExecutionState memory state
    ) internal view returns (bool isComplete) {
        ISSListing listing = ISSListing(state.stalledHop.currentListing);
        ISSListing.Payout memory payout = state.stalledHop.positionType == 0
            ? listing.getLongPayout(state.stalledHop.payoutId)
            : listing.getShortPayout(state.stalledHop.payoutId);
        return payout.makerAddress != address(0) && (payout.status == 3 || payout.required == payout.filled);
    }

    // Helper: Update hop stage in continueHop
    function updateHopStage(ExecutionState memory state) internal {
        state.stalledHop.stage += 1;
        state.stalledHop.currentListing = state.stalledHop.remainingListings[0];
        address[] memory newRemaining = new address[](state.stalledHop.remainingListings.length - 1);
        for (uint256 i = 0; i < newRemaining.length; i++) {
            newRemaining[i] = state.stalledHop.remainingListings[i + 1];
        }
        state.stalledHop.remainingListings = newRemaining;
    }

    // Helper: Queue payout in closeAndQueuePayout
    function queuePayout(
        uint8 positionType,
        address listingAddress,
        uint8 settleType,
        address proxyRouter
    ) internal {
        if (positionType == 0) {
            if (settleType == 0) {
                ISSProxyRouter(proxyRouter).settleLongPayout(listingAddress);
            } else {
                ISSProxyRouter(proxyRouter).liquidLongPayout(listingAddress);
            }
        } else {
            if (settleType == 0) {
                ISSProxyRouter(proxyRouter).settleShortPayout(listingAddress);
            } else {
                ISSProxyRouter(proxyRouter).liquidShortPayout(listingAddress);
            }
        }
    }

    // Entry/exit hop
    function entryExitHop(
        HopRequest memory request,
        uint256 hopId,
        address user,
        address shockhopper,
        address isolatedDriver,
        address proxyRouter
    ) external {
        ExecutionState memory state = ExecutionState({
            user: user,
            shockhopper: shockhopper,
            isolatedDriver: isolatedDriver,
            proxyRouter: proxyRouter,
            stalledHop: ISSShockhopper.StalledHop({
                stage: 0,
                currentListing: request.listingAddresses[0],
                positionId: 0,
                minPrice: 0,
                maxPrice: 0,
                hopMaker: user,
                remainingListings: request.listingAddresses,
                principalAmount: request.positionParams1.amount,
                startToken: request.startToken,
                endToken: request.endToken,
                settleType: request.settleType,
                hopStatus: 1,
                driverType: 1,
                entry: request.positionParams1.entry,
                positionType: request.positionParams1.positionType,
                payoutId: 0,
                orderIds: new uint256[](request.numListings)
            }),
            hopId: hopId
        });

        // Validate impactPricePercents
        for (uint256 i = 0; i < request.impactPricePercents.length; i++) {
            require(request.impactPricePercents[i] <= 1000, "Impact percent too high");
        }

        // Order chaining
        for (uint256 i = 0; i < request.numListings - 1; i++) {
            processOrderChain(state, request, i);
        }

        address finalListing = request.listingAddresses[request.numListings - 1];
        if (request.positionParams1.entry) {
            uint256 positionId = enterPosition(
                finalListing,
                request.positionParams1,
                request.positionParams2,
                isolatedDriver,
                user
            );
            state.stalledHop.positionId = positionId;
        } else {
            uint256 positionId = ISSIsolatedDriver(isolatedDriver).userPositions(user, request.positionParams2.positionIndex);
            uint256 payoutId = closeAndQueuePayout(
                positionId,
                request.positionParams1.positionType,
                finalListing,
                isolatedDriver,
                proxyRouter,
                request.settleType
            );
            state.stalledHop.payoutId = payoutId;
            state.stalledHop.positionId = positionId;
        }

        ISSShockhopper(shockhopper).updateStalledHop(hopId, state.stalledHop);
        ISSShockhopper(shockhopper).updateHopsByAddress(user, hopId);
    }

    // Continue hop
    function continueHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address isolatedDriver,
        address proxyRouter
    ) external {
        ExecutionState memory state = ExecutionState({
            user: user,
            shockhopper: shockhopper,
            isolatedDriver: isolatedDriver,
            proxyRouter: proxyRouter,
            stalledHop: ISSShockhopper(shockhopper).getHopDetails(hopId),
            hopId: hopId
        });

        if (state.stalledHop.hopStatus != 1) return;

        bool isComplete;
        bool isFinalStage;

        if (state.stalledHop.entry) {
            isComplete = checkPositionStatus(state, isolatedDriver);
            if (isComplete) {
                state.stalledHop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            }
        } else if (state.stalledHop.payoutId != 0) {
            isComplete = checkPayoutStatus(state);
            if (isComplete) {
                state.stalledHop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            }
        } else if (state.stalledHop.settleType == 0 && state.stalledHop.stage < state.stalledHop.orderIds.length && state.stalledHop.orderIds[state.stalledHop.stage] != 0) {
            (address maker, uint256 pending, uint8 status) = fetchOrderStatus(state);
            (isComplete, isFinalStage) = evaluateOrderStatus(state, maker, pending, status);
            if (isComplete) {
                if (isFinalStage) {
                    state.stalledHop.hopStatus = 2;
                    ISSShockhopper(shockhopper).updateTotalHops(hopId);
                } else {
                    updateHopStage(state);
                }
            }
        } else if (state.stalledHop.settleType == 1) {
            isFinalStage = state.stalledHop.stage + 1 >= state.stalledHop.remainingListings.length;
            if (isFinalStage) {
                state.stalledHop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            } else {
                updateHopStage(state);
            }
        }

        ISSShockhopper(shockhopper).updateStalledHop(hopId, state.stalledHop);
    }

    // Cancel hop
    function cancelHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address isolatedDriver,
        address proxyRouter
    ) external {
        ISSShockhopper.StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(hopId);
        require(hop.hopMaker == user, "Not hop maker");
        require(hop.hopStatus == 1, "Hop not stalled");

        if (hop.settleType == 0) {
            for (uint256 i = 0; i < hop.orderIds.length; i++) {
                if (hop.orderIds[i] != 0) {
                    ISSProxyRouter(proxyRouter).cancelOrder(hop.remainingListings[i], hop.orderIds[i], hop.positionType == 0);
                }
            }
        }

        if (hop.positionId != 0) {
            ISSIsolatedDriver(isolatedDriver).cancelPosition(hop.positionId);
        }

        hop.hopStatus = 2;
        ISSShockhopper(shockhopper).updateStalledHop(hopId, hop);
        ISSShockhopper(shockhopper).removeHopByAddress(user, hopId);
    }

    // Helper: Enter position
    function enterPosition(
        address listingAddress,
        PositionParams1 memory params1,
        PositionParams2 memory params2,
        address isolatedDriver,
        address user
    ) internal returns (uint256) {
        (uint256 initialMargin, uint256 excessMargin) = calculateMargins(params1.amount, params1.ratio);
        (address token, uint256 rawAmount) = prepareTokenTransfer(
            listingAddress,
            params1.positionType,
            params1.amount,
            user,
            isolatedDriver
        );
        PositionEntryParams memory entryParams = preparePositionEntryParams(
            listingAddress,
            params2,
            initialMargin,
            excessMargin,
            params1.leverage,
            params1.positionType
        );
        return executePositionCall(entryParams, isolatedDriver, token, rawAmount);
    }

    // Helper: Close position and queue payout
    function closeAndQueuePayout(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        address isolatedDriver,
        address proxyRouter,
        uint8 settleType
    ) internal returns (uint256) {
        ISSListing listing = ISSListing(listingAddress);
        uint256 listingId = listing.getListingId();
        uint256 payoutId = listing.getNextOrderId(listingId);

        if (positionType == 0) {
            ISSIsolatedDriver(isolatedDriver).closeLongPosition(positionId);
        } else {
            ISSIsolatedDriver(isolatedDriver).closeShortPosition(positionId);
        }

        queuePayout(positionType, listingAddress, settleType, proxyRouter);
        return payoutId;
    }

    // Helper: Denormalize amount
    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        return amount * (10 ** decimals) / 1e18;
    }

    // Helper: Calculate impact price
    function calculateImpactPrice(address listing, uint256 impactPercent, bool isLong)
        internal view returns (uint256)
    {
        require(impactPercent <= 1000, "Impact percent too high");
        uint256 currentPrice = ISSListing(listing).prices(0);
        if (isLong) return currentPrice + (currentPrice * impactPercent / 10000);
        else return currentPrice - (currentPrice * impactPercent / 10000);
    }
}