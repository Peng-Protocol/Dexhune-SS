# ChronoHopper Contract Documentation

## Overview
The `ChronoHopper` contract, implemented in Solidity (^0.8.2), facilitates time-based multi-step token swaps across up to four listings by integrating with the `IMultihopper` interface, supporting market and liquid order settlements with a 0.05% fee in the input token paid to the caller of `executeHops` or `continueChronoHop`. It uses `SafeERC20` for secure token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control, managing hop creation, execution, continuation, and cancellation with gas optimization and robust decimal handling. State variables are hidden, accessed via view functions, and mappings ensure efficient hop tracking, with validation deferred to `IMultihopper` except for minimal checks on `listing1` and `timestamp`.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.51 (last updated 2025-07-06)

**Compatible Contracts:**
- `IMultihopper` v0.0.2

## Clarifications
- **Integration with IMultihopper**: The contract relies on `IMultihopper.hop` for swap execution, passing listing addresses, tokens, and parameters directly, with validation (e.g., listing count, sequence, impact percent) handled by `IMultihopper`.
- **Minimal Validation**: The `validateChronoHopRequest` function checks only `listing1 != address(0)` and `timestamp >= block.timestamp`, ensuring `ChronoHopper` defers other validations to `IMultihopper` for efficiency.
- **Timestamp-Based Execution**: Hops are stalled until `block.timestamp >= StalledChronoHop.timestamp`, checked in `processChronoHopStep`, enabling time-based execution via `continueChronoHop` or `executeHops`.
- **Single Listing Route**: If only `listing1` is specified (others are `address(0)`), the hop executes as a single-step swap when `timestamp` is reached, with a 0.05% fee paid to the caller.
- **Fee Handling**: A 0.05% fee is deducted from the input amount in `prepChronoHop`, stored in `StalledChronoHop.feeAmount`, paid to the caller of `executeHops` or `continueChronoHop` in `processChronoHopStep`, and refunded to the hop maker during cancellation in `cancelChronoHop` or `cancelAll`.
- **Balance Checks**: The `_checkTransfer` function performs pre/post balance checks (`IERC20.balanceOf` or `address(this).balance`) to verify token transfers, returning the actual amount transferred (`balanceAfter - balanceBefore`) for use in `executeChronoHop`.
- **Hop Cancellation Refunds**: The `cancelChronoHop` and `cancelAll` functions refund the full `principalAmount` plus `feeAmount` in the input token to the hop maker, as `amountSent` is managed by `IMultihopper` and not tracked in `ChronoHopper`.
- **Decimal Handling**: The `normalizeForToken` and `denormalizeForToken` functions handle token decimals (≤ 18) to ensure consistent calculations across native currency and ERC20 tokens.
- **Gas Optimization**: The contract uses `maxIterations` for bounded loops, pop-and-swap for array resizing, and an internal call tree (`computeListings`, `computeTokens`, `computeHopSettings`) to minimize stack usage and gas costs.
- **Stack Optimization**: The `prepChronoHop` function is split into `computeListings` (listing addresses and impact percents), `computeTokens` (token-related parameters), and `computeHopSettings` (hop settings), reducing stack pressure in a single transaction.
- **Hop Finalization**: Once a chronoHop is executed, (hopStatus 2), it cannot be cancelled from the ChronoHopper as the hop is now in the Multihopper. However, each chronoHop stores the `multiHopId` which allows the maker to find their pending multiHop and potentially cancel it from there if not already finalized. 

## State Variables
- **nextChronoHopId** (uint256, private): Tracks the next hop ID for unique identification of hop requests.
- **_multiHopper** (address, private): Stores the `IMultihopper` contract address for swap execution.
- **totalChronoHops** (uint256[], private): Global list of hop IDs.
- **chronoHopsByAddress** (mapping(address => uint256[]), private): Maps maker addresses to their hop IDs.
- **chronoHopID** (mapping(uint256 => StalledChronoHop), private): Stores hop details by hop ID.
- **isChronoHop** (mapping(uint256 => bool), private): Flags time-based hops.

