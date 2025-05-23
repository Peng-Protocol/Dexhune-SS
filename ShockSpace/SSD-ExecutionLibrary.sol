// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.5:
// - Fixed TypeError: Member "initialLoan" not found in struct LeverageParams:
//   - Replaced initialLoan with loanInitial in executeClosePosition function.
// - Retained changes from v0.0.4:
//   - Added timestamp support for historical interest.
//   - Updated ISSIsolatedDriver interface to include updateExcessMargin, updatePositionSL, updatePositionTP.
//   - Refactored PositionParams to modular structs.
//   - Added internalCloseLongPosition, internalCloseShortPosition, internalCancelPosition helpers.
//   - Fixed stack depth and shadowing issues.
// - Compatible with SS-IsolatedDriver.sol v0.0.17, SSD-PositionLibrary.sol v0.0.20, SSD-UtilityLibrary.sol v0.0.6.
// - Uses SafeERC20 for token transfers.

import "./imports/SafeERC20.sol";
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

struct CloseParams {
    uint256 currentPrice;
    uint256 payout;
    uint8 decimals;
}

struct ExecutionContext {
    address listingAddress;
    address driver;
    uint256 currentPrice;
    uint256 actionCount;
    uint256 maxActions;
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
    uint256 loanInitial;
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
    function updatePositionStatus(uint256 positionId, uint8 status) external;
    function updateExcessMargin(uint256 positionId, uint256 amount) external;
    function updatePositionSL(uint256 positionId, uint256 newStopLossPrice) external;
    function updatePositionTP(uint256 positionId, uint256 newTakeProfitPrice) external;
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

library SSDExecutionLibrary {
    using SafeERC20 for IERC20;

    // Modifier to restrict calls to driver
    modifier onlyDriver(address driver) {
        require(msg.sender == driver, "Driver only");
        _;
    }

    // Internal Helper: Close long position
    function internalCloseLongPosition(
        ClosePositionParams memory params,
        LongCloseParams memory longParams
    ) internal returns (uint256 payout) {
        CloseParams memory closeParams;
        PositionCore memory core;
        PriceParams memory priceParams;
        MarginParams memory marginParams;
        LeverageParams memory leverageParams;
        RiskParams memory riskParams;
        (closeParams, core, priceParams, marginParams, leverageParams, riskParams) = prepareCloseLong(params);

        payout = denormalizePayout(closeParams.payout, closeParams.decimals);
        finalizeClose(params, 0, payout);
    }

    // Internal Helper: Close short position
    function internalCloseShortPosition(
        ClosePositionParams memory params,
        ShortCloseParams memory shortParams
    ) internal returns (uint256 payout) {
        CloseParams memory closeParams;
        PositionCore memory core;
        PriceParams memory priceParams;
        MarginParams memory marginParams;
        LeverageParams memory leverageParams;
        RiskParams memory riskParams;
        (closeParams, core, priceParams, marginParams, leverageParams, riskParams) = prepareCloseShort(params);

        payout = denormalizePayout(closeParams.payout, closeParams.decimals);
        finalizeClose(params, 1, payout);
    }

    // Internal Helper: Cancel position
    function internalCancelPosition(
        ClosePositionParams memory params,
        uint8 positionType
    ) internal {
        PositionCore memory core = ISSIsolatedDriver(params.driver).positionCore(params.positionId);
        require(core.status1 == false, "Position executable");
        require(core.status2 == 0, "Position not open");

        uint256 totalMargin = params.taxedMargin + params.excessMargin;
        if (totalMargin > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: params.makerAddress,
                required: totalMargin,
                payoutType: positionType
            });
            ISSListing(params.listingAddress).ssUpdate(address(this), updates);
        }

