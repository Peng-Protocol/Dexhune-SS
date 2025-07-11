

# Multihopper Contract Documentation

## Overview
The `Multihopper` contract, implemented in Solidity (^0.8.2), facilitates multi-step token swaps across up to four listings, supporting market and liquid order settlements with price impact controls. It integrates with `ISSListing`, `ISSRouter`, and `ISSAgent` interfaces, uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract is split into four files (`MHMain.sol`, `MHInit.sol`, `MHCtrl.sol`, `Multihopper.sol`) with an inheritance structure (`MHMain` → `MHInit` → `MHCtrl` → `Multihopper`) to reduce deployment overhead and improve modularity. It manages hop creation, execution, continuation, and cancellation, with gas optimization, robust decimal handling, and accurate refund tracking via the `refundedPending` field in `CancelPrepData`. State variables are internal, accessed via view functions, and mappings ensure efficient hop tracking.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.44 (last updated 2025-07-11)

**Compatible Contracts:**
- `SSRouter` v0.0.61
- `SSListingTemplate` v0.0.10

## Change Log
- **2025-07-11**: Split `Multihopper.sol` (v0.0.42) into `MHMain.sol` (structs, interfaces, mappings), `MHInit.sol` (helpers), `MHCtrl.sol` (cancellation, views), and `Multihopper.sol` (core logic) with inheritance to reduce overhead.
- **2025-07-11**: Removed `SafeERC20` import across files, replaced with `IERC20` import from `../imports/IERC20.sol`, using `IERC20.transferFrom` and `IERC20.approve` for token operations.
- **2025-07-11**: Added `refundedPending` field to `CancelPrepData` to track actual refunded pending amount after transfer taxes in cancellations.
- **2025-07-11**: Fixed TypeError in `MHInit.sol` by replacing `IERC20.safeTransferFrom` with `IERC20.transferFrom` in `_checkTransfer`.
- **2025-07-11**: Updated import paths to `../imports/` for consistency.
- **2025-07-11**: Confirmed `nonReentrant` modifier inherited correctly via `ReentrancyGuard` from `MHMain.sol`.
- **2025-07-06 and earlier**: Extended `CancelPrepData`, optimized stack, added `maker` parameter, added view functions, fixed typos.

## Clarifications
- **Path-Finding Mechanism**: The `computeRoute` function in `MHInit.sol` precomputes a valid token path by fetching `tokenA` and `tokenB` from each listing, ensuring `startToken` connects to `endToken` via intermediate tokens, reverting early if no valid path exists.
- **Usage of amountSent**: The `amountSent` field in `StallData` captures the output token amount from a completed or partially executed hop step, used as the `principal` for the next hop in `executeStalls` and `processHopStep`, ensuring accurate token flow across multi-step swaps.
- **Usage of filled**: The `filled` field in `StallData` tracks the settled input token amount, starting at zero if no settlement occurs, and is refunded in the input token via `_handleFilledOrSent` during cancellation if `amountSent` is zero.
- **Field Conflicts with SSListingTemplate**: The `SSListingTemplate` contract’s `BuyOrder` and `SellOrder` structs define `filled` (processed input token) and `amountSent` (transferred output token), but `Multihopper` avoids conflicts by mapping `ISSListing.getBuyOrderAmounts` or `getSellOrderAmounts` results to `StallData` fields explicitly.
- **Listing Validation**: The `onlyValidListing` modifier in `Multihopper.sol` validates `listing1`, while `validateHopRequest` in `MHInit.sol` checks all non-zero listings (`listing1` to `listing4`) via `ISSAgent.getListing`, ensuring protection against malicious or unverified contracts.
- **Hop Cancellation Refunds**: Cancellation refunds `pending` in the input token (e.g., 25 TokenA unsettled from 50 TokenA sent) via `_handlePending`, `amountSent` (e.g., 100 TokenB, if non-zero and not yet received) or `filled` in the output token via `_handleFilledOrSent` for intermediate hops, and only `pending` for end hops if `amountSent` was already received by the hop maker (per `computeBaseOrderParams`). The `refundedPending` field in `CancelPrepData` tracks the actual refunded pending amount after transfer taxes, updating `hopID.principalAmount` for accuracy.
- **Balance Checks**: `_checkTransfer` in `MHInit.sol` verifies token transfers by comparing pre/post balances (`balanceAfter > balanceBefore`), returning the actual transferred amount for `_createHopOrder`, `_handlePending`, and `_handleBalance`, supporting both native currency and ERC20 tokens with normalization via `normalizeForToken` and `denormalizeForToken`.
- **Single Listing Route**: For a single listing, `validateHopRequest` ensures `listing1` is valid, `computeRoute` verifies `startToken` and `endToken` match the listing’s token pair, and the hop executes as a single-step swap.
- **maxIterations Usage**: In `hop`, `maxIterations` is stored in `StalledHop` and used in `safeSettle` to limit settlement attempts (`settleBuyOrders`, `settleSellOrders`, `settleBuyLiquid`, `settleSellLiquid`). In `continueHop` and `executeHops`, a separate `maxIterations` limits hop processing, resetting per call, while `StalledHop.maxIterations` persists for settlement attempts until the hop completes or is cancelled.
- **File Split and Inheritance**: The contract is split into `MHMain.sol` (structs, interfaces, state), `MHInit.sol` (helpers), `MHCtrl.sol` (cancellation, views), and `Multihopper.sol` (core logic), with inheritance (`MHMain` → `MHInit` → `MHCtrl` → `Multihopper`) ensuring access to state and functions without duplication, reducing deployment gas costs.
- **SafeERC20 Removal**: Replaced `SafeERC20` with `IERC20` imports, using `IERC20.transferFrom` and `IERC20.approve` in `_createHopOrder`, `_handleFilledOrSent`, `_handlePending`, and `_checkTransfer`, maintaining safety with explicit balance checks and reducing external dependencies.

