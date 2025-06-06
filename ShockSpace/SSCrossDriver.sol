/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-05-31: Fixed TypeError in PositionByIndex by explicitly assigning margin2 mapping to local variable margin2Data. Version incremented to 0.0.6 for pre-testing.
// - 2025-05-31: Removed positionCount state variable as it is inherited from ASDUtilityPartial to avoid overlapping declarations.
// - 2025-05-31: Version incremented to 0.0.5 for pre-testing.
// - 2025-05-31: Removed PositionCore1, PositionCore2, PriceParams1, PriceParams2, MarginParams1, MarginParams2, ExitParams, and OpenInterest structs and mappings, moved to ASDUtilityPartial.sol.
// - 2025-05-29: Updated updateSL/updateTP to call _updateSL/_updateTP.
// - 2025-05-29: Removed maker parameter from closeAllLongs, cancelAllLongs, closeAllShorts, cancelAllShorts, using msg.sender.
// - 2025-05-29: Modified addExcessMargin to accept maker parameter.
// - 2025-05-29: Version incremented to 0.0.3 for pre-testing.
// - 2025-05-29: Added addExcessMargin, pullMargin, setAgent, PositionsByTypeView, PositionsByAddressView, PositionByIndex, queryInterest, closeAllShort, cancelAllShort, closeAllLongs, cancelAllLong.
// - 2025-05-29: Added exotic view functions: PositionHealthView, AggregateMarginByToken, OpenInterestTrend, LiquidationRiskCount.
// - 2025-05-29: Added priceAtEntry to PriceParams1 struct.
// - 2025-05-29: Added positionCount for incremental position IDs.
// - 2025-05-29: Added openInterest storage for queryInterest.
// - 2025-05-29: Integrated ISSAgent for listing validation.
// - 2025-05-29: Updated enterLong/enterShort to use minEntryPrice/maxEntryPrice.
// - 2025-05-29: Updated updateSL/updateTP to remove fees and liquidity calls.
// - 2025-05-29: Integrated makerTokenMargin updates for excessMargin only.

pragma solidity 0.8.1;

import "./driverUtils/CSDExecutionPartial.sol";

