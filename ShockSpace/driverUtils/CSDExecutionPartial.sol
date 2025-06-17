/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-06-17: Fixed TypeError by accessing initialMargin from marginParams1 instead of price1 in _updateLiquidationPrices. Version incremented to 0.0.20.
// - 2025-06-17: Modified _updateLiquidationPrices to derive margin token using positionType and listingAddress, removing positionToken dependency. Updated _processPendingPosition and _processActivePosition calls accordingly. Version incremented to 0.0.19.
// - 2025-06-17: Added _updateLiquidationPrices to recalculate liquidation price for a single position. Modified _processPendingPosition and _processActivePosition to call _updateLiquidationPrices before liquidation checks. Version incremented to 0.0.18.
// - 2025-06-16: Replaced parseEntryPrice with _parseEntryPriceInternal at lines 87 and 102 to resolve DeclarationError. Updated Solidity version to ^0.8.2. Version incremented to 0.0.17.
// - 2025-06-13: Renamed executePositions to _executePositions as internal helper, added external executePositions wrapper. Version incremented to 0.0.16.
// - 2025-06-13: Changed executePositions visibility to external virtual. Version incremented to 0.0.15.
// - 2025-06-13: Confirmed PositionClosed emission via CSDUtilityPartial.sol. Version incremented to 0.0.14.

pragma solidity ^0.8.2;

import "./CSDPositionPartial.sol";

