// SPDX-License-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.44
// Change Log:
// - 2025-07-11: Removed SafeERC20 import and replaced safeTransferFrom and safeApprove with IERC20.transferFrom and IERC20.approve in _createHopOrder.
// - 2025-07-11: Added IERC20 import from ../imports/IERC20.sol.
// - 2025-07-11: Updated from Multihopper.sol v0.0.42, split into MHMain, MHInit, MHCtrl, and Multihopper.
// - Included user-facing functions and core logic, inheriting MHCtrl.sol.
// - Moved interfaces, structs, and mappings to MHMain.sol, helpers to MHInit.sol, cancellation/views to MHCtrl.sol.
// - Added onlyValidListing modifier for hop function.
// - Retained v0.0.42 changes: Extended `CancelPrepData` with `refundedPending`, updated cancellation for transfer taxes.
// - Retained v0.0.41 changes: Restructured cancellation to address `Stack too deep`.
// - Retained v0.0.40 and earlier changes: Added `maker` parameter, fixed typos, added view functions.
// - Cross-checked for naming conflicts, reserved keywords, and compatibility with Solidity ^0.8.2, SSRouter v0.0.61, HopPartial v0.0.58.

import "./hopperUtils/MHCtrl.sol";

contract Multihopper is MHCtrl, Ownable, ReentrancyGuard {
    modifier onlyValidListing(address listingAddress) {
        require(_agent != address(0), "Agent not set");
        require(listingAddress == address(0) || ISSAgent(_agent).getListing(listingAddress), "Invalid listing");
        _;
    }

    function _createHopOrder(OrderUpdateData memory orderData, address sender) internal returns (uint256 orderId) {
        // Creates a new order on the listing with specified parameters, assumes approvals are handled externally
        ISSListing listingContract = ISSListing(orderData.listing);
        orderId = listingContract.getNextOrderId();
        uint256 rawAmount = denormalizeForToken(orderData.inputAmount, orderData.inputToken);
        if (orderData.inputToken != address(0)) {
            bool success = IERC20(orderData.inputToken).transferFrom(sender, address(this), rawAmount);
            require(success, "TransferFrom failed");
            success = IERC20(orderData.inputToken).approve(orderData.listing, rawAmount);
            require(success, "Approve failed");
        }
        _checkTransfer(orderData.inputToken, address(this), orderData.listing, rawAmount);
        HopUpdateType[] memory hopUpdates = new HopUpdateType[](4);
        setOrderStatus(hopUpdates, 0);
        setOrderAmount(hopUpdates, 1, "buyAmount", orderData.inputAmount); // Placeholder, updated in computeBuy/SellSpecificParams
        setOrderPrice(hopUpdates, 2, "buyPrice", orderData.priceLimit); // Placeholder, updated in computeBuy/SellSpecificParams
        setOrderRecipient(hopUpdates, 3, orderData.recipient);
        ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
        for (uint256 i = 0; i < hopUpdates.length; i++) {
            updates[i] = ISSListing.UpdateType({
                field: hopUpdates[i].field,
                value: hopUpdates[i].value
            });
        }
        try listingContract.update(updates) {
            // Success
        } catch {
            revert("Order creation failed");
        }
    }

    function addRouter(address router, uint8 routerType) external onlyOwner {
        // Adds or updates a router in _routers, ensuring no duplicate addresses with different types
        require(router != address(0), "Invalid router address");
        require(routerType >= 1 && routerType <= 3, "Invalid router type");
        for (uint256 i = 0; i < _routers.length; i++) {
            if (_routers[i].routerType == routerType) {
                for (uint256 j = 0; j < _routers.length; j++) {
                    if (_routers[j].router == router && _routers[j].routerType != routerType) {
                        revert("Router address used for different type");
                    }
                }
                _routers[i].router = router;
                emit RouterAdded(router, routerType);
                return;
            }
        }
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i].router != router, "Router already added");
        }
        _routers.push(RouterInfo({ router: router, routerType: routerType }));
        emit RouterAdded(router, routerType);
    }

    function removeRouter(address router) external onlyOwner {
        // Removes a router from _routers using pop-and-swap
        for (uint256 i = 0; i < _routers.length; i++) {
            if (_routers[i].router == router) {
                _routers[i] = _routers[_routers.length - 1];
                _routers.pop();
                emit RouterRemoved(router);
                return;
            }
        }
        revert("Router not found");
    }

    function getRouters() public view returns (RouterInfo[] memory) {
        // Returns the array of registered routers
        return _routers;
    }

    function setAgent(address agent) external onlyOwner {
        // Sets the ISSAgent contract address for listing validation
        require(agent != address(0), "Invalid agent address");
        _agent = agent;
        emit AgentSet(agent);
    }

    function processHopStep(
        HopExecutionData memory execData,
        address sender
    ) internal returns (bool completed, uint256 orderId, uint256 amountSent) {
        // Processes a single hop step, creating and settling an order
        OrderUpdateData memory orderData = OrderUpdateData({
            listing: execData.listing,
            recipient: execData.recipient,
            inputAmount: normalizeForToken(execData.principal, execData.inputToken),
            priceLimit: execData.priceLimit,
            inputToken: execData.inputToken
        });
        orderId = _createHopOrder(orderData, sender);
        safeSettle(execData.listing, execData.isBuy, execData.settleType, execData.maxIterations);
        (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount) = checkOrderStatus(execData.listing, orderId, execData.isBuy);
        completed = status == 3 && pending == 0;
        amountSent = receivedAmount;
    }

    function executeHopSteps(
        HopExecutionParams memory params,
        HopPrepData memory prepData
    ) internal {
        // Executes hop steps, updating hop status and storage for the specified maker
        StalledHop storage stalledHop = hopID[prepData.hopId];
        uint256 principal = prepData.principal;
        address currentToken = prepData.currentToken;
        address maker = prepData.maker;

        for (uint256 i = 0; i < prepData.indices.length; i++) {
            OrderParams memory orderParams = OrderParams({
                listing: params.listingAddresses[prepData.indices[i]],
                principal: principal,
                impactPercent: params.impactPricePercents[prepData.indices[i]],
                index: i,
                numListings: params.numListings,
                maxIterations: params.maxIterations,
                settleType: params.settleType
            });
            HopExecutionData memory execData = prepData.isBuy[i]
                ? computeBuyOrderParams(orderParams, maker)
                : computeSellOrderParams(orderParams, maker);
            (bool completed, uint256 orderId, uint256 amountSent) = processHopStep(execData, msg.sender);
            if (!completed) {
                stalledHop.orderID = orderId;
                stalledHop.minPrice = execData.isBuy ? 0 : execData.priceLimit;
                stalledHop.maxPrice = execData.isBuy ? execData.priceLimit : 0;
                stalledHop.principalAmount = principal;
                stalledHop.remainingListings = new address[](prepData.indices.length - i - 1);
                for (uint256 j = i + 1; j < prepData.indices.length; j++) {
                    stalledHop.remainingListings[j - i - 1] = params.listingAddresses[prepData.indices[j]];
                }
                hopsByAddress[maker].push(prepData.hopId);
                totalHops.push(prepData.hopId);
                return;
            }
            principal = amountSent;
            currentToken = execData.isBuy ? ISSListing(execData.listing).tokenA() : ISSListing(execData.listing).tokenB();
        }

        stalledHop.hopStatus = 2;
        hopsByAddress[maker].push(prepData.hopId);
        totalHops.push(prepData.hopId);
    }

    function executeHop(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        HopPrepData memory prepData
    ) internal {
        // Executes a hop by preparing and processing steps
        HopExecutionParams memory params = prepareHopExecution(
            listing1, listing2, listing3, listing4,
            impactPercent, startToken, endToken,
            settleType, maxIterations, prepData
        );
        executeHopSteps(params, prepData);
    }

    function hop(
        address listing1, // First listing contract address, must be valid (verified by ISSAgent)
        address listing2, // Second listing contract address, set to address(0) if unused
        address listing3, // Third listing contract address, set to address(0) if unused
        address listing4, // Fourth listing contract address, set to address(0) if unused
        uint256 impactPercent, // Max price impact applied to all listings (scaled to 1000, e.g., 500 = 5%), must be ≤ 1000
        address startToken, // Starting token address (input token for the first hop step)
        address endToken, // Ending token address (output token for the last hop step)
        uint8 settleType, // Settlement type: 0 = market orders, 1 = liquid orders
        uint256 maxIterations, // Maximum settlement iterations per step, must be > 0
        address maker // Maker address for the hop, defaults to msg.sender if address(0)
    ) external payable nonReentrant onlyValidListing(listing1) returns (uint256) {
        // Initiates a multi-step token swap on behalf of maker
        address effectiveMaker = maker == address(0) ? msg.sender : maker;
        HopPrepData memory prepData = prepHop(listing1, listing2, listing3, listing4, impactPercent, startToken, endToken, settleType, maxIterations, effectiveMaker);
        executeHop(listing1, listing2, listing3, listing4, impactPercent, startToken, endToken, settleType, maxIterations, prepData);
        emit HopStarted(prepData.hopId, effectiveMaker, prepData.indices.length);
        nextHopId++;
        return prepData.hopId;
    }

    function prepStalls() internal returns (StallData[] memory) {
        // Prepares stalled hop data for a user
        uint256[] storage userHops = hopsByAddress[msg.sender];
        StallData[] memory stalls = new StallData[](userHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userHops.length && count < 20; i++) {
            StalledHop storage stalledHop = hopID[userHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
                stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0
            );
            stalls[count] = StallData({
                hopId: userHops[i],
                listing: stalledHop.currentListing,
                orderId: stalledHop.orderID,
                isBuy: stalledHop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status,
                amountSent: amountSent,
                hopMaker: stalledHop.hopMaker
            });
            count++;
        }

        StallData[] memory resizedStalls = new StallData[](count);
        for (uint256 i = 0; i < count; i++) {
            resizedStalls[i] = stalls[i];
        }
        emit StallsPrepared(count > 0 ? resizedStalls[0].hopId : 0, count);
        return resizedStalls;
    }

    function prepAllStalls() internal returns (StallData[] memory) {
        // Prepares stalled hop data globally
        StallData[] memory stalls = new StallData[](totalHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < totalHops.length && count < 20; i++) {
            StalledHop storage stalledHop = hopID[totalHops[i]];
            if (stalledHop.hopStatus != 1) continue;
            (uint256 pending, uint256 filled, uint8 status, uint256 amountSent) = checkOrderStatus(
                stalledHop.currentListing, stalledHop.orderID, stalledHop.maxPrice > 0
            );
            stalls[count] = StallData({
                hopId: totalHops[i],
                listing: stalledHop.currentListing,
                orderId: stalledHop.orderID,
                isBuy: stalledHop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status,
                amountSent: amountSent,
                hopMaker: stalledHop.hopMaker
            });
            count++;
        }

        StallData[] memory resizedStalls = new StallData[](count);
        for (uint256 i = 0; i < count; i++) {
            resizedStalls[i] = stalls[i];
        }
        emit StallsPrepared(count > 0 ? resizedStalls[0].hopId : 0, count);
        return resizedStalls;
    }

    function processStallStep(
        StallExecutionData memory execData,
        address startToken,
        address sender
    ) internal returns (bool completed, uint256 orderId, uint256 amountSent) {
        // Processes a single stall step, creating and settling an order
        OrderUpdateData memory orderData = OrderUpdateData({
            listing: execData.listing,
            recipient: execData.recipient,
            inputAmount: normalizeForToken(execData.principal, startToken),
            priceLimit: execData.priceLimit,
            inputToken: startToken
        });
        orderId = _createHopOrder(orderData, sender);
        safeSettle(execData.listing, execData.isBuy, execData.settleType, execData.maxIterations);
        (uint256 pending, uint256 filled, uint8 status, uint256 receivedAmount) = checkOrderStatus(execData.listing, orderId, execData.isBuy);
        completed = status == 3 && pending == 0;
        amountSent = receivedAmount;
    }

    function executeStalls(StallData[] memory stalls) internal {
        // Executes stalled hops, advancing or completing them
        uint256 count = 0;
        for (uint256 i = 0; i < stalls.length; i++) {
            StalledHop storage stalledHop = hopID[stalls[i].hopId];
            if (stalledHop.hopStatus != 1 || stalls[i].pending > 0 || stalls[i].status != 3) continue;
            count++;
            uint256 nextStage = uint256(stalledHop.stage) + 1;
            if (nextStage >= stalledHop.remainingListings.length + uint256(stalledHop.stage) + 1) {
                stalledHop.hopStatus = 2;
                totalHops.push(stalls[i].hopId);
                emit HopContinued(stalls[i].hopId, uint8(nextStage));
                continue;
            }

            bool isBuy = stalledHop.remainingListings.length > 0 && stalledHop.endToken == ISSListing(stalledHop.remainingListings[0]).tokenA();
            uint256 priceLimit = _validatePriceImpact(stalledHop.remainingListings[0], stalls[i].amountSent, isBuy, 500);
            HopUpdateType[] memory hopUpdates = new HopUpdateType[](4);
            setOrderStatus(hopUpdates, 0);
            setOrderAmount(hopUpdates, 1, isBuy ? "buyAmount" : "sellAmount", normalizeForToken(stalls[i].amountSent, stalledHop.startToken));
            setOrderPrice(hopUpdates, 2, isBuy ? "buyPrice" : "sellPrice", priceLimit);
            setOrderRecipient(hopUpdates, 3, stalledHop.hopMaker);
            ISSListing.UpdateType[] memory updates = new ISSListing.UpdateType[](hopUpdates.length);
            for (uint256 j = 0; j < hopUpdates.length; j++) {
                updates[j] = ISSListing.UpdateType({
                    field: hopUpdates[j].field,
                    value: hopUpdates[j].value
                });
            }
            StallExecutionData memory execData = StallExecutionData({
                listing: stalledHop.remainingListings[0],
                isBuy: isBuy,
                recipient: stalledHop.hopMaker,
                priceLimit: priceLimit,
                principal: stalls[i].amountSent,
                settleType: stalledHop.settleType,
                maxIterations: stalledHop.maxIterations,
                updates: hopUpdates
            });

            (bool completed, uint256 orderId, uint256 amountSent) = processStallStep(execData, stalledHop.startToken, stalledHop.hopMaker);
            if (!completed) {
                stalledHop.currentListing = execData.listing;
                stalledHop.orderID = orderId;
                stalledHop.stage = uint8(nextStage);
                stalledHop.principalAmount = amountSent;
                address[] memory newRemaining = new address[](stalledHop.remainingListings.length - 1);
                for (uint256 j = 1; j < stalledHop.remainingListings.length; j++) {
                    newRemaining[j - 1] = stalledHop.remainingListings[j];
                }
                stalledHop.remainingListings = newRemaining;
            } else {
                stalledHop.hopStatus = 2;
                totalHops.push(stalls[i].hopId);
            }
            emit HopContinued(stalls[i].hopId, uint8(nextStage));

            uint256[] storage userHops = hopsByAddress[stalls[i].hopMaker];
            if (stalledHop.hopStatus == 2) {
                for (uint256 j = userHops.length; j > 0; j--) {
                    if (userHops[j - 1] == stalls[i].hopId) {
                        userHops[j - 1] = userHops[userHops.length - 1];
                        userHops.pop();
                        break;
                    }
                }
            }
        }

        emit StallsExecuted(count > 0 ? stalls[0].hopId : 0, count);
    }

    function executeHops(uint256 maxIterations) external nonReentrant {
        // Processes all stalled hops globally up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 iterations = 0;
        while (iterations < maxIterations) {
            StallData[] memory stalls = prepAllStalls();
            if (stalls.length == 0) break;
            executeStalls(stalls);
            iterations++;
        }
    }
    
    function cancelHop(uint256 hopId) external nonReentrant {
        // External function to cancel a specific hop
        _cancelHop(hopId);
    }

    function cancelAll(uint256 maxIterations) external nonReentrant {
        // Cancels all stalled hops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256[] storage userHops = hopsByAddress[msg.sender];
        uint256 canceled = 0;

        for (uint256 i = userHops.length; i > 0 && canceled < maxIterations; i--) {
            uint256 hopId = userHops[i - 1];
            StalledHop storage stalledHop = hopID[hopId];
            if (stalledHop.hopStatus == 1) {
                _cancelHop(hopId);
                canceled++;
            }
        }
        emit AllHopsCanceled(msg.sender, canceled);
    }

    function continueHop(uint256 maxIterations) external nonReentrant {
        // Continues stalled hops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 iterations = 0;
        while (iterations < maxIterations) {
            StallData[] memory stalls = prepStalls();
            if (stalls.length == 0) break;
            executeStalls(stalls);
            iterations++;
        }
    }
}