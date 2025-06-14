/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-06-13: Renamed executePositions to _executePositions as internal helper, added external executePositions wrapper. Version incremented to 0.0.16.
// - 2025-06-13: Changed executePositions visibility to external virtual. Version incremented to 0.0.15.
// - 2025-06-13: Confirmed PositionClosed emission via CSDUtilityPartial.sol. Version incremented to 0.0.14.

pragma solidity 0.8.1;

import "./CSDPositionPartial.sol";

contract CSDExecutionPartial is CSDPositionPartial {
    using SafeERC20 for IERC20;

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
                (uint256 currentPrice,,,) = parseEntryPrice(priceParams1[positionId].minEntryPrice, priceParams1[positionId].maxEntryPrice, listingAddress);
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
                (uint256 currentPrice,,,) = parseEntryPrice(priceParams1[positionId].minEntryPrice, priceParams1[positionId].maxEntryPrice, listingAddress);
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