## State Variables
- **nextHopId** (uint256, internal, `MHMain.sol`): Tracks the next hop ID for unique identification of hop requests.
- **_routers** (RouterInfo[], internal, `MHMain.sol`): Array storing router addresses and types (1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver).
- **_agent** (address, internal, `MHMain.sol`): Stores the ISSAgent contract address for listing validation.
- **totalHops** (uint256[], internal, `MHMain.sol`): Global list of hop IDs.
- **hopsByAddress** (mapping(address => uint256[]), internal, `MHMain.sol`): Maps maker addresses to their hop IDs.
- **hopID** (mapping(uint256 => StalledHop), internal, `MHMain.sol`): Stores hop details by hop ID.

## Structs
- **RouterInfo** (`MHMain.sol`): Contains `router` (address, router contract), `routerType` (uint8, 1–3 for SSRouter, SSCrossDriver, SSIsolatedDriver).
- **HopUpdateType** (`MHMain.sol`): Includes `field` (string, e.g., "status", "buyAmount"), `value` (uint256, update value or address cast).
- **HopRequest** (`MHMain.sol`): Holds `numListings` (uint256), `listingAddresses` (address[], up to 4), `impactPricePercents` (uint256[]), `startToken` (address), `endToken` (address), `settleType` (uint8, 0 = market, 1 = liquid), `maxIterations` (uint256).
- **StalledHop** (`MHMain.sol`): Tracks `stage` (uint8), `currentListing` (address), `orderID` (uint256), `minPrice` (uint256, for sell), `maxPrice` (uint256, for buy), `hopMaker` (address), `remainingListings` (address[]), `principalAmount` (uint256), `startToken` (address), `endToken` (address), `settleType` (uint8), `hopStatus` (uint8, 1 = stalled, 2 = completed), `maxIterations` (uint256).
- **StallData** (`MHMain.sol`): Stores `hopId` (uint256), `listing` (address), `orderId` (uint256), `isBuy` (bool), `pending` (uint256), `filled` (uint256), `status` (uint8), `amountSent` (uint256), `hopMaker` (address).
- **HopPrepData** (`MHMain.sol`): Includes `hopId` (uint256), `indices` (uint256[]), `isBuy` (bool[]), `currentToken` (address), `principal` (uint256), `maker` (address).
- **HopExecutionData** (`MHMain.sol`): Contains `listing` (address), `isBuy` (bool), `recipient` (address), `priceLimit` (uint256), `principal` (uint256, denormalized), `inputToken` (address), `settleType` (uint8), `maxIterations` (uint256), `updates` (HopUpdateType[]).
- **StallExecutionData** (`MHMain.sol`): Mirrors `HopExecutionData` with `listing`, `isBuy`, `recipient`, `priceLimit`, `principal`, `settleType`, `maxIterations`, `updates`.
- **CancelPrepData** (`MHMain.sol`): Includes `hopId` (uint256), `listing` (address), `isBuy` (bool), `outputToken` (address), `inputToken` (address), `pending` (uint256), `filled` (uint256), `status` (uint8), `receivedAmount` (uint256), `recipient` (address), `refundedPending` (uint256, actual refunded pending amount after transfer taxes).
- **CancelBalanceData** (`MHMain.sol`): Tracks `token` (address), `balanceBefore` (uint256), `balanceAfter` (uint256).
- **OrderUpdateData** (`MHMain.sol`): Holds `listing` (address), `recipient` (address), `inputAmount` (uint256, normalized), `priceLimit` (uint256, normalized), `inputToken` (address).
- **HopExecutionParams** (`MHMain.sol`): Contains `listingAddresses` (address[], up to 4), `impactPricePercents` (uint256[]), `startToken` (address), `endToken` (address), `settleType` (uint8), `maxIterations` (uint256), `numListings` (uint256).
- **OrderParams** (`MHMain.sol`): Contains `listing` (address), `principal` (uint256), `impactPercent` (uint256, scaled to 1000), `index` (uint256), `numListings` (uint256), `maxIterations` (uint256), `settleType` (uint8).
- **HopRouteData** (`MHMain.sol`): Contains `listings` (address[], ordered), `isBuy` (bool[], buy/sell flags).
- **HopOrderDetails** (`MHMain.sol`): Includes `pending` (uint256, input token), `filled` (uint256, input token), `status` (uint8, 1 = active, 2 = partially filled, 3 = completed), `amountSent` (uint256, output token), `recipient` (address).

