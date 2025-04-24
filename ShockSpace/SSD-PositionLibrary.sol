// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.23:
// - Fixed stack too deep in prepareParams by splitting preparePositionParams into helper functions.
// - Optimized prepareCoreAndParams to reduce stack usage.
// - Retained changes from v0.0.22:
//   - Fixed ParserError: Expected ',' but got ';' in prepareCoreAndParams.
//   - Fixed stack depth errors in prepareCoreAndParams using incremental helper functions.
//   - Fixed TypeError: Changed generatePositionId to view.
//   - Fixed TypeError: Resolved DECIMAL_PRECISION reference.
//   - Added timestamp support for historical interest.
//   - Refactored PositionParams to PriceParams, MarginParams, LeverageParams, RiskParams.
// - Improved formatting for readability and consistency.
// - Compatible with SS-IsolatedDriver.sol v0.0.17, SSD-ExecutionLibrary.sol v0.0.4, SSD-UtilityLibrary.sol v0.0.9.

import "./imports/SafeERC20.sol";
import "./imports/Strings.sol";
import "./imports/IERC20Metadata.sol";

// Structs
struct PriceParams {
    uint256 priceMin;
    uint256 priceMax;
    uint256 priceAtEntry;
    uint256 priceClose;
}

struct MarginParams {
    uint256 marginInitial;
    uint256 marginTaxed;
    uint256 marginExcess;
}

struct LeverageParams {
    uint8 leverageVal;
    uint256 leverageAmount;
    uint256 loanInitial;
}

struct RiskParams {
    uint256 priceLiquidation;
    uint256 priceStopLoss;
    uint256 priceTakeProfit;
}

struct PosParamsCore {
    PriceParams priceParams;
    MarginParams marginParams;
}

struct PosParamsExt {
    LeverageParams leverageParams;
    RiskParams riskParams;
}

struct PayoutUpdate {
    address recipient;
    uint256 required;
    uint8 payoutType; // 0: Long, 1: Short
}

struct PositionAction {
    uint256 positionId;
    uint8 actionType; // 0: Update status, 1: Close
}

struct PositionCore {
    address makerAddress;
    address listingAddress;
    uint256 positionId;
    uint8 positionType; // 0: Long, 1: Short
    bool status1; // false: pending, true: executable
    uint8 status2; // 0: open, 1: closed, 2: cancelled
}

struct EntryParams {
    address listingAddr;
    string entryPriceStr;
    uint256 initMargin;
    uint256 extraMargin;
    uint8 leverageVal;
    uint256 stopLoss;
    uint256 takeProfit;
    address tokenAddr;
    uint256 normInitMargin;
    uint256 normExtraMargin;
    address driverAddr;
}

// Interfaces
interface ISSListing {
    function prices(uint256 listingId) external view returns (uint256);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

interface ISSUtilityLibrary {
    function normalizeAmount(address token, uint256 amount) external view returns (uint256);
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice);
    function parseUint(string memory str) external pure returns (uint256);
}

interface ISSIsolatedDriver {
    function positionCore(uint256 positionId) external view returns (PositionCore memory);
    function priceParams(uint256 positionId) external view returns (PriceParams memory);
    function marginParams(uint256 positionId) external view returns (MarginParams memory);
    function leverageParams(uint256 positionId) external view returns (LeverageParams memory);
    function riskParams(uint256 positionId) external view returns (RiskParams memory);
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    function historicalInterestHeight() external view returns (uint256);
    function historicalInterestTimestamps(uint256 height) external view returns (uint256);
    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO, uint256 timestamp) external;
    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO, uint256 timestamp) external;
}

interface ISSPositionLibrary {
    function prepareEnterLong(
        EntryParams memory params
    ) external view returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    );
    function prepareEnterShort(
        EntryParams memory params
    ) external view returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    );
    function finalizePosition(
        uint256 positionId,
        PositionCore memory core,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams,
        address driver
    ) external;
    function updatePositionCore(uint256 positionId, PositionCore memory core, address driver) external;
    function updatePositionParamsCore(uint256 positionId, PosParamsCore memory params, address driver) external;
    function updatePositionParamsExtended(uint256 positionId, PosParamsExt memory params, address driver) external;
    function updateIndexes(address user, uint8 positionType, uint256 positionId, address listingAddress, bool isPending, address driver) external;
    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO, uint256 timestamp, address driver) external;
}

