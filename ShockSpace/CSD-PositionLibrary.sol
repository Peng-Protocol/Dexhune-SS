// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.16:
// - Addressed persistent stack too deep in executeEnterLong/executeEnterShort:
//   - Extracted all local variables into EnterContext struct, reducing stack to ~2 slots per helper.
//   - Helpers (startEnter, batchCoreAndPrice, batchMarginAndLeverage, finalizeEnter) use EnterContext and driver only.
//   - Moved validation to validateEnterContext to avoid stack usage in helpers.
//   - Simplified createPositionCoreAndParams to store directly in EnterContext.
// - Maintained batched workflow: startEnter (margins/fees), batchCoreAndPrice (core/price),
//   batchMarginAndLeverage (margin/leverage), finalizeEnter (exit/indexes/interest).
// - Preserved compatibility with SSCrossDriver.sol v0.0.9, CSDExecutionLibrary.sol v0.0.1,
//   and CSD-UtilityLibrary.sol v0.0.2.
// - Preserved prepEnter$, executeClose$, prepClose$, cancelPosition, and storage setters.
// - Used explicit casting (e.g., uint8(0)) and DECIMAL_PRECISION (1e18).
// - Ensured statelessness with explicit driver parameter.
// - Avoided nested struct initialization; computed dependencies in EnterContext.

import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";

