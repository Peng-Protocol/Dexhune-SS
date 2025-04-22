// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.10:
// - Fixed TypeError in computeClosePrep (lines 698, 710):
//   - Removed incorrect tuple destructuring (prep.payout, prep.marginToReturn) for prepCloseLong/prepCloseShort calls.
//   - Directly assigned ClosePrepData struct returned by prepCloseLong/prepCloseShort to prep variable.
// - Preserved all prior optimizations from v0.0.9:
//   - CloseContext struct for prepareCloseLong/prepareCloseShort (~2 stack slots).
//   - computeClosePrep helper for ClosePrepData computation.
//   - Compatibility with CSDPositionLibrary.sol v0.0.16, CSDExecutionLibrary.sol v0.0.1, CSD-UtilityLibrary.sol v0.0.2.
//   - onlySelf modifier for setters (setPositionCore, setPriceParams, etc.).
//   - Minimal driver-side stack usage in enterLong/enterShort via EnterParams.
// - Maintained all functionality: enter$, close$, cancel$, forceExecution, batch operations.
// - Used explicit casting (e.g., uint8(0)) and DECIMAL_PRECISION (1e18).
// - Ensured driver parameter passed as address(this) to library calls.

import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";
import "./imports/Strings.sol";

// Structs
struct PositionCore {
    address makerAddress;
    address listingAddress;
    uint256 positionId;
    uint8 positionType; // 0: Long, 1: Short
    bool status1; // false: pending, true: executed
    uint8 status2; // 0: open, 1: closed, 2: cancelled
}

struct PriceParams {
    uint256 minPrice;
    uint256 maxPrice;
    uint256 priceAtEntry;
}

struct MarginParams {
    uint256 initialMargin;
    uint256 taxedMargin;
    uint256 excessMargin;
}

struct LeverageParams {
    uint8 leverage;
    uint256 leverageAmount;
    uint256 initialLoan;
}

struct ExitParams {
    uint256 liquidationPrice;
    uint256 stopLossPrice;
    uint256 takeProfitPrice;
    uint256 closePrice;
}

struct HistoricalInterest {
    uint256 shortIO;
    uint256 longIO;
    uint256 timestamp;
}

struct PayoutUpdate {
    address recipient;
    uint256 required;
    uint8 payoutType;
}

struct PositionAction {
    uint256 positionId;
    uint8 actionType; // 0: Update status, 1: Close
}

struct EnterParams {
    address listingAddress;
    string entryPrice;
    uint256 initialMargin;
    uint256 excessMargin;
    uint8 leverage;
    uint256 stopLossPrice;
    uint256 takeProfitPrice;
}

struct MarginTransferData {
    uint256 actualInitialMargin;
    uint256 actualExcessMargin;
    address token;
    uint256 normalizedInitialMargin;
    uint256 normalizedExcessMargin;
}

struct EnterPrepData {
    uint256 fee;
    uint256 taxedMargin;
    uint256 leverageAmount;
    uint256 liquidationPrice;
    uint256 initialLoan;
    uint256 minPrice;
    uint256 maxPrice;
}

struct ClosePrepData {
    uint256 payout;
    uint256 marginToReturn;
    uint256 currentPrice;
}

struct CloseContext {
    uint256 positionId;
    address listingAddress;
    address makerAddress;
    uint256 taxedMargin;
    uint256 excessMargin;
    uint256 leverageAmount;
    uint256 initialLoan;
    uint256 totalMargin;
    uint256 minPrice;
    uint256 currentPrice;
    uint256 availableMargin;
    address token;
    uint8 positionType;
    uint8 leverage;
}

struct LibraryCallData {
    address listingAddress;
    string entryPrice;
    uint8 leverage;
    uint256 stopLossPrice;
    uint256 takeProfitPrice;
}

struct BatchPrepData {
    uint256[] positionIds;
    uint256[] totalMargins;
}

