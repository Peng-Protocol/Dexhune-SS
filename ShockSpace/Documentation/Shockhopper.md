# Shockhopper Contracts Documentation
The system is made up of (2) contracts; `ShockEntry` and `ShockExit`. 

# ShockEntry Contract Documentation

## Overview
The `ShockEntry` contract, implemented in Solidity (^0.8.2), facilitates multi-hop token swaps via the `Multihopper` contract followed by position creation using either `SSCrossDriver` or `SSIsolatedDriver`. It supports up to four listings for token swaps, handles token decimals, and ensures secure position creation with leverage, stop-loss, and take-profit settings. The contract uses `SafeERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. State variables are hidden, accessed via view functions, and mappings track user hops and entry details.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.58 (last updated 2025-07-12)

**Compatible Contracts:**
- `Multihopper` v0.0.44
- `SSCrossDriver` v0.0.61
- `SSIsolatedDriver` v0.0.61
- `SSListingTemplate` v0.0.10

## Clarifications
- **Token Flow**: Tokens are transferred from `msg.sender` to the contract, approved for `Multihopper`, swapped to the `endToken`, and approved for `SSCrossDriver` or `SSIsolatedDriver` for position creation on behalf of the `maker` address; during cancellation, refunds are processed from `Multihopper` to `ShockEntry` and then to the `maker`, potentially incurring transfer taxes.
- **Hop Execution**: The `_executeEntryHop` function initiates a `Multihopper` hop with the contract as the recipient, storing hop details for later continuation or cancellation, optimized with helper functions (`_transferAndApproveTokens`, `_executeMultihop`, `_attemptContinuation`) to reduce stack usage.
- **Position Creation**: After a successful `Multihopper` hop (`hopStatus == 2`), `_executeCrossContinueHop` or `_executeIsolatedContinueHop` approves the `endToken` and calls the respective driver’s `drive` function with denormalized parameters precomputed via `_prepareDriverParams`, using the `maker` address for position ownership.
- **Cancellation Refunds**: `_cancelEntryHop` refunds `pending` amounts in the input token and `filled` or `amountSent` in the output token to the `maker` address, ensuring no duplicate refunds by checking balances before transfers, with `_prepCancelEntryHop` validating the hop’s stall stage and using `CancelPrepData` to handle exact token refunds based on `Multihopper` data; `refundedPending` tracks the actual amount refunded after transfer to account for potential tax losses.
- **RefundedPending Usage**: The `refundedPending` field in `CancelPrepData` is initialized to 0 and updated in `_handlePending` to store the actual amount refunded to the `maker` after transferring the `pending` amount, capturing any reduction due to transfer taxes as handled by `Multihopper`’s refund logic, ensuring accurate refund tracking without independent transfer validation in `ShockEntry`.
- **Maker Flexibility**: In `crossEntryHop` and `isolatedEntryHop`, `msg.sender` can specify a different `maker` address for position ownership while paying the principal via `safeTransferFrom`, with `maker` defaulting to `msg.sender` only if `address(0)` is provided, allowing flexible delegation of position ownership.
- **Decimal Handling**: Amounts and prices are normalized to 1e18 precision using `_normalizeAmount` and `_normalizePrice`, then denormalized for external calls using `_denormalizeAmount` and `_denormalizePrice` based on token decimals from `IERC20.decimals`.
- **Hop Status**: `EntryHop.status` tracks pending (1), completed (2), or cancelled (3) states; `Multihopper.hopStatus` (1 = stalled, 2 = completed) is validated during continuation and cancellation.
- **Driver Selection**: `isCrossDriver` flag determines whether `SSCrossDriver` or `SSIsolatedDriver` is used, ensuring correct approvals and function calls.
- **Listing Validation**: `_validatePositionToken` ensures the `Multihopper` `endToken` matches the required token for the position (`tokenA` for long, `tokenB` for short) via `ISSListingTemplate`.
- **String Parsing**: `_parseHopParams` and `_prepPositionParams` parse hyphen-delimited strings for listings, tokens, and position parameters, ensuring valid addresses and values.
- **Gas Optimization**: Uses `maxIterations` to limit hop processing, pop-and-swap for array operations, avoids inline assembly, and optimizes stack usage with helper functions and structs.

## State Variables
- **crossDriver** (address, private): Stores the `SSCrossDriver` contract address.
- **isolatedDriver** (address, private): Stores the `SSIsolatedDriver` contract address.
- **multihopper** (address, private): Stores the `Multihopper` contract address.
- **hopCount** (uint256, private): Tracks the total number of entry hops.
- **userHops** (mapping(address => uint256[]), private): Maps user addresses to their entry hop IDs.
- **entryHops** (mapping(uint256 => EntryHop), private): Stores entry hop details by hop ID.

## Structs
- **EntryHop**: Contains `maker` (address, hop initiator and position owner), `hopId` (uint256, Multihopper hop ID), `listingAddress` (address, position listing), `positionType` (uint8, 0 = long, 1 = short), `initialMargin` (uint256, normalized margin), `excessMargin` (uint256, normalized excess margin), `leverage` (uint8, leverage multiplier), `stopLossPrice` (uint256, normalized stop-loss price), `takeProfitPrice` (uint256, normalized take-profit price), `endToken` (address, Multihopper end token), `status` (uint8, 1 = pending, 2 = completed, 3 = cancelled), `isCrossDriver` (bool, driver type), `minEntryPrice` (uint256, normalized minimum entry price), `maxEntryPrice` (uint256, normalized maximum entry price).
- **HopParams**: Includes `listingAddresses` (address[], up to 4 listings), `startToken` (address, input token), `endToken` (address, output token), `impactPercent` (uint256, price impact scaled to 1000), `settleType` (uint8, 0 = market, 1 = liquid), `maxIterations` (uint256, max settlement iterations).
- **PositionParams**: Contains `listingAddress` (address, position listing), `minEntryPrice` (uint256, min entry price), `maxEntryPrice` (uint256, max entry price), `initialMargin` (uint256, initial margin), `excessMargin` (uint256, excess margin), `leverage` (uint8, leverage multiplier), `stopLossPrice` (uint256, stop-loss price), `takeProfitPrice` (uint256, take-profit price), `positionType` (uint8, 0 = long, 1 = short).
- **DriverParams**: Contains `minEntryPrice` (uint256, denormalized minimum entry price), `maxEntryPrice` (uint256, denormalized maximum entry price), `initialMargin` (uint256, denormalized initial margin), `excessMargin` (uint256, denormalized excess margin), `stopLossPrice` (uint256, denormalized stop-loss price), `takeProfitPrice` (uint256, denormalized take-profit price).
- **CancelPrepData**: Includes `hopId` (uint256, entry hop ID), `pending` (uint256, pending amount), `filled` (uint256, filled amount), `status` (uint8, order status), `amountSent` (uint256, amount sent), `recipient` (address, output recipient), `inputToken` (address, input token), `outputToken` (address, output token), `refundedPending` (uint256, actual amount refunded after transfer).

## Formulas
1. **Normalized Amount**:
   - **Formula**: `normalizedAmount = (amount * 1e18) / (10 ** decimals)` if `decimals < 18`, else `amount`.
   - **Used in**: `_normalizeAmount`, `_executeMultihop`.
   - **Description**: Converts token amounts to 1e18 precision for consistent storage and calculations.

2. **Denormalized Amount**:
   - **Formula**: `rawAmount = (normalizedAmount * (10 ** decimals)) / 1e18` if `decimals < 18`, else `normalizedAmount`.
   - **Used in**: `_denormalizeAmount`, `_prepareDriverParams`.
   - **Description**: Converts normalized amounts to token-specific decimals for external calls.

3. **Normalized Price**:
   - **Formula**: `normalizedPrice = (price * 1e18) / (10 ** decimals)` if `decimals < 18`, else `price`.
   - **Used in**: `_normalizePrice`, `_executeMultihop`.
   - **Description**: Normalizes prices to 1e18 precision for storage.

4. **Denormalized Price**:
   - **Formula**: `rawPrice = (normalizedPrice * (10 ** decimals)) / 1e18` if `decimals < 18`, else `normalizedPrice`.
   - **Used in**: `_denormalizePrice`, `_prepareDriverParams`.
   - **Description**: Converts normalized prices to token-specific decimals for driver calls.

## External Functions

### setMultihopper(address _multihopper)
- **Parameters**:
  - `_multihopper` (address): New `Multihopper` contract address.
- **Behavior**: Sets the `multihopper` address for token swaps, restricted to the owner.
- **Internal Call Flow**:
  - Validates `_multihopper != address(0)`.
  - Assigns `_multihopper` to `multihopper`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `multihopper`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_multihopper` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### setCrossDriver(address _crossDriver)
