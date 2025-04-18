// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.4:
// - Updated closeLongPosition formula: ((taxedMargin + excessMargin + leverageAmount) / currentPrice) - initialLoan.
// - Updated closeShortPosition formula: (entryPrice - exitPrice) * initialMargin * leverage + (taxedMargin + excessMargin) * currentPrice.
// - Formulas commented in code.
// - Fully implemented closeLongPosition, closeShortPosition with denormalization and payouts via ssUpdate.
// - Fully implemented cancelAll* to cancel pending positions with payouts.
// - Enhanced forceExecution to handle order ranges (minPrice, maxPrice).
// - Updated cancelPosition to use payout orders via ssUpdate, not direct transfers.
// - Added tax-on-transfer checks in addExcessMargin.
// - Updated historical interest for long/short creation, close, cancel.
// - Clarified status1 (pending/executable), status2 (open/closed/cancelled) usage.
// - Local ISSListing interface, interface before contract declaration, libraries as separate contracts.

import "./imports/SafeERC20.sol";
import "./imports/Strings.sol";
import "./imports/IERC20Metadata.sol";

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
        function positionDetails(uint256 positionId) external view returns (PositionDetails memory);
        function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);
        function positionsByType(uint8 positionType) external view returns (uint256[] memory);
        function historicalInterestHeight() external view returns (uint256);
    }

