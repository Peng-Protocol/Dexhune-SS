# ChronoDriver Contract Documentation

## Overview
The `ChronoDriver` contract, implemented in Solidity (^0.8.2), facilitates time-based position execution via `ISSCrossDriver` or `ISSIsolatedDriver`, supporting long and short positions with a 0.05% fee in the input token paid to the caller of `chronoDrive`, `continueChronoDrive`, or `executeChronoDrive`. It uses `SafeERC20` for secure token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control, with an internal call tree to minimize stack usage and robust decimal handling for native and ERC20 tokens. State variables are hidden, accessed via view functions, and inputs are parsed from hyphen-delimited strings for efficiency, with pending drives managed through mappings and arrays, allowing cancellation or delayed execution.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.14 (last updated 2025-07-12)

**Compatible Contracts:**
- `ISSCrossDriver` v??.??.??
- `ISSIsolatedDriver` v0.0.17
- `ISSListingTemplate` v0.0.10

## Clarifications
- **Integration with Drivers**: The contract calls `drive` on `ISSCrossDriver` or `ISSIsolatedDriver` (set via `setCrossDriverAddress` or `setIsolatedDriverAddress`), selecting the driver based on the `isCross` parameter in `settleParams` (`true` for `crossDriverAddress`, `false` for `isolatedDriverAddress`), with most validation deferred to the driver contracts.
- **Driver Selection**: The `isCross` boolean in `settleParams` (format: `positionType-isCross`) explicitly determines whether `crossDriverAddress` or `isolatedDriverAddress` is used; at least one driver address must be non-zero for execution.
- **Pending Drive Management**: Drives with `timestamp > block.timestamp` are stored as `StalledChronoDrive` entries, trackable via `chronoDriveID`, `chronoDrivesByAddress`, and `totalChronoDrives`, and can be continued via `continueChronoDrive` (maker only) or `executeChronoDrive` (any address), or canceled via `cancelChronoDrive`.
- **Timestamp-Based Execution**: Drives execute immediately in `chronoDrive` if `timestamp <= block.timestamp`; otherwise, they are stored for later execution when `block.timestamp >= timestamp`.
- **Fee Handling**: A 0.05% fee is deducted in `_handleTokenTransfer`, stored in `ChronoDriveParams.feeAmount` or `StalledChronoDrive.feeAmount`, paid to `msg.sender` upon execution (`chronoDrive`, `continueChronoDrive`, `executeChronoDrive`) via `_processFeePayout`, or refunded to the maker upon cancellation (`cancelChronoDrive`).
- **Balance Checks**: The `_checkTransfer` function ensures token transfers (native or ERC20) by comparing pre/post balances, returning the actual transferred amount to prevent underflows or transfer failures.
- **Token Inference**: The input token is inferred from `listingAddress` and `positionType` using `ISSListingTemplate` (`tokenA` for long positions where `positionType = 0`, `tokenB` for short positions where `positionType = 1`), ensuring correct token handling without explicit input.
- **Decimal Handling**: Functions `_normalizeAmount`, `_denormalizeAmount`, and `_normalizePrice` handle token decimals (≤ 18) for consistent calculations across native and ERC20 tokens.
- **Cancellation Refunds**: `cancelChronoDrive` refunds the full `principalAmount + feeAmount` in the input token to the maker, updating mappings with pop-and-swap for gas efficiency.
- **isCross in Pending Drives**: In `continueChronoDrive` and `executeChronoDrive`, `isCross` is set to `true` for long positions (`positionType = 0`) by default, as `StalledChronoDrive` does not store `isCross`; users must ensure driver compatibility when initiating drives.

## State Variables
- **crossDriverAddress** (address, private): Stores the `ISSCrossDriver` contract address for position execution.
- **isolatedDriverAddress** (address, private): Stores the `ISSIsolatedDriver` contract address for position execution.
- **nextChronoDriveId** (uint256, private): Tracks the next drive ID for unique identification.
- **totalChronoDrives** (uint256[], private): Global list of drive IDs.
- **chronoDrivesByAddress** (mapping(address => uint256[]), private): Maps maker addresses to their drive IDs.
- **chronoDriveID** (mapping(uint256 => StalledChronoDrive), private): Stores drive details by drive ID.
- **isChronoDrive** (mapping(uint256 => bool), private): Flags time-based drives.