- **Parameters**:
  - `_crossDriver` (address): New `SSCrossDriver` contract address.
- **Behavior**: Sets the `crossDriver` address for position creation, restricted to the owner.
- **Internal Call Flow**:
  - Validates `_crossDriver != address(0)`.
  - Assigns `_crossDriver` to `crossDriver`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `crossDriver`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_crossDriver` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### setIsolatedDriver(address _isolatedDriver)
- **Parameters**:
  - `_isolatedDriver` (address): New `SSIsolatedDriver` contract address.
- **Behavior**: Sets the `isolatedDriver` address for position creation, restricted to the owner.
- **Internal Call Flow**:
  - Validates `_isolatedDriver != address(0)`.
  - Assigns `_isolatedDriver` to `isolatedDriver`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `isolatedDriver`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_isolatedDriver` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### crossEntryHop(string memory listings, uint256 impactPercent, string memory tokens, uint8 settleType, uint256 maxIterations, string memory positionParams, address maker)
- **Parameters**:
  - `listings` (string): Hyphen-delimited list of up to four listing contract addresses (e.g., "0x123...-0x456...-0x789...-0xabc..." or "0x123..."), each a valid Ethereum address for swap listings.
  - `impactPercent` (uint256): Maximum price impact for the swap, scaled to 1000 (e.g., 50 = 5% impact).
  - `tokens` (string): Hyphen-delimited start and end token addresses (e.g., "0xStartToken-0xEndToken"), where `startToken` is the input token and `endToken` is the output token after the swap.
  - `settleType` (uint8): Settlement type, where 0 = market order, 1 = liquid order.
  - `maxIterations` (uint256): Maximum number of iterations for `Multihopper` settlement and `executePositions` processing.
  - `positionParams` (string): Hyphen-delimited position parameters in the format "listingAddress-minEntryPrice-maxEntryPrice-initialMargin-excessMargin-leverage-stopLossPrice-takeProfitPrice-positionType" (e.g., "0xListing-1000-2000-500-100-2-500-6000-0"), where:
    - `listingAddress`: Address of the position listing contract.
    - `minEntryPrice`: Minimum acceptable entry price for the position (uint256, token-specific decimals).
    - `maxEntryPrice`: Maximum acceptable entry price for the position (uint256, token-specific decimals).
    - `initialMargin`: Initial margin amount for the position (uint256, token-specific decimals).
    - `excessMargin`: Excess margin amount for the position (uint256, token-specific decimals).
    - `leverage`: Leverage multiplier (uint8, 2 to 100).
    - `stopLossPrice`: Stop-loss price for the position (uint256, token-specific decimals).
    - `takeProfitPrice`: Take-profit price for the position (uint256, token-specific decimals).
    - `positionType`: 0 for long, 1 for short (uint8).
  - `maker` (address): Address that initiates the hop and owns the resulting position in `SSCrossDriver`; defaults to `msg.sender` if `address(0)`, allowing `msg.sender` to pay the principal while assigning position ownership to another address.
