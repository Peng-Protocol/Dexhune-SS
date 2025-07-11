// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.3

// Interface for Multihopper contract, facilitating multi-step token swaps across up to four listings.
interface IMultihopper {
    // Struct for router information, used in router management functions.
    struct RouterInfo {
        address router; // Router contract address (e.g., SSRouter, SSCrossDriver, SSIsolatedDriver).
        uint8 routerType; // Router type: 1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver.
    }

    // Struct for hop order details, returned by getHopOrderDetails.
    struct HopOrderDetails {
        uint256 pending; // Pending amount in input token (normalized).
        uint256 filled; // Filled amount in input token (normalized).
        uint8 status; // Order status: 1 = active, 2 = partially filled, 3 = completed.
        uint256 amountSent; // Amount sent in output token (normalized).
        address recipient; // Recipient of output tokens (hop maker or contract).
    }

    // Struct for hop route data, returned by getHopRoute.
    struct HopRouteData {
        address[] listings; // Ordered list of listing addresses in the hop route.
        bool[] isBuy; // Buy/sell flags for each listing (true = buy, false = sell).
    }

    // Struct for stalled hop data, returned by getHopDetails.
    struct StalledHop {
        uint8 stage; // Current stage of the hop (index in route).
        address currentListing; // Current listing being processed.
        uint256 orderID; // Order ID for the current listing.
        uint256 minPrice; // Minimum price limit for sell orders (normalized).
        uint256 maxPrice; // Maximum price limit for buy orders (normalized).
        address hopMaker; // Address that initiated the hop.
        address[] remainingListings; // Remaining listings in the route.
        uint256 principalAmount; // Current principal amount (normalized).
        address startToken; // Starting token for the hop.
        address endToken; // Ending token for the hop.
        uint8 settleType; // Settlement type: 0 = market, 1 = liquid.
        uint8 hopStatus; // Hop status: 1 = stalled, 2 = completed/canceled.
        uint256 maxIterations; // Maximum iterations for settlement per step.
    }

    // Adds or updates a router in the internal router list.
    // @param router Address of the router contract.
    // @param routerType Type of router (1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver).
    // @dev Restricted to owner, emits RouterAdded event, reverts on invalid router or type.
    function addRouter(address router, uint8 routerType) external;

    // Removes a router from the internal router list using pop-and-swap.
    // @param router Address of the router to remove.
    // @dev Restricted to owner, emits RouterRemoved event, reverts if router not found.
    function removeRouter(address router) external;

    // Returns the list of registered routers.
    // @return Array of RouterInfo structs containing router addresses and types.
    // @dev View function, no state changes.
    function getRouters() external view returns (RouterInfo[] memory);

    // Sets the ISSAgent contract address for listing validation.
    // @param agent Address of the ISSAgent contract.
    // @dev Restricted to owner, emits AgentSet event, reverts if agent is zero address.
    function setAgent(address agent) external;

    // Returns the current ISSAgent address.
    // @return Address of the ISSAgent contract.
    // @dev View function, no state changes.
    function agentView() external view returns (address);

    // Returns the status of a specific hop.
    // @param hopId ID of the hop to query.
    // @return Hop status (1 = stalled, 2 = completed/canceled).
    // @dev View function, accesses hopID mapping.
    function hopStatusView(uint256 hopId) external view returns (uint8);

    // Returns the full details of a hop.
    // @param hopId ID of the hop to query.
    // @return StalledHop struct containing hop details (stage, tokens, status, etc.).
    // @dev View function, accesses hopID mapping.
    function getHopDetails(uint256 hopId) external view returns (StalledHop memory);

    // Returns the list of hop IDs for a user.
    // @param user Address of the user to query.
    // @return Array of hop IDs associated with the user.
    // @dev View function, accesses hopsByAddress mapping.
    function getUserHops(address user) external view returns (uint256[] memory);

    // Returns the total number of hops created.
    // @return Total count of hops in the system.
    // @dev View function, accesses totalHops array.
    function getTotalHopsCount() external view returns (uint256);

