// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.19 (Updated)
// Changes:
// - v0.0.19: Added amountReceived and normalizedReceived to OrderPrep struct to support pre/post balance checks in SSRouter.sol (v0.0.32). Marked ISSListingTemplate.transact as payable to allow ETH transfers in _checkTransferAmount (line 58). Removed SafeERC20 import, as transferFrom replaces safeTransferFrom.
// - v0.0.18: Added getNextOrderId() external view returns (uint256) to ISSListingTemplate interface to resolve TypeError in SSOrderPartial.sol (line 42).
// - v0.0.17: Fixed ParserError in checkValidListing by removing extra parenthesis in require statement (line 188). Corrected modifier onlyValidListing syntax by moving _; to end of block (line 190). Fixed typo in revert message from "Agent not not set" to "Agent not set" (line 186). Revised SellOrderDetails struct: changed maker from uint256 to address, removed duplicate maxPrice (uint8), removed sellId for consistency with BuyOrderDetails (lines 170-180). Added agentView function to access internal agent state variable (line 200).
// - v0.0.16: Removed redundant mappings (orderPendingAmounts, payoutPendingAmounts, activeBuyOrders, activeSellOrders, activeLongPayouts, activeShortPayouts, makerActiveOrders) to query ISSListingTemplate view functions (e.g., pendingBuyOrdersView, getBuyOrderAmounts) (lines 100-110). Simplified struct definitions (BuyOrderDetails, SellOrderDetails, OrderClearData) as they are unused in SSRouter.sol (lines 90-100).
// - v0.0.15: Fixed DeclarationError by moving checkValidListing from SSRouter.sol to SSMainPartial.sol as a private view function. Updated onlyValidListing modifier to call checkValidListing directly, removing SSRouter dependency (lines 180-190).
// - v0.0.14: Removed isValidListing mapping, updated onlyValidListing modifier to call SSRouter.checkValidListing for runtime validation before order creation and settlement (lines 100-110).
// - v0.0.13: Removed redundant mappings (liquidityAddress, tokenA, tokenB, decimalsA, decimalsB) to fetch data from ISSListingTemplate (lines 100-110).
// - v0.0.12: Renamed listingAddress to getListingAddress in ISSLiquidityTemplate to resolve naming conflict with claimFees. Updated ISSListingTemplate.liquidityAddress to liquidityAddressView to match SSListingTemplate.sol (v0.0.8).
// - v0.0.11: Removed registryAddress mapping, moved to ISSListingTemplate to align with SSListingTemplate.sol (v0.0.8).
// - v0.0.10: Homogenized agent state variable usage, removed redundant listingAgent from SSRouter.sol, retained agent and setAgent for inheritance chain.
// - v0.0.9: Added agent state variable and setAgent function to allow setting the agent address, aligning with ISSListingTemplate.agent().
// - v0.0.8: Updated ISSListingTemplate interface to match SSListingTemplate.sol v0.0.8, revised PayoutUpdate struct, getBuyOrderCore, getSellOrderCore, and renamed viewDecimalsA/B to decimalsA/B.
// - v0.0.8: Added agent() function to ISSListingTemplate to resolve TypeError in SSRouter.sol.
// - v0.0.7: Added globalization comment clarifying SSListingTemplate/SSLiquidityTemplate handle globalization.
// - v0.0.7: Added registryAddress mapping, set manually via SSRouter.setRegistry.
// - v0.0.7: Updated ISSAgent to include only getListing for listing validation.
// - v0.0.7: Maintained ISSListingTemplate and ISSLiquidityTemplate for SSListingTemplate v0.0.5 and SSLiquidityTemplate v0.0.4.
// - v0.0.7: Removed taxCollector references.
// - Compatible with SSListingTemplate.sol (v0.0.8), SSLiquidityTemplate.sol (v0.0.4).

import "../imports/ReentrancyGuard.sol";
import "../imports/Ownable.sol";
import "../imports/SafeERC20.sol";

// Note: Globalization (orders and liquidity) is handled by SSListingTemplate and SSLiquidityTemplate, not SSRouter.

interface ISSListingTemplate {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index;    // orderId or slot index
        uint256 value;    // principal or amount
        address addr;     // makerAddress
        address recipient;// recipientAddress
        uint256 maxPrice; // for Pricing struct
        uint256 minPrice; // for Pricing struct
    }
    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
    }
    struct LongPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }
    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 amount;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }
    function agent() external view returns (address);
    function registryAddress() external view returns (address);
    function setRegistry(address newRegistry) external;
    function update(address caller, UpdateType[] memory updates) external;
    function ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external payable;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory);
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory);
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function longPayoutByIndexView() external view returns (uint256[] memory);
    function shortPayoutByIndexView() external view returns (uint256[] memory);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function normalize(uint256 amount, uint8 decimals) external pure returns (uint256);
    function denormalize(uint256 amount, uint8 decimals) external pure returns (uint256);
    function getListingId() external view returns (uint256);
    function getNextOrderId() external view returns (uint256);
}

interface ISSLiquidityTemplate {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }
    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }
    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dVolume;
        uint256 timestamp;
    }
    
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function deposit(address caller, address token, uint256 amount) external payable;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function addFees(address caller, bool isX, uint256 fee) external;
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external;
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
    function activeXLiquiditySlotsView() external view returns (uint256[] memory);
    function activeYLiquiditySlotsView() external view returns (uint256[] memory);
    function userIndexView(address user) external view returns (uint256[] memory);
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
    function getListingAddress() external view returns (address);
    function listingId() external view returns (uint256);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function routers(address router) external view returns (bool);
}

interface ISSAgent {
    function getListing(address tokenA, address tokenB) external view returns(address);
}

contract SSMainPartial is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address internal agent;

    struct OrderPrep {
        address maker;
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    struct BuyOrderDetails {
        uint256 orderId;
        address maker;
        address recipient;
        uint256 pending;
        uint256 filled;
        uint256 maxPrice;
        uint256 minPrice;
        uint8 status;
    }

    struct SellOrderDetails {
        uint256 orderId;
        address maker;
        address recipient;
        uint256 pending;
        uint256 filled;
        uint256 maxPrice;
        uint256 minPrice;
        uint8 status;
    }

    struct OrderClearData {
        uint256 orderId;
        bool isBuy;
        uint256 amount;
    }

    function checkValidListing(address listing) private view {
        ISSListingTemplate listingTemplate = ISSListingTemplate(listing);
        address agentAddress = listingTemplate.agent();
        if (agentAddress == address(0)) revert("Agent not set");
        address tokenAAddress = listingTemplate.tokenA();
        address tokenBAddress = listingTemplate.tokenB();
        require(ISSAgent(agentAddress).getListing(tokenAAddress, tokenBAddress) == listing, "Invalid listing");
    }

    modifier onlyValidListing(address listing) {
        checkValidListing(listing);
        _;
    }

    function setAgent(address newAgent) external onlyOwner {
        require(newAgent != address(0), "Invalid agent address");
        agent = newAgent;
    }

    function agentView() external view returns (address) {
        return agent;
    }
}