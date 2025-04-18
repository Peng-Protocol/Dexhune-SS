// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.2:
// - Updated closeLongPosition and closeShortPosition to use correct payout formulas and queue payout orders.
// - Updated cancelPosition to use payout orders instead of direct transfers.
// - Enhanced batch functions with maxIteration and payout orders.
// - Updated addExcessMargin to store totalMargin, not transfer to listingAddress.
// - Limited excessMargin returns in close/cancel based on totalMargin.
// - Added tax-on-transfer checks for margin transfers.
// - Clarified status1 (pending/executed) and status2 (open/closed/cancelled).
// - Enhanced forceExecution and enter$ to validate order ranges.
// - Included ISSListing interface inline.
// - Added prepInterestUpdate for historicalInterest updates.
// - Used local imports (./imports/...).
// - Assumed IERC20 includes decimals().

import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";
import "./imports/Strings.sol";

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
        function _queueInterestUpdate(uint256 positionId, uint8 positionType, uint256 marginAmount, bool isAdd) external;
    } 

contract CSDPositionLibrary {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Structs
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

    struct PayoutUpdate {
        address recipient;
        uint256 required;
        uint8 payoutType;
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

    // Prepare interest update
    function prepInterestUpdate(
        uint256 positionId,
        uint8 positionType,
        uint256 marginAmount,
        bool isAdd,
        address driver
    ) external {
        require(msg.sender == driver, "Only driver");
        ISSCrossDriver(driver)._queueInterestUpdate(positionId, positionType, marginAmount, isAdd);
    }

    // Enter long position
    function enterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token0,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        uint256 totalMargin,
        address driver
    ) external returns (uint256 positionId) {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        (uint256 minPrice, uint256 maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        require(minPrice > 0 && minPrice <= maxPrice, "Invalid price range");
        require(stopLossPrice == 0 || stopLossPrice < minPrice, "Invalid stop loss");
        require(takeProfitPrice == 0 || takeProfitPrice > maxPrice, "Invalid take profit");

        uint256 fee = (leverage - 1) * initialMargin / 100;
        uint256 taxedMargin = initialMargin - fee;
        uint256 leverageAmount = initialMargin * leverage;
        uint256 marginRatio = (totalMargin + taxedMargin) / leverageAmount;
        uint256 liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;
        uint256 initialLoan = leverageAmount / (minPrice / DECIMAL_PRECISION);

        address listingToken = token0;
        uint256 actualTaxedMargin = transferMargin(listingAddress, listingToken, taxedMargin);
        uint256 actualExcessMargin = transferMargin(listingAddress, listingToken, excessMargin);

        address liquidityAddr = ISSListing(listingAddress).liquidityAddresses(listingAddress);
        if (fee > 0) {
            uint256 actualFee = transferMargin(liquidityAddr, listingToken, fee);
            ISSLiquidity(liquidityAddr).addFees(true, actualFee);
        }

        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));
        PositionDetails memory pos = PositionDetails({
            makerAddress: msg.sender,
            minPrice: minPrice,
            maxPrice: maxPrice,
            initialMargin: initialMargin,
            taxedMargin: actualTaxedMargin,
            excessMargin: actualExcessMargin,
            leverage: leverage,
            leverageAmount: leverageAmount,
            initialLoan: initialLoan,
            liquidationPrice: liquidationPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 0,
            status1: false,
            status2: 0,
            closePrice: 0,
            priceAtEntry: minPrice,
            positionId: positionId,
            listingAddress: listingAddress
        });

        ISSCrossDriver(driver).setPositionDetails(positionId, pos);
        ISSCrossDriver(driver).updatePositionIndexes(msg.sender, 0, positionId);
        ISSCrossDriver(driver).updatePendingPositions(listingAddress, 0, positionId);
    }

    // Enter short position
    function enterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token1,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        uint256 totalMargin,
        address driver
    ) external returns (uint256 positionId) {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        (uint256 minPrice, uint256 maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        require(minPrice > 0 && minPrice <= maxPrice, "Invalid price range");
        require(stopLossPrice == 0 || stopLossPrice > maxPrice, "Invalid stop loss");
        require(takeProfitPrice == 0 || takeProfitPrice < minPrice, "Invalid take profit");

        uint256 fee = (leverage - 1) * initialMargin / 100;
        uint256 taxedMargin = initialMargin - fee;
        uint256 leverageAmount = initialMargin * leverage;
        uint256 marginRatio = (totalMargin + taxedMargin) / leverageAmount;
        uint256 liquidationPrice = minPrice + marginRatio;
        uint256 initialLoan = leverageAmount * minPrice;

        address listingToken = token1;
        uint256 actualTaxedMargin = transferMargin(listingAddress, listingToken, taxedMargin);
        uint256 actualExcessMargin = transferMargin(listingAddress, listingToken, excessMargin);

        address liquidityAddr = ISSListing(listingAddress).liquidityAddresses(listingAddress);
        if (fee > 0) {
            uint256 actualFee = transferMargin(liquidityAddr, listingToken, fee);
            ISSLiquidity(liquidityAddr).addFees(false, actualFee);
        }

        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));
        PositionDetails memory pos = PositionDetails({
            makerAddress: msg.sender,
            minPrice: minPrice,
            maxPrice: maxPrice,
            initialMargin: initialMargin,
            taxedMargin: actualTaxedMargin,
            excessMargin: actualExcessMargin,
            leverage: leverage,
            leverageAmount: leverageAmount,
            initialLoan: initialLoan,
            liquidationPrice: liquidationPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 1,
            status1: false,
            status2: 0,
            closePrice: 0,
            priceAtEntry: minPrice,
            positionId: positionId,
            listingAddress: listingAddress
        });

        ISSCrossDriver(driver).setPositionDetails(positionId, pos);
        ISSCrossDriver(driver).updatePositionIndexes(msg.sender, 1, positionId);
        ISSCrossDriver(driver).updatePendingPositions(listingAddress, 1, positionId);
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
        uint256 totalMargin,
        address driver
    ) external returns (uint256 payout) {
        address token = ISSListing(listingAddress).tokenA();
        uint256 availableMargin = ISSCrossDriver(driver).makerTokenMargin(makerAddress, token);
        uint256 marginToReturn = taxedMargin + (excessMargin > availableMargin ? availableMargin : excessMargin);
        require(availableMargin >= marginToReturn, "Insufficient margin");

        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        require(currentPrice > 0, "Invalid price");
        payout = (taxedMargin + marginToReturn + leverageAmount) / currentPrice - initialLoan;

        ISSCrossDriver(driver).updatePositionStatus(positionId, 1);

        if (payout > 0) {
            uint256 normalizedPayout = ICSDUtilityLibrary(driver).normalizeAmount(token, payout);
            queuePayoutOrder(listingAddress, makerAddress, normalizedPayout, uint8(0));
        }
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
        uint256 totalMargin,
        address driver
    ) external returns (uint256 payout) {
        address token = ISSListing(listingAddress).tokenB();
        uint256 availableMargin = ISSCrossDriver(driver).makerTokenMargin(makerAddress, token);
        uint256 marginToReturn = taxedMargin + (excessMargin > availableMargin ? availableMargin : excessMargin);
        require(availableMargin >= marginToReturn, "Insufficient margin");

        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        require(currentPrice > 0, "Invalid price");
        uint256 priceDiff = minPrice > currentPrice ? minPrice - currentPrice : 0;
        payout = priceDiff * initialMargin * leverage + marginToReturn * currentPrice;

        ISSCrossDriver(driver).updatePositionStatus(positionId, 1);

        if (payout > 0) {
            uint256 normalizedPayout = ICSDUtilityLibrary(driver).normalizeAmount(token, payout);
            queuePayoutOrder(listingAddress, makerAddress, normalizedPayout, uint8(1));
        }
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

        ISSCrossDriver(driver).updatePositionStatus(positionId, 2);

        if (marginToReturn > 0) {
            uint256 normalizedMargin = ICSDUtilityLibrary(driver).normalizeAmount(token, marginToReturn);
            queuePayoutOrder(listingAddress, makerAddress, normalizedMargin, positionType);
        }
    }

    // Force execution
    function forceExecution(
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount) {
        resultCount = 0;
        uint256 maxActions = 50;
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);

        for (uint8 positionType = 0; positionType <= 1 && resultCount < maxActions; positionType++) {
            uint256[] memory pending = ISSCrossDriver(driver).pendingPositions(listingAddress, positionType);
            for (uint256 i = 0; i < pending.length && resultCount < maxActions; i++) {
                uint256 positionId = pending[i];
                PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positionId);
                if (pos.status1 == false && pos.status2 == 0) {
                    if (currentPrice >= pos.minPrice && currentPrice <= pos.maxPrice) {
                        pos.status1 = true;
                        ISSCrossDriver(driver).setPositionDetails(positionId, pos);
                        resultCount++;
                    }
                }
            }
        }

        for (uint8 positionType = 0; positionType <= 1 && resultCount < maxActions; positionType++) {
            uint256[] memory active = ISSCrossDriver(driver).positionsByType(positionType);
            for (uint256 i = 0; i < active.length && resultCount < maxActions; i++) {
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
                        uint256 totalMargin = ISSCrossDriver(driver).makerTokenMargin(
                            pos.makerAddress,
                            pos.positionType == 0 ? ISSListing(pos.listingAddress).tokenA() : ISSListing(pos.listingAddress).tokenB()
                        );

                        if (pos.positionType == 0) {
                            closeLongPosition(
                                positionId,
                                pos.listingAddress,
                                pos.makerAddress,
                                pos.taxedMargin,
                                pos.excessMargin,
                                pos.leverageAmount,
                                pos.initialLoan,
                                totalMargin,
                                driver
                            );
                        } else {
                            closeShortPosition(
                                positionId,
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
                        }
                        resultCount++;
                    }
                }
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

    // Batch operations
    function closeAllShort(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).positionsByType(1);
        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status2 == 0 && pos.positionType == 1) {
                uint256 totalMargin = ISSCrossDriver(driver).makerTokenMargin(pos.makerAddress, ISSListing(pos.listingAddress).tokenB());
                closeShortPosition(
                    positions[i],
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
                count++;
            }
        }
    }

    function cancelAllShort(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).pendingPositions(address(0), 1);
        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status1 == false && pos.status2 == 0 && pos.positionType == 1) {
                cancelPosition(
                    positions[i],
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

    function closeAllLongs(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).positionsByType(0);
        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status2 == 0 && pos.positionType == 0) {
                uint256 totalMargin = ISSCrossDriver(driver).makerTokenMargin(pos.makerAddress, ISSListing(pos.listingAddress).tokenA());
                closeLongPosition(
                    positions[i],
                    pos.listingAddress,
                    pos.makerAddress,
                    pos.taxedMargin,
                    pos.excessMargin,
                    pos.leverageAmount,
                    pos.initialLoan,
                    totalMargin,
                    driver
                );
                count++;
            }
        }
    }

    function cancelAllLong(address user, address driver) external returns (uint256 count) {
        count = 0;
        uint16 maxIteration = 100;
        uint256[] memory positions = ISSCrossDriver(driver).pendingPositions(address(0), 0);
        for (uint256 i = 0; i < positions.length && count < maxIteration; i++) {
            PositionDetails memory pos = ISSCrossDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status1 == false && pos.status2 == 0 && pos.positionType == 0) {
                cancelPosition(
                    positions[i],
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
}