    // Returns the number of active (stalled) hops for a user.
    // @param user Address of the user to query.
    // @return Count of active hops for the user.
    // @dev View function, iterates hopsByAddress with status checks.
    function getActiveHopsCount(address user) external view returns (uint256);

    // Returns the total number of pending hops across all users.
    // @param maxIterations Maximum number of hops to check to prevent gas limit issues.
    // @return Count of pending hops globally.
    // @dev View function, iterates totalHops with status checks, reverts if maxIterations is 0.
    function getTotalPendingHopsCount(uint256 maxIterations) external view returns (uint256);

    // Returns order details for the current order of a hop.
    // @param hopId ID of the hop to query.
    // @return HopOrderDetails struct with order information (pending, filled, status, etc.).
    // @dev View function, queries ISSListing for order status.
    function getHopOrderDetails(uint256 hopId) external view returns (HopOrderDetails memory);

    // Returns the route details for a hop.
    // @param hopId ID of the hop to query.
    // @return HopRouteData struct with ordered listing addresses and buy/sell flags.
    // @dev View function, queries hopID and ISSListing for route data.
    function getHopRoute(uint256 hopId) external view returns (HopRouteData memory);

    // Returns the total pending amount in a specific token for a user's stalled hops.
    // @param user Address of the user to query.
    // @param token Address of the token to check (address(0) for native currency).
    // @return Total pending amount in the specified token (normalized).
    // @dev View function, iterates hopsByAddress and queries order status.
    function getUserPendingVolume(address user, address token) external view returns (uint256);

    // Returns the contract's balance for a specific token or native currency.
    // @param token Address of the token to check (address(0) for native currency).
    // @return Balance of the specified token or native currency.
    // @dev View function, queries IERC20.balanceOf or native balance.
    function getContractBalance(address token) external view returns (uint256);

    // Initiates a multi-step token swap across up to four listings.
    // @param listing1 First listing contract address (required).
    // @param listing2 Second listing contract address (address(0) if unused).
    // @param listing3 Third listing contract address (address(0) if unused).
    // @param listing4 Fourth listing contract address (address(0) if unused).
    // @param impactPercent Max price impact for all listings (scaled to 1000, e.g., 500 = 5%).
    // @param startToken Starting token address for the hop.
    // @param endToken Ending token address for the hop.
    // @param settleType Settlement type (0 = market, 1 = liquid).
    // @param maxIterations Maximum settlement iterations per step, stored in StalledHop.
    // @param maker Address of the hop initiator (defaults to msg.sender if address(0)).
    // @dev Payable for native currency, protected by nonReentrant and onlyValidListing, emits HopStarted.
    function hop(
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
    ) external payable;

    // Processes all stalled hops globally, up to maxIterations.
    // @param maxIterations Maximum number of hops to process.
    // @dev Protected by nonReentrant, emits StallsPrepared, StallsExecuted, HopContinued.
    function executeHops(uint256 maxIterations) external;

    // Continues stalled hops for the caller, up to maxIterations.
    // @param maxIterations Maximum number of hops to process, separate from StalledHop.maxIterations.
    // @dev Protected by nonReentrant, emits HopContinued, StallsPrepared, StallsExecuted.
    function continueHop(uint256 maxIterations) external;

    // Cancels a specific hop, refunding pending, filled, or amountSent amounts.
    // @param hopId ID of the hop to cancel.
    // @dev Protected by nonReentrant, refunds via IERC20.transferFrom with balance checks, tracks actual refunded amount in CancelPrepData.refundedPending, emits HopCanceled.
    function cancelHop(uint256 hopId) external;

    // Cancels all stalled hops for the caller, up to maxIterations.
    // @param maxIterations Maximum number of hops to cancel.
    // @dev Protected by nonReentrant, refunds as in cancelHop, emits AllHopsCanceled.
    function cancelAll(uint256 maxIterations) external;
}