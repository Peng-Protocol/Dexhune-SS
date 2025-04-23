// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.20:
// - Fixed typo in setPositionCore function signature:
//   - Corrected "uint256aml" to "uint256 positionId".
// - Addressed stack depth errors in enterLong and enterShort:
//   - Introduced PositionEntryData struct to consolidate position data (positionId, minPrice, maxPrice, core, coreParams, extParams).
//   - Updated helper functions to use PositionEntryData struct, reducing stack usage.
//   - Maintained functionality of position creation and parameter handling.
// - Renamed set$ functions to remove "$" (per user clarification):
//   - set$PositionLibrary → setPositionLibrary.
//   - set$ExecutionLibrary → setExecutionLibrary.
//   - set$UtilityLibrary → setUtilityLibrary.
// - Retained changes from v0.0.19:
//   - Refactored enterLong and enterShort with helper functions (normalizeMargins, preparePosition, transferTokens, finalizePositionEntry).
//   - Fixed constructor issue with Ownable.
//   - Added timestamp support for historical interest.
//   - Refactored PositionParams to modular structs (PriceParams, MarginParams, LeverageParams, RiskParams).
// - Compatible with SSD-PositionLibrary.sol v0.0.19, SSD-ExecutionLibrary.sol v0.0.4, SSD-UtilityLibrary.sol v0.0.5.
// - Uses SafeERC20, ReentrancyGuard, Ownable for security.

import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";
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

struct PositionEntryData {
    uint256 positionId;
    uint256 minPrice;
    uint256 maxPrice;
    PositionCore core;
    PosParamsCore coreParams;
    PosParamsExt extParams;
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

struct ClosePositionParams {
    uint256 positionId;
    address listingAddress;
    address makerAddress;
    uint256 taxedMargin;
    uint256 excessMargin;
    address driver;
}

struct LongCloseParams {
    uint256 leverageAmount;
    uint256 initialLoan;
}

struct ShortCloseParams {
    uint256 minPrice;
    uint256 initialMargin;
    uint8 leverage;
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

interface ISSExecutionLibrary {
    function prepareExecution(
        address listingAddress,
        address driver
    ) external view returns (PositionAction[] memory);
    function executePositions(
        PositionAction[] memory actions,
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount);
    function closeLongPosition(
        ClosePositionParams memory params,
        LongCloseParams memory longParams
    ) external returns (uint256 payout);
    function closeShortPosition(
        ClosePositionParams memory params,
        ShortCloseParams memory shortParams
    ) external returns (uint256 payout);
    function cancelPosition(
        ClosePositionParams memory params,
        uint8 positionType
    ) external;
    function addExcessMargin(
        uint256 positionId,
        uint256 amount,
        address token,
        address listingAddress,
        uint8 positionType,
        uint256 normalizedAmount,
        address driver
    ) external;
    function updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint8 positionType,
        address makerAddress,
        uint256 minPrice,
        uint256 maxPrice,
        address driver
    ) external;
    function updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        uint8 positionType,
        address makerAddress,
        uint256 minPrice,
        uint256 maxPrice,
        address driver
    ) external;
    function closeAllShort(address user, address driver) external returns (uint256 count);
    function cancelAllShort(address user, address driver) external returns (uint256 count);
    function closeAllLongs(address user, address driver) external returns (uint256 count);
    function cancelAllLong(address user, address driver) external returns (uint256 count);
}

