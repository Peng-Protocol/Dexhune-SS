# ChronoHopper Contract Documentation

## Overview
The `ChronoHopper` contract, implemented in Solidity (^0.8.2), facilitates time-based multi-step token swaps across up to four listings, supporting market and liquid order settlements with price impact controls and timestamp-based execution. It integrates with `ISSListing`, `ISSRouter`, and `ISSAgent` interfaces, uses `SafeERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract manages hop creation, execution, continuation, and cancellation, with gas optimization, robust decimal handling, and a 0.05% fee in the input token. State variables are hidden, accessed via view functions, and mappings ensure efficient hop tracking.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.44 (last updated 2025-07-04)

**Compatible Contracts:**
- `SSRouter` v0.0.61
- `HopPartial` v0.0.58

## Clarifications
- **Path-Finding Mechanism**: `ChronoHopper` uses `computeRoute` in `prepChronoHop` to precompute a valid token path by fetching `tokenA` and `tokenB` from each listing, ensuring `startToken` connects through intermediate tokens to `endToken` before execution, reverting early if no valid path exists.
- **Usage of amountSent**: The `amountSent` field in `StallData` captures the output token amount from a completed or partially executed hop step, used as the `principalAmount` input for the next hop in `executeStalls` and `processChronoHopStep`, ensuring accurate token flow across multi-step swaps.
- **Usage of filled**: The `filled` field in `StallData` tracks the amount of input token settled in a hop step, starting at zero if no settlement occurs, and is refunded in the input token via `_handleFilledOrSent` during cancellation if `amountSent` is zero.
- **Field Conflicts with SSListingTemplate**: The `SSListingTemplate` contract’s order structs (e.g., `BuyOrder`, `SellOrder`) also define `filled` (input token processed) and `amountSent` (output token transferred), but `ChronoHopper` avoids conflicts by explicitly mapping `ISSListing.getBuyOrderAmounts` or `getSellOrderAmounts` results to `StallData` fields, ensuring distinct usage.
- **Listing Validation**: The `onlyValidListing` modifier in the `hop` function only validates `listing1`, but `validateChronoHopRequest`, called within `prepChronoHop` before hop initiation, validates all non-zero listings (`listing1` to `listing4`) via `ISSAgent.getListing`, sufficiently preventing attacks from malicious or unverified listing contracts.
- **Hop Cancellation Refunds**: Hop cancellation accurately refunds any amount pending or partially settled; for intermediate hops, both `pending` (e.g., 25 TokenA) in the input token and `amountSent` (e.g., 100 TokenB) in the output token are refunded to the hop maker via `_clearHopOrder` and `_handleFilledOrSent`, while for end hops, only `pending` plus `feeAmount` is refunded via `_handlePending` if `amountSent` was already received by the hop maker (per `computeBaseOrderParams`), ensuring no duplicate refunds.
- **Balance Checks**: The contract implements pre/post balance checks in `_checkTransfer` to verify token transfers by comparing balances before and after, returning the actual amount transferred (`balanceAfter - balanceBefore`) for use in `_createHopOrder` and `processBalanceData`, ensuring accurate tracking for both native currency and ERC20 tokens with proper normalization via `denormalizeForToken`.
- **Fee Handling**: A 0.05% fee is deducted from the input amount in `prepChronoHop`, tracked in `StalledChronoHop.feeAmount`, paid in `processChronoHopStep` if the hop completes, and refunded in `_handlePending` during cancellation.
- **Timestamp-Based Execution**: Hops are stalled until `block.timestamp >= StalledChronoHop.timestamp`, checked in `prepStalls` and `prepAllStalls`, enabling time-based execution.
-**Single Listing Route**: If a route has only one listing specified, with others zeroed, `validateChronoHopRequest` ensures `listing1` is valid, `computeRoute` verifies `startToken` and `endToken` match the listing’s token pair, and the hop executes as a single-step swap if `block.timestamp >= timestamp`, with a 0.05% fee applied.

## State Variables
- **nextChronoHopId** (uint256, private): Tracks the next hop ID for unique identification of hop requests.
- **_routers** (RouterInfo[], private): Array storing router addresses and types (1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver).
- **_agent** (address, private): Stores the ISSAgent contract address for listing validation.
- **totalChronoHops** (uint256[], private): Global list of hop IDs.
- **chronoHopsByAddress** (mapping(address => uint256[]), private): Maps maker addresses to their hop IDs.
- **chronoHopID** (mapping(uint256 => StalledChronoHop), private): Stores hop details by hop ID.
- **isChronoHop** (mapping(uint256 => bool), private): Flags time-based hops.

## Structs
- **RouterInfo**: Contains `router` (address, router contract), `routerType` (uint8, 1–3 for SSRouter, SSCrossDriver, SSIsolatedDriver).
- **ChronoHopUpdateType**: Includes `field` (string, update field like "status", "buyAmount"), `value` (uint256, update value or address cast).
- **ChronoHopRequest**: Holds `numListings` (uint256, number of listings), `listingAddresses` (address[], up to 4 listings), `impactPricePercents` (uint256[], price impact percents), `startToken` (address, input token), `endToken` (address, output token), `settleType` (uint8, 0 = market, 1 = liquid), `maxIterations` (uint256, max settlement iterations), `timestamp` (uint256, execution timestamp).
- **StalledChronoHop**: Tracks `stage` (uint8, current hop stage), `currentListing` (address, active listing), `orderID` (uint256, current order ID), `minPrice` (uint256, min price for sell), `maxPrice` (uint256, max price for buy), `hopMaker` (address, hop initiator), `remainingListings` (address[], remaining listings), `principalAmount` (uint256, current input amount), `startToken` (address, input token), `endToken` (address, output token), `settleType` (uint8, settlement type), `hopStatus` (uint8, 1 = stalled, 2 = completed), `maxIterations` (uint256, max iterations), `timestamp` (uint256, execution timestamp), `feeAmount` (uint256, 0.05% fee in input token), `impactPricePercents` (uint256[], price impact percents).
- **StallData**: Stores `hopId` (uint256), `listing` (address), `orderId` (uint256), `isBuy` (bool), `pending` (uint256, pending amount), `filled` (uint256, filled amount), `status` (uint8, order status), `amountSent` (uint256, amount sent), `hopMaker` (address), `timestamp` (uint256, execution timestamp), `feeAmount` (uint256, fee amount), `impactPercent` (uint256, impact percent for current step).
- **ChronoHopPrepData**: Includes `hopId` (uint256), `indices` (uint256[], listing indices), `isBuy` (bool[], buy/sell flags), `currentToken` (address, current token), `principal` (uint256, input amount after fee), `timestamp` (uint256, execution timestamp), `feeAmount` (uint256, 0.05% fee), `impactPricePercents` (uint256[], price impact percents).
- **ChronoHopExecutionData**: Contains `listing` (address), `isBuy` (bool), `recipient` (address), `priceLimit` (uint256, normalized price limit), `principal` (uint256, denormalized input), `inputToken` (address), `settleType` (uint8), `maxIterations` (uint256), `updates` (ChronoHopUpdateType[], order updates), `feeAmount` (uint256, fee amount), `impactPercent` (uint256, impact percent for current step).
- **StallExecutionData**: Mirrors `ChronoHopExecutionData` with `listing`, `isBuy`, `recipient`, `priceLimit`, `principal`, `settleType`, `maxIterations`, `updates`, `feeAmount`, `impactPercent`.
- **CancelPrepData**: Includes `hopId` (uint256), `listing` (address), `isBuy` (bool), `outputToken` (address), `inputToken` (address), `pending` (uint256), `filled` (uint256), `status` (uint8), `receivedAmount` (uint256), `recipient` (address), `feeAmount` (uint256).
- **CancelBalanceData**: Tracks `token` (address), `balanceBefore` (uint256), `balanceAfter` (uint256).
- **OrderUpdateData**: Holds `listing` (address), `recipient` (address), `inputAmount` (uint256, normalized), `priceLimit` (uint256, normalized), `inputToken` (address).
- **ChronoHopExecutionParams**: Contains `listingAddresses` (address[], up to 4 listings), `impactPricePercents` (uint256[], price impact percents), `startToken` (address, input token), `endToken` (address, output token), `settleType` (uint8, 0 = market, 1 = liquid), `maxIterations` (uint256, max iterations), `numListings` (uint256, number of listings), `timestamp` (uint256, execution timestamp).
- **OrderParams**: Contains `listing` (address), `principal` (uint256, input amount), `impactPercent` (uint256, scaled to 1000), `index` (uint256, route index), `numListings` (uint256), `maxIterations` (uint256), `settleType` (uint8), `timestamp` (uint256).
- **ChronoHopRouteData**: Contains `listings` (address[], ordered listing addresses), `isBuy` (bool[], buy/sell flags for each listing).
- **ChronoHopOrderDetails**: Includes `pending` (uint256, pending amount in input token), `filled` (uint256, filled amount in input token), `status` (uint8, order status: 1 = active, 2 = partially filled, 3 = completed), `amountSent` (uint256, amount sent in output token), `recipient` (address, recipient of output tokens), `feeAmount` (uint256, fee amount).

## Formulas
1. **Price Impact**:
   - **Formula**: `impactPrice = (newXBalance * 1e18) / newYBalance`, where `newXBalance = xBalance ± amountOut`, `newYBalance = yBalance ± inputAmount` (based on buy/sell).
   - **Used in**: `_validatePriceImpact`, `computeBuyOrderParams`, `computeSellOrderParams`.
   - **Description**: Calculates price after trade, ensuring it stays within `currentPrice * (10000 ± impactPercent) / 10000`.

2. **Amount Out**:
   - **Formula**: `amountOut = isBuy ? (inputAmount * xBalance) / yBalance : (inputAmount * yBalance) / xBalance`.
   - **Used in**: `_validatePriceImpact`.
   - **Description**: Computes output amount based on input and pool balances.

3. **Normalized Amount**:
   - **Formula**: `normalizedAmount = amount / (10 ** decimals)` (for `decimals <= 18`).
   - **Used in**: `normalizeForToken`, `computeBaseOrderParams`.
   - **Description**: Normalizes token amounts to a common precision.

4. **Denormalized Amount**:
   - **Formula**: `rawAmount = normalizedAmount * (10 ** decimals)` (for `decimals <= 18`).
   - **Used in**: `denormalizeForToken`, `computeBaseOrderParams`, `_createHopOrder`.
   - **Description**: Converts normalized amounts to token-specific decimals.

5. **Fee Calculation**:
   - **Formula**: `feeAmount = (principal * FEE_BASIS_POINTS) / 10000`, where `FEE_BASIS_POINTS = 5` (0.05%).
   - **Used in**: `prepChronoHop`.
   - **Description**: Calculates the fee deducted from the input amount.

## External Functions

### addRouter(address router, uint8 routerType)
- **Parameters**:
  - `router` (address): Router contract address.
  - `routerType` (uint8): 1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver.
- **Behavior**: Adds or updates a router in `_routers`, ensuring no duplicate addresses with different types. Emits `RouterAdded`.
- **Internal Call Flow**:
  - Validates `router != address(0)`, `routerType` is 1–3.
  - Checks `_routers` for existing router or type conflicts.
  - Updates or pushes to `_routers`.
  - No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers`.
  - **Structs**: `RouterInfo`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `router` is zero, `routerType` is invalid, or router address conflicts.
