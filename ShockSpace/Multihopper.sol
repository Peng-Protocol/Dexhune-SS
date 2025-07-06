// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.41
// Change Log:
// - 2025-07-06: Updated from v0.0.40.
// - Restructured `_cancelHop` to address `Stack too deep` error by forming a call tree for helper functions.
// - Modified `_prepCancelHopBuy` and `_prepCancelHopSell` to call `_prepClearHopOrder` and populate `CancelPrepData` with order details.
// - Updated `_executeClearHopOrder` to accept a single `CancelPrepData` struct, reducing parameters passed from `_cancelHop`.
// - Ensured `_cancelHop` only calls `_prepCancelHopBuy` or `_prepCancelHopSell` and `_finalizeCancel`, minimizing local variables.
// - Retained v0.0.40 changes: Split `_clearHopOrder` into `_prepClearHopOrder` and `_executeClearHopOrder`.
// - Retained v0.0.39 fixes: Added `hopId` parameter to `_handlePending` and `_handleBalance`, corrected `amount-sent` typo in `ISSListing.getSellOrderAmounts`.
// - Retained v0.0.38 changes: Added `maker` parameter to `hop`, checked allowances in `_createHopOrder`, used `maker` in `executeHopSteps`, `initializeHopData`, and cancellation functions.
// - Cross-checked for naming conflicts, reserved keywords, and compiler errors; maintained compatibility with Solidity ^0.8.2, SSRouter v0.0.61, and HopPartial v0.0.58.
// - Previous changes from v0.0.37 and earlier retained (e.g., `getTotalPendingHopsCount`, struct optimizations, etc.).

import "./imports/Ownable.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/SafeERC20.sol";

interface ISSListing {
    struct UpdateType {
        string field;
        uint256 value;
    }

    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function listingPriceView() external view returns (uint256);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getNextOrderId() external view returns (uint256);
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipient, uint8 status);
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipient, uint8 status);
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    function transact(address caller, address tokenAddress, uint256 amount, address recipient) external;
    function update(UpdateType[] memory updates) external;
}

interface ISSRouter {
    function settleBuyOrders(address listingAddress, uint256 maxIterations) external;
    function settleSellOrders(address listingAddress, uint256 maxIterations) external;
    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external;
    function settleSellLiquid(address listingAddress, uint256 maxIterations) external;
}

interface ISSAgent {
    function getListing(address listing) external view returns (bool);
}

