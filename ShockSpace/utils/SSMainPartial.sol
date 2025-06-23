// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.25 (Updated)
// Changes:
// - v0.0.25: Replaced getLongPayoutOrder with getLongPayout in ISSListingTemplate interface to align with SSListingTemplate.sol v0.0.10 and fix TypeError in SSSettlementPartial.sol.
// - v0.0.24: Removed duplicate getBuyOrderCore function in ISSListingTemplate interface returning (address makerAddress, uint8 status, uint256 amount). Updated remaining getBuyOrderCore to use recipientAddress instead of receiverAddress for consistency with SSListingTemplate.sol implementation. Ensured compatibility with SSListingTemplate.sol v0.0.10, SSOrderPartial.sol v0.0.17, and SSRouter.sol v0.0.47.
// - v0.0.23: Fixed ParserError in ISSListingTemplate interface by correcting update function signature from `UpdateType[] Thereafter address` to `UpdateType[] memory updates`, aligning with usage in SSOrderPartial.sol v0.0.17 and SSRouter.sol v0.0.47.
// - v0.0.22: Removed duplicate OrderPrep struct to resolve DeclarationError, as it’s defined in SSOrderPartial.sol. Updated ISSListingTemplate.getBuyOrderAmounts and getSellOrderAmounts to return (uint256 pending, uint256 filled, uint256 amountSent) to align with BuyOrderAmounts/SellOrderAmounts structs in SSListingTemplate.sol v0.0.10, fixing TypeError in SSRouter.sol and SSOrderPartial.sol.
// - v0.0.21: Added amountSent to ISSListingTemplate.UpdateType struct to align with BuyOrderAmounts and SellOrderAmounts structs in SSListingTemplate.sol v0.0.10, ensuring compatibility with SSRouter.sol v0.0.45 and SSSettlementPartial.sol v0.0.46.
// - v0.0.20: Added normalize and denormalize functions to handle token amount conversions internally, replacing external calls to ISSListingTemplate.normalize and ISSListingTemplate.denormalize for consistency and control.
// - v0.0.19: Added decimalsA() and decimalsB() to ISSListingTemplate interface.
// - v0.0.18: Added getNextOrderId to ISSListingTemplate interface.

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
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct
        uint256 minPrice; // for Pricing struct
        uint256 amountSent; // for Amounts struct (tokenX for buy, tokenY for sell)
    }
    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient;
        uint256 required;
    }
    struct LongPayoutStruct {
        address makerAddress;
        address recipientAddress; // Updated to match implementation
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }
    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress; // Updated to match implementation
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
    function transact(address caller, address token, uint256 amount, address receiver) external payable;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function getSellOrderCore(uint256 orderId) external view returns (address recipientAddress, address makerAddress, uint8 status);
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
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
    function getListingId() external view returns (uint256);
    function getNextOrderId() external view returns (uint256);
}

interface ISSLiquidityTemplate {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address receiver;
    }
    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }
    struct Slot {
        address depositor;
        address receiver;
        uint256 allocation;
        uint256 dVolume;
        uint64 timestamp;
    }
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address receiver) external;
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

    struct BuyOrderDetails {
        uint256 orderId;
        address maker;
        address receiver;
        uint256 pending;
        uint256 filled;
        uint256 maxPrice;
        uint256 minPrice;
        uint8 status;
    }

    struct SellOrderDetails {
        uint256 orderId;
        address maker;
        address receiver;
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

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Normalizes amount to 18 decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Denormalizes amount from 18 decimals to token decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    function checkValidListing(address listing) private view {
        // Validates listing against agent registry
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
        // Sets new agent address
        require(newAgent != address(0), "Invalid agent address");
        agent = newAgent;
    }

    function agentView() external view returns (address) {
        // Returns current agent address
        return agent;
    }
}