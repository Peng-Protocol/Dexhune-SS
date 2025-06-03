// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.12:
// - Fixed TypeError in closeLongPosition, closeShortPosition, and cancelPosition by correcting driverAddr to driver in ClosePositionBase initialization.
// - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.11:
//   - Fixed ParserError for trailing comma in ClosePositionMargin struct initialization in closeLongPosition.
//   - Fixed ParserError in event declarations by replacing extra parentheses with semicolons and ensuring consistent uint256 types.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.10:
//   - Fixed ParserError in updateEntryCore by adding missing closing parenthesis in function signature.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.9:
//   - Fixed TypeError in closeLongPosition by correcting positionCoreStatus.status2 to coreStatus.status2.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.8:
//   - Fixed ParserError in prepareBaseParams by correcting return type syntax.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.7:
//   - Fixed TypeError in initiateEntry by correcting destructuring assignment for prepareEnterLong/prepareEnterShort return values (positionId, minPrice, maxPrice).
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.6:
//   - Added makerAddress to PendingEntry struct to fix TypeError in updateEntryIndexes.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.5:
//   - Rebuilt position entry to update data incrementally via initiateEntry, updateEntryCore, updateEntryParams, updateEntryIndexes, finalizeEntryTransfer.
//   - Added pendingEntry mapping for temporary storage.
//   - Removed redundant SafeERC20 import, inherited via SSDUtilityPartial.sol.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9.
// - v0.0.4:
//   - Fixed ParserError at line 143 by removing stray comma in prepareEntryContext call in enterLong and enterShort.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.4, SSDExecutionPartial.sol v0.0.9.
// - v0.0.3:
//   - Fixed stack too deep in enterLong/enterShort by introducing EntryContext struct and helper functions (prepareEntryContext, executeEntry).
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDPositionPartial.sol v0.0.4, SSDExecutionPartial.sol v0.0.9.
// - v0.0.2:
//   - Updated enterLong/enterShort to transfer margins via IERC20.transferFrom and ISSListing.update.
//   - Added ISSAgent validation using tokenA/tokenB from listing.
//   - Updated updateSL/updateTP to use msg.sender, validate against currentPrice/priceAtEntry.
//   - Added maxIterations to close/cancel functions.
//   - Added view functions: positionsByTypeView, positionsByAddressView, positionByIndex, queryInterest.
//   - Added setAgent (owner-only).
//   - Compatible with SSDUtilityPartial.sol v0.0.2, SSDPositionPartial.sol v0.0.2, SSDExecutionPartial.sol v0.0.2.

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
    }

    // Temporary storage mapping
    mapping(uint256 => PendingEntry) internal pendingEntries;

    // Constructor
    constructor() {
        historicalInterestHeight = 1;
        nonce = 0;
        positionIdCounter = 0;
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

    // Helper: Prepare base parameters
    function prepareBaseParams(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin
    ) internal pure returns (EntryParamsBase memory baseParams) {
        baseParams = EntryParamsBase({
            listingAddr: listingAddr,
            entryPriceStr: entryPriceStr,
            initMargin: initMargin,
            extraMargin: extraMargin
        });
        return baseParams;
    }

    // Helper: Prepare risk parameters
    function prepareRiskParams(
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal pure returns (EntryParamsRisk memory riskParams) {
        return EntryParamsRisk({
            leverageVal: leverage,
            stopLoss: stopLoss,
            takeProfit: takeProfit
        });
    }

    // Helper: Prepare token parameters
    function prepareTokenParams(
        EntryContext memory context
    ) internal view returns (EntryParamsToken memory tokenParams) {
        return EntryParamsToken({
            tokenAddr: context.tokenAddr,
            normInitMargin: context.normInitMargin,
            normExtraMargin: context.normExtraMargin,
            driverAddr: address(this)
        });
    }

    // Helper: Update entry core data
    function updateEntryCore(
        uint256 positionId,
        EntryParamsBase memory baseParams,
        uint8 positionType
    ) internal {
        PendingEntry memory entry = pendingEntries[positionId];
        PositionCoreBase memory coreBase = PositionCoreBase({
            makerAddress: msg.sender,
            listingAddress: entry.listingAddr,
            positionId: positionId,
            positionType: positionType
        });
        PositionCoreStatus memory coreStatus = PositionCoreStatus({
            status1: false,
            status2: 0
        });
        updatePositionCore(positionId, coreBase, coreStatus);
    }

    // Helper: Update entry parameters
    function updateEntryParams(
        uint256 positionId,
        EntryParamsBase memory baseParams,
        EntryParamsRisk memory riskParams,
        EntryParamsToken memory tokenParams
    ) internal {
        PendingEntry memory entry = pendingEntries[positionId];
        (uint256 minPrice, uint256 maxPrice) = parseEntryPriceHelper(baseParams);
        (MarginParams memory marginParams, LeverageParams memory leverageParams, RiskParams memory calcRiskParams) = computeParams(
            baseParams,
            riskParams,
            minPrice,
            entry.positionType
        );
        validateLeverageLimit(baseParams.listingAddr, leverageParams.leverageAmount, riskParams.leverageVal, entry.positionType);
        PosParamsCore memory coreParams = prepareCoreParams(
            tokenParams.normInitMargin,
            marginParams,
            tokenParams.normExtraMargin,
            minPrice,
            tokenParams.tokenAddr
        );
        PosParamsExt memory extParams = prepareExtParams(
            riskParams.leverageVal,
            riskParams.stopLoss,
            riskParams.takeProfit,
            leverageParams,
            calcRiskParams
        );
        updatePositionParamsCore(positionId, coreParams);
        updatePositionParamsExtended(positionId, extParams);
        positionToken[positionId] = tokenParams.tokenAddr;
        updateLiquidityFees(positionId, baseParams.listingAddr, entry.positionType, marginParams.marginInitial, riskParams.leverageVal);
    }

    // Helper: Update entry indexes
    function updateEntryIndexes(uint256 positionId) internal {
        PendingEntry memory entry = pendingEntries[positionId];
        updateIndexes(entry.makerAddress, entry.positionType, positionId, entry.listingAddr, true);
    }

    // Helper: Finalize entry transfer
    function finalizeEntryTransfer(uint256 positionId) internal {
        PendingEntry memory entry = pendingEntries[positionId];
        IERC20(entry.tokenAddr).transferFrom(
            msg.sender,
            entry.listingAddr,
            entry.initialMargin + entry.extraMargin
        );
        uint256 io = normalizeAmount(entry.tokenAddr, entry.initialMargin + entry.extraMargin);
        transferMarginToListing(entry.listingAddr, io, entry.positionType);
        updateHistoricalInterest(
            historicalInterestHeight,
            entry.positionType == 0 ? io : 0,
            entry.positionType == 1 ? io : 0,
            block.timestamp
        );
    }

    // Helper: Initiate entry
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
        positionId = positionIdCounter++;
        pendingEntries[positionId] = PendingEntry({
            listingAddr: context.listingAddr,
            tokenAddr: context.tokenAddr,
            positionId: positionId,
            positionType: positionType,
            initialMargin: initMargin,
            extraMargin: extraMargin,
            entryPriceStr: entryPriceStr,
            makerAddress: msg.sender
        });
        EntryParamsBase memory baseParams = prepareBaseParams(
            context.listingAddr,
            entryPriceStr,
            initMargin,
            extraMargin
        );
        EntryParamsRisk memory riskParams = prepareRiskParams(
            leverage,
            stopLoss,
            takeProfit
        );
        EntryParamsToken memory tokenParams = prepareTokenParams(context);
        validateEntryInputs(baseParams, riskParams);
        validateListing(baseParams.listingAddr);
        updateEntryCore(positionId, baseParams, positionType);
        updateEntryParams(positionId, baseParams, riskParams, tokenParams);
        updateEntryIndexes(positionId);
        finalizeEntryTransfer(positionId);
        uint256 returnedPositionId;
        uint256 minPrice;
        uint256 maxPrice;
        (returnedPositionId, minPrice, maxPrice) = positionType == 0
            ? prepareEnterLong(baseParams, riskParams, tokenParams)
            : prepareEnterShort(baseParams, riskParams, tokenParams);
        require(returnedPositionId == positionId, "Position ID mismatch");
        emit PositionEntered(
            positionId,
            msg.sender,
            context.listingAddr,
            positionType,
            minPrice,
            maxPrice
        );
        delete pendingEntries[positionId];
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
            0 // Long
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
            1 // Short
        );
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        PositionCoreBase memory coreBase = positionCoreBase[positionId];
        PositionCoreStatus memory coreStatus = positionCoreStatus[positionId];
        require(coreBase.makerAddress == msg.sender, "Not position owner");
        require(coreStatus.status2 == 0, "Position not open");

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
        require(coreStatus.status2 == 0, "Position not open");

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
        require(coreStatus.status2 == 0, "Position not open");

        uint256 normalizedAmount = normalizeAmount(token, amount);
        IERC20(token).transferFrom(msg.sender, coreBase.listingAddress, amount);

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
        require(coreStatus.status2 == 0, "Position not open");

        uint256 currentPrice = getCurrentPrice(coreBase.listingAddress);
        if (coreBase.positionType == 0) {
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
        require(coreStatus.status2 == 0, "Position not open");

        uint256 entryPrice = priceParams[positionId].priceAtEntry;
        if (coreBase.positionType == 0) {
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
        uint256 resultCount = executePositions(actions, listingAddress);
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
        for (uint256 i = 0; i < length; i++) {
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
        for (uint256 i = 0; i < length; i++) {
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
        for (uint256 i = 0; i < length; i++) {
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

    // Events
    event PositionEntered(uint256 indexed positionId, address indexed user, address listingAddress, uint8 positionType, uint256 minPrice, uint256 maxPrice);
    event PositionClosed(uint256 indexed positionId, address indexed user, uint256 payout);
    event PositionCancelled(uint256 indexed positionId, address indexed user);
    event ExcessMarginAdded(uint256 indexed positionId, address indexed user, uint256 amount);
    event StopLossUpdated(uint256 indexed positionId, address indexed user, uint256 newStopLossPrice);
    event TakeProfitUpdated(uint256 indexed positionId, address indexed user, uint256 newTakeProfitPrice);
    event AllShortsClosed(address indexed user, uint256 count);
    event AllShortsCancelled(address indexed user, uint256 count);
    event AllLongsClosed(address indexed user, uint256 count);
    event AllLongsCancelled(address indexed user, uint256 count);
    event PositionsExecuted(address indexed listingAddress, uint256 resultCount);
}