- **Behavior**: Initiates a `Multihopper` swap with tokens transferred from `msg.sender`, followed by `SSCrossDriver` position creation for the `maker` address, storing hop details for continuation or cancellation.
- **Internal Call Flow**:
  - Calls `_prepHopParams` to parse `listings`, `tokens`, `impactPercent`, `settleType`, `maxIterations` into `HopParams`.
  - Calls `_prepPositionParams` to parse `positionParams` into `PositionParams`.
  - Calls `_executeEntryHop`:
    - Calls `_validatePositionToken` to ensure `endToken` matches position requirements.
    - Calls `_transferAndApproveTokens` to transfer input tokens from `msg.sender` and approve `multihopper`.
    - Calls `_executeMultihop` to initiate `IMultihopper.hop`, store `EntryHop` data with normalized prices and amounts, and update `userHops` and `hopCount`.
    - Calls `_attemptContinuation` to attempt immediate continuation if `Multihopper` hop is completed.
  - Emits `EntryHopStarted`.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(this)` for input token before transfer in `_transferAndApproveTokens`.
  - **Post-Balance Check**: Ensures `balanceAfter > balanceBefore`.
- **Mappings/Structs Used**:
  - **Mappings**: `hopCount`, `userHops`, `entryHops`.
  - **Structs**: `HopParams`, `PositionParams`, `EntryHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if invalid addresses, margins, leverage, position type, or token mismatch.
- **Gas Usage Controls**: Single hop processing, optimized with helper functions to reduce stack usage.

### isolatedEntryHop(string memory listings, uint256 impactPercent, string memory tokens, uint8 settleType, uint256 maxIterations, string memory positionParams, address maker)
- **Parameters**: Same as `crossEntryHop`, with `maker` allowing `msg.sender` to pay the principal while assigning position ownership to another address if not `address(0)`.
- **Behavior**: Initiates a `Multihopper` swap with tokens transferred from `msg.sender`, followed by `SSIsolatedDriver` position creation for the `maker` address, storing hop details for continuation or cancellation.
- **Internal Call Flow**: Same as `crossEntryHop`, but sets `isCrossDriver = false` in `_executeEntryHop`.
- **Balance Checks**: Same as `crossEntryHop`.
- **Mappings/Structs Used**: Same as `crossEntryHop`.
- **Restrictions**: Same as `crossEntryHop`.
- **Gas Usage Controls**: Same as `crossEntryHop`.

### continueCrossEntryHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum number of pending hops to process for `msg.sender`.
- **Behavior**: Processes up to `maxIterations` pending `SSCrossDriver` hops for `msg.sender`, continuing completed `Multihopper` hops.
- **Internal Call Flow**:
  - Calls `_continueEntryHops`:
    - Iterates `userHops`, checks `status == 1`, `maker == msg.sender`, and `isCrossDriver == true`.
    - Calls `_prepContinueParams` to check `Multihopper.hopStatus` and retrieve `amountSent`.
    - Calls `_executeCrossContinueHop`:
      - Approves `endToken` for `crossDriver`.
      - Calls `_prepareDriverParams` to precompute denormalized parameters into `DriverParams`.
      - Calls `ISSCrossDriver.drive` with `DriverParams` fields, `maker`, `listingAddress`, `leverage`, and `positionType`.
      - Calls `ISSCrossDriver.executePositions` if `crossDriver` is set.
      - Updates `status` to 2 and emits `EntryHopCompleted`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`, `entryHops`.
  - **Structs**: `EntryHop`, `DriverParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: Bounded by `maxIterations`, optimized with `DriverParams` to reduce stack usage.

### continueIsolatedEntryHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum number of pending hops to process for `msg.sender`.
- **Behavior**: Identical to `continueCrossEntryHops` but for `SSIsolatedDriver` hops (`isCrossDriver == false`), using `maker` as position owner.
- **Internal Call Flow**: Same as `continueCrossEntryHops`, but calls `_executeIsolatedContinueHop`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`, `entryHops`.
  - **Structs**: `EntryHop`, `DriverParams`.
- **Restrictions**: Same as `continueCrossEntryHops`.
- **Gas Usage Controls**: Same as `continueCrossEntryHops`.

### cancelCrossEntryHop(uint256 entryHopId)
- **Parameters**:
  - `entryHopId` (uint256): Entry hop ID to cancel.
- **Behavior**: Cancels a pending `SSCrossDriver` hop, refunds tokens to the `maker` address, and updates status, using `refundedPending` to track actual refunded amounts after transfer.
- **Internal Call Flow**:
  - Calls `_cancelEntryHop`:
    - Validates `isCrossDriver == true`, `status == 1`, and `maker == msg.sender`.
    - Calls `_prepCancelEntryHop` to retrieve `CancelPrepData`, ensuring correct input and output tokens based on `Multihopper` stall stage.
    - Calls `IMultihopper.cancelHop` to initiate cancellation in `Multihopper`.
    - Refunds via `_handleFilledOrSent` (output token, using `filled` or `amountSent`) and `_handlePending` (input token, updating `refundedPending` with actual transferred amount) to `maker`.
    - Updates `status` to 3, removes from `userHops` via `_removeHopIndex`, emits `EntryHopCancelled`.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(this)` for output and input tokens in `_handleFilledOrSent` and `_handlePending`.
  - **Post-Balance Check**: Ensures sufficient balance for refunds; `refundedPending` captures actual transferred amount in `_handlePending`.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHops`, `userHops`.
  - **Structs**: `EntryHop`, `CancelPrepData`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if not pending, not maker, or Multihopper hop not stalled.
- **Gas Usage Controls**: Single hop processing, pop-and-swap for arrays.

### cancelIsolatedEntryHop(uint256 entryHopId)
- **Parameters**:
  - `entryHopId` (uint256): Entry hop ID to cancel.
- **Behavior**: Identical to `cancelCrossEntryHop` but for `SSIsolatedDriver` hops (`isCrossDriver == false`), refunding to the `maker` address and using `refundedPending` to track actual refunded amounts.
- **Internal Call Flow**: Same as `cancelCrossEntryHop`.
- **Balance Checks**: Same as `cancelCrossEntryHop`.
- **Mappings/Structs Used**: Same as `cancelCrossEntryHop`.
- **Restrictions**: Same as `cancelCrossEntryHop`.
- **Gas Usage Controls**: Same as `cancelCrossEntryHop`.

### getEntryHopDetails(uint256 entryHopId)
- **Parameters**:
  - `entryHopId` (uint256): Entry hop ID.
- **Behavior**: Returns the `EntryHop` struct for the given `entryHopId`.
- **Internal Call Flow**: Direct access to `entryHops`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `entryHops`.
  - **Structs**: `EntryHop`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getUserEntryHops(address user)
- **Parameters**:
  - `user` (address): User address.
- **Behavior**: Returns the array of entry hop IDs for a given user.
- **Internal Call Flow**: Direct access to `userHops`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### multihopperView()
- **Parameters**: None.
- **Behavior**: Returns the `multihopper` address.
- **Internal Call Flow**: Direct access to `multihopper`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `multihopper`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### crossDriverView()
- **Parameters**: None.
- **Behavior**: Returns the `crossDriver` address.
- **Internal Call Flow**: Direct access to `crossDriver`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `crossDriver`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### isolatedDriverView()
- **Parameters**: None.
- **Behavior**: Returns the `isolatedDriver` address.
- **Internal Call Flow**: Direct access to `isolatedDriver`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `isolatedDriver`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

## Additional Details
- **Decimal Handling**: Normalizes amounts and prices to 1e18 precision, denormalizes for external calls, using `IERC20.decimals` for accuracy.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap for `userHops` array, avoids inline assembly, and optimizes stack usage with `DriverParams` and helper functions.
- **Token Validation**: Ensures `endToken` matches position requirements via `ISSListingTemplate`.
- **Hop Lifecycle**: Hops are pending (1) until continued (2) or cancelled (3), with `Multihopper` status checks.
- **Events**: Emitted for hop start (`EntryHopStarted`), completion (`EntryHopCompleted`), and cancellation (`EntryHopCancelled`).
- **Safety**: Explicit casting, balance checks, no reserved keywords, and no inline assembly ensure secure operation.
- **Driver Compatibility**: Supports both `SSCrossDriver` and `SSIsolatedDriver` with distinct execution paths.
- **String Parsing**: Robust parsing of hyphen-delimited strings for flexibility and user input handling.

# ShockExit Contract Documentation

## Overview
The `ShockExit` contract, implemented in Solidity (^0.8.2), facilitates closing positions via `SSCrossDriver` or `SSIsolatedDriver` and initiating multi-hop token swaps through the `Multihopper` contract. It supports up to four listings for token swaps, handles token decimals, and ensures secure position closure with market or liquid settlement. The contract uses `SafeERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. State variables are hidden, accessed via view functions, and mappings track user hops and exit details.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.58 (last updated 2025-07-12): 