// Structs
struct PayoutUpdate {
    address recipient;
    uint256 required;
    uint8 payoutType;
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

struct PositionDetails {
    address makerAddress;
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
    uint8 positionType;
    bool status1;
    uint8 status2;
    uint256 closePrice;
    uint256 priceAtEntry;
    uint256 positionId;
    address listingAddress;
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

struct HistoricalInterest {
    uint256 shortIO;
    uint256 longIO;
    uint256 timestamp;
}

struct EnterContext {
    // Input parameters
    address listingAddress;
    uint256 initialMargin;
    uint256 excessMargin;
    uint8 leverage;
    uint256 stopLossPrice;
    uint256 takeProfitPrice;
    address token;
    bool isLong;
    uint8 positionType;
    address maker;
    // Prep data
    EnterPrepData prep;
    // State
    uint256 actualTaxedMargin;
    uint256 actualExcessMargin;
    uint256 positionId;
    PositionCore core;
    PriceParams priceParams;
    MarginParams marginParams;
    LeverageParams leverageParams;
    ExitParams exitParams;
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
}

interface ICSDUtilityLibrary {
    function normalizeAmount(address token, uint256 amount) external view returns (uint256);
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice);
    function parseUint(string memory str) external pure returns (uint256);
}

interface ISSCrossDriver {
    function positionDetails(uint256 positionId) external view returns (PositionCore memory, PriceParams memory, MarginParams memory, LeverageParams memory, ExitParams memory);
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    function makerTokenMargin(address maker, address token) external view returns (uint256);
    function setPositionCore(uint256 positionId, PositionCore memory core) external;
    function setPriceParams(uint256 positionId, PriceParams memory params) external;
    function setMarginParams(uint256 positionId, MarginParams memory params) external;
    function setLeverageParams(uint256 positionId, LeverageParams memory params) external;
    function setExitParams(uint256 positionId, ExitParams memory params) external;
    function setPositionDetails(uint256 positionId, PositionDetails memory pos) external;
    function updatePositionStatus(uint256 positionId, uint8 newStatus) external;
    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external;
    function updatePendingPositions(address listingAddress, uint8 positionType, uint256 positionId) external;
    function positionCount() external view returns (uint256);
    function getHistoricalInterest(uint256 index) external view returns (HistoricalInterest memory);
    function setHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external;
    function getInterestHeight() external view returns (uint256);
    function latestInterest() external view returns (HistoricalInterest memory);
    function queryInterest(uint256 step, uint16 maxIteration) external view returns (HistoricalInterest[] memory);
}

library CSDPositionLibrary {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Helper: Validate EnterContext
    function validateEnterContext(EnterContext memory ctx) internal pure {
        require(ctx.initialMargin > 0, "Invalid margin");
        require(ctx.leverage >= 2 && ctx.leverage <= 100, "Invalid leverage");
        require(ctx.prep.minPrice > 0 && ctx.prep.minPrice <= ctx.prep.maxPrice, "Invalid price range");
        if (ctx.positionType == 0) {
            require(ctx.stopLossPrice == 0 || ctx.stopLossPrice < ctx.prep.minPrice, "Invalid stop loss");
            require(ctx.takeProfitPrice == 0 || ctx.takeProfitPrice > ctx.prep.maxPrice, "Invalid take profit");
        } else {
            require(ctx.stopLossPrice == 0 || ctx.stopLossPrice > ctx.prep.maxPrice, "Invalid stop loss");
            require(ctx.takeProfitPrice == 0 || ctx.takeProfitPrice < ctx.prep.minPrice, "Invalid take profit");
        }
    }

    // Helper: Compute position metrics
    function computePositionMetrics(
        uint256 initialMargin,
        uint8 leverage,
        uint256 totalMargin,
        uint256 minPrice,
        uint8 positionType
    ) internal pure returns (EnterPrepData memory prep) {
        prep.fee = (uint256(leverage) - 1) * initialMargin / 100;
        prep.taxedMargin = initialMargin - prep.fee;
        prep.leverageAmount = initialMargin * uint256(leverage);
        uint256 marginRatio = (totalMargin + prep.taxedMargin) / prep.leverageAmount;
        if (positionType == 0) {
            prep.liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;
            prep.initialLoan = prep.leverageAmount / (minPrice / DECIMAL_PRECISION);
        } else {
            prep.liquidationPrice = minPrice + marginRatio;
            prep.initialLoan = prep.leverageAmount * minPrice;
        }
        prep.minPrice = minPrice;
        prep.maxPrice = minPrice; // Simplified for single price entry
    }

    // Helper: Calculate long payout
    function calculateLongPayout(
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 leverageAmount,
        uint256 initialLoan,
        uint256 currentPrice,
        uint256 availableMargin
    ) internal pure returns (uint256 payout, uint256 marginToReturn) {
        marginToReturn = taxedMargin + (excessMargin > availableMargin ? availableMargin : excessMargin);
        payout = (taxedMargin + marginToReturn + leverageAmount) / currentPrice - initialLoan;
    }

    // Helper: Calculate short payout
    function calculateShortPayout(
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 minPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 currentPrice,
        uint256 availableMargin
    ) internal pure returns (uint256 payout, uint256 marginToReturn) {
        marginToReturn = taxedMargin + (excessMargin > availableMargin ? availableMargin : excessMargin);
        uint256 priceDiff = minPrice > currentPrice ? minPrice - currentPrice : 0;
        payout = priceDiff * initialMargin * uint256(leverage) + marginToReturn * currentPrice;
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

    // Helper: Handle margin and fee transfers
    function handleMarginAndFeeTransfers(EnterContext memory ctx) internal {
        ctx.actualTaxedMargin = transferMargin(ctx.listingAddress, ctx.token, ctx.prep.taxedMargin);
        ctx.actualExcessMargin = transferMargin(ctx.listingAddress, ctx.token, ctx.excessMargin);
        if (ctx.prep.fee > 0) {
            address liquidityAddr = ISSListing(ctx.listingAddress).liquidityAddresses(ctx.listingAddress);
            uint256 actualFee = transferMargin(liquidityAddr, ctx.token, ctx.prep.fee);
            ISSLiquidity(liquidityAddr).addFees(ctx.isLong, actualFee);
        }
    }

    // Helper: Create PositionCore and parameter structs
    function createPositionCoreAndParams(EnterContext memory ctx) internal pure {
        ctx.core = PositionCore({
            makerAddress: ctx.maker,
            listingAddress: ctx.listingAddress,
            positionId: ctx.positionId,
            positionType: ctx.positionType,
            status1: false,
            status2: 0
        });
        ctx.priceParams = PriceParams({
            minPrice: ctx.prep.minPrice,
            maxPrice: ctx.prep.maxPrice,
            priceAtEntry: ctx.prep.minPrice
        });
        ctx.marginParams = MarginParams({
            initialMargin: ctx.initialMargin,
            taxedMargin: ctx.actualTaxedMargin,
            excessMargin: ctx.actualExcessMargin
        });
        ctx.leverageParams = LeverageParams({
            leverage: ctx.leverage,
            leverageAmount: ctx.prep.leverageAmount,
            initialLoan: ctx.prep.initialLoan
        });
        ctx.exitParams = ExitParams({
            liquidationPrice: ctx.prep.liquidationPrice,
            stopLossPrice: ctx.stopLossPrice,
            takeProfitPrice: ctx.takeProfitPrice,
            closePrice: 0
        });
    }

    // Helper: Get position ID from driver
    function getPositionId(address driver) internal view returns (uint256 positionId) {
        positionId = ISSCrossDriver(driver).positionCount();
    }

    // Helper: Start enter long/short
    function startEnter(EnterContext memory ctx, address driver) internal {
        validateEnterContext(ctx);
        ctx.positionId = getPositionId(driver);
        handleMarginAndFeeTransfers(ctx);
    }

    // Helper: Batch core and price params
    function batchCoreAndPrice(EnterContext memory ctx, address driver) internal {
        createPositionCoreAndParams(ctx);
        ISSCrossDriver(driver).setPositionCore(ctx.positionId, ctx.core);
        ISSCrossDriver(driver).setPriceParams(ctx.positionId, ctx.priceParams);
    }

    // Helper: Batch margin and leverage params
    function batchMarginAndLeverage(EnterContext memory ctx, address driver) internal {
        ISSCrossDriver(driver).setMarginParams(ctx.positionId, ctx.marginParams);
        ISSCrossDriver(driver).setLeverageParams(ctx.positionId, ctx.leverageParams);
    }

    // Helper: Finalize enter
    function finalizeEnter(EnterContext memory ctx, address driver) internal {
        ISSCrossDriver(driver).setExitParams(ctx.positionId, ctx.exitParams);
        ISSCrossDriver(driver).updatePositionIndexes(ctx.maker, ctx.positionType, ctx.positionId);
        ISSCrossDriver(driver).updatePendingPositions(ctx.listingAddress, ctx.positionType, ctx.positionId);
        uint256 totalMargin = ctx.actualTaxedMargin + ctx.actualExcessMargin;
        ISSCrossDriver(driver).setHistoricalInterest(
            ISSCrossDriver(driver).getInterestHeight(),
            ctx.positionType == 0 ? totalMargin : 0,
            ctx.positionType == 1 ? totalMargin : 0
        );
    }

    // Prep enter long
    function prepEnterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 totalMargin,
        address driver
    ) external view returns (EnterPrepData memory prep) {
        (prep.minPrice, prep.maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        EnterContext memory ctx = EnterContext({
            listingAddress: listingAddress,
            initialMargin: initialMargin,
            excessMargin: 0,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            token: address(0),
            isLong: true,
            positionType: 0,
            maker: address(0),
            prep: prep,
            actualTaxedMargin: 0,
            actualExcessMargin: 0,
            positionId: 0,
            core: PositionCore(address(0), address(0), 0, 0, false, 0),
            priceParams: PriceParams(0, 0, 0),
            marginParams: MarginParams(0, 0, 0),
            leverageParams: LeverageParams(0, 0, 0),
            exitParams: ExitParams(0, 0, 0, 0)
        });
        validateEnterContext(ctx);
        prep = computePositionMetrics(initialMargin, leverage, totalMargin, prep.minPrice, 0);
    }

    // Execute enter long
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
    ) external returns (uint256 positionId) {
        EnterContext memory ctx = EnterContext({
            listingAddress: listingAddress,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            token: token0,
            isLong: true,
            positionType: 0,
            maker: msg.sender,
            prep: prep,
            actualTaxedMargin: 0,
            actualExcessMargin: 0,
            positionId: 0,
            core: PositionCore(address(0), address(0), 0, 0, false, 0),
            priceParams: PriceParams(0, 0, 0),
            marginParams: MarginParams(0, 0, 0),
            leverageParams: LeverageParams(0, 0, 0),
            exitParams: ExitParams(0, 0, 0, 0)
        });

        startEnter(ctx, driver);
        batchCoreAndPrice(ctx, driver);
        batchMarginAndLeverage(ctx, driver);
        finalizeEnter(ctx, driver);
        positionId = ctx.positionId;
    }

    // Prep enter short
    function prepEnterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 totalMargin,
        address driver
    ) external view returns (EnterPrepData memory prep) {
        (prep.minPrice, prep.maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        EnterContext memory ctx = EnterContext({
            listingAddress: listingAddress,
            initialMargin: initialMargin,
            excessMargin: 0,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            token: address(0),
            isLong: false,
            positionType: 1,
            maker: address(0),
            prep: prep,
            actualTaxedMargin: 0,
            actualExcessMargin: 0,
            positionId: 0,
            core: PositionCore(address(0), address(0), 0, 0, false, 0),
            priceParams: PriceParams(0, 0, 0),
            marginParams: MarginParams(0, 0, 0),
            leverageParams: LeverageParams(0, 0, 0),
            exitParams: ExitParams(0, 0, 0, 0)
        });
        validateEnterContext(ctx);
        prep = computePositionMetrics(initialMargin, leverage, totalMargin, prep.minPrice, 1);
    }

    // Execute enter short
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
    ) external returns (uint256 positionId) {
        EnterContext memory ctx = EnterContext({
            listingAddress: listingAddress,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            token: token1,
            isLong: false,
            positionType: 1,
            maker: msg.sender,
            prep: prep,
            actualTaxedMargin: 0,
            actualExcessMargin: 0,
            positionId: 0,
            core: PositionCore(address(0), address(0), 0, 0, false, 0),
            priceParams: PriceParams(0, 0, 0),
            marginParams: MarginParams(0, 0, 0),
            leverageParams: LeverageParams(0, 0, 0),
            exitParams: ExitParams(0, 0, 0, 0)
        });

        startEnter(ctx, driver);
        batchCoreAndPrice(ctx, driver);
        batchMarginAndLeverage(ctx, driver);
        finalizeEnter(ctx, driver);
        positionId = ctx.positionId;
    }