- **Gas Usage Controls**: Single array push or update, minimal gas.

### removeRouter(address router)
- **Parameters**:
  - `router` (address): Router to remove.
- **Behavior**: Removes a router from `_routers` using pop-and-swap. Emits `RouterRemoved`.
- **Internal Call Flow**:
  - Iterates `_routers` to find and remove `router`.
  - No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers`.
  - **Structs**: `RouterInfo`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `router` not found.
- **Gas Usage Controls**: Pop-and-swap minimizes gas.

### setAgent(address agent)
- **Parameters**:
  - `agent` (address): ISSAgent contract address.
- **Behavior**: Sets `_agent` for listing validation. Emits `AgentSet`.
- **Internal Call Flow**:
  - Validates `agent != address(0)`.
  - Assigns to `_agent`.
  - No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_agent`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `agent` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### hop(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations, uint256 timestamp)
- **Parameters**:
  - `listing1`–`listing4` (address): Listing contracts (listing2–4 optional, set to address(0) if unused).
  - `impactPercent` (uint256): Max price impact (scaled to 1000, e.g., 500 = 5%), applied to all listings.
  - `startToken` (address): Input token.
  - `endToken` (address): Output token.
  - `settleType` (uint8): 0 = market, 1 = liquid.
  - `maxIterations` (uint256): Max settlement iterations.
  - `timestamp` (uint256): Execution timestamp (must be >= `block.timestamp`).
