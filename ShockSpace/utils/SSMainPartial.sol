// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.20 (Updated)
// Changes:
// - v0.0.20: Added normalize and denormalize functions to handle token amount conversions internally, replacing external calls to ISSListingTemplate.normalize and ISSListingTemplate.denormalize for consistency and control.

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

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
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