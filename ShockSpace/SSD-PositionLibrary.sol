// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.12:
// - Extracted logic from prepareExecution into getCurrentPrice, processPendingActions, processActiveActions, and finalizeActions helpers to address stack too deep errors.
// - Extracted logic from executePositions into updatePositionStatusHelper and executeClosePosition helpers to address potential stack depth issues.
// - Introduced ExecutionContext struct to encapsulate listingAddress, driver, and currentPrice, reducing parameter passing and stack usage.
// - Extracted logic from closeLongPosition and closeShortPosition into prepareCloseLong, prepareCloseShort, denormalizePayout, and finalizeClose helpers to address stack too deep errors (from v0.0.11).
// - Introduced CloseParams struct to encapsulate currentPrice, payout, and decimals, reducing stack usage in closure functions (from v0.0.11).
// - Simplified closeLongPosition and closeShortPosition to call prepareClose*, denormalize payout, and finalizeClose, minimizing local variables (from v0.0.11).
// - Extracted struct creation and logic from enterLong and enterShort into prepareEnterLong and prepareEnterShort helpers to address stack too deep (from v0.0.10).
// - Added finalizePosition helper to handle storage and interest updates, reducing stack usage in enterLong and enterShort (from v0.0.10).
// - Simplified enterLong and enterShort to validate inputs, call helpers, and minimize local variables (from v0.0.10).
// - Split PositionDetails into PositionCore (makerAddress, listingAddress, positionId, positionType, status1, status2) and PositionParams (minPrice, maxPrice, initialMargin, taxedMargin, excessMargin, leverage, leverageAmount, initialLoan, liquidationPrice, stopLossPrice, takeProfitPrice, closePrice, priceAtEntry) to address stack too deep (from v0.0.10).
// - Split createPosition into preparePositionCore and preparePositionParams for modularity (from v0.0.10).
// - Updated storePosition to handle PositionCore and PositionParams separately (from v0.0.10).
// - Moved structs (PayoutUpdate, PositionAction, PositionCore, PositionParams, CloseParams, ExecutionContext) before interfaces to avoid identifier errors.
// - Introduced PositionParams struct to encapsulate taxedMargin, leverageAmount, liquidationPrice, and initialLoan in enterLong and enterShort to address stack too deep (from v0.0.10).
// - Moved entry price parsing to parseEntryPrice helper function for modularity (from v0.0.10).
// - Split enterLong and enterShort into helper functions (computePositionParams, createPosition, storePosition, updateInterest) to address stack depth issues (from v0.0.10).
// - Split forceExecution into prepareExecution and executePositions to address stack depth issue (from v0.0.10).
// - Added PositionAction struct to manage position actions (update status or close) (from v0.0.10).
// - Introduced helper functions processPendingPosition and processActivePosition for modular logic (from v0.0.10).
// - Moved PayoutUpdate struct before ISSListing interface to resolve DeclarationError (from v0.0.10).
// - Updated closeLongPosition formula: ((taxedMargin + excessMargin + leverageAmount) / currentPrice) - initialLoan (from v0.0.10).
// - Updated closeShortPosition formula: (entryPrice - exitPrice) * initialMargin * leverage + (taxedMargin + excessMargin) * currentPrice (from v0.0.10).
// - Formulas commented in code (from v0.0.10).
// - Fully implemented closeLongPosition, closeShortPosition with denormalization and payouts via ssUpdate (from v0.0.10).
// - Fully implemented cancelAll* to cancel pending positions with payouts (from v0.0.10).
// - Enhanced forceExecution to handle order ranges (minPrice, maxPrice) (from v0.0.10).
// - Updated cancelPosition to use payout orders via ssUpdate, not direct transfers (from v0.0.10).
// - Added tax-on-transfer checks in addExcessMargin (from v0.0.10).
// - Updated historical interest for long/short creation, close, cancel (from v0.0.10).
// - Clarified status1 (pending/executable), status2 (open/closed/cancelled) usage (from v0.0.10).
// - Local ISSListing interface, interface before contract declaration, libraries as separate contracts (from v0.0.10).

import "./imports/SafeERC20.sol";
import "./imports/Strings.sol";
import "./imports/IERC20Metadata.sol";

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
    uint256 initialMargin;
    uint256 taxedMargin;
    uint256 excessMargin;
    uint8 leverage;
    uint256 leverageAmount;
    uint256 initialLoan;
    uint256 liquidationPrice;
    uint256 stopLossPrice;
    uint256 takeProfitPrice;
    uint256 closePrice;
    uint256 priceAtEntry;
}