contract SSIsolatedDriver is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // State variables
    mapping(uint256 => PositionCore) public positionCore;
    mapping(uint256 => PriceParams) public priceParams;
    mapping(uint256 => MarginParams) public marginParams;
    mapping(uint256 => LeverageParams) public leverageParams;
    mapping(uint256 => RiskParams) public riskParams;
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions;
    mapping(uint8 => uint256[]) public positionsByType;
    mapping(uint256 => uint256) public longIOByHeight;
    mapping(uint256 => uint256) public shortIOByHeight;
    mapping(uint256 => uint256) public historicalInterestTimestamps;
    uint256 public historicalInterestHeight;
    uint256 public nonce;

    address public positionLibrary;
    address public executionLibrary;
    address public utilityLibrary;

    // Constructor
    constructor() {
        historicalInterestHeight = 1;
        nonce = 0;
    }

    // Modifier to check library initialization
    modifier librariesInitialized() {
        require(positionLibrary != address(0), "Position library not set");
        require(executionLibrary != address(0), "Execution library not set");
        require(utilityLibrary != address(0), "Utility library not set");
        _;
    }

    // Set library addresses
    function setPositionLibrary(address _positionLibrary) external onlyOwner {
        require(_positionLibrary != address(0), "Invalid position library");
        positionLibrary = _positionLibrary;
    }

    function setExecutionLibrary(address _executionLibrary) external onlyOwner {
        require(_executionLibrary != address(0), "Invalid execution library");
        executionLibrary = _executionLibrary;
    }

    function setUtilityLibrary(address _utilityLibrary) external onlyOwner {
        require(_utilityLibrary != address(0), "Invalid utility library");
        utilityLibrary = _utilityLibrary;
    }

    // Set position core
    function setPositionCore(uint256 positionId, PositionCore memory core) external {
        require(msg.sender == positionLibrary, "Only position library");
        positionCore[positionId] = core;
    }

    // Update position status
    function updatePositionStatus(uint256 positionId, uint8 status) external {
        require(msg.sender == executionLibrary, "Only execution library");
        positionCore[positionId].status2 = status;
        if (status == 0) {
            positionCore[positionId].status1 = true;
        }
    }

    // Update position params core
    function updatePositionParamsCore(uint256 positionId, PosParamsCore memory params) external {
        require(msg.sender == positionLibrary, "Only position library");
        priceParams[positionId] = params.priceParams;
        marginParams[positionId] = params.marginParams;
    }

    // Update position params extended
    function updatePositionParamsExtended(uint256 positionId, PosParamsExt memory params) external {
        require(msg.sender == positionLibrary, "Only position library");
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
    ) external {
        require(msg.sender == positionLibrary, "Only position library");
        if (isPending) {
            pendingPositions[listingAddress][positionType].push(positionId);
        } else {
            positionsByType[positionType].push(positionId);
        }
    }

    // Update historical interest
    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO, uint256 timestamp) external {
        require(msg.sender == positionLibrary || msg.sender == executionLibrary, "Only libraries");
        longIOByHeight[index] += longIO;
        shortIOByHeight[index] += shortIO;
        if (longIO > 0 || shortIO > 0) {
            historicalInterestTimestamps[index] = timestamp;
            historicalInterestHeight++;
        }
    }

    // Reduce historical interest
    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO, uint256 timestamp) external {
        require(msg.sender == executionLibrary, "Only execution library");
        longIOByHeight[index] -= longIO;
        shortIOByHeight[index] -= shortIO;
        // Timestamp not used for reductions, included for interface consistency
    }

    // Update excess margin
    function updateExcessMargin(uint256 positionId, uint256 amount) external {
        require(msg.sender == executionLibrary, "Only execution library");
        marginParams[positionId].marginExcess += amount;
    }

    // Update stop loss
    function updatePositionSL(uint256 positionId, uint256 newStopLossPrice) external {
        require(msg.sender == executionLibrary, "Only execution library");
        riskParams[positionId].priceStopLoss = newStopLossPrice;
    }

    // Update take profit
    function updatePositionTP(uint256 positionId, uint256 newTakeProfitPrice) external {
        require(msg.sender == executionLibrary, "Only execution library");
        riskParams[positionId].priceTakeProfit = newTakeProfitPrice;
    }

    // Helper: Normalize margin amounts
    function normalizeMargins(
        address tokenAddr,
        uint256 initMargin,
        uint256 extraMargin
    ) internal view returns (uint256 normInitMargin, uint256 normExtraMargin) {
        normInitMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(tokenAddr, initMargin);
        normExtraMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(tokenAddr, extraMargin);
    }

    // Helper: Prepare position parameters
    function preparePosition(
        EntryParams memory params,
        bool isLong
    ) internal view returns (PositionEntryData memory entryData) {
        if (isLong) {
            (entryData.positionId, entryData.minPrice, entryData.maxPrice, entryData.core, entryData.coreParams, entryData.extParams) =
                ISSPositionLibrary(positionLibrary).prepareEnterLong(params);
        } else {
            (entryData.positionId, entryData.minPrice, entryData.maxPrice, entryData.core, entryData.coreParams, entryData.extParams) =
                ISSPositionLibrary(positionLibrary).prepareEnterShort(params);
        }
    }

    // Helper: Transfer tokens
    function transferTokens(address tokenAddr, uint256 initMargin, uint256 extraMargin) internal {
        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), initMargin + extraMargin);
    }

    // Helper: Finalize position entry
    function finalizePositionEntry(PositionEntryData memory entryData) internal {
        ISSPositionLibrary(positionLibrary).finalizePosition(
            entryData.positionId,
            entryData.core,
            entryData.coreParams,
            entryData.extParams,
            address(this)
        );
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
    ) external nonReentrant librariesInitialized {
        // Normalize margins
        (uint256 normInitMargin, uint256 normExtraMargin) = normalizeMargins(tokenAddr, initMargin, extraMargin);

        // Build EntryParams
        EntryParams memory params = EntryParams({
            listingAddr: listingAddr,
            entryPriceStr: entryPriceStr,
            initMargin: initMargin,
            extraMargin: extraMargin,
            leverageVal: leverageVal,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            tokenAddr: tokenAddr,
            normInitMargin: normInitMargin,
            normExtraMargin: normExtraMargin,
            driverAddr: address(this)
        });

        // Prepare position
        PositionEntryData memory entryData = preparePosition(params, true);

        // Transfer tokens
        transferTokens(tokenAddr, initMargin, extraMargin);

        // Finalize position
        finalizePositionEntry(entryData);

        emit PositionEntered(entryData.positionId, msg.sender, listingAddr, 0, entryData.minPrice, entryData.maxPrice);
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
    ) external nonReentrant librariesInitialized {
        // Normalize margins
        (uint256 normInitMargin, uint256 normExtraMargin) = normalizeMargins(tokenAddr, initMargin, extraMargin);

        // Build EntryParams
        EntryParams memory params = EntryParams({
            listingAddr: listingAddr,
            entryPriceStr: entryPriceStr,
            initMargin: initMargin,
            extraMargin: extraMargin,
            leverageVal: leverageVal,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            tokenAddr: tokenAddr,
            normInitMargin: normInitMargin,
            normExtraMargin: normExtraMargin,
            driverAddr: address(this)
        });

        // Prepare position
        PositionEntryData memory entryData = preparePosition(params, false);

        // Transfer tokens
        transferTokens(tokenAddr, initMargin, extraMargin);

        // Finalize position
        finalizePositionEntry(entryData);

        emit PositionEntered(entryData.positionId, msg.sender, listingAddr, 1, entryData.minPrice, entryData.maxPrice);
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant librariesInitialized {
        PositionCore memory core = positionCore[positionId];
        require(core.makerAddress == msg.sender, "Not position owner");
        require(core.status2 == 0, "Position not open");

        ClosePositionParams memory closeParams = ClosePositionParams({
            positionId: positionId,
            listingAddress: core.listingAddress,
            makerAddress: core.makerAddress,
            taxedMargin: marginParams[positionId].marginTaxed,
            excessMargin: marginParams[positionId].marginExcess,
            driver: address(this)
        });

        LongCloseParams memory longParams = LongCloseParams({
            leverageAmount: leverageParams[positionId].leverageAmount,
            initialLoan: leverageParams[positionId].loanInitial
        });

        uint256 payout = ISSExecutionLibrary(executionLibrary).closeLongPosition(closeParams, longParams);
        emit PositionClosed(positionId, msg.sender, payout);
    }

    // Close short position
    function closeShortPosition(uint256 positionId) external nonReentrant librariesInitialized {
        PositionCore memory core = positionCore[positionId];
        require(core.makerAddress == msg.sender, "Not position owner");
        require(core.status2 == 0, "Position not open");

        ClosePositionParams memory closeParams = ClosePositionParams({
            positionId: positionId,
            listingAddress: core.listingAddress,
            makerAddress: core.makerAddress,
            taxedMargin: marginParams[positionId].marginTaxed,
            excessMargin: marginParams[positionId].marginExcess,
            driver: address(this)
        });

        ShortCloseParams memory shortParams = ShortCloseParams({
            minPrice: priceParams[positionId].priceMin,
            initialMargin: marginParams[positionId].marginInitial,
            leverage: leverageParams[positionId].leverageVal
        });

        uint256 payout = ISSExecutionLibrary(executionLibrary).closeShortPosition(closeParams, shortParams);
        emit PositionClosed(positionId, msg.sender, payout);
    }

    // Cancel position
    function cancelPosition(uint256 positionId) external nonReentrant librariesInitialized {
        PositionCore memory core = positionCore[positionId];
        require(core.makerAddress == msg.sender, "Not position owner");
        require(core.status1 == false, "Position executable");

        ClosePositionParams memory closeParams = ClosePositionParams({
            positionId: positionId,
            listingAddress: core.listingAddress,
            makerAddress: core.makerAddress,
            taxedMargin: marginParams[positionId].marginTaxed,
            excessMargin: marginParams[positionId].marginExcess,
            driver: address(this)
        });

        ISSExecutionLibrary(executionLibrary).cancelPosition(closeParams, core.positionType);
        emit PositionCancelled(positionId, msg.sender);
    }

    // Add excess margin
    function addExcessMargin(
        uint256 positionId,
        uint256 amount,
        address token
    ) external nonReentrant librariesInitialized {
        PositionCore memory core = positionCore[positionId];
        require(core.makerAddress == msg.sender, "Not position owner");
        require(core.status2 == 0, "Position not open");

        uint256 normalizedAmount = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        ISSExecutionLibrary(executionLibrary).addExcessMargin(
            positionId,
            amount,
            token,
            core.listingAddress,
            core.positionType,
            normalizedAmount,
            address(this)
        );
        emit ExcessMarginAdded(positionId, msg.sender, amount);
    }

    // Update stop loss
    function updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint256 minPrice,
        uint256 maxPrice
    ) external nonReentrant librariesInitialized {
        PositionCore memory core = positionCore[positionId];
        require(core.makerAddress == msg.sender, "Not position owner");
        require(core.status2 == 0, "Position not open");

        ISSExecutionLibrary(executionLibrary).updateSL(
            positionId,
            newStopLossPrice,
            listingAddress,
            core.positionType,
            msg.sender,
            minPrice,
            maxPrice,
            address(this)
        );
        emit StopLossUpdated(positionId, msg.sender, newStopLossPrice);
    }

    // Update take profit
    function updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        address listingAddress,
        uint256 minPrice,
        uint256 maxPrice
    ) external nonReentrant librariesInitialized {
        PositionCore memory core = positionCore[positionId];
        require(core.makerAddress == msg.sender, "Not position owner");
        require(core.status2 == 0, "Position not open");

        ISSExecutionLibrary(executionLibrary).updateTP(
            positionId,
            newTakeProfitPrice,
            core.positionType,
            msg.sender,
            minPrice,
            maxPrice,
            address(this)
        );
        emit TakeProfitUpdated(positionId, msg.sender, newTakeProfitPrice);
    }

    // Close all short positions
    function closeAllShort() external nonReentrant librariesInitialized {
        uint256 count = ISSExecutionLibrary(executionLibrary).closeAllShort(msg.sender, address(this));
        emit AllShortsClosed(msg.sender, count);
    }

    // Cancel all short positions
    function cancelAllShort() external nonReentrant librariesInitialized {
        uint256 count = ISSExecutionLibrary(executionLibrary).cancelAllShort(msg.sender, address(this));
        emit AllShortsCancelled(msg.sender, count);
    }

    // Close all long positions
    function closeAllLongs() external nonReentrant librariesInitialized {
        uint256 count = ISSExecutionLibrary(executionLibrary).closeAllLongs(msg.sender, address(this));
        emit AllLongsClosed(msg.sender, count);
    }

    // Cancel all long positions
    function cancelAllLong() external nonReentrant librariesInitialized {
        uint256 count = ISSExecutionLibrary(executionLibrary).cancelAllLong(msg.sender, address(this));
        emit AllLongsCancelled(msg.sender, count);
    }

    // Execute positions
    function executePositions(address listingAddress) external nonReentrant librariesInitialized {
        PositionAction[] memory actions = ISSExecutionLibrary(executionLibrary).prepareExecution(listingAddress, address(this));
        uint256 resultCount = ISSExecutionLibrary(executionLibrary).executePositions(actions, listingAddress, address(this));
        emit PositionsExecuted(listingAddress, resultCount);
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