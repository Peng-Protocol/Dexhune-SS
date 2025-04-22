// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.8:
// - Fixed stack depth error in handleCloseAction (v0.0.7):
//   - Extracted operations into new helpers to reduce stack usage to ~1–2 slots:
//     - fetchPositionCore: Fetches PositionCore (~1 slot).
//     - fetchCloseDetails: Fetches PriceParams, MarginParams, LeverageParams (~2 slots).
//     - getMarginAndToken: Computes totalMargin and token (~1 slot).
//   - Reused prepareCloseData, executeCloseAction from v0.0.5–v0.0.7 (~2 slots each).
//   - Restructured handleCloseAction to call helpers sequentially (~1–2 slots).
// - Preserved all functionality from v0.0.7:
//   - Split processSingleAction into handleStatusUpdate, handleCloseAction (v0.0.7).
//   - Fixed stack depth in executePositions with processSingleAction (v0.0.6).
//   - Fixed stack depth in executeCloseAll$, executeCancelAll$ with helpers (v0.0.4).
//   - Optimized prepForceExecution with processPositionType (~3 slots, v0.0.4).
//   - Fixed destructuring in prepCloseAll$, prepCancelAll$ (v0.0.3).
//   - Fixed setPositionCore in ISSCrossDriver interface (v0.0.2).
//   - Handles non-position-creation functions: prepForceExecution, prepareExecution, executePositions, executeForceExecution,
//     forceExecution, addExcessMargin, updateSL, updateTP, prepCloseAll$, executeCloseAll$, prepCancelAll$, executeCancelAll$.
//   - Structs: ExecutionPrepData, BatchPrepData, PositionAction.
//   - Stateless design with explicit driver parameter.
//   - Stack usage: ~1–5 slots per function.
//   - Compatibility with SSCrossDriver.sol v0.0.10, CSDPositionLibrary.sol v0.0.16, CSD-UtilityLibrary.sol v0.0.2.
//   - Explicit casting (e.g., uint8(0)) and DECIMAL_PRECISION (1e18).
//   - Pure/view functions: prepForceExecution, prepareExecution, prepCloseAll$, prepCancelAll$.
// - Maintained all workflows: force execution, margin updates, SL/TP updates, batch close/cancel.

import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";

// Structs
struct ExecutionPrepData {
    uint256[] pendingIds;
    uint256[] activeIds;
    bool[] shouldClose;
}