    // Prep close long
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
    ) external view returns (ClosePrepData memory prep) {
        address token = ISSListing(listingAddress).tokenA();
        prep.currentPrice = ISSListing(listingAddress).prices(listingAddress);
        require(prep.currentPrice > 0, "Invalid price");
        uint256 availableMargin = ISSCrossDriver(driver).makerTokenMargin(makerAddress, token);
        require(availableMargin >= taxedMargin + excessMargin, "Insufficient margin");
        (prep.payout, prep.marginToReturn) = calculateLongPayout(
            taxedMargin,
            excessMargin,
            leverageAmount,
            initialLoan,
            prep.currentPrice,
            availableMargin
        );
    }

    // Execute close long
    function executeCloseLong(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        ClosePrepData memory prep,
        address driver
    ) external returns (uint256 payout) {
        ISSCrossDriver(driver).setHistoricalInterest(
            ISSCrossDriver(driver).getInterestHeight(),
            prep.marginToReturn,
            0
        );
        ISSCrossDriver(driver).updatePositionStatus(positionId, 1);
        if (prep.payout > 0) {
            address token = ISSListing(listingAddress).tokenA();
            uint256 normalizedPayout = ICSDUtilityLibrary(driver).normalizeAmount(token, prep.payout);
            queuePayoutOrder(listingAddress, makerAddress, normalizedPayout, uint8(0));
        }
        payout = prep.payout;
    }

    // Prep close short
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
    ) external view returns (ClosePrepData memory prep) {
        address token = ISSListing(listingAddress).tokenB();
        prep.currentPrice = ISSListing(listingAddress).prices(listingAddress);
        require(prep.currentPrice > 0, "Invalid price");
        uint256 availableMargin = ISSCrossDriver(driver).makerTokenMargin(makerAddress, token);
        require(availableMargin >= taxedMargin + excessMargin, "Insufficient margin");
        (prep.payout, prep.marginToReturn) = calculateShortPayout(
            taxedMargin,
            excessMargin,
            minPrice,
            initialMargin,
            leverage,
            prep.currentPrice,
            availableMargin
        );
    }

    // Execute close short
    function executeCloseShort(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        ClosePrepData memory prep,
        address driver
    ) external returns (uint256 payout) {
        ISSCrossDriver(driver).setHistoricalInterest(
            ISSCrossDriver(driver).getInterestHeight(),
            0,
            prep.marginToReturn
        );
        ISSCrossDriver(driver).updatePositionStatus(positionId, 1);
        if (prep.payout > 0) {
            address token = ISSListing(listingAddress).tokenB();
            uint256 normalizedPayout = ICSDUtilityLibrary(driver).normalizeAmount(token, prep.payout);
            queuePayoutOrder(listingAddress, makerAddress, normalizedPayout, uint8(1));
        }
        payout = prep.payout;
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
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        uint256 availableMargin = ISSCrossDriver(driver).makerTokenMargin(makerAddress, token);
        uint256 marginToReturn = taxedMargin + (excessMargin > availableMargin ? availableMargin : excessMargin);
        ISSCrossDriver(driver).setHistoricalInterest(
            ISSCrossDriver(driver).getInterestHeight(),
            positionType == 0 ? marginToReturn : 0,
            positionType == 1 ? marginToReturn : 0
        );
        ISSCrossDriver(driver).updatePositionStatus(positionId, 2);
        if (marginToReturn > 0) {
            uint256 normalizedMargin = ICSDUtilityLibrary(driver).normalizeAmount(token, marginToReturn);
            queuePayoutOrder(listingAddress, makerAddress, normalizedMargin, positionType);
        }
    }

    // External storage functions for driver
    function setPositionCore(uint256 positionId, PositionCore memory core) external {
        // No additional logic; driver handles storage
    }

    function setPriceParams(uint256 positionId, PriceParams memory params) external {
        // No additional logic; driver handles storage
    }

    function setMarginParams(uint256 positionId, MarginParams memory params) external {
        // No additional logic; driver handles storage
    }

    function setLeverageParams(uint256 positionId, LeverageParams memory params) external {
        // No additional logic; driver handles storage
    }

    function setExitParams(uint256 positionId, ExitParams memory params) external {
        // No additional logic; driver handles storage
    }

    // Compatibility wrapper for setPositionDetails
    function setPositionDetails(uint256 positionId, PositionDetails memory pos) external {
        PositionCore memory core = PositionCore({
            makerAddress: pos.makerAddress,
            listingAddress: pos.listingAddress,
            positionId: pos.positionId,
            positionType: pos.positionType,
            status1: pos.status1,
            status2: pos.status2
        });
        PriceParams memory priceParams = PriceParams({
            minPrice: pos.minPrice,
            maxPrice: pos.maxPrice,
            priceAtEntry: pos.priceAtEntry
        });
        MarginParams memory marginParams = MarginParams({
            initialMargin: pos.initialMargin,
            taxedMargin: pos.taxedMargin,
            excessMargin: pos.excessMargin
        });
        LeverageParams memory leverageParams = LeverageParams({
            leverage: pos.leverage,
            leverageAmount: pos.leverageAmount,
            initialLoan: pos.initialLoan
        });
        ExitParams memory exitParams = ExitParams({
            liquidationPrice: pos.liquidationPrice,
            stopLossPrice: pos.stopLossPrice,
            takeProfitPrice: pos.takeProfitPrice,
            closePrice: pos.closePrice
        });
        ISSCrossDriver(msg.sender).setPositionCore(positionId, core);
        ISSCrossDriver(msg.sender).setPriceParams(positionId, priceParams);
        ISSCrossDriver(msg.sender).setMarginParams(positionId, marginParams);
        ISSCrossDriver(msg.sender).setLeverageParams(positionId, leverageParams);
        ISSCrossDriver(msg.sender).setExitParams(positionId, exitParams);
    }

    // Historical interest updates
    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO, address driver) external {
        ISSCrossDriver(driver).setHistoricalInterest(index, longIO, shortIO);
    }

    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO, address driver) external {
        ISSCrossDriver(driver).setHistoricalInterest(index, longIO, shortIO);
    }
}