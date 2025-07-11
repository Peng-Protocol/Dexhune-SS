// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.42
// Change Log:
// - 2025-07-11: Created from Multihopper.sol v0.0.42 split.
// - Defined interfaces, structs, mappings, events, and imports for use by MHInit, MHCtrl, and Multihopper.
// - Made state variables internal for inheritance.
// - Retained v0.0.42 changes: Extended `CancelPrepData` with `refundedPending`, updated cancellation functions for transfer taxes.
// - Retained v0.0.41 changes: Restructured cancellation to address `Stack too deep`.
// - Retained v0.0.40 and earlier changes: Added `maker` parameter, fixed typos, added view functions.

import "../imports/Ownable.sol";
import "../imports/ReentrancyGuard.sol";
import "../imports/SafeERC20.sol";

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

contract MHMain {
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
        uint256 refundedPending; // Actual amount refunded after transfer taxes
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

    RouterInfo[] internal _routers; // Hidden array of router info
    address internal _agent; // Hidden ISSAgent address for listing validation
    mapping(uint256 => StalledHop) internal hopID; // Hidden hop storage
    mapping(address => uint256[]) internal hopsByAddress; // Hidden user hop list
    uint256[] internal totalHops; // Hidden global hop list
    uint256 internal nextHopId; // Hidden hop ID counter

    event HopStarted(uint256 indexed hopId, address indexed maker, uint256 numListings);
    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event HopCanceled(uint256 indexed hopId);
    event AllHopsCanceled(address indexed maker, uint256 count);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);
    event RouterAdded(address indexed router, uint8 routerType);
    event RouterRemoved(address indexed router);
    event AgentSet(address indexed agent);
}