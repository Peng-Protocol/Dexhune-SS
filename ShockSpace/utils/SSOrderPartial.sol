// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.14 (Updated)
// Changes:
// - v0.0.14: Updated _clearOrderData to refund pending amounts via ISSListingTemplate.transact, using denormalized amount based on token decimals (tokenB for buy, tokenA for sell) and recipient from order core, before canceling order status (status 0 for canceled or invalid orders).
// - v0.0.13: Updated _executeSingleOrder to use prep.normalizedReceived instead of prep.amount to reflect pre/post balance checks in SSRouter.sol (v0.0.32).
// - v0.0.12: Fixed TypeError in _executeSingleOrder by adding getNextOrderId to ISSListingTemplate interface in SSMainPartial.sol, enabling correct order ID retrieval (line 42). Noted potential review needed for updates[1].value in _executeSingleOrder (set to 0 for Pricing struct).
// - v0.0.11: Removed makerActiveOrders, activeBuyOrders, and activeSellOrders mappings from SSOrderPartial.sol as they are redundant. Replaced with ISSListingTemplate.makerPendingOrdersView, pendingBuyOrdersView, and pendingSellOrdersView calls to fetch order details directly from the listing contract. Updated _executeSingleOrder and _clearOrderData to rely on listing contract state via view functions, ensuring correct context and alignment with SSListingTemplate.sol (v0.0.8).
// - v0.0.10: Fixed DeclarationError in _handleOrderPrep by replacing decimalsA/decimalsB mappings with ISSListingTemplate.decimalsA()/decimalsB() calls, aligning with SSMainPartial.sol v0.0.19 (line 28).
// - v0.0.9: Fixed TypeError in _clearOrderData by explicitly destructuring tuples from getBuyOrderCore and getSellOrderCore.
// - v0.0.8: Updated to align with SSMainPartial.sol v0.0.8 and SSListingTemplate.sol v0.0.8).
// - v0.0.7: Removed ISSAgent.globalizeOrders calls, globalization handled by SSListingTemplate.
// - v0.0.7: Fixed _clearOrderData array index assignment (removed erroneous activeOrders[i] = i).
// - v0.0.7: Maintained generic helpers (_handleOrderPrep, _executeSingleOrder, _clearOrderData).
// - Compatible with SSListingTemplate.sol (v0.0.8), SSLiquidityTemplate.sol (v0.0.4), SSMainPartial.sol (v0.0.19).

import "./SSMainPartial.sol";

contract SSOrderPartial is SSMainPartial {
    function _handleOrderPrep(
        address listing,
        address maker,
        address recipient,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        bool isBuy
    ) internal view returns (OrderPrep memory) {
        require(maker != address(0), "Invalid maker");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint8 decimals = isBuy ? listingContract.decimalsB() : listingContract.decimalsA();
        uint256 normalizedAmount = listingContract.normalize(amount, decimals);
        return OrderPrep(maker, recipient, normalizedAmount, maxPrice, minPrice, 0, 0);
    }

    function _executeSingleOrder(
        address listing,
        OrderPrep memory prep,
        bool isBuy
    ) internal {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256 orderId = listingContract.getNextOrderId();
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](2);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: 1, // Initial status: pending
            addr: prep.maker,
            recipient: prep.recipient,
            maxPrice: 0,
            minPrice: 0
        });
        updates[1] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 1,
            index: orderId,
            value: prep.normalizedReceived, // Use normalized received amount
            addr: address(0),
            recipient: address(0),
            maxPrice: prep.maxPrice,
            minPrice: prep.minPrice
        });
        listingContract.update(address(this), updates);
    }

    function _clearOrderData(
        address listing,
        uint256 orderId,
        bool isBuy
    ) internal {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        (address maker, address recipient, uint8 status) = isBuy
            ? listingContract.getBuyOrderCore(orderId)
            : listingContract.getSellOrderCore(orderId);
        (uint256 pending,) = isBuy
            ? listingContract.getBuyOrderAmounts(orderId)
            : listingContract.getSellOrderAmounts(orderId);
        if (pending > 0 && (status == 1 || status == 2)) {
            address tokenAddress = isBuy ? listingContract.tokenB() : listingContract.tokenA();
            uint8 tokenDecimals = isBuy ? listingContract.decimalsB() : listingContract.decimalsA();
            uint256 refundAmount = listingContract.denormalize(pending, tokenDecimals);
            try listingContract.transact(address(this), tokenAddress, refundAmount, recipient) {} catch {
                revert("Refund failed");
            }
        }
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](1);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: 0, // Set status to cancelled
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        listingContract.update(address(this), updates);
    }
}