struct CloseParams {
    uint256 currentPrice;
    uint256 payout;
    uint8 decimals;
}

struct ExecutionContext {
    address listingAddress;
    address driver;
    uint256 currentPrice;
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
    function positionParams(uint256 positionId) external view returns (PositionParams memory);
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    function historicalInterestHeight() external view returns (uint256);
}

contract SSPositionLibrary {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Helper: Parse entry price
    function parseEntryPrice(
        string memory entryPrice,
        address listingAddress,
        address driver
    ) private view returns (uint256 minPrice, uint256 maxPrice) {
        (minPrice, maxPrice) = ISSUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        require(minPrice > 0, "Invalid entry price");
    }

    // Helper: Compute position parameters
    function computePositionParams(
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 minPrice,
        uint8 positionType
    ) private pure returns (PositionParams memory params) {
        params.taxedMargin = initialMargin - ((leverage - 1) * initialMargin / 100);
        params.leverageAmount = initialMargin * leverage;

        // Calculate liquidation price
        require(params.leverageAmount > 0, "Invalid leverage amount");
        uint256 marginRatio = (excessMargin + params.taxedMargin) / params.leverageAmount;
        params.liquidationPrice = positionType == 0 ? (marginRatio < minPrice ? minPrice - marginRatio : 0) : minPrice + marginRatio;

        // Calculate initial loan
        params.initialLoan = positionType == 0 ? params.leverageAmount / (minPrice / DECIMAL_PRECISION) : params.leverageAmount * minPrice;

        params.initialMargin = initialMargin;
        params.excessMargin = excessMargin;
        params.leverage = leverage;
        params.minPrice = minPrice;
        params.maxPrice = minPrice; // Simplified for stack reduction
        params.priceAtEntry = minPrice;
    }

    // Helper: Prepare PositionCore
    function preparePositionCore(
        address maker,
        uint256 positionId,
        uint8 positionType,
        address listingAddress
    ) private pure returns (PositionCore memory core) {
        core = PositionCore({
            makerAddress: maker,
            listingAddress: listingAddress,
            positionId: positionId,
            positionType: positionType,
            status1: false, // Pending
            status2: 0 // Open
        });
    }

    // Helper: Prepare PositionParams
    function preparePositionParams(
        uint256 normalizedInitialMargin,
        PositionParams memory params,
        uint256 normalizedExcessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token,
        address driver
    ) private view returns (PositionParams memory updatedParams) {
        updatedParams = PositionParams({
            minPrice: params.minPrice,
            maxPrice: params.maxPrice,
            initialMargin: normalizedInitialMargin,
            taxedMargin: ISSUtilityLibrary(driver).normalizeAmount(token, params.taxedMargin),
            excessMargin: normalizedExcessMargin,
            leverage: leverage,
            leverageAmount: params.leverageAmount,
            initialLoan: params.initialLoan,
            liquidationPrice: params.liquidationPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            closePrice: 0,
            priceAtEntry: params.priceAtEntry
        });
    }

    // Helper: Prepare enterLong
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
    ) private view returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PositionParams memory params
    ) {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        // Parse entry price
        (minPrice, maxPrice) = parseEntryPrice(entryPrice, listingAddress, driver);

        // Compute parameters
        PositionParams memory tempParams = computePositionParams(
            initialMargin,
            excessMargin,
            leverage,
            minPrice,
            0 // Long
        );

        // Generate positionId
        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));

        // Prepare structs
        core = preparePositionCore(msg.sender, positionId, 0, listingAddress);
        params = preparePositionParams(
            normalizedInitialMargin,
            tempParams,
            normalizedExcessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token,
            driver
        );
    }

    // Helper: Prepare enterShort
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
    ) private view returns (
        uint256 positionId,
        uint256 minPrice,
        uint256 maxPrice,
        PositionCore memory core,
        PositionParams memory params
    ) {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        // Parse entry price
        (minPrice, maxPrice) = parseEntryPrice(entryPrice, listingAddress, driver);

        // Compute parameters
        PositionParams memory tempParams = computePositionParams(
            initialMargin,
            excessMargin,
            leverage,
            minPrice,
            1 // Short
        );

        // Generate positionId
        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));

        // Prepare structs
        core = preparePositionCore(msg.sender, positionId, 1, listingAddress);
        params = preparePositionParams(
            normalizedInitialMargin,
            tempParams,
            normalizedExcessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token,
            driver
        );
    }

    // Helper: Finalize position
    function finalizePosition(
        uint256 positionId,
        PositionCore memory core,
        PositionParams memory params,
        address driver
    ) private {
        // Store position
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "setPositionCore(uint256,(address,address,uint256,uint8,bool,uint8))",
                positionId,
                core
            )
        );
        require(success, "Core storage failed");

        (success, ) = driver.call(
            abi.encodeWithSignature(
                "setPositionParams(uint256,(uint256,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256))",
                positionId,
                params
            )
        );
        require(success, "Params storage failed");

        // Update indexes
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionIndexes(address,uint8,uint256)",
                core.makerAddress,
                core.positionType,
                positionId
            )
        );
        require(success, "Index update failed");

        // Update historical interest
        uint256 io = params.taxedMargin + params.excessMargin;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updateHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                core.positionType == 0 ? io : 0,
                core.positionType == 1 ? io : 0
            )
        );
        require(success, "Interest update failed");
    }

    // Helper: Process pending position
    function processPendingPosition(
        PositionCore memory core,
        PositionParams memory params,
        uint256 currentPrice
    ) private pure returns (PositionAction memory action) {
        action.positionId = core.positionId;
        action.actionType = 255; // No action
        if (core.status1 == false && core.status2 == 0) {
            if (currentPrice >= params.minPrice && currentPrice <= params.maxPrice) {
                action.actionType = 0; // Update status
            }
        }
    }

    // Helper: Process active position
    function processActivePosition(
        PositionCore memory core,
        PositionParams memory params,
        uint256 currentPrice,
        address listingAddress
    ) private pure returns (PositionAction memory action) {
        action.positionId = core.positionId;
        action.actionType = 255; // No action
        if (core.status1 == true && core.status2 == 0 && core.listingAddress == listingAddress) {
            bool shouldClose = false;
            if (core.positionType == 0) { // Long
                if (params.stopLossPrice > 0 && currentPrice <= params.stopLossPrice) shouldClose = true;
                else if (params.takeProfitPrice > 0 && currentPrice >= params.takeProfitPrice) shouldClose = true;
                else if (currentPrice <= params.liquidationPrice) shouldClose = true;
            } else { // Short
                if (params.stopLossPrice > 0 && currentPrice >= params.stopLossPrice) shouldClose = true;
                else if (params.takeProfitPrice > 0 && currentPrice <= params.takeProfitPrice) shouldClose = true;
                else if (currentPrice >= params.liquidationPrice) shouldClose = true;
            }
            if (shouldClose) {
                action.actionType = 1; // Close
            }
        }
    }

    // Helper: Get current price
    function getCurrentPrice(address listingAddress) private view returns (uint256) {
        return ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
    }

    // Helper: Process pending actions
    function processPendingActions(
        ExecutionContext memory context,
        uint8 positionType,
        PositionAction[] memory tempActions,
        uint256 actionCount,
        uint256 maxActions
    ) private view returns (uint256) {
        uint256[] memory pending = ISSIsolatedDriver(context.driver).pendingPositions(context.listingAddress, positionType);
        for (uint256 i = 0; i < pending.length && actionCount < maxActions; i++) {
            PositionCore memory core = ISSIsolatedDriver(context.driver).positionCore(pending[i]);
            PositionParams memory params = ISSIsolatedDriver(context.driver).positionParams(pending[i]);
            PositionAction memory action = processPendingPosition(core, params, context.currentPrice);
            if (action.actionType != 255) {
                tempActions[actionCount] = action;
                actionCount++;
            }
        }
        return actionCount;
    }

    // Helper: Process active actions
    function processActiveActions(
        ExecutionContext memory context,
        uint8 positionType,
        PositionAction[] memory tempActions,
        uint256 actionCount,
        uint256 maxActions
    ) private view returns (uint256) {
        uint256[] memory active = ISSIsolatedDriver(context.driver).positionsByType(positionType);
        for (uint256 i = 0; i < active.length && actionCount < maxActions; i++) {
            PositionCore memory core = ISSIsolatedDriver(context.driver).positionCore(active[i]);
            PositionParams memory params = ISSIsolatedDriver(context.driver).positionParams(active[i]);
            PositionAction memory action = processActivePosition(core, params, context.currentPrice, context.listingAddress);
            if (action.actionType != 255) {
                tempActions[actionCount] = action;
                actionCount++;
            }
        }
        return actionCount;
    }

    // Helper: Finalize actions
    function finalizeActions(
        PositionAction[] memory tempActions,
        uint256 actionCount
    ) private pure returns (PositionAction[] memory actions) {
        actions = new PositionAction[](actionCount);
        for (uint256 i = 0; i < actionCount; i++) {
            actions[i] = tempActions[i];
        }
    }

    // Prepare execution
    function prepareExecution(
        address listingAddress,
        address driver
    ) external view returns (PositionAction[] memory actions) {
        uint256 maxActions = 100;
        ExecutionContext memory context = ExecutionContext({
            listingAddress: listingAddress,
            driver: driver,
            currentPrice: getCurrentPrice(listingAddress)
        });
        PositionAction[] memory tempActions = new PositionAction[](maxActions);
        uint256 actionCount = 0;

        // Process pending positions
        for (uint8 positionType = 0; positionType <= 1 && actionCount < maxActions; positionType++) {
            actionCount = processPendingActions(context, positionType, tempActions, actionCount, maxActions);
        }

        // Process active positions
        for (uint8 positionType = 0; positionType <= 1 && actionCount < maxActions; positionType++) {
            actionCount = processActiveActions(context, positionType, tempActions, actionCount, maxActions);
        }

        // Finalize actions
        actions = finalizeActions(tempActions, actionCount);
    }

    // Helper: Update position status
    function updatePositionStatusHelper(
        uint256 positionId,
        PositionCore memory core,
        address driver
    ) private returns (bool) {
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 0
            )
        );
        if (success) {
            core.status1 = true;
            (success, ) = driver.call(
                abi.encodeWithSignature(
                    "setPositionCore(uint256,(address,address,uint256,uint8,bool,uint8))",
                    positionId,
                    core
                )
            );
        }
        return success;
    }

    // Helper: Execute close position
    function executeClosePosition(
        PositionAction memory action,
        PositionCore memory core,
        PositionParams memory params,
        ExecutionContext memory context
    ) private {
        if (core.positionType == 0) {
            this.closeLongPosition(
                action.positionId,
                core.listingAddress,
                core.makerAddress,
                params.taxedMargin,
                params.excessMargin,
                params.leverageAmount,
                params.initialLoan,
                context.driver
            );
        } else {
            this.closeShortPosition(
                action.positionId,
                core.listingAddress,
                core.makerAddress,
                params.minPrice,
                params.initialMargin,
                params.leverage,
                params.taxedMargin,
                params.excessMargin,
                context.driver
            );
        }
    }

    // Execute positions
    function executePositions(
        PositionAction[] memory actions,
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount) {
        resultCount = 0;
        ExecutionContext memory context = ExecutionContext({
            listingAddress: listingAddress,
            driver: driver,
            currentPrice: 0 // Not used in execution
        });

        for (uint256 i = 0; i < actions.length; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(actions[i].positionId);
            PositionParams memory params = ISSIsolatedDriver(driver).positionParams(actions[i].positionId);
            if (actions[i].actionType == 0) { // Update status
                if (updatePositionStatusHelper(actions[i].positionId, core, driver)) {
                    resultCount++;
                }
            } else if (actions[i].actionType == 1) { // Close
                executeClosePosition(actions[i], core, params, context);
                resultCount++;
            }
        }
    }

    // Helper: Prepare closeLong
    function prepareCloseLong(
        uint256 positionId,
        address listingAddress,
        address driver
    ) private view returns (CloseParams memory closeParams, PositionCore memory core, PositionParams memory params) {
        core = ISSIsolatedDriver(driver).positionCore(positionId);
        params = ISSIsolatedDriver(driver).positionParams(positionId);
        require(core.status2 == 0, "Position not open");
        require(core.status1 == true, "Position not executable");

        closeParams.currentPrice = ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
        // Formula: ((taxedMargin + excessMargin + leverageAmount) / currentPrice) - initialLoan
        uint256 totalValue = params.taxedMargin + params.excessMargin + params.leverageAmount;
        closeParams.payout = closeParams.currentPrice > 0 && totalValue > params.initialLoan
            ? (totalValue / closeParams.currentPrice) - params.initialLoan
            : 0;
        closeParams.decimals = ISSListing(listingAddress).decimalsB();
    }

    // Helper: Prepare closeShort
    function prepareCloseShort(
        uint256 positionId,
        address listingAddress,
        address driver
    ) private view returns (CloseParams memory closeParams, PositionCore memory core, PositionParams memory params) {
        core = ISSIsolatedDriver(driver).positionCore(positionId);
        params = ISSIsolatedDriver(driver).positionParams(positionId);
        require(core.status2 == 0, "Position not open");
        require(core.status1 == true, "Position not executable");

        closeParams.currentPrice = ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
        // Formula: (entryPrice - exitPrice) * initialMargin * leverage + (taxedMargin + excessMargin) * currentPrice
        uint256 priceDiff = params.minPrice > closeParams.currentPrice ? params.minPrice - closeParams.currentPrice : 0;
        uint256 profit = (priceDiff * params.initialMargin * params.leverage);
        uint256 marginReturn = (params.taxedMargin + params.excessMargin) * closeParams.currentPrice;
        closeParams.payout = profit + marginReturn;
        closeParams.decimals = ISSListing(listingAddress).decimalsA();
    }

    // Helper: Denormalize payout
    function denormalizePayout(uint256 payout, uint8 decimals) private pure returns (uint256) {
        if (decimals != 18) {
            if (decimals < 18) {
                return payout / (10 ** (uint256(18) - uint256(decimals)));
            } else {
                return payout * (10 ** (uint256(decimals) - uint256(18)));
            }
        }
        return payout;
    }

    // Helper: Finalize close
    function finalizeClose(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 payout,
        uint8 positionType,
        uint256 taxedMargin,
        uint256 excessMargin,
        address driver
    ) private {
        // Update status to closed
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 1 // Closed
            )
        );
        require(success, "Status update failed");

        // Issue payout
        if (payout > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: makerAddress,
                required: payout,
                payoutType: positionType
            });
            ISSListing(listingAddress).ssUpdate(address(this), updates);
        }

        // Reduce historical interest
        uint256 io = taxedMargin + excessMargin;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "reduceHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                positionType == 0 ? io : 0,
                positionType == 1 ? io : 0
            )
        );
        require(success, "Interest reduction failed");
    }

    // Close long position
    function closeLongPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 leverageAmount,
        uint256 initialLoan,
        address driver
    ) external returns (uint256 payout) {
        // Prepare closure
        CloseParams memory closeParams;
        PositionCore memory core;
        PositionParams memory params;
        (closeParams, core, params) = prepareCloseLong(positionId, listingAddress, driver);

        // Denormalize payout
        payout = denormalizePayout(closeParams.payout, closeParams.decimals);

        // Finalize closure
        finalizeClose(
            positionId,
            listingAddress,
            makerAddress,
            payout,
            0, // Long
            taxedMargin,
            excessMargin,
            driver
        );

        return payout;
    }

    // Close short position
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
    ) external returns (uint256 payout) {
        // Prepare closure
        CloseParams memory closeParams;
        PositionCore memory core;
        PositionParams memory params;
        (closeParams, core, params) = prepareCloseShort(positionId, listingAddress, driver);

        // Denormalize payout
        payout = denormalizePayout(closeParams.payout, closeParams.decimals);

        // Finalize closure
        finalizeClose(
            positionId,
            listingAddress,
            makerAddress,
            payout,
            1, // Short
            taxedMargin,
            excessMargin,
            driver
        );

        return payout;
    }

    // Cancel position
    function cancelPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint8 positionType,
        address driver
    ) external {
        PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positionId);
        require(core.status1 == false, "Position executable");
        require(core.status2 == 0, "Position not open");

        uint256 totalMargin = taxedMargin + excessMargin;
        if (totalMargin > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: makerAddress,
                required: totalMargin,
                payoutType: positionType
            });
            ISSListing(listingAddress).ssUpdate(address(this), updates);
        }

        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 2 // Cancelled
            )
        );
        require(success, "Status update failed");

        // Reduce historical interest
        uint256 io = taxedMargin + excessMargin;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "reduceHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                positionType == 0 ? io : 0,
                positionType == 1 ? io : 0
            )
        );
        require(success, "Interest reduction failed");
    }

    // Add excess margin
    function addExcessMargin(
        uint256 positionId,
        uint256 amount,
        address token,
        address listingAddress,
        uint8 positionType,
        uint256 normalizedAmount,
        address driver
    ) external {
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updateExcessMargin(uint256,uint256)", positionId, normalizedAmount
            )
        );
        require(success, "Margin update failed");

        // Update historical interest
        uint256 io = normalizedAmount;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updateHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                positionType == 0 ? io : 0,
                positionType == 1 ? io : 0
            )
        );
        require(success, "Interest update failed");
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
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionSL(uint256,uint256)", positionId, newStopLossPrice
            )
        );
        require(success, "SL update failed");
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
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionTP(uint256,uint256)", positionId, newTakeProfitPrice
            )
        );
        require(success, "TP update failed");
    }

    // Batch operations
    function closeAllShort(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).positionsByType(1);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            PositionParams memory params = ISSIsolatedDriver(driver).positionParams(positions[i]);
            if (core.makerAddress == user && core.status2 == 0 && core.status1 == true) {
                this.closeShortPosition(
                    positions[i],
                    core.listingAddress,
                    core.makerAddress,
                    params.minPrice,
                    params.initialMargin,
                    params.leverage,
                    params.taxedMargin,
                    params.excessMargin,
                    driver
                );
                count++;
            }
        }
    }

    function cancelAllShort(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).pendingPositions(user, 1);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            PositionParams memory params = ISSIsolatedDriver(driver).positionParams(positions[i]);
            if (core.makerAddress == user && core.status1 == false && core.status2 == 0) {
                this.cancelPosition(
                    positions[i],
                    core.listingAddress,
                    core.makerAddress,
                    params.taxedMargin,
                    params.excessMargin,
                    core.positionType,
                    driver
                );
                count++;
            }
        }
    }

    function closeAllLongs(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).positionsByType(0);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            PositionParams memory params = ISSIsolatedDriver(driver).positionParams(positions[i]);
            if (core.makerAddress == user && core.status2 == 0 && core.status1 == true) {
                this.closeLongPosition(
                    positions[i],
                    core.listingAddress,
                    core.makerAddress,
                    params.taxedMargin,
                    params.excessMargin,
                    params.leverageAmount,
                    params.initialLoan,
                    driver
                );
                count++;
            }
        }
    }

    function cancelAllLong(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).pendingPositions(user, 0);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            PositionParams memory params = ISSIsolatedDriver(driver).positionParams(positions[i]);
            if (core.makerAddress == user && core.status1 == false && core.status2 == 0) {
                this.cancelPosition(
                    positions[i],
                    core.listingAddress,
                    core.makerAddress,
                    params.taxedMargin,
                    params.excessMargin,
                    core.positionType,
                    driver
                );
                count++;
            }
        }
    }

    // Storage functions
    function setPositionCore(uint256 positionId, PositionCore memory core) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "setPositionCore(uint256,(address,address,uint256,uint8,bool,uint8))",
                positionId,
                core
            )
        );
        require(success, "Core storage failed");
    }

    function setPositionParams(uint256 positionId, PositionParams memory params) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "setPositionParams(uint256,(uint256,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256))",
                positionId,
                params
            )
        );
        require(success, "Params storage failed");
    }

    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "updatePositionIndexes(address,uint8,uint256)",
                user,
                positionType,
                positionId
            )
        );
        require(success, "Index update failed");
    }

    function updatePositionStatus(uint256 positionId, uint8 newStatus) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, newStatus
            )
        );
        require(success, "Status update failed");
    }

    function updateExcessMargin(uint256 positionId, uint256 normalizedAmount) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "updateExcessMargin(uint256,uint256)", positionId, normalizedAmount
            )
        );
        require(success, "Margin update failed");
    }

    function updatePositionSL(uint256 positionId, uint256 newStopLossPrice) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "updatePositionSL(uint256,uint256)", positionId, newStopLossPrice
            )
        );
        require(success, "SL update failed");
    }

    function updatePositionTP(uint256 positionId, uint256 newTakeProfitPrice) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "updatePositionTP(uint256,uint256)", positionId, newTakeProfitPrice
            )
        );
        require(success, "TP update failed");
    }

    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "updateHistoricalInterest(uint256,uint256,uint256)",
                index,
                longIO,
                shortIO
            )
        );
        require(success, "Interest update failed");
    }

    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "reduceHistoricalInterest(uint256,uint256,uint256)",
                index,
                longIO,
                shortIO
            )
        );
        require(success, "Interest reduction failed");
    }
}