## Formulas
1. **Price Impact**:
   - **Formula**: `impactPrice = (newXBalance * 1e18) / newYBalance`, where `newXBalance = xBalance ± amountOut`, `newYBalance = yBalance ± inputAmount` (based on buy/sell).
   - **Used in**: `_validatePriceImpact`, `computeBuyOrderParams`, `computeSellOrderParams` in `MHInit.sol`.
   - **Description**: Ensures trade price stays within `currentPrice * (10000 ± impactPercent) / 10000`.

2. **Amount Out**:
   - **Formula**: `amountOut = isBuy ? (inputAmount * xBalance) / yBalance : (inputAmount * yBalance) / xBalance`.
   - **Used in**: `_validatePriceImpact` in `MHInit.sol`.
   - **Description**: Computes output amount based on input and pool balances.

3. **Normalized Amount**:
   - **Formula**: `normalizedAmount = amount / (10 ** decimals)` (for `decimals <= 18`).
   - **Used in**: `normalizeForToken`, `computeBaseOrderParams` in `MHInit.sol`.
   - **Description**: Normalizes token amounts to a common precision.

4. **Denormalized Amount**:
   - **Formula**: `rawAmount = normalizedAmount * (10 ** decimals)` (for `decimals <= 18`).
   - **Used in**: `denormalizeForToken`, `computeBaseOrderParams`, `_createHopOrder` in `Multihopper.sol`, `MHInit.sol`.
   - **Description**: Converts normalized amounts to token-specific decimals.

## External Functions

### addRouter(address router, uint8 routerType)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `router` (address): Router contract address.
  - `routerType` (uint8): 1 = SSRouter, 2 = SSCrossDriver, 3 = SSIsolatedDriver.
- **Behavior**: Adds or updates a router in `_routers`, ensuring no duplicate addresses with different types. Emits `RouterAdded`.
- **Internal Call Flow**:
  - Validates `router != address(0)`, `routerType` is 1–3.
  - Checks `_routers` for conflicts.
  - Updates or pushes to `_routers`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers` (`MHMain.sol`).
  - **Structs**: `RouterInfo` (`MHMain.sol`).
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `router` is zero, `routerType` is invalid, or router address conflicts.
- **Gas Usage Controls**: Single array push/update, minimal gas.

### removeRouter(address router)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `router` (address): Router to remove.
- **Behavior**: Removes a router from `_routers` using pop-and-swap. Emits `RouterRemoved`.
- **Internal Call Flow**:
  - Iterates `_routers` to remove `router`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers` (`MHMain.sol`).
  - **Structs**: `RouterInfo` (`MHMain.sol`).
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `router` not found.
- **Gas Usage Controls**: Pop-and-swap, minimal gas.