## Structs
- **StalledChronoDrive**: Tracks `listingAddress` (address, listing contract), `positionType` (uint8, 0 = long, 1 = short), `initialMargin` (uint256, position margin), `excessMargin` (uint256, additional margin), `leverage` (uint8, position leverage), `pricePercent` (uint256, price impact percent), `timestamp` (uint256, execution timestamp), `maker` (address, position initiator), `token` (address, input token), `principalAmount` (uint256, amount after fee), `feeAmount` (uint256, 0.05% fee), `driveStatus` (uint8, 1 = active, 2 = completed/canceled), `positionId` (uint256, ID from driver contract).
- **ChronoDriveParams**: Tracks `listingAddress` (address), `positionType` (uint8, 0 = long, 1 = short), `initialMargin` (uint256), `excessMargin` (uint256), `leverage` (uint8), `pricePercent` (uint256), `timestamp` (uint256), `maker` (address), `token` (address), `rawPrincipal` (uint256, input amount), `normalizedPrincipal` (uint256, normalized input), `feeAmount` (uint256), `principal` (uint256, amount after fee), `rawPrincipalAfterFee` (uint256, denormalized principal), `maxEntryPrice` (uint256), `minEntryPrice` (uint256), `stopLossPrice` (uint256), `takeProfitPrice` (uint256), `driveStatus` (uint8), `driveId` (uint256), `isCross` (bool, true for CrossDriver, false for IsolatedDriver).

## Formulas
- **Normalized Amount**:
  - **Formula**: `normalizedAmount = amount * DECIMAL_PRECISION / (10 ** decimals)` (for `decimals <= 18`).
  - **Used in**: `_normalizeAmount`, `_handleTokenTransfer`.
  - **Description**: Normalizes token amounts to 18 decimals for consistent calculations.
- **Denormalized Amount**:
  - **Formula**: `rawAmount = normalizedAmount * (10 ** decimals) / DECIMAL_PRECISION` (for `decimals <= 18`).
  - **Used in**: `_denormalizeAmount`, `_handleTokenTransfer`, `_executeDriverCall`, `_processFeePayout`, `cancelChronoDrive`.
  - **Description**: Converts normalized amounts to token-specific decimals.
- **Normalized Price**:
  - **Formula**: `normalizedPrice = price * DECIMAL_PRECISION / (10 ** decimals)` (for `decimals <= 18`).
  - **Used in**: `_normalizePrice`, `_computeEntryPrices`.
  - **Description**: Normalizes prices to 18 decimals for consistent calculations.
- **Fee Calculation**:
  - **Formula**: `feeAmount = (normalizedPrincipal * FEE_BASIS_POINTS) / 10000`, where `FEE_BASIS_POINTS = 5` (0.05%).
  - **Used in**: `_handleTokenTransfer`.
  - **Description**: Calculates the fee deducted from the input amount.
- **Price Calculations**:
  - **Formula** (for `currentPrice` from `ISSListingTemplate.listingPriceView`):
    - `priceDelta = currentPrice * pricePercent / 100`
    - `maxEntryPrice = currentPrice + priceDelta` (normalized)
    - `minEntryPrice = currentPrice - priceDelta` (normalized)
    - Long (`positionType = 0`): `stopLossPrice = currentPrice - priceDelta`, `takeProfitPrice = currentPrice + priceDelta` (normalized)
    - Short (`positionType = 1`): `stopLossPrice = currentPrice + priceDelta`, `takeProfitPrice = currentPrice - priceDelta` (normalized)
  - **Used in**: `_computeEntryPrices`.
  - **Description**: Computes entry and exit prices based on `pricePercent`.

## External Functions

### setCrossDriverAddress(address _crossDriverAddress)
- **Parameters**:
  - `_crossDriverAddress` (address): `ISSCrossDriver` contract address.