**Compatible Contracts:**
- `Multihopper` v0.0.41
- `SSCrossDriver` v0.0.61
- `SSIsolatedDriver` v0.0.61
- `SSListingTemplate` v0.0.10

## Clarifications
- **Maker Address Flexibility**: In `crossExitHop` and `isolatedExitHop`, the `maker` parameter specifies the hop initiator for `IMultihopper.hop`; if `address(0)`, `msg.sender` is used, with all tokens transferred to the `maker`.
- **Token Flow**: Tokens from position closure (`tokenB` for long, `tokenA` for short) are received by the contract, approved for `Multihopper`, swapped to the `endToken`, and transferred to the `maker`.
- **Hop Execution**: `_executeExitHop` initiates position closure via `SSCrossDriver` or `SSIsolatedDriver.drift`, settles the payout, and calls `_initiateMultihop` to start a `Multihopper` hop with the `maker` address as the hop initiator in `IMultihopper.hop`.
- **Position Closure**: `_initiateDrift` calls the respective driver’s `drift` function, retrieving the payout order ID from `ISSListingTemplate.getNextOrderId`.
- **Payout Settlement**: `_settlePayout` uses `ISSListingTemplate.settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, or `settleShortLiquid` based on `settleType` and `positionType`.
- **Zero Payout Handling**: If `_checkPayout` returns `amountReceived == 0`, `_initiateMultihop` attempts to approve zero tokens for `Multihopper` and calls `_callMultihop` to initiate `IMultihopper.hop`, which reverts with "Invalid raw amount" in `Multihopper`’s `computeBaseOrderParams`, leading to `_initiateMultihop` refunding zero tokens, cancelling the hop, and emitting `ExitHopCancelled`. If `_callMultihop` fails to initiate `IMultihopper.hop` (returning 0), `_initiateMultihop` refunds any received tokens (zero in case of zero payout) and cancels the hop, emitting `ExitHopCancelled`.
- **Cancellation Handling**: `_cancelExitHop` cancels hops in the initializing state (before `Multihopper` hop), while failed `continueHop` calls in `_continueExitHops` refund `startToken` and cancel the hop.
- **Global Hop Processing**: `executeCrossExitHops` and `executeIsolatedExitHops` process pending hops globally across all users, iterating through `exitHops` up to `maxIterations`, reusing `_continueExitHops` for each user’s hops.
- **Decimal Handling**: Amounts are normalized to 1e18 precision using `_normalizeAmount` and denormalized for external calls using `_denormalizeAmount` based on token decimals.
- **Hop Status**: `ExitHop.status` tracks initializing (0), pending (1), completed (2), or cancelled (3); `Multihopper.hopStatus` (1 = stalled, 2 = completed) is validated during continuation.
- **Driver Selection**: `isCrossDriver` flag determines whether `SSCrossDriver` or `SSIsolatedDriver` is used, ensuring correct function calls.
- **Token Validation**: `_validatePositionToken` ensures the `startToken` matches the position’s payout token (`tokenB` for long, `tokenA` for short) via `ISSListingTemplate`.
- **String Parsing**: `_parseHopParams` and `_prepPositionParams` parse hyphen-delimited strings for `listings`, `tokens`, and `positionParams`:
  - **`listings`**: Up to four Ethereum addresses (42 characters each, including "0x") representing listing contracts, separated by hyphens (e.g., "0x1-0x2-0x3-0x4" or "0x1" for one listing); empty listings are padded with `address(0)`.
  - **`tokens`**: Two Ethereum addresses (42 characters each, including "0x") representing `startToken` and `endToken`, separated by a hyphen (e.g., "0xStart-0xEnd").
  - **`positionParams`**: Three fields—listing address (42 characters, including "0x"), position ID (numeric string), and position type (0 for long, 1 for short)—separated by hyphens (e.g., "0xListing-123-0").
- **Gas Optimization**: Uses `maxIterations` to limit hop processing, pop-and-swap for array operations, and avoids inline assembly for array resizing.

## State Variables
- **crossDriver** (address, private): Stores the `SSCrossDriver` contract address.
- **isolatedDriver** (address, private): Stores the `SSIsolatedDriver` contract address.
- **multihopper** (address, private): Stores the `Multihopper` contract address.
- **hopCount** (uint256, private): Tracks the total number of exit hops.
- **userHops** (mapping(address => uint256[]), private): Maps user addresses to their exit hop IDs.
- **exitHops** (mapping(uint256 => ExitHop), private): Stores exit hop details by hop ID.

## Structs
- **ExitHop**: Contains `maker` (address, hop initiator), `multihopId` (uint256, Multihopper hop ID), `positionId` (uint256, position to close), `listingAddress` (address, position listing), `positionType` (uint8, 0 = long, 1 = short), `payoutOrderId` (uint256, payout order ID), `startToken` (address, position payout token), `endToken` (address, Multihopper end token), `settleType` (uint8, 0 = market, 1 = liquid), `status` (uint8, 0 = initializing, 1 = pending, 2 = completed, 3 = cancelled), `isCrossDriver` (bool, driver type).
- **HopParams**: Includes `listingAddresses` (address[], up to 4 listings), `startToken` (address, input token), `endToken` (address, output token), `impactPercent` (uint256, price impact scaled to 1000), `settleType` (uint8, 0 = market, 1 = liquid), `maxIterations` (uint256, max settlement iterations).
- **PositionParams**: Contains `listingAddress` (address, position listing), `positionId` (uint256, position ID), `positionType` (uint8, 0 = long, 1 = short).

## Formulas
1. **Normalized Amount**:
   - **Formula**: `normalizedAmount = (amount * 1e18) / (10 ** decimals)` if `decimals < 18`, else `amount`.
   - **Used in**: `_normalizeAmount`, `_initiateMultihop`.
   - **Description**: Converts token amounts to 1e18 precision for consistent calculations.
2. **Denormalized Amount**:
   - **Formula**: `rawAmount = (normalizedAmount * (10 ** decimals)) / 1e18` if `decimals < 18`, else `normalizedAmount`.
   - **Used in**: `_denormalizeAmount`, `_executeCrossContinueHop`, `_executeIsolatedContinueHop`.
   - **Description**: Converts normalized amounts to token-specific decimals for external calls.

## External Functions

### setMultihopper(address _multihopper)
- **Parameters**:
  - `_multihopper` (address): New `Multihopper` contract address.
- **Behavior**: Sets the `multihopper` address for token swaps, restricted to the owner.
- **Internal Call Flow**:
  - Validates `_multihopper != address(0)`.
  - Assigns `_multihopper` to `multihopper`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `multihopper`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_multihopper` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### setCrossDriver(address _crossDriver)