        bool success;
        (success, ) = params.driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", params.positionId, 2
            )
        );
        require(success, "Status update failed");

        uint256 io = params.taxedMargin + params.excessMargin;
        (success, ) = params.driver.call(
            abi.encodeWithSignature(
                "reduceHistoricalInterest(uint256,uint256,uint256,uint256)",
                ISSIsolatedDriver(params.driver).historicalInterestHeight(),
                positionType == 0 ? io : 0,
                positionType == 1 ? io : 0,
                block.timestamp
            )
        );
        require(success, "Interest reduction failed");
    }

    // Helper: Get current price
    function getCurrentPrice(address listingAddress) internal view returns (uint256) {
        return ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
    }

    // Helper: Process pending position
    function processPendingPosition(
        PositionCore memory core,
        PriceParams memory priceParams,
        uint256 currentPrice
    ) internal pure returns (PositionAction memory action) {
        action.positionId = core.positionId;
        action.actionType = 255; // No action
        if (core.status1 == false && core.status2 == 0) {
            if (currentPrice >= priceParams.priceMin && currentPrice <= priceParams.priceMax) {
                action.actionType = 0; // Update status
            }
        }
    }

    // Helper: Process active position
    function processActivePosition(
        PositionCore memory core,
        PriceParams memory priceParams,
        RiskParams memory riskParams,
        uint256 currentPrice,
        address listingAddress
    ) internal pure returns (PositionAction memory action) {
        action.positionId = core.positionId;
        action.actionType = 255; // No action
        if (core.status1 == true && core.status2 == 0 && core.listingAddress == listingAddress) {
            bool shouldClose = false;
            if (core.positionType == 0) { // Long
                if (riskParams.priceStopLoss > 0 && currentPrice <= riskParams.priceStopLoss) shouldClose = true;
                else if (riskParams.priceTakeProfit > 0 && currentPrice >= riskParams.priceTakeProfit) shouldClose = true;
                else if (currentPrice <= riskParams.priceLiquidation) shouldClose = true;
            } else { // Short
                if (riskParams.priceStopLoss > 0 && currentPrice >= riskParams.priceStopLoss) shouldClose = true;
                else if (riskParams.priceTakeProfit > 0 && currentPrice <= riskParams.priceTakeProfit) shouldClose = true;
                else if (currentPrice >= riskParams.priceLiquidation) shouldClose = true;
            }
            if (shouldClose) {
                action.actionType = 1; // Close
            }
        }
    }

    // Helper: Process pending actions
    function processPendingActions(
        ExecutionContext memory context,
        uint8 positionType,
        PositionAction[] memory tempActions
    ) internal view returns (uint256) {
        uint256[] memory pending = ISSIsolatedDriver(context.driver).pendingPositions(context.listingAddress, positionType);
        for (uint256 i = 0; i < pending.length && context.actionCount < context.maxActions; i++) {
            PositionCore memory core = ISSIsolatedDriver(context.driver).positionCore(pending[i]);
            PriceParams memory priceParams = ISSIsolatedDriver(context.driver).priceParams(pending[i]);
            PositionAction memory action = processPendingPosition(core, priceParams, context.currentPrice);
            if (action.actionType != 255) {
                tempActions[context.actionCount] = action;
                context.actionCount++;
            }
        }
        return context.actionCount;
    }

    // Helper: Process active actions
    function processActiveActions(
        ExecutionContext memory context,
        uint8 positionType,
        PositionAction[] memory tempActions
    ) internal view returns (uint256) {
        uint256[] memory active = ISSIsolatedDriver(context.driver).positionsByType(positionType);
        for (uint256 i = 0; i < active.length && context.actionCount < context.maxActions; i++) {
            PositionCore memory core = ISSIsolatedDriver(context.driver).positionCore(active[i]);
            PriceParams memory priceParams = ISSIsolatedDriver(context.driver).priceParams(active[i]);
            RiskParams memory riskParams = ISSIsolatedDriver(context.driver).riskParams(active[i]);
            PositionAction memory action = processActivePosition(core, priceParams, riskParams, context.currentPrice, context.listingAddress);
            if (action.actionType != 255) {
                tempActions[context.actionCount] = action;
                context.actionCount++;
            }
        }
        return context.actionCount;
    }

    // Helper: Finalize actions
    function finalizeActions(
        PositionAction[] memory tempActions,
        uint256 actionCount
    ) internal pure returns (PositionAction[] memory actions) {
        actions = new PositionAction[](actionCount);
        for (uint256 i = 0; i < actionCount; i++) {
            actions[i] = tempActions[i];
        }
    }

    // Prepare execution
    function prepareExecution(
        address listingAddress,
        address driver
    ) external view onlyDriver(driver) returns (PositionAction[] memory actions) {
        ExecutionContext memory context = ExecutionContext({
            listingAddress: listingAddress,
            driver: driver,
            currentPrice: getCurrentPrice(listingAddress),
            actionCount: 0,
            maxActions: 100
        });
        PositionAction[] memory tempActions = new PositionAction[](context.maxActions);

        // Process pending and active positions
        for (uint8 positionType = 0; positionType <= 1 && context.actionCount < context.maxActions; positionType++) {
            context.actionCount = processPendingActions(context, positionType, tempActions);
        }
        for (uint8 positionType = 0; positionType <= 1 && context.actionCount < context.maxActions; positionType++) {
            context.actionCount = processActiveActions(context, positionType, tempActions);
        }

        actions = finalizeActions(tempActions, context.actionCount);
    }

    // Helper: Update position status
    function updatePositionStatusHelper(
        uint256 positionId,
        PositionCore memory core,
        address driver
    ) internal returns (bool) {
        bool success;
        (success, ) = driver.call(
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
        ExecutionContext memory context
    ) internal {
        ClosePositionParams memory closeParams = ClosePositionParams({
            positionId: action.positionId,
            listingAddress: core.listingAddress,
            makerAddress: core.makerAddress,
            taxedMargin: ISSIsolatedDriver(context.driver).marginParams(action.positionId).marginTaxed,
            excessMargin: ISSIsolatedDriver(context.driver).marginParams(action.positionId).marginExcess,
            driver: context.driver
        });
        if (core.positionType == 0) {
            LongCloseParams memory longParams = LongCloseParams({
                leverageAmount: ISSIsolatedDriver(context.driver).leverageParams(action.positionId).leverageAmount,
                loanInitial: ISSIsolatedDriver(context.driver).leverageParams(action.positionId).loanInitial
            });
            internalCloseLongPosition(closeParams, longParams);
        } else {
            ShortCloseParams memory shortParams = ShortCloseParams({
                minPrice: ISSIsolatedDriver(context.driver).priceParams(action.positionId).priceMin,
                initialMargin: ISSIsolatedDriver(context.driver).marginParams(action.positionId).marginInitial,
                leverage: ISSIsolatedDriver(context.driver).leverageParams(action.positionId).leverageVal
            });
            internalCloseShortPosition(closeParams, shortParams);
        }
    }

    // Execute positions
    function executePositions(
        PositionAction[] memory actions,
        address listingAddress,
        address driver
    ) external onlyDriver(driver) returns (uint256 resultCount) {
        resultCount = 0;
        ExecutionContext memory context = ExecutionContext({
            listingAddress: listingAddress,
            driver: driver,
            currentPrice: 0, // Not used
            actionCount: 0,
            maxActions: 100
        });

        for (uint256 i = 0; i < actions.length; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(actions[i].positionId);
            if (actions[i].actionType == 0) {
                if (updatePositionStatusHelper(actions[i].positionId, core, driver)) {
                    resultCount++;
                }
            } else if (actions[i].actionType == 1) {
                executeClosePosition(actions[i], core, context);
                resultCount++;
            }
        }
    }

    // Helper: Prepare closeLong
    function prepareCloseLong(
        ClosePositionParams memory params
    ) internal view returns (
        CloseParams memory closeParams,
        PositionCore memory core,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams
    ) {
        core = ISSIsolatedDriver(params.driver).positionCore(params.positionId);
        priceParams = ISSIsolatedDriver(params.driver).priceParams(params.positionId);
        marginParams = ISSIsolatedDriver(params.driver).marginParams(params.positionId);
        leverageParams = ISSIsolatedDriver(params.driver).leverageParams(params.positionId);
        riskParams = ISSIsolatedDriver(params.driver).riskParams(params.positionId);
        require(core.status2 == 0, "Position not open");
        require(core.status1 == true, "Position not executable");

        closeParams.currentPrice = ISSListing(params.listingAddress).prices(uint256(uint160(params.listingAddress)));
        uint256 totalValue = params.taxedMargin + params.excessMargin + leverageParams.leverageAmount;
        closeParams.payout = closeParams.currentPrice > 0 && totalValue > leverageParams.loanInitial
            ? (totalValue / closeParams.currentPrice) - leverageParams.loanInitial
            : 0;
        closeParams.decimals = ISSListing(params.listingAddress).decimalsB();
    }

    // Helper: Prepare closeShort
    function prepareCloseShort(
        ClosePositionParams memory params
    ) internal view returns (
        CloseParams memory closeParams,
        PositionCore memory core,
        PriceParams memory priceParams,
        MarginParams memory marginParams,
        LeverageParams memory leverageParams,
        RiskParams memory riskParams
    ) {
        core = ISSIsolatedDriver(params.driver).positionCore(params.positionId);
        priceParams = ISSIsolatedDriver(params.driver).priceParams(params.positionId);
        marginParams = ISSIsolatedDriver(params.driver).marginParams(params.positionId);
        leverageParams = ISSIsolatedDriver(params.driver).leverageParams(params.positionId);
        riskParams = ISSIsolatedDriver(params.driver).riskParams(params.positionId);
        require(core.status2 == 0, "Position not open");
        require(core.status1 == true, "Position not executable");

        closeParams.currentPrice = ISSListing(params.listingAddress).prices(uint256(uint160(params.listingAddress)));
        uint256 priceDiff = priceParams.priceMin > closeParams.currentPrice ? priceParams.priceMin - closeParams.currentPrice : 0;
        uint256 profit = (priceDiff * marginParams.marginInitial * leverageParams.leverageVal);
        uint256 marginReturn = (params.taxedMargin + params.excessMargin) * closeParams.currentPrice;
        closeParams.payout = profit + marginReturn;
        closeParams.decimals = ISSListing(params.listingAddress).decimalsA();
    }

    // Helper: Denormalize payout
    function denormalizePayout(uint256 payout, uint8 decimals) internal pure returns (uint256) {
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
        ClosePositionParams memory params,
        uint8 positionType,
        uint256 payout
    ) internal {
        bool success;
        (success, ) = params.driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", params.positionId, 1
            )
        );
        require(success, "Status update failed");

        if (payout > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: params.makerAddress,
                required: payout,
                payoutType: positionType
            });
            ISSListing(params.listingAddress).ssUpdate(address(this), updates);
        }

        uint256 io = params.taxedMargin + params.excessMargin;
        (success, ) = params.driver.call(
            abi.encodeWithSignature(
                "reduceHistoricalInterest(uint256,uint256,uint256,uint256)",
                ISSIsolatedDriver(params.driver).historicalInterestHeight(),
                positionType == 0 ? io : 0,
                positionType == 1 ? io : 0,
                block.timestamp
            )
        );
        require(success, "Interest reduction failed");
    }

    // Close long position
    function closeLongPosition(
        ClosePositionParams memory params,
        LongCloseParams memory longParams
    ) external onlyDriver(params.driver) returns (uint256 payout) {
        return internalCloseLongPosition(params, longParams);
    }

    // Close short position
    function closeShortPosition(
        ClosePositionParams memory params,
        ShortCloseParams memory shortParams
    ) external onlyDriver(params.driver) returns (uint256 payout) {
        return internalCloseShortPosition(params, shortParams);
    }

    // Cancel position
    function cancelPosition(
        ClosePositionParams memory params,
        uint8 positionType
    ) external onlyDriver(params.driver) {
        internalCancelPosition(params, positionType);
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
    ) external onlyDriver(driver) {
        bool success;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updateExcessMargin(uint256,uint256)", positionId, normalizedAmount
            )
        );
        require(success, "Margin update failed");

        uint256 io = normalizedAmount;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updateHistoricalInterest(uint256,uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                positionType == 0 ? io : 0,
                positionType == 1 ? io : 0,
                block.timestamp
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
    ) external onlyDriver(driver) {
        bool success;
        (success, ) = driver.call(
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
    ) external onlyDriver(driver) {
        bool success;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionTP(uint256,uint256)", positionId, newTakeProfitPrice
            )
        );
        require(success, "TP update failed");
    }

    // Close all short
    function closeAllShort(address user, address driver) external onlyDriver(driver) returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).positionsByType(1);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            MarginParams memory marginParams = ISSIsolatedDriver(driver).marginParams(positions[i]);
            PriceParams memory priceParams = ISSIsolatedDriver(driver).priceParams(positions[i]);
            LeverageParams memory leverageParams = ISSIsolatedDriver(driver).leverageParams(positions[i]);
            if (core.makerAddress == user && core.status2 == 0 && core.status1 == true) {
                ClosePositionParams memory closeParams = ClosePositionParams({
                    positionId: positions[i],
                    listingAddress: core.listingAddress,
                    makerAddress: core.makerAddress,
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess,
                    driver: driver
                });
                ShortCloseParams memory shortParams = ShortCloseParams({
                    minPrice: priceParams.priceMin,
                    initialMargin: marginParams.marginInitial,
                    leverage: leverageParams.leverageVal
                });
                internalCloseShortPosition(closeParams, shortParams);
                count++;
            }
        }
    }

    // Cancel all short
    function cancelAllShort(address user, address driver) external onlyDriver(driver) returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).pendingPositions(user, 1);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            MarginParams memory marginParams = ISSIsolatedDriver(driver).marginParams(positions[i]);
            if (core.makerAddress == user && core.status1 == false && core.status2 == 0) {
                ClosePositionParams memory closeParams = ClosePositionParams({
                    positionId: positions[i],
                    listingAddress: core.listingAddress,
                    makerAddress: core.makerAddress,
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess,
                    driver: driver
                });
                internalCancelPosition(closeParams, core.positionType);
                count++;
            }
        }
    }

    // Close all longs
    function closeAllLongs(address user, address driver) external onlyDriver(driver) returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).positionsByType(0);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            MarginParams memory marginParams = ISSIsolatedDriver(driver).marginParams(positions[i]);
            LeverageParams memory leverageParams = ISSIsolatedDriver(driver).leverageParams(positions[i]);
            if (core.makerAddress == user && core.status2 == 0 && core.status1 == true) {
                ClosePositionParams memory closeParams = ClosePositionParams({
                    positionId: positions[i],
                    listingAddress: core.listingAddress,
                    makerAddress: core.makerAddress,
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess,
                    driver: driver
                });
                LongCloseParams memory longParams = LongCloseParams({
                    leverageAmount: leverageParams.leverageAmount,
                    loanInitial: leverageParams.loanInitial
                });
                internalCloseLongPosition(closeParams, longParams);
                count++;
            }
        }
    }

    // Cancel all long
    function cancelAllLong(address user, address driver) external onlyDriver(driver) returns (uint256 count) {
        count = 0;
        uint256[] memory positions = ISSIsolatedDriver(driver).pendingPositions(user, 0);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionCore memory core = ISSIsolatedDriver(driver).positionCore(positions[i]);
            MarginParams memory marginParams = ISSIsolatedDriver(driver).marginParams(positions[i]);
            if (core.makerAddress == user && core.status1 == false && core.status2 == 0) {
                ClosePositionParams memory closeParams = ClosePositionParams({
                    positionId: positions[i],
                    listingAddress: core.listingAddress,
                    makerAddress: core.makerAddress,
                    taxedMargin: marginParams.marginTaxed,
                    excessMargin: marginParams.marginExcess,
                    driver: driver
                });
                internalCancelPosition(closeParams, core.positionType);
                count++;
            }
        }
    }
}