- **Behavior**: Initiates a time-based multi-step token swap, creating orders across listings, settling via routers if `timestamp` is reached, and tracking progress in `chronoHopID`. Emits `ChronoHopStarted`.
- **Internal Call Flow**:
  - Calls `prepChronoHop` to validate inputs, compute route (`computeRoute` returns `indices`, `isBuy`), and calculate 0.05% fee.
  - `prepareChronoHopExecution` builds `ChronoHopExecutionParams`, calls `initializeChronoHopData` to store in `chronoHopID`.
  - `executeChronoHopSteps`:
    - Stores hop data in `chronoHopID`, deferring execution to `continueHop` or `executeHops`.
    - If `timestamp <= block.timestamp`, iterates route, calling `computeBuyOrderParams` or `computeSellOrderParams`.
    - `_createHopOrder` transfers `inputAmount` to listing via `IERC20.safeTransferFrom` (input: `msg.sender`, `listing`, `rawAmount`, returns: `bool`), with balance checks via `_checkTransfer`.
    - `safeSettle` calls `ISSRouter.settleBuyOrders`/`settleSellOrders` or `settleBuyLiquid`/`settleSellLiquid` (input: `listing`, `maxIterations`, returns: none).
    - `checkOrderStatus` retrieves order details via `ISSListing.getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, `getSellOrderAmounts`.
    - Updates `chronoHopID`, `chronoHopsByAddress`, `totalChronoHops` if stalled or completed.
  - Transfer destinations: Listings for input tokens, `msg.sender` or contract for outputs, `msg.sender` for fee refunds on completion.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(listing)` or `address(listing).balance` before transfer.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers`, `chronoHopID`, `chronoHopsByAddress`, `totalChronoHops`, `nextChronoHopId`, `isChronoHop`.
  - **Structs**: `ChronoHopPrepData`, `ChronoHopExecutionParams`, `ChronoHopExecutionData`, `OrderParams`, `OrderUpdateData`, `ChronoHopUpdateType`, `StalledChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing(listing1)`.
  - Reverts if `numListings` is 0 or > 4, `maxIterations` is 0, `impactPercent > 1000`, `timestamp < block.timestamp`, listings are invalid, or route doesn’t reach `endToken`.
- **Gas Usage Controls**: `maxIterations`, pop-and-swap for arrays, single-element updates.

### continueHop(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process.
- **Behavior**: Continues stalled hops for `msg.sender` if `block.timestamp >= timestamp`, processing up to `maxIterations`. Emits `ChronoHopContinued`, `StallsPrepared`, `StallsExecuted`.
- **Internal Call Flow**:
  - Iterates `chronoHopsByAddress` via `prepStalls` (up to 20 hops), retrieving `StallData` using `checkOrderStatus` if `timestamp` is reached.
  - `executeStalls`:
    - Checks order completion (`status == 3`, `pending == 0`).
    - Advances `chronoHopID.stage`, creates new orders via `_createHopOrder`, settles via `safeSettle`, updates `chronoHopID.remainingListings`.
    - Refunds `feeAmount` via `_handlePending` if hop completes.
    - Updates `chronoHopsByAddress`, `totalChronoHops` if completed.
  - Transfer destinations: Listings for inputs, `msg.sender` or contract for outputs, `msg.sender` for fee refunds.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(listing)` or `address(listing).balance` in `_createHopOrder`.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` in `_checkTransfer`.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`, `chronoHopsByAddress`, `totalChronoHops`.
  - **Structs**: `StallData`, `StallExecutionData`, `ChronoHopUpdateType`, `OrderUpdateData`, `StalledChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: `maxIterations`, capped at 20 stalls, pop-and-swap for arrays.

### executeHops(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max iterations for processing hops.
- **Behavior**: Processes all stalled hops globally if `block.timestamp >= timestamp`, up to `maxIterations`. Emits `StallsPrepared`, `StallsExecuted`, `ChronoHopContinued`.
- **Internal Call Flow**:
  - Iterates `totalChronoHops` via `prepAllStalls` (up to 20 hops), retrieving `StallData` if `timestamp` is reached.
  - `executeStalls` mirrors `continueHop`, processing orders and updating `chronoHopID`, `chronoHopsByAddress`, `totalChronoHops`.
  - Transfer destinations: Listings for inputs, `msg.sender` or contract for outputs, `msg.sender` for fee refunds.
- **Balance Checks**:
  - Same as `continueHop`.
- **Mappings/Structs Used**:
  - Same as `continueHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: Same as `continueHop`.