- **Returns**: None.
- **Behavior**: Sets the `crossDriverAddress` for position execution, emitting `CrossDriverSet`.
- **Internal Call Flow**: Validates `_crossDriverAddress != address(0)`, assigns to `crossDriverAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `crossDriverAddress`.
- **Restrictions**: Restricted to `onlyOwner`, reverts if `_crossDriverAddress` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### setIsolatedDriverAddress(address _isolatedDriverAddress)
- **Parameters**:
  - `_isolatedDriverAddress` (address): `ISSIsolatedDriver` contract address.
- **Returns**: None.
- **Behavior**: Sets the `isolatedDriverAddress` for position execution, emitting `IsolatedDriverSet`.
- **Internal Call Flow**: Validates `_isolatedDriverAddress != address(0)`, assigns to `isolatedDriverAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `isolatedDriverAddress`.
- **Restrictions**: Restricted to `onlyOwner`, reverts if `_isolatedDriverAddress` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### crossDriverAddressView()
- **Parameters**: None.
- **Returns**: `address` (CrossDriver address).
- **Behavior**: Returns the `crossDriverAddress`.
- **Internal Call Flow**: Direct access to `crossDriverAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `crossDriverAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### isolatedDriverAddressView()
- **Parameters**: None.
- **Returns**: `address` (IsolatedDriver address).
- **Behavior**: Returns the `isolatedDriverAddress`.
- **Internal Call Flow**: Direct access to `isolatedDriverAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `isolatedDriverAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### totalDrives()
- **Parameters**: None.
- **Returns**: `uint256` (total count of chrono drives).
- **Behavior**: Returns the total number of chrono drives in `totalChronoDrives`.
- **Internal Call Flow**: Accesses `totalChronoDrives.length`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `totalChronoDrives`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### viewDrive(uint256 driveId)
- **Parameters**:
  - `driveId` (uint256): Drive ID to query.
- **Returns**: `StalledChronoDrive` (drive details).
- **Behavior**: Returns the `StalledChronoDrive` struct for the specified `driveId`, reverting if the drive does not exist.
- **Internal Call Flow**: Accesses `chronoDriveID` and `isChronoDrive`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoDriveID`, `isChronoDrive`.
  - **Structs**: `StalledChronoDrive`.
- **Restrictions**: Reverts if `isChronoDrive[driveId]` is false.
- **Gas Usage Controls**: View function, single mapping access, minimal gas.

### getUserDrives(address user)
- **Parameters**:
  - `user` (address): User address to query.
- **Returns**: `uint256[]` (array of drive IDs).
- **Behavior**: Returns the array of drive IDs associated with the specified `user` from `chronoDrivesByAddress`.
- **Internal Call Flow**: Accesses `chronoDrivesByAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoDrivesByAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, array access, gas depends on array size.

### getActiveDrivesCount(address user)
- **Parameters**:
  - `user` (address): User address to query.
