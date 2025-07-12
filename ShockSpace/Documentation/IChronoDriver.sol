// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.4
// Change Log:
// - 2025-07-12: Updated to v0.0.4
//   - Removed outdated mappings: chronoDrivesByAddress, chronoDriveID, isChronoDrive
//   - Removed nextChronoDriveId view function
//   - Aligned interface with ChronoDriver.sol v0.0.14
//   - Preserved all relevant functionality from v0.0.3
// - Previous (v0.0.3):
//   - Added totalDrives, viewDrive, getUserDrives, getActiveDrivesCount, getTotalActiveDrives
//   - Removed totalChronoDrives view function
// - Previous (v0.0.2):
//   - Updated settleParams to positionType-isCross
//   - Added isCross to ChronoDriveParams struct
// - Previous (v0.0.1):
//   - Initial creation of IChronoDriver interface

// Interface for ChronoDriver contract
interface IChronoDriver {
    // Struct to hold stalled chronoDrive data
    struct StalledChronoDrive {
        address listingAddress; // Address of the listing contract
        uint8 positionType; // 0 for long (tokenA), 1 for short (tokenB)
        uint256 initialMargin; // Initial margin amount for the position
        uint256 excessMargin; // Additional margin for the position
        uint8 leverage; // Leverage multiplier for the position
        uint256 pricePercent; // Percentage for price range calculation (max 100%)
        uint256 timestamp; // Execution timestamp for the drive
        address maker; // Address initiating the drive
        address token; // Token used for the position (tokenA for long, tokenB for short)
        uint256 principalAmount; // Principal amount after fee deduction
        uint256 feeAmount; // Fee amount (0.05% of normalized principal)
        uint8 driveStatus; // 1 = active, 2 = completed/canceled
        uint256 positionId; // Position ID returned by driver contract
    }

    // Struct to hold chronoDrive parameters
    struct ChronoDriveParams {
        address listingAddress; // Address of the listing contract
        uint8 positionType; // 0 for long (tokenA), 1 for short (tokenB)
        uint256 initialMargin; // Initial margin amount for the position
        uint256 excessMargin; // Additional margin for the position
        uint8 leverage; // Leverage multiplier for the position
        uint256 pricePercent; // Percentage for price range calculation (max 100%)
        uint256 timestamp; // Execution timestamp for the drive
        address maker; // Address initiating the drive
        address token; // Token used for the position (tokenA for long, tokenB for short)
        uint256 rawPrincipal; // Raw principal amount before normalization
        uint256 normalizedPrincipal; // Principal amount normalized to 18 decimals
        uint256 feeAmount; // Fee amount (0.05% of normalized principal)
        uint256 principal; // Principal amount after fee deduction
        uint256 rawPrincipalAfterFee; // Denormalized principal after fee
        uint256 maxEntryPrice; // Maximum entry price for the position
        uint256 minEntryPrice; // Minimum entry price for the position
        uint256 stopLossPrice; // Stop-loss price for the position
        uint256 takeProfitPrice; // Take-profit price for the position
        uint8 driveStatus; // 1 = active, 2 = completed/canceled
        uint256 driveId; // Unique ID for the drive
        bool isCross; // True for CrossDriver, false for IsolatedDriver
    }

    // State variables (via view functions)
    function crossDriverAddressView() external view returns (address); // Returns ISSCrossDriver contract address
    function isolatedDriverAddressView() external view returns (address); // Returns ISSIsolatedDriver contract address
    function totalDrives() external view returns (uint256); // Returns total count of chrono drives
    function viewDrive(uint256 driveId) external view returns (StalledChronoDrive memory); // Returns drive details for a drive ID
    function getUserDrives(address user) external view returns (uint256[] memory); // Returns array of drive IDs for a user
    function getActiveDrivesCount(address user) external view returns (uint256); // Returns count of active drives for a user
    function getTotalActiveDrives() external view returns (uint256); // Returns count of all active drives globally

    // External functions

    // Sets ISSCrossDriver contract address
    // @param _crossDriverAddress Address of the ISSCrossDriver contract
    function setCrossDriverAddress(address _crossDriverAddress) external;

    // Sets ISSIsolatedDriver contract address
    // @param _isolatedDriverAddress Address of the ISSIsolatedDriver contract
    function setIsolatedDriverAddress(address _isolatedDriverAddress) external;

    // Initiates a time-based position via ISSCrossDriver or ISSIsolatedDriver
    // @param pathParams Hyphen-delimited string: listing-impactPercent
    //   - listing: Address of the listing contract (e.g., 0x123...456)
    //   - impactPercent: Percentage for price range calculation (e.g., 5 for 5%)
    // @param settleParams Hyphen-delimited string: positionType-isCross
    //   - positionType: 0 for long (tokenA), 1 for short (tokenB)
    //   - isCross: 1 for CrossDriver, 0 for IsolatedDriver
    // @param positionData Hyphen-delimited string: initialMargin-excessMargin-leverage
    //   - initialMargin: Initial margin amount for the position
    //   - excessMargin: Additional margin for the position
    //   - leverage: Leverage multiplier for the position
    // @param executionData Hyphen-delimited string: pricePercent-timestamp-maker
    //   - pricePercent: Percentage for price range calculation (max 100%)
    //   - timestamp: Unix timestamp for drive execution
    //   - maker: Address initiating the drive (0x0 for msg.sender)
    // @return Drive ID if pending, or position ID if executed immediately
    function chronoDrive(
        string memory pathParams,
        string memory settleParams,
        string memory positionData,
        string memory executionData
    ) external payable returns (uint256);

    // Cancels a pending chronoDrive
    // @param driveId ID of the drive to cancel
    function cancelChronoDrive(uint256 driveId) external;

    // Continues maker's pending chronoDrives
    // @param maxIterations Maximum number of drives to process
    function continueChronoDrive(uint256 maxIterations) external;

    // Executes pending chronoDrives globally
    // @param maxIterations Maximum number of drives to process
    function executeChronoDrive(uint256 maxIterations) external;

    // Returns contract balance for a token or native currency
    // @param token Token address (address(0) for native currency)
    // @return Balance amount
    function getContractBalance(address token) external view returns (uint256);
}