contract CSDExecutionPartial is CSDPositionPartial {
    using SafeERC20 for IERC20;

    // Updates liquidation price for a specific position based on current margin
    function _updateLiquidationPrices(
        uint256 positionId,
        address maker,
        uint8 positionType,
        address listingAddress
    ) internal {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        
        // Skip invalid or closed positions
        if (core1.positionId != positionId || core2.status2 != 0) {
            return;
        }

        PriceParams1 storage price1 = priceParams1[positionId];
        PriceParams2 storage price2 = priceParams2[positionId];
        MarginParams1 storage margin1 = marginParams1[positionId]; // Access MarginParams1 for initialMargin

        // Compute new liquidation price based on position type
        uint256 newLiquidationPrice;
        if (positionType == 0) {
            // Long position: use tokenA for margin, compute liquidation price
            address tokenA = ISSListing(listingAddress).tokenA();
            (, newLiquidationPrice) = _computeLoanAndLiquidationLong(
                uint256(price1.leverage) * margin1.initialMargin, // Use margin1.initialMargin
                price1.minEntryPrice,
                maker,
                tokenA
            );
        } else {
            // Short position: use tokenB for margin, compute liquidation price
            address tokenB = ISSListing(listingAddress).tokenB();
            (, newLiquidationPrice) = _computeLoanAndLiquidationShort(
                uint256(price1.leverage) * margin1.initialMargin, // Use margin1.initialMargin
                price1.minEntryPrice,
                maker,
                tokenB
            );
        }

        // Update liquidation price in storage
        price2.liquidationPrice = newLiquidationPrice;
    }

    function _processPendingPosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256[] storage pending,
        uint256 i,
        uint256 currentPrice
    ) internal returns (bool continueLoop) {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        PriceParams1 storage price1 = priceParams1[positionId];
        PriceParams2 storage price2 = priceParams2[positionId];
        ExitParams storage exit = exitParams[positionId];

        // Update liquidation price before checking conditions
        _updateLiquidationPrices(positionId, core1.makerAddress, positionType, listingAddress);

        bool shouldLiquidate = positionType == 0 ? currentPrice <= price2.liquidationPrice : currentPrice >= price2.liquidationPrice;

        if (shouldLiquidate) {
            uint256 payout = positionType == 0 ? prepCloseLong(positionId, listingAddress) : prepCloseShort(positionId, listingAddress);
            removePositionIndex(positionId, positionType, listingAddress);
            emit PositionClosed(positionId, core1.makerAddress, payout);
            pending[i] = pending[pending.length - 1];
            pending.pop();
            return true;
        } else if (currentPrice >= price1.minEntryPrice && currentPrice <= price1.maxEntryPrice) {
            core2.status1 = true;
            positionsByType[positionType].push(positionId);
            pending[i] = pending[pending.length - 1];
            pending.pop();
            return true;
        }
        return false;
    }

    function _processActivePosition(
        uint256 positionId,
        uint8 positionType,
        address listingAddress,
        uint256[] storage active,
        uint256 i,
        uint256 currentPrice
    ) internal returns (bool continueLoop) {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        PriceParams2 storage price2 = priceParams2[positionId];
        ExitParams storage exit = exitParams[positionId];

        // Update liquidation price before checking conditions
        _updateLiquidationPrices(positionId, core1.makerAddress, positionType, listingAddress);

        bool shouldLiquidate = positionType == 0 ? currentPrice <= price2.liquidationPrice : currentPrice >= price2.liquidationPrice;
        bool shouldCloseSL = exit.stopLossPrice > 0 && (positionType == 0 ? currentPrice <= exit.stopLossPrice : currentPrice >= exit.stopLossPrice);
        bool shouldCloseTP = exit.takeProfitPrice > 0 && (positionType == 0 ? currentPrice >= exit.takeProfitPrice : currentPrice <= exit.takeProfitPrice);

        if (shouldLiquidate || shouldCloseSL || shouldCloseTP) {
            uint256 payout = positionType == 0 ? prepCloseLong(positionId, listingAddress) : prepCloseShort(positionId, listingAddress);
            removePositionIndex(positionId, positionType, listingAddress);
            emit PositionClosed(positionId, core1.makerAddress, payout);
            active[i] = active[active.length - 1];
            active.pop();
            return true;
        }
        return false;
    }

    function _executePositions(address listingAddress, uint256 maxIterations) internal {
        require(listingAddress != address(0), "Invalid listing address");
        for (uint8 positionType = 0; positionType <= 1; positionType++) {
            uint256[] storage pending = pendingPositions[listingAddress][positionType];
            uint256 processed = 0;
            for (uint256 i = 0; i < pending.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = pending[i];
                PositionCore1 storage core1 = positionCore1[positionId];
                address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
                (uint256 currentPrice,,,) = _parseEntryPriceInternal(priceParams1[positionId].minEntryPrice, priceParams1[positionId].maxEntryPrice, listingAddress);
                currentPrice = normalizePrice(token, currentPrice);

                if (_processPendingPosition(positionId, positionType, listingAddress, pending, i, currentPrice)) {
                    i--;
                }
                processed++;
            }

            uint256[] storage active = positionsByType[positionType];
            for (uint256 i = 0; i < active.length && processed < maxIterations && gasleft() >= 50000; i++) {
                uint256 positionId = active[i];
                PositionCore1 storage core1 = positionCore1[positionId];
                if (core1.positionId == 0 || core1.listingAddress != listingAddress || positionCore2[positionId].status2 != 0) continue;
                address token = positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
                (uint256 currentPrice,,,) = _parseEntryPriceInternal(priceParams1[positionId].minEntryPrice, priceParams1[positionId].maxEntryPrice, listingAddress);
                currentPrice = normalizePrice(token, currentPrice);

                if (_processActivePosition(positionId, positionType, listingAddress, active, i, currentPrice)) {
                    i--;
                }
                processed++;
            }
        }
    }

    function _updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint8 positionType,
        uint256 minPrice,
        uint256 maxEntryPrice,
        uint256 currentPrice
    ) internal {
        ExitParams storage exit = exitParams[positionId];
        exit.stopLossPrice = newStopLossPrice;
    }

    function _updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        address listingAddress,
        uint8 positionType,
        uint256 priceAtEntry,
        uint256 maxEntryPrice,
        uint256 currentPrice
    ) internal {
        ExitParams storage exit = exitParams[positionId];
        if (positionType == 0) {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice > priceAtEntry, "Invalid TP for long");
        } else {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice < priceAtEntry, "Invalid TP for short");
        }
        exit.takeProfitPrice = newTakeProfitPrice;
    }
}