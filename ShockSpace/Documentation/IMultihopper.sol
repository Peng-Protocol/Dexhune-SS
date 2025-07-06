// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.2

interface IMultihopper {
    // Struct for router information
    struct RouterInfo {
        address router; // Router contract address
        uint8 routerType; // 1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver
    }

    // Struct for hop order details
    struct HopOrderDetails {
        uint256 pending; // Pending amount in input token
        uint256 filled; // Filled amount in input token
        uint8 status; // Order status (1 = active, 2 = partially filled, 3 = completed)
        uint256 amountSent; // Amount sent in output token
        address recipient; // Recipient of the output tokens
    }

    // Struct for hop route data
    struct HopRouteData {
        address[] listings; // Ordered list of listing addresses
        bool[] isBuy; // Buy/sell flags for each listing
    }

    // Struct for stalled hop data
    struct StalledHop {
        uint8 stage; // Current stage of the hop
        address currentListing; // Current listing being processed
        uint256 orderID; // Order ID for the current listing
        uint256 minPrice; // Minimum price limit for sell orders
        uint256 maxPrice; // Maximum price limit for buy orders
        address hopMaker; // Address that initiated the hop
        address[] remainingListings; // Remaining listings in the route
        uint256 principalAmount; // Current principal amount
        address startToken; // Starting token for the hop
        address endToken; // Ending token for the hop
        uint8 settleType; // Settlement type (0 = market, 1 = liquid)
        uint8 hopStatus; // Hop status (1 = active, 2 = completed/canceled)
        uint256 maxIterations; // Maximum iterations for settlement
    }

    // Adds a new router or updates an existing one
    // @param router Address of the router contract
    // @param routerType Type of router (1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver)
    function addRouter(address router, uint8 routerType) external;

    // Removes a router from the list
    // @param router Address of the router to remove
    function removeRouter(address router) external;

    // Returns the list of registered routers
    // @return Array of RouterInfo structs
    function getRouters() external view returns (RouterInfo[] memory);

    // Sets the ISSAgent contract address for listing validation
    // @param agent Address of the ISSAgent contract
    function setAgent(address agent) external;

    // Returns the current ISSAgent address
    // @return Address of the ISSAgent contract
    function agentView() external view returns (address);

    // Returns the status of a specific hop
    // @param hopId ID of the hop to query
    // @return Hop status (1 = active, 2 = completed/canceled)
    function hopStatusView(uint256 hopId) external view returns (uint8);

    // Returns the full details of a hop
    // @param hopId ID of the hop to query
    // @return StalledHop struct containing hop details
    function getHopDetails(uint256 hopId) external view returns (StalledHop memory);

    // Returns the list of hop IDs for a user
    // @param user Address of the user to query
    // @return Array of hop IDs
    function getUserHops(address user) external view returns (uint256[] memory);

    // Returns the total number of hops created
    // @return Total count of hops
    function getTotalHopsCount() external view returns (uint256);

    // Returns the number of active (stalled) hops for a user
    // @param user Address of the user to query
    // @return Count of active hops
    function getActiveHopsCount(address user) external view returns (uint256);

    // Returns the total number of pending hops across all users
    // @param maxIterations Maximum number of hops to check to prevent gas limit issues
    // @return Count of pending hops
    function getTotalPendingHopsCount(uint256 maxIterations) external view returns (uint256);

    // Returns order details for the current order of a hop
    // @param hopId ID of the hop to query
    // @return HopOrderDetails struct with order information
    function getHopOrderDetails(uint256 hopId) external view returns (HopOrderDetails memory);

    // Returns the route details for a hop
    // @param hopId ID of the hop to query
    // @return HopRouteData struct with listing addresses and buy/sell flags
    function getHopRoute(uint256 hopId) external view returns (HopRouteData memory);

    // Returns the total pending amount in a specific token for a user's stalled hops
    // @param user Address of the user to query
    // @param token Address of the token to check
    // @return Total pending amount in the specified token
    function getUserPendingVolume(address user, address token) external view returns (uint256);

    // Returns the contract's balance for a specific token or native currency
    // @param token Address of the token to check (address(0) for native currency)
    // @return Balance of the specified token
    function getContractBalance(address token) external view returns (uint256);

    // Initiates a multi-step token swap
    // @param listing1 First listing contract address (required)
    // @param listing2 Second listing contract address (address(0) if unused)
    // @param listing3 Third listing contract address (address(0) if unused)
    // @param listing4 Fourth listing contract address (address(0) if unused)
    // @param impactPercent Max price impact for all listings (scaled to 1000, e.g., 500 = 5%)
    // @param startToken Starting token address for the hop
    // @param endToken Ending token address for the hop
    // @param settleType Settlement type (0 = market, 1 = liquid)
    // @param maxIterations Maximum settlement iterations per step
    // @param maker Address of the hop initiator (defaults to msg.sender if address(0))
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

    // Processes all stalled hops globally
    // @param maxIterations Maximum number of iterations to process
    function executeHops(uint256 maxIterations) external;

    // Continues stalled hops for the caller
    // @param maxIterations Maximum number of iterations to process
    function continueHop(uint256 maxIterations) external;

    // Cancels a specific hop
    // @param hopId ID of the hop to cancel
    function cancelHop(uint256 hopId) external;

    // Cancels all stalled hops for the caller
    // @param maxIterations Maximum number of hops to cancel
    function cancelAll(uint256 maxIterations) external;
}