### setAgent(address agent)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `agent` (address): ISSAgent contract address.
- **Behavior**: Sets `_agent` for listing validation. Emits `AgentSet`.
- **Internal Call Flow**:
  - Validates `agent != address(0)`.
  - Assigns to `_agent`.
  - No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_agent` (`MHMain.sol`).
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `agent` is zero.
- **Gas Usage Controls**: Single state write, minimal gas.

### hop(address listing1, address listing2, address listing3, address listing4, uint256 impactPercent, address startToken, address endToken, uint8 settleType, uint256 maxIterations, address maker)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `listing1`–`listing4` (address): Listing contracts (listing2–4 optional, set to address(0) if unused).
  - `impactPercent` (uint256): Max price impact (scaled to 1000, e.g., 500 = 5%).
  - `startToken` (address): Input token.
  - `endToken` (address): Output token.
  - `settleType` (uint8): 0 = market, 1 = liquid.
  - `maxIterations` (uint256): Max settlement iterations per order, stored in `StalledHop`.
  - `maker` (address): Hop initiator, defaults to `msg.sender` if `address(0)`.
- **Behavior**: Initiates a multi-step token swap, creating orders, settling via routers with `maxIterations`, and tracking in `hopID`. Emits `HopStarted`.
- **Internal Call Flow**:
  - Calls `prepHop` (`MHInit.sol`) to validate inputs and compute route.
  - `prepareHopExecution` (`MHInit.sol`) builds `HopExecutionParams`, calls `initializeHopData`.
  - `executeHopSteps`:
    - Calls `computeBuyOrderParams` or `computeSellOrderParams` (`MHInit.sol`).
    - `_createHopOrder` transfers tokens via `IERC20.transferFrom` and `IERC20.approve`, verified by `_checkTransfer` (`MHInit.sol`).
    - `safeSettle` calls `ISSRouter` settlement functions (`MHInit.sol`).
    - `checkOrderStatus` retrieves order details (`MHInit.sol`).
    - Updates `hopID`, `hopsByAddress`, `totalHops` (`MHMain.sol`).
  - Transfer destinations: Listings for inputs, `maker` or contract for outputs.
- **Balance Checks**:
  - Pre: `IERC20.balanceOf(listing)` or `address(listing).balance` in `_createHopOrder`.
  - Post: `balanceAfter > balanceBefore` in `_checkTransfer`.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers`, `hopID`, `hopsByAddress`, `totalHops`, `nextHopId` (`MHMain.sol`).
  - **Structs**: `HopPrepData`, `HopExecutionParams`, `HopExecutionData`, `OrderParams`, `OrderUpdateData`, `HopUpdateType`, `StalledHop` (`MHMain.sol`).
- **Restrictions**:
  - Protected by `nonReentrant` (`MHMain.sol`) and `onlyValidListing` (`Multihopper.sol`).
  - Reverts if `numListings` is 0 or > 4, `maxIterations` is 0, `impactPercent > 1000`, listings are invalid, or route fails.
- **Gas Usage Controls**: `maxIterations`, pop-and-swap, single-element updates.

### continueHop(uint256 maxIterations)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `maxIterations` (uint256): Max hops to process, separate from `StalledHop.maxIterations`.
- **Behavior**: Continues stalled hops for `msg.sender`, processing up to `maxIterations` hops, using `StalledHop.maxIterations` for settlements. Emits `HopContinued`, `StallsPrepared`, `StallsExecuted`.
- **Internal Call Flow**:
  - `prepStalls` iterates `hopsByAddress`, retrieves `StallData` via `checkOrderStatus` (`MHInit.sol`).
  - `executeStalls`:
    - Checks completion (`status == 3`, `pending == 0`).
    - Advances `hopID.stage`, creates orders via `_createHopOrder`, settles via `safeSettle` (`MHInit.sol`).
    - Updates `hopID`, `hopsByAddress`, `totalHops` (`MHMain.sol`).
  - Transfer destinations: Listings for inputs, `msg.sender` or contract for outputs.
- **Balance Checks**:
  - Pre: `IERC20.balanceOf(listing)` or `address(listing).balance` in `_createHopOrder`.
  - Post: `balanceAfter > balanceBefore` in `_checkTransfer`.
- **Mappings/Structs Used**:
  - **Mappings**: `hopID`, `hopsByAddress`, `totalHops` (`MHMain.sol`).
  - **Structs**: `StallData`, `StallExecutionData`, `HopUpdateType`, `OrderUpdateData`, `StalledHop` (`MHMain.sol`).
- **Restrictions**:
  - Protected by `nonReentrant` (`MHMain.sol`).
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: `maxIterations`, 20-stall cap, pop-and-swap.