contract Multihopper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct RouterInfo {
        address router; // Router contract address
        uint8 routerType; // 1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver
    }

    struct HopUpdateType {
        string field;
        uint256 value;
    }

    struct HopRequest {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents;
        address startToken;
        address endToken;
        uint8 settleType;
        uint256 maxIterations;
    }

    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 orderID;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus;
        uint256 maxIterations;
    }

    struct StallData {
        uint256 hopId;
        address listing;
        uint256 orderId;
        bool isBuy;
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 amountSent;
        address hopMaker;
    }

    struct HopPrepData {
        uint256 hopId;
        uint256[] indices;
        bool[] isBuy;
        address currentToken;
        uint256 principal;
        address maker;
    }

    struct HopExecutionData {
        address listing;
        bool isBuy; // Tracks buy/sell order type
        address recipient;
        uint256 priceLimit;
        uint256 principal;
        address inputToken;
        uint8 settleType;
        uint256 maxIterations;
        HopUpdateType[] updates;
    }

    struct StallExecutionData {
        address listing;
        bool isBuy;
        address recipient;
        uint256 priceLimit;
        uint256 principal;
        uint8 settleType;
        uint256 maxIterations;
        HopUpdateType[] updates;
    }

    struct CancelPrepData {
        uint256 hopId;
        address listing;
        bool isBuy;
        address outputToken;
        address inputToken;
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 receivedAmount;
        address recipient;
    }

    struct CancelBalanceData {
        address token;
        uint256 balanceBefore;
        uint256 balanceAfter;
    }

    struct OrderUpdateData {
        address listing;
        address recipient;
        uint256 inputAmount;
        uint256 priceLimit;
        address inputToken;
    }

    struct HopExecutionParams {
        address[] listingAddresses; // Array of listing addresses (up to 4)
        uint256[] impactPricePercents; // Array of impact percents for each listing
        address startToken; // Starting token for the hop
        address endToken; // Ending token for the last hop
        uint8 settleType; // Settlement type (0 = market, 1 = liquid)
        uint256 maxIterations; // Maximum iterations for settlement
        uint256 numListings; // Number of listings in the route
    }

    struct OrderParams {
        address listing; // Listing contract address
        uint256 principal; // Input amount for the order
        uint256 impactPercent; // Price impact percentage (scaled to 1000)
        uint256 index; // Current index in the hop route
        uint256 numListings; // Total number of listings in the route
        uint256 maxIterations; // Maximum settlement iterations
        uint8 settleType; // Settlement type (0 = market, 1 = liquid)
    }

    struct HopRouteData {
        address[] listings; // Ordered list of listing addresses
        bool[] isBuy; // Buy/sell flags for each listing
    }

    struct HopOrderDetails {
        uint256 pending; // Pending amount in input token
        uint256 filled; // Filled amount in input token
        uint8 status; // Order status (1 = active, 2 = partially filled, 3 = completed)
        uint256 amountSent; // Amount sent in output token
        address recipient; // Recipient of the output tokens
    }

    RouterInfo[] private _routers; // Hidden array of router info
    address private _agent; // Hidden ISSAgent address for listing validation
    mapping(uint256 => StalledHop) private hopID; // Hidden hop storage
    mapping(address => uint256[]) private hopsByAddress; // Hidden user hop list
    uint256[] private totalHops; // Hidden global hop list
    uint256 private nextHopId; // Hidden hop ID counter

    event HopStarted(uint256 indexed hopId, address indexed maker, uint256 numListings);
    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event HopCanceled(uint256 indexed hopId);
    event AllHopsCanceled(address indexed maker, uint256 count);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);
    event RouterAdded(address indexed router, uint8 routerType);
    event RouterRemoved(address indexed router);
    event AgentSet(address indexed agent);

    modifier onlyValidListing(address listingAddress) {
        require(_agent != address(0), "Agent not set");
        require(listingAddress == address(0) || ISSAgent(_agent).getListing(listingAddress), "Invalid listing");
        _;
    }

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
        // Verifies token transfer success by checking balance changes
        uint256 balanceBefore = token == address(0) ? address(to).balance : IERC20(token).balanceOf(to);
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransferFrom(from, to, amount);
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

    function _createHopOrder(OrderUpdateData memory orderData, address sender) internal returns (uint256 orderId) {
        // Creates a new order on the listing with specified parameters, checks allowance if sender != recipient
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = denormalizeForToken(orderData.inputAmount, orderData.inputToken);
        if (orderData.inputToken != address(0)) {
            if (sender != orderData.recipient) {
                uint256 allowance = IERC20(orderData.inputToken).allowance(sender, address(this));
                require(allowance >= rawAmount, "Insufficient allowance");
            }
            IERC20(orderData.inputToken).safeTransferFrom(sender, address(this), rawAmount);
            IERC20(orderData.inputToken).safeApprove(orderData.listing, rawAmount);
        }
        _checkTransfer(orderData.inputToken, address(this), orderData.listing, rawAmount);
        HopUpdateType[] memory hopUpdates = new HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, "buyAmount", orderData.inputAmount); // Placeholder, updated in computeBuy/SellSpecificParams
        setOrderPrice(hopUpdates, 2, "buyPrice", orderData.priceLimit); // Placeholder, updated in computeBuy/SellSpecificParams
        setOrderRecipient(hopUpdates, 3, orderData.recipient);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({
                field: hopUpdates[i].field,
                value: hopUpdates[i].value
            });
        }
        try listingContract.update(updates) {
            // Success
        } catch {
            revert("Order creation failed");
        }
    }

    function addRouter(address router, uint8 routerType) external onlyOwner {
        // Adds or updates a router in _routers, ensuring no duplicate addresses with different types
        require(router != address(0), "Invalid router address");
        require(routerType >= 1 && routerType <= 3, "Invalid router type");
        for (uint256 i = 0; i < _routers.length; i++) {
            if (_routers[i].routerType == routerType) {
                for (uint256 j = 0; j < _routers.length; j++) {
                    if (_routers[j].router == router && _routers[j].routerType != routerType) {
                        revert("Router address used for different type");
                    }
                }
                _routers[i].router = router;
                emit RouterAdded(router, routerType);
                return;
            }
        }
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i].router != router, "Router already added");
        }
        _routers.push(RouterInfo({ router: router, routerType: routerType }));
        emit RouterAdded(router, routerType);
    }

    function removeRouter(address router) external onlyOwner {
        // Removes a router from _routers using pop-and-swap
        for (uint256 i = 0; i < _routers.length; i++) {
            if (_routers[i].router == router) {
                _routers[i] = _routers[_routers.length - 1];
                _routers.pop();
                emit RouterRemoved(router);
                return;
            }
        }
        revert("Router not found");
    }

    function getRouters() public view returns (RouterInfo[] memory) {
        // Returns the array of registered routers
        return _routers;
    }

    function setAgent(address agent) external onlyOwner {
        // Sets the ISSAgent contract address for listing validation
        require(agent != address(0), "Invalid agent address");
        _agent = agent;
        emit AgentSet(agent);
    }

    function agentView() public view returns (address) {
        // Returns the current ISSAgent address
        return _agent;
    }

    function hopStatusView(uint256 hopId) public view returns (uint8) {
        // Returns the status of a specific hop
        return hopID[hopId].hopStatus;
    }

    function getHopDetails(uint256 hopId) public view returns (StalledHop memory) {
        // Returns the full StalledHop struct for a given hopId for analytics
        return hopID[hopId];
    }

    function getUserHops(address user) public view returns (uint256[] memory) {
        // Returns the array of hop IDs for a given user
        return hopsByAddress[user];
    }

    function getTotalHopsCount() public view returns (uint256) {
        // Returns the total number of hops ever created
        return totalHops.length;
    }

    function getActiveHopsCount(address user) public view returns (uint256) {
        // Returns the count of stalled hops for a given user
        uint256 count = 0;
        uint256[] memory userHops = hopsByAddress[user];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (hopID[userHops[i]].hopStatus == 1) {
                count++;
            }
        }
        return count;
    }

    function getTotalPendingHopsCount(uint256 maxIterations) public view returns (uint256) {
        // Returns the total number of pending hops across all users, limited by maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 count = 0;
        for (uint256 i = 0; i < totalHops.length && i < maxIterations; i++) {
            if (hopID[totalHops[i]].hopStatus == 1) {
                count++;
            }
        }
        return count;
    }

    function getHopOrderDetails(uint256 hopId) public view returns (HopOrderDetails memory) {
        // Returns order details for the current order of a hop
        StalledHop memory stalledHop = hopID[hopId];
        (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
            stalledHop.currentListing,
            stalledHop.orderID,
            stalledHop.maxPrice > 0
        );
        (, address recipient, ) = stalledHop.maxPrice > 0
            ? ISSListing(stalledHop.currentListing).getBuyOrderCore(stalledHop.orderID)
            : ISSListing(stalledHop.currentListing).getSellOrderCore(stalledHop.orderID);
        return HopOrderDetails({
            pending: pending,
            filled: filled,
            status: status,
            amountSent: amountSent,
            recipient: recipient
        });
    }

    function getHopRoute(uint256 hopId) public view returns (HopRouteData memory) {
        // Returns the ordered list of listings and buy/sell flags for a hop
        StalledHop memory stalledHop = hopID[hopId];
        address[] memory listingAddresses = new address[](stalledHop.remainingListings.length + 1);
        bool[] memory isBuy = new bool[](stalledHop.remainingListings.length + 1);
        listingAddresses[0] = stalledHop.currentListing;
        isBuy[0] = stalledHop.maxPrice > 0;
        for (uint256 i = 0; i < stalledHop.remainingListings.length; i++) {
            listingAddresses[i + 1] = stalledHop.remainingListings[i];
            ISSListing listing = ISSListing(stalledHop.remainingListings[i]);
            isBuy[i + 1] = stalledHop.endToken == listing.tokenA();
        }
        return HopRouteData({
            listings: listingAddresses,
            isBuy: isBuy
        });
    }

    function getUserPendingVolume(address user, address token) public view returns (uint256) {
        // Returns total pending amount in a specified token across user's stalled hops
        uint256 totalPending = 0;
        uint256[] memory userHops = hopsByAddress[user];
        for (uint256 i = 0; i < userHops.length; i++) {
            StalledHop memory stalledHop = hopID[userHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            ISSListing listing = ISSListing(stalledHop.currentListing);
            address inputToken = stalledHop.maxPrice > 0 ? listing.tokenB() : listing.tokenA();
            if (inputToken != token) continue;
            (uint256 pending, , , ) = checkOrderStatus(stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0);
            totalPending += pending;
        }
        return totalPending;
    }

    function getContractBalance(address token) public view returns (uint256) {
        // Returns the contract's balance for a specified token or native currency
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
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

    function processHopStep(
        HopExecutionData memory execData,
        address sender
    ) internal returns (bool completed, uint256 orderId, uint256 amountSent) {
        // Processes a single hop step, creating and settling an order
        OrderUpdateData memory orderData = OrderUpdateData({
            listing: execData.listing,
            recipient: execData.recipient,
            inputAmount: normalizeForToken(execData.principal, execData.inputToken),
            priceLimit: execData.priceLimit,
            inputToken: execData.inputToken
        });
        orderId = _createHopOrder(orderData, sender);
        safeSettle(execData.listing, execData.isBuy, execData.settleType, execData.maxIterations);
        (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount) = checkOrderStatus(execData.listing, orderId, execData.isBuy);
        completed = status == 3 && pending == 0;
        amountSent = receivedAmount;
    }

    function executeHopSteps(
        HopExecutionParams memory params,
        HopPrepData memory prepData
    ) internal {
        // Executes hop steps, updating hop status and storage for the specified maker
        StalledHop storage stalledHop = hopID[prepData.hopId];
        uint256 principal = prepData.principal;
        address currentToken = prepData.currentToken;
        address maker = prepData.maker;

        for (uint256 i = 0; i < prepData.indices.length; i++) {
            OrderParams memory orderParams = OrderParams({
                listing: params.listingAddresses[prepData.indices[i]],
                principal: principal,
                impactPercent: params.impactPricePercents[prepData.indices[i]],
                index: i,
                numListings: params.numListings,
                maxIterations: params.maxIterations,
                settleType: params.settleType
            });
            HopExecutionData memory execData = prepData.isBuy[i]
                ? computeBuyOrderParams(orderParams, maker)
                : computeSellOrderParams(orderParams, maker);
            (bool completed, uint256 orderId, uint256 amountSent) = processHopStep(execData, msg.sender);
            if (!completed) {
                stalledHop.orderID = orderId;
                stalledHop.minPrice = execData.isBuy ? 0 : execData.priceLimit;
                stalledHop.maxPrice = execData.isBuy ? execData.priceLimit : 0;
                stalledHop.principalAmount = principal;
                stalledHop.remainingListings = new address[](prepData.indices.length - i - 1);
                for (uint256 j = i + 1; j < prepData.indices.length; j++) {
                    stalledHop.remainingListings[j - i - 1] = params.listingAddresses[prepData.indices[j]];
                }
                hopsByAddress[maker].push(prepData.hopId);
                totalHops.push(prepData.hopId);
                return;
            }
            principal = amountSent;
            currentToken = execData.isBuy ? ISSListing(execData.listing).tokenA() : ISSListing(execData.listing).tokenB();
        }

        stalledHop.hopStatus = 2;
        hopsByAddress[maker].push(prepData.hopId);
        totalHops.push(prepData.hopId);
    }

    function executeHop(
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
    ) internal {
        // Executes a hop by preparing and processing steps
        HopExecutionParams memory params = prepareHopExecution(
            listing1, listing2, listing3, listing4,
            impactPercent, startToken, endToken,
            settleType, maxIterations, prepData
        );
        executeHopSteps(params, prepData);
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

    function hop(
        address listing1, // First listing contract address, must be valid (verified by ISSAgent)
        address listing2, // Second listing contract address, set to address(0) if unused
        address listing3, // Third listing contract address, set to address(0) if unused
        address listing4, // Fourth listing contract address, set to address(0) if unused
        uint256 impactPercent, // Max price impact applied to all listings (scaled to 1000, e.g., 500 = 5%), must be ≤ 1000
        address startToken, // Starting token address (input token for the first hop step)
        address endToken, // Ending token address (output token for the last hop step)
        uint8 settleType, // Settlement type: 0 = market orders, 1 = liquid orders
        uint256 maxIterations, // Maximum settlement iterations per step, must be > 0
        address maker // Maker address for the hop, defaults to msg.sender if address(0)
    ) external payable nonReentrant onlyValidListing(listing1) returns (uint256) {
        // Initiates a multi-step token swap on behalf of maker
        address effectiveMaker = maker == address(0) ? msg.sender : maker;
        HopPrepData memory prepData = prepHop(listing1, listing2, listing3, listing4, impactPercent, startToken, endToken, settleType, maxIterations, effectiveMaker);
        executeHop(listing1, listing2, listing3, listing4, impactPercent, startToken, endToken, settleType, maxIterations, prepData);
        emit HopStarted(prepData.hopId, effectiveMaker, prepData.indices.length);
        nextHopId++;
        return prepData.hopId;
    }

    function prepStalls() internal returns (StallData[] memory) {
        // Prepares stalled hop data for a user
        uint256[] storage userHops = hopsByAddress[msg.sender];
        StallData[] memory stalls = new StallData[](userHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userHops.length && count < 20; i++) {
            StalledHop storage stalledHop = hopID[userHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
                stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0
            );
            stalls[count] = StallData({
                hopId: userHops[i],
                listing: stalledHop.currentListing,
                orderId: stalledHop.orderID,
                isBuy: stalledHop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status,
                amountSent: amountSent,
                hopMaker: stalledHop.hopMaker
            });
            count++;
        }

        StallData[] memory resizedStalls = new StallData[](count);
        for (uint256 i = 0; i < count; i++) {
            resizedStalls[i] = stalls[i];
        }
        emit StallsPrepared(count > 0 ? resizedStalls[0].hopId : 0, count);
        return resizedStalls;
    }

    function prepAllStalls() internal returns (StallData[] memory) {
        // Prepares stalled hop data globally
        StallData[] memory stalls = new StallData[](totalHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < totalHops.length && count < 20; i++) {
            StalledHop storage stalledHop = hopID[totalHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
                stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0
            );
            stalls[count] = StallData({
                hopId: totalHops[i],
                listing: stalledHop.currentListing,
                orderId: stalledHop.orderID,
                isBuy: stalledHop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status,
                amountSent: amountSent,
                hopMaker: stalledHop.hopMaker
            });
            count++;
        }

        StallData[] memory resizedStalls = new StallData[](count);
        for (uint256 i = 0; i < count; i++) {
            resizedStalls[i] = stalls[i];
        }
        emit StallsPrepared(count > 0 ? resizedStalls[0].hopId : 0, count);
        return resizedStalls;
    }

    function processStallStep(
        StallExecutionData memory execData,
        address startToken,
        address sender
    ) internal returns (bool completed, uint256 orderId, uint256 amountSent) {
        // Processes a single stall step, creating and settling an order
        OrderUpdateData memory orderData = OrderUpdateData({
            listing: execData.listing,
            recipient: execData.recipient,
            inputAmount: normalizeForToken(execData.principal, startToken),
            priceLimit: execData.priceLimit,
            inputToken: startToken
        });
        orderId = _createHopOrder(orderData, sender);
        safeSettle(execData.listing, execData.isBuy, execData.settleType, execData.maxIterations);
        (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount) = checkOrderStatus(execData.listing, orderId, execData.isBuy);
        completed = status == 3 && pending == 0;
        amountSent = receivedAmount;
    }

    function executeStalls(StallData[] memory stalls) internal {
        // Executes stalled hops, advancing or completing them
        uint256 count = 0;
        for (uint256 i = 0; i < stalls.length; i++) {
            StalledHop storage stalledHop = hopID[stalls[i].hopId];
            if (stalledHop.hopStatus != 1 || stalls[i].pending > 0 || stalls[i].status != 3) continue;
            count++;
            uint256 nextStage = uint256(stalledHop.stage) + 1;
            if (nextStage >= stalledHop.remainingListings.length + uint256(stalledHop.stage) + 1) {
                stalledHop.hopStatus = 2;
                totalHops.push(stalls[i].hopId);
                emit HopContinued(stalls[i].hopId, uint8(nextStage));
                continue;
            }

            bool isBuy = stalledHop.remainingListings.length > 0 && stalledHop.endToken == ISSListing(stalledHop.remainingListings[0]).tokenA();
            uint256 priceLimit = _validatePriceImpact(stalledHop.remainingListings[0], stalls[i].amountSent, isBuy, 500);
            HopUpdateType[] memory hopUpdates = new HopUpdateType[](4);
            setOrderStatus(hopUpdates, 0);
            setOrderAmount(hopUpdates, 1, isBuy ? "buyAmount" : "sellAmount", normalizeForToken(stalls[i].amountSent, stalledHop.startToken));
            setOrderPrice(hopUpdates, 2, isBuy ? "buyPrice" : "sellPrice", priceLimit);
            setOrderRecipient(hopUpdates, 3, stalledHop.hopMaker);
            ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
            for (uint256 j = 0; j < hopUpdates.length; j++) {
                updates[j] = ISSListing.UpdateType({
                    field: hopUpdates[j].field,
                    value: hopUpdates[j].value
                });
            }
            StallExecutionData memory execData = StallExecutionData({
                listing: stalledHop.remainingListings[0],
                isBuy: isBuy,
                recipient: stalledHop.hopMaker,
                priceLimit: priceLimit,
                principal: stalls[i].amountSent,
                settleType: stalledHop.settleType,
                maxIterations: stalledHop.maxIterations,
                updates: hopUpdates
            });

            (bool completed, uint256 orderId, uint256 amountSent) = processStallStep(execData, stalledHop.startToken, stalledHop.hopMaker);
            if (!completed) {
                stalledHop.currentListing = execData.listing;
                stalledHop.orderID = orderId;
                stalledHop.stage = uint8(nextStage);
                stalledHop.principalAmount = amountSent;
                address[] memory newRemaining = new address[](stalledHop.remainingListings.length - 1);
                for (uint256 j = 1; j < stalledHop.remainingListings.length; j++) {
                    newRemaining[j - 1] = stalledHop.remainingListings[j];
                }
                stalledHop.remainingListings = newRemaining;
            } else {
                stalledHop.hopStatus = 2;
                totalHops.push(stalls[i].hopId);
            }
            emit HopContinued(stalls[i].hopId, uint8(nextStage));

            uint256[] storage userHops = hopsByAddress[stalls[i].hopMaker];
            if (stalledHop.hopStatus == 2) {
                for (uint256 j = userHops.length; j > 0; j--) {
                    if (userHops[j - 1] == stalls[i].hopId) {
                        userHops[j - 1] = userHops[userHops.length - 1];
                        userHops.pop();
                        break;
                    }
                }
            }
        }

        emit StallsExecuted(count > 0 ? stalls[0].hopId : 0, count);
    }

    function executeHops(uint256 maxIterations) external nonReentrant {
        // Processes all stalled hops globally up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 iterations = 0;
        while (iterations < maxIterations) {
            StallData[] memory stalls = prepAllStalls();
            if (stalls.length == 0) break;
            executeStalls(stalls);
            iterations++;
        }
    }

    function continueHop(uint256 maxIterations) external nonReentrant {
        // Continues stalled hops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 iterations = 0;
        while (iterations < maxIterations) {
            StallData[] memory stalls = prepStalls();
            if (stalls.length == 0) break;
            executeStalls(stalls);
            iterations++;
        }
    }

    function _prepClearHopOrder(address listing, uint256 orderId, bool isBuy, uint256 hopId)
        internal view returns (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 amountSent, address tokenIn, address tokenOut)
    {
        // Prepares data for clearing a hop order, checking permissions and retrieving order details
        ISSListing listingContract = ISSListing(listing);
        (maker, recipient, status) = isBuy ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        require(maker == msg.sender, "Only maker can cancel");
        require(status == 1 || status == 2, "Order not cancellable");
        (pending, filled, , amountSent) = checkOrderStatus(listing, orderId, isBuy);
        tokenIn = isBuy ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuy ? listingContract.tokenA() : listingContract.tokenB();
    }

    function _executeClearHopOrder(CancelPrepData memory prepData) internal {
        // Executes cancellation of a hop order, updating status and handling refunds
        ISSListing listingContract = ISSListing(prepData.listing);
        uint256 balanceBefore = prepData.outputToken == address(0) ? address(this).balance : IERC20(prepData.outputToken).balanceOf(address(this));
        HopUpdateType[] memory hopUpdates = new HopUpdateType[](1);
        setOrderStatus(hopUpdates, 0);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({
                field: hopUpdates[i].field,
                value: hopUpdates[i].value
            });
        }
        try listingContract.update(updates) {
            uint256 balanceAfter = prepData.outputToken == address(0) ? address(this).balance : IERC20(prepData.outputToken).balanceOf(address(this));
            CancelBalanceData memory balanceData = CancelBalanceData({
                token: prepData.outputToken,
                balanceBefore: balanceBefore,
                balanceAfter: balanceAfter
            });
            _handleFilledOrSent(prepData.filled, prepData.receivedAmount, prepData.outputToken, prepData.recipient);
            _handlePending(prepData.pending, prepData.inputToken, prepData.hopId);
            _handleBalance(balanceData, prepData.hopId);
        } catch {
            revert("Order cancellation failed");
        }
    }

    function _handleFilledOrSent(uint256 filled, uint256 receivedAmount, address outputToken, address recipient) internal {
        // Refunds amountSent (if non-zero and not yet received) or filled to recipient
        if (filled > 0 || receivedAmount > 0) {
            uint256 rawAmount = denormalizeForToken(receivedAmount > 0 ? receivedAmount : filled, outputToken);
            if (outputToken == address(0)) {
                payable(recipient).transfer(rawAmount);
            } else {
                IERC20(outputToken).safeTransfer(recipient, rawAmount);
            }
        }
    }

    function _handlePending(uint256 pending, address inputToken, uint256 hopId) internal {
        // Refunds pending amount in input token to hopMaker
        if (pending > 0) {
            uint256 rawPending = denormalizeForToken(pending, inputToken);
            if (inputToken == address(0)) {
                payable(hopID[hopId].hopMaker).transfer(rawPending);
            } else {
                IERC20(inputToken).safeTransfer(hopID[hopId].hopMaker, rawPending);
            }
        }
    }

    function _handleBalance(CancelBalanceData memory balanceData, uint256 hopId) internal {
        // Refunds any additional balance increase in output token to hopMaker
        if (balanceData.balanceAfter > balanceData.balanceBefore) {
            uint256 amount = balanceData.balanceAfter - balanceData.balanceBefore;
            if (balanceData.token == address(0)) {
                payable(hopID[hopId].hopMaker).transfer(amount);
            } else {
                IERC20(balanceData.token).safeTransfer(hopID[hopId].hopMaker, amount);
            }
        }
    }

    function _getOrderDetails(address listing, uint256 orderId, bool isBuy)
        internal view returns (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount, address recipient)
    {
        // Retrieves detailed order information for cancellation
        ISSListing listingContract = ISSListing(listing);
        (pending, filled, status, receivedAmount) = checkOrderStatus(listing, orderId, isBuy);
        (, recipient, ) = isBuy ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
    }

    function _prepCancelHopBuy(uint256 hopId) internal returns (CancelPrepData memory) {
        // Prepares cancellation data for a buy order and initiates order clearing
        StalledHop storage stalledHop = hopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Not hop maker");
        require(stalledHop.hopStatus == 1, "Hop not stalled");

        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenA();
        address inputToken = listing.tokenB();
        (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 receivedAmount, , ) =
            _prepClearHopOrder(stalledHop.currentListing, stalledHop.orderID, true, hopId);

        CancelPrepData memory prepData = CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: true,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: receivedAmount,
            recipient: recipient
        });

        _executeClearHopOrder(prepData);
        return prepData;
    }

    function _prepCancelHopSell(uint256 hopId) internal returns (CancelPrepData memory) {
        // Prepares cancellation data for a sell order and initiates order clearing
        StalledHop storage stalledHop = hopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Not hop maker");
        require(stalledHop.hopStatus == 1, "Hop not stalled");

        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenB();
        address inputToken = listing.tokenA();
        (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 receivedAmount, , ) =
            _prepClearHopOrder(stalledHop.currentListing, stalledHop.orderID, false, hopId);

        CancelPrepData memory prepData = CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: false,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: receivedAmount,
            recipient: recipient
        });

        _executeClearHopOrder(prepData);
        return prepData;
    }

    function _finalizeCancel(uint256 hopId) internal {
        // Finalizes hop cancellation, updating status and removing from user hops
        StalledHop storage stalledHop = hopID[hopId];
        stalledHop.hopStatus = 2;
        uint256[] storage userHops = hopsByAddress[stalledHop.hopMaker];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] == hopId) {
                userHops[i] = userHops[userHops.length - 1];
                userHops.pop();
                break;
            }
        }
        emit HopCanceled(hopId);
    }

    function _cancelHop(uint256 hopId) internal {
        // Cancels a single hop, refunding appropriate amounts
        StalledHop storage stalledHop = hopID[hopId];
        bool isBuy = stalledHop.maxPrice > 0;
        if (isBuy) {
            _prepCancelHopBuy(hopId);
        } else {
            _prepCancelHopSell(hopId);
        }
        _finalizeCancel(hopId);
    }

    function cancelHop(uint256 hopId) external nonReentrant {
        // External function to cancel a specific hop
        _cancelHop(hopId);
    }

    function cancelAll(uint256 maxIterations) external nonReentrant {
        // Cancels all stalled hops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256[] storage userHops = hopsByAddress[msg.sender];
        uint256 canceled = 0;

        for (uint256 i = userHops.length; i > 0 && canceled < maxIterations; i--) {
            uint256 hopId = userHops[i - 1];
            StalledHop storage stalledHop = hopID[hopId];
            if (stalledHop.hopStatus == 1) {
                _cancelHop(hopId);
                canceled++;
            }
        }
        emit AllHopsCanceled(msg.sender, canceled);
    }
}