## Structs
- **StalledChronoHop**: Tracks `stage` (uint8, current hop stage), `currentListing` (address, active listing), `orderID` (uint256, current order ID, unused), `minPrice` (uint256, min price for sell, unused), `maxPrice` (uint256, max price for buy, unused), `hopMaker` (address, hop initiator), `remainingListings` (address[], remaining listings), `principalAmount` (uint256, current input amount), `startToken` (address, input token), `endToken` (address, output token), `settleType` (uint8, 0 = market, 1 = liquid), `hopStatus` (uint8, 1 = active, 2 = completed/canceled), `maxIterations` (uint256, max iterations), `timestamp` (uint256, execution timestamp), `feeAmount` (uint256, 0.05% fee in input token), `impactPricePercents` (uint256[], price impact percents), `multiHopId` (uint256, hop ID from `IMultihopper`).
- **ChronoHopPrepData**: Includes `hopId` (uint256, unique hop ID), `indices` (uint256[], listing indices), `isBuy` (bool[], buy/sell flags set by `IMultihopper`), `currentToken` (address, input token), `principal` (uint256, input amount after fee), `timestamp` (uint256, execution timestamp), `feeAmount` (uint256, 0.05% fee), `impactPricePercents` (uint256[], price impact percents), `maker` (address, hop initiator).
- **ChronoHopOrderDetails**: Contains `pending` (uint256, pending amount in input token), `filled` (uint256, filled amount in input token), `status` (uint8, order status: 1 = active, 2 = partially filled, 3 = completed), `amountSent` (uint256, amount sent in output token), `recipient` (address, recipient of output tokens).
- **ChronoHopRouteData**: Includes `listings` (address[], ordered listing addresses), `isBuy` (bool[], buy/sell flags for each listing).

## Formulas
- **Normalized Amount**:
  - **Formula**: `normalizedAmount = amount / (10 ** decimals)` (for `decimals <= 18`).
  - **Used in**: `normalizeForToken`, `executeChronoHop`.
  - **Description**: Normalizes token amounts to a common precision.
- **Denormalized Amount**:
  - **Formula**: `rawAmount = normalizedAmount * (10 ** decimals)` (for `decimals <= 18`).
  - **Used in**: `denormalizeForToken`, `executeChronoHop`, `processChronoHopStep`, `cancelChronoHop`, `cancelAll`.
  - **Description**: Converts normalized amounts to token-specific decimals.
- **Fee Calculation**:
  - **Formula**: `feeAmount = (principal * FEE_BASIS_POINTS) / 10000`, where `FEE_BASIS_POINTS = 5` (0.05%).
  - **Used in**: `computeTokens`, `executeChronoHop`.
  - **Description**: Calculates the fee deducted from the input amount.

## External Functions

### setMultiHopper(address multiHopper)
- **Parameters**:
  - `multiHopper` (address): `IMultihopper` contract address.
- **Behavior**: Sets the `_multiHopper` address for swap execution, emitting `MultiHopperSet`.
- **Internal Call Flow**:
  - Validates `multiHopper != address(0)`.
  - Assigns to `_multiHopper`.
  - No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_multiHopper`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `multiHopper` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### multiHopperView()
- **Parameters**: None.
- **Behavior**: Returns the `_multiHopper` address.
- **Internal Call Flow**: Direct access to `_multiHopper`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_multiHopper`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### chronoHop(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations, address maker)
- **Parameters**:
  - `listing1`–`listing4` (address): Listing contracts (listing2–4 optional, set to `address(0)` if unused).
  - `impactPercent` (uint256): Max price impact (scaled to 1000, e.g., 500 = 5%), applied to all listings.
  - `startToken` (address): Input token.
  - `endToken` (address): Output token.
  - `settleType` (uint8): 0 = market, 1 = liquid.
  - `maxIterations` (uint256): Max settlement iterations.
  - `maker` (address): Hop initiator (`msg.sender` if `address(0)`).
