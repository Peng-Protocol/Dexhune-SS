// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.9
// Changes:
// - v0.0.9: Fixed TypeError in _clearOrderData by explicitly destructuring tuples from getBuyOrderCore and getSellOrderCore.
// - v0.0.8: Updated to align with SSMainPartial.sol v0.0.8 and SSListingTemplate.sol v0.0.8.
// - v0.0.7: Removed ISSAgent.globalizeOrders calls, globalization handled by SSListingTemplate.
// - v0.0.7: Fixed _clearOrderData array index assignment (removed erroneous activeOrders[i] = i).
// - v0.0.7: Maintained generic helpers (_handleOrderPrep, _executeSingleOrder, _clearOrderData).
// - Compatible with SSListingTemplate.sol (v0.0.8), SSLiquidityTemplate.sol (v0.0.4).

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
        uint8 decimals = isBuy ? decimalsB[listing] : decimalsA[listing];
        uint256 normalizedAmount = ISSListingTemplate(listing).normalize(amount, decimals);
        return OrderPrep(maker, recipient, normalizedAmount, maxPrice, minPrice);
    }

    function _executeSingleOrder(
        address listing,
        OrderPrep memory prep,
        bool isBuy
    ) internal {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        uint256 orderId = makerActiveOrders[listing][prep.maker].length;
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](1);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: prep.amount,
            addr: prep.maker,
            recipient: prep.recipient,
            maxPrice: prep.maxPrice,
            minPrice: prep.minPrice
        });
        listingContract.update(address(this), updates);
        orderPendingAmounts[listing][orderId] = prep.amount;
        makerActiveOrders[listing][prep.maker].push(orderId);
        if (isBuy) {
            activeBuyOrders[listing].push(orderId);
        } else {
            activeSellOrders[listing].push(orderId);
        }
    }

    function _clearOrderData(
        address listing,
        uint256 orderId,
        bool isBuy
    ) internal {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.UpdateType[] memory updates = new ISSListingTemplate.UpdateType[](1);
        updates[0] = ISSListingTemplate.UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: 0,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        listingContract.update(address(this), updates);
        orderPendingAmounts[listing][orderId] = 0;
        (address maker,,) = isBuy ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        uint256[] storage makerOrders = makerActiveOrders[listing][maker];
        for (uint256 i = 0; i < makerOrders.length; i++) {
            if (makerOrders[i] == orderId) {
                makerOrders[i] = makerOrders[makerOrders.length - 1];
                makerOrders.pop();
                break;
            }
        }
        uint256[] storage activeOrders = isBuy ? activeBuyOrders[listing] : activeSellOrders[listing];
        for (uint256 i = 0; i < activeOrders.length; i++) {
            if (activeOrders[i] == orderId) {
                activeOrders[i] = activeOrders[activeOrders.length - 1];
                activeOrders.pop();
                break;
            }
        }
    }
}