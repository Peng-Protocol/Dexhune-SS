// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.9:
// - Updated to ensure compatibility with SSPositionLibrary.sol v0.0.12, which fixed stack depth errors in prepareExecution and executePositions via new helpers (getCurrentPrice, processPendingActions, processActiveActions, finalizeActions, updatePositionStatusHelper, executeClosePosition) and ExecutionContext struct.
// - Modified ISSPositionLibrary interface to remove enterLong and enterShort, adding prepareEnterLong, prepareEnterShort, and finalizePosition to align with library v0.0.12’s helper-based workflow.
// - Updated enterLong and enterShort to call prepareEnter* and finalizePosition from SSPositionLibrary, preserving tax-on-transfer checks and historical interest updates.
// - Verified forceExecution compatibility with library’s optimized prepareExecution and executePositions, no signature changes needed.
// - Preserved payable transfers and fee handling in prepareEnterLong, prepareEnterShort, and addExcessMargin with tax-on-transfer checks (from v0.0.8).
// - Preserved historical interest functionality in updateHistoricalInterest and reduceHistoricalInterest, restricted to library calls (from v0.0.8).
// - Preserved closeLongPosition, closeShortPosition, cancelPosition, and batch operations (closeAll*, cancelAll*) with library delegation (from v0.0.8).
// - Preserved view functions (PositionsByTypeView, PositionsByAddressView, queryInterest, interest, interestHeight) and owner-only setters (setAgent, set*Library) (from v0.0.8).
// - Maintained Ownable, ReentrancyGuard, and struct-first ordering (from v0.0.8).
// - Changelog updated to reflect alignment with prior fixes (tax-on-transfer, historical interest, stack depth resolutions from v0.0.8).

// Version 0.0.8:
// - Extracted token transfers and normalization from enterLong and enterShort into prepareEnterLong and prepareEnterShort helpers to address stack too deep.
// - Simplified enterLong and enterShort to validate inputs, call helpers, and forward to SSPositionLibrary, minimizing local variables.
// - Fixed DeclarationError in updatePositionIndexes by retrieving PositionCore for listingAddress.
// - Updated to use PositionCore and PositionParams structs from SSPositionLibrary.sol.
// - Moved structs (PayoutUpdate, PositionAction, PositionCore, PositionParams, HistoricalInterest) before interfaces to avoid identifier errors.
// - Fixed ParserError in LibrarySet event by renaming 'library' parameter to 'libraryAddress' to avoid reserved keyword.
// - Updated enterLong and enterShort to match modified SSPositionLibrary function signatures for compatibility.
// - Interfaces before contract declaration.
// - Updated setAgent to ownerOnly.
// - Fully implemented cancelAll* to cancel pending positions with payouts via ssUpdate.
// - Added tax-on-transfer checks for margin transfers, storing post-transfer amounts.
// - Added historical interest view functions: interest, interestHeight.
// - Moved ISSListing interface locally, removed import.
// - PositionLibrary and UtilityLibrary as separate contracts, not inherited.
// - Clarified status1 (pending/executable), status2 (open/closed/cancelled) usage.
// - Local imports for SafeERC20, IERC20Metadata, etc.
// - Ensured no constructor args, reusable set* functions.

import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Strings.sol";
import "./imports/IERC20Metadata.sol";
import "./imports/Ownable.sol";

// Structs
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

struct PositionParams {
    uint256 minPrice;
    uint256 maxPrice;
    uint256 initialMargin; // Pre-tax margin
    uint256 taxedMargin; // Post-tax margin
    uint256 excessMargin; // Additional margin
    uint8 leverage; // 2-100x
    uint256 leverageAmount; // Margin * leverage
    uint256 initialLoan; // Loan at entry
    uint256 liquidationPrice; // Price to liquidate
    uint256 stopLossPrice; // SL trigger
    uint256 takeProfitPrice; // TP trigger
    uint256 closePrice; // Price at close
    uint256 priceAtEntry; // Entry price
}

struct HistoricalInterest {
    uint256 shortIO; // Total taxed + excess margin for shorts
    uint256 longIO; // Total taxed + excess margin for longs
    uint256 timestamp; // Update time
}