- **Behavior**: Initiates a time-based multi-step token swap, storing hop data in `chronoHopID` and deferring execution to `continueChronoHop` or `executeHops` until `timestamp` is reached, emitting `ChronoHopStarted`.
- **Internal Call Flow**:
  - Calls `prepChronoHop` to validate `listing1` and `timestamp`, compute listings (`computeListings`), tokens (`computeTokens`), and hop settings (`computeHopSettings`).
  - `executeChronoHop` performs balance checks via `_checkTransfer`, calculates fees, and stores hop data via `initializeChronoHopData`.
  - Transfer destinations: Contract for input tokens (via `IERC20.safeTransferFrom` or native currency), `maker` for fee refunds on cancellation.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(this)` or `address(this).balance` before transfer.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms transfer in `_checkTransfer`.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`, `chronoHopsByAddress`, `totalChronoHops`, `nextChronoHopId`, `isChronoHop`.
  - **Structs**: `ChronoHopPrepData`, `StalledChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing(listing1)`.
  - Reverts if `listing1` is zero, `timestamp < block.timestamp`, or principal is too low for fee.
- **Gas Usage Controls**: Pop-and-swap for arrays, single-element updates, optimized call tree.

### continueChronoHop(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process.
- **Behavior**: Continues stalled hops for `msg.sender` if `block.timestamp >= timestamp`, processing up to `maxIterations` via `IMultihopper.hop`, paying the 0.05% fee to `msg.sender`, emitting `ChronoHopContinued` and `FeePaid`.
- **Internal Call Flow**:
  - Iterates `chronoHopsByAddress` via `processChronoHopStep`.
  - Approves tokens via `IERC20.safeApprove`, calls `IMultihopper.hop` with try-catch, updates `chronoHopID.multiHopId`, and pays fees to `msg.sender`.
  - Updates `chronoHopsByAddress` and `totalChronoHops` using pop-and-swap if completed.
  - Transfer destinations: `IMultihopper` for input tokens, `msg.sender` for fee payments.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(multiHopper)` or `address(multiHopper).balance` in `_checkTransfer`.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`, `chronoHopsByAddress`, `totalChronoHops`.
  - **Structs**: `StalledChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0` or `_multiHopper` is not set.
- **Gas Usage Controls**: Bounded by `maxIterations`, pop-and-swap for arrays.

### executeHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process.
- **Behavior**: Processes all stalled hops globally if `block.timestamp >= timestamp`, up to `maxIterations` via `IMultihopper.hop`, paying the 0.05% fee to `msg.sender`, emitting `ChronoHopContinued` and `FeePaid`.
- **Internal Call Flow**:
  - Iterates `totalChronoHops` via `processChronoHopStep`, mirroring `continueChronoHop`.
  - Updates `chronoHopID`, `chronoHopsByAddress`, and `totalChronoHops` if completed.
  - Transfer destinations: `IMultihopper` for input tokens, `msg.sender` for fee payments.
- **Balance Checks**:
  - Same as `continueChronoHop`.
- **Mappings/Structs Used**:
  - Same as `continueChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0` or `_multiHopper` is not set.
- **Gas Usage Controls**: Same as `continueChronoHop`.

### cancelChronoHop(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID to cancel.
- **Behavior**: Cancels a stalled hop, refunding `principalAmount` plus `feeAmount` in the input token to the hop maker, emitting `ChronoHopCanceled`.
- **Internal Call Flow**:
  - Validates `hopMaker == msg.sender` and `hopStatus == 1`.
  - Refunds via `IERC20.safeTransfer` or native currency transfer, using `_checkTransfer` for balance checks.
  - Updates `chronoHopID.hopStatus` to 2, removes from `chronoHopsByAddress` using pop-and-swap.
  - Transfer destinations: `msg.sender` for refunds.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(this)` or `address(this).balance` before refund.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms refund transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`, `chronoHopsByAddress`.
  - **Structs**: `StalledChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if not hop maker or `hopStatus != 1`.
- **Gas Usage Controls**: Single hop processing, pop-and-swap for arrays.

### cancelAll(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to cancel.
- **Behavior**: Cancels up to `maxIterations` stalled hops for `msg.sender`, refunding `principalAmount` plus `feeAmount` in the input token per hop, emitting `ChronoHopCanceled` and `AllChronoHopsCanceled`.
- **Internal Call Flow**:
  - Iterates `chronoHopsByAddress`, calling `cancelChronoHop` logic for `hopStatus == 1` hops.
  - Transfer destinations: `msg.sender` for refunds.
- **Balance Checks**:
  - Same as `cancelChronoHop`.
- **Mappings/Structs Used**:
  - Same as `cancelChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: Bounded by `maxIterations`, pop-and-swap for arrays.