library SSPositionLibrary {
    using SafeERC20 for IERC20;

    // Restrict calls to driver
    modifier onlyDriver(address driver) {
        require(msg.sender == driver, "Driver only");
        _;
    }

    // Validate inputs for entry functions
    function validateEntryInputs(EntryParams memory validateParams) internal pure {
        require(validateParams.initMargin > 0, "Invalid margin");
        require(validateParams.leverageVal >= 2 && validateParams.leverageVal <= 100, "Invalid leverage");
        require(validateParams.listingAddr != address(0), "Invalid listing");
    }

    // Parse entry price
    function parseEntryPriceHelper(EntryParams memory parseParams) internal view returns (uint256 minPrice, uint256 maxPrice) {
        (minPrice, maxPrice) = ISSUtilityLibrary(parseParams.driverAddr).parseEntryPrice(
            parseParams.entryPriceStr,
            parseParams.listingAddr
        );
        require(minPrice > 0, "Invalid entry price");
    }

    // Generate position ID
    function generatePositionId(EntryParams memory idParams, uint256 nonce) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(idParams.listingAddr, block.timestamp, nonce)));
    }

    // Prepare PositionCore
    function preparePositionCore(
        address maker,
        uint256 positionId,
        uint8 positionType,
        address listingAddress
    ) internal pure returns (PositionCore memory core) {
        core = PositionCore({
            makerAddress: maker,
            listingAddress: listingAddress,
            positionId: positionId,
            positionType: positionType,
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
        uint8 positionType,
        address driver
    ) internal view returns (
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams
    ) {
        marginParams.marginTaxed = initialMargin - ((leverage - 1) * initialMargin / 100);
        leverageParams.leverageAmount = initialMargin * leverage;
        require(leverageParams.leverageAmount > 0, "Invalid leverage amount");

        uint256 marginRatio = (excessMargin + marginParams.marginTaxed) / leverageParams.leverageAmount;
        riskParams.priceLiquidation = positionType == 0
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

    // Helper to prepare core params
    function prepareCoreParams(
        uint256 normInitMargin,
        MarginParams memory calcMarginParams,
        uint256 normExtraMargin,
        uint256 minPrice,
        address tokenAddr,
        address driver
    ) internal view returns (PosParamsCore memory coreParams) {
        coreParams.priceParams = PriceParams({
            priceMin: minPrice,
            priceMax: minPrice,
            priceAtEntry: minPrice,
            priceClose: 0
        });
        coreParams.marginParams = MarginParams({
            marginInitial: normInitMargin,
            marginTaxed: ISSUtilityLibrary(driver).normalizeAmount(tokenAddr, calcMarginParams.marginTaxed),
            marginExcess: normExtraMargin
        });
    }

    // Helper to prepare extended params
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
        EntryParams memory entryCoreParams,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams,
        uint256 minPrice
    ) internal view returns (
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    ) {
        coreParams = prepareCoreParams(
            entryCoreParams.normInitMargin,
            marginParams,
            entryCoreParams.normExtraMargin,
            minPrice,
            entryCoreParams.tokenAddr,
            entryCoreParams.driverAddr
        );
        extParams = prepareExtParams(
            entryCoreParams.leverageVal,
            entryCoreParams.stopLoss,
            entryCoreParams.takeProfit,
            leverageParams,
            riskParams
        );
    }

    // Compute parameters
    function computeParams(
        EntryParams memory entryCoreParams,
        uint256 minPrice,
        uint8 positionType
    ) internal view returns (
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams
    ) {
        return computeParamsHelper(
            entryCoreParams.initMargin,
            entryCoreParams.extraMargin,
            entryCoreParams.leverageVal,
            minPrice,
            positionType,
            entryCoreParams.driverAddr
        );
    }

    // Prepare core
    function prepareCore(
        EntryParams memory entryCoreParams,
        uint256 positionId,
        uint8 positionType
    ) internal view returns (PositionCore memory core) {
        return preparePositionCore(
            msg.sender,
            positionId,
            positionType,
            entryCoreParams.listingAddr
        );
    }

    // Prepare core and extended params
    function prepareCoreAndParams(
        EntryParams memory entryCoreParams,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 positionId,
        uint8 positionType
    ) internal view returns (
        PositionCore memory core,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    ) {
        core = prepareCore(entryCoreParams, positionId, positionType);
        (MarginParams memory marginParams, LeverageParams memory leverageParams, RiskParams memory riskParams) = computeParams(
            entryCoreParams,
            minPrice,
            positionType
        );
        (coreParams, extParams) = prepareParams(entryCoreParams, marginParams, leverageParams, riskParams, minPrice);
    }

    // Prepare enterLong
    function prepareEnterLong(
        EntryParams memory longEntryParams
    ) external view onlyDriver(longEntryParams.driverAddr) returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    ) {
        validateEntryInputs(longEntryParams);
        (minPrice, maxPrice) = parseEntryPriceHelper(longEntryParams);
        positionId = generatePositionId(longEntryParams, 0);
        (core, coreParams, extParams) = prepareCoreAndParams(longEntryParams, minPrice, maxPrice, positionId, 0);
    }

    // Prepare enterShort
    function prepareEnterShort(
        EntryParams memory shortEntryParams
    ) external view onlyDriver(shortEntryParams.driverAddr) returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams
    ) {
        validateEntryInputs(shortEntryParams);
        (minPrice, maxPrice) = parseEntryPriceHelper(shortEntryParams);
        positionId = generatePositionId(shortEntryParams, 1);
        (core, coreParams, extParams) = prepareCoreAndParams(shortEntryParams, minPrice, maxPrice, positionId, 1);
    }

    // Update position core
    function updatePositionCore(uint256 positionId, PositionCore memory core, address driver) internal {
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "setPositionCore(uint256,(address,address,uint256,uint8,bool,uint8))",
                positionId,
                core
            )
        );
        require(success, "Core storage failed");
    }

    // Update position params core
    function updatePositionParamsCore(uint256 positionId, PosParamsCore memory params, address driver) internal {
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionParamsCore(uint256,(uint256,uint256,uint256,uint256,uint256,uint256))",
                positionId,
                params
            )
        );
        require(success, "Params core storage failed");
    }

    // Update position params extended
    function updatePositionParamsExtended(uint256 positionId, PosParamsExt memory params, address driver) internal {
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionParamsExtended(uint256,(uint8,uint256,uint256,uint256,uint256,uint256))",
                positionId,
                params
            )
        );
        require(success, "Params extended storage failed");
    }

    // Update indexes
    function updateIndexes(
        address user,
        uint8 positionType,
        uint256 positionId,
        address listingAddress,
        bool isPending,
        address driver
    ) internal {
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updateIndexes(address,uint8,uint256,address,bool)",
                user,
                positionType,
                positionId,
                listingAddress,
                isPending
            )
        );
        require(success, "Index update failed");
    }

    // Update historical interest
    function updateHistoricalInterest(
        uint256 index,
        uint256 longIO,
        uint256 shortIO,
        uint256 timestamp,
        address driver
    ) internal {
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updateHistoricalInterest(uint256,uint256,uint256,uint256)",
                index,
                longIO,
                shortIO,
                timestamp
            )
        );
        require(success, "Interest update failed");
    }

    // Finalize position
    function finalizePosition(
        uint256 positionId,
        PositionCore memory core,
        PosParamsCore memory coreParams,
        PosParamsExt memory extParams,
        address driver
    ) external onlyDriver(driver) {
        updatePositionCore(positionId, core, driver);
        updatePositionParamsCore(positionId, coreParams, driver);
        updatePositionParamsExtended(positionId, extParams, driver);
        updateIndexes(core.makerAddress, core.positionType, positionId, core.listingAddress, true, driver);

        uint256 io = coreParams.marginParams.marginTaxed + coreParams.marginParams.marginExcess;
        updateHistoricalInterest(
            ISSIsolatedDriver(driver).historicalInterestHeight(),
            core.positionType == 0 ? io : 0,
            core.positionType == 1 ? io : 0,
            block.timestamp,
            driver
        );
    }
}