struct BatchPrepData {
    uint256[] positionIds;
    uint256[] totalMargins;
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

struct ClosePrepData {
    uint256 payout;
    uint256 marginToReturn;
    uint256 currentPrice;
}

// Interfaces
interface ISSListing {
    function prices(address listingAddress) external view returns (uint256);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
}

interface ICSDPositionLibrary {
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
}

interface ISSCrossDriver {
    function positionDetails(uint256 positionId) external view returns (
        PositionCore memory,
        PriceParams memory,
        MarginParams memory,
        LeverageParams memory,
        ExitParams memory
    );
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    function makerTokenMargin(address maker, address token) external view returns (uint256);
    function setPositionCore(uint256 positionId, PositionCore memory core) external;
    function setExitParams(uint256 positionId, ExitParams memory params) external;
}

interface ICSDUtilityLibrary {
    function normalizeAmount(address token, uint256 amount) external view returns (uint256);
}

interface ICSDExecutionLibrary {
    function prepForceExecution(address listingAddress, address driver) external view returns (ExecutionPrepData memory prep);
    function prepareExecution(address listingAddress, address driver) external view returns (PositionAction[] memory actions);
    function executePositions(PositionAction[] memory actions, address listingAddress, address driver) external returns (uint256 resultCount);
    function executeForceExecution(ExecutionPrepData memory prep, address listingAddress, address driver) external returns (uint256 resultCount);
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
    function prepCloseAllShort(address user, address driver) external view returns (BatchPrepData memory prep);
    function executeCloseAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
    function prepCancelAllShort(address user, address driver) external view returns (BatchPrepData memory prep);
    function executeCancelAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
    function prepCloseAllLongs(address user, address driver) external view returns (BatchPrepData memory prep);
    function executeCloseAllLongs(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
    function prepCancelAllLong(address user, address driver) external view returns (BatchPrepData memory prep);
    function executeCancelAllLong(address user, BatchPrepData memory prep, address driver) external returns (uint256 count);
}

library CSDExecutionLibrary {
    using SafeERC20 for IERC20;

    // Helper: Transfer margin with tax-on-transfer check
    function transferMargin(address to, address token, uint256 amount) internal returns (uint256 actualAmount) {
        require(amount > 0, "Zero transfer amount");
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

    // Helper: Process position type for prepForceExecution
    function processPositionType(
        address listingAddress,
        uint8 positionType,
        uint256 currentPrice,
        uint256 maxActions,
        uint256 actionCount,
        ExecutionPrepData memory prep,
        address driver
    ) internal view returns (uint256 newActionCount) {
        newActionCount = actionCount;
        uint256[] memory pending = ISSCrossDriver(driver).pendingPositions(listingAddress, uint8(positionType));
        for (uint256 i = 0; i < pending.length && newActionCount < maxActions; i++) {
            uint256 positionId = pending[i];
            (PositionCore memory core, PriceParams memory priceParams,,,) = ISSCrossDriver(driver).positionDetails(positionId);
            if (!core.status1 && core.status2 == 0) {
                if (currentPrice >= priceParams.minPrice && currentPrice <= priceParams.maxPrice) {
                    prep.pendingIds[newActionCount] = positionId;
                    prep.shouldClose[newActionCount] = false;
                    newActionCount++;
                }
            }
        }

        uint256[] memory active = ISSCrossDriver(driver).positionsByType(uint8(positionType));
        for (uint256 i = 0; i < active.length && newActionCount < maxActions; i++) {
            uint256 positionId = active[i];
            (PositionCore memory core, PriceParams memory priceParams,,, ExitParams memory exitParams) = ISSCrossDriver(driver).positionDetails(positionId);
            if (core.status1 && core.status2 == 0 && core.listingAddress == listingAddress) {
                bool shouldClose = false;
                if (core.positionType == 0) {
                    if (exitParams.stopLossPrice > 0 && currentPrice <= exitParams.stopLossPrice) shouldClose = true;
                    else if (exitParams.takeProfitPrice > 0 && currentPrice >= exitParams.takeProfitPrice) shouldClose = true;
                    else if (currentPrice <= exitParams.liquidationPrice) shouldClose = true;
                } else {
                    if (exitParams.stopLossPrice > 0 && currentPrice >= exitParams.stopLossPrice) shouldClose = true;
                    else if (exitParams.takeProfitPrice > 0 && currentPrice <= exitParams.takeProfitPrice) shouldClose = true;
                    else if (currentPrice >= exitParams.liquidationPrice) shouldClose = true;
                }
                if (shouldClose) {
                    prep.activeIds[newActionCount] = positionId;
                    prep.shouldClose[newActionCount] = true;
                    newActionCount++;
                }
            }
        }
    }

    // Prep force execution (maintained for compatibility)
    function prepForceExecution(
        address listingAddress,
        address driver
    ) internal view returns (ExecutionPrepData memory prep) {
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        uint256 maxActions = 25;

        prep.pendingIds = new uint256[](maxActions);
        prep.activeIds = new uint256[](maxActions);
        prep.shouldClose = new bool[](maxActions);
        uint256 actionCount = 0;

        for (uint8 positionType = 0; positionType <= 1 && actionCount < maxActions; positionType++) {
            actionCount = processPositionType(
                listingAddress,
                positionType,
                currentPrice,
                maxActions,
                actionCount,
                prep,
                driver
            );
        }
    }

    // Prepare execution
    function prepareExecution(
        address listingAddress,
        address driver
    ) public view returns (PositionAction[] memory actions) {
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        uint256 maxActions = 25;
        actions = new PositionAction[](maxActions);
        uint256 actionCount = 0;

        for (uint8 positionType = 0; positionType <= 1 && actionCount < maxActions; positionType++) {
            uint256[] memory pending = ISSCrossDriver(driver).pendingPositions(listingAddress, uint8(positionType));
            for (uint256 i = 0; i < pending.length && actionCount < maxActions; i++) {
                uint256 positionId = pending[i];
                (
                    PositionCore memory core,
                    PriceParams memory priceParams,
                    ,
                    ,
                    ExitParams memory exitParams
                ) = ISSCrossDriver(driver).positionDetails(positionId);
                if (!core.status1 && core.status2 == 0) {
                    if (currentPrice >= priceParams.minPrice && currentPrice <= priceParams.maxPrice) {
                        actions[actionCount] = PositionAction({
                            positionId: positionId,
                            actionType: 0 // Update status
                        });
                        actionCount++;
                    }
                }
            }
        }

        for (uint8 positionType = 0; positionType <= 1 && actionCount < maxActions; positionType++) {
            uint256[] memory active = ISSCrossDriver(driver).positionsByType(uint8(positionType));
            for (uint256 i = 0; i < active.length && actionCount < maxActions; i++) {
                uint256 positionId = active[i];
                (
                    PositionCore memory core,
                    PriceParams memory priceParams,
                    ,
                    ,
                    ExitParams memory exitParams
                ) = ISSCrossDriver(driver).positionDetails(positionId);
                if (core.status1 && core.status2 == 0 && core.listingAddress == listingAddress) {
                    bool shouldClose = false;
                    if (core.positionType == 0) {
                        if (exitParams.stopLossPrice > 0 && currentPrice <= exitParams.stopLossPrice) shouldClose = true;
                        else if (exitParams.takeProfitPrice > 0 && currentPrice >= exitParams.takeProfitPrice) shouldClose = true;
                        else if (currentPrice <= exitParams.liquidationPrice) shouldClose = true;
                    } else {
                        if (exitParams.stopLossPrice > 0 && currentPrice >= exitParams.stopLossPrice) shouldClose = true;
                        else if (exitParams.takeProfitPrice > 0 && currentPrice <= exitParams.takeProfitPrice) shouldClose = true;
                        else if (currentPrice >= exitParams.liquidationPrice) shouldClose = true;
                    }
                    if (shouldClose) {
                        actions[actionCount] = PositionAction({
                            positionId: positionId,
                            actionType: 1 // Close
                        });
                        actionCount++;
                    }
                }
            }
        }

        // Resize array to actual size
        assembly {
            mstore(actions, actionCount)
        }
    }

    // Helper: Fetch position details for close/cancel
    function fetchPositionDetails(uint256 positionId, address driver) internal view returns (
        PositionCore memory core,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        ExitParams memory exitParams
    ) {
        return ISSCrossDriver(driver).positionDetails(positionId);
    }

    // Helper: Fetch only PositionCore
    function fetchPositionCore(uint256 positionId, address driver) internal view returns (PositionCore memory core) {
        (core,,,,) = ISSCrossDriver(driver).positionDetails(positionId);
    }

    // Helper: Fetch close details (PriceParams, MarginParams, LeverageParams)
    function fetchCloseDetails(uint256 positionId, address driver) internal view returns (
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams
    ) {
        ( , priceParams, marginParams, leverageParams, ) = ISSCrossDriver(driver).positionDetails(positionId);
    }

    // Helper: Get margin and token
    function getMarginAndToken(
        PositionCore memory core,
        address listingAddress,
        address driver
    ) internal view returns (uint256 totalMargin, address token) {
        token = core.positionType == 0 ? ISSListing(core.listingAddress).tokenA() : ISSListing(core.listingAddress).tokenB();
        totalMargin = ISSCrossDriver(driver).makerTokenMargin(core.makerAddress, token);
    }

    // Helper: Execute status update
    function executeStatusUpdate(uint256 positionId, address driver) internal {
        (PositionCore memory core,,,,) = ISSCrossDriver(driver).positionDetails(positionId);
        core.status1 = true;
        ISSCrossDriver(driver).setPositionCore(positionId, core);
    }

    // Helper: Prepare close data
    function prepareCloseData(
        uint256 positionId,
        PositionCore memory core,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        uint256 totalMargin,
        address driver
    ) internal view returns (ClosePrepData memory closePrep) {
        if (core.positionType == 0) {
            closePrep = ICSDPositionLibrary(driver).prepCloseLong(
                positionId,
                core.listingAddress,
                core.makerAddress,
                marginParams.taxedMargin,
                marginParams.excessMargin,
                leverageParams.leverageAmount,
                leverageParams.initialLoan,
                totalMargin,
                driver
            );
        } else {
            closePrep = ICSDPositionLibrary(driver).prepCloseShort(
                positionId,
                core.listingAddress,
                core.makerAddress,
                priceParams.minPrice,
                marginParams.initialMargin,
                leverageParams.leverage,
                marginParams.taxedMargin,
                marginParams.excessMargin,
                totalMargin,
                driver
            );
        }
    }

    // Helper: Execute close action
    function executeCloseAction(
        uint256 positionId,
        PositionCore memory core,
        ClosePrepData memory closePrep,
        address driver
    ) internal {
        if (core.positionType == 0) {
            ICSDPositionLibrary(driver).executeCloseLong(
                positionId,
                core.listingAddress,
                core.makerAddress,
                closePrep,
                driver
            );
        } else {
            ICSDPositionLibrary(driver).executeCloseShort(
                positionId,
                core.listingAddress,
                core.makerAddress,
                closePrep,
                driver
            );
        }
    }

    // Helper: Handle status update (actionType == 0)
    function handleStatusUpdate(uint256 positionId, address driver) internal returns (bool success) {
        if (positionId == 0) return false;
        executeStatusUpdate(positionId, driver);
        return true;
    }

    // Helper: Handle close action (actionType == 1)
    function handleCloseAction(
        uint256 positionId,
        address listingAddress,
        address driver
    ) internal returns (bool success) {
        if (positionId == 0) return false;

        // Step 1: Fetch PositionCore
        PositionCore memory core = fetchPositionCore(positionId, driver);
        
        // Step 2: Fetch close details
        (
            PriceParams memory priceParams,
            MarginParams memory marginParams,
            LeverageParams memory leverageParams
        ) = fetchCloseDetails(positionId, driver);
        
        // Step 3: Get margin and token
        (uint256 totalMargin, address token) = getMarginAndToken(core, listingAddress, driver);
        
        // Step 4: Prepare close data
        ClosePrepData memory closePrep = prepareCloseData(
            positionId,
            core,
            priceParams,
            marginParams,
            leverageParams,
            totalMargin,
            driver
        );
        
        // Step 5: Execute close action
        executeCloseAction(positionId, core, closePrep, driver);
        return true;
    }

    // Helper: Process a single PositionAction
    function processSingleAction(
        PositionAction memory action,
        address listingAddress,
        address driver
    ) internal returns (bool success) {
        if (action.actionType == 0) {
            return handleStatusUpdate(action.positionId, driver);
        } else if (action.actionType == 1) {
            return handleCloseAction(action.positionId, listingAddress, driver);
        }
        return false;
    }

    // Execute positions
    function executePositions(
        PositionAction[] memory actions,
        address listingAddress,
        address driver
    ) public returns (uint256 resultCount) {
        resultCount = 0;
        for (uint256 i = 0; i < actions.length; i++) {
            if (processSingleAction(actions[i], listingAddress, driver)) {
                resultCount++;
            }
        }
    }

    // Execute force execution (wrapper for compatibility)
    function executeForceExecution(
        ExecutionPrepData memory prep,
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount) {
        PositionAction[] memory actions = prepareExecution(listingAddress, driver);
        return executePositions(actions, listingAddress, driver);
    }

    // Force execution (wrapper for compatibility)
    function forceExecution(
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount) {
        PositionAction[] memory actions = prepareExecution(listingAddress, driver);
        return executePositions(actions, listingAddress, driver);
    }

    // Add excess margin
    function addExcessMargin(
        address maker,
        uint256 amount,
        address token,
        uint256 normalizedAmount,
        address driver
    ) external {
        require(amount > 0, "Invalid amount");
        transferMargin(driver, token, amount);
    }

    // Update stop loss
    function updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint8 positionType,
        address makerAddress,
        uint256 minPrice,
        uint256 maxPrice,
        address driver
    ) external {
        require(positionType <= 1, "Invalid position type");
        require(
            newStopLossPrice == 0 ||
            (positionType == 0 && newStopLossPrice < minPrice) ||
            (positionType == 1 && newStopLossPrice > maxPrice),
            "Invalid stop loss"
        );

        (
            ,
            ,
            ,
            ,
            ExitParams memory exitParams
        ) = ISSCrossDriver(driver).positionDetails(positionId);
        exitParams.stopLossPrice = newStopLossPrice;
        ISSCrossDriver(driver).setExitParams(positionId, exitParams);
    }

    // Update take profit
    function updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        uint8 positionType,
        address makerAddress,
        uint256 minPrice,
        uint256 maxPrice,
        address driver
    ) external {
        require(positionType <= 1, "Invalid position type");
        require(
            newTakeProfitPrice == 0 ||
            (positionType == 0 && newTakeProfitPrice > maxPrice) ||
            (positionType == 1 && newTakeProfitPrice < minPrice),
            "Invalid take profit"
        );

        (
            ,
            ,
            ,
            ,
            ExitParams memory exitParams
        ) = ISSCrossDriver(driver).positionDetails(positionId);
        exitParams.takeProfitPrice = newTakeProfitPrice;
        ISSCrossDriver(driver).setExitParams(positionId, exitParams);
    }