### cancelChronoHop(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID to cancel.
- **Behavior**: Cancels a stalled hop, refunding `amountSent` (if non-zero and not yet received) in the output token or `filled` in the input token via `_handleFilledOrSent`, and `pending` plus `feeAmount` in the input token (e.g., 25 TokenA for 25 TokenA unsettled from 50 TokenA sent) via `_handlePending` to the hop maker; for end hops, only `pending` plus `feeAmount` is refunded if `amountSent` (e.g., 100 TokenB) was already received by the hop maker. Emits `ChronoHopCanceled`.
- **Internal Call Flow**:
  - Calls `_prepCancelChronoHopBuy` or `_prepCancelChronoHopSell` based on `chronoHopID.maxPrice`.
  - `_clearHopOrder` updates `ISSListing.update` (input: `ChronoHopUpdateType[]` for status, returns: none), checks balances via `IERC20.balanceOf` or `address(this).balance`.
  - `_handleFilledOrSent` refunds `amountSent` (if non-zero and not yet received) in output token or `filled` in input token, `_handlePending` refunds `pending` plus `feeAmount` in input token to `msg.sender`.
  - `_finalizeCancel` updates `chronoHopID.hopStatus` to 2 (completed), removes from `chronoHopsByAddress`.
  - Transfer destinations: `msg.sender` for refunds.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(this)` or `address(this).balance` before cancellation.
  - **Post-Balance Check**: `balanceAfter > balanceBefore` confirms refund transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`, `chronoHopsByAddress`.
  - **Structs**: `CancelPrepData`, `CancelBalanceData`, `ChronoHopUpdateType`, `StalledChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if not hop maker, `hopStatus != 1`, or order not cancellable.
- **Gas Usage Controls**: Single hop processing, pop-and-swap for arrays.

### cancelAll(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max hops to cancel.
- **Behavior**: Cancels up to `maxIterations` stalled hops for `msg.sender`, refunding `amountSent` (if non-zero and not yet received) in the output token or `filled` in the input token, and `pending` plus `feeAmount` in the input token (e.g., 25 TokenA for 25 TokenA unsettled from 50 TokenA sent) for each hop; for end hops, only `pending` plus `feeAmount` is refunded if `amountSent` (e.g., 100 TokenB) was already received. Emits `AllChronoHopsCanceled`.
- **Internal Call Flow**:
  - Iterates `chronoHopsByAddress`, calling `_cancelChronoHop` for `hopStatus == 1` hops.
  - Transfer destinations: `msg.sender` for refunds.
- **Balance Checks**:
  - Same as `cancelChronoHop`.
- **Mappings/Structs Used**:
  - Same as `cancelChronoHop`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: `maxIterations`, pop-and-swap for arrays.

### getRouters()
- **Parameters**: None.
- **Behavior**: Returns `_routers` array.
- **Internal Call Flow**: Direct access to `_routers`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers`.
  - **Structs**: `RouterInfo`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### agentView()