// Interfaces
interface ISSListing {
    function prices(uint256 listingId) external view returns (uint256);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

interface ISSLiquidity {
    function addFees(bool isX, uint256 amount) external;
    function liquidityDetails(address listingAddress) external view returns (uint256 xLiquid, uint256 yLiquid);
}

interface ISSPositionLibrary {
    function prepareEnterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        address driver
    ) external view returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PositionParams memory params
    );

    function prepareEnterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        address driver
    ) external view returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PositionParams memory params
    );

    function finalizePosition(
        uint256 positionId,
        PositionCore memory core,
        PositionParams memory params,
        address driver
    ) external;

    function closeLongPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 leverageAmount,
        uint256 initialLoan,
        address driver
    ) external returns (uint256 payout);

    function closeShortPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 minPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 taxedMargin,
        uint256 excessMargin,
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

    function prepareExecution(
        address listingAddress,
        address driver
    ) external view returns (PositionAction[] memory actions);

    function executePositions(
        PositionAction[] memory actions,
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount);

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

    function closeAllShort(
        address user,
        address driver
    ) external returns (uint256 count);

    function cancelAllShort(
        address user,
        address driver
    ) external returns (uint256 count);

    function closeAllLongs(
        address user,
        address driver
    ) external returns (uint256 count);

    function cancelAllLong(
        address user,
        address driver
    ) external returns (uint256 count);

    function setPositionCore(uint256 positionId, PositionCore memory core) external;
    function setPositionParams(uint256 positionId, PositionParams memory params) external;
    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external;
    function updatePositionStatus(uint256 positionId, uint8 newStatus) external;
    function updateExcessMargin(uint256 positionId, uint256 normalizedAmount) external;
    function updatePositionSL(uint256 positionId, uint256 newStopLossPrice) external;
    function updatePositionTP(uint256 positionId, uint256 newTakeProfitPrice) external;
    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external;
    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external;
}

interface ISSUtilityLibrary {
    function normalizeAmount(address token, uint256 amount) external view returns (uint256);
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice);
    function parseUint(string memory str) external pure returns (uint256);
    function splitString(string memory str, string memory delimiter) external pure returns (string memory, string memory);
}