### executeHops(uint256 maxIterations)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `maxIterations` (uint256): Max iterations for processing hops.
- **Behavior**: Processes all stalled hops globally, up to `maxIterations`, using `StalledHop.maxIterations` for settlements. Emits `StallsPrepared`, `StallsExecuted`, `HopContinued`.
- **Internal Call Flow**:
  - `prepAllStalls` iterates `totalHops`, retrieves `StallData` (`MHInit.sol`).
  - `executeStalls` mirrors `continueHop`.
- **Balance Checks**: Same as `continueHop`.
- **Mappings/Structs Used**: Same as `continueHop`.
- **Restrictions**:
  - Protected by `nonReentrant` (`MHMain.sol`).
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: Same as `continueHop`.

### cancelHop(uint256 hopId)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID to cancel.
- **Behavior**: Cancels a stalled hop, refunding `amountSent` (if non-zero and not yet received) or `filled` in output token via `_handleFilledOrSent`, and `pending` in input token via `_handlePending`, with `refundedPending` tracking actual refunded pending amount. Emits `HopCanceled`.
- **Internal Call Flow**:
  - Calls `_cancelHop` (`MHCtrl.sol`), selecting `_prepCancelHopBuy` or `_prepCancelHopSell` based on `maxPrice > 0`.
  - `_prepClearHopOrder` retrieves order details (`MHCtrl.sol`).
  - `_executeClearHopOrder`:
    - Updates status via `ISSListing.update`.
    - Refunds via `_handleFilledOrSent`, `_handlePending`, `_handleBalance` (`MHCtrl.sol`).
    - Updates `hopID.principalAmount` with `refundedPending`.
  - `_finalizeCancel` updates `hopID.hopStatus`, removes from `hopsByAddress` (`MHCtrl.sol`).
  - Transfer destinations: `hopMaker` for refunds.
- **Balance Checks**:
  - Pre: `IERC20.balanceOf(this)` or `address(this).balance` in `_executeClearHopOrder`.
  - Post: `balanceAfter > balanceBefore` in `_checkTransfer` (`MHInit.sol`).
- **Mappings/Structs Used**:
  - **Mappings**: `hopID`, `hopsByAddress` (`MHMain.sol`).
  - **Structs**: `CancelPrepData`, `CancelBalanceData`, `HopUpdateType`, `StalledHop` (`MHMain.sol`).
- **Restrictions**:
  - Protected by `nonReentrant` (`MHMain.sol`).
  - Reverts if not hop maker, `hopStatus != 1`, or order not cancellable.
- **Gas Usage Controls**: Single hop processing, pop-and-swap, minimal calls.

### cancelAll(uint256 maxIterations)
- **File**: `Multihopper.sol`
- **Parameters**:
  - `maxIterations` (uint256): Max hops to cancel.
- **Behavior**: Cancels up to `maxIterations` stalled hops for `msg.sender`, refunding as in `cancelHop`. Emits `AllHopsCanceled`.
- **Internal Call Flow**:
  - Iterates `hopsByAddress`, calls `_cancelHop` for `hopStatus == 1` (`MHCtrl.sol`).
- **Balance Checks**: Same as `cancelHop`.
- **Mappings/Structs Used**: Same as `cancelHop`.
- **Restrictions**:
  - Protected by `nonReentrant` (`MHMain.sol`).
  - Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: `maxIterations`, pop-and-swap.

### getRouters()
- **File**: `Multihopper.sol`
- **Parameters**: None.
- **Behavior**: Returns `_routers` array.
- **Internal Call Flow**: Accesses `_routers` (`MHMain.sol`). No external calls.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers` (`MHMain.sol`).
  - **Structs**: `RouterInfo` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### agentView()
- **File**: `MHCtrl.sol`
- **Parameters**: None.
- **Behavior**: Returns `_agent` address.
- **Internal Call Flow**: Accesses `_agent` (`MHMain.sol`). No external calls.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_agent` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### hopStatusView(uint256 hopId)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns `hopID[hopId].hopStatus`.
- **Internal Call Flow**: Accesses `hopID` (`MHMain.sol`). No external calls.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopID` (`MHMain.sol`).
  - **Structs**: `StalledHop` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getHopDetails(uint256 hopId)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns `StalledHop` struct from `hopID` for detailed hop information.
- **Internal Call Flow**: Accesses `hopID` (`MHMain.sol`). No external calls.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopID` (`MHMain.sol`).
  - **Structs**: `StalledHop` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getUserHops(address user)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `user` (address): User address.
