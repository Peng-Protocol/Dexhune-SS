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

interface ISSShockhopper {
    function updateStalledHop(uint256 hopId, HopLibrary.StalledHop memory hop) external;
    function updateHopsByAddress(address maker, uint256 hopId) external;
    function updateTotalHops(uint256 hopId) external;
    function getHopDetails(uint256 hopId) external view returns (HopLibrary.StalledHop memory);
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
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function getLongPayout(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 required,
        uint256 filled,
        uint256 orderId,
        uint8 status
    );
    function getShortPayout(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 required,
        uint256 filled,
        uint256 orderId,
        uint8 status
    );
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

    // Entry/exit hop
    function entryExitHop(
        HopLibrary.HopRequest memory request,
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external {
        HopLibrary.StalledHop memory stalledHop = HopLibrary.StalledHop({
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
            orderIds: new uint256[](request.numListings) // Initialize orderIds
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

        ISSShockhopper(shockhopper).updateStalledHop(hopId, stalledHop);
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
        HopLibrary.StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(hopId);
        if (hop.hopStatus != 1) return;

        if (hop.entry) {
            (, , bool status1, ) = ISSCrossDriver(crossDriver).positionCore(hop.positionId);
            if (status1) {
                hop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            }
        } else if (hop.payoutId != 0) {
            // Check payout status
            ISSListing listing =Dias ISSListing(hop.currentListing);
            (address maker, , uint256 required, uint256 filled, , uint8 status) = hop.positionType == 0
                ? listing.getLongPayout(hop.payoutId)
                : listing.getShortPayout(hop.payoutId);
            if (maker != address(0) && (status == 3 || required == filled)) {
                hop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            }
        } else if (hop.settleType == 0 && hop.stage < hop.orderIds.length && hop.orderIds[hop.stage] != 0) {
            // Check order status for market-based hops
            ISSListing listing = ISSListing(hop.currentListing);
            (address maker, , , , uint256 pending, , uint8 status) = hop.positionType == 0
                ? listing.getBuyOrder(hop.orderIds[hop.stage])
                : listing.getSellOrder(hop.orderIds[hop.stage]);
            if (maker != address(0) && (status == 3 || pending == 0)) {
                if (hop.stage + 1 >= hop.remainingListings.length) {
                    hop.hopStatus = 2;
                    ISSShockhopper(shockhopper).updateTotalHops(hopId);
                } else {
                    hop.stage += 1;
                    hop.currentListing = hop.remainingListings[0];
                    address[] memory newRemaining = new address[](hop.remainingListings.length - 1);
                    for (uint256 i = 0; i < newRemaining.length; i++) {
                        newRemaining[i] = hop.remainingListings[i + 1];
                    }
                    hop.remainingListings = newRemaining;
                }
            }
        } else if (hop.settleType == 1) {
            // Assume liquidity-based settlement is complete
            if (hop.stage + 1 >= hop.remainingListings.length) {
                hop.hopStatus = 2;
                ISSShockhopper(shockhopper).updateTotalHops(hopId);
            } else {
                hop.stage += 1;
                hop.currentListing = hop.remainingListings[0];
                address[] memory newRemaining = new address[](hop.remainingListings.length - 1);
                for (uint256 i = 0; i < newRemaining.length; i++) {
                    newRemaining[i] = hop.remainingListings[i + 1];
                }
                hop.remainingListings = newRemaining;
            }
        }

        ISSShockhopper(shockhopper).updateStalledHop(hopId, hop);
    }

    // Cancel hop
    function cancelHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external {
        HopLibrary.StalledHop memory hop = ISSShockhopper(shockhopper).getHopDetails(hopId);
        require(hop.hopMaker == user, "Not hop maker");
        require(hop.hopStatus == 1, "Hop not stalled");

        // Cancel orders for market-based hops only
        if (hop.settleType == 0) {
            for (uint256 i = 0; i < hop.orderIds.length; i++) {
                if (hop.orderIds[i] != 0) {
                    ISSProxyRouter(proxyRouter).cancelOrder(hop.remainingListings[i], hop.orderIds[i], hop.positionType == 0);
                }
            }
        }

        // Cancel position if exists
        if (hop.positionId != 0) {
            ISSCrossDriver(crossDriver).cancelPosition(hop.positionId);
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
        address crossDriver,
        address user
    ) internal returns (uint256) {
        uint256 initialMargin = params1.amount * params1.ratio / 100;
        uint256 excessMargin = params1.amount * (100 - params1.ratio) / 100;
        address token = params1.positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        uint256 rawAmount = denormalizeForToken(params1.amount, token);

        if (token != address(0)) {
            IERC20(token).safeTransferFrom(user, address(this), rawAmount);
            IERC20(token).safeApprove(crossDriver, rawAmount);
        }

        if (params1.positionType == 0) {
            return ISSCrossDriver(crossDriver).enterLong{value: token == address(0) ? rawAmount : 0}(
                listingAddress,
                params2.entryPrice,
                initialMargin,
                excessMargin,
                params1.leverage,
                params2.stopLossPrice,
                params2.takeProfitPrice
            );
        } else {
            return ISSCrossDriver(crossDriver).enterShort{value: token == address(0) ? rawAmount : 0}(
                listingAddress,
                params2.entryPrice,
                initialMargin,
                excessMargin,
                params1.leverage,
                params2.stopLossPrice,
                params2.takeProfitPrice
            );
        }
    }

    // Helper: Close position and queue payout
    function closeAndQueuePayout(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        address crossDriver,
        address proxyRouter,
        uint8 settleType
    ) internal returns (uint256) {
        ISSListing listing = ISSListing(listingAddress);
        uint256 listingId = listing.getListingId();
        uint256 payoutId = listing.getNextOrderId(listingId);

        if (positionType == 0) {
            ISSCrossDriver(crossDriver).closeLongPosition(positionId);
            if (settleType == 0) {
                ISSProxyRouter(proxyRouter).settleLongPayout(listingAddress);
            } else {
                ISSProxyRouter(proxyRouter).liquidLongPayout(listingAddress);
            }
        } else {
            ISSCrossDriver(crossDriver).closeShortPosition(positionId);
            if (settleType == 0) {
                ISSProxyRouter(proxyRouter).settleShortPayout(listingAddress);
            } else {
                ISSProxyRouter(proxyRouter).liquidShortPayout(listingAddress);
            }
        }

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