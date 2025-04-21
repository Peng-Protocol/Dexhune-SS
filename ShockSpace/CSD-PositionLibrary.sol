// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.6:
// - Further mitigated stack depth errors in executeEnter$ by introducing EnterParams struct to group parameters.
// - Added updatePositionState helper for position storage and index updates.
// - Added recordHistoricalInterest helper for historical interest updates.
// - Retained createPositionDetails and handleMarginAndFeeTransfers helpers.
// - Maintained public visibility for executeCloseLong, executeCloseShort, and cancelPosition.
// - Preserved HistoricalInterest tracking, query functions, and fee/margin routing.

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

struct PositionDetails {
    address makerAddress;
    uint256 minPrice;
    uint256 maxPrice;
    uint256 initialMargin;
    uint256 taxedMargin;
    uint256 excessMargin; // Reference only, not used in calculations
    uint8 leverage;
    uint256 leverageAmount;
    uint256 initialLoan;
    uint256 liquidationPrice;
    uint256 stopLossPrice;
    uint256 takeProfitPrice;
    uint8 positionType; // 0: Long, 1: Short
    bool status1; // false: pending, true: executed
    uint8 status2; // 0: open, 1: closed, 2: cancelled
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

struct ExecutionPrepData {
    uint256[] pendingIds;
    uint256[] activeIds;
    bool[] shouldClose;
}

struct BatchPrepData {
    uint256[] positionIds;
    uint256[] totalMargins;
}

struct HistoricalInterest {
    uint256 shortIO;
    uint256 longIO;
    uint256 timestamp;
}

struct EnterParams {
    address listingAddress;
    uint256 initialMargin;
    uint256 excessMargin;
    uint8 leverage;
    uint256 stopLossPrice;
    uint256 takeProfitPrice;
    address listingToken;
    EnterPrepData prep;
    address driver;
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
    function positionDetails(uint256 positionId) external view returns (PositionDetails memory);
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    function makerTokenMargin(address maker, address token) external view returns (uint256);
    function setPositionDetails(uint256 positionId, PositionDetails memory pos) external;
    function updatePositionStatus(uint256 positionId, uint8 newStatus) external;
    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external;
    function updatePendingPositions(address listingAddress, uint8 positionType, uint256 positionId) external;
    function positionCount() external view returns (uint256);
}

contract CSDPositionLibrary {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Historical Interest Storage
    mapping(uint256 => HistoricalInterest) public historicalInterest;
    uint256 public historicalInterestHeight;

    // Helper: Validate position parameters
    function validatePositionParams(
        uint256 initialMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 minPrice,
        uint256 maxPrice,
        uint8 positionType
    ) internal pure {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");
        require(minPrice > 0 && minPrice <= maxPrice, "Invalid price range");
        if (positionType == 0) {
            require(stopLossPrice == 0 || stopLossPrice < minPrice, "Invalid stop loss");
            require(takeProfitPrice == 0 || takeProfitPrice > maxPrice, "Invalid take profit");
        } else {
            require(stopLossPrice == 0 || stopLossPrice > maxPrice, "Invalid stop loss");
            require(takeProfitPrice == 0 || takeProfitPrice < minPrice, "Invalid take profit");
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

    // Helper: Update historical interest
    function updateHistoricalInterest(uint8 positionType, uint256 marginAmount, bool isAdd) internal {
        require(positionType <= 1, "Invalid position type");
        require(marginAmount > 0, "Invalid margin amount");
        uint256 currentHeight = historicalInterestHeight;
        if (currentHeight == 0 || historicalInterest[currentHeight - 1].timestamp != block.timestamp) {
            historicalInterest[currentHeight].timestamp = block.timestamp;
            currentHeight++;
            historicalInterestHeight = currentHeight;
        }
        if (positionType == 0) {
            if (isAdd) {
                historicalInterest[currentHeight - 1].longIO += marginAmount;
            } else {
                historicalInterest[currentHeight - 1].longIO = historicalInterest[currentHeight - 1].longIO > marginAmount
                    ? historicalInterest[currentHeight - 1].longIO - marginAmount
                    : 0;
            }
        } else {
            if (isAdd) {
                historicalInterest[currentHeight - 1].shortIO += marginAmount;
            } else {
                historicalInterest[currentHeight - 1].shortIO = historicalInterest[currentHeight - 1].shortIO > marginAmount
                    ? historicalInterest[currentHeight - 1].shortIO - marginAmount
                    : 0;
            }
        }
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

    // Helper: Create PositionDetails struct
    function createPositionDetails(
        address maker,
        uint256 initialMargin,
        uint256 actualTaxedMargin,
        uint256 actualExcessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address listingAddress,
        uint8 positionType,
        EnterPrepData memory prep,
        uint256 positionId
    ) internal pure returns (PositionDetails memory) {
        return PositionDetails({
            makerAddress: maker,
            minPrice: prep.minPrice,
            maxPrice: prep.maxPrice,
            initialMargin: initialMargin,
            taxedMargin: actualTaxedMargin,
            excessMargin: actualExcessMargin,
            leverage: leverage,
            leverageAmount: prep.leverageAmount,
            initialLoan: prep.initialLoan,
            liquidationPrice: prep.liquidationPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: positionType,
            status1: false,
            status2: 0,
            closePrice: 0,
            priceAtEntry: prep.minPrice,
            positionId: positionId,
            listingAddress: listingAddress
        });
    }

    // Helper: Handle margin and fee transfers
    function handleMarginAndFeeTransfers(
        address listingAddress,
        address listingToken,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        bool isLong
    ) internal returns (uint256 actualTaxedMargin, uint256 actualExcessMargin) {
        actualTaxedMargin = transferMargin(listingAddress, listingToken, taxedMargin);
        actualExcessMargin = transferMargin(listingAddress, listingToken, excessMargin);
        if (fee > 0) {
            address liquidityAddr = ISSListing(listingAddress).liquidityAddresses(listingAddress);
            uint256 actualFee = transferMargin(liquidityAddr, listingToken, fee);
            ISSLiquidity(liquidityAddr).addFees(isLong, actualFee);
        }
    }

    // Helper: Update position state
    function updatePositionState(
        uint256 positionId,
        PositionDetails memory pos,
        address maker,
        uint8 positionType,
        address listingAddress,
        address driver
    ) internal {
        ISSCrossDriver(driver).setPositionDetails(positionId, pos);
        ISSCrossDriver(driver).updatePositionIndexes(maker, positionType, positionId);
        ISSCrossDriver(driver).updatePendingPositions(listingAddress, positionType, positionId);
    }

    // Helper: Record historical interest
    function recordHistoricalInterest(
        uint8 positionType,
        uint256 actualTaxedMargin,
        uint256 actualExcessMargin
    ) internal {
        updateHistoricalInterest(positionType, actualTaxedMargin + actualExcessMargin, true);
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
    ) internal view returns (EnterPrepData memory prep) {
        (prep.minPrice, prep.maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        validatePositionParams(initialMargin, leverage, stopLossPrice, takeProfitPrice, prep.minPrice, prep.maxPrice, 0);
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
        require(driver != address(0), "Invalid driver");
        EnterParams memory params = EnterParams({
            listingAddress: listingAddress,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            listingToken: token0,
            prep: prep,
            driver: driver
        });

        (uint256 actualTaxedMargin, uint256 actualExcessMargin) = handleMarginAndFeeTransfers(
            params.listingAddress,
            params.listingToken,
            params.prep.taxedMargin,
            params.excessMargin,
            params.prep.fee,
            true
        );

        positionId = ISSCrossDriver(params.driver).positionCount();
        PositionDetails memory pos = createPositionDetails(
            msg.sender,
            params.initialMargin,
            actualTaxedMargin,
            actualExcessMargin,
            params.leverage,
            params.stopLossPrice,
            params.takeProfitPrice,
            params.listingAddress,
            0,
            params.prep,
            positionId
        );

        updatePositionState(positionId, pos, msg.sender, 0, params.listingAddress, params.driver);
        recordHistoricalInterest(0, actualTaxedMargin, actualExcessMargin);
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
    ) internal view returns (EnterPrepData memory prep) {
        (prep.minPrice, prep.maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        validatePositionParams(initialMargin, leverage, stopLossPrice, takeProfitPrice, prep.minPrice, prep.maxPrice, 1);
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
        require(driver != address(0), "Invalid driver");
        EnterParams memory params = EnterParams({
            listingAddress: listingAddress,
            initialMargin: initialMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            listingToken: token1,
            prep: prep,
            driver: driver
        });

        (uint256 actualTaxedMargin, uint256 actualExcessMargin) = handleMarginAndFeeTransfers(
            params.listingAddress,
            params.listingToken,
            params.prep.taxedMargin,
            params.excessMargin,
            params.prep.fee,
            false
        );

        positionId = ISSCrossDriver(params.driver).positionCount();
        PositionDetails memory pos = createPositionDetails(
            msg.sender,
            params.initialMargin,
            actualTaxedMargin,
            actualExcessMargin,
            params.leverage,
            params.stopLossPrice,
            params.takeProfitPrice,
            params.listingAddress,
            1,
            params.prep,
            positionId
        );

        updatePositionState(positionId, pos, msg.sender, 1, params.listingAddress, params.driver);
        recordHistoricalInterest(1, actualTaxedMargin, actualExcessMargin);
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
    ) internal view returns (ClosePrepData memory prep) {
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
    ) public returns (uint256 payout) {
        require(driver != address(0), "Invalid driver");
        updateHistoricalInterest(0, prep.marginToReturn, false);
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
    ) internal view returns (ClosePrepData memory prep) {
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
    ) public returns (uint256 payout) {
        require(driver != address(0), "Invalid driver");
        updateHistoricalInterest(1, prep.marginToReturn, false);
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
    ) public {
        require(driver != address(0), "Invalid driver");
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        uint256 availableMargin = ISSCrossDriver(driver).makerTokenMargin(makerAddress, token);
        uint256 marginToReturn = taxedMargin + (excessMargin > availableMargin ? availableMargin : excessMargin);
        updateHistoricalInterest(positionType, marginToReturn, false);
        ISSCrossDriver(driver).updatePositionStatus(positionId, 2);
        if (marginToReturn > 0) {
            uint256 normalizedMargin = ICSDUtilityLibrary(driver).normalizeAmount(token, marginToReturn);
            queuePayoutOrder(listingAddress, makerAddress, normalizedMargin, positionType);
        }
    }

    // Prep force execution
    function prepForceExecution(
        address listingAddress,
        address driver
    ) internal view returns (ExecutionPrepData memory prep) {
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        uint256 maxActions = 50;

        prep.pendingIds = new uint256[](maxActions);
        prep.activeIds = new uint256[](maxActions);
        prep.shouldClose = new bool[](maxActions);
        uint256 actionCount = 0;

        for (uint8 positionType = 0; positionType <= 1 && actionCount < maxActions; positionType++) {
            uint256[] memory pending = ISSCrossDriver(driver).pendingPositions(listingAddress, positionType);
            for (uint256 i = 0; i < pending.length && actionCount < maxActions; i++) {
                uint256 positionId = pending[i];
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positionId);
                if (pos.status1 == false && pos.status2 == 0) {
                    if (currentPrice >= pos.minPrice && currentPrice <= pos.maxPrice) {
                        prep.pendingIds[actionCount] = positionId;
                        prep.shouldClose[actionCount] = false;
                        actionCount++;
                    }
                }
            }
        }

        for (uint8 positionType = 0; positionType <= 1 && actionCount < maxActions; positionType++) {
            uint256[] memory active = ISSCrossDriver(driver).positionsByType(positionType);
            for (uint256 i = 0; i < active.length && actionCount < maxActions; i++) {
                uint256 positionId = active[i];
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positionId);
                if (pos.status1 == true && pos.status2 == 0 && pos.listingAddress == listingAddress) {
                    bool shouldClose = false;
                    if (pos.positionType == 0) {
                        if (pos.stopLossPrice > 0 && currentPrice <= pos.stopLossPrice) shouldClose = true;
                        else if (pos.takeProfitPrice > 0 && currentPrice >= pos.takeProfitPrice) shouldClose = true;
                        else if (currentPrice <= pos.liquidationPrice) shouldClose = true;
                    } else {
                        if (pos.stopLossPrice > 0 && currentPrice >= pos.stopLossPrice) shouldClose = true;
                        else if (pos.takeProfitPrice > 0 && currentPrice <= pos.takeProfitPrice) shouldClose = true;
                        else if (currentPrice >= pos.liquidationPrice) shouldClose = true;
                    }
                    if (shouldClose) {
                        prep.activeIds[actionCount] = positionId;
                        prep.shouldClose[actionCount] = true;
                        actionCount++;
                    }
                }
            }
        }
    }

    // Execute force execution
    function executeForceExecution(
        ExecutionPrepData memory prep,
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount) {
        require(driver != address(0), "Invalid driver");
        resultCount = 0;

        for (uint256 i = 0; i < prep.pendingIds.length; i++) {
            if (prep.pendingIds[i] != 0 && !prep.shouldClose[i]) {
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(prep.pendingIds[i]);
                pos.status1 = true;
                ISSCrossDriver(driver).setPositionDetails(prep.pendingIds[i], pos);
                resultCount++;
            }
        }

        for (uint256 i = 0; i < prep.activeIds.length; i++) {
            if (prep.activeIds[i] != 0 && prep.shouldClose[i]) {
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(prep.activeIds[i]);
                uint256 totalMargin = ISSCrossDriver(driver).makerTokenMargin(
                    pos.makerAddress,
                    pos.positionType == 0 ? ISSListing(pos.listingAddress).tokenA() : ISSListing(pos.listingAddress).tokenB()
                );
                if (pos.positionType == 0) {
                    ClosePrepData memory closePrep = prepCloseLong(
                        prep.activeIds[i],
                        pos.listingAddress,
                        pos.makerAddress,
                        pos.taxedMargin,
                        pos.excessMargin,
                        pos.leverageAmount,
                        pos.initialLoan,
                        totalMargin,
                        driver
                    );
                    updateHistoricalInterest(0, closePrep.marginToReturn, false);
                    executeCloseLong(prep.activeIds[i], pos.listingAddress, pos.makerAddress, closePrep, driver);
                } else {
                    ClosePrepData memory closePrep = prepCloseShort(
                        prep.activeIds[i],
                        pos.listingAddress,
                        pos.makerAddress,
                        pos.minPrice,
                        pos.initialMargin,
                        pos.leverage,
                        pos.taxedMargin,
                        pos.excessMargin,
                        totalMargin,
                        driver
                    );
                    updateHistoricalInterest(1, closePrep.marginToReturn, false);
                    executeCloseShort(prep.activeIds[i], pos.listingAddress, pos.makerAddress, closePrep, driver);
                }
                resultCount++;
            }
        }
    }

    // Add excess margin
    function addExcessMargin(
        address maker,
        uint256 amount,
        address token,
        uint256 normalizedAmount,
        address driver
    ) external {
        require(driver != address(0), "Invalid driver");
        require(amount > 0, "Invalid amount");
        uint256 actualAmount = transferMargin(driver, token, amount);
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
        require(driver != address(0), "Invalid driver");
        require(positionType <= 1, "Invalid position type");
        require(
            newStopLossPrice == 0 ||
            (positionType == 0 && newStopLossPrice < minPrice) ||
            (positionType == 1 && newStopLossPrice > maxPrice),
            "Invalid stop loss"
        );

        PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positionId);
        pos.stopLossPrice = newStopLossPrice;
        ISSCrossDriver(driver).setPositionDetails(positionId, pos);
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
        require(driver != address(0), "Invalid driver");
        require(positionType <= 1, "Invalid position type");
        require(
            newTakeProfitPrice == 0 ||
            (positionType == 0 && newTakeProfitPrice > maxPrice) ||
            (positionType == 1 && newTakeProfitPrice < minPrice),
            "Invalid take profit"
        );

        PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positionId);
        pos.takeProfitPrice = newTakeProfitPrice;
        ISSCrossDriver(driver).setPositionDetails(positionId, pos);
    }

    // Prep close all short
    function prepCloseAllShort(address user, address driver) internal view returns (BatchPrepData memory prep) {
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).positionsByType(1);
        prep.positionIds = new uint256[](maxIteration);
        prep.totalMargins = new uint256[](maxIteration);
        uint256 count = 0;

        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status2 == 0 && pos.positionType == 1) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(pos.makerAddress, ISSListing(pos.listingAddress).tokenB());
                count++;
            }
        }
    }

    // Execute close all short
    function executeCloseAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        require(driver != address(0), "Invalid driver");
        count = 0;
        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] != 0) {
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(prep.positionIds[i]);
                ClosePrepData memory closePrep = prepCloseShort(
                    prep.positionIds[i],
                    pos.listingAddress,
                    pos.makerAddress,
                    pos.minPrice,
                    pos.initialMargin,
                    pos.leverage,
                    pos.taxedMargin,
                    pos.excessMargin,
                    prep.totalMargins[i],
                    driver
                );
                updateHistoricalInterest(1, closePrep.marginToReturn, false);
                executeCloseShort(prep.positionIds[i], pos.listingAddress, pos.makerAddress, closePrep, driver);
                count++;
            }
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
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status1 == false && pos.status2 == 0 && pos.positionType == 1) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(pos.makerAddress, ISSListing(pos.listingAddress).tokenB());
                count++;
            }
        }
    }

    // Execute cancel all short
    function executeCancelAllShort(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        require(driver != address(0), "Invalid driver");
        count = 0;
        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] != 0) {
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(prep.positionIds[i]);
                uint256 marginToReturn = pos.taxedMargin + (pos.excessMargin > prep.totalMargins[i] ? prep.totalMargins[i] : pos.excessMargin);
                updateHistoricalInterest(1, marginToReturn, false);
                cancelPosition(
                    prep.positionIds[i],
                    pos.listingAddress,
                    pos.makerAddress,
                    pos.taxedMargin,
                    pos.excessMargin,
                    pos.positionType,
                    driver
                );
                count++;
            }
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
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status2 == 0 && pos.positionType == 0) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(pos.makerAddress, ISSListing(pos.listingAddress).tokenA());
                count++;
            }
        }
    }

    // Execute close all longs
    function executeCloseAllLongs(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        require(driver != address(0), "Invalid driver");
        count = 0;
        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] != 0) {
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(prep.positionIds[i]);
                ClosePrepData memory closePrep = prepCloseLong(
                    prep.positionIds[i],
                    pos.listingAddress,
                    pos.makerAddress,
                    pos.taxedMargin,
                    pos.excessMargin,
                    pos.leverageAmount,
                    pos.initialLoan,
                    prep.totalMargins[i],
                    driver
                );
                updateHistoricalInterest(0, closePrep.marginToReturn, false);
                executeCloseLong(prep.positionIds[i], pos.listingAddress, pos.makerAddress, closePrep, driver);
                count++;
            }
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
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status1 == false && pos.status2 == 0 && pos.positionType == 0) {
                prep.positionIds[count] = positions[i];
                prep.totalMargins[count] = ISSCrossDriver(driver).makerTokenMargin(pos.makerAddress, ISSListing(pos.listingAddress).tokenA());
                count++;
            }
        }
    }

    // Execute cancel all long
    function executeCancelAllLong(address user, BatchPrepData memory prep, address driver) external returns (uint256 count) {
        require(driver != address(0), "Invalid driver");
        count = 0;
        for (uint256 i = 0; i < prep.positionIds.length; i++) {
            if (prep.positionIds[i] != 0) {
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(prep.positionIds[i]);
                uint256 marginToReturn = pos.taxedMargin + (pos.excessMargin > prep.totalMargins[i] ? prep.totalMargins[i] : pos.excessMargin);
                updateHistoricalInterest(0, marginToReturn, false);
                cancelPosition(
                    prep.positionIds[i],
                    pos.listingAddress,
                    pos.makerAddress,
                    pos.taxedMargin,
                    pos.excessMargin,
                    pos.positionType,
                    driver
                );
                count++;
            }
        }
    }

    // Query historical interest height
    function interestHeight() external view returns (uint256) {
        return historicalInterestHeight;
    }

    // Query latest historical interest
    function latestInterest() external view returns (HistoricalInterest memory) {
        require(historicalInterestHeight > 0, "No interest history");
        return historicalInterest[historicalInterestHeight - 1];
    }

    // Query past historical interest
    function queryInterest(uint256 step, uint16 maxIteration) external view returns (HistoricalInterest[] memory) {
        require(maxIteration <= 1000, "Max iteration exceeded");
        uint256 start = step * uint256(maxIteration);
        uint256 end = start + uint256(maxIteration) > historicalInterestHeight ? historicalInterestHeight : start + uint256(maxIteration);
        HistoricalInterest[] memory result = new HistoricalInterest[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = historicalInterest[i];
        }
        return result;
    }
}