### chronoHopStatusView(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns `chronoHopID[hopId].hopStatus` (1 = active, 2 = completed/canceled).
- **Internal Call Flow**: Direct access to `chronoHopID`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`.
  - **Structs**: `StalledChronoHop`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getChronoHopDetails(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns the full `StalledChronoHop` struct for a given `hopId` from `chronoHopID`, including stage, listings, tokens, and fees.
- **Internal Call Flow**: Direct access to `chronoHopID`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`.
  - **Structs**: `StalledChronoHop`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getUserChronoHops(address user)
- **Parameters**:
  - `user` (address): User address.
- **Behavior**: Returns the array of hop IDs for a given user from `chronoHopsByAddress`.
- **Internal Call Flow**: Direct access to `chronoHopsByAddress`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopsByAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getChronoHopOrderDetails(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns order details (`pending`, `filled`, `status`, `amountSent`, `recipient`) for the current hop by calling `IMultihopper.getHopOrderDetails` with `chronoHopID[hopId].multiHopId`.
- **Internal Call Flow**: Accesses `chronoHopID`, calls `IMultihopper.getHopOrderDetails`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`.
  - **Structs**: `StalledChronoHop`, `ChronoHopOrderDetails`.
- **Restrictions**: Reverts if `_multiHopper` is not set.
- **Gas Usage Controls**: View function, single external call, low gas.

### getChronoHopRoute(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns the ordered list of listing addresses and `isBuy` flags for a hop by calling `IMultihopper.getHopRoute` with `chronoHopID[hopId].multiHopId`.
- **Internal Call Flow**: Accesses `chronoHopID`, calls `IMultihopper.getHopRoute`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`.
  - **Structs**: `StalledChronoHop`, `ChronoHopRouteData`.
- **Restrictions**: Reverts if `_multiHopper` is not set.
- **Gas Usage Controls**: View function, single external call, low gas.

### getContractBalance(address token)
- **Parameters**:
  - `token` (address): Token address (or `address(0)` for native currency).
- **Behavior**: Returns the contract’s balance of a specified token (or native currency) using `IERC20.balanceOf` or `address(this).balance`.
- **Internal Call Flow**: Queries `IERC20.balanceOf` or `address(this).balance`. No transfers or state changes.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, single external call, minimal gas.

## Additional Details
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap for array resizing, and an internal call tree (`computeListings`, `computeTokens`, `computeHopSettings`) to minimize stack usage.
- **Token Flow**: Managed by `IMultihopper`, with `ChronoHopper` handling input token transfers and fee payments to callers.
- **Hop Lifecycle**: Initiated or active (`hopStatus = 1`), completed or canceled (`hopStatus = 2`), cancellable if active and `timestamp` not yet reached.
- **Events**: Emitted for hop start (`ChronoHopStarted`), continuation (`ChronoHopContinued`), cancellation (`ChronoHopCanceled`, `AllChronoHopsCanceled`), fee payment (`FeePaid`), and `IMultihopper` setting (`MultiHopperSet`).
- **Safety**: Explicit casting, balance checks, no inline assembly, and minimal validation ensure secure operation.
- **Stack Optimization**: The internal call tree splits `prepChronoHop` to avoid stack-too-deep errors, processing parameters incrementally in a single transaction.