- **Parameters**: None.
- **Behavior**: Returns `_agent` address.
- **Internal Call Flow**: Direct access to `_agent`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_agent`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### chronoHopStatusView(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns `chronoHopID[hopId].hopStatus`.
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
- **Behavior**: Returns the full `StalledChronoHop` struct for a given `hopId` from the `chronoHopID` mapping to provide detailed hop information, including stage, current listing, order ID, token details, timestamp, and fee amount.
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
- **Behavior**: Returns the array of hop IDs for a given user from `chronoHopsByAddress` to track all hops initiated by a specific address.
- **Internal Call Flow**: Direct access to `chronoHopsByAddress`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopsByAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getTotalChronoHopsCount()
- **Parameters**: None.
- **Behavior**: Returns the length of the `totalChronoHops` array to provide a count of all hops ever created.
- **Internal Call Flow**: Direct access to `totalChronoHops`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `totalChronoHops`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getActiveChronoHopsCount(address user)
- **Parameters**:
  - `user` (address): User address.
- **Behavior**: Returns the count of stalled hops (`hopStatus == 1`) for a given user by iterating `chronoHopsByAddress[user]` to assist in managing active trades.
- **Internal Call Flow**: Iterates `chronoHopsByAddress` and checks `chronoHopID` for `hopStatus`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopsByAddress`, `chronoHopID`.
  - **Structs**: `StalledChronoHop`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, bounded iteration, minimal gas.

