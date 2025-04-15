// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.2:
// - Library for SSIsolatedDriver, handles position logic.
// - Implements corrected liquidation price formulas:
//   - Long: (excessMargin + taxedMargin) / leverageAmount = marginRatio, entryPrice - marginRatio = liquidationPrice.
//   - Short: (excessMargin + taxedMargin) / leverageAmount = marginRatio, entryPrice + marginRatio = liquidationPrice.
// - Implements corrected payout formulas:
//   - Long: ((taxedMargin + excessMargin + leverageAmount) * currentPrice) - initialLoan, 0 if negative.
//   - Short: (entryPrice - exitPrice) * initialMargin * leverage + (taxedMargin + excessMargin) / currentPrice.
// - Size: ~350 lines, optimized for gas efficiency.
// - No direct storage; updates via SSIsolatedDriver.

import "imports/SafeERC20.sol";
import "imports/Strings.sol";
import "imports/IERC20Metadata.sol";

contract SSPositionLibrary {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Structs (mirrored from SSIsolatedDriver)
    struct PositionDetails {
        address makerAddress;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin; // Included in liquidation and payout calculations
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
        uint8 payoutType;
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

    interface ISSUtilityLibrary {
        function normalizeAmount(address token, uint256 amount) external view returns (uint256);
        function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice);
        function parseUint(string memory str) external pure returns (uint256);
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
        // Validate inputs
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        // Parse entry price
        (uint256 minPrice, uint256 maxPrice) = ISSUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);

        // Calculate taxed margin (assume 1% fee per leverage)
        uint256 taxedMargin = initialMargin - ((leverage - 1) * initialMargin / 100);

        // Calculate leverage amount
        uint256 leverageAmount = initialMargin * leverage;

        // Calculate liquidation price
        // Formula: (excessMargin + taxedMargin) / leverageAmount = marginRatio
        // liquidationPrice = entryPrice - marginRatio
        uint256 marginRatio = (excessMargin + taxedMargin) / leverageAmount;
        uint256 liquidationPrice = minPrice > marginRatio ? minPrice - marginRatio : 0; // Ensure non-negative

        // Create position
        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));
        PositionDetails memory pos = PositionDetails({
            makerAddress: msg.sender,
            minPrice: minPrice,
            maxPrice: maxPrice,
            initialMargin: initialMargin,
            taxedMargin: taxedMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            leverageAmount: leverageAmount,
            initialLoan: leverageAmount * minPrice / DECIMAL_PRECISION,
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

        // Store via driver
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "setPositionDetails(uint256,(address,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint8,bool,uint8,uint256,uint256,uint256,address))",
                positionId,
                pos
            )
        );
        require(success, "Storage failed");

        // Update positionsByType and userPositions
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionIndexes(address,uint8,uint256)",
                msg.sender,
                0,
                positionId
            )
        );
        require(success, "Index update failed");

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
        // Validate inputs
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        // Parse entry price
        (uint256 minPrice, uint256 maxPrice) = ISSUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);

        // Calculate taxed margin
        uint256 taxedMargin = initialMargin - ((leverage - 1) * initialMargin / 100);

        // Calculate leverage amount
        uint256 leverageAmount = initialMargin * leverage;

        // Calculate liquidation price
        // Formula: (excessMargin + taxedMargin) / leverageAmount = marginRatio
        // liquidationPrice = entryPrice + marginRatio
        uint256 marginRatio = (excessMargin + taxedMargin) / leverageAmount;
        uint256 liquidationPrice = minPrice + marginRatio;

        // Create position
        positionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, positionId)));
        PositionDetails memory pos = PositionDetails({
            makerAddress: msg.sender,
            minPrice: minPrice,
            maxPrice: maxPrice,
            initialMargin: initialMargin,
            taxedMargin: taxedMargin,
            excessMargin: excessMargin,
            leverage: leverage,
            leverageAmount: leverageAmount,
            initialLoan: leverageAmount * minPrice / DECIMAL_PRECISION,
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

        // Store via driver
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "setPositionDetails(uint256,(address,uint256,uint256,uint256,uint256,uint8,uint256,uint256,uint256,uint256,uint256,uint8,bool,uint8,uint256,uint256,uint256,address))",
                positionId,
                pos
            )
        );
        require(success, "Storage failed");

        // Update positionsByType and userPositions
        (success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionIndexes(address,uint8,uint256)",
                msg.sender,
                1,
                positionId
            )
        );
        require(success, "Index update failed");

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
        // Get current price
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);

        // Calculate payout
        // Formula: ((taxedMargin + excessMargin + leverageAmount) * currentPrice) - initialLoan
        // Pays 0 if payout <= 0
        uint256 totalValue = (taxedMargin + excessMargin + leverageAmount) * currentPrice;
        payout = totalValue > initialLoan ? (totalValue - initialLoan) / DECIMAL_PRECISION : 0;

        // Update status
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 1
            )
        );
        require(success, "Status update failed");

        // Trigger payout via ssUpdate
        if (payout > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: makerAddress,
                required: payout,
                payoutType: 0
            });
            ISSListing(listingAddress).ssUpdate(listingAddress, updates);
        }

        // Clear leverage amount (not stored, implicit via status)
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
        // Get current price (exit price)
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);

        // Calculate payout
        // Formula: (entryPrice - exitPrice) * initialMargin * leverage + (taxedMargin + excessMargin) / currentPrice
        // Uses tokenB (yBalance/yLiquid context)
        uint256 priceDiff = minPrice > currentPrice ? minPrice - currentPrice : 0;
        uint256 profit = (priceDiff * initialMargin * leverage) / DECIMAL_PRECISION;
        uint256 marginReturn = currentPrice > 0 ? (taxedMargin + excessMargin) / (currentPrice / DECIMAL_PRECISION) : 0;
        payout = profit + marginReturn;

        // Update status
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 1
            )
        );
        require(success, "Status update failed");

        // Trigger payout via ssUpdate
        if (payout > 0) {
            PayoutUpdate[] memory updates = new PayoutUpdate[](1);
            updates[0] = PayoutUpdate({
                recipient: makerAddress,
                required: payout,
                payoutType: 1
            });
            ISSListing(listingAddress).ssUpdate(listingAddress, updates);
        }

        // Clear leverage amount (implicit via status)
    }

    // Cancel position
    function cancelPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint8 positionType,
        address driver
    ) external {
        // Refund margin
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        if (token == address(0)) {
            payable(makerAddress).transfer(taxedMargin);
        } else {
            IERC20(token).safeTransfer(makerAddress, taxedMargin);
        }

        // Update status
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 2
            )
        );
        require(success, "Status update failed");
    }

    // Force execution
    function forceExecution(
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount) {
        resultCount = 0;
        // Mock: iterate pendingPositions and positionsByType
        // Check SL/TP/liquidation, up to 50 actions
        // Update via driver
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
        // Update excessMargin
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updateExcessMargin(uint256,uint256)", positionId, normalizedAmount
            )
        );
        require(success, "Margin update failed");
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
        // Mock: iterate userPositions
    }

    function cancelAllShort(address user, address driver) external returns (uint256 count) {
        count = 0;
        // Mock: iterate userPositions
    }

    function closeAllLongs(address user, address driver) external returns (uint256 count) {
        count = 0;
        // Mock: iterate userPositions
    }

    function cancelAllLong(address user, address driver) external returns (uint256 count) {
        count = 0;
        // Mock: iterate userPositions
    }
}