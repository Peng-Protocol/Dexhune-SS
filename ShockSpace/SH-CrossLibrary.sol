// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.8
// - Updated from v0.0.7: Fetch orderIds only for buyOrder/sellOrder (settleType == 0)
// - Clarified buyLiquid/sellLiquid as settlement functions, not order functions
// - Modified entryExitHop to skip orderId for buyLiquid/sellLiquid
// - Updated continueHop to skip order checks for settleType == 1
// - Updated cancelHop to skip order cancellation for settleType == 1
// - Retained payoutId fetching for closeAndQueuePayout
// - Compatible with SSShockhopper v0.0.5, SS-ListingTemplate v0.0.4, SSCrossDriver v0.0.10

import "./imports/SafeERC20.sol";

interface IHopLibrary {
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
}

interface ISSShockhopper {
    function updateStalledHop(uint256 hopId, IHopLibrary.StalledHop memory hop) external;
    function updateHopsByAddress(address maker, uint256 hopId) external;
    function updateTotalHops(uint256 hopId) external;
    function getHopDetails(uint256 hopId) external view returns (IHopLibrary.StalledHop memory);
    function removeHopByAddress(address maker, uint256 hopId) external;
}

interface ISSCrossDriver {
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
    struct PayoutDetails {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 payoutOrderId;
        uint8 status;
    }

    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function getLongPayout(uint256 orderId) external view returns (PayoutDetails memory);
    function getShortPayout(uint256 orderId) external view returns (PayoutDetails memory);
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
    function prices(uint256 listingId) external view returns (uint256);
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

contract CrossLibrary {
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
        uint8 settleType; // 0 = market-based, 1 = liquidity-based
        uint8 driverType; // 0 = CrossDriver, 1 = IsolatedDriver
        PositionParams1 positionParams1;
        PositionParams2 positionParams2;
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

    // Entry/exit hop
    function entryExitHop(
        HopRequest memory request,
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external {
        StalledHop memory stalledHop = StalledHop({
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
            driverType: 0,
            entry: request.positionParams1.entry,
            positionType: request.positionParams1.positionType,
            payoutId: 0,
            orderIds: new uint256[](request.numListings)
        });

        // Validate impactPricePercents
        for (uint256 i = 0; i < request.impactPricePercents.length; i++) {
            require(request.impactPricePercents[i] <= 1000, "Impact percent too high"); // Max 10%
        }

        // Order chaining
        for (uint256 i = 0; i < request.numListings - 1; i++) {
            address listing = request.listingAddresses[i];
            bool isLong = request.positionParams1.positionType == 0;
            uint256 priceLimit = calculateImpactPrice(listing, request.impactPricePercents[i], isLong);

            if (request.settleType == 0) {
                // Fetch orderId for market-based orders
                ISSListing listingContract = ISSListing(listing);
                uint256 orderId = listingContract.getNextOrderId(0); // listingId = 0
                stalledHop.orderIds[i] = orderId;

                if (isLong) {
                    ISSOrderLibrary.BuyOrderDetails memory details = ISSOrderLibrary.BuyOrderDetails({
                        recipient: user,
                        amount: request.positionParams1.amount,
                        maxPrice: priceLimit,
                        minPrice: 0
                    });
                    ISSProxyRouter(proxyRouter).buyOrder(listing, details);
                    ISSProxyRouter(proxyRouter).settleBuy(listing);
                } else {
                    ISSOrderLibrary.SellOrderDetails memory details = ISSOrderLibrary.SellOrderDetails({
                        recipient: user,
                        amount: request.positionParams1.amount,
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
        }

        address finalListing = request.listingAddresses[request.numListings - 1];
        if (request.positionParams1.entry) {
            // Entry hop: Enter position
            uint256 positionId = enterPosition(
                finalListing,
                request.positionParams1,
                request.positionParams2,
                crossDriver,
                user
            );
            stalledHop.positionId = positionId;
        } else {
            // Exit hop: Close position, settle payout
            uint256 positionId = ISSCrossDriver(crossDriver).userPositions(user, request.positionParams2.positionIndex);
            uint256 payoutId = closeAndQueuePayout(
                positionId,
                request.positionParams1.positionType,
                finalListing,
                crossDriver,
                proxyRouter,
                request.settleType
            );
            stalledHop.payoutId = payoutId;
            stalledHop.positionId = positionId;
        }

        // Convert local StalledHop to IHopLibrary.StalledHop for interface compatibility
        IHopLibrary.StalledHop memory hopForShockhopper = IHopLibrary.StalledHop({
            stage: stalledHop.stage,
            currentListing: stalledHop.currentListing,
            positionId: stalledHop.positionId,
            minPrice: stalledHop.minPrice,
            maxPrice: stalledHop.maxPrice,
            hopMaker: stalledHop.hopMaker,
            remainingListings: stalledHop.remainingListings,
            principalAmount: stalledHop.principalAmount,
            startToken: stalledHop.startToken,
            endToken: stalledHop.endToken,
            settleType: stalledHop.settleType,
            hopStatus: stalledHop.hopStatus,
            driverType: stalledHop.driverType,
            entry: stalledHop.entry,
            positionType: stalledHop.positionType,
            payoutId: stalledHop.payoutId,
            orderIds: stalledHop.orderIds
        });

        ISSShockhopper(shockhopper).updateStalledHop(hopId, hopForShockhopper);
        ISSShockhopper(shockhopper).updateHopsByAddress(user, hopId);
    }

    // Continue hop
    function continueHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external {
        IHopLibrary.StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(hopId);
        if (hop.hopStatus != 1) return;

        // Convert IHopLibrary.StalledHop to local StalledHop for internal processing
        StalledHop memory localHop = StalledHop({
            stage: hop.stage,
            currentListing: hop.currentListing,
            positionId: hop.positionId,
            minPrice: hop.minPrice,
            maxPrice: hop.maxPrice,
            hopMaker: hop.hopMaker,
            remainingListings: hop.remainingListings,
            principalAmount: hop.principalAmount,
            startToken: hop.startToken,
            endToken: hop.endToken,
            settleType: hop.settleType,
            hopStatus: hop.hopStatus,
            driverType: hop.driverType,
            entry: hop.entry,
            positionType: hop.positionType,
            payoutId: hop.payoutId,
            orderIds: hop.orderIds
        });

        if (localHop.entry) {
            (, , bool status1, ) = ISSCrossDriver(crossDriver).positionCore(localHop.positionId);
            if (status1) {
                localHop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            }
        } else if (localHop.payoutId != 0) {
            // Check payout status
            ISSListing listing = ISSListing(localHop.currentListing);
            ISSListing.PayoutDetails memory payout = localHop.positionType == 0
                ? listing.getLongPayout(localHop.payoutId)
                : listing.getShortPayout(localHop.payoutId);
            if (payout.makerAddress != address(0) && (payout.status == 3 || payout.required == payout.filled)) {
                localHop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            }
        } else if (localHop.settleType == 0 && localHop.stage < localHop.orderIds.length && localHop.orderIds[localHop.stage] != 0) {
            // Check order status for market-based hops
            ISSListing listing = ISSListing(localHop.currentListing);
            (address maker, , , , uint256 pending, , uint8 status) = localHop.positionType == 0
                ? listing.getBuyOrder(localHop.orderIds[localHop.stage])
                : listing.getSellOrder(localHop.orderIds[localHop.stage]);
            if (maker != address(0) && (status == 3 || pending == 0)) {
                if (localHop.stage + 1 >= localHop.remainingListings.length) {
                    localHop.hopStatus = 2;
                    ISSShockhopper(shockhopper).updateTotalHops(hopId);
                } else {
                    localHop.stage += 1;
                    localHop.currentListing = localHop.remainingListings[0];
                    address[] memory newRemaining = new address[](localHop.remainingListings.length - 1);
                    for (uint256 i = 0; i < newRemaining.length; i++) {
                        newRemaining[i] = localHop.remainingListings[i + 1];
                    }
                    localHop.remainingListings = newRemaining;
                }
            }
        } else if (localHop.settleType == 1) {
            // Assume liquidity-based settlement is complete
            if (localHop.stage + 1 >= localHop.remainingListings.length) {
                localHop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            } else {
                localHop.stage += 1;
                localHop.currentListing = localHop.remainingListings[0];
                address[] memory newRemaining = new address[](localHop.remainingListings.length - 1);
                for (uint256 i = 0; i < newRemaining.length; i++) {
                    newRemaining[i] = localHop.remainingListings[i + 1];
                }
                localHop.remainingListings = newRemaining;
            }
        }

        // Convert back to IHopLibrary.StalledHop for update
        IHopLibrary.StalledHop memory hopForShockhopper = IHopLibrary.StalledHop({
            stage: localHop.stage,
            currentListing: localHop.currentListing,
            positionId: localHop.positionId,
            minPrice: localHop.minPrice,
            maxPrice: localHop.maxPrice,
            hopMaker: localHop.hopMaker,
            remainingListings: localHop.remainingListings,
            principalAmount: localHop.principalAmount,
            startToken: localHop.startToken,
            endToken: localHop.endToken,
            settleType: localHop.settleType,
            hopStatus: localHop.hopStatus,
            driverType: localHop.driverType,
            entry: localHop.entry,
            positionType: localHop.positionType,
            payoutId: localHop.payoutId,
            orderIds: localHop.orderIds
        });

        ISSShockhopper(shockhopper).updateStalledHop(hopId, hopForShockhopper);
    }

    // Cancel hop
    function cancelHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external {
        IHopLibrary.StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(hopId);

        // Convert IHopLibrary.StalledHop to local StalledHop
        StalledHop memory localHop = StalledHop({
            stage: hop.stage,
            currentListing: hop.currentListing,
            positionId: hop.positionId,
            minPrice: hop.minPrice,
            maxPrice: hop.maxPrice,
            hopMaker: hop.hopMaker,
            remainingListings: hop.remainingListings,
            principalAmount: hop.principalAmount,
            startToken: hop.startToken,
            endToken: hop.endToken,
            settleType: hop.settleType,
            hopStatus: hop.hopStatus,
            driverType: hop.driverType,
            entry: hop.entry,
            positionType: hop.positionType,
            payoutId: hop.payoutId,
            orderIds: hop.orderIds
        });

        require(localHop.hopMaker == user, "Not hop maker");
        require(localHop.hopStatus == 1, "Hop not stalled");

        // Cancel orders for market-based hops only
        if (localHop.settleType == 0) {
            for (uint256 i = 0; i < localHop.orderIds.length; i++) {
                if (localHop.orderIds[i] != 0) {
                    ISSProxyRouter(proxyRouter).cancelOrder(localHop.remainingListings[i], localHop.orderIds[i], localHop.positionType == 0);
                }
            }
        }

        // Cancel position if exists
        if (localHop.positionId != 0) {
            ISSCrossDriver(crossDriver).cancelPosition(localHop.positionId);
        }

        localHop.hopStatus = 2;

        // Convert back to IHopLibrary.StalledHop for update
        IHopLibrary.StalledHop memory hopForShockhopper = IHopLibrary.StalledHop({
            stage: localHop.stage,
            currentListing: localHop.currentListing,
            positionId: localHop.positionId,
            minPrice: localHop.minPrice,
            maxPrice: localHop.maxPrice,
            hopMaker: localHop.hopMaker,
            remainingListings: localHop.remainingListings,
            principalAmount: localHop.principalAmount,
            startToken: localHop.startToken,
            endToken: localHop.endToken,
            settleType: localHop.settleType,
            hopStatus: localHop.hopStatus,
            driverType: localHop.driverType,
            entry: localHop.entry,
            positionType: localHop.positionType,
            payoutId: localHop.payoutId,
            orderIds: localHop.orderIds
        });

        ISSShockhopper(shockhopper).updateStalledHop(hopId, hopForShockhopper);
        ISSShockhopper(shockhopper).removeHopByAddress(user, hopId);
    }

    // Helper: Calculate margins for position entry
    function calculateMargins(
        uint256 amount,
        uint256 ratio
    ) internal pure returns (uint256 initialMargin, uint256 excessMargin) {
        initialMargin = amount * ratio / 100;
        excessMargin = amount * (100 - ratio) / 100;
    }

    // Helper: Determine token and normalize amount
    function getTokenAndAmount(
        address listingAddress,
        uint8 positionType,
        uint256 amount
    ) internal view returns (address token, uint256 rawAmount) {
        token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        rawAmount = denormalizeForToken(amount, token);
    }

    // Helper: Handle token transfer and approval
    function handleTokenTransfer(
        address token,
        address user,
        address crossDriver,
        uint256 rawAmount
    ) internal {
        if (token != address(0)) {
            IERC20(token).safeTransferFrom(user, address(this), rawAmount);
            IERC20(token).safeApprove(crossDriver, rawAmount);
        }
    }

    // Helper: Execute position entry
    function executePositionEntry(
        address listingAddress,
        PositionParams1 memory params1,
        PositionParams2 memory params2,
        address crossDriver,
        uint256 rawAmount
    ) internal returns (uint256) {
        if (params1.positionType == 0) {
            return ISSCrossDriver(crossDriver).enterLong{value: rawAmount}(
                listingAddress,
                params2.entryPrice,
                params1.amount * params1.ratio / 100,
                params1.amount * (100 - params1.ratio) / 100,
                params1.leverage,
                params2.stopLossPrice,
                params2.takeProfitPrice
            );
        } else {
            return ISSCrossDriver(crossDriver).enterShort{value: rawAmount}(
                listingAddress,
                params2.entryPrice,
                params1.amount * params1.ratio / 100,
                params1.amount * (100 - params1.ratio) / 100,
                params1.leverage,
                params2.stopLossPrice,
                params2.takeProfitPrice
            );
        }
    }

    // Refactored: Enter position
    function enterPosition(
        address listingAddress,
        PositionParams1 memory params1,
        PositionParams2 memory params2,
        address crossDriver,
        address user
    ) internal returns (uint256) {
        // Step 1: Calculate margins
        (uint256 initialMargin, uint256 excessMargin) = calculateMargins(params1.amount, params1.ratio);

        // Step 2: Get token and normalized amount
        (address token, uint256 rawAmount) = getTokenAndAmount(listingAddress, params1.positionType, params1.amount);

        // Step 3: Handle token transfer and approval
        handleTokenTransfer(token, user, crossDriver, rawAmount);

        // Step 4: Execute position entry
        return executePositionEntry(listingAddress, params1, params2, crossDriver, token == address(0) ? rawAmount : 0);
    }

    // Helper: Fetch payout ID
    function fetchPayoutId(address listingAddress) internal view returns (uint256) {
        ISSListing listing = ISSListing(listingAddress);
        uint256 listingId = listing.getListingId();
        return listing.getNextOrderId(listingId);
    }

    // Helper: Close position
    function closePosition(
        uint256 positionId,
        uint8 positionType,
        address crossDriver
    ) internal {
        if (positionType == 0) {
            ISSCrossDriver(crossDriver).closeLongPosition(positionId);
        } else {
            ISSCrossDriver(crossDriver).closeShortPosition(positionId);
        }
    }

    // Helper: Settle or liquidate payout
    function settleOrLiquidatePayout(
        uint8 positionType,
        address listingAddress,
        address proxyRouter,
        uint8 settleType
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

    // Refactored: Close position and queue payout
    function closeAndQueuePayout(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        address crossDriver,
        address proxyRouter,
        uint8 settleType
    ) internal returns (uint256) {
        // Step 1: Fetch payout ID
        uint256 payoutId = fetchPayoutId(listingAddress);

        // Step 2: Close position
        closePosition(positionId, positionType, crossDriver);

        // Step 3: Settle or liquidate payout
        settleOrLiquidatePayout(positionType, listingAddress, proxyRouter, settleType);

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
        require(impactPercent <= 1000, "Impact percent too high"); // Max 10%
        uint256 currentPrice = ISSListing(listing).prices(0);
        if (isLong) return currentPrice + (currentPrice * impactPercent / 10000);
        else return currentPrice - (currentPrice * impactPercent / 10000);
    }
}