- **Parameters**:
  - `_crossDriver` (address): New `SSCrossDriver` contract address.
- **Behavior**: Sets the `crossDriver` address for position closure, restricted to the owner.
- **Internal Call Flow**:
  - Validates `_crossDriver != address(0)`.
  - Assigns `_crossDriver` to `crossDriver`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `crossDriver`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_crossDriver` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### setIsolatedDriver(address _isolatedDriver)
- **Parameters**:
  - `_isolatedDriver` (address): New `SSIsolatedDriver` contract address.
- **Behavior**: Sets the `isolatedDriver` address for position closure, restricted to the owner.
- **Internal Call Flow**:
  - Validates `_isolatedDriver != address(0)`.
  - Assigns `_isolatedDriver` to `isolatedDriver`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `isolatedDriver`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `_isolatedDriver` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### crossExitHop(string memory listings, uint256 impactPercent, string memory tokens, uint8 settleType, uint256 maxIterations, string memory positionParams, address maker)
- **Parameters**:
  - `listings` (string): Hyphen-delimited string of up to four listing contract addresses (42 characters each, including "0x"), e.g., "0x1-0x2-0x3-0x4" or "0x1".
  - `impactPercent` (uint256): Max price impact (scaled to 1000).
  - `tokens` (string): Hyphen-delimited string of two token addresses (42 characters each, including "0x"), e.g., "0xStart-0xEnd".
  - `settleType` (uint8): 0 = market, 1 = liquid.
  - `maxIterations` (uint256): Max settlement iterations for `Multihopper` and payout settlement.
  - `positionParams` (string): Hyphen-delimited string of listing address (42 characters, including "0x"), position ID (numeric string), and position type (0 for long, 1 for short), e.g., "0xListing-123-0".
  - `maker` (address): Hop initiator (defaults to `msg.sender` if `address(0)`).
- **Behavior**: Initiates position closure via `SSCrossDriver`, settles payout, and starts a `Multihopper` hop with the `maker` as the initiator, transferring swapped tokens to the `maker`.
- **Internal Call Flow**:
  - Parses `listings`, `tokens`, and `positionParams` into `HopParams` and `PositionParams`.
  - Calls `_executeExitHop` with `isCrossDriver = true`:
    - Calls `_initiateDrift` to close the position via `SSCrossDriver.drift`.
    - Calls `_settlePayout` to settle the payout.
    - Calls `_checkPayout` to retrieve `startToken` and `amountReceived`.
    - Validates `startToken` via `_validatePositionToken`.
    - Calls `_initiateMultihop`, which uses `_callMultihop` to initiate `IMultihopper.hop`, handling failures by refunding tokens and cancelling the hop.
  - Emits `ExitHopStarted` on success or `ExitHopCancelled` on failure.
- **Balance Checks**:
  - Implicitly handled by `IERC20.safeTransfer` and `safeApprove`.
- **Mappings/Structs Used**:
  - **Mappings**: `hopCount`, `userHops`, `exitHops`.
  - **Structs**: `HopParams`, `PositionParams`, `ExitHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if invalid addresses, position type, or token mismatch.