    // Prep close all short
    function prepCloseAllShort(address user, address driver) internal view returns (BatchPrepData memory prep) {
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).positionsByType(1);
        prep.positionIds = new uint256[](maxIteration);
        prep.totalMargins = new uint256[](maxIteration);
        uint256 count = 0;

        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            (PositionCore memory core,,,,) = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (core.makerAddress == user && core.status2 == 0 && core.positionType == 1) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(core.makerAddress, ISSListing(core.listingAddress).tokenB());
                count++;
            }
        }
    }

    // Execute close all short
    function executeCloseAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        count = 0;
        if (prep.positionIds.length == 0 || prep.positionIds[0] == 0) {
            prep = prepCloseAllShort(user, driver);
        }

        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] == 0) continue;
            (
                PositionCore memory core,
                PriceParams memory priceParams,
                MarginParams memory marginParams,
                LeverageParams memory leverageParams,
                ExitParams memory exitParams
            ) = fetchPositionDetails(prep.positionIds[i], driver);
            ClosePrepData memory closePrep = prepareCloseData(
                prep.positionIds[i],
                core,
                priceParams,
                marginParams,
                leverageParams,
                prep.totalMargins[i],
                driver
            );
            executeCloseAction(prep.positionIds[i], core, closePrep, driver);
            count++;
        }
    }

    // Prep cancel all short
    function prepCancelAllShort(address user, address driver) internal view returns (BatchPrepData memory prep) {
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).pendingPositions(address(0), 1);
        prep.positionIds = new uint256[](maxIteration);
        prep.totalMargins = new uint256[](maxIteration);
        uint256 count = 0;

        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            (PositionCore memory core,,,,) = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (core.makerAddress == user && !core.status1 && core.status2 == 0 && core.positionType == 1) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(core.makerAddress, ISSListing(core.listingAddress).tokenB());
                count++;
            }
        }
    }

    // Execute cancel all short
    function executeCancelAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        count = 0;
        if (prep.positionIds.length == 0 || prep.positionIds[0] == 0) {
            prep = prepCancelAllShort(user, driver);
        }

        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] == 0) continue;
            (
                PositionCore memory core,
                ,
                MarginParams memory marginParams,
                ,
                ExitParams memory exitParams
            ) = fetchPositionDetails(prep.positionIds[i], driver);
            executeCancelAction(prep.positionIds[i], core, marginParams, driver);
            count++;
        }
    }

    // Prep close all longs
    function prepCloseAllLongs(address user, address driver) internal view returns (BatchPrepData memory prep) {
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).positionsByType(0);
        prep.positionIds = new uint256[](maxIteration);
        prep.totalMargins = new uint256[](maxIteration);
        uint256 count = 0;

        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            (PositionCore memory core,,,,) = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (core.makerAddress == user && core.status2 == 0 && core.positionType == 0) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(core.makerAddress, ISSListing(core.listingAddress).tokenA());
                count++;
            }
        }
    }

    // Execute close all longs
    function executeCloseAllLongs(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        count = 0;
        if (prep.positionIds.length == 0 || prep.positionIds[0] == 0) {
            prep = prepCloseAllLongs(user, driver);
        }

        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] == 0) continue;
            (
                PositionCore memory core,
                PriceParams memory priceParams,
                MarginParams memory marginParams,
                LeverageParams memory leverageParams,
                ExitParams memory exitParams
            ) = fetchPositionDetails(prep.positionIds[i], driver);
            ClosePrepData memory closePrep = prepareCloseData(
                prep.positionIds[i],
                core,
                priceParams,
                marginParams,
                leverageParams,
                prep.totalMargins[i],
                driver
            );
            executeCloseAction(prep.positionIds[i], core, closePrep, driver);
            count++;
        }
    }

    // Prep cancel all long
    function prepCancelAllLong(address user, address driver) internal view returns (BatchPrepData memory prep) {
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).pendingPositions(address(0), 0);
        prep.positionIds = new uint256[](maxIteration);
        prep.totalMargins = new uint256[](maxIteration);
        uint256 count = 0;

        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            (PositionCore memory core,,,,) = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (core.makerAddress == user && !core.status1 && core.status2 == 0 && core.positionType == 0) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(core.makerAddress, ISSListing(core.listingAddress).tokenA());
                count++;
            }
        }
    }

    // Execute cancel all long
    function executeCancelAllLong(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        count = 0;
        if (prep.positionIds.length == 0 || prep.positionIds[0] == 0) {
            prep = prepCancelAllLong(user, driver);
        }

        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] == 0) continue;
            (
                PositionCore memory core,
                ,
                MarginParams memory marginParams,
                ,
                ExitParams memory exitParams
            ) = fetchPositionDetails(prep.positionIds[i], driver);
            executeCancelAction(prep.positionIds[i], core, marginParams, driver);
            count++;
        }
    }

    // Helper: Execute cancel action
    function executeCancelAction(
        uint256 positionId,
        PositionCore memory core,
        MarginParams memory marginParams,
        address driver
    ) internal {
        ICSDPositionLibrary(driver).cancelPosition(
            positionId,
            core.listingAddress,
            core.makerAddress,
            marginParams.taxedMargin,
            marginParams.excessMargin,
            core.positionType,
            driver
        );
    }
}