contract SSCrossDriver is ReentrancyGuard, Ownable, CSDExecutionPartial {
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice, uint256 currentPrice, uint256 timestamp);
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice, uint256 currentPrice, uint256 timestamp);

    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address");
        agentAddress = newAgentAddress;
    }

    function addExcessMargin(address tokenA, address tokenB, uint256 amount, address maker) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(maker != address(0), "Invalid maker");
        address listingAddress = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(listingAddress != address(0), "Invalid listing");
        address token = ISSListing(listingAddress).tokenB();
        transferMargin(listingAddress, token, amount);
        makerTokenMargin[maker][token] += amount;
        if (makerTokenMargin[maker][token] == amount) {
            makerMarginTokens[maker].push(token);
        }
    }

    function pullMargin(address tokenA, address tokenB, uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        address listingAddress = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(listingAddress != address(0), "Invalid listing");
        address token = ISSListing(listingAddress).tokenB();
        require(amount <= makerTokenMargin[msg.sender][token], "Insufficient margin");
        makerTokenMargin[msg.sender][token] -= amount;
        transferMargin(msg.sender, token, amount);
        if (makerTokenMargin[msg.sender][token] == 0) {
            _removeToken(msg.sender, token);
        }
    }

    function enterLong(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external nonReentrant {
        require(positionCore1[positionId].positionId == 0, "Position ID exists");
        address listingAddress = ISSAgent(agentAddress).getListing(ISSListing(msg.sender).tokenA(), ISSListing(msg.sender).tokenB());
        require(listingAddress == msg.sender, "Invalid listing");
        address maker = msg.sender;
        positionCount++;

        PrepPosition memory prep = prepEnterLong(
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            listingAddress,
            maker
        );

        positionCore1[positionId] = PositionCore1({
            positionId: positionId,
            listingAddress: listingAddress,
            makerAddress: maker,
            positionType: 0
        });
        positionCore2[positionId] = PositionCore2({ status1: false, status2: 0 });
        (, , , uint256 priceAtEntry) = parseEntryPrice(minEntryPrice, maxEntryPrice, listingAddress);
        priceParams1[positionId] = PriceParams1({
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            minPrice: prep.liquidationPrice,
            priceAtEntry: priceAtEntry,
            leverage: leverage
        });
        priceParams2[positionId] = PriceParams2({ liquidationPrice: prep.liquidationPrice });
        marginParams1[positionId] = MarginParams1({
            initialMargin: initialMargin,
            taxedMargin: prep.taxedMargin,
            excessMargin: excessMargin,
            fee: prep.fee
        });
        margin2[positionId] = MarginParams2({ initialLoan: prep.initialLoan });
        openInterest[positionId] = OpenInterest({ leverageAmount: prep.leverageAmount, timestamp: block.timestamp });
        setExitParams(positionId, stopLossPrice, takeProfitPrice);
    }

    function enterShort(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external nonReentrant {
        require(positionCore1[positionId].positionId == 0, "Position ID exists");
        address listingAddress = ISSAgent(agentAddress).getListing(ISSListing(msg.sender).tokenA(), ISSListing(msg.sender).tokenB());
        require(listingAddress == msg.sender, "Invalid listing");
        address maker = msg.sender;
        positionCount++;

        PrepPosition memory prep = prepEnterShort(
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            listingAddress,
            maker
        );

        positionCore1[positionId] = PositionCore1({
            positionId: positionId,
            listingAddress: listingAddress,
            makerAddress: maker,
            positionType: 1
        });
        positionCore2[positionId] = PositionCore2({ status1: false, status2: 0 });
        (, , , uint256 priceAtEntry) = parseEntryPrice(minEntryPrice, maxEntryPrice, listingAddress);
        priceParams1[positionId] = PriceParams1({
            minEntryPrice: minEntryPrice,
            maxEntryPrice: maxEntryPrice,
            minPrice: prep.liquidationPrice,
            priceAtEntry: priceAtEntry,
            leverage: leverage
        });
        priceParams2[positionId] = PriceParams2({ liquidationPrice: prep.liquidationPrice });
        marginParams1[positionId] = MarginParams1({
            initialMargin: initialMargin,
            taxedMargin: prep.taxedMargin,
            excessMargin: excessMargin,
            fee: prep.fee
        });
        margin2[positionId] = MarginParams2({ initialLoan: prep.initialLoan });
        openInterest[positionId] = OpenInterest({ leverageAmount: prep.leverageAmount, timestamp: block.timestamp });
        setExitParams(positionId, stopLossPrice, takeProfitPrice);
    }

    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        require(newStopLossPrice > 0 || newStopLossPrice == 0, "Invalid SL");

        uint256 currentPrice = ISSListing(core1.listingAddress).prices(core1.listingAddress);
        PriceParams1 storage price1 = priceParams1[positionId];

        _updateSL(
            positionId,
            newStopLossPrice,
            core1.listingAddress,
            core1.positionType,
            price1.minPrice,
            price1.maxEntryPrice,
            currentPrice
        );

        emit StopLossUpdated(positionId, newStopLossPrice, currentPrice, block.timestamp);
    }

    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        require(newTakeProfitPrice > 0 || newTakeProfitPrice == 0, "Invalid TP");

        uint256 currentPrice = ISSListing(core1.listingAddress).prices(core1.listingAddress);
        PriceParams1 storage price1 = priceParams1[positionId];

        _updateTP(
            positionId,
            newTakeProfitPrice,
            core1.listingAddress,
            core1.positionType,
            price1.minPrice,
            price1.maxEntryPrice,
            currentPrice
        );

        emit TakeProfitUpdated(positionId, newTakeProfitPrice, currentPrice, block.timestamp);
    }

    function closeAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 0 || core2.status2 != 0 || !core2.status1) continue;
            prepCloseLong(positionId, core1.listingAddress);
            processed++;
        }
    }

    function cancelAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 0 || core2.status2 != 0 || core2.status1) continue;
            address token = ISSListing(core1.listingAddress).tokenB();
            MarginParams1 storage margin1 = marginParams1[positionId];
            makerTokenMargin[maker][token] -= (margin1.taxedMargin + margin1.excessMargin);
            if (makerTokenMargin[maker][token] == 0) {
                _removeToken(maker, token);
            }
            core2.status2 = 1;
            exitParams[positionId].exitPrice = 0;
            processed++;
        }
    }

    function closeAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 1 || core2.status2 != 0 || !core2.status1) continue;
            prepCloseShort(positionId, core1.listingAddress);
            processed++;
        }
    }

    function cancelAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 1 || core2.status2 != 0 || core2.status1) continue;
            address token = ISSListing(core1.listingAddress).tokenA();
            MarginParams1 storage margin1 = marginParams1[positionId];
            makerTokenMargin[maker][token] -= (margin1.taxedMargin + margin1.excessMargin);
            if (makerTokenMargin[maker][token] == 0) {
                _removeToken(maker, token);
            }
            core2.status2 = 1;
            exitParams[positionId].exitPrice = 0;
            processed++;
        }
    }

    function PositionsByTypeView(
        uint8 positionType,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        require(positionType <= 1, "Invalid position type");
        uint256[] memory tempIds = new uint256[](positionCount);
        uint256 count = 0;
        for (uint256 i = startIndex; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCore1[positionId].positionType == positionType) {
                tempIds[count] = positionId;
                count++;
            }
        }
        positionIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            positionIds[i] = tempIds[i];
        }
    }

    function PositionsByAddressView(
        address maker,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        uint256[] memory tempIds = new uint256[](positionCount);
        uint256 count = 0;
        for (uint256 i = startIndex; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCore1[positionId].makerAddress == maker) {
                tempIds[count] = positionId;
                count++;
            }
        }
        positionIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            positionIds[i] = tempIds[i];
        }
    }

    function PositionByIndex(uint256 positionId) external view returns (
        PositionCore1 memory core1,
        PositionCore2 memory core2,
        PriceParams1 memory price1,
        PriceParams2 memory price2,
        MarginParams1 memory margin1,
        MarginParams2 memory margin2Data,
        ExitParams memory exit
    ) {
        require(positionCore1[positionId].positionId == positionId, "Invalid position");
        margin2Data = margin2[positionId];
        return (
            positionCore1[positionId],
            positionCore2[positionId],
            priceParams1[positionId],
            priceParams2[positionId],
            marginParams1[positionId],
            margin2Data,
            exitParams[positionId]
        );
    }

    function queryInterest(uint256 startIndex, uint256 maxIterations) external view returns (
        uint256[] memory leverageAmounts,
        uint256[] memory timestamps
    ) {
        uint256 count = positionCount > startIndex + maxIterations ? maxIterations : positionCount - startIndex;
        leverageAmounts = new uint256[](count);
        timestamps = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 positionId = startIndex + i + 1;
            leverageAmounts[i] = openInterest[positionId].leverageAmount;
            timestamps[i] = openInterest[positionId].timestamp;
        }
    }

    function makerMarginIndex(
        address maker,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory tokens, uint256[] memory margins) {
        address[] storage makerTokens = makerMarginTokens[maker];
        uint256 length = makerTokens.length > startIndex + maxIterations ? maxIterations : makerTokens.length - startIndex;
        tokens = new address[](length);
        margins = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            tokens[i] = makerTokens[startIndex + i];
            margins[i] = makerTokenMargin[maker][tokens[i]];
        }
    }

    function PositionHealthView(uint256 positionId) external view returns (
        uint256 marginRatio,
        uint256 distanceToLiquidation,
        uint256 estimatedProfitLoss
    ) {
        require(positionCore1[positionId].positionId == positionId, "Invalid position");
        PositionCore1 memory core1 = positionCore1[positionId];
        MarginParams1 memory margin1 = marginParams1[positionId];
        PriceParams1 memory price1 = priceParams1[positionId];
        PriceParams2 memory price2 = priceParams2[positionId];
        uint256 currentPrice = ISSListing(core1.listingAddress).prices(core1.listingAddress);

        uint256 totalMargin = makerTokenMargin[core1.makerAddress][core1.positionType == 0 ? ISSListing(core1.listingAddress).tokenB() : ISSListing(core1.listingAddress).tokenA()];
        marginRatio = totalMargin * DECIMAL_PRECISION / (margin1.initialMargin * uint256(price1.leverage));

        if (core1.positionType == 0) {
            distanceToLiquidation = currentPrice > price2.liquidationPrice ? currentPrice - price2.liquidationPrice : 0;
            estimatedProfitLoss = (margin1.taxedMargin + totalMargin + price1.leverage * margin1.initialMargin) / currentPrice - margin2[positionId].initialLoan;
        } else {
            distanceToLiquidation = currentPrice < price2.liquidationPrice ? price2.liquidationPrice - currentPrice : 0;
            estimatedProfitLoss = (price1.minEntryPrice - currentPrice) * margin1.initialMargin * price1.leverage + (margin1.taxedMargin + totalMargin) * currentPrice;
        }
    }

    function AggregateMarginByToken(
        address tokenA,
        address tokenB,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory makers, uint256[] memory margins) {
        address listingAddress = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(listingAddress != address(0), "Invalid listing");
        address token = ISSListing(listingAddress).tokenB();
        uint256 count = 0;
        address[] memory tempMakers = new address[](positionCount);
        uint256[] memory tempMargins = new uint256[](positionCount);

        for (uint256 i = startIndex; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            address maker = positionCore1[positionId].makerAddress;
            if (maker != address(0) && makerTokenMargin[maker][token] > 0) {
                tempMakers[count] = maker;
                tempMargins[count] = makerTokenMargin[maker][token];
                count++;
            }
        }

        makers = new address[](count);
        margins = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            makers[i] = tempMakers[i];
            margins[i] = tempMargins[i];
        }
    }

    function OpenInterestTrend(
        address listingAddress,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory leverageAmounts, uint256[] memory timestamps) {
        uint256 count = 0;
        uint256[] memory tempAmounts = new uint256[](positionCount);
        uint256[] memory tempTimestamps = new uint256[](positionCount);

        for (uint256 i = startIndex; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCore1[positionId].listingAddress == listingAddress && positionCore2[positionId].status2 == 0) {
                tempAmounts[count] = openInterest[positionId].leverageAmount;
                tempTimestamps[count] = openInterest[positionId].timestamp;
                count++;
            }
        }

        leverageAmounts = new uint256[](count);
        timestamps = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            leverageAmounts[i] = tempAmounts[i];
            timestamps[i] = tempTimestamps[i];
        }
    }

    function LiquidationRiskCount(address listingAddress, uint256 maxIterations) external view returns (uint256 count) {
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCore1 memory core1 = positionCore1[positionId];
            PositionCore2 memory core2 = positionCore2[positionId];
            if (core1.listingAddress != listingAddress || core2.status2 != 0) continue;

            uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
            uint256 liquidationPrice = priceParams2[positionId].liquidationPrice;
            uint256 threshold = liquidationPrice * 5 / 100;

            if (core1.positionType == 0) {
                if (currentPrice <= liquidationPrice + threshold) count++;
            } else {
                if (currentPrice >= liquidationPrice - threshold) count++;
            }
            processed++;
        }
    }
}