contract SSIsolatedDriver is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Mappings
    mapping(uint256 => PositionCore) public positionCore;
    mapping(uint256 => PositionParams) public positionParams;
    mapping(address => uint256[]) public userPositions;
    mapping(uint8 => uint256[]) public positionsByType; // 0: Long, 1: Short
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions; // listingAddress -> type -> positionIds
    mapping(uint256 => HistoricalInterest) public historicalInterest;
    uint256 public positionCount;
    uint256 public historicalInterestHeight;
    address public agent;
    address public positionLibrary;
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
    event ExcessMarginAdded(uint256 indexed positionId, uint256 amount);
    event PositionsClosed(uint256 count);
    event PositionsCancelled(uint256 count);
    event LibrarySet(address indexed libraryAddress, string libraryType);
    event HistoricalInterestUpdated(uint256 indexed index, uint256 longIO, uint256 shortIO);

    // Set agent (owner-only)
    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Invalid agent");
        agent = _agent;
    }

    // Set library addresses (owner-only)
    function setPositionLibrary(address _positionLibrary) external onlyOwner {
        require(_positionLibrary != address(0), "Invalid address");
        positionLibrary = _positionLibrary;
        emit LibrarySet(_positionLibrary, "PositionLibrary");
    }

    function setUtilityLibrary(address _utilityLibrary) external onlyOwner {
        require(_utilityLibrary != address(0), "Invalid address");
        utilityLibrary = _utilityLibrary;
        emit LibrarySet(_utilityLibrary, "UtilityLibrary");
    }

    // Helper: Prepare enterLong
    function prepareEnterLong(
        address listingAddress,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage
    ) private returns (
        address token,
        address liquidityAddress,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        uint256 fee
    ) {
        require(listingAddress != address(0), "Invalid listing");
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        token = ISSListing(listingAddress).tokenA();
        liquidityAddress = ISSListing(listingAddress).liquidityAddresses(uint256(uint160(listingAddress)));
        normalizedInitialMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, initialMargin);
        normalizedExcessMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, excessMargin);
        fee = (leverage - 1) * initialMargin / 100;

        // Transfer margin to listingAddress, fee to liquidityAddress with tax-on-transfer check
        uint256 totalMargin = initialMargin + excessMargin;
        if (token == address(0)) {
            require(msg.value == totalMargin, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: totalMargin - fee}("");
            require(success, "ETH transfer failed");
            ISSLiquidity(liquidityAddress).addFees(true, fee);
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(listingAddress);
            IERC20(token).safeTransferFrom(msg.sender, listingAddress, totalMargin - fee);
            uint256 balanceAfter = IERC20(token).balanceOf(listingAddress);
            require(balanceAfter >= balanceBefore + totalMargin - fee, "Tax-on-transfer issue");
            IERC20(token).safeTransferFrom(msg.sender, liquidityAddress, fee);
            ISSLiquidity(liquidityAddress).addFees(true, fee);
        }
    }

    // Helper: Prepare enterShort
    function prepareEnterShort(
        address listingAddress,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage
    ) private returns (
        address token,
        address liquidityAddress,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        uint256 fee
    ) {
        require(listingAddress != address(0), "Invalid listing");
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        token = ISSListing(listingAddress).tokenB();
        liquidityAddress = ISSListing(listingAddress).liquidityAddresses(uint256(uint160(listingAddress)));
        normalizedInitialMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, initialMargin);
        normalizedExcessMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, excessMargin);
        fee = (leverage - 1) * initialMargin / 100;

        // Transfer margin to listingAddress, fee to liquidityAddress with tax-on-transfer check
        uint256 totalMargin = initialMargin + excessMargin;
        if (token == address(0)) {
            require(msg.value == totalMargin, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: totalMargin - fee}("");
            require(success, "ETH transfer failed");
            ISSLiquidity(liquidityAddress).addFees(false, fee);
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(listingAddress);
            IERC20(token).safeTransferFrom(msg.sender, listingAddress, totalMargin - fee);
            uint256 balanceAfter = IERC20(token).balanceOf(listingAddress);
            require(balanceAfter >= balanceBefore + totalMargin - fee, "Tax-on-transfer issue");
            IERC20(token).safeTransferFrom(msg.sender, liquidityAddress, fee);
            ISSLiquidity(liquidityAddress).addFees(false, fee);
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
        require(positionLibrary != address(0), "PositionLibrary not set");

        // Prepare transfer and normalization
        (address token, , uint256 normalizedInitialMargin, uint256 normalizedExcessMargin, ) = prepareEnterLong(
            listingAddress,
            initialMargin,
            excessMargin,
            leverage
        );

        // Call position library to prepare position
        (uint256 positionId, , , PositionCore memory core, PositionParams memory params) = ISSPositionLibrary(positionLibrary).prepareEnterLong(
            listingAddress,
            entryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token,
            normalizedInitialMargin,
            normalizedExcessMargin,
            address(this)
        );

        // Store position
        positionCore[positionId] = core;
        positionParams[positionId] = params;
        userPositions[msg.sender].push(positionId);
        positionsByType[0].push(positionId);
        pendingPositions[listingAddress][0].push(positionId);
        positionCount++;

        // Finalize position
        ISSPositionLibrary(positionLibrary).finalizePosition(positionId, core, params, address(this));

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
        require(positionLibrary != address(0), "PositionLibrary not set");

        // Prepare transfer and normalization
        (address token, , uint256 normalizedInitialMargin, uint256 normalizedExcessMargin, ) = prepareEnterShort(
            listingAddress,
            initialMargin,
            excessMargin,
            leverage
        );

        // Call position library to prepare position
        (uint256 positionId, , , PositionCore memory core, PositionParams memory params) = ISSPositionLibrary(positionLibrary).prepareEnterShort(
            listingAddress,
            entryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token,
            normalizedInitialMargin,
            normalizedExcessMargin,
            address(this)
        );

        // Store position
        positionCore[positionId] = core;
        positionParams[positionId] = params;
        userPositions[msg.sender].push(positionId);
        positionsByType[1].push(positionId);
        pendingPositions[listingAddress][1].push(positionId);
        positionCount++;

        // Finalize position
        ISSPositionLibrary(positionLibrary).finalizePosition(positionId, core, params, address(this));

        emit PositionCreated(positionId, false);
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        PositionParams storage params = positionParams[positionId];
        require(core.positionType == 0, "Not a long position");
        require(core.status2 == 0, "Position not open");
        require(core.makerAddress == msg.sender, "Not position maker");

        uint256 payout = ISSPositionLibrary(positionLibrary).closeLongPosition(
            positionId,
            core.listingAddress,
            core.makerAddress,
            params.taxedMargin,
            params.excessMargin,
            params.leverageAmount,
            params.initialLoan,
            address(this)
        );

        emit PositionClosed(positionId, payout);
    }

    // Close short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        PositionParams storage params = positionParams[positionId];
        require(core.positionType == 1, "Not a short position");
        require(core.status2 == 0, "Position not open");
        require(core.makerAddress == msg.sender, "Not position maker");

        uint256 payout = ISSPositionLibrary(positionLibrary).closeShortPosition(
            positionId,
            core.listingAddress,
            core.makerAddress,
            params.minPrice,
            params.initialMargin,
            params.leverage,
            params.taxedMargin,
            params.excessMargin,
            address(this)
        );

        emit PositionClosed(positionId, payout);
    }

    // Cancel position
    function cancelPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        PositionParams storage params = positionParams[positionId];
        require(core.status1 == false, "Position executable");
        require(core.status2 == 0, "Position not open");
        require(core.makerAddress == msg.sender, "Not position maker");

        ISSPositionLibrary(positionLibrary).cancelPosition(
            positionId,
            core.listingAddress,
            core.makerAddress,
            params.taxedMargin,
            params.excessMargin,
            core.positionType,
            address(this)
        );

        emit PositionCancelled(positionId);
    }

    // Force execution
    function forceExecution(address listingAddress) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionAction[] memory actions = ISSPositionLibrary(positionLibrary).prepareExecution(
            listingAddress,
            address(this)
        );
        uint256 resultCount = ISSPositionLibrary(positionLibrary).executePositions(
            actions,
            listingAddress,
            address(this)
        );
        emit PositionsExecuted(resultCount, listingAddress);
    }

    // Add excess margin
    function addExcessMargin(uint256 positionId, uint256 amount) external payable nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");
        require(amount > 0, "Invalid amount");

        PositionCore storage core = positionCore[positionId];
        PositionParams storage params = positionParams[positionId];
        require(core.status2 == 0, "Position not open");

        address token = core.positionType == 0 ? ISSListing(core.listingAddress).tokenA() : ISSListing(core.listingAddress).tokenB();
        address listingAddress = core.listingAddress;
        uint256 normalizedAmount;

        // Transfer to listingAddress with tax-on-transfer check
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: amount}("");
            require(success, "ETH transfer failed");
            normalizedAmount = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, amount);
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(listingAddress);
            IERC20(token).safeTransferFrom(msg.sender, listingAddress, amount);
            uint256 balanceAfter = IERC20(token).balanceOf(listingAddress);
            require(balanceAfter >= balanceBefore + amount, "Tax-on-transfer issue");
            normalizedAmount = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, balanceAfter - balanceBefore);
        }

        ISSPositionLibrary(positionLibrary).addExcessMargin(
            positionId,
            amount,
            token,
            core.listingAddress,
            core.positionType,
            normalizedAmount,
            address(this)
        );

        emit ExcessMarginAdded(positionId, normalizedAmount);
    }

    // Update stop loss
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        PositionParams storage params = positionParams[positionId];
        require(core.makerAddress == msg.sender, "Not position maker");
        require(core.status2 == 0, "Position not open");

        ISSPositionLibrary(positionLibrary).updateSL(
            positionId,
            newStopLossPrice,
            core.listingAddress,
            core.positionType,
            core.makerAddress,
            params.minPrice,
            params.maxPrice,
            address(this)
        );

        emit StopLossUpdated(positionId, newStopLossPrice);
    }

    // Update take profit
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionCore storage core = positionCore[positionId];
        PositionParams storage params = positionParams[positionId];
        require(core.makerAddress == msg.sender, "Not position maker");
        require(core.status2 == 0, "Position not open");

        ISSPositionLibrary(positionLibrary).updateTP(
            positionId,
            newTakeProfitPrice,
            core.positionType,
            core.makerAddress,
            params.minPrice,
            params.maxPrice,
            address(this)
        );

        emit TakeProfitUpdated(positionId, newTakeProfitPrice);
    }

    // Close all short positions
    function closeAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).closeAllShort(msg.sender, address(this));
        emit PositionsClosed(count);
    }

    // Cancel all short positions
    function cancelAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).cancelAllShort(msg.sender, address(this));
        emit PositionsCancelled(count);
    }

    // Close all long positions
    function closeAllLongs() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).closeAllLongs(msg.sender, address(this));
        emit PositionsClosed(count);
    }

    // Cancel all long positions
    function cancelAllLong() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).cancelAllLong(msg.sender, address(this));
        emit PositionsCancelled(count);
    }

    // Storage update functions
    function setPositionCore(uint256 positionId, PositionCore memory core) external {
        require(msg.sender == positionLibrary, "Library only");
        positionCore[positionId] = core;
        positionCount++;
    }

    function setPositionParams(uint256 positionId, PositionParams memory params) external {
        require(msg.sender == positionLibrary, "Library only");
        positionParams[positionId] = params;
    }

    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external {
        require(msg.sender == positionLibrary, "Library only");
        PositionCore storage core = positionCore[positionId];
        userPositions[user].push(positionId);
        if (core.status1 == true) {
            positionsByType[positionType].push(positionId);
        }
        pendingPositions[core.listingAddress][positionType].push(positionId);
    }

    function updatePositionStatus(uint256 positionId, uint8 newStatus) external {
        require(msg.sender == positionLibrary, "Library only");
        positionCore[positionId].status2 = newStatus;
    }

    function updateExcessMargin(uint256 positionId, uint256 normalizedAmount) external {
        require(msg.sender == positionLibrary, "Library only");
        positionParams[positionId].excessMargin += normalizedAmount;
    }

    function updatePositionSL(uint256 positionId, uint256 newStopLossPrice) external {
        require(msg.sender == positionLibrary, "Library only");
        positionParams[positionId].stopLossPrice = newStopLossPrice;
    }

    function updatePositionTP(uint256 positionId, uint256 newTakeProfitPrice) external {
        require(msg.sender == positionLibrary, "Library only");
        positionParams[positionId].takeProfitPrice = newTakeProfitPrice;
    }

    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external {
        require(msg.sender == positionLibrary, "Library only");
        HistoricalInterest storage interest = historicalInterest[index];
        interest.longIO += longIO;
        interest.shortIO += shortIO;
        interest.timestamp = block.timestamp;
        historicalInterestHeight = index + 1;
        emit HistoricalInterestUpdated(index, interest.longIO, interest.shortIO);
    }

    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external {
        require(msg.sender == positionLibrary, "Library only");
        HistoricalInterest storage interest = historicalInterest[index];
        interest.longIO = interest.longIO > longIO ? interest.longIO - longIO : 0;
        interest.shortIO = interest.shortIO > shortIO ? interest.shortIO - shortIO : 0;
        interest.timestamp = block.timestamp;
        historicalInterestHeight = index + 1;
        emit HistoricalInterestUpdated(index, interest.longIO, interest.shortIO);
    }

    // View functions
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

    function PositionByIndex(uint256 positionId) external view returns (PositionCore memory, PositionParams memory) {
        require(positionId < positionCount, "Invalid position ID");
        return (positionCore[positionId], positionParams[positionId]);
    }

    function queryInterest(uint256 step, uint16 maxIteration) external view returns (HistoricalInterest[] memory) {
        require(maxIteration <= 1000, "Max iteration exceeded");

        uint256 start = step * maxIteration;
        uint256 end = start + maxIteration > historicalInterestHeight ? historicalInterestHeight : start + maxIteration;
        HistoricalInterest[] memory result = new HistoricalInterest[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = historicalInterest[i];
        }
        return result;
    }

    function interest(uint256 index) external view returns (uint256 longIO, uint256 shortIO, uint256 timestamp) {
        require(index < historicalInterestHeight, "Invalid index");
        HistoricalInterest storage hi = historicalInterest[index];
        return (hi.longIO, hi.shortIO, hi.timestamp);
    }

    function interestHeight() external view returns (uint256) {
        return historicalInterestHeight;
    }
}