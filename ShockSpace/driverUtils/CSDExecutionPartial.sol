/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-06-01: Extracted shouldClose logic from forceExecution to _shouldClosePosition to reduce stack depth for downstream calls. Version incremented to 0.0.4 for pre-testing.
// - 2025-05-29: Renamed internal updateSL to _updateSL, updateTP to _updateTP.
// - 2025-05-29: Version incremented to 0.0.3 for pre-testing.
// - 2025-05-29: Implemented forceExecution and executeCloseAction.
// - 2025-05-29: Updated updateSL/updateTP to check minEntryPrice/maxEntryPrice.
// - 2025-05-29: Added onlyDriver modifier.

pragma solidity 0.8.1;

import "./CSDPositionPartial.sol";

contract CSDExecutionPartial is CSDPositionPartial {
    modifier onlyDriver() {
        require(msg.sender == address(this), "Only Driver");
        _;
    }

    function _updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint8 positionType,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 currentPrice
    ) internal onlyDriver {
        require(positionType <= 1, "Invalid position type");
        PriceParams1 storage price1 = priceParams1[positionId];

        if (positionType == 0) {
            require(newStopLossPrice == 0 || (newStopLossPrice <= currentPrice && newStopLossPrice < price1.minEntryPrice), "Invalid SL for long");
        } else {
            require(newStopLossPrice == 0 || (newStopLossPrice >= currentPrice && newStopLossPrice > price1.maxEntryPrice), "Invalid SL for short");
        }

        setExitParams(positionId, newStopLossPrice, exitParams[positionId].takeProfitPrice);
    }

    function _updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        address listingAddress,
        uint8 positionType,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 currentPrice
    ) internal onlyDriver {
        require(positionType <= 1, "Invalid position type");
        PriceParams1 storage price1 = priceParams1[positionId];

        if (positionType == 0) {
            require(newTakeProfitPrice == 0 || (newTakeProfitPrice >= currentPrice && newTakeProfitPrice > price1.maxEntryPrice), "Invalid TP for long");
        } else {
            require(newTakeProfitPrice == 0 || (newTakeProfitPrice <= currentPrice && newTakeProfitPrice < price1.minEntryPrice), "Invalid TP for short");
        }

        setExitParams(positionId, exitParams[positionId].stopLossPrice, newTakeProfitPrice);
    }

    function _shouldClosePosition(
        uint256 positionId,
        uint8 positionType,
        uint256 currentPrice,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 liquidationPrice
    ) internal view returns (bool) {
        if (positionType == 0) {
            return (stopLossPrice != 0 && currentPrice <= stopLossPrice) ||
                   (takeProfitPrice != 0 && currentPrice >= takeProfitPrice) ||
                   (currentPrice <= liquidationPrice);
        } else {
            return (stopLossPrice != 0 && currentPrice >= stopLossPrice) ||
                   (takeProfitPrice != 0 && currentPrice <= takeProfitPrice) ||
                   (currentPrice >= liquidationPrice);
        }
    }

    function forceExecution(address listingAddress, uint256 maxIterations) internal onlyDriver {
        uint256 gasLimit = gasleft();
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        uint256 processed = 0;

        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            if (gasLimit < 50000) break; // Graceful degradation
            uint256 positionId = i + 1; // Incremental position IDs
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.listingAddress != listingAddress || core2.status2 != 0) continue;

            PriceParams1 storage price1 = priceParams1[positionId];
            PriceParams2 storage price2 = priceParams2[positionId];
            ExitParams storage exit = exitParams[positionId];

            // Check Price-at-Entry for Status-1
            if (!core2.status1) {
                if (price1.priceAtEntry > price1.minEntryPrice && currentPrice <= price1.minEntryPrice) {
                    core2.status1 = true;
                } else if (price1.priceAtEntry < price1.maxEntryPrice && currentPrice >= price1.maxEntryPrice) {
                    core2.status1 = true;
                }
            }

            // Check SL/TP/Liquidation
            if (core2.status1) {
                bool shouldClose = _shouldClosePosition(
                    positionId,
                    core1.positionType,
                    currentPrice,
                    exit.stopLossPrice,
                    exit.takeProfitPrice,
                    price2.liquidationPrice
                );
                if (shouldClose) {
                    executeCloseAction(positionId, listingAddress);
                }
            }

            processed++;
            gasLimit = gasleft();
        }
    }

    function executeCloseAction(uint256 positionId, address listingAddress) internal onlyDriver {
        PositionCore1 storage core1 = positionCore1[positionId];
        if (core1.positionType == 0) {
            prepCloseLong(positionId, listingAddress);
        } else {
            prepCloseShort(positionId, listingAddress);
        }
    }
}