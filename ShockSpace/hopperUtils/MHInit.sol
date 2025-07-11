// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.44
// Change Log:
// - 2025-07-11: Removed SafeERC20 import and replaced safeTransferFrom with IERC20.transferFrom in _checkTransfer.
// - 2025-07-11: Added IERC20 import from ../imports/IERC20.sol.
// - 2025-07-11: Updated to fix TypeError in _checkTransfer; replaced direct IERC20.safeTransferFrom with IERC20.transferFrom.
// - Aligned import paths to use ../imports/ for consistency with MHMain.sol.
// - 2025-07-11: Created from Multihopper.sol v0.0.42 split.
// - Included hop-related helper functions from Multihopper.sol.
// - Imports MHMain.sol for structs, interfaces, and state variables.
// - Retained v0.0.42 changes: Extended `CancelPrepData`, updated cancellation for transfer taxes.
// - Retained v0.0.41 and earlier changes: Stack optimization, `maker` parameter, view functions.

import "./MHMain.sol";

contract MHInit is MHMain {
    function getTokenDecimals(address token) internal view returns (uint8) {
        // Returns decimals for a token, defaulting to 18 for native currency (address(0))
        if (token == address(0)) return 18;
        uint8 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return decimals;
    }

    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        // Converts normalized amount to token-specific decimals
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return amount * (10 ** decimals);
    }

    function normalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        // Converts token-specific amount to normalized form
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return amount / (10 ** decimals);
    }

    function computeRoute(address[] memory listingAddresses, address startToken, address endToken)
        internal view returns (uint256[] memory indices, bool[] memory isBuy)
    {
        // Computes the token swap path, ensuring startToken reaches endToken
        require(listingAddresses.length > 0 && listingAddresses.length <= 4, "Invalid listing count");
        indices = new uint256[](listingAddresses.length);
        isBuy = new bool[](listingAddresses.length);
        address currentToken = startToken;
        uint256 pathLength = 0;

        for (uint256 i = 0; i < listingAddresses.length; i++) {
            require(listingAddresses[i] != address(0), "Invalid listing in route");
            ISSListing listing = ISSListing(listingAddresses[i]);
            address tokenA = listing.tokenA();
            address tokenB = listing.tokenB();
            if (currentToken == tokenA) {
                indices[pathLength] = i;
                isBuy[pathLength] = false;
                currentToken = tokenB;
                pathLength++;
            } else if (currentToken == tokenB) {
                indices[pathLength] = i;
                isBuy[pathLength] = true;
                currentToken = tokenA;
                pathLength++;
            }
            if (currentToken == endToken) break;
        }
        require(currentToken == endToken, "No valid route to endToken");
        uint256[] memory resizedIndices = new uint256[](pathLength);
        bool[] memory resizedIsBuy = new bool[](pathLength);
        for (uint256 i = 0; i < pathLength; i++) {
            resizedIndices[i] = indices[i];
            resizedIsBuy[i] = isBuy[i];
        }
        return (resizedIndices, resizedIsBuy);
    }

    function _validatePriceImpact(address listing, uint256 inputAmount, bool isBuy, uint256 impactPercent)
        internal view returns (uint256)
    {
        // Validates price impact does not exceed limit based on input amount and listing balances
        ISSListing listingContract = ISSListing(listing);
        (uint256 xBalance, uint256 yBalance, , ) = listingContract.listingVolumeBalancesView();
        uint256 amountOut = isBuy ? (inputAmount * xBalance) / yBalance : (inputAmount * yBalance) / xBalance;
        uint256 newXBalance = isBuy ? xBalance - amountOut : xBalance + inputAmount;
        uint256 newYBalance = isBuy ? yBalance + inputAmount : yBalance - amountOut;
        uint256 impactPrice = (newXBalance * 1e18) / newYBalance;
        uint256 currentPrice = listingContract.listingPriceView();
        require(currentPrice > 0, "Invalid current price");
        uint256 limitPrice = isBuy ? (currentPrice * (10000 + impactPercent)) / 10000 : (currentPrice * (10000 - impactPercent)) / 10000;
        require(isBuy ? impactPrice <= limitPrice : impactPrice >= limitPrice, "Price impact exceeded");
        return impactPrice;
    }

    function checkOrderStatus(address listing, uint256 orderId, bool isBuy)
        internal view returns (uint256 pending, uint256 filled, uint8 status, uint256 amountSent)
    {
        // Retrieves order details (pending, filled, status, amountSent) for a given order
        ISSListing listingContract = ISSListing(listing);
        if (isBuy) {
            (, , status) = listingContract.getBuyOrderCore(orderId);
            (pending, filled, amountSent) = listingContract.getBuyOrderAmounts(orderId);
        } else {
            (, , status) = listingContract.getSellOrderCore(orderId);
            (pending, filled, amountSent) = listingContract.getSellOrderAmounts(orderId);
        }
    }

    function safeSettle(address listing, bool isBuy, uint8 settleType, uint256 maxIterations)
        internal
    {
        // Settles orders through available routers based on settleType
        require(_routers.length > 0, "No routers set");
        for (uint256 i = 0; i < _routers.length; i++) {
            if (_routers[i].routerType != 1) continue; // Only SSRouter (type 1) used for settlement
            ISSRouter router = ISSRouter(_routers[i].router);
            if (isBuy) {
                if (settleType == 0) {
                    router.settleBuyOrders(listing, maxIterations);
                } else {
                    router.settleBuyLiquid(listing, maxIterations);
                }
            } else {
                if (settleType == 0) {
                    router.settleSellOrders(listing, maxIterations);
                } else {
                    router.settleSellLiquid(listing, maxIterations);
                }
            }
        }
    }

    function _checkTransfer(address token, address from, address to, uint256 amount) internal returns (uint256) {
        // Verifies token transfer success by checking balance changes, assumes approvals are handled externally
        uint256 balanceBefore = token == address(0) ? address(to).balance : IERC20(token).balanceOf(to);
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            bool success = IERC20(token).transferFrom(from, to, amount);
            require(success, "Transfer failed");
        }
        uint256 balanceAfter = token == address(0) ? address(to).balance : IERC20(token).balanceOf(to);
        require(balanceAfter > balanceBefore, "Transfer failed");
        return balanceAfter - balanceBefore;
    }

    function setOrderStatus(HopUpdateType[] memory updates, uint256 index) internal pure {
        // Sets order status in updates array
        updates[index] = HopUpdateType({ field: "status", value: uint256(1) });
    }

    function setOrderAmount(HopUpdateType[] memory updates, uint256 index, string memory orderType, uint256 amount) internal pure {
        // Sets order amount (buyAmount or sellAmount) in updates array
        updates[index] = HopUpdateType({ field: orderType, value: amount });
    }

    function setOrderPrice(HopUpdateType[] memory updates, uint256 index, string memory priceType, uint256 priceLimit) internal pure {
        // Sets price limit (buyPrice or sellPrice) in updates array
        updates[index] = HopUpdateType({ field: priceType, value: priceLimit });
    }

    function setOrderRecipient(HopUpdateType[] memory updates, uint256 index, address recipient) internal pure {
        // Sets recipient address in updates array
        updates[index] = HopUpdateType({ field: "recipient", value: uint256(uint160(recipient)) });
    }

    function computeBaseOrderParams(OrderParams memory params) internal view returns (address inputToken, uint256 normalizedAmount, address recipient, uint256 rawAmount) {
        // Computes base parameters for an order (input token, amounts, recipient)
        ISSListing listingContract = ISSListing(params.listing);
        inputToken = listingContract.tokenB(); // Placeholder, updated in specific params
        normalizedAmount = normalizeForToken(params.principal, inputToken);
        recipient = params.index == params.numListings - 1 ? msg.sender : address(this);
        rawAmount = denormalizeForToken(normalizedAmount, inputToken);
        require(rawAmount > 0, "Invalid raw amount");
    }

    function computeBuySpecificParams(OrderParams memory params, address inputToken, uint256 normalizedAmount, address recipient)
        internal view returns (HopExecutionData memory execData)
    {
        // Computes specific parameters for a buy order
        uint256 priceLimit = _validatePriceImpact(params.listing, normalizedAmount, true, params.impactPercent);
        HopUpdateType[] memory updates = new HopUpdateType[](4);
        setOrderStatus(updates, 0);
        setOrderAmount(updates, 1, "buyAmount", normalizedAmount);
        setOrderPrice(updates, 2, "buyPrice", priceLimit);
        setOrderRecipient(updates, 3, recipient);
        execData = HopExecutionData({
            listing: params.listing,
            isBuy: true,
            recipient: recipient,
            priceLimit: priceLimit,
            principal: denormalizeForToken(normalizedAmount, inputToken),
            inputToken: inputToken,
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: updates
        });
    }

    function computeSellSpecificParams(OrderParams memory params, address inputToken, uint256 normalizedAmount, address recipient)
        internal view returns (HopExecutionData memory execData)
    {
        // Computes specific parameters for a sell order
        uint256 priceLimit = _validatePriceImpact(params.listing, normalizedAmount, false, params.impactPercent);
        HopUpdateType[] memory updates = new HopUpdateType[](4);
        setOrderStatus(updates, 0);
        setOrderAmount(updates, 1, "sellAmount", normalizedAmount);
        setOrderPrice(updates, 2, "sellPrice", priceLimit);
        setOrderRecipient(updates, 3, recipient);
        execData = HopExecutionData({
            listing: params.listing,
            isBuy: false,
            recipient: recipient,
            priceLimit: priceLimit,
            principal: denormalizeForToken(normalizedAmount, inputToken),
            inputToken: inputToken,
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: updates
        });
    }

    function computeBuyOrderParams(OrderParams memory params, address maker) internal view returns (HopExecutionData memory) {
        // Computes buy order parameters, overriding input token and recipient
        ISSListing listingContract = ISSListing(params.listing);
        (address inputToken, uint256 normalizedAmount, , uint256 rawAmount) = computeBaseOrderParams(params);
        inputToken = listingContract.tokenB(); // Override for buy order
        address recipient = params.index == params.numListings - 1 ? maker : address(this);
        require(rawAmount > 0, "Invalid buy order amount");
        return computeBuySpecificParams(params, inputToken, normalizedAmount, recipient);
    }

    function computeSellOrderParams(OrderParams memory params, address maker) internal view returns (HopExecutionData memory) {
        // Computes sell order parameters, overriding input token and recipient
        ISSListing listingContract = ISSListing(params.listing);
        (address inputToken, uint256 normalizedAmount, , uint256 rawAmount) = computeBaseOrderParams(params);
        inputToken = listingContract.tokenA(); // Override for sell order
        address recipient = params.index == params.numListings - 1 ? maker : address(this);
        require(rawAmount > 0, "Invalid sell order amount");
        return computeSellSpecificParams(params, inputToken, normalizedAmount, recipient);
    }

    function updateHopListings(
        HopExecutionParams memory params,
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent
    ) internal pure {
        // Updates HopExecutionParams with listing addresses and impact percents
        params.numListings = 1;
        params.listingAddresses = new address[](4);
        params.impactPricePercents = new uint256[](4);
        params.listingAddresses[0] = listing1;
        params.impactPricePercents[0] = impactPercent;
        if (listing2 != address(0)) {
            params.listingAddresses[1] = listing2;
            params.impactPricePercents[1] = impactPercent;
            params.numListings++;
        }
        if (listing3 != address(0)) {
            params.listingAddresses[2] = listing3;
            params.impactPricePercents[2] = impactPercent;
            params.numListings++;
        }
        if (listing4 != address(0)) {
            params.listingAddresses[3] = listing4;
            params.impactPricePercents[3] = impactPercent;
            params.numListings++;
        }
    }

    function updateHopTokens(
        HopExecutionParams memory params,
        address startToken,
        address endToken
    ) internal pure {
        // Updates HopExecutionParams with start and end tokens
        params.startToken = startToken;
        params.endToken = endToken;
    }

    function updateHopSettings(
        HopExecutionParams memory params,
        uint8 settleType,
        uint256 maxIterations
    ) internal pure {
        // Updates HopExecutionParams with settlement settings
        params.settleType = settleType;
        params.maxIterations = maxIterations;
    }

    function prepareHopExecution(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        HopPrepData memory prepData
    ) internal returns (HopExecutionParams memory) {
        // Prepares hop execution parameters and initializes hop data
        HopExecutionParams memory params;
        updateHopListings(params, listing1, listing2, listing3, listing4, impactPercent);
        updateHopTokens(params, startToken, endToken);
        updateHopSettings(params, settleType, maxIterations);
        validateHopRequest(listing1, listing2, listing3, listing4, impactPercent, params.numListings, maxIterations);
        initializeHopData(listing1, listing2, listing3, listing4, impactPercent, startToken, endToken, settleType, maxIterations, prepData.indices, prepData.hopId, prepData.maker);
        return params;
    }

    function initializeHopData(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256[] memory indices,
        uint256 hopId,
        address maker
    ) internal {
        // Initializes hop data in hopID mapping with specified maker
        uint256 numListings = 1;
        if (listing2 != address(0)) numListings++;
        if (listing3 != address(0)) numListings++;
        if (listing4 != address(0)) numListings++;
        address[] memory listingAddresses = new address[](numListings);
        listingAddresses[0] = listing1;
        if (numListings >= 2) listingAddresses[1] = listing2;
        if (numListings >= 3) listingAddresses[2] = listing3;
        if (numListings == 4) listingAddresses[3] = listing4;
        address[] memory orderedListings = new address[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            orderedListings[i] = listingAddresses[indices[i]];
        }
        hopID[hopId] = StalledHop({
            stage: 0,
            currentListing: orderedListings[0],
            orderID: 0,
            minPrice: 0,
            maxPrice: 0,
            hopMaker: maker,
            remainingListings: orderedListings,
            principalAmount: startToken == address(0) ? msg.value : impactPercent,
            startToken: startToken,
            endToken: endToken,
            settleType: settleType,
            hopStatus: 1,
            maxIterations: maxIterations
        });
    }

    function validateHopRequest(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        uint256 numListings,
        uint256 maxIterations
    ) internal view {
        // Validates hop request parameters, allowing address(0) for trailing listings
        require(numListings > 0 && numListings <= 4, "Invalid listing count");
        require(maxIterations > 0, "Invalid maxIterations");
        require(listing1 != address(0), "First listing required");
        require(ISSAgent(_agent).getListing(listing1), "Invalid listing1");
        require(impactPercent <= 1000, "Impact percent too high");

        if (numListings >= 2) {
            if (listing2 == address(0) && (listing3 != address(0) || listing4 != address(0))) {
                revert("Invalid listing sequence: zero address in middle");
            }
            if (listing2 != address(0)) {
                require(ISSAgent(_agent).getListing(listing2), "Invalid listing2");
            }
        }
        if (numListings >= 3) {
            if (listing3 == address(0) && listing4 != address(0)) {
                revert("Invalid listing sequence: zero address in middle");
            }
            if (listing3 != address(0)) {
                require(ISSAgent(_agent).getListing(listing3), "Invalid listing3");
            }
        }
        if (numListings == 4 && listing4 != address(0)) {
            require(ISSAgent(_agent).getListing(listing4), "Invalid listing4");
        }
    }

    function prepHop(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        address maker
    ) internal view returns (HopPrepData memory) {
        // Prepares hop data, validating inputs and computing route
        require(_routers.length > 0, "No routers set");
        uint256 numListings = 1;
        if (listing2 != address(0)) numListings++;
        if (listing3 != address(0)) numListings++;
        if (listing4 != address(0)) numListings++;
        validateHopRequest(listing1, listing2, listing3, listing4, impactPercent, numListings, maxIterations);
        address[] memory listingAddresses = new address[](numListings);
        uint256[] memory impactPricePercents = new uint256[](numListings);
        listingAddresses[0] = listing1;
        impactPricePercents[0] = impactPercent;
        if (numListings >= 2) {
            listingAddresses[1] = listing2;
            impactPricePercents[1] = impactPercent;
        }
        if (numListings >= 3) {
            listingAddresses[2] = listing3;
            impactPricePercents[2] = impactPercent;
        }
        if (numListings == 4) {
            listingAddresses[3] = listing4;
            impactPricePercents[3] = impactPercent;
        }
        uint256 hopId = nextHopId;
        (uint256[] memory indices, bool[] memory isBuy) = computeRoute(listingAddresses, startToken, endToken);
        return HopPrepData({
            hopId: hopId,
            indices: indices,
            isBuy: isBuy,
            currentToken: startToken,
            principal: msg.value > 0 ? msg.value : impactPercent,
            maker: maker
        });
    }
}