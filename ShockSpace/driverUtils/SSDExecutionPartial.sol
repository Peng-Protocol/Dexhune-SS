// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.6:
// - Removed unnecessary 'this.' prefix from inherited mapping accesses in prepareCloseLong, prepareCloseShort, and other functions.
// - Split prepareCloseLong and prepareCloseShort into smaller helper functions to address stack depth concerns.
// - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.3, SSIsolatedDriver.sol v0.0.2.

import "./SSDPositionPartial.sol";

contract SSDExecutionPartial is SSDPositionPartial {
    using SafeERC20 for IERC20;

    // Internal struct for close params
    struct CloseParams {
        uint256 currentPrice;
        uint256 payout;
        uint8 decimals;
    }

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
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams
    ) {
        coreBase = positionCoreBase[positionId];
        coreStatus = positionCoreStatus[positionId];
        priceParamsLocal = priceParams[positionId];
        marginParams = marginParams[positionId];
        leverageParams = leverageParams[positionId];
        riskParams = riskParams[positionId];
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

    // Helper: Process active position
    function processActivePosition(
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory priceParams,
        RiskParams memory riskParams,
        uint256 currentPrice,
        address listingAddress
    ) internal pure returns (PositionAction memory action) {
        action.positionId = coreBase.positionId;
        action.actionType = 255; // No action
        if (coreStatus.status1 && coreStatus.status2 == 0 && coreBase.listingAddress == listingAddress) {
            bool shouldClose = false;
            if (coreBase.positionType == 0) { // Long
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

    // Helper: Process active actions
    function processActiveActions(
        ExecutionContextBase memory contextBase,
        ExecutionContextCounts memory contextCounts,
        uint8 positionType,
        PositionAction[] memory tempActions
    ) internal view returns (uint256) {
        uint256[] memory active = positionsByType[positionType];
        for (uint256 i = 0; i < active.length; i++) {
            if (gasleft() < 100000) break;
            PositionCoreBase memory coreBase = positionCoreBase[active[i]];
            PositionCoreStatus memory coreStatus = positionCoreStatus[active[i]];
            PriceParams memory priceParams = priceParams[active[i]];
            RiskParams memory riskParams = riskParams[active[i]];
            PositionAction memory action = processActivePosition(coreBase, coreStatus, priceParams, riskParams, contextBase.currentPrice, contextBase.listingAddress);
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
    ) internal view returns (PositionAction[] memory actions) {
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
            contextCounts.actionCount = processActiveActions(contextBase, contextCounts, positionType, tempActions);
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

    // Helper: Prepare closeLong
    function prepareCloseLong(
        ClosePositionBase memory closeBase,
        ClosePositionMargin memory closeMargin
    ) internal view returns (
        CloseParams memory closeParams,
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory priceParamsLocal,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams
    ) {
        (coreBase, coreStatus, priceParamsLocal, marginParams, leverageParams, riskParams) = fetchPositionData(closeBase.positionId);
        validatePositionStatus(coreStatus);

        closeParams.currentPrice = ISSListing(closeBase.listingAddress).prices(uint256(uint160(closeBase.listingAddress)));
        closeParams.payout = computeLongPayout(closeMargin, leverageParams, closeParams.currentPrice);
        closeParams.decimals = ISSListing(closeBase.listingAddress).decimalsB();
    }

    // Helper: Prepare closeShort
    function prepareCloseShort(
        ClosePositionBase memory closeBase,
        ClosePositionMargin memory closeMargin
    ) internal view returns (
        CloseParams memory closeParams,
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory priceParamsLocal,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams
    ) {
        (coreBase, coreStatus, priceParamsLocal, marginParams, leverageParams, riskParams) = fetchPositionData(closeBase.positionId);
        validatePositionStatus(coreStatus);

        closeParams.currentPrice = ISSListing(closeBase.listingAddress).prices(uint256(uint160(closeBase.listingAddress)));
        closeParams.payout = computeShortPayout(closeMargin, priceParamsLocal, marginParams, leverageParams, closeParams.currentPrice);
        closeParams.decimals = ISSListing(closeBase.listingAddress).decimalsA();
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
        CloseParams memory closeParams;
        PositionCoreBase memory coreBase;
        PositionCoreStatus memory coreStatus;
        PriceParams memory priceParamsLocal;
        MarginParams memory marginParams;
        LeverageParams memory leverageParams;
        RiskParams memory riskParams;
        (closeParams, coreBase, coreStatus, priceParamsLocal, marginParams, leverageParams, riskParams) = prepareCloseLong(closeBase, closeMargin);

        payout = denormalizePayout(closeParams.payout, closeParams.decimals);
        finalizeClose(closeBase, closeMargin, 0, payout);
    }

    // Internal Helper: Close short position
    function internalCloseShortPosition(
        ClosePositionBase memory closeBase,
        ClosePositionMargin memory closeMargin,
        ShortCloseParams memory shortParams
    ) internal returns (uint256 payout) {
        CloseParams memory closeParams;
        PositionCoreBase memory coreBase;
        PositionCoreStatus memory coreStatus;
        PriceParams memory priceParamsLocal;
        MarginParams memory marginParams;
        LeverageParams memory leverageParams;
        RiskParams memory riskParams;
        (closeParams, coreBase, coreStatus, priceParamsLocal, marginParams, leverageParams, riskParams) = prepareCloseShort(closeBase, closeMargin);

        payout = denormalizePayout(closeParams.payout, closeParams.decimals);
        finalizeClose(closeBase, closeMargin, 1, payout);
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
                    loanInitial: leverageParams.loanInitial
                });
                internalCloseLongPosition(closeBase, closeMargin, longParams);
                count++;
            }
        }
    }

    // Cancel all long
    function cancelAllLongInternal(address user, uint256 maxIterations) internal returns (uint256 count) {
        count = 0;
        uint256[] memory positions = pendingPositions[user][0];
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
}