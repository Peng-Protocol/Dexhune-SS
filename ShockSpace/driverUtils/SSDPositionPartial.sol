// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.5:
// - Split finalizePosition into modular functions: updateHistoricalInterest, updateLiquidityFees.
// - Adjusted prepareEnterLong/prepareEnterShort to return only positionId, minPrice, maxPrice.
// - Compatible with SSDUtilityPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.9, SSIsolatedDriver.sol v0.0.5.
// - v0.0.4:
//   - Fixed TypeError: Wrong argument count for liquidityAddressView calls in validateLeverageLimit and finalizePosition.
//   - Compatible with SSDUtilityPartial.sol v0.0.5, SSDExecutionPartial.sol v0.0.7, SSIsolatedDriver.sol v0.0.2.

import "./SSDUtilityPartial.sol";

contract SSDPositionPartial is SSDUtilityPartial {
    using SafeERC20 for IERC20;

    // Validate inputs for entry functions
    function validateEntryInputs(EntryParamsBase memory baseParams, EntryParamsRisk memory riskParams) internal pure {
        require(baseParams.initMargin > 0, "Invalid margin");
        require(riskParams.leverageVal >= 2 && riskParams.leverageVal <= 100, "Invalid leverage");
        require(baseParams.listingAddr != address(0), "Invalid listing");
    }

    // Parse entry price
    function parseEntryPriceHelper(EntryParamsBase memory baseParams) internal view returns (uint256 minPrice, uint256 maxPrice) {
        (minPrice, maxPrice) = parseEntryPrice(baseParams.entryPriceStr, baseParams.listingAddr);
        require(minPrice > 0, "Invalid entry price");
    }

    // Generate position ID
    function generatePositionId(EntryParamsBase memory baseParams, uint256 typeNonce) internal returns (uint256) {
        return positionIdCounter++;
    }

    // Prepare PositionCore
    function preparePositionCore(
        address maker,
        uint256 positionId,
        uint8 positionType,
        address listingAddress
    ) internal pure returns (PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus) {
        coreBase = PositionCoreBase({
            makerAddress: maker,
            listingAddress: listingAddress,
            positionId: positionId,
            positionType: positionType
        });
        coreStatus = PositionCoreStatus({
            status1: false, // Pending
            status2: 0 // Open
        });
    }

    // Compute position parameters
    function computeParamsHelper(
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 minPrice,
        uint8 positionType
    ) internal view returns (
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory calcRiskParams
    ) {
        marginParams.marginTaxed = initialMargin - ((leverage - 1) * initialMargin / 100);
        leverageParams.leverageAmount = initialMargin * leverage;
        require(leverageParams.leverageAmount > 0, "Invalid leverage amount");

        uint256 marginRatio = (excessMargin + marginParams.marginTaxed) / leverageParams.leverageAmount;
        calcRiskParams.priceLiquidation = positionType == 0
            ? (marginRatio < minPrice ? minPrice - marginRatio : 0)
            : minPrice + marginRatio;

        uint256 priceFactor = minPrice / 1e18;
        leverageParams.loanInitial = positionType == 0
            ? leverageParams.leverageAmount / priceFactor
            : leverageParams.leverageAmount * minPrice;

        marginParams.marginInitial = initialMargin;
        marginParams.marginExcess = excessMargin;
        leverageParams.leverageVal = leverage;
    }

    // Prepare core params
    function prepareCoreParams(
        uint256 normInitMargin,
        MarginParams memory calcMarginParams,
        uint256 normExtraMargin,
        uint256 minPrice,
        address tokenAddr
    ) internal view returns (PosParamsCore memory coreParams) {
        coreParams.priceParams = PriceParams({
            priceMin: minPrice,
            priceMax: minPrice,
            priceAtEntry: minPrice,
            priceClose: 0
        });
        coreParams.marginParams = MarginParams({
            marginInitial: normInitMargin,
            marginTaxed: normalizeAmount(tokenAddr, calcMarginParams.marginTaxed),
            marginExcess: normExtraMargin
        });
    }

    // Prepare extended params
    function prepareExtParams(
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit,
        LeverageParams memory calcLeverageParams,
        RiskParams memory calcRiskParams
    ) internal pure returns (PosParamsExt memory extParams) {
        extParams.leverageParams = LeverageParams({
            leverageVal: leverage,
            leverageAmount: calcLeverageParams.leverageAmount,
            loanInitial: calcLeverageParams.loanInitial
        });
        extParams.riskParams = RiskParams({
            priceLiquidation: calcRiskParams.priceLiquidation,
            priceStopLoss: stopLoss,
            priceTakeProfit: takeProfit
        });
    }

    // Prepare all params
    function prepareParams(
        EntryParamsBase memory baseParams,
        EntryParamsRisk memory riskParams,
        EntryParamsToken memory tokenParams,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory calcRiskParams,
        uint256 minPrice
    ) internal view returns (
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    ) {
        coreParams = prepareCoreParams(
            tokenParams.normInitMargin,
            marginParams,
            tokenParams.normExtraMargin,
            minPrice,
            tokenParams.tokenAddr
        );
        extParams = prepareExtParams(
            riskParams.leverageVal,
            riskParams.stopLoss,
            riskParams.takeProfit,
            leverageParams,
            calcRiskParams
        );
    }

    // Compute parameters
    function computeParams(
        EntryParamsBase memory baseParams,
        EntryParamsRisk memory riskParams,
        uint256 minPrice,
        uint8 positionType
    ) internal view returns (
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory calcRiskParams
    ) {
        return computeParamsHelper(
            baseParams.initMargin,
            baseParams.extraMargin,
            riskParams.leverageVal,
            minPrice,
            positionType
        );
    }

    // Prepare core
    function prepareCore(
        EntryParamsBase memory baseParams,
        uint256 positionId,
        uint8 positionType
    ) internal view returns (PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus) {
        return preparePositionCore(
            msg.sender,
            positionId,
            positionType,
            baseParams.listingAddr
        );
    }

    // Validate listing via ISSAgent
    function validateListing(address listingAddress) internal view {
        require(agent != address(0), "Agent not set");
        address tokenA = ISSListing(listingAddress).tokenA();
        address tokenB = ISSListing(listingAddress).tokenB();
        address validListing = ISSAgent(agent).getListing(tokenA, tokenB);
        require(validListing == listingAddress, "Invalid listing");
    }

    // Validate leverage limit
    function validateLeverageLimit(
        address listingAddress,
        uint256 leverageAmount,
        uint8 leverageVal,
        uint8 positionType
    ) internal view {
        address liquidityAddress = ISSListing(listingAddress).liquidityAddressView();
        (uint256 xLiquid, uint256 yLiquid,,) = ISSLiquidityTemplate(liquidityAddress).liquidityDetailsView();
        uint256 limitPercent = 101 - leverageVal;
        uint256 limit = positionType == 0
            ? (xLiquid * limitPercent) / 100
            : (yLiquid * limitPercent) / 100;
        require(leverageAmount <= limit, "Leverage exceeds liquidity limit");
    }

    // Validate stop loss and take profit
    function validateRiskParams(
        PosParamsExt memory extParams,
        uint256 minPrice,
        uint8 positionType
    ) internal pure {
        if (positionType == 0) {
            require(
                extParams.riskParams.priceStopLoss == 0 || extParams.riskParams.priceStopLoss < minPrice,
                "Invalid stop loss for long"
            );
            require(
                extParams.riskParams.priceTakeProfit == 0 || extParams.riskParams.priceTakeProfit > minPrice,
                "Invalid take profit for long"
            );
        } else {
            require(
                extParams.riskParams.priceStopLoss == 0 || extParams.riskParams.priceStopLoss > minPrice,
                "Invalid stop loss for short"
            );
            require(
                extParams.riskParams.priceTakeProfit == 0 || extParams.riskParams.priceTakeProfit < minPrice,
                "Invalid take profit for short"
            );
        }
    }

    // Transfer margin to listing via update
    function transferMarginToListing(
        address listingAddress,
        uint256 amount,
        uint8 positionType
    ) internal {
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType({
            updateType: 0,
            index: positionType == 0 ? 0 : 1, // 0: xBalance, 1: yBalance
            value: amount,
            addr: address(0),
            recipient: address(0)
        });
        ISSListing(listingAddress).update(address(this), updates);
    }

    // Update historical interest
    function updateHistoricalInterest(
        uint256 index,
        uint256 longIO,
        uint256 shortIO,
        uint256 timestamp
    ) internal {
        longIOByHeight[index] += longIO;
        shortIOByHeight[index] += shortIO;
        if (longIO > 0 || shortIO > 0) {
            historicalInterestTimestamps[index] = timestamp;
            historicalInterestHeight++;
        }
    }

    // Update liquidity fees
    function updateLiquidityFees(
        uint256 positionId,
        address listingAddress,
        uint8 positionType,
        uint256 marginInitial,
        uint8 leverageVal
    ) internal {
        address liquidityAddress = ISSListing(listingAddress).liquidityAddressView();
        uint256 fee = (leverageVal - 1) * marginInitial / 100;
        if (fee > 0) {
            ISSLiquidityTemplate(liquidityAddress).addFees(address(this), positionType == 0, fee);
        }
    }

    // Prepare core and extended params
    function prepareCoreAndParams(
        EntryParamsBase memory baseParams,
        EntryParamsRisk memory riskParams,
        EntryParamsToken memory tokenParams,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 positionId,
        uint8 positionType
    ) internal view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    ) {
        validateListing(baseParams.listingAddr);
        (coreBase, coreStatus) = prepareCore(baseParams, positionId, positionType);
        (MarginParams memory marginParams, LeverageParams memory leverageParams, RiskParams memory calcRiskParams) = computeParams(
            baseParams,
            riskParams,
            minPrice,
            positionType
        );
        validateLeverageLimit(baseParams.listingAddr, leverageParams.leverageAmount, riskParams.leverageVal, positionType);
        (coreParams, extParams) = prepareParams(baseParams, riskParams, tokenParams, marginParams, leverageParams, calcRiskParams, minPrice);
        require(coreParams.marginParams.marginExcess <= extParams.leverageParams.leverageAmount, "Excess margin exceeds leverage");
        validateRiskParams(extParams, minPrice, positionType);
    }

    // Prepare enterLong
    function prepareEnterLong(
        EntryParamsBase memory baseParams,
        EntryParamsRisk memory riskParams,
        EntryParamsToken memory tokenParams
    ) internal returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice
    ) {
        validateEntryInputs(baseParams, riskParams);
        (minPrice, maxPrice) = parseEntryPriceHelper(baseParams);
        positionId = generatePositionId(baseParams, 0);
    }

    // Prepare enterShort
    function prepareEnterShort(
        EntryParamsBase memory baseParams,
        EntryParamsRisk memory riskParams,
        EntryParamsToken memory tokenParams
    ) internal returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice
    ) {
        validateEntryInputs(baseParams, riskParams);
        (minPrice, maxPrice) = parseEntryPriceHelper(baseParams);
        positionId = generatePositionId(baseParams, 1);
    }

    // Update position core
    function updatePositionCore(uint256 positionId, PositionCoreBase memory coreBase, PositionCoreStatus memory coreStatus) internal {
        positionCoreBase[positionId] = coreBase;
        positionCoreStatus[positionId] = coreStatus;
    }

    // Update position params core
    function updatePositionParamsCore(uint256 positionId, PosParamsCore memory params) internal {
        priceParams[positionId] = params.priceParams;
        marginParams[positionId] = params.marginParams;
    }

    // Update position params extended
    function updatePositionParamsExtended(uint256 positionId, PosParamsExt memory params) internal {
        leverageParams[positionId] = params.leverageParams;
        riskParams[positionId] = params.riskParams;
    }

    // Update indexes
    function updateIndexes(
        address user,
        uint8 positionType,
        uint256 positionId,
        address listingAddress,
        bool isPending
    ) internal {
        if (isPending) {
            pendingPositions[listingAddress][positionType].push(positionId);
        } else {
            positionsByType[positionType].push(positionId);
        }
    }
}