// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

// Version: 0.0.3 (Updated)
// Changes:
// - Updated ISSLiquidLibrary: removed listingId from xClaimFees, yClaimFees; pass listingAddress (new in v0.0.2).
// - Modified claimFees to pass listingAddress instead of listingId (new in v0.0.2).
// - Added ISSLiquidSlotLibrary for deposit/withdrawal; updated deposit/withdraw to use it; included xPrepOut, yPrepOut in SSLiquidSlotLibrary (new in v0.0.3).
// - Side effects: Aligns with SSLiquidityTemplate’s claimFees; uses SSLiquidSlotLibrary for deposits/withdrawals.

import "./imports/SafeERC20.sol";
import "./imports/Ownable.sol";

interface ISS {
    function isValidListing(address listing) external view returns (bool);
}

interface ISSListing {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address maker;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct PayoutUpdate {
        uint8 payoutType; // 0 = long payout, 1 = short payout
        address recipient;
        uint256 required;
        uint256 price;    // Added for historical data
        uint256 xBalance; // Added for historical data
        uint256 yBalance; // Added for historical data
        uint256 xVolume;  // Added for historical data
        uint256 yVolume;  // Added for historical data
    }

    function update(address caller, UpdateType[] memory updates) external;
    function ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function liquidityAddresses(uint256 index) external view returns (address);
}

interface ISSOrderLibrary {
    struct BuyOrderDetails {
        uint256 amount;
        uint256 price;
        address recipient;
    }

    struct SellOrderDetails {
        uint256 amount;
        uint256 price;
        address recipient;
    }

    function prepBuyOrder(address listingAddress, address listingAgent, BuyOrderDetails memory details) external payable returns (ISSListing.UpdateType memory);
    function prepSellOrder(address listingAddress, address listingAgent, SellOrderDetails memory details) external payable returns (ISSListing.UpdateType memory);
    function executeBuyOrder(address listingAddress, address proxy, ISSListing.UpdateType memory update) external;
    function executeSellOrder(address listingAddress, address proxy, ISSListing.UpdateType memory update) external;
    function clearSingleOrder(address listingAddress, address proxy, uint256 orderId, bool isBuy) external returns (ISSListing.UpdateType memory);
    function clearOrders(address listingAddress, address proxy) external returns (ISSListing.UpdateType[] memory);
}

interface ISSSettlementLibrary {
    struct PreparedUpdate {
        uint256 orderId;
        bool isBuy;
        uint256 amount;
        address recipient;
    }

    struct PreparedPayoutUpdate {
        uint256 orderId;
        bool isLong;
        uint256 amount;
        address recipient;
    }

    function prepBuyOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function prepSellOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function executeBuyOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external;
    function executeSellOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external;
    function prepLongPayouts(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory);
    function prepShortPayouts(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory);
    function executeLongPayouts(address listingAddress, address proxy, PreparedPayoutUpdate[] memory preparedUpdates) external;
    function executeShortPayouts(address listingAddress, address proxy, PreparedPayoutUpdate[] memory preparedUpdates) external;
}

interface ISSLiquidLibrary {
    struct PreparedUpdate {
        uint256 orderId;
        bool isBuy;
        uint256 amount;
        address recipient;
    }

    struct PreparedPayoutUpdate {
        uint256 orderId;
        bool isLong;
        uint256 amount;
        address recipient;
    }

    function prepBuyLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function prepSellLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function executeBuyLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external;
    function executeSellLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external;
    function xClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external;
    function yClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external;
    function prepLongPayoutLiquid(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory);
    function prepShortPayoutLiquid(address listingAddress, address listingAgent) external view returns (PreparedPayoutUpdate[] memory);
    function executeLongPayoutLiquid(address listingAddress, address listingAgent, address proxy, PreparedPayoutUpdate[] memory preparedUpdates) external;
    function executeShortPayoutLiquid(address listingAddress, address listingAgent, address proxy, PreparedPayoutUpdate[] memory preparedUpdates) external;
}

interface ISSLiquidSlotLibrary {
    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }

    function xDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
    function yDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
    function xWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory);
    function yWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory);
}