- **Returns**: `uint256` (count of active drives).
- **Behavior**: Returns the number of active drives (`driveStatus == 1`) for the specified `user`.
- **Internal Call Flow**: Iterates `chronoDrivesByAddress[user]` and checks `chronoDriveID` for `driveStatus == 1`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoDrivesByAddress`, `chronoDriveID`.
  - **Structs**: `StalledChronoDrive`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, gas depends on number of user drives.

### getTotalActiveDrives()
- **Parameters**: None.
- **Returns**: `uint256` (count of all active drives).
- **Behavior**: Returns the total number of active drives (`driveStatus == 1`) across all users.
- **Internal Call Flow**: Iterates `totalChronoDrives` and checks `chronoDriveID` for `driveStatus == 1`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `totalChronoDrives`, `chronoDriveID`.
  - **Structs**: `StalledChronoDrive`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, gas depends on total number of drives.

### chronoDrive(string pathParams, string settleParams, string positionData, string executionData)
- **Parameters**:
  - `pathParams` (string): Hyphen-delimited `listing-impactPercent` (e.g., `0x123...456-5`).
  - `settleParams` (string): Hyphen-delimited `positionType-isCross` (e.g., `0-1` for long with CrossDriver, `1-0` for short with IsolatedDriver).
  - `positionData` (string): Hyphen-delimited `initialMargin-excessMargin-leverage` (e.g., `1000000-500000-2`).
  - `executionData` (string): Hyphen-delimited `pricePercent-timestamp-maker` (e.g., `10-1767225599-0x789...abc`).
- **Returns**: `uint256` (drive ID if pending, or position ID if executed immediately).
- **Behavior**: Initiates a time-based position, executing immediately if `timestamp <= block.timestamp` or storing as a pending drive, parsing inputs, handling token transfers, calculating fees, and executing via `ISSCrossDriver` or `ISSIsolatedDriver` based on `isCross`, emitting `ChronoDriveStarted` (if pending) and `FeePaid`.
- **Internal Call Flow**:
  - Calls `_parseChronoDriveInputs` to parse inputs into `ChronoDriveParams`.
  - Calls `_validateChronoDriveInputs` to check `timestamp`, `pricePercent`, and `positionType` (0 for long, 1 for short).
  - Calls `_handleTokenTransfer` to transfer tokens and calculate fees.
  - If `timestamp <= block.timestamp`, calls `_computeChronoDrivePrices` and `_executeChronoDrive` (which uses `_prepareDriverExecution`, `_handleTokenApproval`, `_executeDriverCall`, `_processFeePayout`).
  - Otherwise, calls `_initializeChronoDrive` to store the drive.
  - Transfer destinations: Contract for input tokens, driver contract for execution, `msg.sender` for fees (if executed).
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(this)` or `address(this).balance` in `_checkTransfer`.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `crossDriverAddress`, `isolatedDriverAddress`, `nextChronoDriveId`, `totalChronoDrives`, `chronoDrivesByAddress`, `chronoDriveID`, `isChronoDrive`.
  - **Structs**: `ChronoDriveParams`, `StalledChronoDrive`.
- **Restrictions**: Protected by `nonReentrant` and `onlyValidDriver`, reverts if no driver is set, `timestamp < block.timestamp`, `pricePercent > 100`, `positionType > 1`, or principal too low for fee.
- **Gas Usage Controls**: Internal call tree, `ChronoDriveParams`, pop-and-swap for arrays, bounded parsing.

### cancelChronoDrive(uint256 driveId)
- **Parameters**:
  - `driveId` (uint256): Drive ID to cancel.
- **Returns**: None.
- **Behavior**: Cancels a pending drive, refunding `principalAmount + feeAmount` in the input token to the maker, updating `driveStatus` to 2, and removing from mappings, emitting `ChronoDriveCanceled`.
- **Internal Call Flow**:
  - Validates `isChronoDrive`, `maker == msg.sender`, and `driveStatus == 1`.
  - Refunds via `_checkTransfer` (native or ERC20).
  - Updates `chronoDriveID`, `chronoDrivesByAddress`, and `totalChronoDrives` using pop-and-swap.
  - Transfer destinations: `msg.sender` for refunds.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(this)` or `address(this).balance`.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms refund.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoDriveID`, `chronoDrivesByAddress`, `totalChronoDrives`, `isChronoDrive`.
  - **Structs**: `StalledChronoDrive`.
- **Restrictions**: Protected by `nonReentrant`, reverts if not maker or `driveStatus != 1`.
- **Gas Usage Controls**: Single drive processing, pop-and-swap for arrays.

