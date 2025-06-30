// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.19 (Updated)
// Changes:
// - v0.0.19: Added maker check in _clearOrderData to ensure msg.sender is the order’s maker, restricting cancellations.
// - v0.0.18: Fixed TypeError in _executeSingleOrder and _clearOrderData by replacing receiver with recipient in UpdateType struct.
// - v0.0.17: Fixed TypeError in _clearOrderData by including amountSent in tuple destructuring from getBuyOrderAmounts/getSellOrderAmounts.
// - v0.0.16: Updated _executeSingleOrder to initialize amountSent to 0 in BuyOrderAmounts/SellOrderAmounts during creation.
// - v0.0.15: Replaced ISSListingTemplate.normalize/denormalize calls with inherited functions from SSMainPartial.sol.
// - v0.0.14: Updated _clearOrderData to refund pending amounts via transact, using denormalized amounts based on token decimals.
// - v0.0.13: Updated _executeSingleOrder to use prep.normalizedReceived instead of prep.amount.
// - v0.0.12: Fixed TypeError in _executeSingleOrder by adding getNextOrderId to ISSListingTemplate interface.
// - v0.0.11: Removed redundant mappings, using makerPendingOrdersView, pendingBuyOrdersView, and pendingSellOrdersView.
// - v0.0.10: Fixed TypeError in _handleOrderPrep by using decimalsA()/decimalsB() from ISSListingTemplate.
// - v0.0.9: Fixed TypeError in _clearOrderData by explicitly destructuring tuples from getBuyOrderCore/getSellOrderCore.
// Compatible with SSListingTemplate.sol (v0.0.10), SSLiquidityTemplate.sol (v0.0.6), SSMainPartial.sol (v0.0.25), SSRouter.sol (v0.0.61), SSSettlementPartial.sol (v0.0.57).

import "./SSMainPartial.sol";

contract SSOrderPartial is SSMainPartial {
    struct OrderPrep {
        address maker;
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 amountReceived;
        uint256 normalizedReceived;
    }

    function _handleOrderPrep(
        address listing,
        address maker,
        address recipient,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        bool isBuy
    ) internal view returns (OrderPrep memory) {
        // Prepares order data, normalizes amount based on token decimals
        require(maker != address(0), "Invalid maker");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint8 decimals = isBuy ? listingContract.decimalsB() : listingContract.decimalsA();
        uint256 normalizedAmount = normalize(amount, decimals);
        return OrderPrep(maker, recipient, normalizedAmount, maxPrice, minPrice, 0, 0);
    }

    function _executeSingleOrder(
        address listing,
        OrderPrep memory prep,
        bool isBuy
    ) internal {
        // Executes single order creation, initializes amountSent to 0
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256 orderId = listingContract.getNextOrderId();
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](3);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2, // 1: Buy, 2: Sell
            structId: 0,               // Core struct
            index: orderId,
            value: 1,                  // Status: pending
            addr: prep.maker,
            recipient: prep.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2, // 1: Buy, 2: Sell
            structId: 1,               // Pricing struct
            index: orderId,
            value: 0,
            addr: address(0),
            recipient: address(0),
            maxPrice: prep.maxPrice,
            minPrice: prep.minPrice,
            amountSent: 0
        });
        updates[2] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2, // 1: Buy, 2: Sell
            structId: 2,               // Amounts struct
            index: orderId,
            value: prep.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        listingContract.update(address(this), updates);
    }

    function _clearOrderData(
        address listing,
        uint256 orderId,
        bool isBuy
    ) internal {
        // Clears order data, refunds pending amounts, sets status to cancelled
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        (address maker, address recipient, uint8 status) = isBuy
            ? listingContract.getBuyOrderCore(orderId)
            : listingContract.getSellOrderCore(orderId);
        require(maker == msg.sender, "Only maker can cancel");
        (uint256 pending, uint256 filled, uint256 amountSent) = isBuy
            ? listingContract.getBuyOrderAmounts(orderId)
            : listingContract.getSellOrderAmounts(orderId);
        if (pending > 0 && (status == 1 || status == 2)) {
            address tokenAddress = isBuy ? listingContract.tokenB() : listingContract.tokenA();
            uint8 tokenDecimals = isBuy ? listingContract.decimalsB() : listingContract.decimalsA();
            uint256 refundAmount = denormalize(pending, tokenDecimals);
            try listingContract.transact(address(this), tokenAddress, refundAmount, recipient) {} catch {
                revert("Refund failed");
            }
        }
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](1);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2, // 1: Buy, 2: Sell
            structId: 0,               // Core struct
            index: orderId,
            value: 0,                  // Status: cancelled
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        listingContract.update(address(this), updates);
    }
}