// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.44
// Change Log:
// - 2025-07-04: Updated from ChronoHopper v0.0.43.
// - Fixed TypeError in prepareOrderCancellation (line 1224) by correctly destructuring all four return values (pending, filled, status, amountSent) from checkOrderStatus.
// - Maintained fix from v0.0.43: Stack too deep fix in _clearHopOrder with prepareOrderCancellation, executeOrderUpdate, processBalanceData.
// - Maintained fixes from v0.0.42: Stack too deep fix in executeStalls with processSingleStall, computeOrderParams, updateStallData.
// - Maintained fixes from v0.0.41: Added ChronoHopPrepData struct to fix DeclarationError.
// - Maintained fixes from v0.0.40: TypeError in executeStalls and ParserError in StalledChronoHop.
// - Ensured price impact validation at execution time in executeStalls for all hop steps.
// - Ensured compatibility with SSRouter v0.0.61 and HopPartial v0.0.58.
// - Cross-checked for naming conflicts, reserved keywords, and compiler errors.
// - Maintained stack depth mitigation, explicit casting, and fee handling (0.05% in input token).

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

contract ChronoHopper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct RouterInfo {
        address router; // Router contract address
        uint8 routerType; // 1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver
    }

    struct ChronoHopUpdateType {
        string field;
        uint256 value;
    }

    struct ChronoHopRequest {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents;
        address startToken;
        address endToken;
        uint8 settleType;
        uint256 maxIterations;
        uint256 timestamp; // Execution timestamp
    }

    struct StalledChronoHop {
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
        uint256 timestamp; // Execution timestamp
        uint256 feeAmount; // 0.05% fee in input token
        uint256[] impactPricePercents; // Impact percents for each listing
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
        uint256 timestamp; // Execution timestamp
        uint256 feeAmount; // Fee amount
        uint256 impactPercent; // Impact percent for current step
    }

    struct ChronoHopExecutionData {
        address listing;
        bool isBuy; // Tracks buy/sell order type
        address recipient;
        uint256 priceLimit;
        uint256 principal;
        address inputToken;
        uint8 settleType;
        uint256 maxIterations;
        ChronoHopUpdateType[] updates;
        uint256 feeAmount; // Fee amount
        uint256 impactPercent; // Impact percent for current step
    }

    struct StallExecutionData {
        address listing;
        bool isBuy;
        address recipient;
        uint256 priceLimit;
        uint256 principal;
        uint8 settleType;
        uint256 maxIterations;
        ChronoHopUpdateType[] updates;
        uint256 feeAmount; // Fee amount
        uint256 impactPercent; // Impact percent for current step
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
        uint256 feeAmount; // Fee amount
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

    struct ChronoHopExecutionParams {
        address[] listingAddresses; // Array of listing addresses (up to 4)
        uint256[] impactPricePercents; // Array of impact percents for each listing
        address startToken; // Starting token for the hop
        address endToken; // Ending token for the last hop step
        uint8 settleType; // Settlement type (0 = market, 1 = liquid)
        uint256 maxIterations; // Maximum iterations for settlement
        uint256 numListings; // Number of listings in the route
        uint256 timestamp; // Execution timestamp
    }

    struct ChronoHopPrepData {
        uint256 hopId; // Unique identifier for the ChronoHop
        uint256[] indices; // Ordered indices of listings
        bool[] isBuy; // Buy/sell flags for each listing
        address currentToken; // Current token in the hop
        uint256 principal; // Principal amount after fee deduction
        uint256 timestamp; // Execution timestamp
        uint256 feeAmount; // 0.05% fee in input token
        uint256[] impactPricePercents; // Impact percents for each listing
    }

    struct OrderParams {
        address listing; // Listing contract address
        uint256 principal; // Input amount for the order
        uint256 impactPercent; // Price impact percentage (scaled to 1000)
        uint256 index; // Current index in the hop route
        uint256 numListings; // Total number of listings in the route
        uint256 maxIterations; // Maximum settlement iterations
        uint8 settleType; // Settlement type (0 = market, 1 = liquid)
        uint256 timestamp; // Execution timestamp
    }

    struct ChronoHopRouteData {
        address[] listings; // Ordered list of listing addresses
        bool[] isBuy; // Buy/sell flags for each listing
    }

    struct ChronoHopOrderDetails {
        uint256 pending; // Pending amount in input token
        uint256 filled; // Filled amount in input token
        uint8 status; // Order status (1 = active, 2 = partially filled, 3 = completed)
        uint256 amountSent; // Amount sent in output token
        address recipient; // Recipient of the output tokens
        uint256 feeAmount; // Fee amount
    }

    RouterInfo[] private _routers; // Hidden array of router info
    address private _agent; // Hidden ISSAgent address for listing validation
    mapping(uint256 => StalledChronoHop) private chronoHopID; // Hidden hop storage
    mapping(address => uint256[]) private chronoHopsByAddress; // Hidden user hop list
    mapping(uint256 => bool) private isChronoHop; // Flags time-based hops
    uint256[] private totalChronoHops; // Hidden global hop list
    uint256 private nextChronoHopId; // Hidden hop ID counter
    uint256 private constant FEE_BASIS_POINTS = 5; // 0.05% fee (5/10000)

    event ChronoHopStarted(uint256 indexed hopId, address indexed maker, uint256 numListings, uint256 timestamp);
    event ChronoHopContinued(uint256 indexed hopId, uint8 newStage);
    event ChronoHopCanceled(uint256 indexed hopId);
    event AllChronoHopsCanceled(address indexed maker, uint256 count);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);
    event RouterAdded(address indexed router, uint8 routerType);
    event RouterRemoved(address indexed router);
    event AgentSet(address indexed agent);
    event FeePaid(address indexed recipient, address token, uint256 amount);

    modifier onlyValidListing(address listingAddress) {
        require(_agent != address(0), "Agent not set");
        require(listingAddress == address(0) || ISSAgent(_agent).getListing(listingAddress), "Invalid listing");
        _;
    }

    function getTokenDecimals(address token) internal view returns (uint8) {
        // Returns decimals for a token, defaulting to 18 for native currency
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

    function setOrderStatus(ChronoHopUpdateType[] memory updates, uint256 index) internal pure {
        // Sets order status in updates array
        updates[index] = ChronoHopUpdateType({ field: "status", value: uint256(1) });
    }

    function setOrderAmount(ChronoHopUpdateType[] memory updates, uint256 index, string memory orderType, uint256 amount) internal pure {
        // Sets order amount (buyAmount or sellAmount) in updates array
        updates[index] = ChronoHopUpdateType({ field: orderType, value: amount });
    }

    function setOrderPrice(ChronoHopUpdateType[] memory updates, uint256 index, string memory priceType, uint256 priceLimit) internal pure {
        // Sets price limit (buyPrice or sellPrice) in updates array
        updates[index] = ChronoHopUpdateType({ field: priceType, value: priceLimit });
    }

    function setOrderRecipient(ChronoHopUpdateType[] memory updates, uint256 index, address recipient) internal pure {
        // Sets recipient address in updates array
        updates[index] = ChronoHopUpdateType({ field: "recipient", value: uint256(uint160(recipient)) });
    }

    function _createHopOrder(OrderUpdateData memory orderData, address sender) internal returns (uint256 orderId) {
        // Creates a new order on the listing with specified parameters
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = denormalizeForToken(orderData.inputAmount, orderData.inputToken);
        if (orderData.inputToken != address(0)) {
            IERC20(orderData.inputToken).safeTransferFrom(sender, address(this), rawAmount);
            IERC20(orderData.inputToken).safeApprove(orderData.listing, rawAmount);
        }
        _checkTransfer(orderData.inputToken, address(this), orderData.listing, rawAmount);
        ChronoHopUpdateType[] memory hopUpdates = new ChronoHopUpdateType[](4);
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

    function chronoHopStatusView(uint256 hopId) public view returns (uint8) {
        // Returns the status of a specific ChronoHop
        return chronoHopID[hopId].hopStatus;
    }

    function getChronoHopDetails(uint256 hopId) public view returns (StalledChronoHop memory) {
        // Returns the full StalledChronoHop struct for a given hopId for analytics
        return chronoHopID[hopId];
    }

    function getUserChronoHops(address user) public view returns (uint256[] memory) {
        // Returns the array of ChronoHop IDs for a given user
        return chronoHopsByAddress[user];
    }

    function getTotalChronoHopsCount() public view returns (uint256) {
        // Returns the total number of ChronoHops ever created
        return totalChronoHops.length;
    }

    function getActiveChronoHopsCount(address user) public view returns (uint256) {
        // Returns the count of stalled ChronoHops for a given user
        uint256 count = 0;
        uint256[] memory userHops = chronoHopsByAddress[user];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (chronoHopID[userHops[i]].hopStatus == 1) {
                count++;
            }
        }
        return count;
    }

    function getTotalPendingChronoHopsCount(uint256 maxIterations) public view returns (uint256) {
        // Returns the total number of pending ChronoHops across all users, limited by maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 count = 0;
        for (uint256 i = 0; i < totalChronoHops.length && i < maxIterations; i++) {
            if (chronoHopID[totalChronoHops[i]].hopStatus == 1) {
                count++;
            }
        }
        return count;
    }

    function getChronoHopOrderDetails(uint256 hopId) public view returns (ChronoHopOrderDetails memory) {
        // Returns order details for the current order of a ChronoHop
        StalledChronoHop memory stalledHop = chronoHopID[hopId];
        (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
            stalledHop.currentListing,
            stalledHop.orderID,
            stalledHop.maxPrice > 0
        );
        (, address recipient, ) = stalledHop.maxPrice > 0
            ? ISSListing(stalledHop.currentListing).getBuyOrderCore(stalledHop.orderID)
            : ISSListing(stalledHop.currentListing).getSellOrderCore(stalledHop.orderID);
        return ChronoHopOrderDetails({
            pending: pending,
            filled: filled,
            status: status,
            amountSent: amountSent,
            recipient: recipient,
            feeAmount: stalledHop.feeAmount
        });
    }

    function getChronoHopRoute(uint256 hopId) public view returns (ChronoHopRouteData memory) {
        // Returns the ordered list of listings and buy/sell flags for a ChronoHop
        StalledChronoHop memory stalledHop = chronoHopID[hopId];
        address[] memory listingAddresses = new address[](stalledHop.remainingListings.length + 1);
        bool[] memory isBuy = new bool[](stalledHop.remainingListings.length + 1);
        listingAddresses[0] = stalledHop.currentListing;
        isBuy[0] = stalledHop.maxPrice > 0;
        for (uint256 i = 0; i < stalledHop.remainingListings.length; i++) {
            listingAddresses[i + 1] = stalledHop.remainingListings[i];
            ISSListing listing = ISSListing(stalledHop.remainingListings[i]);
            isBuy[i + 1] = stalledHop.endToken == listing.tokenA();
        }
        return ChronoHopRouteData({
            listings: listingAddresses,
            isBuy: isBuy
        });
    }

    function getUserPendingVolume(address user, address token) public view returns (uint256) {
        // Returns total pending amount in a specified token across user's stalled ChronoHops
        uint256 totalPending = 0;
        uint256[] memory userHops = chronoHopsByAddress[user];
        for (uint256 i = 0; i < userHops.length; i++) {
            StalledChronoHop memory stalledHop = chronoHopID[userHops[i]];
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

    function validateChronoHopRequest(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        uint256 numListings,
        uint256 maxIterations,
        uint256 timestamp
    ) internal view {
        // Validates ChronoHop request parameters, allowing address(0) for trailing listings
        require(numListings > 0 && numListings <= 4, "Invalid listing count");
        require(maxIterations > 0, "Invalid maxIterations");
        require(timestamp >= block.timestamp, "Timestamp in past");
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
        internal view returns (ChronoHopExecutionData memory execData)
    {
        // Computes specific parameters for a buy order
        uint256 priceLimit = _validatePriceImpact(params.listing, normalizedAmount, true, params.impactPercent);
        ChronoHopUpdateType[] memory updates = new ChronoHopUpdateType[](4);
        setOrderStatus(updates, 0);
        setOrderAmount(updates, 1, "buyAmount", normalizedAmount);
        setOrderPrice(updates, 2, "buyPrice", priceLimit);
        setOrderRecipient(updates, 3, recipient);
        execData = ChronoHopExecutionData({
            listing: params.listing,
            isBuy: true,
            recipient: recipient,
            priceLimit: priceLimit,
            principal: denormalizeForToken(normalizedAmount, inputToken),
            inputToken: inputToken,
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: updates,
            feeAmount: 0, // Set during hop creation
            impactPercent: params.impactPercent
        });
    }

    function computeSellSpecificParams(OrderParams memory params, address inputToken, uint256 normalizedAmount, address recipient)
        internal view returns (ChronoHopExecutionData memory execData)
    {
        // Computes specific parameters for a sell order
        uint256 priceLimit = _validatePriceImpact(params.listing, normalizedAmount, false, params.impactPercent);
        ChronoHopUpdateType[] memory updates = new ChronoHopUpdateType[](4);
        setOrderStatus(updates, 0);
        setOrderAmount(updates, 1, "sellAmount", normalizedAmount);
        setOrderPrice(updates, 2, "sellPrice", priceLimit);
        setOrderRecipient(updates, 3, recipient);
        execData = ChronoHopExecutionData({
            listing: params.listing,
            isBuy: false,
            recipient: recipient,
            priceLimit: priceLimit,
            principal: denormalizeForToken(normalizedAmount, inputToken),
            inputToken: inputToken,
            settleType: params.settleType,
            maxIterations: params.maxIterations,
            updates: updates,
            feeAmount: 0, // Set during hop creation
            impactPercent: params.impactPercent
        });
    }

    function computeBuyOrderParams(OrderParams memory params) internal view returns (ChronoHopExecutionData memory) {
        // Computes buy order parameters, overriding input token
        ISSListing listingContract = ISSListing(params.listing);
        (address inputToken, uint256 normalizedAmount, address recipient, ) = computeBaseOrderParams(params);
        inputToken = listingContract.tokenB(); // Override for buy order
        return computeBuySpecificParams(params, inputToken, normalizedAmount, recipient);
    }

    function computeSellOrderParams(OrderParams memory params) internal view returns (ChronoHopExecutionData memory) {
        // Computes sell order parameters, overriding input token
        ISSListing listingContract = ISSListing(params.listing);
        (address inputToken, uint256 normalizedAmount, address recipient, ) = computeBaseOrderParams(params);
        inputToken = listingContract.tokenA(); // Override for sell order
        return computeSellSpecificParams(params, inputToken, normalizedAmount, recipient);
    }

    function updateChronoHopListings(
        ChronoHopExecutionParams memory params,
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent
    ) internal pure {
        // Updates ChronoHopExecutionParams with listing addresses and impact percents
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

    function updateChronoHopTokens(
        ChronoHopExecutionParams memory params,
        address startToken,
        address endToken
    ) internal pure {
        // Updates ChronoHopExecutionParams with start and end tokens
        params.startToken = startToken;
        params.endToken = endToken;
    }

    function updateChronoHopSettings(
        ChronoHopExecutionParams memory params,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp
    ) internal pure {
        // Updates ChronoHopExecutionParams with settlement settings and timestamp
        params.settleType = settleType;
        params.maxIterations = maxIterations;
        params.timestamp = timestamp;
    }

    function prepareChronoHopExecution(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp,
        ChronoHopPrepData memory prepData
    ) internal view returns (ChronoHopExecutionParams memory) {
        // Prepares ChronoHop execution parameters and validates inputs
        ChronoHopExecutionParams memory params;
        updateChronoHopListings(params, listing1, listing2, listing3, listing4, impactPercent);
        updateChronoHopTokens(params, startToken, endToken);
        updateChronoHopSettings(params, settleType, maxIterations, timestamp);
        validateChronoHopRequest(listing1, listing2, listing3, listing4, impactPercent, params.numListings, maxIterations, timestamp);
        return params;
    }

    function initializeChronoHopData(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp,
        ChronoHopPrepData memory prepData
    ) internal {
        // Initializes ChronoHop data in chronoHopID mapping
        uint256 numListings = 1;
        if (listing2 != address(0)) numListings++;
        if (listing3 != address(0)) numListings++;
        if (listing4 != address(0)) numListings++;
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
        address[] memory orderedListings = new address[](prepData.indices.length);
        for (uint256 i = 0; i < prepData.indices.length; i++) {
            orderedListings[i] = listingAddresses[prepData.indices[i]];
        }
        chronoHopID[prepData.hopId] = StalledChronoHop({
            stage: 0,
            currentListing: orderedListings[0],
            orderID: 0,
            minPrice: 0,
            maxPrice: 0,
            hopMaker: msg.sender,
            remainingListings: orderedListings,
            principalAmount: prepData.principal,
            startToken: startToken,
            endToken: endToken,
            settleType: settleType,
            hopStatus: 1,
            maxIterations: maxIterations,
            timestamp: timestamp,
            feeAmount: prepData.feeAmount,
            impactPricePercents: prepData.impactPricePercents
        });
        isChronoHop[prepData.hopId] = true;
    }

    function processChronoHopStep(
        ChronoHopExecutionData memory execData,
        address sender
    ) internal returns (bool completed, uint256 orderId, uint256 amountSent) {
        // Processes a single ChronoHop step, creating and settling an order
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
        if (completed && execData.feeAmount > 0) {
            uint256 rawFee = denormalizeForToken(execData.feeAmount, execData.inputToken);
            if (execData.inputToken == address(0)) {
                payable(msg.sender).transfer(rawFee);
            } else {
                IERC20(execData.inputToken).safeTransfer(msg.sender, rawFee);
            }
            emit FeePaid(msg.sender, execData.inputToken, rawFee);
        }
    }

    function executeChronoHopSteps(
        ChronoHopExecutionParams memory params,
        ChronoHopPrepData memory prepData
    ) internal {
        // Stores ChronoHop without executing steps, deferring to executeStalls
        StalledChronoHop storage stalledHop = chronoHopID[prepData.hopId];
        stalledHop.orderID = 0;
        stalledHop.minPrice = 0;
        stalledHop.maxPrice = 0;
        stalledHop.principalAmount = prepData.principal;
        stalledHop.feeAmount = prepData.feeAmount;
        stalledHop.remainingListings = new address[](prepData.indices.length);
        for (uint256 i = 0; i < prepData.indices.length; i++) {
            stalledHop.remainingListings[i] = params.listingAddresses[prepData.indices[i]];
        }
        stalledHop.impactPricePercents = prepData.impactPricePercents;
        chronoHopsByAddress[msg.sender].push(prepData.hopId);
        totalChronoHops.push(prepData.hopId);
    }

    function executeChronoHop(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp,
        ChronoHopPrepData memory prepData
    ) internal {
        // Prepares and stores a ChronoHop, deferring execution to continueHop or executeHops
        ChronoHopExecutionParams memory params = prepareChronoHopExecution(
            listing1, listing2, listing3, listing4,
            impactPercent, startToken, endToken,
            settleType, maxIterations, timestamp, prepData
        );
        executeChronoHopSteps(params, prepData);
    }

    function prepChronoHop(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp
    ) internal view returns (ChronoHopPrepData memory) {
        // Prepares ChronoHop data, validating inputs and computing route
        require(_routers.length > 0, "No routers set");
        uint256 numListings = 1;
        if (listing2 != address(0)) numListings++;
        if (listing3 != address(0)) numListings++;
        if (listing4 != address(0)) numListings++;
        validateChronoHopRequest(listing1, listing2, listing3, listing4, impactPercent, numListings, maxIterations, timestamp);
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
        uint256 hopId = nextChronoHopId;
        (uint256[] memory indices, bool[] memory isBuy) = computeRoute(listingAddresses, startToken, endToken);
        uint256 principal = msg.value > 0 ? msg.value : impactPercent;
        uint256 feeAmount = (principal * FEE_BASIS_POINTS) / 10000; // 0.05% fee
        require(principal > feeAmount, "Principal too low for fee");
        return ChronoHopPrepData({
            hopId: hopId,
            indices: indices,
            isBuy: isBuy,
            currentToken: startToken,
            principal: principal - feeAmount, // Deduct fee from principal
            timestamp: timestamp,
            feeAmount: feeAmount,
            impactPricePercents: impactPricePercents
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
        uint256 timestamp // Execution timestamp, must be >= block.timestamp
    ) external payable nonReentrant onlyValidListing(listing1) {
        // Initiates a time-based multi-step token swap, stalling until timestamp
        ChronoHopPrepData memory prepData = prepChronoHop(
            listing1, listing2, listing3, listing4, impactPercent,
            startToken, endToken, settleType, maxIterations, timestamp
        );
        initializeChronoHopData(
            listing1, listing2, listing3, listing4, impactPercent,
            startToken, endToken, settleType, maxIterations, timestamp, prepData
        );
        executeChronoHop(
            listing1, listing2, listing3, listing4, impactPercent,
            startToken, endToken, settleType, maxIterations, timestamp, prepData
        );
        emit ChronoHopStarted(prepData.hopId, msg.sender, prepData.indices.length, timestamp);
        nextChronoHopId++;
    }

    function prepStalls() internal returns (StallData[] memory) {
        // Prepares stalled ChronoHop data for a user
        uint256[] storage userHops = chronoHopsByAddress[msg.sender];
        StallData[] memory stalls = new StallData[](userHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userHops.length && count < 20; i++) {
            StalledChronoHop storage stalledHop = chronoHopID[userHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            if (isChronoHop[userHops[i]] && block.timestamp < stalledHop.timestamp) continue; // Skip if timestamp not reached
            (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount) = stalledHop.orderID == 0
                ? (0, 0, 0, 0)
                : checkOrderStatus(stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0);
            stalls[count] = StallData({
                hopId: userHops[i],
                listing: stalledHop.currentListing,
                orderId: stalledHop.orderID,
                isBuy: stalledHop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status,
                amountSent: receivedAmount,
                hopMaker: stalledHop.hopMaker,
                timestamp: stalledHop.timestamp,
                feeAmount: stalledHop.feeAmount,
                impactPercent: stalledHop.impactPricePercents[stalledHop.stage]
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
        // Prepares stalled ChronoHop data globally
        StallData[] memory stalls = new StallData[](totalChronoHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < totalChronoHops.length && count < 20; i++) {
            StalledChronoHop storage stalledHop = chronoHopID[totalChronoHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            if (isChronoHop[totalChronoHops[i]] && block.timestamp < stalledHop.timestamp) continue; // Skip if timestamp not reached
            (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount) = stalledHop.orderID == 0
                ? (0, 0, 0, 0)
                : checkOrderStatus(stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0);
            stalls[count] = StallData({
                hopId: totalChronoHops[i],
                listing: stalledHop.currentListing,
                orderId: stalledHop.orderID,
                isBuy: stalledHop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status,
                amountSent: receivedAmount,
                hopMaker: stalledHop.hopMaker,
                timestamp: stalledHop.timestamp,
                feeAmount: stalledHop.feeAmount,
                impactPercent: stalledHop.impactPricePercents[stalledHop.stage]
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
        if (completed && execData.feeAmount > 0) {
            uint256 rawFee = denormalizeForToken(execData.feeAmount, startToken);
            if (startToken == address(0)) {
                payable(msg.sender).transfer(rawFee);
            } else {
                IERC20(startToken).safeTransfer(msg.sender, rawFee);
            }
            emit FeePaid(msg.sender, startToken, rawFee);
        }
    }

    function computeOrderParams(
        StalledChronoHop storage stalledHop,
        StallData memory stall,
        uint256 nextStage
    ) internal view returns (OrderParams memory, address inputToken, address recipient) {
        // Computes order parameters for a stall step
        uint256 principal = stall.orderId == 0 ? stalledHop.principalAmount : stall.amountSent;
        bool isBuy = stall.orderId == 0
            ? (stalledHop.endToken == ISSListing(stalledHop.currentListing).tokenA())
            : stall.isBuy;
        inputToken = isBuy ? ISSListing(stalledHop.currentListing).tokenB() : ISSListing(stalledHop.currentListing).tokenA();
        recipient = nextStage >= stalledHop.remainingListings.length ? stalledHop.hopMaker : address(this);
        OrderParams memory orderParams = OrderParams({
            listing: stalledHop.currentListing,
            principal: principal,
            impactPercent: stall.impactPercent,
            index: nextStage - 1,
            numListings: stalledHop.remainingListings.length,
            maxIterations: stalledHop.maxIterations,
            settleType: stalledHop.settleType,
            timestamp: stalledHop.timestamp
        });
        return (orderParams, inputToken, recipient);
    }

    function updateStallData(
        StalledChronoHop storage stalledHop,
        StallExecutionData memory execData,
        uint256 nextStage,
        bool completed,
        uint256 orderId,
        uint256 amountSent
    ) internal {
        // Updates stalled hop data after processing a step
        if (!completed) {
            stalledHop.currentListing = execData.listing;
            stalledHop.orderID = orderId;
            stalledHop.stage = uint8(nextStage);
            stalledHop.principalAmount = amountSent;
            stalledHop.feeAmount = execData.feeAmount;
            stalledHop.minPrice = execData.isBuy ? 0 : execData.priceLimit;
            stalledHop.maxPrice = execData.isBuy ? execData.priceLimit : 0;
            address[] memory newRemaining = new address[](stalledHop.remainingListings.length > 0 ? stalledHop.remainingListings.length - 1 : 0);
            for (uint256 j = 1; j < stalledHop.remainingListings.length; j++) {
                newRemaining[j - 1] = stalledHop.remainingListings[j];
            }
            stalledHop.remainingListings = newRemaining;
        } else {
            stalledHop.hopStatus = nextStage >= stalledHop.remainingListings.length ? 2 : 1;
            stalledHop.currentListing = stalledHop.remainingListings.length > 0 ? stalledHop.remainingListings[0] : address(0);
            address[] memory newRemaining = new address[](stalledHop.remainingListings.length > 0 ? stalledHop.remainingListings.length - 1 : 0);
            for (uint256 j = 1; j < stalledHop.remainingListings.length; j++) {
                newRemaining[j - 1] = stalledHop.remainingListings[j];
            }
            stalledHop.remainingListings = newRemaining;
            stalledHop.principalAmount = amountSent;
            stalledHop.stage = uint8(nextStage);
        }
    }

    function processSingleStall(StallData memory stall, uint256[] storage userHops) internal {
        // Processes a single stall, advancing or completing it
        StalledChronoHop storage stalledHop = chronoHopID[stall.hopId];
        if (stalledHop.hopStatus != 1) return;
        uint256 nextStage = uint256(stalledHop.stage) + 1;

        (OrderParams memory orderParams, address inputToken, address recipient) = computeOrderParams(stalledHop, stall, nextStage);
        ChronoHopExecutionData memory chronoExecData = orderParams.index < orderParams.numListings
            ? (orderParams.index == orderParams.numListings - 1
                ? computeBuyOrderParams(orderParams)
                : computeSellOrderParams(orderParams))
            : computeBuyOrderParams(orderParams);

        StallExecutionData memory execData = StallExecutionData({
            listing: chronoExecData.listing,
            isBuy: chronoExecData.isBuy,
            recipient: recipient,
            priceLimit: chronoExecData.priceLimit,
            principal: chronoExecData.principal,
            settleType: chronoExecData.settleType,
            maxIterations: chronoExecData.maxIterations,
            updates: chronoExecData.updates,
            feeAmount: stall.feeAmount,
            impactPercent: chronoExecData.impactPercent
        });

        (bool completed, uint256 orderId, uint256 amountSent) = processStallStep(execData, inputToken, stalledHop.hopMaker);
        updateStallData(stalledHop, execData, nextStage, completed, orderId, amountSent);
        emit ChronoHopContinued(stall.hopId, uint8(nextStage));

        if (stalledHop.hopStatus == 2) {
            for (uint256 j = userHops.length; j > 0; j--) {
                if (userHops[j - 1] == stall.hopId) {
                    userHops[j - 1] = userHops[userHops.length - 1];
                    userHops.pop();
                    break;
                }
            }
        }
    }

    function executeStalls(StallData[] memory stalls) internal {
        // Executes stalled ChronoHops, advancing or completing them
        uint256 count = 0;
        for (uint256 i = 0; i < stalls.length; i++) {
            uint256[] storage userHops = chronoHopsByAddress[stalls[i].hopMaker];
            processSingleStall(stalls[i], userHops);
            if (chronoHopID[stalls[i].hopId].hopStatus == 1) count++;
        }
        emit StallsExecuted(count > 0 ? stalls[0].hopId : 0, count);
    }

    function executeHops(uint256 maxIterations) external nonReentrant {
        // Processes all stalled ChronoHops globally up to maxIterations
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
        // Continues stalled ChronoHops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 iterations = 0;
        while (iterations < maxIterations) {
            StallData[] memory stalls = prepStalls();
            if (stalls.length == 0) break;
            executeStalls(stalls);
            iterations++;
        }
    }

    function prepareOrderCancellation(address listing, uint256 orderId, bool isBuy)
        internal view returns (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 amountSent, address tokenIn, address tokenOut)
    {
        // Prepares order cancellation data, retrieving order details and token addresses
        ISSListing listingContract = ISSListing(listing);
        (maker, recipient, status) = isBuy ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        (pending, filled, status, amountSent) = checkOrderStatus(listing, orderId, isBuy);
        tokenIn = isBuy ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuy ? listingContract.tokenA() : listingContract.tokenB();
    }

    function executeOrderUpdate(address listing, bool isBuy) internal returns (CancelBalanceData memory) {
        // Executes order update to cancel the order, tracking balance changes
        ISSListing listingContract = ISSListing(listing);
        address tokenOut = isBuy ? listingContract.tokenA() : listingContract.tokenB();
        uint256 balanceBefore = tokenOut == address(0) ? address(this).balance : IERC20(tokenOut).balanceOf(address(this));
        ChronoHopUpdateType[] memory hopUpdates = new ChronoHopUpdateType[](1);
        setOrderStatus(hopUpdates, 0);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({
                field: hopUpdates[i].field,
                value: hopUpdates[i].value
            });
        }
        try listingContract.update(updates) {
            uint256 balanceAfter = tokenOut == address(0) ? address(this).balance : IERC20(tokenOut).balanceOf(address(this));
            return CancelBalanceData({
                token: tokenOut,
                balanceBefore: balanceBefore,
                balanceAfter: balanceAfter
            });
        } catch {
            revert("Order cancellation failed");
        }
    }

    function processBalanceData(CancelBalanceData memory balanceData) internal {
        // Refunds any additional balance increase in output token
        if (balanceData.balanceAfter > balanceData.balanceBefore) {
            uint256 amount = balanceData.balanceAfter - balanceData.balanceBefore;
            if (balanceData.token == address(0)) {
                payable(msg.sender).transfer(amount);
            } else {
                IERC20(balanceData.token).safeTransfer(msg.sender, amount);
            }
        }
    }

    function _clearHopOrder(address listing, uint256 orderId, bool isBuy) internal {
        // Clears a ChronoHop order, refunding appropriate amounts
        (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 amountSent, address tokenIn, address tokenOut) =
            prepareOrderCancellation(listing, orderId, isBuy);
        require(maker == msg.sender, "Only maker can cancel");
        require(status == 1 || status == 2, "Order not cancellable");
        CancelBalanceData memory balanceData = executeOrderUpdate(listing, isBuy);
        _handleFilledOrSent(filled, amountSent, tokenOut, recipient);
        _handlePending(pending, tokenIn, listing, orderId);
        processBalanceData(balanceData);
    }

    function _handleFilledOrSent(uint256 filled, uint256 receivedAmount, address outputToken, address recipient) internal {
        // Refunds amountSent (if non-zero and not yet received) or filled to recipient
        if (filled > 0 || receivedAmount > 0) {
            require(recipient == msg.sender, "Recipient must be hop maker for refund");
            uint256 rawAmount = denormalizeForToken(receivedAmount > 0 ? receivedAmount : filled, outputToken);
            if (outputToken == address(0)) {
                payable(msg.sender).transfer(rawAmount);
            } else {
                IERC20(outputToken).safeTransfer(msg.sender, rawAmount);
            }
        }
    }

    function _handlePending(uint256 pending, address inputToken, address listing, uint256 orderId) internal {
        // Refunds pending amount plus fee in input token to msg.sender
        StalledChronoHop storage stalledHop = chronoHopID[orderId];
        uint256 totalRefund = pending + stalledHop.feeAmount;
        if (totalRefund > 0) {
            uint256 rawPending = denormalizeForToken(totalRefund, inputToken);
            if (inputToken == address(0)) {
                payable(msg.sender).transfer(rawPending);
            } else {
                IERC20(inputToken).safeTransfer(msg.sender, rawPending);
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

    function _prepCancelChronoHopBuy(uint256 hopId) internal returns (CancelPrepData memory) {
        // Prepares cancellation data for a buy order
        StalledChronoHop storage stalledHop = chronoHopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Not hop maker");
        require(stalledHop.hopStatus == 1, "Hop not stalled");

        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenA();
        address inputToken = listing.tokenB();
        (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount, address recipient) = stalledHop.orderID == 0
            ? (0, 0, 0, 0, address(0))
            : _getOrderDetails(stalledHop.currentListing, stalledHop.orderID, true);

        return CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: true,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: receivedAmount,
            recipient: recipient,
            feeAmount: stalledHop.feeAmount
        });
    }

    function _prepCancelChronoHopSell(uint256 hopId) internal returns (CancelPrepData memory) {
        // Prepares cancellation data for a sell order
        StalledChronoHop storage stalledHop = chronoHopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Not hop maker");
        require(stalledHop.hopStatus == 1, "Hop not stalled");

        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenB();
        address inputToken = listing.tokenA();
        (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount, address recipient) = stalledHop.orderID == 0
            ? (0, 0, 0, 0, address(0))
            : _getOrderDetails(stalledHop.currentListing, stalledHop.orderID, false);

        return CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: false,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: receivedAmount,
            recipient: recipient,
            feeAmount: stalledHop.feeAmount
        });
    }

    function _finalizeCancel(uint256 hopId) internal {
        // Finalizes ChronoHop cancellation, updating status and removing from user hops
        StalledChronoHop storage stalledHop = chronoHopID[hopId];
        stalledHop.hopStatus = 2;
        uint256[] storage userHops = chronoHopsByAddress[stalledHop.hopMaker];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] == hopId) {
                userHops[i] = userHops[userHops.length - 1];
                userHops.pop();
                break;
            }
        }
        emit ChronoHopCanceled(hopId);
    }

    function _cancelChronoHop(uint256 hopId) internal {
        // Cancels a single ChronoHop, refunding appropriate amounts
        StalledChronoHop storage stalledHop = chronoHopID[hopId];
        bool isBuy = stalledHop.maxPrice > 0;
        CancelPrepData memory prepData = isBuy ? _prepCancelChronoHopBuy(hopId) : _prepCancelChronoHopSell(hopId);
        if (stalledHop.orderID != 0) {
            _clearHopOrder(prepData.listing, stalledHop.orderID, isBuy);
        } else {
            uint256 totalRefund = prepData.pending + prepData.feeAmount;
            if (totalRefund > 0) {
                uint256 rawPending = denormalizeForToken(totalRefund, prepData.inputToken);
                if (prepData.inputToken == address(0)) {
                    payable(msg.sender).transfer(rawPending);
                } else {
                    IERC20(prepData.inputToken).safeTransfer(msg.sender, rawPending);
                }
            }
        }
        _finalizeCancel(hopId);
    }

    function cancelChronoHop(uint256 hopId) external nonReentrant {
        // External function to cancel a specific ChronoHop
        _cancelChronoHop(hopId);
    }

    function cancelAll(uint256 maxIterations) external nonReentrant {
        // Cancels all stalled ChronoHops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256[] storage userHops = chronoHopsByAddress[msg.sender];
        uint256 canceled = 0;

        for (uint256 i = userHops.length; i > 0 && canceled < maxIterations; i--) {
            uint256 hopId = userHops[i - 1];
            StalledChronoHop storage stalledHop = chronoHopID[hopId];
            if (stalledHop.hopStatus == 1) {
                _cancelChronoHop(hopId);
                canceled++;
            }
        }
        emit AllChronoHopsCanceled(msg.sender, canceled);
    }
}