// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.44
// Change Log:
// - 2025-07-11: Removed SafeERC20 import and replaced safeTransferFrom with IERC20.transferFrom in _handleFilledOrSent, _handlePending, and _handleBalance.
// - 2025-07-11: Added IERC20 import from ../imports/IERC20.sol.
// - 2025-07-11: Updated import paths to use ../imports/ for consistency with MHMain.sol.
// - Confirmed nonReentrant modifier correctly inherited from ReentrancyGuard via MHMain.sol.
// - 2025-07-11: Created from Multihopper.sol v0.0.42 split.
// - Included cancellation and view functions from Multihopper.sol.
// - Inherits MHInit.sol for hop-related helpers.
// - Retained v0.0.42 changes: Extended `CancelPrepData` with `refundedPending`, updated cancellation for transfer taxes.
// - Retained v0.0.41 and earlier changes: Stack optimization, `maker` parameter, view functions.

import "./MHInit.sol";

contract MHCtrl is MHInit {
    function _prepClearHopOrder(address listing, uint256 orderId, bool isBuy, uint256 hopId)
        internal view returns (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 amountSent, address tokenIn, address tokenOut)
    {
        // Prepares data for clearing a hop order, checking permissions and retrieving order details
        ISSListing listingContract = ISSListing(listing);
        (maker, recipient, status) = isBuy ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        require(maker == msg.sender, "Only maker can cancel");
        require(status == 1 || status == 2, "Order not cancellable");
        (pending, filled, , amountSent) = checkOrderStatus(listing, orderId, isBuy);
        tokenIn = isBuy ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuy ? listingContract.tokenA() : listingContract.tokenB();
    }

    function _executeClearHopOrder(CancelPrepData memory prepData) internal {
        // Executes cancellation of a hop order, updating status, handling refunds, and updating principalAmount
        ISSListing listingContract = ISSListing(prepData.listing);
        uint256 balanceBefore = prepData.outputToken == address(0) ? address(this).balance : IERC20(prepData.outputToken).balanceOf(address(this));
        HopUpdateType[] memory hopUpdates = new HopUpdateType[](1);
        setOrderStatus(hopUpdates, 0);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({
                field: hopUpdates[i].field,
                value: hopUpdates[i].value
            });
        }
        try listingContract.update(updates) {
            uint256 balanceAfter = prepData.outputToken == address(0) ? address(this).balance : IERC20(prepData.outputToken).balanceOf(address(this));
            CancelBalanceData memory balanceData = CancelBalanceData({
                token: prepData.outputToken,
                balanceBefore: balanceBefore,
                balanceAfter: balanceAfter
            });
            _handleFilledOrSent(prepData.filled, prepData.receivedAmount, prepData.outputToken, prepData.recipient);
            _handlePending(prepData.pending, prepData.inputToken, prepData.hopId, prepData);
            _handleBalance(balanceData, prepData.hopId);
            hopID[prepData.hopId].principalAmount = prepData.refundedPending; // Update principalAmount with actual refunded pending amount
        } catch {
            revert("Order cancellation failed");
        }
    }

    function _handleFilledOrSent(uint256 filled, uint256 receivedAmount, address outputToken, address recipient) internal {
        // Refunds amountSent (if non-zero and not yet received) or filled to recipient, accounting for transfer taxes
        if (filled > 0 || receivedAmount > 0) {
            uint256 rawAmount = denormalizeForToken(receivedAmount > 0 ? receivedAmount : filled, outputToken);
            uint256 actualAmount = _checkTransfer(outputToken, address(this), recipient, rawAmount);
            require(actualAmount > 0, "No amount refunded");
        }
    }

    function _handlePending(uint256 pending, address inputToken, uint256 hopId, CancelPrepData memory prepData) internal {
        // Refunds pending amount in input token to hopMaker, storing actual refunded amount
        if (pending > 0) {
            uint256 rawPending = denormalizeForToken(pending, inputToken);
            uint256 actualAmount = _checkTransfer(inputToken, address(this), hopID[hopId].hopMaker, rawPending);
            prepData.refundedPending = normalizeForToken(actualAmount, inputToken);
        }
    }

    function _handleBalance(CancelBalanceData memory balanceData, uint256 hopId) internal {
        // Refunds any additional balance increase in output token to hopMaker, accounting for transfer taxes
        if (balanceData.balanceAfter > balanceData.balanceBefore) {
            uint256 amount = balanceData.balanceAfter - balanceData.balanceBefore;
            uint256 actualAmount = _checkTransfer(balanceData.token, address(this), hopID[hopId].hopMaker, amount);
            require(actualAmount > 0, "No balance refunded");
        }
    }

    function _getOrderDetails(address listing, uint256 orderId, bool isBuy)
        internal view returns (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount, address recipient)
    {
        // Retrieves detailed order information for cancellation
        ISSListing listingContract = ISSListing(listing);
        (pending, filled, status, receivedAmount) = checkOrderStatus(listing, orderId, isBuy);
        (, recipient, ) = isBuy ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
    }

    function _prepCancelHopBuy(uint256 hopId) internal returns (CancelPrepData memory) {
        // Prepares cancellation data for a buy order and initiates order clearing
        StalledHop storage stalledHop = hopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Not hop maker");
        require(stalledHop.hopStatus == 1, "Hop not stalled");

        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenA();
        address inputToken = listing.tokenB();
        (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 receivedAmount, , ) =
            _prepClearHopOrder(stalledHop.currentListing, stalledHop.orderID, true, hopId);

        CancelPrepData memory prepData = CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: true,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: receivedAmount,
            recipient: recipient,
            refundedPending: 0 // Initialized, updated in _handlePending
        });

        _executeClearHopOrder(prepData);
        return prepData;
    }

    function _prepCancelHopSell(uint256 hopId) internal returns (CancelPrepData memory) {
        // Prepares cancellation data for a sell order and initiates order clearing
        StalledHop storage stalledHop = hopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Not hop maker");
        require(stalledHop.hopStatus == 1, "Hop not stalled");

        ISSListing listing = ISSListing(stalledHop.currentListing);
        address outputToken = listing.tokenB();
        address inputToken = listing.tokenA();
        (address maker, address recipient, uint8 status, uint256 pending, uint256 filled, uint256 receivedAmount, , ) =
            _prepClearHopOrder(stalledHop.currentListing, stalledHop.orderID, false, hopId);

        CancelPrepData memory prepData = CancelPrepData({
            hopId: hopId,
            listing: stalledHop.currentListing,
            isBuy: false,
            outputToken: outputToken,
            inputToken: inputToken,
            pending: pending,
            filled: filled,
            status: status,
            receivedAmount: receivedAmount,
            recipient: recipient,
            refundedPending: 0 // Initialized, updated in _handlePending
        });

        _executeClearHopOrder(prepData);
        return prepData;
    }

    function _finalizeCancel(uint256 hopId) internal {
        // Finalizes hop cancellation, updating status and removing from user hops
        StalledHop storage stalledHop = hopID[hopId];
        stalledHop.hopStatus = 2;
        uint256[] storage userHops = hopsByAddress[stalledHop.hopMaker];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] == hopId) {
                userHops[i] = userHops[userHops.length - 1];
                userHops.pop();
                break;
            }
        }
        emit HopCanceled(hopId);
    }

    function _cancelHop(uint256 hopId) internal {
        // Cancels a single hop, refunding appropriate amounts
        StalledHop storage stalledHop = hopID[hopId];
        bool isBuy = stalledHop.maxPrice > 0;
        if (isBuy) {
            _prepCancelHopBuy(hopId);
        } else {
            _prepCancelHopSell(hopId);
        }
        _finalizeCancel(hopId);
    }


    function agentView() public view returns (address) {
        // Returns the current ISSAgent address
        return _agent;
    }

    function hopStatusView(uint256 hopId) public view returns (uint8) {
        // Returns the status of a specific hop
        return hopID[hopId].hopStatus;
    }

    function getHopDetails(uint256 hopId) public view returns (StalledHop memory) {
        // Returns the full StalledHop struct for a given hopId for analytics
        return hopID[hopId];
    }

    function getUserHops(address user) public view returns (uint256[] memory) {
        // Returns the array of hop IDs for a given user
        return hopsByAddress[user];
    }

    function getTotalHopsCount() public view returns (uint256) {
        // Returns the total number of hops ever created
        return totalHops.length;
    }

    function getActiveHopsCount(address user) public view returns (uint256) {
        // Returns the count of stalled hops for a given user
        uint256 count = 0;
        uint256[] memory userHops = hopsByAddress[user];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (hopID[userHops[i]].hopStatus == 1) {
                count++;
            }
        }
        return count;
    }

    function getTotalPendingHopsCount(uint256 maxIterations) public view returns (uint256) {
        // Returns the total number of pending hops across all users, limited by maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 count = 0;
        for (uint256 i = 0; i < totalHops.length && i < maxIterations; i++) {
            if (hopID[totalHops[i]].hopStatus == 1) {
                count++;
            }
        }
        return count;
    }

    function getHopOrderDetails(uint256 hopId) public view returns (HopOrderDetails memory) {
        // Returns order details for the current order of a hop
        StalledHop memory stalledHop = hopID[hopId];
        (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
            stalledHop.currentListing,
            stalledHop.orderID,
            stalledHop.maxPrice > 0
        );
        (, address recipient, ) = stalledHop.maxPrice > 0
            ? ISSListing(stalledHop.currentListing).getBuyOrderCore(stalledHop.orderID)
            : ISSListing(stalledHop.currentListing).getSellOrderCore(stalledHop.orderID);
        return HopOrderDetails({
            pending: pending,
            filled: filled,
            status: status,
            amountSent: amountSent,
            recipient: recipient
        });
    }

    function getHopRoute(uint256 hopId) public view returns (HopRouteData memory) {
        // Returns the ordered list of listings and buy/sell flags for a hop
        StalledHop memory stalledHop = hopID[hopId];
        address[] memory listingAddresses = new address[](stalledHop.remainingListings.length + 1);
        bool[] memory isBuy = new bool[](stalledHop.remainingListings.length + 1);
        listingAddresses[0] = stalledHop.currentListing;
        isBuy[0] = stalledHop.maxPrice > 0;
        for (uint256 i = 0; i < stalledHop.remainingListings.length; i++) {
            listingAddresses[i + 1] = stalledHop.remainingListings[i];
            ISSListing listing = ISSListing(stalledHop.remainingListings[i]);
            isBuy[i + 1] = stalledHop.endToken == listing.tokenA();
        }
        return HopRouteData({
            listings: listingAddresses,
            isBuy: isBuy
        });
    }

    function getUserPendingVolume(address user, address token) public view returns (uint256) {
        // Returns total pending amount in a specified token across user's stalled hops
        uint256 totalPending = 0;
        uint256[] memory userHops = hopsByAddress[user];
        for (uint256 i = 0; i < userHops.length; i++) {
            StalledHop memory stalledHop = hopID[userHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            ISSListing listing = ISSListing(stalledHop.currentListing);
            address inputToken = stalledHop.maxPrice > 0 ? listing.tokenB() : listing.tokenA();
            if (inputToken != token) continue;
            (uint256 pending, , , ) = checkOrderStatus(stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0);
            totalPending += pending;
        }
        return totalPending;
    }

    function getContractBalance(address token) public view returns (uint256) {
        // Returns the contract's balance for a specified token or native currency
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }
}