// Interfaces
interface ISSListing {
    function prices(address listingAddress) external view returns (uint256);
    function volumeBalances(address listingAddress) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddresses(address listingAddress) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address listingAddress, PayoutUpdate[] calldata updates) external;
}

interface ISSLiquidity {
    function addFees(bool isX, uint256 amount) external;
    function liquidityDetails(address listingAddress) external view returns (uint256 xLiquid, uint256 yLiquid);
}

interface ICSDPositionLibrary {
    function prepEnterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 totalMargin,
        address driver
    ) external view returns (EnterPrepData memory prep);

    function prepEnterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 totalMargin,
        address driver
    ) external view returns (EnterPrepData memory prep);

    function executeEnterLong(
        address listingAddress,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token0,
        EnterPrepData memory prep,
        address driver
    ) external returns (uint256 positionId);

    function executeEnterShort(
        address listingAddress,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token1,
        EnterPrepData memory prep,
        address driver
    ) external returns (uint256 positionId);

    function prepCloseLong(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 leverageAmount,
        uint256 initialLoan,
        uint256 totalMargin,
        address driver
    ) external view returns (ClosePrepData memory prep);

    function prepCloseShort(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 minPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 totalMargin,
        address driver
    ) external view returns (ClosePrepData memory prep);

    function executeCloseLong(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        ClosePrepData memory prep,
        address driver
    ) external returns (uint256 payout);

    function executeCloseShort(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        ClosePrepData memory prep,
        address driver
    ) external returns (uint256 payout);

    function cancelPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint8 positionType,
        address driver
    ) external;

    function setPositionCore(uint256 positionId, PositionCore memory core) external;
    function setPriceParams(uint256 positionId, PriceParams memory params) external;
    function setMarginParams(uint256 positionId, MarginParams memory params) external;
    function setLeverageParams(uint256 positionId, LeverageParams memory params) external;
    function setExitParams(uint256 positionId, ExitParams memory params) external;
}

interface ICSDExecutionLibrary {
    function prepareExecution(address listingAddress, address driver) external view returns (PositionAction[] memory actions);
    function executePositions(PositionAction[] memory actions, address listingAddress, address driver) external returns (uint256 resultCount);
    function forceExecution(address listingAddress, address driver) external returns (uint256 resultCount);
    function addExcessMargin(address maker, uint256 amount, address token, uint256 normalizedAmount, address driver) external;
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
    function executeCloseAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
    function executeCancelAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
    function executeCloseAllLongs(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
    function executeCancelAllLong(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
}

interface ICSDUtilityLibrary {
    function normalizeAmount(address token, uint256 amount) external view returns (uint256);
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice);
    function parseUint(string memory str) external pure returns (uint256);
    function splitString(string memory str, string memory delimiter) external pure returns (string memory, string memory);
}

contract SSCrossDriver is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Mappings
    mapping(uint256 => PositionCore) public positionCore;
    mapping(uint256 => PriceParams) public priceParams;
    mapping(uint256 => MarginParams) public marginParams;
    mapping(uint256 => LeverageParams) public leverageParams;
    mapping(uint256 => ExitParams) public exitParams;
    mapping(address => uint256[]) public userPositions;
    mapping(uint8 => uint256[]) public positionsByType; // 0: Long, 1: Short
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions; // listingAddress -> type -> positionIds
    mapping(address => mapping(address => uint256)) public makerTokenMargin; // maker => token => totalMargin
    mapping(address => address[]) public makerMarginTokens; // maker => token[] (tracks non-zero margins)
    mapping(uint256 => HistoricalInterest) public historicalInterest;
    uint256 public positionCount;
    uint256 public interestHeight;
    address public agent;

