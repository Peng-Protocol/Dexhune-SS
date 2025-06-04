/* SPDX-License-Identifier: BSD-3-Clause */
pragma solidity ^0.8.1;

// Version 0.0.17:
// - Fixed TypeError in prepareExecution by removing view modifier and refactoring to avoid state modifications in view context.
// - Split processActiveActions logic into non-view processActiveActionsInternal to handle state updates incrementally using pendingActions mapping.
// - Removed state writes from prepareActiveBase, validateActiveStatus, checkActiveConditions, and introduced computeActiveAction for pure computation.
// - Ensured compatibility with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSIsolatedDriver.sol v0.0.15.
// - v0.0.16:
//   - Fixed TypeError in prepareClosePrice by correcting comparison: changed 'close.positionId == address(this)' to 'close.positionId == positionId'.
//   - Refactored processActiveActions to reduce stack depth with modular helpers.

import "./SSDPositionPartial.sol";

contract SSDExecutionPartial is SSDPositionPartial {
    using SafeERC20 for IERC20;

    // Internal struct for close params
    struct CloseParams {
        uint256 currentPrice;
        uint256 payout;
        uint8 decimals;
    }

    // Temporary storage for close operations
    struct PendingClose {
        uint256 positionId;
        uint256 currentPrice;
        uint256 payout;
        uint8 decimals;
        address listingAddress;
        address makerAddress;
        uint8 positionType;
    }

    // Temporary storage for action processing
    struct PendingAction {
        uint256 positionId;
        uint8 positionType;
        address listingAddress;
        bool isValid;
        uint8 actionType;
    }

    // Temporary storage mapping
    mapping(uint256 => PendingClose) internal pendingCloses;
    mapping(uint256 => PendingAction) internal pendingActions;

    // Helper: Get current price
    function getCurrentPrice(address listingAddress) internal view returns (uint256) {
        return ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
    }

    // Helper: Fetch position data for close
    function fetchPositionData(
        uint256 positionId
    ) internal view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory priceParamsLocal,
        MarginParams memory marginParamsLocal,
        LeverageParams memory leverageParamsLocal,
        RiskParams memory riskParamsLocal
    ) {
        coreBase = positionCoreBase[positionId];
        coreStatus = positionCoreStatus[positionId];
        priceParamsLocal = priceParams[positionId];
        marginParamsLocal = marginParams[positionId];
        leverageParamsLocal = leverageParams[positionId];
        riskParamsLocal = riskParams[positionId];
    }

    // Helper: Validate position status
    function validatePositionStatus(
        PositionCoreStatus memory coreStatus
    ) internal pure {
        require(coreStatus.status2 == 0, "Position not open");
        require(coreStatus.status1 == true, "Position not executable");
    }

    // Helper: Compute long payout
    function computeLongPayout(
        ClosePositionMargin memory closeMargin,
        LeverageParams memory leverageParams,
        uint256 currentPrice
    ) internal pure returns (uint256) {
        uint256 totalValue = closeMargin.taxedMargin + closeMargin.excessMargin + leverageParams.leverageAmount;
        return currentPrice > 0 && totalValue > leverageParams.loanInitial ? (totalValue / currentPrice) - leverageParams.loanInitial : 0;
    }

    // Helper: Compute short payout
    function computeShortPayout(
        ClosePositionMargin memory closeMargin,
        PriceParams memory priceParamsLocal,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        uint256 currentPrice
    ) internal pure returns (uint256) {
        uint256 priceDiff = priceParamsLocal.priceMin > currentPrice ? priceParamsLocal.priceMin - currentPrice : 0;
        uint256 profit = (priceDiff * marginParams.marginInitial * leverageParams.leverageVal);
        uint256 marginReturn = (closeMargin.taxedMargin + closeMargin.excessMargin) * currentPrice;
        return profit + marginReturn;
    }

    // Helper: Process pending position
    function processPendingPosition(
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory priceParams,
        uint256 currentPrice
    ) internal pure returns (PositionAction memory action) {
        action.positionId = coreBase.positionId;
        action.actionType = 255; // No action
        if (!coreStatus.status1 && coreStatus.status2 == 0) {
            if (currentPrice >= priceParams.priceMin && currentPrice <= priceParams.priceMax) {
                action.actionType = 0; // Update status
            }
        }
    }

    // Helper: Compute active action (pure)
    function computeActiveAction(
        uint256 positionId,
        uint8 positionType,
        uint256 currentPrice,
        address listingAddress
    ) internal view returns (PositionAction memory action) {
        action.positionId = positionId;
        action.actionType = 255; // No action
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        if (!coreStatus.status1 || coreStatus.status2 != 0 || coreBase.listingAddress != listingAddress) {
            return action;
        }
        PriceParams memory priceParams = priceParams[positionId];
        RiskParams memory riskParams = riskParams[positionId];
        bool shouldClose = false;
        if (positionType == 0) { // Long
            if (riskParams.priceStopLoss > 0 && currentPrice <= riskParams.priceStopLoss) shouldClose = true;
            else if (riskParams.priceTakeProfit > 0 && currentPrice >= riskParams.priceTakeProfit) shouldClose = true;
            else if (currentPrice <= riskParams.priceLiquidation) shouldClose = true;
        } else { // Short
            if (riskParams.priceStopLoss > 0 && currentPrice >= riskParams.priceStopLoss) shouldClose = true;
            else if (riskParams.priceTakeProfit > 0 && currentPrice <= riskParams.priceTakeProfit) shouldClose = true;
            else if (currentPrice >= riskParams.priceLiquidation) shouldClose = true;
        }
        if (shouldClose) {
            action.actionType = 1; // Close
        }
    }

    // Helper: Store active action
    function storeActiveAction(
        PositionAction memory action,
        PositionAction[] memory tempActions,
        uint256 actionCount
    ) internal {
        if (action.actionType != 255) {
            tempActions[actionCount] = action;
        }
    }

    // Helper: Process active actions (state-modifying)
    function processActiveActionsInternal(
        ExecutionContextBase memory contextBase,
        ExecutionContextCounts memory contextCounts,
        uint8 positionType,
        PositionAction[] memory tempActions
    ) internal {
        uint256[] memory active = positionsByType[positionType];
        for (uint256 i = 0; i < active.length; i++) {
            if (gasleft() < 100000) break;
            PositionAction memory action = computeActiveAction(active[i], positionType, contextBase.currentPrice, contextBase.listingAddress);
            storeActiveAction(action, tempActions, contextCounts.actionCount);
            if (action.actionType != 255) {
                contextCounts.actionCount++;
            }
        }
    }

    // Helper: Process pending actions
    function processPendingActions(
        ExecutionContextBase memory contextBase,
        ExecutionContextCounts memory contextCounts,
        uint8 positionType,
        PositionAction[] memory tempActions
    ) internal view returns (uint256) {
        uint256[] memory pending = pendingPositions[contextBase.listingAddress][positionType];
        for (uint256 i = 0; i < pending.length; i++) {
            if (gasleft() < 100000) break;
            PositionCoreBase memory coreBase = positionCoreBase[pending[i]];
            PositionCoreStatus memory coreStatus = positionCoreStatus[pending[i]];
            PriceParams memory priceParams = priceParams[pending[i]];
            PositionAction memory action = processPendingPosition(coreBase, coreStatus, priceParams, contextBase.currentPrice);
            if (action.actionType != 255) {
                tempActions[contextCounts.actionCount] = action;
                contextCounts.actionCount++;
            }
        }
        return contextCounts.actionCount;
    }

    // Helper: Finalize actions
    function finalizeActions(
        PositionAction[] memory tempActions,
        uint256 actionCount
    ) internal pure returns (PositionAction[] memory actions) {
        actions = new PositionAction[](actionCount);
        for (uint256 i = 0; i < actionCount; i++) {
            actions[i] = tempActions[i];
        }
    }

    // Prepare execution
    function prepareExecution(
        address listingAddress
    ) internal returns (PositionAction[] memory actions) {
        ExecutionContextBase memory contextBase = ExecutionContextBase({
            listingAddress: listingAddress,
            driver: address(this),
            currentPrice: getCurrentPrice(listingAddress)
        });
        ExecutionContextCounts memory contextCounts = ExecutionContextCounts({
            actionCount: 0,
            maxActions: 0
        });
        PositionAction[] memory tempActions = new PositionAction[](pendingPositions[listingAddress][0].length + pendingPositions[listingAddress][1].length + positionsByType[0].length + positionsByType[1].length);

        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            contextCounts.actionCount = processPendingActions(contextBase, contextCounts, positionType, tempActions);
        }
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            processActiveActionsInternal(contextBase, contextCounts, positionType, tempActions);
        }

        actions = finalizeActions(tempActions, contextCounts.actionCount);
    }

    // Helper: Update position status
    function updatePositionStatusHelper(
        uint256 positionId,
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus
    ) internal returns (bool) {
        coreStatus.status1 = true;
        updatePositionCore(positionId, coreBase, coreStatus);
        return true;
    }

    // Helper: Prepare close base data
    function prepareCloseBase(
        ClosePositionBase memory closeBase
    ) internal returns (uint256 positionId) {
        positionId = closeBase.positionId;
        pendingCloses[positionId] = PendingClose({
            positionId: positionId,
            currentPrice: 0,
            payout: 0,
            decimals: 0,
            listingAddress: closeBase.listingAddress,
            makerAddress: closeBase.makerAddress,
            positionType: 0
        });
        (PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus,,,,) = fetchPositionData(positionId);
        validatePositionStatus(coreStatus);
        pendingCloses[positionId].positionType = coreBase.positionType;
        return positionId;
    }

    // Helper: Prepare close price data
    function prepareClosePrice(
        uint256 positionId
    ) internal {
        PendingClose storage close = pendingCloses[positionId];
        require(close.positionId == positionId, "Invalid position ID");
        close.currentPrice = ISSListing(close.listingAddress).prices(uint256(uint160(close.listingAddress)));
        close.decimals = close.positionType == 0
            ? ISSListing(close.listingAddress).decimalsB()
            : ISSListing(close.listingAddress).decimalsA();
    }

    // Helper: Prepare close payout
    function prepareClosePayout(
        uint256 positionId,
        ClosePositionMargin memory closeMargin
    ) internal {
        PendingClose storage close = pendingCloses[positionId];
        require(close.positionId == positionId, "Invalid position ID");
        (,, PriceParams memory priceParamsLocal, MarginParams memory marginParamsLocal, LeverageParams memory leverageParamsLocal, RiskParams memory riskParamsLocal) = fetchPositionData(positionId);
        close.payout = close.positionType == 0
            ? computeLongPayout(closeMargin, leverageParamsLocal, close.currentPrice)
            : computeShortPayout(closeMargin, priceParamsLocal, marginParamsLocal, leverageParamsLocal, close.currentPrice);
    }

    // Helper: Denormalize payout
    function denormalizePayout(uint256 payout, uint8 decimals) internal pure returns (uint256) {
        if (decimals != 18) {
            if (decimals < 18) {
                return payout / (10 ** (uint256(18) - uint256(decimals)));
            } else {
                return payout * (10 ** (uint256(decimals) - uint256(18)));
            }
        }
        return payout;
    }

    // Helper: Finalize close
    function finalizeClose(
        ClosePositionBase memory closeBase,
        ClosePositionMargin memory closeMargin,
        uint8 positionType,
        uint256 payout
    ) internal {
        positionCoreStatus[closeBase.positionId].status2 = 1;

        if (payout > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: closeBase.makerAddress,
                required: payout,
                payoutType: positionType
            });
            ISSListing(closeBase.listingAddress).ssUpdate(address(this), updates);
        }

        uint256 io = closeMargin.taxedMargin + closeMargin.excessMargin;
        longIOByHeight[historicalInterestHeight] -= positionType == 0 ? io : 0;
        shortIOByHeight[historicalInterestHeight] -= positionType == 1 ? io : 0;
    }

    // Internal Helper: Close long position
    function internalCloseLongPosition(
        ClosePositionBase memory closeBase,
        ClosePositionMargin memory closeMargin,
        LongCloseParams memory longParams
    ) internal returns (uint256 payout) {
        uint256 positionId = prepareCloseBase(closeBase);
        prepareClosePrice(positionId);
        prepareClosePayout(positionId, closeMargin);
        PendingClose storage close = pendingCloses[positionId];
        payout = denormalizePayout(close.payout, close.decimals);
        finalizeClose(closeBase, closeMargin, 0, payout);
        delete pendingCloses[positionId];
    }

    // Internal Helper: Close short position
    function internalCloseShortPosition(
        ClosePositionBase memory closeBase,
        ClosePositionMargin memory closeMargin,
        ShortCloseParams memory shortParams
    ) internal returns (uint256 payout) {
        uint256 positionId = prepareCloseBase(closeBase);
        prepareClosePrice(positionId);
        prepareClosePayout(positionId, closeMargin);
        PendingClose storage close = pendingCloses[positionId];
        payout = denormalizePayout(close.payout, close.decimals);
        finalizeClose(closeBase, closeMargin, 1, payout);
        delete pendingCloses[positionId];
    }

    // Internal Helper: Cancel position
    function internalCancelPosition(
        ClosePositionBase memory closeBase,
        ClosePositionMargin memory closeMargin,
        uint8 positionType
    ) internal {
        PositionCoreStatus memory coreStatus = positionCoreStatus[closeBase.positionId];
        require(!coreStatus.status1, "Position executable");
        require(coreStatus.status2 == 0, "Position not open");

        uint256 totalMargin = closeMargin.taxedMargin + closeMargin.excessMargin;
        if (totalMargin > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: closeBase.makerAddress,
                required: totalMargin,
                payoutType: positionType
            });
            ISSListing(closeBase.listingAddress).ssUpdate(address(this), updates);
        }

        positionCoreStatus[closeBase.positionId].status2 = 2;

        uint256 io = closeMargin.taxedMargin + closeMargin.excessMargin;
        longIOByHeight[historicalInterestHeight] -= positionType == 0 ? io : 0;
        shortIOByHeight[historicalInterestHeight] -= positionType == 1 ? io : 0;
    }

    // Execute close position
    function executeClosePosition(
        PositionAction memory action,
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        ExecutionContextBase memory contextBase
    ) internal {
        ClosePositionBase memory closeBase = ClosePositionBase({
            positionId: action.positionId,
            listingAddress: coreBase.listingAddress,
            makerAddress: coreBase.makerAddress,
            driver: address(this)
        });
        ClosePositionMargin memory closeMargin = ClosePositionMargin({
            taxedMargin: marginParams[action.positionId].marginTaxed,
            excessMargin: marginParams[action.positionId].marginExcess
        });
        if (coreBase.positionType == 0) {
            LongCloseParams memory longParams = LongCloseParams({
                leverageAmount: leverageParams[action.positionId].leverageAmount,
                loanInitial: leverageParams[action.positionId].loanInitial
            });
            internalCloseLongPosition(closeBase, closeMargin, longParams);
        } else {
            ShortCloseParams memory shortParams = ShortCloseParams({
                minPrice: priceParams[action.positionId].priceMin,
                initialMargin: marginParams[action.positionId].marginInitial,
                leverage: leverageParams[action.positionId].leverageVal
            });
            internalCloseShortPosition(closeBase, closeMargin, shortParams);
        }
    }

    // Execute positions
    function executePositions(
        PositionAction[] memory actions,
        address listingAddress
    ) internal returns (uint256 resultCount) {
        resultCount = 0;
        ExecutionContextBase memory contextBase = ExecutionContextBase({
            listingAddress: listingAddress,
            driver: address(this),
            currentPrice: 0
        });

        for (uint256 i = 0; i < actions.length; i++) {
            PositionCoreBase memory coreBase = positionCoreBase[actions[i].positionId];
            PositionCoreStatus memory coreStatus = positionCoreStatus[actions[i].positionId];
            if (actions[i].actionType == 0) {
                if (updatePositionStatusHelper(actions[i].positionId, coreBase, coreStatus)) {
                    resultCount++;
                }
            } else if (actions[i].actionType == 1) {
                executeClosePosition(actions[i], coreBase, coreStatus, contextBase);
                resultCount++;
            }
        }
    }

    // Add excess margin
    function addExcessMarginInternal(
        uint256 positionId,
        uint256 amount,
        address token,
        address listingAddress,
        uint8 positionType,
        uint256 normalizedAmount
    ) internal {
        require(normalizedAmount <= leverageParams[positionId].leverageAmount, "Excess margin exceeds leverage");
        marginParams[positionId].marginExcess += normalizedAmount;
        transferMarginToListing(listingAddress, normalizedAmount, positionType);
        updateHistoricalInterest(
            historicalInterestHeight,
            positionType == 0 ? normalizedAmount : 0,
            positionType == 1 ? normalizedAmount : 0,
            block.timestamp
        );
    }

    // Update stop loss
    function updateSLInternal(
        uint256 positionId,
        uint256 newStopLossPrice
    ) internal {
        riskParams[positionId].priceStopLoss = newStopLossPrice;
    }

    // Update take profit
    function updateTPInternal(
        uint256 positionId,
        uint256 newTakeProfitPrice
    ) internal {
        riskParams[positionId].priceTakeProfit = newTakeProfitPrice;
    }

    // Close all short
    function closeAllShortInternal(address user, uint256 maxIterations) internal returns (uint256 count) {
        count = 0;
        uint256[] memory positions = positionsByType[1];
        for (uint256 i = 0; i < positions.length && count < maxIterations; i++) {
            PositionCoreBase memory coreBase = positionCoreBase[positions[i]];
            PositionCoreStatus memory coreStatus = positionCoreStatus[positions[i]];
            MarginParams memory marginParams = marginParams[positions[i]];
            PriceParams memory priceParams = priceParams[positions[i]];
            LeverageParams memory leverageParams = leverageParams[positions[i]];
            if (coreBase.makerAddress == user && coreStatus.status2 == 0 && coreStatus.status1 == true) {
                ClosePositionBase memory closeBase = ClosePositionBase({
                    positionId: positions[i],
                    listingAddress: coreBase.listingAddress,
                    makerAddress: coreBase.makerAddress,
                    driver: address(this)
                });
                ClosePositionMargin memory closeMargin = ClosePositionMargin({
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess
                });
                ShortCloseParams memory shortParams = ShortCloseParams({
                    minPrice: priceParams.priceMin,
                    initialMargin: marginParams.marginInitial,
                    leverage: leverageParams.leverageVal
                });
                internalCloseShortPosition(closeBase, closeMargin, shortParams);
                count++;
            }
        }
    }

    // Cancel all short
    function cancelAllShortInternal(address user, uint256 maxIterations) internal returns (uint256 count) {
        count = 0;
        uint256[] memory positions = pendingPositions[user][1];
        for (uint256 i = 0; i < positions.length && count < maxIterations; i++) {
            PositionCoreBase memory coreBase = positionCoreBase[positions[i]];
            PositionCoreStatus memory coreStatus = positionCoreStatus[positions[i]];
            MarginParams memory marginParams = marginParams[positions[i]];
            if (coreBase.makerAddress == user && !coreStatus.status1 && coreStatus.status2 == 0) {
                ClosePositionBase memory closeBase = ClosePositionBase({
                    positionId: positions[i],
                    listingAddress: coreBase.listingAddress,
                    makerAddress: coreBase.makerAddress,
                    driver: address(this)
                });
                ClosePositionMargin memory closeMargin = ClosePositionMargin({
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess
                });
                internalCancelPosition(closeBase, closeMargin, coreBase.positionType);
                count++;
            }
        }
    }

    // Close all longs
    function closeAllLongsInternal(address user, uint256 maxIterations) internal returns (uint256 count) {
        count = 0;
        uint256[] memory positions = positionsByType[0];
        for (uint256 i = 0; i < positions.length && count < maxIterations; i++) {
            PositionCoreBase memory coreBase = positionCoreBase[positions[i]];
            PositionCoreStatus memory coreStatus = positionCoreStatus[positions[i]];
            MarginParams memory marginParams = marginParams[positions[i]];
            LeverageParams memory leverageParams = leverageParams[positions[i]];
            if (coreBase.makerAddress == user && coreStatus.status2 == 0 && coreStatus.status1 == true) {
                ClosePositionBase memory closeBase = ClosePositionBase({
                    positionId: positions[i],
                    listingAddress: coreBase.listingAddress,
                    makerAddress: coreBase.makerAddress,
                    driver: address(this)
                });
                ClosePositionMargin memory closeMargin = ClosePositionMargin({
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess
                });
                LongCloseParams memory longParams = LongCloseParams({
                    leverageAmount: leverageParams.leverageAmount,
                    loanInitial: leverageParams.leverageVal
                });
                internalCloseLongPosition(closeBase, closeMargin, longParams);
                count++;
            }
        }
    }

    // Cancel all long
    function cancelAllLongInternal(
        address user,
        uint256 maxIterations
    ) internal returns (uint256 count) {
        count = 0;
        uint256[] memory positions = pendingPositions[user][0];
        for (uint256 i = 0; i < positions.length && i < maxIterations; i++) {
            PositionCoreBase memory coreBase = positionCoreBase[positions[i]];
            PositionCoreStatus memory coreStatus = positionCoreStatus[positions[i]];
            MarginParams memory marginParams = marginParams[positions[i]];
            if (coreBase.makerAddress == user && !coreStatus.status1 && coreStatus.status2 == 0) {
                ClosePositionBase memory closeBase = ClosePositionBase({
                    positionId: positions[i],
                    listingAddress: coreBase.listingAddress,
                    makerAddress: coreBase.makerAddress,
                    driver: address(this)
                });
                ClosePositionMargin memory closeMargin = ClosePositionMargin({
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess
                });
                internalCancelPosition(closeBase, closeMargin, coreBase.positionType);
                count++;
            }
        }
        return count;
    }
}