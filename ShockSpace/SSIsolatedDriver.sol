// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.2:
// - Updated enterLong/enterShort to transfer margins via IERC20.safeTransferFrom and ISSListing.update.
// - Added ISSAgent validation using tokenA/tokenB from listing.
// - Updated updateSL/updateTP to use msg.sender, validate against currentPrice/priceAtEntry.
// - Added maxIterations to close/cancel functions.
// - Added view functions: positionsByTypeView, positionsByAddressView, positionByIndex, queryInterest.
// - Added setAgent (owner-only).
// - Compatible with SSDUtilityPartial.sol v0.0.2, SSDPositionPartial.sol v0.0.2, SSDExecutionPartial.sol v0.0.2.

import "./driverUtils/SSDExecutionPartial.sol";
import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";

contract SSIsolatedDriver is SSDExecutionPartial, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Constructor
    constructor() Ownable() {
        historicalInterestHeight = 1;
        nonce = 0;
        positionIdCounter = 1;
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

    // Enter long position
    function enterLong(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverageVal,
        uint256 stopLoss,
        uint256 takeProfit,
        address tokenAddr
    ) external nonReentrant {
        (uint256 normInitMargin, uint256 normExtraMargin) = normalizeMargins(tokenAddr, initMargin, extraMargin);

        EntryParamsBase memory baseParams = EntryParamsBase({
            listingAddr: listingAddr,
            entryPriceStr: entryPriceStr,
            initMargin: initMargin,
            extraMargin: extraMargin
        });
        EntryParamsRisk memory riskParams = EntryParamsRisk({
            leverageVal: leverageVal,
            stopLoss: stopLoss,
            takeProfit: takeProfit
        });
        EntryParamsToken memory tokenParams = EntryParamsToken({
            tokenAddr: tokenAddr,
            normInitMargin: normInitMargin,
            normExtraMargin: normExtraMargin,
            driverAddr: address(this)
        });

        (uint256 positionId, uint256 minPrice, uint256 maxPrice, PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus, PosParamsCore memory coreParams, PosParamsExt memory extParams) =
            prepareEnterLong(baseParams, riskParams, tokenParams);

        IERC20(tokenAddr).safeTransferFrom(msg.sender, listingAddr, initMargin + extraMargin);
        finalizePosition(positionId, coreBase, coreStatus, coreParams, extParams);

        emit PositionEntered(positionId, msg.sender, listingAddr, 0, minPrice, maxPrice);
    }

    // Enter short position
    function enterShort(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverageVal,
        uint256 stopLoss,
        uint256 takeProfit,
        address tokenAddr
    ) external nonReentrant {
        (uint256 normInitMargin, uint256 normExtraMargin) = normalizeMargins(tokenAddr, initMargin, extraMargin);

        EntryParamsBase memory baseParams = EntryParamsBase({
            listingAddr: listingAddr,
            entryPriceStr: entryPriceStr,
            initMargin: initMargin,
            extraMargin: extraMargin
        });
        EntryParamsRisk memory riskParams = EntryParamsRisk({
            leverageVal: leverageVal,
            stopLoss: stopLoss,
            takeProfit: takeProfit
        });
        EntryParamsToken memory tokenParams = EntryParamsToken({
            tokenAddr: tokenAddr,
            normInitMargin: normInitMargin,
            normExtraMargin: normExtraMargin,
            driverAddr: address(this)
        });

        (uint256 positionId, uint256 minPrice, uint256 maxPrice, PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus, PosParamsCore memory coreParams, PosParamsExt memory extParams) =
            prepareEnterShort(baseParams, riskParams, tokenParams);

        IERC20(tokenAddr).safeTransferFrom(msg.sender, listingAddr, initMargin + extraMargin);
        finalizePosition(positionId, coreBase, coreStatus, coreParams, extParams);

        emit PositionEntered(positionId, msg.sender, listingAddr, 1, minPrice, maxPrice);
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
        IERC20(token).safeTransferFrom(msg.sender, coreBase.listingAddress, amount);

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