    // Library addresses
    address public positionLibrary;
    address public executionLibrary;
    address public utilityLibrary;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Events
    event PositionCreated(uint256 indexed positionId, bool isLong);
    event PositionClosed(uint256 indexed positionId, uint256 payout);
    event PositionCancelled(uint256 indexed positionId);
    event PositionsExecuted(uint256 count, address listingAddress);
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice);
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice);
    event ExcessMarginAdded(address indexed maker, uint256 amount, address token);
    event MarginPulled(address indexed maker, uint256 amount, address token);
    event PositionsClosed(uint256 count);
    event PositionsCancelled(uint256 count);
    event LibrarySet(address indexed libraryAddress, string libraryType);

    // Modifiers
    modifier onlyAgent() {
        require(msg.sender == agent, "Only agent");
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "Only self");
        _;
    }

    // Constructor
    constructor() {}

    // Set library addresses
    function setPositionLibrary(address _positionLibrary) external onlyOwner {
        require(_positionLibrary != address(0), "Invalid library");
        positionLibrary = _positionLibrary;
        emit LibrarySet(_positionLibrary, "PositionLibrary");
    }

    function setExecutionLibrary(address _executionLibrary) external onlyOwner {
        require(_executionLibrary != address(0), "Invalid library");
        executionLibrary = _executionLibrary;
        emit LibrarySet(_executionLibrary, "ExecutionLibrary");
    }

    function setUtilityLibrary(address _utilityLibrary) external onlyOwner {
        require(_utilityLibrary != address(0), "Invalid library");
        utilityLibrary = _utilityLibrary;
        emit LibrarySet(_utilityLibrary, "UtilityLibrary");
    }

    // Set agent
    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Invalid agent");
        agent = _agent;
    }

    // Set position core
    function setPositionCore(uint256 positionId, PositionCore memory core) external onlySelf {
        require(core.positionId == positionId, "Mismatched position ID");
        positionCore[positionId] = core;
        positionCount++;
    }

    // Set price params
    function setPriceParams(uint256 positionId, PriceParams memory params) external onlySelf {
        priceParams[positionId] = params;
    }

    // Set margin params
    function setMarginParams(uint256 positionId, MarginParams memory params) external onlySelf {
        marginParams[positionId] = params;
    }

    // Set leverage params
    function setLeverageParams(uint256 positionId, LeverageParams memory params) external onlySelf {
        leverageParams[positionId] = params;
    }

    // Set exit params
    function setExitParams(uint256 positionId, ExitParams memory params) external onlySelf {
        exitParams[positionId] = params;
    }

    // Update position status
    function updatePositionStatus(uint256 positionId, uint8 newStatus) external onlySelf {
        require(newStatus <= 2, "Invalid status");
        PositionCore storage core = positionCore[positionId];
        require(core.positionId == positionId, "Invalid position");
        core.status2 = newStatus;
        if (newStatus == 1 || newStatus == 2) {
            _removePendingPosition(core.listingAddress, core.positionType, positionId);
        }
    }

    // Update position indexes
    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external {
        require(msg.sender == positionLibrary, "Only position library");
        userPositions[user].push(positionId);
        positionsByType[positionType].push(positionId);
    }

    // Update pending positions
    function updatePendingPositions(address listingAddress, uint8 positionType, uint256 positionId) external {
        require(msg.sender == positionLibrary, "Only position library");
        pendingPositions[listingAddress][positionType].push(positionId);
    }

    // Historical interest functions
    function setHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external {
        require(msg.sender == positionLibrary, "Only position library");
        historicalInterest[index] = HistoricalInterest({
            longIO: longIO,
            shortIO: shortIO,
            timestamp: block.timestamp
        });
        if (index >= interestHeight) {
            interestHeight = index + 1;
        }
    }

    function getHistoricalInterest(uint256 index) external view returns (HistoricalInterest memory) {
        return historicalInterest[index];
    }

    function getInterestHeight() external view returns (uint256) {
        return interestHeight;
    }

    function latestInterest() external view returns (HistoricalInterest memory) {
        return historicalInterest[interestHeight > 0 ? interestHeight - 1 : 0];
    }

    function queryInterest(uint256 step, uint16 maxIteration) external view returns (HistoricalInterest[] memory) {
        require(maxIteration <= 1000, "Max iteration exceeded");
        uint256 start = step * maxIteration;
        uint256 end = start + maxIteration > interestHeight ? interestHeight : start + maxIteration;
        HistoricalInterest[] memory result = new HistoricalInterest[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = historicalInterest[i];
        }
        return result;
    }

    // Helper: Queue payout order
    function queuePayoutOrder(address listingAddress, address recipient, uint256 amount, uint8 payoutType) internal {
        PayoutUpdate[] memory updates = new PayoutUpdate[](1);
        updates[0] = PayoutUpdate({
            recipient: recipient,
            required: amount,
            payoutType: payoutType
        });
        ISSListing(listingAddress).ssUpdate(listingAddress, updates);
    }

    // Helper: Transfer margin with tax-on-transfer check
    function transferMargin(address to, address token, uint256 amount) internal returns (uint256 actualAmount) {
        if (token == address(0)) {
            uint256 balanceBefore = address(to).balance;
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
            actualAmount = address(to).balance - balanceBefore;
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(to);
            IERC20(token).safeTransfer(to, amount);
            actualAmount = IERC20(token).balanceOf(to) - balanceBefore;
        }
    }

    // Helper: Remove pending position
    function _removePendingPosition(address listingAddress, uint8 positionType, uint256 positionId) internal {
        uint256[] storage pending = pendingPositions[listingAddress][positionType];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == positionId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
    }

    // Helper: Remove token
    function _removeToken(address maker, address token) internal {
        address[] storage tokens = makerMarginTokens[maker];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }

    // Helper: Validate enter parameters
    function validateEnterParams(EnterParams memory params) internal view {
        require(params.listingAddress != address(0), "Invalid listing");
        require(params.initialMargin > 0, "Invalid margin");
        require(params.leverage >= 2 && params.leverage <= 100, "Invalid leverage");
        require(params.excessMargin <= params.initialMargin * params.leverage, "Excess margin too high");
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");
    }

    // Helper: Get listing token
    function getListingToken(address listingAddress, bool isLong) internal view returns (address token) {
        token = isLong ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
    }

    // Helper: Normalize margins
    function normalizeMargins(
        uint256 initialMargin,
        uint256 excessMargin,
        address token
    ) internal view returns (uint256 normalizedInitialMargin, uint256 normalizedExcessMargin) {
        normalizedInitialMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token, initialMargin);
        normalizedExcessMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token, excessMargin);
    }

    // Helper: Transfer margins
    function transferMargins(
        EnterParams memory params,
        address token,
        address maker
    ) internal returns (MarginTransferData memory transferData) {
        transferData.token = token;
        transferData.actualInitialMargin = transferMargin(address(this), token, params.initialMargin);
        transferData.actualExcessMargin = transferMargin(address(this), token, params.excessMargin);
        (transferData.normalizedInitialMargin, transferData.normalizedExcessMargin) = normalizeMargins(
            transferData.actualInitialMargin,
            transferData.actualExcessMargin,
            token
        );

        uint256 totalMargin = transferData.actualInitialMargin + transferData.actualExcessMargin;
        makerTokenMargin[maker][token] += totalMargin;
        if (makerTokenMargin[maker][token] == totalMargin) {
            makerMarginTokens[maker].push(token);
        }
    }

    // Helper: Prepare library call
    function prepareLibraryCall(
        EnterParams memory params,
        MarginTransferData memory transferData,
        bool isLong
    ) internal view returns (EnterPrepData memory prep) {
        LibraryCallData memory callData = LibraryCallData({
            listingAddress: params.listingAddress,
            entryPrice: params.entryPrice,
            leverage: params.leverage,
            stopLossPrice: params.stopLossPrice,
            takeProfitPrice: params.takeProfitPrice
        });

        uint256 totalMargin = transferData.actualInitialMargin + transferData.actualExcessMargin;
        if (isLong) {
            prep = ICSDPositionLibrary(positionLibrary).prepEnterLong(
                callData.listingAddress,
                callData.entryPrice,
                transferData.actualInitialMargin,
                callData.leverage,
                callData.stopLossPrice,
                callData.takeProfitPrice,
                totalMargin,
                address(this)
            );
        } else {
            prep = ICSDPositionLibrary(positionLibrary).prepEnterShort(
                callData.listingAddress,
                callData.entryPrice,
                transferData.actualInitialMargin,
                callData.leverage,
                callData.stopLossPrice,
                callData.takeProfitPrice,
                totalMargin,
                address(this)
            );
        }
    }

    // Helper: Execute library call
    function executeLibraryCall(
        EnterParams memory params,
        MarginTransferData memory transferData,
        EnterPrepData memory prep,
        bool isLong
    ) internal returns (uint256 positionId) {
        if (isLong) {
            positionId = ICSDPositionLibrary(positionLibrary).executeEnterLong(
                params.listingAddress,
                transferData.actualInitialMargin,
                transferData.actualExcessMargin,
                params.leverage,
                params.stopLossPrice,
                params.takeProfitPrice,
                transferData.token,
                prep,
                address(this)
            );
        } else {
            positionId = ICSDPositionLibrary(positionLibrary).executeEnterShort(
                params.listingAddress,
                transferData.actualInitialMargin,
                transferData.actualExcessMargin,
                params.leverage,
                params.stopLossPrice,
                params.takeProfitPrice,
                transferData.token,
                prep,
                address(this)
            );
        }
    }

    // Enter long position
    function enterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable nonReentrant {
        EnterParams memory params = EnterParams({
            listingAddress: listingAddress,
            entryPrice: entryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice
        });

        validateEnterParams(params);
        address token = getListingToken(params.listingAddress, true);
        MarginTransferData memory transferData = transferMargins(params, token, msg.sender);
        EnterPrepData memory prep = prepareLibraryCall(params, transferData, true);
        uint256 positionId = executeLibraryCall(params, transferData, prep, true);

        emit PositionCreated(positionId, true);
    }

    // Enter short position
    function enterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable nonReentrant {
        EnterParams memory params = EnterParams({
            listingAddress: listingAddress,
            entryPrice: entryPrice,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice
        });

        validateEnterParams(params);
        address token = getListingToken(params.listingAddress, false);
        MarginTransferData memory transferData = transferMargins(params, token, msg.sender);
        EnterPrepData memory prep = prepareLibraryCall(params, transferData, false);
        uint256 positionId = executeLibraryCall(params, transferData, prep, false);

        emit PositionCreated(positionId, false);
    }

    // Helper: Compute close prep
    function computeClosePrep(CloseContext memory ctx) internal view returns (ClosePrepData memory prep) {
        require(ctx.currentPrice > 0, "Invalid price");
        require(ctx.availableMargin >= ctx.taxedMargin + ctx.excessMargin, "Insufficient margin");

        if (ctx.positionType == 0) {
            prep = ICSDPositionLibrary(positionLibrary).prepCloseLong(
                ctx.positionId,
                ctx.listingAddress,
                ctx.makerAddress,
                ctx.taxedMargin,
                ctx.excessMargin,
                ctx.leverageAmount,
                ctx.initialLoan,
                ctx.totalMargin,
                address(this)
            );
        } else {
            prep = ICSDPositionLibrary(positionLibrary).prepCloseShort(
                ctx.positionId,
                ctx.listingAddress,
                ctx.makerAddress,
                ctx.minPrice,
                ctx.totalMargin, // Use totalMargin as initialMargin for simplicity
                ctx.leverage,
                ctx.taxedMargin,
                ctx.excessMargin,
                ctx.totalMargin,
                address(this)
            );
        }
    }

    // Prepare close long
    function prepareCloseLong(uint256 positionId) internal view returns (ClosePrepData memory closePrep, address token) {
        CloseContext memory ctx;
        ctx.positionId = positionId;
        ctx.positionType = positionCore[positionId].positionType;
        ctx.listingAddress = positionCore[positionId].listingAddress;
        ctx.makerAddress = positionCore[positionId].makerAddress;
        ctx.taxedMargin = marginParams[positionId].taxedMargin;
        ctx.excessMargin = marginParams[positionId].excessMargin;
        ctx.leverageAmount = leverageParams[positionId].leverageAmount;
        ctx.initialLoan = leverageParams[positionId].initialLoan;
        ctx.totalMargin = makerTokenMargin[ctx.makerAddress][ISSListing(ctx.listingAddress).tokenA()];
        ctx.currentPrice = ISSListing(ctx.listingAddress).prices(ctx.listingAddress);
        ctx.availableMargin = makerTokenMargin[ctx.makerAddress][ISSListing(ctx.listingAddress).tokenA()];
        ctx.token = ISSListing(ctx.listingAddress).tokenA();

        require(ctx.positionType == 0, "Not a long position");
        require(positionCore[positionId].status2 == 0, "Position not open");
        require(ctx.makerAddress == msg.sender, "Not position maker");

        closePrep = computeClosePrep(ctx);
        token = ctx.token;
    }

    // Prepare close short
    function prepareCloseShort(uint256 positionId) internal view returns (ClosePrepData memory closePrep, address token) {
        CloseContext memory ctx;
        ctx.positionId = positionId;
        ctx.positionType = positionCore[positionId].positionType;
        ctx.listingAddress = positionCore[positionId].listingAddress;
        ctx.makerAddress = positionCore[positionId].makerAddress;
        ctx.taxedMargin = marginParams[positionId].taxedMargin;
        ctx.excessMargin = marginParams[positionId].excessMargin;
        ctx.leverage = leverageParams[positionId].leverage;
        ctx.totalMargin = makerTokenMargin[ctx.makerAddress][ISSListing(ctx.listingAddress).tokenB()];
        ctx.minPrice = priceParams[positionId].minPrice;
        ctx.currentPrice = ISSListing(ctx.listingAddress).prices(ctx.listingAddress);
        ctx.availableMargin = makerTokenMargin[ctx.makerAddress][ISSListing(ctx.listingAddress).tokenB()];
        ctx.token = ISSListing(ctx.listingAddress).tokenB();

        require(ctx.positionType == 1, "Not a short position");
        require(positionCore[positionId].status2 == 0, "Position not open");
        require(ctx.makerAddress == msg.sender, "Not position maker");

        closePrep = computeClosePrep(ctx);
        token = ctx.token;
    }

    // Execute close long
    function executeCloseLong(uint256 positionId, ClosePrepData memory closePrep, address token) internal returns (uint256 payout) {
        PositionCore storage core = positionCore[positionId];
        MarginParams storage margin = marginParams[positionId];
        payout = ICSDPositionLibrary(positionLibrary).executeCloseLong(
            positionId,
            core.listingAddress,
            core.makerAddress,
            closePrep,
            address(this)
        );

        uint256 marginToDeduct = margin.taxedMargin + (margin.excessMargin > makerTokenMargin[core.makerAddress][token] ? makerTokenMargin[core.makerAddress][token] : margin.excessMargin);
        makerTokenMargin[core.makerAddress][token] -= marginToDeduct;
        if (makerTokenMargin[core.makerAddress][token] == 0) {
            _removeToken(core.makerAddress, token);
        }
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        (ClosePrepData memory closePrep, address token) = prepareCloseLong(positionId);
        uint256 payout = executeCloseLong(positionId, closePrep, token);
        emit PositionClosed(positionId, payout);
    }

    // Execute close short
    function executeCloseShort(uint256 positionId, ClosePrepData memory closePrep, address token) internal returns (uint256 payout) {
        PositionCore storage core = positionCore[positionId];
        MarginParams storage margin = marginParams[positionId];
        payout = ICSDPositionLibrary(positionLibrary).executeCloseShort(
            positionId,
            core.listingAddress,
            core.makerAddress,
            closePrep,
            address(this)
        );

        uint256 marginToDeduct = margin.taxedMargin + (margin.excessMargin > makerTokenMargin[core.makerAddress][token] ? makerTokenMargin[core.makerAddress][token] : margin.excessMargin);
        makerTokenMargin[core.makerAddress][token] -= marginToDeduct;
        if (makerTokenMargin[core.makerAddress][token] == 0) {
            _removeToken(core.makerAddress, token);
        }
    }

    // Close short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        (ClosePrepData memory closePrep, address token) = prepareCloseShort(positionId);
        uint256 payout = executeCloseShort(positionId, closePrep, token);
        emit PositionClosed(positionId, payout);
    }

    // Cancel position
    function cancelPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        MarginParams storage margin = marginParams[positionId];
        require(core.status1 == false, "Position executable");
        require(core.status2 == 0, "Position not open");
        require(core.makerAddress == msg.sender, "Not position maker");

        ICSDPositionLibrary(positionLibrary).cancelPosition(
            positionId,
            core.listingAddress,
            core.makerAddress,
            margin.taxedMargin,
            margin.excessMargin,
            core.positionType,
            address(this)
        );

        address token = core.positionType == 0 ? ISSListing(core.listingAddress).tokenA() : ISSListing(core.listingAddress).tokenB();
        uint256 marginToDeduct = margin.taxedMargin + (margin.excessMargin > makerTokenMargin[core.makerAddress][token] ? makerTokenMargin[core.makerAddress][token] : margin.excessMargin);
        makerTokenMargin[core.makerAddress][token] -= marginToDeduct;
        if (makerTokenMargin[core.makerAddress][token] == 0) {
            _removeToken(core.makerAddress, token);
        }

        emit PositionCancelled(positionId);
    }

    // Force execution
    function forceExecution(address listingAddress) external nonReentrant {
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        uint256 resultCount = ICSDExecutionLibrary(executionLibrary).forceExecution(
            listingAddress,
            address(this)
        );
        emit PositionsExecuted(resultCount, listingAddress);
    }

    // Add excess margin
    function addExcessMargin(address maker, uint256 amount, address token) external payable nonReentrant {
        require(amount > 0, "Invalid amount");
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        uint256 actualAmount = transferMargin(address(this), token, amount);
        uint256 normalizedAmount = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token, actualAmount);

        ICSDExecutionLibrary(executionLibrary).addExcessMargin(
            maker,
            actualAmount,
            token,
            normalizedAmount,
            address(this)
        );

        makerTokenMargin[maker][token] += actualAmount;
        if (makerTokenMargin[maker][token] == actualAmount) {
            makerMarginTokens[maker].push(token);
        }

        emit ExcessMarginAdded(maker, actualAmount, token);
    }

    // Update stop loss
    function updateSL(
        uint256 positionId,
        uint256 newStopLossPrice
    ) external nonReentrant {
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        PriceParams storage price = priceParams[positionId];
        require(core.status2 == 0, "Position not open");
        require(core.makerAddress == msg.sender, "Not position maker");

        ICSDExecutionLibrary(executionLibrary).updateSL(
            positionId,
            newStopLossPrice,
            core.listingAddress,
            core.positionType,
            core.makerAddress,
            price.minPrice,
            price.maxPrice,
            address(this)
        );

        emit StopLossUpdated(positionId, newStopLossPrice);
    }

    // Update take profit
    function updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice
    ) external nonReentrant {
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        PriceParams storage price = priceParams[positionId];
        require(core.status2 == 0, "Position not open");
        require(core.makerAddress == msg.sender, "Not position maker");

        ICSDExecutionLibrary(executionLibrary).updateTP(
            positionId,
            newTakeProfitPrice,
            core.positionType,
            core.makerAddress,
            price.minPrice,
            price.maxPrice,
            address(this)
        );

        emit TakeProfitUpdated(positionId, newTakeProfitPrice);
    }

    // Pull margin
    function pullMargin(address listingAddress, address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(makerTokenMargin[msg.sender][token] >= amount, "Insufficient margin");
        require(listingAddress != address(0), "Invalid listing");

        makerTokenMargin[msg.sender][token] -= amount;
        if (makerTokenMargin[msg.sender][token] == 0) {
            _removeToken(msg.sender, token);
        }

        uint8 payoutType = token == ISSListing(listingAddress).tokenA() ? uint8(0) : uint8(1);
        queuePayoutOrder(listingAddress, msg.sender, amount, payoutType);

        emit MarginPulled(msg.sender, amount, token);
    }

    // View functions
    function positionDetails(uint256 positionId) external view returns (
        PositionCore memory,
        PriceParams memory,
        MarginParams memory,
        LeverageParams memory,
        ExitParams memory
    ) {
        return (
            positionCore[positionId],
            priceParams[positionId],
            marginParams[positionId],
            leverageParams[positionId],
            exitParams[positionId]
        );
    }

    function makerTokenMarginView(address maker, address token) external view returns (uint256) {
        return makerTokenMargin[maker][token];
    }

    function makerMarginIndex(address maker, uint256 index) external view returns (address token, uint256 totalMargin) {
        if (index < makerMarginTokens[maker].length) {
            token = makerMarginTokens[maker][index];
            totalMargin = makerTokenMargin[maker][token];
        } else {
            token = address(0);
            totalMargin = 0;
        }
    }

    function PositionsByTypeView(uint8 positionType, uint256 step, uint16 maxIteration) external view returns (uint256[] memory) {
        require(positionType <= 1, "Invalid type");
        require(maxIteration <= 1000, "Max iteration exceeded");

        uint256[] storage positions = positionsByType[positionType];
        uint256 start = step * maxIteration;
        uint256 end = start + maxIteration > positions.length ? positions.length : start + maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = positions[i];
        }
        return result;
    }

    function PositionsByAddressView(address user, uint256 step, uint16 maxIteration) external view returns (uint256[] memory) {
        require(maxIteration <= 1000, "Max iteration exceeded");

        uint256[] storage positions = userPositions[user];
        uint256 start = step * maxIteration;
        uint256 end = start + maxIteration > positions.length ? positions.length : start + maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            if (positionCore[positions[i]].status2 == 0) {
                result[i - start] = positions[i];
            }
        }
        return result;
    }

    function PositionByIndex(uint256 positionId) external view returns (
        PositionCore memory,
        PriceParams memory,
        MarginParams memory,
        LeverageParams memory,
        ExitParams memory
    ) {
        require(positionId < positionCount, "Invalid position ID");
        return (
            positionCore[positionId],
            priceParams[positionId],
            marginParams[positionId],
            leverageParams[positionId],
            exitParams[positionId]
        );
    }

    // Batch operations
    function closeAllShort() external nonReentrant {
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        uint256 count = ICSDExecutionLibrary(executionLibrary).executeCloseAllShort(
            msg.sender,
            BatchPrepData(new uint256[](0), new uint256[](0)),
            address(this)
        );
        emit PositionsClosed(count);
    }

    function cancelAllShort() external nonReentrant {
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        uint256 count = ICSDExecutionLibrary(executionLibrary).executeCancelAllShort(
            msg.sender,
            BatchPrepData(new uint256[](0), new uint256[](0)),
            address(this)
        );
        emit PositionsCancelled(count);
    }

    function closeAllLongs() external nonReentrant {
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        uint256 count = ICSDExecutionLibrary(executionLibrary).executeCloseAllLongs(
            msg.sender,
            BatchPrepData(new uint256[](0), new uint256[](0)),
            address(this)
        );
        emit PositionsClosed(count);
    }

    function cancelAllLong() external nonReentrant {
        require(executionLibrary != address(0), "ExecutionLibrary not set");
        uint256 count = ICSDExecutionLibrary(executionLibrary).executeCancelAllLong(
            msg.sender,
            BatchPrepData(new uint256[](0), new uint256[](0)),
            address(this)
        );
        emit PositionsCancelled(count);
    }
}