- **Gas Usage Controls**: Single hop processing, minimal external calls, stack optimization.

### isolatedExitHop(string memory listings, uint256 impactPercent, string memory tokens, uint8 settleType, uint256 maxIterations, string memory positionParams, address maker)
- **Parameters**: Same as `crossExitHop`.
- **Behavior**: Identical to `crossExitHop` but uses `SSIsolatedDriver` for position closure and sets `maker` as the hop initiator in `Multihopper`.
- **Internal Call Flow**: Same as `crossExitHop`, but sets `isCrossDriver = false` in `_executeExitHop` and uses `_callMultihop` in `_initiateMultihop` for `IMultihopper.hop`.
- **Balance Checks**: Same as `crossExitHop`.
- **Mappings/Structs Used**: Same as `crossExitHop`.
- **Restrictions**: Same as `crossExitHop`.
- **Gas Usage Controls**: Same as `crossExitHop`.

### continueCrossExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process for the caller.
- **Behavior**: Processes up to `maxIterations` pending `SSCrossDriver` hops for `msg.sender`, settling payouts and continuing `Multihopper` hops.
- **Internal Call Flow**:
  - Calls `_continueExitHops` with `msg.sender`:
    - Iterates `userHops`, checks `status == 1` and `isCrossDriver = true`.
    - Settles payout via `ISSListingTemplate.settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, or `settleShortLiquid`.
    - Checks payout status via `_checkPayout` (may return zero `amountReceived`).
    - Approves `startToken` for `multihopper` (zero if `amountReceived == 0`).
    - Calls `IMultihopper.continueHop`, then `_prepContinueParams` to check `hopStatus` and get `amountSent`.
    - Calls `_executeCrossContinueHop` to transfer `endToken` to `maker` and update `status` to 2.
    - Refunds and cancels on `continueHop` failure (zero refund if `amountReceived == 0`).
  - Emits `ExitHopCompleted` or `ExitHopCancelled`.
- **Balance Checks**:
  - Implicitly handled by `IERC20.safeTransfer` and `safeApprove`.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`, `exitHops`.
  - **Structs**: `ExitHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls.

### continueIsolatedExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process for the caller.
- **Behavior**: Identical to `continueCrossExitHops` but for `SSIsolatedDriver` hops (`isCrossDriver = false`).
- **Internal Call Flow**: Same as `continueCrossExitHops`, but calls `_executeIsolatedContinueHop`.
- **Balance Checks**: Same as `continueCrossExitHops`.
- **Mappings/Structs Used**: Same as `continueCrossExitHops`.
- **Restrictions**: Same as `continueCrossExitHops`.
- **Gas Usage Controls**: Same as `continueCrossExitHops`.

### executeCrossExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process globally.
- **Behavior**: Processes up to `maxIterations` pending `SSCrossDriver` hops across all users, settling payouts and continuing `Multihopper` hops.
- **Internal Call Flow**:
  - Calls `_executeGlobalExitHops` with `isCrossDriver = true`:
    - Iterates `exitHops` from 1 to `hopCount`, checking `status == 1` and `isCrossDriver = true`.
    - Calls `_continueExitHops` for each hop’s `maker`, processing their hops.
    - Settles payouts via `ISSListingTemplate.settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, or `settleShortLiquid`.
    - Checks payout status via `_checkPayout`.
    - Approves `startToken` for `multihopper`.
    - Calls `IMultihopper.continueHop`, then `_prepContinueParams` to check `hopStatus` and get `amountSent`.
    - Calls `_executeCrossContinueHop` to transfer `endToken` to `maker` and update `status` to 2.
    - Refunds and cancels on `continueHop` failure.
  - Emits `ExitHopCompleted` or `ExitHopCancelled`.
- **Balance Checks**:
  - Implicitly handled by `IERC20.safeTransfer` and `safeApprove`.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`, `exitHops`.
  - **Structs**: `ExitHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls.

### executeIsolatedExitHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process globally.
- **Behavior**: Identical to `executeCrossExitHops` but for `SSIsolatedDriver` hops (`isCrossDriver = false`).
- **Internal Call Flow**: Same as `executeCrossExitHops`, but calls `_executeIsolatedContinueHop`.
- **Balance Checks**: Same as `executeCrossExitHops`.
- **Mappings/Structs Used**: Same as `executeCrossExitHops`.
- **Restrictions**: Same as `executeCrossExitHops`.
- **Gas Usage Controls**: Same as `executeCrossExitHops`.

### getExitHopDetails(uint256 exitHopId)
- **Parameters**:
  - `exitHopId` (uint256): Exit hop ID.
- **Behavior**: Returns the `ExitHop` struct for the given `exitHopId`.
- **Internal Call Flow**: Direct access to `exitHops`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `exitHops`.
  - **Structs**: `ExitHop`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getUserExitHops(address user)
- **Parameters**:
  - `user` (address): User address.