contract SSProxyRouter is Ownable {
    address public listingAgent;
    address public orderLibrary;
    address public liquidLibrary;
    address public settlementLibrary;
    address public liquidSlotLibrary;

    constructor() {}

    function setListingAgent(address _listingAgent) external onlyOwner {
        require(listingAgent == address(0), "ListingAgent already set");
        listingAgent = _listingAgent;
    }

    function setOrderLibrary(address _orderLibrary) external onlyOwner {
        require(_orderLibrary != address(0), "Zero address");
        orderLibrary = _orderLibrary;
    }

    function setLiquidLibrary(address _liquidLibrary) external onlyOwner {
        require(_liquidLibrary != address(0), "Zero address");
        liquidLibrary = _liquidLibrary;
    }

    function setSettlementLibrary(address _settlementLibrary) external onlyOwner {
        require(_settlementLibrary != address(0), "Zero address");
        settlementLibrary = _settlementLibrary;
    }

    function setLiquidSlotLibrary(address _liquidSlotLibrary) external onlyOwner {
        require(_liquidSlotLibrary != address(0), "Zero address");
        liquidSlotLibrary = _liquidSlotLibrary;
    }

    function buyOrder(address listingAddress, ISSOrderLibrary.BuyOrderDetails memory details) external payable {
        require(orderLibrary != address(0), "Order library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing.UpdateType memory update = ISSOrderLibrary(orderLibrary).prepBuyOrder{value: msg.value}(listingAddress, listingAgent, details);
        ISSOrderLibrary(orderLibrary).executeBuyOrder(listingAddress, address(this), update);
    }

    function sellOrder(address listingAddress, ISSOrderLibrary.SellOrderDetails memory details) external payable {
        require(orderLibrary != address(0), "Order library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing.UpdateType memory update = ISSOrderLibrary(orderLibrary).prepSellOrder{value: msg.value}(listingAddress, listingAgent, details);
        ISSOrderLibrary(orderLibrary).executeSellOrder(listingAddress, address(this), update);
    }

    function buyLiquid(address listingAddress) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSLiquidLibrary.PreparedUpdate[] memory updates = ISSLiquidLibrary(liquidLibrary).prepBuyLiquid(listingAddress, listingAgent);
        ISSLiquidLibrary(liquidLibrary).executeBuyLiquid(listingAddress, listingAgent, address(this), updates);
    }

    function sellLiquid(address listingAddress) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSLiquidLibrary.PreparedUpdate[] memory updates = ISSLiquidLibrary(liquidLibrary).prepSellLiquid(listingAddress, listingAgent);
        ISSLiquidLibrary(liquidLibrary).executeSellLiquid(listingAddress, listingAgent, address(this), updates);
    }

    function settleBuy(address listingAddress) external {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSSettlementLibrary.PreparedUpdate[] memory updates = ISSSettlementLibrary(settlementLibrary).prepBuyOrders(listingAddress, listingAgent);
        ISSSettlementLibrary(settlementLibrary).executeBuyOrders(listingAddress, address(this), updates);
    }

    function settleSell(address listingAddress) external {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSSettlementLibrary.PreparedUpdate[] memory updates = ISSSettlementLibrary(settlementLibrary).prepSellOrders(listingAddress, listingAgent);
        ISSSettlementLibrary(settlementLibrary).executeSellOrders(listingAddress, address(this), updates);
    }

    function settleLongPayout(address listingAddress) external {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSSettlementLibrary.PreparedPayoutUpdate[] memory updates = ISSSettlementLibrary(settlementLibrary).prepLongPayouts(listingAddress, listingAgent);
        ISSSettlementLibrary(settlementLibrary).executeLongPayouts(listingAddress, address(this), updates);
    }

    function settleShortPayout(address listingAddress) external {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSSettlementLibrary.PreparedPayoutUpdate[] memory updates = ISSSettlementLibrary(settlementLibrary).prepShortPayouts(listingAddress, listingAgent);
        ISSSettlementLibrary(settlementLibrary).executeShortPayouts(listingAddress, address(this), updates);
    }

    function liquidLongPayout(address listingAddress) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSLiquidLibrary.PreparedPayoutUpdate[] memory updates = ISSLiquidLibrary(liquidLibrary).prepLongPayoutLiquid(listingAddress, listingAgent);
        ISSLiquidLibrary(liquidLibrary).executeLongPayoutLiquid(listingAddress, listingAgent, address(this), updates);
    }

    function liquidShortPayout(address listingAddress) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSLiquidLibrary.PreparedPayoutUpdate[] memory updates = ISSLiquidLibrary(liquidLibrary).prepShortPayoutLiquid(listingAddress, listingAgent);
        ISSLiquidLibrary(liquidLibrary).executeShortPayoutLiquid(listingAddress, listingAgent, address(this), updates);
    }

    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy) external {
        require(orderLibrary != address(0), "Order library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing.UpdateType memory update = ISSOrderLibrary(orderLibrary).clearSingleOrder(listingAddress, address(this), orderId, isBuy);
        ISSListing(listingAddress).update(address(this), _updateArray(update));
    }

    function clearOrders(address listingAddress) external {
        require(orderLibrary != address(0), "Order library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing.UpdateType[] memory updates = ISSOrderLibrary(orderLibrary).clearOrders(listingAddress, address(this));
        ISSListing(listingAddress).update(address(this), updates);
    }

    function deposit(address listingAddress, bool isX, uint256 amount) external payable {
        require(liquidSlotLibrary != address(0), "Liquid slot library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        if (isX) {
            ISSLiquidSlotLibrary(liquidSlotLibrary).xDeposit(listingAddress, amount, listingAgent, address(this));
        } else {
            ISSLiquidSlotLibrary(liquidSlotLibrary).yDeposit(listingAddress, amount, listingAgent, address(this));
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        if (isX) {
            ISSLiquidLibrary(liquidLibrary).xClaimFees(listingAddress, liquidityIndex, listingAgent, address(this));
        } else {
            ISSLiquidLibrary(liquidLibrary).yClaimFees(listingAddress, liquidityIndex, listingAgent, address(this));
        }
    }

    function withdraw(address listingAddress, bool isX, uint256 amount, uint256 index) external {
        require(liquidSlotLibrary != address(0), "Liquid slot library not set");
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        if (isX) {
            ISSLiquidSlotLibrary(liquidSlotLibrary).xWithdraw(listingAddress, amount, index, listingAgent, address(this));
        } else {
            ISSLiquidSlotLibrary(liquidSlotLibrary).yWithdraw(listingAddress, amount, index, listingAgent, address(this));
        }
    }

    function _updateArray(ISSListing.UpdateType memory update) private pure returns (ISSListing.UpdateType[] memory) {
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](1);
        updates[0] = update;
        return updates;
    }

    receive() external payable {}
}