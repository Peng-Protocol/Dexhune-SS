// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.10:
// - Fixed DeclarationError in updateEntryParamsStore by passing baseParams.initMargin as a parameter.
// - Optimized stack usage by passing initMargin as uint256 instead of baseParams struct.
// - Retained fixes from v0.0.9 (closeShortPosition), v0.0.8 (updateEntryParams), v0.0.7 (finalizeEntry).
// - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.6, SSDExecutionPartial.sol v0.0.24.
// - v0.0.9:
//   - Fixed ParserError in closeShortPosition by removing extra parenthesis.
//   - Corrected syntax errors in closeShortPosition: status -> status2, MeanscoreBase -> coreBase, minPrice -> priceMin.
// - v0.0.8:
//   - Fixed ParserError by correcting typo '众多Params' to 'leverageParams' in updateEntryParams.
//   - Split updateEntryParams into helpers to mitigate stack depth.
// - v0.0.7:
//   - Split finalizeEntry into helpers to fix stack too deep error.
//   - Adjusted finalizeEntry to deduct actual fee from initial margin.

import "./driverUtils/SSDExecutionPartial.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";

contract SSIsolatedDriver is SSDExecutionPartial, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Context struct to reduce stack usage
    struct EntryContext {
        address listingAddr;
        address tokenAddr;
        uint256 normInitMargin;
        uint256 normExtraMargin;
    }

    // Temporary storage for position entry
    struct PendingEntry {
        address listingAddr;
        address tokenAddr;
        uint256 positionId;
        uint8 positionType;
        uint256 initialMargin;
        uint256 extraMargin;
        string entryPriceStr;
        address makerAddress;
        uint8 leverageVal;
        uint256 stopLoss;
        uint256 takeProfit;
        uint256 normInitMargin;
        uint256 normExtraMargin;
    }

    // Temporary storage mapping
    mapping(uint256 => PendingEntry) internal pendingEntries;

    // Constructor
    constructor() {
        historicalInterestHeight = uint256(1);
        nonce = uint256(0);
        positionIdCounter = uint256(0);
    }

    // Helper: Normalize margin amounts
    function normalizeMargins(
        address tokenAddr,
        uint256 initMargin,
        uint256 extraMargin
    ) internal view returns (uint256 normInitMargin, uint256 normExtraMargin) {
        normInitMargin = normalizeAmount(tokenAddr, initMargin);
        normExtraMargin = normalizeAmount(tokenAddr, extraMargin);
    }

    // Helper: Prepare entry context
    function prepareEntryContext(
        address listingAddr,
        address tokenAddr,
        uint256 initMargin,
        uint256 extraMargin
    ) internal view returns (EntryContext memory context) {
        (uint256 normInitMargin, uint256 normExtraMargin) = normalizeMargins(
            tokenAddr,
            initMargin,
            extraMargin
        );
        return EntryContext({
            listingAddr: listingAddr,
            tokenAddr: tokenAddr,
            normInitMargin: normInitMargin,
            normExtraMargin: normExtraMargin
        });
    }

    // Helper: Prepare base entry data
    function prepareEntryBase(
        EntryContext memory context,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 positionType
    ) internal returns (uint256 positionId) {
        positionId = positionIdCounter++;
        pendingEntries[positionId] = PendingEntry({
            listingAddr: context.listingAddr,
            tokenAddr: context.tokenAddr,
            positionId: positionId,
            positionType: positionType,
            initialMargin: initMargin,
            extraMargin: extraMargin,
            entryPriceStr: entryPriceStr,
            makerAddress: msg.sender,
            leverageVal: uint8(0),
            stopLoss: uint256(0),
            takeProfit: uint256(0),
            normInitMargin: context.normInitMargin,
            normExtraMargin: context.normExtraMargin
        });
        return positionId;
    }

    // Helper: Prepare risk parameters
    function prepareEntryRisk(
        uint256 positionId,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        entry.leverageVal = leverage;
        entry.stopLoss = stopLoss;
        entry.takeProfit = takeProfit;
    }

    // Helper: Prepare token parameters
    function prepareEntryToken(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
    }

    // Helper: Validate base parameters
    function validateEntryBase(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        EntryParamsBase memory baseParams = EntryParamsBase({
            listingAddr: entry.listingAddr,
            entryPriceStr: entry.entryPriceStr,
            initMargin: entry.initialMargin,
            extraMargin: entry.extraMargin
        });
        require(baseParams.initMargin > uint256(0), "Invalid margin");
        require(baseParams.listingAddr != address(0), "Invalid listing");
        validateListing(baseParams.listingAddr);
    }

    // Helper: Validate risk parameters
    function validateEntryRisk(uint256 positionId) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        EntryParamsRisk memory riskParams = EntryParamsRisk({
            leverageVal: entry.leverageVal,
            stopLoss: entry.stopLoss,
            takeProfit: entry.takeProfit
        });
        require(riskParams.leverageVal >= uint8(2) && riskParams.leverageVal <= uint8(100), "Invalid leverage");
    }

    // Helper: Update entry core
    function updateEntryCore(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        PositionCoreBase memory coreBase = PositionCoreBase({
            makerAddress: entry.makerAddress,
            listingAddress: entry.listingAddr,
            positionId: positionId,
            positionType: entry.positionType
        });
        PositionCoreStatus memory coreStatus = PositionCoreStatus({
            status1: false,
            status2: uint8(0)
        });
        updatePositionCore(positionId, coreBase, coreStatus);
    }

    // Helper: Compute entry parameters
    function updateEntryParamsCompute(
        uint256 positionId,
        EntryParamsBase memory baseParams,
        EntryParamsRisk memory riskParams
    ) internal view returns (
        uint256 minPrice,
        uint256 maxPrice,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory calcRiskParams
    ) {
        (minPrice, maxPrice) = parseEntryPriceHelper(baseParams);
        (marginParams, leverageParams, calcRiskParams) = computeParams(
            baseParams,
            riskParams,
            minPrice,
            pendingEntries[positionId].positionType
        );
    }

    // Helper: Validate computed parameters
    function updateEntryParamsValidate(
        uint256 positionId,
        uint256 minPrice,
        uint256 leverageAmount,
        uint8 leverageVal
    ) internal view {
        PendingEntry storage entry = pendingEntries[positionId];
        validateLeverageLimit(
            entry.listingAddr,
            leverageAmount,
            leverageVal,
            entry.positionType
        );
    }

    // Helper: Store entry parameters
    function updateEntryParamsStore(
        uint256 positionId,
        uint256 minPrice,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory calcRiskParams,
        EntryParamsToken memory tokenParams,
        uint256 initMargin
    ) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        PosParamsCore memory coreParams = prepareCoreParams(
            tokenParams.normInitMargin,
            marginParams,
            tokenParams.normExtraMargin,
            minPrice,
            tokenParams.tokenAddr
        );
        PosParamsExt memory extParams = prepareExtParams(
            entry.leverageVal,
            entry.stopLoss,
            entry.takeProfit,
            leverageParams,
            calcRiskParams
        );
        updatePositionParamsCore(positionId, coreParams);
        updatePositionParamsExtended(positionId, extParams);
        positionToken[positionId] = tokenParams.tokenAddr;
        updateLiquidityFees(
            positionId,
            entry.listingAddr,
            entry.positionType,
            initMargin,
            entry.leverageVal
        );
    }

    // Helper: Update entry parameters
    function updateEntryParams(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        EntryParamsBase memory baseParams = EntryParamsBase({
            listingAddr: entry.listingAddr,
            entryPriceStr: entry.entryPriceStr,
            initMargin: entry.initialMargin,
            extraMargin: entry.extraMargin
        });
        EntryParamsRisk memory riskParams = EntryParamsRisk({
            leverageVal: entry.leverageVal,
            stopLoss: entry.stopLoss,
            takeProfit: entry.takeProfit
        });
        EntryParamsToken memory tokenParams = EntryParamsToken({
            tokenAddr: entry.tokenAddr,
            normInitMargin: entry.normInitMargin,
            normExtraMargin: entry.normExtraMargin,
            driverAddr: address(this)
        });
        (
            uint256 minPrice,
            uint256 maxPrice,
            MarginParams memory marginParams,
            LeverageParams memory leverageParams,
            RiskParams memory calcRiskParams
        ) = updateEntryParamsCompute(positionId, baseParams, riskParams);
        updateEntryParamsValidate(
            positionId,
            minPrice,
            leverageParams.leverageAmount,
            riskParams.leverageVal
        );
        updateEntryParamsStore(
            positionId,
            minPrice,
            marginParams,
            leverageParams,
            calcRiskParams,
            tokenParams,
            baseParams.initMargin
        );
    }

    // Helper: Update entry indexes
    function updateEntryIndexes(uint256 positionId) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        updateIndexes(entry.makerAddress, entry.positionType, positionId, entry.listingAddr, true);
    }

    // Helper: Finalize entry fees
    function finalizeEntryFees(uint256 positionId) internal returns (uint256 actualFee) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        actualFee = updateLiquidityFees(
            positionId,
            entry.listingAddr,
            entry.positionType,
            entry.initialMargin,
            entry.leverageVal
        );
        return actualFee;
    }

    // Helper: Finalize entry margin transfer
    function finalizeEntryTransfer(uint256 positionId, uint256 actualFee) internal returns (uint256) {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        uint256 denormInitMargin = denormalizeAmount(entry.tokenAddr, entry.normInitMargin);
        require(denormInitMargin >= actualFee, "Fee exceeds initial margin");
        uint256 remainingMargin = denormInitMargin - actualFee;
        uint256 expectedAmount = remainingMargin + entry.extraMargin;
        uint256 balanceBefore = IERC20(entry.tokenAddr).balanceOf(entry.listingAddr);
        IERC20(entry.tokenAddr).transferFrom(
            entry.makerAddress,
            entry.listingAddr,
            expectedAmount
        );
        uint256 actualAmount = checkTransferAmount(
            entry.tokenAddr,
            entry.listingAddr,
            expectedAmount,
            balanceBefore
        );
        uint256 io = normalizeAmount(entry.tokenAddr, actualAmount);
        transferMarginToListing(entry.listingAddr, io, entry.positionType);
        return io;
    }

    // Helper: Finalize entry position
    function finalizeEntryPosition(uint256 positionId, uint256 io) internal {
        PendingEntry storage entry = pendingEntries[positionId];
        require(entry.positionId == positionId, "Invalid position ID");
        updateHistoricalInterest(
            historicalInterestHeight,
            entry.positionType == 0 ? io : uint256(0),
            entry.positionType == 1 ? io : uint256(0),
            block.timestamp
        );
        EntryParamsBase memory baseParams = EntryParamsBase({
            listingAddr: entry.listingAddr,
            entryPriceStr: entry.entryPriceStr,
            initMargin: entry.initialMargin,
            extraMargin: entry.extraMargin
        });
        EntryParamsRisk memory riskParams = EntryParamsRisk({
            leverageVal: entry.leverageVal,
            stopLoss: entry.stopLoss,
            takeProfit: entry.takeProfit
        });
        EntryParamsToken memory tokenParams = EntryParamsToken({
            tokenAddr: entry.tokenAddr,
            normInitMargin: entry.normInitMargin,
            normExtraMargin: entry.normExtraMargin,
            driverAddr: address(this)
        });
        uint256 returnedPositionId;
        uint256 minPrice;
        uint256 maxPrice;
        (returnedPositionId, minPrice, maxPrice) = entry.positionType == 0
            ? prepareEnterLong(baseParams, riskParams, tokenParams)
            : prepareEnterShort(baseParams, riskParams, tokenParams);
        require(returnedPositionId == positionId, "Position ID mismatch");
        emit PositionEntered(
            positionId,
            entry.makerAddress,
            entry.listingAddr,
            entry.positionType,
            minPrice,
            maxPrice
        );
        delete pendingEntries[positionId];
    }

    // Helper: Finalize entry
    function finalizeEntry(uint256 positionId) internal {
        uint256 actualFee = finalizeEntryFees(positionId);
        uint256 io = finalizeEntryTransfer(positionId, actualFee);
        finalizeEntryPosition(positionId, io);
    }

    // Initiate entry
    function initiateEntry(
        EntryContext memory context,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit,
        uint8 positionType
    ) internal returns (uint256 positionId) {
        positionId = prepareEntryBase(context, entryPriceStr, initMargin, extraMargin, positionType);
        prepareEntryRisk(positionId, leverage, stopLoss, takeProfit);
        prepareEntryToken(positionId);
        validateEntryBase(positionId);
        validateEntryRisk(positionId);
        updateEntryCore(positionId);
        updateEntryParams(positionId);
        updateEntryIndexes(positionId);
        finalizeEntry(positionId);
        return positionId;
    }

    // Enter long position
    function enterLong(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit,
        address tokenAddr
    ) external nonReentrant {
        EntryContext memory context = prepareEntryContext(
            listingAddr,
            tokenAddr,
            initMargin,
            extraMargin
        );
        initiateEntry(
            context,
            entryPriceStr,
            initMargin,
            extraMargin,
            leverage,
            stopLoss,
            takeProfit,
            uint8(0) // Long
        );
    }

    // Enter short position
    function enterShort(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit,
        address tokenAddr
    ) external nonReentrant {
        EntryContext memory context = prepareEntryContext(
            listingAddr,
            tokenAddr,
            initMargin,
            extraMargin
        );
        initiateEntry(
            context,
            entryPriceStr,
            initMargin,
            extraMargin,
            leverage,
            stopLoss,
            takeProfit,
            uint8(1) // Short
        );
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        require(coreBase.makerAddress == msg.sender, "Not position owner");
        require(coreStatus.status2 == uint8(0), "Position not open");

        ClosePositionBase memory closeBase = ClosePositionBase({
            positionId: positionId,
            listingAddress: coreBase.listingAddress,
            makerAddress: coreBase.makerAddress,
            driver: address(this)
        });
        ClosePositionMargin memory closeMargin = ClosePositionMargin({
            taxedMargin: marginParams[positionId].marginTaxed,
            excessMargin: marginParams[positionId].marginExcess
        });
        LongCloseParams memory longParams = LongCloseParams({
            leverageAmount: leverageParams[positionId].leverageAmount,
            loanInitial: leverageParams[positionId].loanInitial
        });

        uint256 payout = internalCloseLongPosition(closeBase, closeMargin, longParams);
        emit PositionClosed(positionId, msg.sender, payout);
    }

    // Close short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        require(coreBase.makerAddress == msg.sender, "Not position owner");
        require(coreStatus.status2 == uint8(0), "Position not open");

        ClosePositionBase memory closeBase = ClosePositionBase({
            positionId: positionId,
            listingAddress: coreBase.listingAddress,
            makerAddress: coreBase.makerAddress,
            driver: address(this)
        });
        ClosePositionMargin memory closeMargin = ClosePositionMargin({
            taxedMargin: marginParams[positionId].marginTaxed,
            excessMargin: marginParams[positionId].marginExcess
        });
        ShortCloseParams memory shortParams = ShortCloseParams({
            minPrice: priceParams[positionId].priceMin,
            initialMargin: marginParams[positionId].marginInitial,
            leverage: leverageParams[positionId].leverageVal
        });

        uint256 payout = internalCloseShortPosition(closeBase, closeMargin, shortParams);
        emit PositionClosed(positionId, msg.sender, payout);
    }

    // Cancel position
    function cancelPosition(uint256 positionId) external nonReentrant {
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        require(coreBase.makerAddress == msg.sender, "Not position owner");
        require(!coreStatus.status1, "Position executable");

        ClosePositionBase memory closeBase = ClosePositionBase({
            positionId: positionId,
            listingAddress: coreBase.listingAddress,
            makerAddress: coreBase.makerAddress,
            driver: address(this)
        });
        ClosePositionMargin memory closeMargin = ClosePositionMargin({
            taxedMargin: marginParams[positionId].marginTaxed,
            excessMargin: marginParams[positionId].marginExcess
        });

        internalCancelPosition(closeBase, closeMargin, coreBase.positionType);
        emit PositionCancelled(positionId, msg.sender);
    }

    // Add excess margin
    function addExcessMargin(
        uint256 positionId,
        uint256 amount,
        address token
    ) external nonReentrant {
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        require(coreStatus.status2 == uint8(0), "Position not open");

        uint256 normalizedAmount = normalizeAmount(token, amount);
        addExcessMarginInternal(
            positionId,
            amount,
            token,
            coreBase.listingAddress,
            coreBase.positionType,
            normalizedAmount
        );
        emit ExcessMarginAdded(positionId, msg.sender, amount);
    }

    // Update stop loss
    function updateSL(
        uint256 positionId,
        uint256 newStopLossPrice
    ) external nonReentrant {
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        require(coreBase.makerAddress == msg.sender, "Not position owner");
        require(coreStatus.status2 == uint8(0), "Position not open");

        uint256 currentPrice = getCurrentPrice(coreBase.listingAddress);
        if (coreBase.positionType == uint8(0)) {
            require(newStopLossPrice < currentPrice, "Stop loss too high for long");
        } else {
            require(newStopLossPrice > currentPrice, "Stop loss too low for short");
        }

        updateSLInternal(positionId, newStopLossPrice);
        emit StopLossUpdated(positionId, msg.sender, newStopLossPrice);
    }

    // Update take profit
    function updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice
    ) external nonReentrant {
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        require(coreBase.makerAddress == msg.sender, "Not position owner");
        require(coreStatus.status2 == uint8(0), "Position not open");

        uint256 entryPrice = priceParams[positionId].priceAtEntry;
        if (coreBase.positionType == uint8(0)) {
            require(newTakeProfitPrice > entryPrice, "Take profit too low for long");
        } else {
            require(newTakeProfitPrice < entryPrice, "Take profit too high for short");
        }

        updateTPInternal(positionId, newTakeProfitPrice);
        emit TakeProfitUpdated(positionId, msg.sender, newTakeProfitPrice);
    }

    // Close all short positions
    function closeAllShort(uint256 maxIterations) external nonReentrant {
        uint256 count = closeAllShortInternal(msg.sender, maxIterations);
        emit AllShortsClosed(msg.sender, count);
    }

    // Cancel all short positions
    function cancelAllShort(uint256 maxIterations) external nonReentrant {
        uint256 count = cancelAllShortInternal(msg.sender, maxIterations);
        emit AllShortsCancelled(msg.sender, count);
    }

    // Close all long positions
    function closeAllLongs(uint256 maxIterations) external nonReentrant {
        uint256 count = closeAllLongsInternal(msg.sender, maxIterations);
        emit AllLongsClosed(msg.sender, count);
    }

    // Cancel all long positions
    function cancelAllLong(uint256 maxIterations) external nonReentrant {
        uint256 count = cancelAllLongInternal(msg.sender, maxIterations);
        emit AllLongsCancelled(msg.sender, count);
    }

    // Execute positions
    function executePositions(address listingAddress) external nonReentrant {
        PositionAction[] memory actions = prepareExecution(listingAddress);
        uint256 resultCount = executePositionsLogic(actions, listingAddress);
        emit PositionsExecuted(listingAddress, resultCount);
    }

    // View positions by type
    function positionsByTypeView(
        uint8 positionType,
        uint256 step,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        uint256[] memory positions = positionsByType[positionType];
        uint256 length = maxIterations < positions.length - step ? maxIterations : positions.length - step;
        positionIds = new uint256[](length);
        for (uint256 i = uint256(0); i < length; i++) {
            positionIds[i] = positions[step + i];
        }
    }

    // View positions by address
    function positionsByAddressView(
        address user,
        uint8 positionType,
        uint256 step,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        uint256[] memory positions = pendingPositions[user][positionType];
        uint256 length = maxIterations < positions.length - step ? maxIterations : positions.length - step;
        positionIds = new uint256[](length);
        for (uint256 i = uint256(0); i < length; i++) {
            positionIds[i] = positions[step + i];
        }
    }

    // View position by index
    function positionByIndex(uint256 positionId) external view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory price,
        MarginParams memory margin,
        LeverageParams memory leverage,
        RiskParams memory risk,
        address token
    ) {
        coreBase = positionCoreBase[positionId];
        coreStatus = positionCoreStatus[positionId];
        price = priceParams[positionId];
        margin = marginParams[positionId];
        leverage = leverageParams[positionId];
        risk = riskParams[positionId];
        token = positionToken[positionId];
    }

    // Query historical interest
    function queryInterest(
        uint256 step,
        uint256 maxIterations
    ) external view returns (
        uint256[] memory longIO,
        uint256[] memory shortIO,
        uint256[] memory timestamps
    ) {
        uint256 length = maxIterations < historicalInterestHeight - step ? maxIterations : historicalInterestHeight - step;
        longIO = new uint256[](length);
        shortIO = new uint256[](length);
        timestamps = new uint256[](length);
        for (uint256 i = uint256(0); i < length; i++) {
            uint256 index = step + i;
            longIO[i] = longIOByHeight[index];
            shortIO[i] = shortIOByHeight[index];
            timestamps[i] = historicalInterestTimestamps[index];
        }
    }

    // Set agent address
    function setAgent(address newAgent) external onlyOwner {
        agent = newAgent;
    }
}