- **Behavior**: Returns the array of exit hop IDs for a given user.
- **Internal Call Flow**: Direct access to `userHops`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### multihopperView()
- **Parameters**: None.
- **Behavior**: Returns the `multihopper` address.
- **Internal Call Flow**: Direct access to `multihopper`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `multihopper`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### crossDriverView()
- **Parameters**: None.
- **Behavior**: Returns the `crossDriver` address.
- **Internal Call Flow**: Direct access to `crossDriver`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `crossDriver`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### isolatedDriverView()
- **Parameters**: None.
- **Behavior**: Returns the `isolatedDriver` address.
- **Internal Call Flow**: Direct access to `isolatedDriver`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `isolatedDriver`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

## Internal Functions

### _callMultihop(HopParams memory hopParams, address startToken, address hopMaker)
- **Parameters**:
  - `hopParams` (HopParams): Hop parameters including listing addresses, tokens, and settings.
  - `startToken` (address): Token to approve and use for the hop.
  - `hopMaker` (address): Address initiating the hop.
- **Behavior**: Calls `IMultihopper.hop` with hop parameters, approves `startToken`, and returns the multihop ID or 0 if the call fails, ensuring stack depth optimization and graceful degradation.
- **Internal Call Flow**:
  - Calls `IMultihopper.hop` with up to four listing addresses, `impactPercent`, `startToken`, `endToken`, `settleType`, `maxIterations`, and `hopMaker`.
  - Returns the multihop ID on success or 0 on failure.
- **Balance Checks**: Relies on prior `IERC20.safeApprove` in `_initiateMultihop`.
- **Mappings/Structs Used**:
  - **Structs**: `HopParams`.
- **Restrictions**: Private function, only called by `_initiateMultihop`.
- **Gas Usage Controls**: Minimal external call, try-catch for failure handling.

### _continueExitHops(address user, uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `user` (address): User whose hops to process.
  - `maxIterations` (uint256): Max hops to process for the user.
  - `isCrossDriver` (bool): True for `SSCrossDriver`, false for `SSIsolatedDriver`.
- **Behavior**: Processes up to `maxIterations` pending hops for a specific user, settling payouts and continuing `Multihopper` hops, used by both user-specific and global hop processing functions.
- **Internal Call Flow**:
  - Iterates `userHops` for the given user, checks `status == 1` and `isCrossDriver` match.
  - Settles payout via `ISSListingTemplate.settleLongPayouts`, `settleShortPayouts`, `settleLongLiquid`, or `settleShortLiquid`.
  - Checks payout status via `_checkPayout`.
  - Approves `startToken` for `multihopper`.
  - Calls `IMultihopper.continueHop`, then `_prepContinueParams` to check `hopStatus` and get `amountSent`.
  - Calls `_executeCrossContinueHop` or `_executeIsolatedContinueHop` to transfer `endToken` to `maker` and update `status` to 2.
  - Refunds and cancels on `continueHop` failure.
- **Balance Checks**:
  - Implicitly handled by `IERC20.safeTransfer` and `safeApprove`.
- **Mappings/Structs Used**:
  - **Mappings**: `userHops`, `exitHops`.
  - **Structs**: `ExitHop`.
- **Restrictions**: Private function, called by `continueCrossExitHops`, `continueIsolatedExitHops`, `executeCrossExitHops`, or `executeIsolatedExitHops`.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls.

### _executeGlobalExitHops(uint256 maxIterations, bool isCrossDriver)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process globally.
  - `isCrossDriver` (bool): True for `SSCrossDriver`, false for `SSIsolatedDriver`.
- **Behavior**: Iterates over all pending hops in `exitHops` up to `maxIterations`, calling `_continueExitHops` for each hop’s `maker` to process their hops, ensuring global processing of pending hops.
- **Internal Call Flow**:
  - Iterates `exitHops` from 1 to `hopCount`, checking `status == 1` and `isCrossDriver` match.
  - Calls `_continueExitHops` for each hop’s `maker`.
- **Balance Checks**: None directly; handled by `_continueExitHops`.
- **Mappings/Structs Used**:
  - **Mappings**: `exitHops`.
  - **Structs**: `ExitHop`.
- **Restrictions**: Private function, called by `executeCrossExitHops` or `executeIsolatedExitHops`.
- **Gas Usage Controls**: Bounded by `maxIterations`, minimal external calls.

## Additional Details
- **Decimal Handling**: Normalizes amounts to 1e18 precision, denormalizes for external calls, using `IERC20.decimals` for accuracy.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap for `userHops` array, avoids inline assembly, and optimizes stack depth.
- **Token Validation**: Ensures `startToken` matches position payout via `ISSListingTemplate`.
- **Hop Lifecycle**: Hops are initializing (0), pending (1), completed (2), or cancelled (3), with `Multihopper` status checks.
- **Events**: Emitted for hop start (`ExitHopStarted`), completion (`ExitHopCompleted`), and cancellation (`ExitHopCancelled`).
- **Safety**: Explicit casting, balance checks via `SafeERC20`, no reserved keywords, and no inline assembly ensure secure operation.