### continueChronoDrive(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum drives to process.
- **Returns**: None.
- **Behavior**: Processes up to `maxIterations` of the maker’s pending drives where `block.timestamp >= timestamp`, executing via `ISSCrossDriver` or `ISSIsolatedDriver` with `isCross` set to `true` for long positions (`positionType = 0`), paying the 0.05% fee to `msg.sender`, updating mappings, emitting `ChronoDriveContinued` and `FeePaid`.
- **Internal Call Flow**:
  - Iterates `chronoDrivesByAddress` for `msg.sender`.
  - For eligible drives, populates `ChronoDriveParams`, calls `_computeChronoDrivePrices` and `_executeChronoDrive` (using `_prepareDriverExecution`, `_handleTokenApproval`, `_executeDriverCall`, `_processFeePayout`).
  - Updates `chronoDriveID` and removes from `chronoDrivesByAddress` using pop-and-swap.
  - Transfer destinations: Driver contract for execution, `msg.sender` for fees.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(driver)` or `address(driver).balance` in `_checkTransfer`.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoDriveID`, `chronoDrivesByAddress`, `crossDriverAddress`, `isolatedDriverAddress`.
  - **Structs**: `StalledChronoDrive`, `ChronoDriveParams`.
- **Restrictions**: Protected by `nonReentrant` and `onlyValidDriver`, reverts if `maxIterations == 0` or no driver set.
- **Gas Usage Controls**: Bounded by `maxIterations`, pop-and-swap for arrays.

### executeChronoDrive(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum drives to process.
- **Returns**: None.
- **Behavior**: Processes up to `maxIterations` pending drives globally where `block.timestamp >= timestamp`, executing via `ISSCrossDriver` or `ISSIsolatedDriver` with `isCross` set to `true` for long positions (`positionType = 0`), paying the 0.05% fee to `msg.sender`, updating mappings, emitting `ChronoDriveContinued` and `FeePaid`.
- **Internal Call Flow**:
  - Iterates `totalChronoDrives`.
  - For eligible drives, populates `ChronoDriveParams`, calls `_computeChronoDrivePrices` and `_executeChronoDrive` (using `_prepareDriverExecution`, `_handleTokenApproval`, `_executeDriverCall`, `_processFeePayout`).
  - Updates `chronoDriveID`, `chronoDrivesByAddress`, and `totalChronoDrives` using pop-and-swap.
  - Transfer destinations: Driver contract for execution, `msg.sender` for fees.
- **Balance Checks**:
  - Same as `continueChronoDrive`.
- **Mappings/Structs Used**:
  - Same as `continueChronoDrive`, plus `totalChronoDrives`.
- **Restrictions**: Protected by `nonReentrant` and `onlyValidDriver`, reverts if `maxIterations == 0` or no driver set.
- **Gas Usage Controls**: Bounded by `maxIterations`, pop-and-swap for arrays.

### getContractBalance(address token)
- **Parameters**:
  - `token` (address): Token address (or `address(0)` for native currency).
- **Returns**: `uint256` (contract balance).
- **Behavior**: Returns the contract’s balance for the specified token or native currency using `IERC20.balanceOf` or `address(this).balance`.
- **Internal Call Flow**: Queries balance directly.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, single external call, minimal gas.

## Additional Details
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap for array resizing, and an internal call tree to minimize gas costs.
- **Token Flow**: Input tokens are transferred to the contract, then to the driver contract for execution, with fees paid to `msg.sender` or refunded to the maker on cancellation.
- **Drive Lifecycle**: Initiated via `chronoDrive` (immediate or pending), executable via `continueChronoDrive` or `executeChronoDrive` when `timestamp` is reached, cancellable via `cancelChronoDrive` if active.
- **Events**: Emitted for driver setting (`CrossDriverSet`, `IsolatedDriverSet`), drive initiation (`ChronoDriveStarted`), continuation (`ChronoDriveContinued`), cancellation (`ChronoDriveCanceled`), and fee payment (`FeePaid`).
- **Safety**: Explicit casting, balance checks, no inline assembly, and minimal validation ensure secure operation.
- **Stack Optimization**: The `ChronoDriveParams` struct and internal call tree prevent stack-too-deep errors by modularizing logic, with `_executeChronoDrive` split into smaller helpers.
- **Position Type Usage**: The `positionType` parameter (`0` for long, `1` for short) is used consistently in `settleParams`, `_getPositionToken`, `_computeEntryPrices`, `chronoDrive`, `continueChronoDrive`, and `executeChronoDrive` to determine the token (`tokenA` or `tokenB`) and price calculation logic (long or short formulas).
