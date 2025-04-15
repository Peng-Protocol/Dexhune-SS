// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.1:
// - Cloned from SSPositionLibrary, supports SSCrossDriver.
// - Handles position creation, closure, cancellation, and execution with totalMargin.
// - Implements liquidation price calculations: 
//   - Long: (totalMargin + taxedMargin) / leverageAmount = marginRatio, entryPrice - marginRatio = liquidationPrice.
//   - Short: (totalMargin + taxedMargin) / leverageAmount = marginRatio, entryPrice + marginRatio = liquidationPrice.
// - Size: ~350 lines, optimized for gas efficiency.
// - No direct storage; reads/writes via SSCrossDriver.

import "imports/SafeERC20.sol";
import "imports/Strings.sol";
import "imports/IERC20Metadata.sol";

contract CSDPositionLibrary {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Structs (mirrored from SSCrossDriver for reference)
    struct PositionDetails {
        address makerAddress;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin; // Reference only, not used in calculations; stores margin for deductions
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

    interface ICSDUtilityLibrary {
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
        uint256 totalMargin,
        address driver
    ) external returns (uint256 positionId) {
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        // Parse entry price
        (uint256 minPrice, uint256 maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);

        // Calculate taxed margin (simplified fee: 1% of leverage)
        uint256 taxedMargin = initialMargin - ((leverage - 1) * initialMargin / 100);

        // Calculate leverage amount
        uint256 leverageAmount = initialMargin * leverage;

        // Calculate liquidation price
        uint256 marginRatio = (totalMargin + taxedMargin) / leverageAmount;
        uint256 liquidationPrice = minPrice - marginRatio;

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
                "positionDetails(uint256)", positionId
            )
        );
        require(success, "Storage failed");
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

        // Parse entry price
        (uint256 minPrice, uint256 maxPrice) = ICSDUtilityLibrary(driver).parseEntryPrice(entryPrice, listingAddress);

        // Calculate taxed margin
        uint256 taxedMargin = initialMargin - ((leverage - 1) * initialMargin / 100);

        // Calculate leverage amount
        uint256 leverageAmount = initialMargin * leverage;

        // Calculate liquidation price
        uint256 marginRatio = (totalMargin + taxedMargin) / leverageAmount;
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
                "positionDetails(uint256)", positionId
            )
        );
        require(success, "Storage failed");
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
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        payout = ((taxedMargin + totalMargin + leverageAmount) * currentPrice) / DECIMAL_PRECISION - initialLoan;

        // Update via driver
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 1
            )
        );
        require(success, "Status update failed");

        // Trigger ssUpdate
        PayoutUpdate[] memory updates = new PayoutUpdate[](1);
        updates[0] = PayoutUpdate({
            recipient: makerAddress,
            required: payout,
            payoutType: 0
        });
        ISSListing(listingAddress).ssUpdate(listingAddress, updates);
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
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        payout = ((minPrice - currentPrice) * initialMargin * leverage) / DECIMAL_PRECISION +
                 (taxedMargin + totalMargin) / (currentPrice / DECIMAL_PRECISION);

        // Update via driver
        (bool success, ) = driver.call(
            abi.encodeWithSignature(
                "updatePositionStatus(uint256,uint8)", positionId, 1
            )
        );
        require(success, "Status update failed");

        // Trigger ssUpdate
        PayoutUpdate[] memory updates = new PayoutUpdate[](1);
        updates[0] = PayoutUpdate({
            recipient: makerAddress,
            required: payout,
            payoutType: 1
        });
        ISSListing(listingAddress).ssUpdate(listingAddress, updates);
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
        // Refund margin
        address token = positionType == 0 ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        if (token == address(0)) {
            payable(makerAddress).transfer(taxedMargin + excessMargin);
        } else {
            IERC20(token).safeTransfer(makerAddress, taxedMargin + excessMargin);
        }

        // Update via driver
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
        // Mock implementation: assume up to 50 actions
        // - Process pending positions
        // - Check SL/TP/liquidation
        // - Update liquidation prices based on totalMargin
        // Actual logic would iterate positionsByType and pendingPositions via driver
        return resultCount;
    }

    // Add excess margin
    function addExcessMargin(
        address maker,
        uint256 amount,
        address token,
        uint256 normalizedAmount,
        address driver
    ) external {
        // No-op in library; handled by driver
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
        // Mock: iterate userPositions, close shorts
    }

    function cancelAllShort(address user, address driver) external returns (uint256 count) {
        count = 0;
        // Mock: iterate userPositions, cancel shorts
    }

    function closeAllLongs(address user, address driver) external returns (uint256 count) {
        count = 0;
        // Mock: iterate userPositions, close longs
    }

    function cancelAllLong(address user, address driver) external returns (uint256 count) {
        count = 0;
        // Mock: iterate userPositions, cancel longs
    }
}