- **Behavior**: Returns hop IDs from `hopsByAddress` for a user.
- **Internal Call Flow**: Accesses `hopsByAddress` (`MHMain.sol`). No external calls.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopsByAddress` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getTotalHopsCount()
- **File**: `MHCtrl.sol`
- **Parameters**: None.
- **Behavior**: Returns length of `totalHops` array.
- **Internal Call Flow**: Accesses `totalHops` (`MHMain.sol`). No external calls.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `totalHops` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal gas.

### getActiveHopsCount(address user)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `user` (address): User address.
- **Behavior**: Returns count of stalled hops for a user from `hopsByAddress`.
- **Internal Call Flow**: Iterates `hopsByAddress`, checks `hopID` (`MHMain.sol`).
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopsByAddress`, `hopID` (`MHMain.sol`).
  - **Structs**: `StalledHop` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, bounded iteration.

### getTotalPendingHopsCount(uint256 maxIterations)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `maxIterations` (uint256): Max iterations for gas control.
- **Behavior**: Returns count of stalled hops across all users, limited by `maxIterations`.
- **Internal Call Flow**: Iterates `totalHops`, checks `hopID` (`MHMain.sol`).
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `totalHops`, `hopID` (`MHMain.sol`).
  - **Structs**: `StalledHop` (`MHMain.sol`).
- **Restrictions**: Reverts if `maxIterations == 0`.
- **Gas Usage Controls**: Bounded by `maxIterations`.

### getHopOrderDetails(uint256 hopId)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns order details for a hop’s current order via `checkOrderStatus`.
- **Internal Call Flow**: Accesses `hopID`, calls `ISSListing` functions (`MHInit.sol`, `MHMain.sol`).
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopID` (`MHMain.sol`).
  - **Structs**: `StalledHop`, `HopOrderDetails` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal external calls.

### getHopRoute(uint256 hopId)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `hopId` (uint256): Hop ID.
- **Behavior**: Returns ordered listings and `isBuy` flags for a hop from `hopID`.
- **Internal Call Flow**: Accesses `hopID`, queries `ISSListing.tokenA` (`MHMain.sol`).
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopID` (`MHMain.sol`).
  - **Structs**: `StalledHop`, `HopRouteData` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, minimal external calls.

### getUserPendingVolume(address user, address token)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `user` (address): User address.
  - `token` (address): Token address.
- **Behavior**: Returns total pending amount in a token across user’s stalled hops.
- **Internal Call Flow**: Iterates `hopsByAddress`, calls `checkOrderStatus` (`MHInit.sol`, `MHMain.sol`).
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `hopsByAddress`, `hopID` (`MHMain.sol`).
  - **Structs**: `StalledHop` (`MHMain.sol`).
- **Restrictions**: None.
- **Gas Usage Controls**: View function, bounded iteration.

### getContractBalance(address token)
- **File**: `MHCtrl.sol`
- **Parameters**:
  - `token` (address): Token address (or address(0) for native currency).
- **Behavior**: Returns contract’s balance for a token or native currency.
- **Internal Call Flow**: Queries `IERC20.balanceOf` or `address(this).balance`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: None.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, single call.

## Additional Details
- **Decimal Handling**: Uses `normalizeForToken` and `denormalizeForToken` (`MHInit.sol`) for tokens with decimals ≤ 18.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` (`MHMain.sol`).
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap, 20-stall cap.
- **Listing Validation**: `validateHopRequest` (`MHInit.sol`) verifies all non-zero listings via `ISSAgent.getListing`.
- **Token Flow**: Buy orders: `tokenB` input, `tokenA` output; sell orders: `tokenA` input, `tokenB` output.
- **Hop Lifecycle**: Stalled (`hopStatus = 1`), cancelled/completed (`hopStatus = 2`).
- **Events**: `HopStarted`, `HopContinued`, `HopCanceled`, `AllHopsCanceled`, `StallsPrepared`, `StallsExecuted`, `RouterAdded`, `RouterRemoved`, `AgentSet`.
- **Safety**: Explicit casting, balance checks, no inline assembly, robust validation.
- **Price Impact**: Ensures trades stay within `impactPercent` (≤ 1000) of current price.
- **maxIterations Persistence**: Stored in `StalledHop` for settlements, separate from `maxIterations` in `continueHop` and `executeHops`.