### getTotalPendingChronoHopsCount(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Max iterations to limit gas usage.
- **Behavior**: Returns the count of all stalled hops (`hopStatus == 1`) across all users by iterating `totalChronoHops`, limited by `maxIterations` for gas control, to provide a global view of pending trades.
- **Internal Call Flow**: Iterates `totalChronoHops` and checks `chronoHopID` for `hopStatus`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `totalChronoHops`, `chronoHopID`.
  - **Structs**: `StalledChronoHop`.
- **Restrictions**: Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: View function, bounded by `maxIterations`, minimal gas.

### getChronoHopOrderDetails(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns order details (`pending`, `filled`, `status`, `amountSent`, `recipient`, `feeAmount`) for the current order of a hop by calling `checkOrderStatus` on `chronoHopID[hopId].currentListing` and `orderID`.
- **Internal Call Flow**: Accesses `chronoHopID`, calls `ISSListing.getBuyOrderCore` or `getSellOrderCore` and `checkOrderStatus`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`.
  - **Structs**: `StalledChronoHop`, `ChronoHopOrderDetails`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal external calls, low gas.

### getChronoHopRoute(uint256 hopId)
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns the ordered list of listing addresses and their `isBuy` flags for a hop from `chronoHopID[hopId].remainingListings` and initial route data to analyze the token swap path.
- **Internal Call Flow**: Accesses `chronoHopID`, queries `ISSListing.tokenA` for `isBuy` determination. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopID`.
  - **Structs**: `StalledChronoHop`, `ChronoHopRouteData`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal external calls, low gas.

### getUserPendingVolume(address user, address token)
- **Parameters**:
  - `user` (address): User address.
  - `token` (address): Token address to query.
- **Behavior**: Returns the total `pending` amount in a specified token across all stalled hops for a user by iterating `chronoHopsByAddress` and calling `checkOrderStatus`.
- **Internal Call Flow**: Iterates `chronoHopsByAddress`, checks `chronoHopID` and `ISSListing` for input token and pending amounts. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `chronoHopsByAddress`, `chronoHopID`.
  - **Structs**: `StalledChronoHop`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, bounded iteration, moderate gas due to external calls.

### getContractBalance(address token)
- **Parameters**:
  - `token` (address): Token address (or address(0) for native currency).
- **Behavior**: Returns the contract’s balance of a specified token (or native currency) using `IERC20.balanceOf` or `address(this).balance`.
- **Internal Call Flow**: Queries `IERC20.balanceOf` or `address(this).balance`. No transfers or state changes.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, single external call, minimal gas.

## Additional Details
- **Decimal Handling**: Uses `normalizeForToken` and `denormalizeForToken` to handle token decimals (≤ 18), ensuring consistent calculations.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap for arrays, and caps stall processing at 20.
- **Listing Validation**: `validateChronoHopRequest` uses `ISSAgent.getListing` to verify listings, allowing `address(0)` for unused trailing listings, ensuring security despite `onlyValidListing` checking only `listing1`.
- **Token Flow**: Buy orders use `tokenB` input, `tokenA` output; sell orders use `tokenA` input, `tokenB` output.
- **Hop Lifecycle**: Initiated or stalled (`hopStatus = 1`), cancelled or completed (`hopStatus = 2`), cancellable if stalled and `timestamp` not yet reached.
- **Events**: Emitted for hop start (`ChronoHopStarted`), continuation (`ChronoHopContinued`), cancellation (`ChronoHopCanceled`, `AllChronoHopsCanceled`), stall preparation (`StallsPrepared`), execution (`StallsExecuted`), router changes (`RouterAdded`, `RouterRemoved`), agent setting (`AgentSet`), and fee payment (`FeePaid`).
- **Safety**: Explicit casting (e.g., `uint256(uint160())` for addresses), balance checks, no inline assembly, and robust validation ensure secure operation.
- **Price Impact**: Ensures trades stay within `impactPercent` (≤ 1000) of current price, preventing excessive slippage.
Impact price is calculated at the time of execution, not at hop creation. 
- **Fee Handling**: 0.05% fee deducted in `prepChronoHop`, paid on completion in `processChronoHopStep`, refunded on cancellation in `_handlePending`.