contract SSPositionLibrary {
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
        uint256 excessMargin;
        uint8 leverage;
        uint256 leverageAmount;
        uint256 initialLoan;
        uint256 liquidationPrice;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 positionType; // 0: Long, 1: Short
        bool status1; // false: pending, true: executable
        uint8 status2; // 0: open, 1: closed, 2: cancelled
        uint256 closePrice;
        uint256 priceAtEntry;
        uint256 positionId;
        address listingAddress;
    }

    struct PayoutUpdate {
        address recipient;
        uint256 required;
        uint8 payoutType; // 0: Long, 1: Short
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
        address driver
    ) external returns (uint256 positionId) {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        (uint256 minPrice, uint256 maxPrice) = ISSUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        require(minPrice > 0, "Invalid entry price");
        uint256 taxedMargin = initialMargin - ((leverage - 1) * initialMargin / 100);
        uint256 leverageAmount = initialMargin * leverage;

        // Calculate liquidation price
        require(leverageAmount > 0, "Invalid leverage amount");
        uint256 marginRatio = (excessMargin + taxedMargin) / leverageAmount;
        uint256 liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0;

        // Calculate initial loan
        uint256 initialLoan = leverageAmount / (minPrice / DECIMAL_PRECISION);

        // Create position
        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));
        PositionDetails memory pos = PositionDetails({
            makerAddress: msg.sender,
            minPrice: minPrice,
            maxPrice: maxPrice,
            initialMargin: normalizedInitialMargin,
            taxedMargin: ISSUtilityLibrary(driver).normalizeAmount(token0, taxedMargin),
            excessMargin: normalizedExcessMargin,
            leverage: leverage,
            leverageAmount: leverageAmount,
            initialLoan: initialLoan,
            liquidationPrice: liquidationPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 0,
            status1: false, // Pending
            status2: 0, // Open
            closePrice: 0,
            priceAtEntry: minPrice,
            positionId: positionId,
            listingAddress: listingAddress
        });

        // Store via driver
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "setPositionDetails(uint256,(address,uint256,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint8,bool,uint8,uint256,uint256,uint256,address))",
                positionId,
                pos
            )
        );
        require(success, "Storage failed");

        // Update indexes
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionIndexes(address,uint8,uint256)",
                msg.sender,
                0,
                positionId
            )
        );
        require(success, "Index update failed");

        // Update historical interest
        uint256 io = pos.taxedMargin + pos.excessMargin;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updateHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                io,
                0
            )
        );
        require(success, "Interest update failed");

        return positionId;
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
        address driver
    ) external returns (uint256 positionId) {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        (uint256 minPrice, uint256 maxPrice) = ISSUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);
        require(minPrice > 0, "Invalid entry price");
        uint256 taxedMargin = initialMargin - ((leverage - 1) * initialMargin / 100);
        uint256 leverageAmount = initialMargin * leverage;

        // Calculate liquidation price
        require(leverageAmount > 0, "Invalid leverage amount");
        uint256 marginRatio = (excessMargin + taxedMargin) / leverageAmount;
        uint256 liquidationPrice = minPrice + marginRatio;

        // Calculate initial loan
        uint256 initialLoan = leverageAmount * minPrice;

        // Create position
        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));
        PositionDetails memory pos = PositionDetails({
            makerAddress: msg.sender,
            minPrice: minPrice,
            maxPrice: maxPrice,
            initialMargin: normalizedInitialMargin,
            taxedMargin: ISSUtilityLibrary(driver).normalizeAmount(token1, taxedMargin),
            excessMargin: normalizedExcessMargin,
            leverage: leverage,
            leverageAmount: leverageAmount,
            initialLoan: initialLoan,
            liquidationPrice: liquidationPrice,
            stopLossPrice: stopLossPrice,
            takeProfitPrice: takeProfitPrice,
            positionType: 1,
            status1: false, // Pending
            status2: 0, // Open
            closePrice: 0,
            priceAtEntry: minPrice,
            positionId: positionId,
            listingAddress: listingAddress
        });

        // Store via driver
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "setPositionDetails(uint256,(address,uint256,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint8,bool,uint8,uint256,uint256,uint256,address))",
                positionId,
                pos
            )
        );
        require(success, "Storage failed");

        // Update indexes
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionIndexes(address,uint8,uint256)",
                msg.sender,
                1,
                positionId
            )
        );
        require(success, "Index update failed");

        // Update historical interest
        uint256 io = pos.taxedMargin + pos.excessMargin;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updateHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                0,
                io
            )
        );
        require(success, "Interest update failed");

        return positionId;
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
        require(ISSIsolatedDriver(driver).positionDetails(positionId).status2 == 0, "Position not open"); // Only open positions
        require(ISSIsolatedDriver(driver).positionDetails(positionId).status1 == true, "Position not executable"); // Only executable

        uint256 currentPrice = ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
        // Formula: ((taxedMargin + excessMargin + leverageAmount) / currentPrice) - initialLoan
        uint256 totalValue = taxedMargin + excessMargin + leverageAmount;
        payout = currentPrice > 0 && totalValue > initialLoan ? (totalValue / currentPrice) - initialLoan : 0;

        // Denormalize payout (tokenB)
        uint8 decimalsB = ISSListing(listingAddress).decimalsB();
        if (decimalsB != 18) {
            if (decimalsB < 18) {
                payout = payout / (10 ** (uint256(18) - uint256(decimalsB)));
            } else {
                payout = payout * (10 ** (uint256(decimalsB) - uint256(18)));
            }
        }

        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 1 // Closed
            )
        );
        require(success, "Status update failed");

        if (payout > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: makerAddress,
                required: payout,
                payoutType: 0 // Long
            });
            ISSListing(listingAddress).ssUpdate(address(this), updates);
        }

        // Reduce historical interest
        uint256 io = taxedMargin + excessMargin;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "reduceHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                io,
                0
            )
        );
        require(success, "Interest reduction failed");
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
        require(ISSIsolatedDriver(driver).positionDetails(positionId).status2 == 0, "Position not open"); // Only open positions
        require(ISSIsolatedDriver(driver).positionDetails(positionId).status1 == true, "Position not executable"); // Only executable

        uint256 currentPrice = ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
        // Formula: (entryPrice - exitPrice) * initialMargin * leverage + (taxedMargin + excessMargin) * currentPrice
        uint256 priceDiff = minPrice > currentPrice ? minPrice - currentPrice : 0;
        uint256 profit = (priceDiff * initialMargin * leverage);
        uint256 marginReturn = (taxedMargin + excessMargin) * currentPrice;
        payout = profit + marginReturn;

        // Denormalize payout (tokenA)
        uint8 decimalsA = ISSListing(listingAddress).decimalsA();
        if (decimalsA != 18) {
            if (decimalsA < 18) {
                payout = payout / (10 ** (uint256(18) - uint256(decimalsA)));
            } else {
                payout = payout * (10 ** (uint256(decimalsA) - uint256(18)));
            }
        }

        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 1 // Closed
            )
        );
        require(success, "Status update failed");

        if (payout > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: makerAddress,
                required: payout,
                payoutType: 1 // Short
            });
            ISSListing(listingAddress).ssUpdate(address(this), updates);
        }

        // Reduce historical interest
        uint256 io = taxedMargin + excessMargin;
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "reduceHistoricalInterest(uint256,uint256,uint256)",
                ISSIsolatedDriver(driver).historicalInterestHeight(),
                0,
                io
            )
        );
        require(success, "Interest reduction failed");
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
        require(ISSIsolatedDriver(driver).positionDetails(positionId).status1 == false, "Position executable"); // Only pending
        require(ISSIsolatedDriver(driver).positionDetails(positionId).status2 == 0, "Position not open"); // Only open

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

    // Force execution
    function forceExecution(
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount) {
        resultCount = 0;
        uint256 maxActions = 100;
        uint256 currentPrice = ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));

        // Process pending positions (status1 = false)
        for (uint8 positionType = 0; positionType <= 1 && resultCount < maxActions; positionType++) {
            uint256[] memory pending = ISSIsolatedDriver(driver).pendingPositions(listingAddress, positionType);
            for (uint256 i = 0; i < pending.length && resultCount < maxActions; i++) {
                uint256 positionId = pending[i];
                PositionDetails memory pos = ISSIsolatedDriver(driver).positionDetails(positionId);
                if (pos.status1 == false && pos.status2 == 0) {
                    // Check entry price range
                    if (currentPrice >= pos.minPrice && currentPrice <= pos.maxPrice) {
                        (bool success, ) = driver.call(
                            abi.encodeWithSignature(
                                "updatePositionStatus(uint256,uint8)", positionId, 0
                            )
                        );
                        if (success) {
                            pos.status1 = true;
                            (success, ) = driver.call(
                                abi.encodeWithSignature(
                                    "setPositionDetails(uint256,(address,uint256,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint8,bool,uint8,uint256,uint256,uint256,address))",
                                    positionId,
                                    pos
                                )
                            );
                            if (success) resultCount++;
                        }
                    }
                }
            }
        }

        // Process active positions (status1 = true, status2 = 0)
        for (uint8 positionType = 0; positionType <= 1 && resultCount < maxActions; positionType++) {
            uint256[] memory active = ISSIsolatedDriver(driver).positionsByType(positionType);
            for (uint256 i = 0; i < active.length && resultCount < maxActions; i++) {
                uint256 positionId = active[i];
                PositionDetails memory pos = ISSIsolatedDriver(driver).positionDetails(positionId);
                if (pos.status1 == true && pos.status2 == 0 && pos.listingAddress == listingAddress) {
                    bool shouldClose = false;
                    if (pos.positionType == 0) { // Long
                        if (pos.stopLossPrice > 0 && currentPrice <= pos.stopLossPrice) shouldClose = true;
                        else if (pos.takeProfitPrice > 0 && currentPrice >= pos.takeProfitPrice) shouldClose = true;
                        else if (currentPrice <= pos.liquidationPrice) shouldClose = true;
                    } else { // Short
                        if (pos.stopLossPrice > 0 && currentPrice >= pos.stopLossPrice) shouldClose = true;
                        else if (pos.takeProfitPrice > 0 && currentPrice <= pos.takeProfitPrice) shouldClose = true;
                        else if (currentPrice >= pos.liquidationPrice) shouldClose = true;
                    }

                    if (shouldClose) {
                        if (pos.positionType == 0) {
                            closeLongPosition(
                                positionId,
                                pos.listingAddress,
                                pos.makerAddress,
                                pos.taxedMargin,
                                pos.excessMargin,
                                pos.leverageAmount,
                                pos.initialLoan,
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
                                driver
                            );
                        }
                        resultCount++;
                    }
                }
            }
        }

        return resultCount;
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
            PositionDetails memory pos = ISSIsolatedDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status2 == 0 && pos.status1 == true) {
                closeShortPosition(
                    positions[i],
                    pos.listingAddress,
                    pos.makerAddress,
                    pos.minPrice,
                    pos.initialMargin,
                    pos.leverage,
                    pos.taxedMargin,
                    pos.excessMargin,
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
            PositionDetails memory pos = ISSIsolatedDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status1 == false && pos.status2 == 0) {
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
        uint256[] memory positions = ISSIsolatedDriver(driver).positionsByType(0);
        for (uint256 i = 0; i < positions.length && count < 100; i++) {
            PositionDetails memory pos = ISSIsolatedDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status2 == 0 && pos.status1 == true) {
                closeLongPosition(
                    positions[i],
                    pos.listingAddress,
                    pos.makerAddress,
                    pos.taxedMargin,
                    pos.excessMargin,
                    pos.leverageAmount,
                    pos.initialLoan,
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
            PositionDetails memory pos = ISSIsolatedDriver(driver).positionDetails(positions[i]);
            if (pos.makerAddress == user && pos.status1 == false && pos.status2 == 0) {
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

    // Storage functions
    function setPositionDetails(uint256 positionId, PositionDetails memory pos) external {
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature(
                "setPositionDetails(uint256,(address,uint256,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint8,bool,uint8,uint256,uint256,uint256,address))",
                positionId,
                pos
            )
        );
        require(success, "Storage failed");
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