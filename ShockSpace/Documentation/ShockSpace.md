# Shock Space Contracts Documentation
The System comprises of SSAgent  SSListingLogic - SSLiquidityLogic - SSLiquidityTemplate - SSListingTemplate - SSRouter - SSIsolatedDriver and SSCrossDriver. 

## SSLiquidityLogic Contract

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new SSLiquidityTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed SSLiquidityTemplate contract.

## SSListingLogic Contract

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new SSListingTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed SSListingTemplate contract.

## SSAgent Contract

### Mappings and Arrays
- `getListing` (mapping - address, address, address): Maps tokenA to tokenB to the listing address for a trading pair.
- `allListings` (address[]): Array of all listing addresses created.
- `allListedTokens` (address[]): Array of all unique tokens listed.
- `queryByAddress` (mapping - address, uint256[])): Maps a token to an array of listing IDs involving that token.
- `globalLiquidity` (mapping - address, address, address, uint256): Tracks liquidity per user for each tokenA-tokenB pair.
- `totalLiquidityPerPair` (mapping - address, address, uint256): Total liquidity for each tokenA-tokenB pair.
- `userTotalLiquidity` (mapping - address, uint256): Total liquidity contributed by each user across all pairs.
- `listingLiquidity` (mapping - uint256, address, uint256): Liquidity per user for each listing ID.
- `historicalLiquidityPerPair` (mapping - address, address, uint256, uint256): Historical liquidity for each tokenA-tokenB pair at specific timestamps.
- `historicalLiquidityPerUser` (mapping - address, address, address, uint256, uint256): Historical liquidity per user for each tokenA-tokenB pair at specific timestamps.
- `globalOrders` (mapping - address, address, uint256, GlobalOrder): Stores order details for each tokenA-tokenB pair by order ID.
- `pairOrders` (mapping - address, address, uint256[]): Array of order IDs for each tokenA-tokenB pair.
- `userOrders` (mapping - address, uint256[]): Array of order IDs created by each user.
- `historicalOrderStatus` (mapping - address, address, uint256, uint256, uint8): Historical status of orders for each tokenA-tokenB pair at specific timestamps.
- `userTradingSummaries` (mapping - address, address, address, uint256): Trading volume per user for each tokenA-tokenB pair.

### State Variables
- `proxyRouter` (address): Address of the proxy router contract, set post-deployment.
- `isolatedDriver` (address): Address of the isolated driver contract, set post-deployment.
- `crossDriver` (address): Address of the cross driver contract, set post-deployment.
- `listingLogicAddress` (address): Address of the SSListingLogic contract, set post-deployment.
- `liquidityLogicAddress` (address): Address of the SSLiquidityLogic contract, set post-deployment.
- `registryAddress` (address): Address of the registry contract, set post-deployment.
- `listingCount` (uint256): Counter for the number of listings created, incremented per listing.

### Functions

#### Setter Functions
- **setProxyRouter**
  - **Parameters:**
    - `_proxyRouter` (address): Address to set as the proxy router.
  - **Actions:**
    - Requires non-zero address.
    - Updates proxyRouter state variable.
    - Restricted to owner via onlyOwner modifier.
- **setIsolatedDriver**
  - **Parameters:**
    - `_isolatedDriver` (address): Address to set as the isolated driver.
  - **Actions:**
    - Requires non-zero address.
    - Updates isolatedDriver state variable.
    - Restricted to owner via onlyOwner modifier.
- **setCrossDriver**
  - **Parameters:**
    - `_crossDriver` (address): Address to set as the cross driver.
  - **Actions:**
    - Requires non-zero address.
    - Updates crossDriver state variable.
    - Restricted to owner via onlyOwner modifier.
- **setListingLogic**
  - **Parameters:**
    - `_listingLogic` (address): Address to set as the listing logic contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates listingLogicAddress state variable.
    - Restricted to owner via onlyOwner modifier.
- **setLiquidityLogic**
  - **Parameters:**
    - `_liquidityLogic` (address): Address to set as the liquidity logic contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates liquidityLogicAddress state variable.
    - Restricted to owner via onlyOwner modifier.
- **setRegistry**
  - **Parameters:**
    - `_registryAddress` (address): Address to set as the registry contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates registryAddress state variable.
    - Restricted to owner via onlyOwner modifier.

#### Listing Functions
- **listToken**
  - **Parameters:**
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
  - **Actions:**
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies proxyRouter, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract with routers, listing ID, liquidity address, tokens, agent, and registry.
    - Calls _initializeLiquidity to set up liquidity contract with routers, listing ID, listing address, tokens, and agent.
    - Calls _updateState to update mappings and arrays.
    - Emits ListingCreated event.
    - Increments listingCount.
  - **Returns:**
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **listNative**
  - **Parameters:**
    - `token` (address): Token to pair with native currency.
    - `isA` (bool): If true, native currency is tokenA; else, tokenB.
  - **Actions:**
    - Sets nativeAddress to address(0) for native currency.
    - Determines tokenA and tokenB based on isA.
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies proxyRouter, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract.
    - Calls _initializeLiquidity to set up liquidity contract.
    - Calls _updateState to update mappings and arrays.
    - Emits ListingCreated event.
    - Increments listingCount.
  - **Returns:**
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.

#### Liquidity Management Functions
- **globalizeLiquidity**
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `user` (address): User providing or removing liquidity.
    - `amount` (uint256): Liquidity amount to add or remove.
    - `isDeposit` (bool): True for deposit, false for withdrawal.
  - **Actions:**
    - Validates non-zero tokens, user, and valid listingId.
    - Retrieves listing address from caller (liquidity contract) via ISSLiquidityTemplate.
    - Verifies listing validity and details via isValidListing.
    - Confirms caller is the associated liquidity contract.
    - Calls _updateGlobalLiquidity to adjust liquidity mappings.
    - Emits GlobalLiquidityChanged event.
- **_updateGlobalLiquidity** (Internal)
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `user` (address): User providing or removing liquidity.
    - `amount` (uint256): Liquidity amount to add or remove.
    - `isDeposit` (bool): True for deposit, false for withdrawal.
  - **Actions:**
    - If isDeposit, adds amount to globalLiquidity, totalLiquidityPerPair, userTotalLiquidity, and listingLiquidity.
    - If not isDeposit, checks sufficient liquidity, then subtracts amount from mappings.
    - Updates historicalLiquidityPerPair and historicalLiquidityPerUser with current timestamp.
    - Emits GlobalLiquidityChanged event.

#### Order Management Functions
- **globalizeOrders**
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `orderId` (uint256): Unique order identifier.
    - `isBuy` (bool): True if buy order, false if sell.
    - `maker` (address): Address creating the order.
    - `recipient` (address): Address receiving the order outcome.
    - `amount` (uint256): Order amount.
    - `status` (uint8): Order status (0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled).
  - **Actions:**
    - Validates non-zero tokens, maker, and valid listingId.
    - Checks caller is the listing contract via getListing.
    - If new order (maker is zero and status not cancelled), initializes GlobalOrder struct and adds orderId to pairOrders and userOrders.
    - If existing order, updates amount, status, and timestamp.
    - Updates historicalOrderStatus with current timestamp.
    - Adds amount to userTradingSummaries if non-zero.
    - Emits GlobalOrderChanged event.

#### View Functions
- **isValidListing**
  - **Parameters:**
    - `listingAddress` (address): Address to check.
  - **Actions:**
    - Iterates allListings to find matching address.
    - If found, retrieves tokenA and tokenB via ISSListingTemplate.getTokens.
    - Retrieves liquidity address via ISSListing.liquidityAddressView.
    - Constructs ListingDetails struct with listing details.
  - **Returns:**
    - `isValid` (bool): True if listing is valid.
    - `details` (ListingDetails): Struct with listingAddress, liquidityAddress, tokenA, tokenB, and listingId.
- **getPairLiquidityTrend**
  - **Parameters:**
    - `tokenA` (address): Token to focus on.
    - `focusOnTokenA` (bool): If true, tracks tokenA liquidity; else, tokenB.
    - `startTime` (uint256): Start timestamp for trend.
    - `endTime` (uint256): End timestamp for trend.
  - **Actions:**
    - Validates time range and non-zero tokenA.
    - If focusOnTokenA, checks historicalLiquidityPerPair for tokenA with first listed token.
    - Else, checks all tokenB pairings with tokenA.
    - Collects non-zero amounts into TrendData array.
    - Returns timestamps and amounts arrays.
  - **Returns:**
    - `timestamps` (uint256[]): Timestamps with liquidity changes.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityTrend**
  - **Parameters:**
    - `user` (address): User to track.
    - `focusOnTokenA` (bool): If true, tracks tokenA; else, tokenB.
    - `startTime` (uint256): Start timestamp for trend.
    - `endTime` (uint256): End timestamp for trend.
  - **Actions:**
    - Validates time range and non-zero user.
    - Iterates allListedTokens, checks historicalLiquidityPerUser for non-zero amounts.
    - Collects data into TrendData array.
    - Returns tokens, timestamps, and amounts arrays.
  - **Returns:**
    - `tokens` (address[]): Tokens involved in liquidity.
    - `timestamps` (uint256[]): Timestamps with liquidity changes.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityAcrossPairs**
  - **Parameters:**
    - `user` (address): User to track.
    - `maxIterations` (uint256): Maximum pairs to check.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits pairs to maxIterations or allListedTokens length.
    - Iterates allListedTokens, collects non-zero globalLiquidity amounts.
    - Returns tokenAs, tokenBs, and amounts arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `amounts` (uint256[]): Liquidity amounts.
- **getTopLiquidityProviders**
  - **Parameters:**
    - `listingId` (uint256): Listing ID to analyze.
    - `maxIterations` (uint256): Maximum users to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListings length.
    - Collects non-zero listingLiquidity amounts into TrendData array.
    - Sorts in descending order via _sortDescending.
    - Returns users and amounts arrays.
  - **Returns:**
    - `users` (address[]): Top liquidity providers.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityShare**
  - **Parameters:**
    - `user` (address): User to check.
    - `tokenA` (address): First token in pair.
    - `tokenB` (address): Second token in pair.
  - **Actions:**
    - Retrieves total liquidity for the pair from totalLiquidityPerPair.
    - Gets user’s liquidity from globalLiquidity.
    - Calculates share as (userAmount * 1e18) / total if total is non-zero.
  - **Returns:**
    - `share` (uint256): User’s share of liquidity (scaled by 1e18).
    - `total` (uint256): Total liquidity for the pair.
- **getAllPairsByLiquidity**
  - **Parameters:**
    - `minLiquidity` (uint256): Minimum liquidity threshold.
    - `focusOnTokenA` (bool): If true, focuses on tokenA; else, tokenB.
    - `maxIterations` (uint256): Maximum pairs to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListedTokens length.
    - Collects pairs with totalLiquidityPerPair >= minLiquidity into TrendData array.
    - Returns tokenAs, tokenBs, and amounts arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `amounts` (uint256[]): Liquidity amounts.
- **getOrderActivityByPair**
  - **Parameters:**
    - `tokenA` (address): First token in pair.
    - `tokenB` (address): Second token in pair.
    - `startTime` (uint256): Start timestamp for activity.
    - `endTime` (uint256): End timestamp for activity.
  - **Actions:**
    - Validates time range and non-zero tokens.
    - Retrieves order IDs from pairOrders.
    - Filters globalOrders by timestamp range, constructs OrderData array.
    - Returns orderIds and orders arrays.
  - **Returns:**
    - `orderIds` (uint256[]): IDs of orders in the range.
    - `orders` (OrderData[]): Array of order details.
- **getUserTradingProfile**
  - **Parameters:**
    - `user` (address): User to profile.
  - **Actions:**
    - Iterates allListedTokens, collects non-zero trading volumes from userTradingSummaries.
    - Returns tokenAs, tokenBs, and volumes arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `volumes` (uint256[]): Trading volumes.
- **getTopTradersByVolume**
  - **Parameters:**
    - `listingId` (uint256): Listing ID to analyze.
    - `maxIterations` (uint256): Maximum traders to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListings length.
    - Identifies tokenA for each listing, collects non-zero trading volumes from userTradingSummaries.
    - Sorts in descending order via _sortDescending.
    - Returns traders and volumes arrays.
  - **Returns:**
    - `traders` (address[]): Top traders.
    - `volumes` (uint256[]): Corresponding trading volumes.
- **getAllPairsByOrderVolume**
  - **Parameters:**
    - `minVolume` (uint256): Minimum order volume threshold.
    - `focusOnTokenA` (bool): If true, focuses on tokenA; else, tokenB.
    - `maxIterations` (uint256): Maximum pairs to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListedTokens length.
    - Calculates total volume per pair from globalOrders via pairOrders.
    - Collects pairs with volume >= minVolume into TrendData array.
    - Returns tokenAs, tokenBs, and volumes arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `volumes` (uint256[]): Order volumes.
- **queryByIndex**
  - **Parameters:**
    - `index` (uint256): Index to query.
  - **Actions:**
    - Validates index is within allListings length.
    - Retrieves listing address from allListings array.
  - **Returns:**
    - `address`: Listing address at the index.
- **queryByAddressView**
  - **Parameters:**
    - `target` (address): Token to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions:**
    - Retrieves indices from queryByAddress mapping.
    - Calculates start and end bounds based on step and maxIteration.
    - Returns a subset of indices for pagination.
  - **Returns:**
    - `uint256[]`: Array of listing IDs for the target token.
- **queryByAddressLength**
  - **Parameters:**
    - `target` (address): Token to query.
  - **Actions:**
    - Retrieves length of queryByAddress array for the target token.
  - **Returns:**
    - `uint256`: Number of listing IDs for the target token.
- **allListingsLength**
  - **Actions:**
    - Retrieves length of allListings array.
  - **Returns:**
    - `uint256`: Total number of listings.
- **allListedTokensLength**
  - **Actions:**
    - Retrieves length of allListedTokens array.
  - **Returns:**
    - `uint256`: Total number of listed tokens.

# SSListing and SSLiquidity Contract Documentation

## Overview
The `SSListingTemplate` and `SSLiquidityTemplate` contracts, implemented in Solidity (^0.8.1), form the core of a decentralized trading platform. `SSListingTemplate` manages buy/sell orders, payouts, and volume balances, while `SSLiquidityTemplate` handles liquidity deposits, withdrawals, and fee claims. Both inherit `ReentrancyGuard` for security and use `SafeERC20` for token operations, integrating with `ISSAgent` and `ITokenRegistry` for global updates and registry synchronization. State variables are private, accessed via view functions, and amounts are normalized to 1e18 for consistency across token decimals.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.8 (last updated 2025-06-19)

## SSListingTemplate Documentation

### Mappings
- **routers**: Maps addresses to boolean, indicating authorized routers.
- **buyOrderCores**: Maps order ID to `BuyOrderCore` (makerAddress, recipientAddress, status).
- **buyOrderPricings**: Maps order ID to `BuyOrderPricing` (maxPrice, minPrice).
- **buyOrderAmounts**: Maps order ID to `BuyOrderAmounts` (pending, filled).
- **sellOrderCores**: Maps order ID to `SellOrderCore` (makerAddress, recipientAddress, status).
- **sellOrderPricings**: Maps order ID to `SellOrderPricing` (maxPrice, minPrice).
- **sellOrderAmounts**: Maps order ID to `SellOrderAmounts` (pending, filled).
- **longPayouts**: Maps order ID to `LongPayoutStruct` (makerAddress, recipientAddress, required, filled, orderId, status).
- **shortPayouts**: Maps order ID to `ShortPayoutStruct` (makerAddress, recipientAddress, amount, filled, orderId, status).
- **makerPendingOrders**: Maps maker address to array of pending order IDs.
- **userPayoutIDs**: Maps user address to array of payout order IDs.

### Structs
- **VolumeBalance**: Stores `xBalance` (tokenX), `yBalance` (tokenY), `xVolume`, `yVolume` (normalized).
- **LastDayFee**: Stores `xFees`, `yFees`, `timestamp` for daily fee tracking.
- **BuyOrderCore**: Contains `makerAddress`, `recipientAddress`, `status` (0=cancelled, 1=pending, 2=partially filled, 3=filled).
- **BuyOrderPricing**: Contains `maxPrice`, `minPrice` (normalized).
- **BuyOrderAmounts**: Contains `pending`, `filled` (normalized).
- **SellOrderCore**: Same as `BuyOrderCore` for sell orders.
- **SellOrderPricing**: Same as `BuyOrderPricing` for sell orders.
- **SellOrderAmounts**: Same as `BuyOrderAmounts` for sell orders.
- **PayoutUpdate**: Contains `payoutType` (0=long, 1=short), `recipient`, `required` (normalized).
- **LongPayoutStruct**: Contains `makerAddress`, `recipientAddress`, `required`, `filled`, `orderId`, `status`.
- **ShortPayoutStruct**: Contains `makerAddress`, `recipientAddress`, `amount`, `filled`, `orderId`, `status`.
- **HistoricalData**: Stores `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **UpdateType**: Contains `updateType` (0=balance, 1=buy order, 2=sell order, 3=historical), `structId` (0=core, 1=pricing, 2=amounts), `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`.

### Formulas
1. **Price Calculation**:
   - **Formula**: `price = (xBalance * 1e18) / yBalance`
   - **Used in**: `update`, `transact`.
   - **Description**: Computes current price when `xBalance` and `yBalance` are non-zero, used for order pricing and historical data.

2. **Daily Yield**:
   - **Formula**: `dailyYield = ((feeDifference * 0.0005) * 1e18) / liquidity * 365`
   - **Used in**: `queryYield`.
   - **Description**: Calculates annualized yield from `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`), using 0.05% fee rate and liquidity from `SSLiquidityTemplate`.

### External Functions
#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` (array of router addresses).
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet` to true.
- **Restrictions**: Reverts if `routersSet` or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` (uint256).
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setLiquidityAddress(address _liquidityAddress)
- **Parameters**: `_liquidityAddress` (address).
- **Behavior**: Sets `liquidityAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `liquidityAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` (addresses).
- **Behavior**: Sets `tokenX`, `tokenY`, `decimalX`, `decimalY`, callable once.
- **Internal Call Flow**: Fetches decimals via `IERC20.decimals` (18 for ETH).
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes and external calls.

#### setAgent(address _agent)
- **Parameters**: `_agent` (address).
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setRegistry(address _registryAddress)
- **Parameters**: `_registryAddress` (address).
- **Behavior**: Sets `registryAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `registryAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` (address): Router address.
  - `updates` (UpdateType[]): Array of updates.
- **Behavior**: Updates balances, orders, or historical data, triggers `globalizeUpdate`.
- **Internal Call Flow**:
  - Checks `volumeUpdated` to update `lastDayFee` if new day.
  - Processes `updates`:
    - `updateType=0`: Updates `xBalance`, `yBalance`, `xVolume`, `yVolume`.
    - `updateType=1`: Updates buy order `core`, `pricing`, or `amounts`, adjusts `pendingBuyOrders`, `makerPendingOrders`.
    - `updateType=2`: Same for sell orders.
    - `updateType=3`: Adds `HistoricalData`.
  - Updates `price`, calls `globalizeUpdate`, emits `BalancesUpdated` or `OrderUpdated`.
- **Balance Checks**: Updates `xBalance`, `yBalance` for orders.
- **Mappings/Structs Used**: All mappings, `UpdateType`, `VolumeBalance`, `LastDayFee`, `HistoricalData`.
- **Restrictions**: `nonReentrant`, `routers[caller]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`.

#### ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates)
- **Parameters**:
  - `caller` (address): Router address.
  - `payoutUpdates` (PayoutUpdate[]): Array of payout updates.
- **Behavior**: Creates long/short payout orders, increments `nextOrderId`.
- **Internal Call Flow**:
  - Creates `LongPayoutStruct` or `ShortPayoutStruct`, updates `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`.
  - Emits `PayoutOrderCreated`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `longPayouts`, `shortPayouts`, `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`, `PayoutUpdate`.
- **Restrictions**: `nonReentrant`, `routers[caller]`.
- **Gas Usage Controls**: Loop over `payoutUpdates`, dynamic arrays.

#### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` (address): Router address.
  - `token` (address): TokenX or tokenY.
  - `amount` (uint256): Denormalized amount.
  - `recipient` (address): Recipient address.
- **Behavior**: Transfers tokens/ETH, updates balances, and registry.
- **Internal Call Flow**:
  - Normalizes `amount`, checks `xBalance`/`yBalance`.
  - Transfers via `SafeERC20` or ETH call.
  - Updates `xVolume`/`yVolume`, `lastDayFee`, `price`.
  - Calls `_updateRegistry`, emits `BalancesUpdated`.
- **Balance Checks**: Pre-transfer balance check.
- **Mappings/Structs Used**: `volumeBalance`, `LastDayFee`.
- **Restrictions**: `nonReentrant`, `routers[caller]`.
- **Gas Usage Controls**: Single transfer, minimal state updates.

#### queryYield(bool isA, uint256 maxIterations)
- **Parameters**:
  - `isA` (bool): True for tokenX, false for tokenY.
  - `maxIterations` (uint256): Max historical data iterations.
- **Behavior**: Returns annualized yield based on daily fees.
- **Internal Call Flow**:
  - Checks `lastDayFee` timestamp, fetches liquidity from `liquidityAddress`.
  - Computes `feeDifference`, calculates yield.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `lastDayFee`, `volumeBalance`.
- **Restrictions**: Reverts if `maxIterations` is zero.
- **Gas Usage Controls**: Minimal, external call to `liquidityAmounts`.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts, fetched via `IERC20.decimals` or `decimalX`/`decimalY`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Dynamic arrays, minimal external calls.
- **Token Usage**: Buy orders use tokenY input, tokenX output; sell orders use tokenX input, tokenY output; long payouts use tokenY, short payouts use tokenX.
- **Events**: `OrderUpdated`, `PayoutOrderCreated`, `BalancesUpdated`.
- **Safety**: Balance checks, explicit casting, no inline assembly, try-catch error handling.
- **Compatibility**: Aligned with `SSRouter` (v0.0.44), `SSAgent` (v0.0.2).

## SSLiquidityTemplate Documentation

### Mappings
- **routers**: Maps addresses to boolean, indicating authorized routers.
- **xLiquiditySlots**: Maps slot index to `Slot` for tokenA (depositor, recipient, allocation, dVolume, timestamp).
- **yLiquiditySlots**: Maps slot index to `Slot` for tokenB.
- **activeXLiquiditySlots**: Array of active xSlot indices.
- **activeYLiquiditySlots**: Array of active ySlot indices.
- **userIndex**: Maps user address to array of slot indices.

### Structs
- **LiquidityDetails**: Stores `xLiquid`, `yLiquid` (normalized liquidity), `xFees`, `yFees` (normalized fees).
- **Slot**: Contains `depositor`, `recipient`, `allocation` (normalized), `dVolume`, `timestamp`.
- **UpdateType**: Contains `updateType` (0=balance, 1=fees, 2=xSlot, 3=ySlot), `index` (0=xFees/xLiquid, 1=yFees/yLiquid, or slot index), `value` (normalized), `addr` (depositor), `recipient` (unused).
- **PreparedWithdrawal**: Contains `amountA`, `amountB` (normalized).
- **FeeClaimContext**: Contains `caller` (address), `isX` (bool), `volume`, `dVolume`, `liquid`, `allocation`, `fees`, `liquidityIndex` (uint256) for `claimFees` stack optimization.

### Formulas
1. **Fee Share**:
   - **Formula**: `feeShare = (feesAccrued * liquidityContribution) / 1e18`, where `feesAccrued = (contributedVolume * 0.0005)`, `contributedVolume = volume - dVolume`, `liquidityContribution = (allocation * 1e18) / liquid`
   - **Used in**: `_claimFeeShare`.
   - **Description**: Computes fee share for a liquidity slot based on volume contribution and liquidity proportion.

### External Functions
#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` (array of router addresses).
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet`.
- **Restrictions**: Reverts if `routersSet` or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` (uint256).
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setListingAddress(address _listingAddress)
- **Parameters**: `_listingAddress` (address).
- **Behavior**: Sets `listingAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` (addresses).
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes.

#### setAgent(address _agent)
- **Parameters**: `_agent` (address).
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` (address): User address.
  - `updates` (UpdateType[]): Array of updates.
- **Behavior**: Updates liquidity or fees, manages slots.
- **Internal Call Flow**:
  - Processes `updates`:
    - `updateType=0`: Updates `xLiquid` or `yLiquid`.
    - `updateType=1`: Updates `xFees` or `yFees`, emits `FeesUpdated`.
    - `updateType=2`: Updates `xLiquiditySlots`, `activeXLiquiditySlots`, `userIndex`, fetches `xVolume`.
    - `updateType=3`: Same for `yLiquiditySlots`, `activeYLiquiditySlots`, fetches `yVolume`.
  - Emits `LiquidityUpdated`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `liquidityDetail`, `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `UpdateType`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`.

#### changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `caller` (address): User address.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `slotIndex` (uint256): Slot index.
  - `newDepositor` (address): New depositor.
- **Behavior**: Transfers slot ownership.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots` or `yLiquiditySlots`, `userIndex`.
  - Emits `SlotDepositorChanged`.
- **Balance Checks**: Checks slot `allocation`.
- **Mappings/Structs Used**: `xLiquiditySlots`, `yLiquiditySlots`, `userIndex`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`, caller must be depositor.
- **Gas Usage Controls**: Single slot update, array adjustments.

#### deposit(address caller, address token, uint256 amount)
- **Parameters**:
  - `caller` (address): User address.
  - `token` (address): TokenA or tokenB.
  - `amount` (uint256): Denormalized amount.
- **Behavior**: Deposits tokens/ETH to liquidity pool.
- **Internal Call Flow**:
  - Performs pre/post balance checks, transfers via `transferFrom` or ETH.
  - Normalizes amount, creates `UpdateType` for slot allocation.
  - Calls `update`, `globalizeUpdate`, `updateRegistry`.
- **Balance Checks**: Pre/post balance for tokens, `msg.value` for ETH.
- **Mappings/Structs Used**: `UpdateType`, `activeXLiquiditySlots`, `activeYLiquiditySlots`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal updates.

#### xPrepOut(address caller, uint256 amount, uint256 index)
- **Parameters**:
  - `caller` (address): User address.
  - `amount` (uint256): Normalized amount.
  - `index` (uint256): Slot index.
- **Behavior**: Prepares tokenA withdrawal, calculates compensation.
- **Internal Call Flow**:
  - Checks `xLiquid` and slot `allocation`.
  - Fetches `getPrice`, computes `withdrawAmountB` if deficit.
  - Returns `PreparedWithdrawal`.
- **Balance Checks**: Checks `xLiquid`, `yLiquid`.
- **Mappings/Structs Used**: `liquidityDetail`, `xLiquiditySlots`, `PreparedWithdrawal`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`.
- **Gas Usage Controls**: Minimal, external call to `getPrice`.

#### xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**:
  - `caller` (address): User address.
  - `index` (uint256): Slot index.
  - `withdrawal` (PreparedWithdrawal): Withdrawal amounts.
- **Behavior**: Executes tokenA withdrawal, transfers tokens/ETH.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots` via `update`.
  - Transfers `amountA` (tokenA), `amountB` (tokenB) via `SafeERC20` or ETH.
  - Calls `globalizeUpdate`, `updateRegistry` for both tokens.
- **Balance Checks**: None, assumes `xPrepOut` validation.
- **Mappings/Structs Used**: `xLiquiditySlots`, `UpdateType`, `PreparedWithdrawal`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`.
- **Gas Usage Controls**: Two transfers, minimal updates.

#### yPrepOut(address caller, uint256 amount, uint256 index)
- **Parameters**: Same as `xPrepOut`.
- **Behavior**: Prepares tokenB withdrawal, calculates compensation.
- **Internal Call Flow**: Similar to `xPrepOut`, uses `yLiquid`, computes `withdrawAmountA`.
- **Balance Checks**: Checks `yLiquid`, `xLiquid`.
- **Mappings/Structs Used**: `yLiquiditySlots`, `liquidityDetail`, `PreparedWithdrawal`.
- **Restrictions**: Same as `xPrepOut`.
- **Gas Usage Controls**: Same as `xPrepOut`.

#### yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**: Same as `xExecuteOut`.
- **Behavior**: Executes tokenB withdrawal, transfers tokens/ETH.
- **Internal Call Flow**: Similar to `xExecuteOut`, uses `yLiquiditySlots`.
- **Balance Checks**: None, assumes `yPrepOut` validation.
- **Mappings/Structs Used**: `yLiquiditySlots`, `UpdateType`, `PreparedWithdrawal`.
- **Restrictions**: Same as `xExecuteOut`.
- **Gas Usage Controls**: Same as `xExecuteOut`.

#### claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 volume)
- **Parameters**:
  - `caller` (address): User address.
  - `_listingAddress` (address): Listing contract.
  - `liquidityIndex` (uint256): Slot index.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `volume` (uint256): Volume for fee calculation.
- **Behavior**: Claims fees (tokenB for xSlots, tokenA for ySlots).
- **Internal Call Flow**:
  - Creates `FeeClaimContext` to store `caller`, `isX`, `volume`, `dVolume`, `liquid`, `allocation`, `fees`, `liquidityIndex`.
  - Calls `_processFeeClaim` with `FeeClaimContext`.
  - `_processFeeClaim` calls `_claimFeeShare` to compute `feeShare`, updates fees and slot via `update`, transfers via `transact`.
  - Emits `FeesClaimed`.
- **Balance Checks**: Checks `xBalance` (from `volumeBalances`), `xLiquid`/`yLiquid`, `xFees`/`yFees`.
- **Mappings/Structs Used**: `liquidityDetail`, `xLiquiditySlots`, `yLiquiditySlots`, `UpdateType`, `FeeClaimContext`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`, caller must be depositor.
- **Gas Usage Controls**: Single transfer, struct-based stack optimization.

#### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` (address): User address.
  - `token` (address): TokenA or tokenB.
  - `amount` (uint256): Denormalized amount.
  - `recipient` (address): Recipient address.
- **Behavior**: Transfers tokens/ETH, updates liquidity.
- **Internal Call Flow**:
  - Normalizes `amount`, checks `xLiquid`/`yLiquid`.
  - Transfers via `SafeERC20` or ETH, updates `liquidityDetail`.
  - Emits `LiquidityUpdated`.
- **Balance Checks**: Pre-transfer liquidity check.
- **Mappings/Structs Used**: `liquidityDetail`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`.
- **Gas Usage Controls**: Single transfer, minimal updates.

#### addFees(address caller, bool isX, uint256 fee)
- **Parameters**:
  - `caller` (address): User address.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `fee` (uint256): Normalized fee amount.
- **Behavior**: Adds fees to `xFees` or `yFees`.
- **Internal Call Flow**: Creates `UpdateType`, calls `update`, emits `FeesUpdated`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `UpdateType`, `liquidityDetail`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`.
- **Gas Usage Controls**: Minimal, single update.

#### updateLiquidity(address caller, bool isX, uint256 amount)
- **Parameters**:
  - `caller` (address): User address.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `amount` (uint256): Normalized amount.
- **Behavior**: Reduces `xLiquid` or `yLiquid`.
- **Internal Call Flow**: Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Checks `xLiquid` or `yLiquid`.
- **Mappings/Structs Used**: `liquidityDetail`.
- **Restrictions**: `nonReentrant`, `routers[msg.sender]`.
- **Gas Usage Controls**: Minimal, single update.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts, fetched via `IERC20.decimals`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Dynamic arrays, minimal external calls, struct-based stack management in `claimFees`.
- **Token Usage**: xSlots claim tokenB fees, ySlots claim tokenA fees.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `FeesClaimed`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`.
- **Safety**: Balance checks, explicit casting, no inline assembly, try-catch error handling.
- **Compatibility**: Aligned with `SSRouter` (v0.0.44), `SSAgent` (v0.0.2), `SSListingTemplate` (v0.0.8).
- **Caller Param**: functionally unused in `addFees` and `updateLiquidity`, though used in other functions like `deposit`. 

# SSRouter Contract Documentation

## Overview
The `SSRouter` contract, implemented in Solidity (^0.8.2), facilitates order creation, settlement, and liquidity management for a decentralized trading platform. It inherits functionality from `SSSettlementPartial`, which extends `SSOrderPartial` and `SSMainPartial`, integrating with external interfaces (`ISSListingTemplate`, `ISSLiquidityTemplate`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles buy/sell order creation, settlement, liquidity deposits, withdrawals, fee claims, and depositor changes, with rigorous gas optimization and safety mechanisms. State variables are hidden, accessed via view functions, and decimal precision is maintained across tokens.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.44 (last updated 2025-06-19)

**Inheritance Tree:** `SSRouter` → `SSSettlementPartial` → `SSOrderPartial` → `SSMainPartial`

## Mappings
- **orderPendingAmounts**: Tracks pending order amounts per listing and order ID (normalized to 1e18).
- **payoutPendingAmounts**: Tracks pending payout amounts per listing and order ID (normalized to 1e18).

## Structs
- **OrderPrep**: Contains `maker` (address), `recipient` (address), `amount` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256).
- **BuyOrderDetails**: Includes `orderId` (uint256), `maker` (address), `recipient` (address), `pending` (uint256, normalized), `filled` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `status` (uint8).
- **SellOrderDetails**: Same as `BuyOrderDetails` for sell orders.
- **OrderClearData**: Contains `orderId` (uint256), `isBuy` (bool), `amount` (uint256, normalized).
- **OrderContext**: Includes `listingContract` (ISSListingTemplate), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **SellOrderUpdateContext**: Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256).
- **BuyOrderUpdateContext**: Same as `SellOrderUpdateContext` for buy orders.
- **PayoutContext**: Includes `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).

## Formulas
1. **Price Impact**:
   - **Formula**: `impactPrice = (newXBalance * 1e18) / newYBalance`
   - **Used in**: `_computeImpact`, `_checkPricing`.
   - **Description**: Represents the post-settlement price after processing a buy or sell order, calculated using updated pool balances (`newXBalance` for tokenA, `newYBalance` for tokenB). In `_computeImpact`, it uses `listingVolumeBalancesView` (includes input amount), computes `amountOut` using constant product formula (`inputAmount * xBalance / yBalance` for buy, `inputAmount * yBalance / xBalance` for sell), and adjusts balances (`newXBalance -= amountOut` for buy, `newYBalance -= amountOut` for sell).

2. **Buy Order Output**:
   - **Formula**: `amountOut = (inputAmount * xBalance) / yBalance`
   - **Used in**: `executeBuyOrder`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenA) for a buy order given the input amount (tokenB), using constant product formula.

3. **Sell Order Output**:
   - **Formula**: `amountOut = (inputAmount * yBalance) / xBalance`
   - **Used in**: `executeSellOrder`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenB) for a sell order given the input amount (tokenA), using constant product formula.

## External Functions

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ISSAgent address.
- **Behavior**: Updates `agent` state variable for listing validation.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores ISSAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### createBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `recipientAddress` (address): Order recipient.
  - `inputAmount` (uint256): Input amount (denormalized, tokenB).
  - `maxPrice` (uint256): Maximum price (normalized).
  - `minPrice` (uint256): Minimum price (normalized).
- **Behavior**: Creates a buy order, transferring tokenB to the listing contract, and updating order state.
- **Internal Call Flow**:
  - Calls `_handleOrderPrep` to validate inputs and create `OrderPrep` struct, normalizing `inputAmount` using `listingContract.decimalsB`.
  - `_checkTransferAmount` transfers `inputAmount` in tokenB from `msg.sender` to `listingAddress` via `IERC20.transferFrom` or ETH transfer, with pre/post balance checks.
  - `_executeSingleOrder` calls `listingContract.getNextOrderId` and creates `UpdateType[]` for pending order status and pricing, invoking `listingContract.update`.
  - Transfer destination: `listingAddress`.
- **Balance Checks**:
  - **Pre-Balance Check**: Captures `listingAddress` balance before transfer.
  - **Post-Balance Check**: Ensures `postBalance > preBalance`, computes `amountReceived`.
- **Mappings/Structs Used**:
  - **Structs**: `OrderPrep`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `maker`, `recipient`, or `amount` is invalid, or transfer fails.
- **Gas Usage Controls**: Single transfer, minimal array updates.

### createSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createBuyOrder`, but for sell orders with tokenA input.
- **Behavior**: Creates a sell order, transferring tokenA to the listing contract.
- **Internal Call Flow**:
  - Similar to `createBuyOrder`, using tokenA and `listingContract.decimalsA`.
  - `_checkTransferAmount` handles tokenA transfer.
- **Balance Checks**: Same as `createBuyOrder`.
- **Mappings/Structs Used**: Same as `createBuyOrder`.
- **Restrictions**: Same as `createBuyOrder`.
- **Gas Usage Controls**: Same as `createBuyOrder`.

### settleBuyOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles pending buy orders, transferring tokenA to recipients.
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - For each order, calls `executeBuyOrder`:
    - Validates pricing via `_checkPricing` using `_computeImpact`, ensuring `impactPrice` is within `maxPrice` and `minPrice`.
    - Computes output via `_computeImpact` and `amountOut = (inputAmount * xBalance) / yBalance`.
    - Calls `_prepBuyOrderUpdate` for tokenA transfer via `listingContract.transact`, with denormalized amounts.
    - Updates `orderPendingAmounts` and creates `UpdateType[]` via `_executeBuyOrderUpdate`.
  - Applies `finalUpdates[]` via `listingContract.update`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - Assumes transfers succeed, user foots fee-on-transfer costs.
- **Mappings/Structs Used**:
  - **Mappings**: `orderPendingAmounts`.
  - **Structs**: `UpdateType`, `BuyOrderUpdateContext`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders with zero pending amount or invalid pricing.
- **Gas Usage Controls**: `maxIterations` limits iteration, dynamic array resizing.

### settleSellOrders(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles pending sell orders, transferring tokenB to recipients.
- **Internal Call Flow**:
  - Similar to `settleBuyOrders`, using `pendingSellOrdersView[]` and `executeSellOrder`.
  - Computes `amountOut = (inputAmount * yBalance) / xBalance`.
  - Uses `_prepSellOrderUpdate` for tokenB transfers.
- **Balance Checks**: Same as `settleBuyOrders`.
- **Mappings/Structs Used**: Same as `settleBuyOrders`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyOrders`.
- **Gas Usage Controls**: Same as `settleBuyOrders`.

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles buy orders with liquidity pool, transferring tokenA to recipients and updating liquidity.
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - Calls `executeSingleBuyLiquid`:
    - Validates pricing via `_checkPricing`, ensuring `impactPrice` is valid.
    - `_prepBuyLiquidUpdates` uses `_prepareLiquidityTransaction` to compute `amountOut` and tokens.
    - Transfers tokenA via `liquidityContract.transact`.
    - Updates liquidity via `_updateLiquidity` (tokenB, isX=false).
    - Creates `UpdateType[]` via `_createBuyOrderUpdates`.
  - Applies `finalUpdates[]` via `listingContract.update`.
  - Transfer destinations: `recipientAddress` (tokenA), `liquidityAddr` (tokenB).
- **Balance Checks**:
  - `_checkAndTransferPrincipal` checks listing and liquidity balances pre/post transfer.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `BuyOrderUpdateContext`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles sell orders with liquidity pool, transferring tokenB and updating amounts.
- **Internal Call Flow**:
  - Similar to `settleBuyLiquid`, using `executeSingleSellLiquid` and `_prepSellLiquidUpdates`.
  - Transfers tokenB, updates amounts (tokenA, isX=true).
- **Balance Checks**: Same as `settleBuyLiquid`.
- **Mappings/Structs Used**: Same as `settleBuyLiquid`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyLiquid`.
- **Gas Usage Controls**: Same as `settleBuyLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long position payouts, transferring tokenB to holders.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `executeLongPayout`:
    - Uses `_prepPayoutContext` (tokenB, decimalsB).
    - Transfers `amountOut` via `listingContract.transact`.
    - Updates `payoutPendingAmounts` and creates `PayoutUpdate[]` via `_createPayoutUpdate`.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipientAddress` (tokenB).
- **Balance Checks**: Pre/post balances in `_transferListingPayoutAmount`.
- **Mappings/Structs Used**:
  - **Mappings**: `payoutPendingAmounts`.
  - **Structs**: `PayoutContext`, `PayoutUpdate`, `LongPayoutStruct`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `listingContract`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles short position payouts, transferring tokenA to holders.
- **Internal Call Flow**:
  - Similar to `settleLongPayouts`, using `shortPayoutByIndexView[]` and `executeShortPayout`.
  - Uses `_prepPayoutContext` with tokenA and `decimalsA`.
- **Balance Checks**: Same as `settleLongPayouts`.
- **Mappings/Structs Used**: Same as `settleLongPayouts`, with `ShortPayoutStruct`.
- **Restrictions**: Same as `settleLongPayouts`.
- **Gas Usage Controls**: Same as `settleLongPayouts`.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles long position payouts from liquidity pool, transferring tokenB to holders.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `settleSingleLongLiquid`:
    - Uses `_prepPayoutContext` (tokenB, decimalsB).
    - Checks liquidity via `_checkLiquidityBalance`.
    - Transfers `amountOut` via `liquidityContract.transact`.
    - Updates `payoutPendingAmounts` and creates `PayoutUpdate[]` via `_createPayoutUpdate`.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipientAddress` (tokenB).
- **Balance Checks**: Pre/post balances in `_transferPayoutAmount`.
- **Mappings/Structs Used**:
  - **Mappings**: `payoutPendingAmounts`.
  - **Structs**: `PayoutContext`, `PayoutUpdate`, `LongPayoutStruct`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles short position payouts from liquidity pool, transferring tokenA to holders.
- **Internal Call Flow**:
  - Similar to `settleLongLiquid`, using `settleSingleShortLiquid` and `_prepPayoutContext` with tokenA and `decimalsA`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`, with `ShortPayoutStruct`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.

### deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `isTokenA` (bool): True for tokenA, false for tokenB.
  - `inputAmount` (uint256): Deposit amount (denormalized).
  - `user` (address): User depositing liquidity.
- **Behavior**: Deposits tokens or ETH to the liquidity pool on behalf of `user`.
- **Internal Call Flow**:
  - Validates `isTokenA` to select tokenA or tokenB.
  - For ETH: Checks `msg.value == inputAmount`, calls `liquidityContract.deposit(user, tokenAddress, inputAmount)`.
  - For tokens: Transfers via `IERC20.transferFrom` from `msg.sender` to `this`, with pre/post balance checks, approves `liquidityAddr`, and calls `liquidityContract.deposit(user, tokenAddress, receivedAmount)`.
  - Transfer destinations: `this` (from `msg.sender`), `liquidityAddr` (from `this`).
- **Balance Checks**:
  - Pre/post balance checks for token transfers to handle fee-on-transfer tokens.
  - Relies on `liquidityContract.deposit` for ETH balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract`.
  - Reverts if `user` is zero or deposit fails.
- **Gas Usage Controls**: Single transfer and call, minimal state writes.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `liquidityIndex` (uint256): Liquidity slot index.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `volumeAmount` (uint256): Volume for fee calculation.
  - `user` (address): User claiming fees.
- **Behavior**: Claims fees from the liquidity pool on behalf of `user`.
- **Internal Call Flow**:
  - Calls `liquidityContract.claimFees(user, listingAddress, liquidityIndex, isX, volumeAmount)`.
  - No direct transfers or balance checks.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract`.
  - Reverts if `user` is zero or claim fails.
- **Gas Usage Controls**: Minimal, single external call.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `inputAmount` (uint256): Withdrawal amount (denormalized).
  - `index` (uint256): Liquidity slot index.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `user` (address): User withdrawing liquidity.
- **Behavior**: Withdraws liquidity from the pool on behalf of `user`.
- **Internal Call Flow**:
  - Calls `xPrepOut` or `yPrepOut` with `user` to prepare withdrawal.
  - Executes via `xExecuteOut` or `yExecuteOut` with `user`.
  - No direct transfers, handled by `liquidityContract`.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Mappings/Structs Used**:
  - **Structs**: `PreparedWithdrawal`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract`.
  - Reverts if `user` is zero or preparation/execution fails.
- **Gas Usage Controls**: Minimal, two external calls.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `orderIdentifier` (uint256): Order ID.
  - `isBuyOrder` (bool): True for buy, false for sell.
- **Behavior**: Cancels a single order, refunding pending amounts.
- **Internal Call Flow**:
  - Calls `_clearOrderData`:
    - Retrieves order data via `getBuyOrderCore` or `getSellOrderCore`.
    - Refunds pending amount via `listingContract.transact` (tokenB for buy, tokenA for sell).
    - Sets status to 0 via `listingContract.update`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**: Assumes transfer succeeds, user foots fee-on-transfer costs.
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if refund fails.
- **Gas Usage Controls**: Single transfer and update.

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Cancels pending buy and sell orders.
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` and `pendingSellOrdersView[]` up to `maxIterations`.
  - Calls `_clearOrderData` for each order.
- **Balance Checks**: Same as `clearSingleOrder`.
- **Mappings/Structs Used**: Same as `clearSingleOrder`.
- **Restrictions**: Same as `clearSingleOrder`.
- **Gas Usage Controls**: `maxIterations` limits iteration.

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `slotIndex` (uint256): Liquidity slot index.
  - `newDepositor` (address): New depositor address.
  - `user` (address): Current slot owner.
- **Behavior**: Changes the depositor for a liquidity slot on behalf of `user`.
- **Internal Call Flow**:
  - Calls `liquidityContract.changeSlotDepositor(user, isX, slotIndex, newDepositor)`.
  - No direct transfers or balance checks.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract`.
  - Reverts if `user` or `newDepositor` is zero or change fails.
- **Gas Usage Controls**: Minimal, single external call.

## Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` from `SSMainPartial.sol` (1e18) for token amounts, fetched via `IERC20.decimals` or `listingContract.decimalsA/B`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, dynamic arrays, and `_checkAndTransferPrincipal` to reduce stack depth.
- **Listing Validation**: Uses `onlyValidListing` modifier with `ISSAgent.getListing` checks.
- **Token Usage**: Buy orders use tokenB input, tokenA output; sell orders use tokenA input, tokenB output; long payouts use tokenB, short payouts use tokenA.
- **Events**: No events explicitly defined; relies on `listingContract` and `liquidityContract` events.
- **Safety**: Balance checks, explicit casting, no inline assembly, and try-catch error handling ensure robustness.
- **Compatibility**: Aligned with `SSListingTemplate` (v0.0.8), `SSLiquidityTemplate` (v0.0.7), `SSAgent` (v0.0.2).

# SSCrossDriver Contract Documentation

## Overview
The `SSCrossDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short strategies, inheriting functionality through `CSDExecutionPartial` to `CSDPositionPartial` to `CSDUtilityPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`) and uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles position creation, closure, cancellation, margin adjustments, and stop-loss/take-profit updates, with rigorous gas optimization and safety mechanisms. State variables are hidden, accessed via view functions, and decimal precision is maintained across tokens with varying decimals.

**Inheritance Tree:** `SSCrossDriver` → `CSDExecutionPartial` → `CSDPositionPartial` → `CSDUtilityPartial`

**SPDX License:** BSD-3-Clause

**Version:** 0.0.36 (last updated 2025-06-17)

## Mappings
- **makerTokenMargin**: Tracks margin balances per maker and token (normalized to 1e18).
- **makerMarginTokens**: Lists tokens with non-zero margins per maker.
- **positionCore1**: Stores core position data (ID, listing, maker, type).
- **positionCore2**: Tracks position status (active, closed).
- **priceParams1**: Holds price data (entry prices, leverage, liquidation price).
- **priceParams2**: Stores liquidation price.
- **marginParams1**: Manages margin details (initial, taxed, excess, fee).
- **marginParams2**: Tracks initial loan amount.
- **exitParams**: Stores exit conditions (stop-loss, take-profit, exit price).
- **openInterest**: Records leverage amount and timestamp.
- **positionsByType**: Lists position IDs by type (long: 0, short: 1).
- **pendingPositions**: Tracks pending position IDs by listing and type.
- **positionToken**: Maps position ID to margin token (tokenA for long, tokenB for short).
- **longIOByHeight**: Tracks long open interest by block height.
- **shortIOByHeight**: Tracks short open interest by block height.
- **historicalInterestTimestamps**: Stores timestamps for interest updates.

## Structs
- **PositionCore1**: Contains `positionId` (uint256), `listingAddress` (address), `makerAddress` (address), `positionType` (uint8: 0 for long, 1 for short).
- **PositionCore2**: Includes `status1` (bool: active flag), `status2` (uint8: 0 for open, 1 for closed).
- **PriceParams1**: Stores `minEntryPrice`, `maxEntryPrice`, `minPrice`, `priceAtEntry` (uint256, normalized), `leverage` (uint8).
- **PriceParams2**: Holds `liquidationPrice` (uint256, normalized).
- **MarginParams1**: Tracks `initialMargin`, `taxedMargin`, `excessMargin`, `fee` (uint256, normalized).
- **MarginParams2**: Stores `initialLoan` (uint256, normalized).
- **ExitParams**: Includes `stopLossPrice`, `takeProfitPrice`, `exitPrice` (uint256, normalized).
- **OpenInterest**: Contains `leverageAmount` (uint256, normalized), `timestamp` (uint256).
- **EntryContext**: Parameters for position entry: `positionId`, `listingAddress`, `minEntryPrice`, `maxEntryPrice`, `initialMargin`, `excessMargin`, `leverage`, `positionType`, `maker`, `token`.
- **PrepPosition**: Computed position parameters: `fee`, `taxedMargin`, `leverageAmount`, `initialLoan`, `liquidationPrice`.

## Formulas
Formulas drive position calculations, detailed in their functional context.

1. **Fee Calculation**:
   - **Formula**: `fee = (initialMargin * (leverage - 1) * DECIMAL_PRECISION) / 100 / DECIMAL_PRECISION`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Computes fee based on leverage and margin, normalized to 1e18.

2. **Taxed Margin**:
   - **Formula**: `taxedMargin = normalizeAmount(token, initialMargin) - fee`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Margin after fee deduction, normalized for token decimals.

3. **Leverage Amount**:
   - **Formula**: `leverageAmount = normalizeAmount(token, initialMargin) * leverage`
   - **Used in**: `prepEnterLong`, `prepEnterShort`.
   - **Description**: Leveraged position size, normalized to 1e18.

4. **Initial Loan (Long)**:
   - **Formula**: `initialLoan = leverageAmount / minPrice`
   - **Used in**: `_computeLoanAndLiquidationLong`.
   - **Description**: Loan for long positions based on minimum entry price.

5. **Initial Loan (Short)**:
   - **Formula**: `initialLoan = leverageAmount * minPrice`
   - **Used in**: `_computeLoanAndLiquidationShort`.
   - **Description**: Loan for short positions based on minimum entry price.

6. **Liquidation Price (Long)**:
   - **Formula**: `liquidationPrice = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = makerTokenMargin[maker][tokenA] / leverageAmount`
   - **Used in**: `_computeLoanAndLiquidationLong`, `_updateLiquidationPrices`.
   - **Description**: Liquidation price for long positions, adjusted for updated margins.

7. **Liquidation Price (Short)**:
   - **Formula**: `liquidationPrice = minPrice + marginRatio`, where `marginRatio = makerTokenMargin[maker][tokenB] / leverageAmount`
   - **Used in**: `_computeLoanAndLiquidationShort`, `_updateLiquidationPrices`.
   - **Description**: Liquidation price for short positions, adjusted for updated margins.

8. **Liquidity Limit (Long)**:
   - **Formula**: `initialLoan <= yLiquid * (101 - leverage) / 100`, where `yLiquid` is tokenB liquidity
   - **Used in**: `_checkLiquidityLimitLong`.
   - **Description**: Ensures initial loan does not exceed available tokenB liquidity, scaled by leverage.

9. **Liquidity Limit (Short)**:
   - **Formula**: `initialLoan <= xLiquid * (101 - leverage) / 100`, where `xLiquid` is tokenA liquidity
   - **Used in**: `_checkLiquidityLimitShort`.
   - **Description**: Ensures initial loan does not exceed available tokenA liquidity, scaled by leverage.

10. **Payout (Long)**:
    - **Formula**: `payout = baseValue > initialLoan ? baseValue - initialLoan : 0`, where `baseValue = (taxedMargin + totalMargin + leverageAmount) / currentPrice`
    - **Used in**: `_computePayoutLong`, `prepCloseLong`.
    - **Description**: Payout for long position closure in tokenB, normalized.

11. **Payout (Short)**:
    - **Formula**: `payout = profit + (taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION`, where `profit = (priceAtEntry - currentPrice) * initialMargin * leverage`
    - **Used in**: `_computePayoutShort`, `prepCloseShort`.
    - **Description**: Payout for short position closure in tokenA, normalized.

12. **Margin Ratio**:
    - **Formula**: `marginRatio = totalMargin * DECIMAL_PRECISION / (initialMargin * leverage)`
    - **Used in**: `PositionHealthView`.
    - **Description**: Position health metric, normalized to 1e18.

13. **Distance to Liquidation (Long)**:
    - **Formula**: `distanceToLiquidation = currentPrice > liquidationPrice ? currentPrice - liquidationPrice : 0`
    - **Used in**: `PositionHealthView`.
    - **Description**: Liquidation risk for long positions, normalized.

14. **Distance to Liquidation (Short)**:
    - **Formula**: `distanceToLiquidation = currentPrice < liquidationPrice ? liquidationPrice - currentPrice : 0`
    - **Used in**: `PositionHealthView`.
    - **Description**: Liquidation risk for short positions, normalized.

15. **Estimated Profit/Loss (Long)**:
    - **Formula**: `estimatedProfitLoss = (taxedMargin + totalMargin + leverage * initialMargin) / currentPrice - initialLoan`
    - **Used in**: `PositionHealthView`.
    - **Description**: Profit/loss estimate for long positions, normalized.

16. **Estimated Profit/Loss (Short)**:
    - **Formula**: `estimatedProfitLoss = (priceAtEntry - currentPrice) * initialMargin * leverage + (taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION`
    - **Used in**: `PositionHealthView`.
    - **Description**: Profit/loss estimate for short positions, normalized.

## External Functions
Each function details its parameters, behavior, internal call flow (including external call inputs/returns, transfer destinations, and balance checks), restrictions, and gas controls. Mappings and structs are explained in context. Pre/post balance checks are explicitly described where applicable.

### setAgent(address newAgentAddress)
- **Parameters**:
  - `newAgentAddress` (address): New ISSAgent address.
- **Behavior**: Updates `agentAddress` state variable for listing validation in other functions.
- **Internal Call Flow**: Direct state update with no internal or external calls. Validates `newAgentAddress` is non-zero, then assigns it to `agentAddress`. No transfers or balance checks.
- **Mappings/Structs Used**:
  - **agentAddress** (state variable): Stores the ISSAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgentAddress` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write and simple check.

### enterLong(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (denormalized).
  - `maxEntryPrice` (uint256): Maximum entry price (denormalized).
  - `initialMargin` (uint256): Initial margin (denormalized).
  - `excessMargin` (uint256): Additional margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (denormalized).
  - `takeProfitPrice` (uint256): Take-profit price (denormalized).
- **Behavior**: Creates a pending long position, transferring margins in tokenA to the listing contract, computing fees, loans, and liquidation prices, and storing position data. Emits `PositionEntered`.
- **Internal Call Flow**: 
  - Invokes `_initiateEntry` with `positionType = 0`.
  - `_prepareEntryContext` creates `EntryContext` with inputs and `positionId` from `positionCount + 1`.
  - `_validateEntry` calls `_validateAndInit`, incrementing `positionCount`, invoking `ISSAgent.getListing` (input: `tokenA`, `tokenB` from `ISSListing`, returns: `listingAddress`) to validate listing, and selecting `tokenA` for margins. Ensures `initialMargin > 0` and `leverage` is 2–100.
  - `_computeEntryParams` calls `prepEnterLong`:
    - `_parseEntryPriceInternal` fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `currentPrice`), validating against `minEntryPrice` and `maxEntryPrice`.
    - `computeFee` applies fee formula.
    - `normalizeAmount` adjusts margins using `IERC20.decimals` (input: none, returns: `decimals`).
    - Updates `makerTokenMargin` and `makerMarginTokens` for `tokenA`.
    - `_computeLoanAndLiquidationLong` calculates loan and liquidation price using updated margin.
    - `_checkLiquidityLimitLong` verifies liquidity limit formula (`initialLoan <= yLiquid * (101 - leverage) / 100`) using `ISSLiquidityTemplate.liquidityDetailsView` (input: `this`, returns: `yLiquid`).
    - `_transferMarginToListing` handles transfers after calculations:
      - `_transferLiquidityFee` transfers fee in `tokenA` to `liquidityAddress` using `IERC20.transfer` (input: `liquidityAddress`, `denormalizedFee`, returns: `bool success`), with pre/post balance checks via `IERC20.balanceOf(liquidityAddr)`.
      - Transfers `taxedMargin + excessMargin` in `tokenA` to `listingAddress` using `IERC20.transferFrom` (input: `msg.sender`, `listingAddress`, `denormalizedAmount`, returns: `bool success`), with pre/post balance checks via `IERC20.balanceOf(listingAddress)`.
      - Calls `ISSLiquidityTemplate.addFees` (input: `this`, `true`, `denormalizedFee`, returns: none).
  - Updates `ISSListing.update` (input: `UpdateType[]` with type 0, `denormalizedAmount`, returns: none).
  - `_storeEntryData` calls `_setCoreData`, `_setPriceData`, `_setMarginData`, `_setExitData`, updating `pendingPositions`, `positionToken` (`tokenA`), and `longIOByHeight` via `updateHistoricalInterest`.
  - Transfer destinations: `liquidityAddress` (fee), `listingAddress` (margins).
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddr)` captures balance before fee transfer.
  - **Post-Balance Check (Fee)**: `balanceAfter - balanceBefore == denormalizedFee` confirms fee transfer.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(listingAddress)` captures balance before margin transfer.
  - **Post-Balance Check (Margin)**: `balanceAfter - balanceBefore == denormalizedAmount` confirms margin transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `pendingPositions`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `longIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `EntryContext`, `PrepPosition`, `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if listing is invalid, margin is zero, leverage is out of range, liquidity limit is exceeded, or transfers fail.
- **Gas Usage Controls**: Single-element array updates, balance checks, and no loops in critical paths minimize gas.

### enterShort(address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice)
- **Parameters**: Same as `enterLong`, for short positions.
- **Behavior**: Creates a pending short position, transferring margins in tokenB to the listing contract, computing fees, loans, and liquidation prices. Emits `PositionEntered`.
- **Internal Call Flow**: 
  - Mirrors `enterLong`, calling `_initiateEntry` with `positionType = 1`.
  - `prepEnterShort`:
    - Uses `_parseEntryPriceInternal` for price validation.
    - Computes fee and taxed margin.
    - Updates `makerTokenMargin` and `makerMarginTokens` for `tokenB`.
    - `_computeLoanAndLiquidationShort` calculates loan and liquidation price using updated margin.
    - `_checkLiquidityLimitShort` verifies liquidity limit formula (`initialLoan <= xLiquid * (101 - leverage) / 100`) using `ISSLiquidityTemplate.liquidityDetailsView` (input: `this`, returns: `xLiquid`).
    - `_transferMarginToListing` transfers fee in `tokenB` to `liquidityAddress` via `IERC20.transfer` and margins to `listingAddress` via `IERC20.transferFrom`, with pre/post balance checks.
    - Calls `ISSLiquidityTemplate.addFees` (input: `this`, `false`, `denormalizedFee`).
  - Updates `ISSListing.update` and stores data in same mappings/structs as `enterLong`, with `positionToken` as `tokenB` and `shortIOByHeight` updated.
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddr)` captures balance before fee transfer.
  - **Post-Balance Check (Fee)**: `balanceAfter - balanceBefore == denormalizedFee` confirms fee transfer.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(listingAddress)` captures balance before margin transfer.
  - **Post-Balance Check (Margin)**: `balanceAfter - balanceBefore == denormalizedAmount` confirms margin transfer.
- **Mappings/Structs Used**: Same as `enterLong`, with `positionToken` for `tokenB`, `shortIOByHeight`.
- **Restrictions**: Same as `enterLong`, with tokenA liquidity checks.
- **Gas Usage Controls**: Identical to `enterLong`.

### addExcessMargin(address listingAddress, bool tokenA, uint256 amount, address maker)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `tokenA` (bool): True for tokenA, false for tokenB.
  - `amount` (uint256): Margin to add (denormalized).
  - `maker` (address): Margin owner.
- **Behavior**: Adds margin to a maker’s balance, transferring the amount to the listing contract, updating liquidation prices, and recording interest. No event emitted.
- **Internal Call Flow**: 
  - Validates inputs (`amount > 0`, `maker` and `listingAddress` non-zero).
  - Calls `ISSAgent.isValidListing` (input: `listingAddress`, returns: `bool isValid`) to validate listing.
  - Selects token via `ISSListing.tokenA()` or `tokenB()`.
  - `_transferMarginToListing` transfers `amount` in selected token from `msg.sender` to `listingAddress` using `IERC20.transferFrom` (input: `msg.sender`, `listingAddress`, `amount`, returns: `bool success`), with pre/post balance checks via `IERC20.balanceOf(listingAddress)`.
  - `_updateListingMargin` calls `ISSListing.update` (input: `UpdateType[]` with type 0, `amount`, returns: none).
  - `_updateMakerMargin` updates `makerTokenMargin` and `makerMarginTokens`.
  - `_updatePositionLiquidationPrices` iterates `positionCount`, updating `priceParams2.liquidationPrice` for matching positions using `_computeLoanAndLiquidationLong` or `_computeLoanAndLiquidationShort` based on `positionType`.
  - `updateHistoricalInterest` updates `longIOByHeight` (positionType = 0).
  - Transfer destination: `listingAddress`.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(listingAddress)` captures balance before transfer.
  - **Post-Balance Check**: `balanceAfter - balanceBefore == amount` confirms transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `makerTokenMargin`, `makerMarginTokens`, `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `longIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `amount == 0`, `maker` or `listingAddress` is zero, listing is invalid, or transfer fails.
- **Gas Usage Controls**: Single transfer, array update, and full iteration for liquidation prices; optimized with pop-and-swap.

### pullMargin(address listingAddress, bool tokenA, uint256 amount)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `tokenA` (bool): True for tokenA, false for tokenB.
  - `amount` (uint256): Margin to withdraw (denormalized).
- **Behavior**: Withdraws margin from `msg.sender`’s balance, updating liquidation prices, transferring to `msg.sender`, and recording interest. No event emitted.
- **Internal Call Flow**: 
  - `_validateAndNormalizePullMargin` validates inputs (`amount > 0`, `listingAddress` non-zero), checks listing via `ISSAgent.isValidListing`, selects token, normalizes `amount`, and verifies `normalizedAmount <= makerTokenMargin`.
  - `_updatePositionLiquidationPrices` updates liquidation prices for matching positions before margin deduction.
  - `_reduceMakerMargin` deducts `normalizedAmount` from `makerTokenMargin`, calling `_removeToken` if balance is zero.
  - `_executeMarginPayout` calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `msg.sender`, `amount`, returns: none) to transfer `amount` in selected token to `msg.sender`.
  - `updateHistoricalInterest` updates `shortIOByHeight` (positionType = 1).
  - Transfer destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `normalizedAmount <= makerTokenMargin[msg.sender][token]` ensures sufficient margin.
  - **Post-Balance Check**: None, as transfer is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `makerTokenMargin`, `makerMarginTokens`, `positionCore1`, `positionCore2`, `priceParams1`, `priceParams sho2`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `amount == 0`, listing is invalid, or margin is insufficient.
- **Gas Usage Controls**: Minimal updates, pop-and-swap for arrays, full iteration for liquidation prices.

### closeLongPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a long position, computing payout in tokenB, transferring to `msg.sender`, and removing position. Emits `PositionClosed`.
- **Internal Call Flow**: 
  - Validates position in `positionCore1`, ensures not closed (`positionCore2.status2 == 0`) and owned by `msg.sender`.
  - `prepCloseLong`:
    - `_computePayoutLong` uses payout formula for tokenB.
    - `_deductMarginAndRemoveToken` deducts `taxedMargin + excessMargin` from `makerTokenMargin` (tokenA) with pre-balance check.
    - `_executePayoutUpdate` updates `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `msg.sender`, `denormalizedPayout`, returns: none), sets `exitParams.exitPrice` and `positionCore2.status2`.
  - `removePositionIndex` updates `positionsByType` and `pendingPositions`.
  - Payout destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenA] >= taxedMargin + excessMargin` ensures sufficient margin.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `exitParams`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `ExitParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, or not owned.
- **Gas Usage Controls**: Single position processing with pop-and-swap minimizes gas.

### closeShortPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a short position, paying out in tokenA to `msg.sender`, and removes position. Emits `PositionClosed`.
- **Internal Call Flow**: 
  - Similar to `closeLongPosition`, but calls `prepCloseShort`:
    - `_computePayoutShort` uses payout formula for tokenA.
    - `_deductMarginAndRemoveToken` deducts margins for tokenB with pre-balance check.
    - `_executePayoutUpdate` updates `ISSListing.ssUpdate` for tokenA payout.
  - `removePositionIndex` updates arrays.
  - Payout destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenB] >= taxedMargin + excessMargin` ensures sufficient margin.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**: Same as `closeLongPosition`, with tokenB margins and tokenA payouts.
- **Restrictions**: Same as `closeLongPosition`.
- **Gas Usage Controls**: Identical to `closeLongPosition`.

### cancelPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to cancel.
- **Behavior**: Cancels a pending position, returning margins to `msg.sender` and removing position. Emits `PositionCancelled`.
- **Internal Call Flow**: 
  - Validates position in `positionCore1`, ensures not closed, not active (`positionCore2.status1 == false`), and owned by `msg.sender`.
  - Deducts `taxedMargin + excessMargin` from `makerTokenMargin` (`positionToken`) with pre-balance check, calling `_removeToken` if zero.
  - Sets `positionCore2.status2 = 1`, `exitParams.exitPrice = 0`.
  - Updates `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `msg.sender`, `denormalizedMargin`, returns: none) to transfer margins in `positionToken`.
  - Calls `removePositionIndex` for `pendingPositions`.
  - Margin destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[msg.sender][positionToken] >= taxedMargin + excessMargin` ensures sufficient margin.
  - **Post-Balance Check**: None, as transfer is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `exitParams`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `ExitParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, active, or not owned.
- **Gas Usage Controls**: Minimal updates with pop-and-swap for arrays.

### updateSL(uint256 positionId, uint256 newStopLossPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newStopLossPrice` (uint256): New stop-loss price (denormalized).
- **Behavior**: Updates stop-loss price. Emits `StopLossUpdated`.
- **Internal Call Flow**: 
  - Validates position in `positionCore1`, ensures not closed (`positionCore2.status2 == 0`) and owned by `msg.sender`.
  - Normalizes prices with `normalizePrice`, fetching `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `currentPrice`).
  - Calls `_updateSL` to set `exitParams.stopLossPrice`.
  - No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `exitParams`, `positionToken`, `priceParams1`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `ExitParams`, `PriceParams1`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, not owned, or stop-loss is invalid (`newStopLossPrice > 0 || newStopLossPrice == 0`).
- **Gas Usage Controls**: Single state update, minimal gas.

### updateTP(uint256 positionId, uint256 newTakeProfitPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newTakeProfitPrice` (uint256): New take-profit price (denormalized).
- **Behavior**: Updates take-profit price. Emits `TakeProfitUpdated`.
- **Internal Call Flow**: 
  - Similar to `updateSL`, but calls `_updateTP`.
  - Validates `newTakeProfitPrice` (`> priceAtEntry` for long, `< priceAtEntry` for short, or `0`).
  - Uses `normalizePrice` and `ISSListing.prices`.
  - Sets `exitParams.takeProfitPrice`.
  - No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**: Same as `updateSL`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, not owned, or take-profit is invalid.
- **Gas Usage Controls**: Same as `updateSL`.

### closeAllLongs(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active long positions for `msg.sender`, transferring payouts in tokenB. Emits `AllLongsClosed` and `PositionClosed` per position.
- **Internal Call Flow**: 
  - Iterates `positionCount`, processing up to `maxIterations` long, active, non-closed positions owned by `msg.sender`.
  - For each, calls `prepCloseLong`, updates `ISSListing.ssUpdate` with `PayoutUpdate` for tokenB to `msg.sender`, calls `removePositionIndex`, and emits `PositionClosed`.
  - Pre-balance checks on `makerTokenMargin` ensure sufficient margins.
  - Payout destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenA] >= taxedMargin + excessMargin` per position.
  - **Post-Balance Check**: None, as payouts are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `exitParams`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `ExitParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Skips non-matching positions.
- **Gas Usage Controls**: Uses `maxIterations` and `gasleft() >= 50000`. Pop-and-swap optimizes arrays.

### cancelAllLongs(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending long positions, returning margins in tokenA to `msg.sender`. Emits `AllLongsCancelled` and `PositionCancelled` per position.
- **Internal Call Flow**: 
  - Iterates `positionCount`, processing up to `maxIterations` pending long positions.
  - For each, deducts margins from `makerTokenMargin` with pre-balance checks, updates `positionCore2` and `exitParams`, calls `removePositionIndex`, and emits `PositionCancelled`.
  - Margin destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenA] >= taxedMargin + excessMargin` per position.
  - **Post-Balance Check**: None, as transfers are handled by `ISSListing`.
- **Mappings/Structs Used**: Same as `cancelPosition`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Skips non-matching positions.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### closeAllShorts(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active short positions, paying out in tokenA to `msg.sender`. Emits `AllShortsClosed` and `PositionClosed` per position.
- **Internal Call Flow**: 
  - Similar to `closeAllLongs`, using `prepCloseShort` for tokenA payouts.
  - Pre-balance checks on `makerTokenMargin` for tokenB.
  - Payout destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenB] >= taxedMargin + excessMargin` per position.
  - **Post-Balance Check**: None, as payouts are handled by `ISSListing`.
- **Mappings/Structs Used**: Same as `closeShortPosition`.
- **Restrictions**: Same as `closeAllLongs`.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### cancelAllShorts(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending short positions, returning margins in tokenB to `msg.sender`. Emits `AllShortsCancelled` and `PositionCancelled` per position.
- **Internal Call Flow**: 
  - Similar to `cancelAllLongs`, for short positions with tokenB margins.
  - Pre-balance checks on `makerTokenMargin`.
  - Margin destination: `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[maker][tokenB] >= taxedMargin + excessMargin` per position.
  - **Post-Balance Check**: None, as transfers are handled by `ISSListing`.
- **Mappings/Structs Used**: Same as `cancelPosition`.
- **Restrictions**: Same as `closeAllLongs`.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### executePositions(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Processes pending and active positions, activating or closing them based on price triggers, with payouts or liquidations. Emits `PositionClosed` as needed.
- **Internal Call Flow**: 
  - Calls `_executePositions`, iterating over long and short types.
  - For pending positions in `pendingPositions`, `_processPendingPosition`:
    - Updates liquidation price via `_updateLiquidationPrices`.
    - Uses `_parseEntryPriceInternal` (via `ISSListing.prices`) to check liquidation (`currentPrice <= priceParams2.liquidationPrice` for long, `>=` for short) or entry conditions.
    - If liquidating, calls `prepCloseLong`/`prepCloseShort` with pre-balance checks, updates `ISSListing.ssUpdate`, removes positions via `removePositionIndex`, and emits `PositionClosed`.
    - If within entry range, sets `positionCore2.status1 = true` and moves to `positionsByType`.
  - For active positions in `positionsByType`, `_processActivePosition`:
    - Updates liquidation price via `_updateLiquidationPrices`.
    - Checks triggers (stop-loss, take-profit, liquidation) using `normalizePrice` and `ISSListing.prices`, closing positions with payouts.
  - Payouts go to `positionCore1.makerAddress` in tokenB (long) or tokenA (short).
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[makerAddress][positionToken] >= taxedMargin + excessMargin` during `prepCloseLong`/`prepCloseShort`.
  - **Post-Balance Check**: None, as payouts are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `exitParams`, `positionsByType`, `pendingPositions`, `marginParams1`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `ExitParams`, `MarginParams1`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `listingAddress` is zero.
- **Gas Usage Controls**: `maxIterations` and `gasleft() >= 50000` limit gas. Pop-and-swap reduces array costs.

### PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `positionType` (uint8): 0 for long, 1 for short.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns position IDs from `positionsByType` starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Iterates `positionsByType` for `positionType`, returning up to `maxIterations` IDs. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionsByType`.
- **Restrictions**: Reverts if `positionType > 1` (`"Invalid position type"`).
- **Gas Usage Controls**: View function, `maxIterations` limits iteration, minimal gas.

### PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `maker` (address): Position owner.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns pending position IDs for `maker` starting at `startIndex`, up to `maxIterations`.
- **Internal Call Flow**: Iterates `positionCount`, filtering by `positionCore1.makerAddress == maker` and `positionCore2.status1 == false`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`.
  - **Structs**: `PositionCore1`, `PositionCore2`.
- **Restrictions**: None.
- **Gas Usage Controls**: `maxIterations`, view function, low gas.

### positionByIndex(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns all position data (core, price, margin, exit, token).
- **Internal Call Flow**: Retrieves data from `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `positionToken`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `positionToken`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `MarginParams1`, `MarginParams2`, `ExitParams`.
- **Restrictions**: Reverts if `positionId` is invalid (`"Invalid position"`).
- **Gas Usage Controls**: Minimal gas, view function.

### TotalActivePositionsView()
- **Parameters**: None.
- **Behavior**: Counts active positions (`status1 == true`, `status2 == 0`).
- **Internal Call Flow**: Iterates `positionCount`, checking `positionCore1` and `positionCore2`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`.
  - **Structs**: `PositionCore1`, `PositionCore2`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, full iteration, no state changes.

### queryInterest(uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `startIndex` (uint256): Starting block height.
  - `maxIterations` (uint256): Maximum entries to return.
- **Behavior**: Returns open interest (`longIOByHeight`, `shortIOByHeight`) and timestamps (`historicalInterestTimestamps`).
- **Internal Call Flow**: Iterates `startIndex` to `startIndex + maxIterations`, retrieving data from `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
- **Restrictions**: None.
- **Gas Usage Controls**: `maxIterations`, view function, low gas.

### makerMarginIndex(address maker, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `maker` (address): Margin owner.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum tokens to return.
- **Behavior**: Returns tokens and margins for `maker` from `makerMarginTokens` and `makerTokenMargin`.
- **Internal Call Flow**: Iterates `makerMarginTokens` from `startIndex` up to `maxIterations`, retrieving margins from `makerTokenMargin`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `makerTokenMargin`, `makerMarginTokens`.
- **Restrictions**: None.
- **Gas Usage Controls**: `maxIterations`, view function, minimal gas.

### PositionHealthView(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns margin ratio, liquidation distance, and estimated profit/loss using formulas.
- **Internal Call Flow**: 
  - Retrieves data from `positionCore1`, `marginParams1`, `priceParams1`, `priceParams2`, `positionToken`.
  - Uses `normalizePrice` and `ISSListing.prices` (input: `listingAddress`, returns: `currentPrice`) for health metrics.
  - Computes `marginRatio`, `distanceToLiquidation`, and `estimatedProfitLoss` for long or short positions.
  - No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `marginParams1`, `priceParams1`, `priceParams2`, `positionToken`, `makerTokenMargin`.
  - **Structs**: `PositionCore1`, `MarginParams1`, `PriceParams1`, `PriceParams2`.
- **Restrictions**: Reverts if position or price is invalid (`"Invalid position"`, `"Invalid price"`).
- **Gas Usage Controls**: Minimal gas, view function.

### AggregateMarginByToken(address tokenA, address tokenB, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `tokenA`, `tokenB` (address): Token pair for listing.
  - `startIndex` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Returns makers and margins for a listing’s tokenB from `positionsByType`.
- **Internal Call Flow**: 
  - Calls `ISSAgent.getListing` (input: `tokenA`, `tokenB`, returns: `listingAddress`).
  - Iterates `positionsByType` for both types, collecting `makerTokenMargin` data for `tokenB`.
  - No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionsByType`, `positionCore1`, `makerTokenMargin`.
  - **Structs**: `PositionCore1`.
- **Restrictions**: Reverts if listing is invalid (`"Invalid listing"`).
- **Gas Usage Controls**: `maxIterations`, view function, minimal gas.

### OpenInterestTrend(address listingAddress, uint256 startIndex, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing address.
  - `startIndex` (uint256): Starting position ID.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns leverage amounts and timestamps for open positions (`status2 == 0`) in `listingAddress`.
- **Internal Call Flow**: Iterates `positionCount`, filtering by `positionCore1.listingAddress` and `positionCore2.status2 == 0`, retrieving `openInterest`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `openInterest`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `OpenInterest`.
- **Restrictions**: None.
- **Gas Usage Controls**: `maxIterations`, view function, minimal gas.

### LiquidationRiskCount(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Counts positions within 5% of liquidation price.
- **Internal Call Flow**: 
  - Iterates `positionCount` up to `maxIterations`, checking `positionCore1`, `positionCore2`, `priceParams2`.
  - Uses `normalizePrice` and `ISSListing.prices` (input: `listingAddress`, returns: `currentPrice`) to compare `currentPrice` with `liquidationPrice ± 5%`.
  - No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams2`, `positionToken`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `PriceParams2`.
- **Restrictions**: None.
- **Gas Usage Controls**: `maxIterations`, view function, low gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization across token decimals, via `normalizeAmount`, `denormalizeAmount`, `normalizePrice`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Employs `maxIterations`, `gasleft() >= 50000`, and pop-and-swap for arrays.
- **Listing Validation**: Uses `ISSAgent.isValidListing` or `ISSAgent.getListing` for robust checks.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts.
- **Position Lifecycle**: Pending (`status1 == false`) to active (`status1 == true`) to closed (`status2 == 1`), with state updates.
- **Events**: Emitted for entry (`PositionEntered`), closure (`PositionClosed`), cancellation (`PositionCancelled`), SL/TP updates (`StopLossUpdated`, `TakeProfitUpdated`), and batch operations (`AllLongsClosed`, `AllLongsCancelled`, `AllShortsClosed`, `AllShortsCancelled`).
- **Safety**: Balance checks, explicit casting, no inline assembly, and liquidation price updates ensure robustness.
- **Liquidation Price Updates**: `addExcessMargin` and `pullMargin` update liquidation prices for all relevant positions to reflect margin changes, ensuring accurate risk assessment.

# SSIsolatedDriver Contract Documentation

## Overview
The `SSIsolatedDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short strategies, inheriting functionality through `SSDExecutionPartial` to `SSDPositionPartial` to `SSDUtilityPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`) and uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles position creation, closure, cancellation, margin adjustments, and stop-loss/take-profit updates, with gas optimization and safety mechanisms. State variables are hidden, accessed via view functions, and decimal precision is maintained across tokens.

**Inheritance Tree:** `SSIsolatedDriver` → `SSDExecutionPartial` → `SSDPositionPartial` → `SSDUtilityPartial`

**SPDX License:** BSD-3-Clause

**Version:** 0.0.13 (last updated 2025-06-17)

## Mappings
- **positionCoreBase**: Stores core position data (maker, listing, ID, type).
- **positionCoreStatus**: Tracks position status (pending/executable, open/closed/cancelled).
- **priceParams**: Holds price data (min/max entry, entry, close).
- **marginParams**: Manages margin details (initial, taxed, excess).
- **leverageParams**: Stores leverage details (value, amount, initial loan).
- **riskParams**: Contains risk parameters (liquidation, stop-loss, take-profit prices).
- **pendingPositions**: Tracks pending position IDs by listing and type.
- **positionsByType**: Stores position IDs by type (long/short).
- **positionToken**: Maps position ID to token (tokenA for long, tokenB for short).
- **longIOByHeight**: Tracks long open interest by block height.
- **shortIOByHeight**: Tracks short open interest by block height.
- **historicalInterestTimestamps**: Stores timestamps for interest updates.
- **pendingEntries**: Temporary storage for position entry parameters.
- **pendingCloses**: Temporary storage for position closure parameters.
- **pendingActions**: Temporary storage for position actions.

## Structs
- **PositionCoreBase**: Contains maker address, listing address, position ID, position type (long/short).
- **PositionCoreStatus**: Tracks pending/executable flag, status (open/closed/cancelled).
- **PriceParams**: Stores minimum/maximum entry prices, entry price, close price.
- **MarginParams**: Holds initial, taxed, excess margins.
- **LeverageParams**: Contains leverage value, amount, initial loan.
- **RiskParams**: Stores liquidation, stop-loss, take-profit prices.
- **PosParamsCore**: Combines price and margin parameters.
- **PosParamsExt**: Combines leverage and risk parameters.
- **EntryParamsBase**: Stores listing address, entry price string, initial/excess margins.
- **EntryParamsRisk**: Stores leverage value, stop-loss, take-profit prices.
- **EntryParamsToken**: Stores token address, normalized margins, driver address.
- **ClosePositionBase**: Stores position ID, listing/maker addresses, driver.
- **ClosePositionMargin**: Stores taxed and excess margins.
- **LongCloseParams**: Stores leverage amount, initial loan for long positions.
- **ShortCloseParams**: Stores minimum price, initial margin, leverage for short positions.
- **PositionAction**: Stores position ID, action type (update status/close).
- **ExecutionContextBase**: Stores listing address, driver, current price.
- **ExecutionContextCounts**: Stores action count, maximum actions.
- **EntryContext**: Stores listing/token addresses, normalized margins.
- **PendingEntry**: Stores entry parameters for position creation.
- **PendingClose**: Stores closure parameters (price, payout, decimals, listing, maker, type).
- **PendingAction**: Stores action parameters (type, listing, orphaned status, action type).
- **PayoutUpdate**: Stores recipient, required amount, payout type.
- **UpdateType**: Stores update type, index, value, address, recipient.

## Formulas
Formulas drive position calculations, detailed in their functional context.

1. **Fee Calculation**:
   - **Formula**: `fee = (leverageVal - 1) * normMarginInitial / 100`
   - **Used in**: `updateLiquidityFees` (called by `finalizeEntryFees` in `enterLong`, `enterShort`).
   - **Description**: Computes fee based on leverage and normalized initial margin.

2. **Taxed Margin**:
   - **Formula**: `marginTaxed = initialMargin - ((leverage - 1) * initialMargin / 100)`
   - **Used in**: `computeParamsHelper`.
   - **Description**: Margin after fee deduction.

3. **Leverage Amount**:
   - **Formula**: `leverageAmount = initialMargin * leverage`
   - **Used in**: `computeParamsHelper`.
   - **Description**: Leveraged position size.

4. **Initial Loan (Long)**:
   - **Formula**: `loanInitial = leverageAmount / (minPrice / 1e18)`
   - **Used in**: `computeParamsHelper`.
   - **Description**: Loan for long positions based on minimum entry price.

5. **Initial Loan (Short)**:
   - **Formula**: `loanInitial = leverageAmount * minPrice`
   - **Used in**: `computeParamsHelper`.
   - **Description**: Loan for short positions based on minimum entry price.

6. **Liquidation Price (Long)**:
   - **Formula**: `priceLiquidation = marginRatio < minPrice ? minPrice - marginRatio : 0`, where `marginRatio = (excessMargin + marginTaxed) / leverageAmount`
   - **Used in**: `computeParamsHelper`.
   - **Description**: Liquidation price for long positions.

7. **Liquidation Price (Short)**:
   - **Formula**: `priceLiquidation = minPrice + marginRatio`
   - **Used in**: `computeParamsHelper`.
   - **Description**: Liquidation price for short positions.

8. **Liquidity Limit (Long)**:
   - **Formula**: `loanInitial <= yLiquid * (101 - leverageVal) / 100`, where `yLiquid` is tokenB liquidity
   - **Used in**: `validateLeverageLimit`.
   - **Description**: Ensures initial loan does not exceed tokenB liquidity, scaled by leverage.

9. **Liquidity Limit (Short)**:
   - **Formula**: `loanInitial <= xLiquid * (101 - leverageVal) / 100`, where `xLiquid` is tokenA liquidity
   - **Used in**: `validateLeverageLimit`.
   - **Description**: Ensures initial loan does not exceed tokenA liquidity, scaled by leverage.

10. **Payout (Long)**:
    - **Formula**: `payout = totalValue > loanInitial ? (totalValue / currentPrice) - loanInitial : 0`, where `totalValue = taxedMargin + excessMargin + leverageAmount`
    - **Used in**: `computeLongPayout`.
    - **Description**: Payout for long position closure in tokenB.

11. **Payout (Short)**:
    - **Formula**: `payout = profit + (taxedMargin + excessMargin) * currentPrice`, where `profit = (priceMin - currentPrice) * initialMargin * leverageVal`
    - **Used in**: `computeShortPayout`.
    - **Description**: Payout for short position closure in tokenA.

## External Functions
Each function details its parameters, behavior, internal call flow (including external call inputs/returns, transfer destinations, and balance checks), restrictions, and gas controls. Mappings and structs are explained in context. Pre/post balance checks are explicitly described where applicable.

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ISSAgent address.
- **Behavior**: Updates `agent` state variable for listing validation.
- **Internal Call Flow**: Directly updates `agent`. No internal or external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores the ISSAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Agent not set"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### enterLong(address listingAddr, string entryPriceStr, uint256 initMargin, uint256 extraMargin, uint8 leverage, uint256 stopLoss, uint256 takeProfit)
- **Parameters**:
  - `listingAddr` (address): Listing contract address.
  - `entryPriceStr` (string): Entry price range (e.g., "100-200").
  - `initMargin` (uint256): Initial margin (denormalized).
  - `extraMargin` (uint256): Excess margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLoss` (uint256): Stop-loss price (normalized).
  - `takeProfit` (uint256): Take-profit price (normalized).
- **Behavior**: Creates a pending long position, transferring margins in tokenA to the listing contract, computing fees, loans, and liquidation prices, and storing position data. Emits `PositionEntered`.
- **Internal Call Flow**: Calls `initiateEntry` with `positionType = 0`. `prepareEntryContext` fetches `tokenA` via `ISSListing.tokenA` (input: `listingAddr`, returns: `address`) and normalizes margins with `normalizeAmount` (`IERC20.decimals`, input: none, returns: `uint8`). Creates `EntryContext`. `prepareEntryBase` increments `positionIdCounter` and stores `PendingEntry`. `prepareEntryRisk` and `prepareEntryToken` set parameters. `validateEntryBase` calls `validateListing` with `ISSAgent.getListing` (input: `tokenA`, `tokenB`, returns: `listingAddr`) and checks `initMargin > 0`. `validateEntryRisk` ensures `leverage` is 2–100. `updateEntryCore` sets `PositionCoreBase` and `PositionCoreStatus`. `updateEntryParams` calls `updateEntryParamsCompute` (`parseEntryPriceHelper` uses `ISSListing.prices`, input: `listingAddr`, returns: `uint256`; `computeParams`), `updateEntryParamsValidate` (`validateLeverageLimit` uses `ISSLiquidityTemplate.liquidityDetailsView`, input: `this`, returns: `yLiquid`), and `updateEntryParamsStore` (`prepareCoreParams`, `prepareExtParams`, `updateLiquidityFees`). `updateLiquidityFees` transfers fee in tokenA to `liquidityAddress` via `IERC20.transferFrom` (input: `msg.sender`, `liquidityAddress`, `denormFee`, returns: `bool`), with pre-balance check (`IERC20.balanceOf(liquidityAddress)`) and post-balance check (`checkTransferAmount`). Calls `ISSLiquidityTemplate.addFees` (input: `this`, `true`, `actualFee`, returns: none). `finalizeEntry` transfers `remainingMargin + extraMargin` in tokenA to `listingAddr` via `IERC20.transferFrom` (input: `msg.sender`, `listingAddr`, `expectedAmount`, returns: `bool`), with pre/post balance checks (`IERC20.balanceOf(listingAddr)`). Calls `ISSListing.update` (input: `UpdateType[]` with `io`, returns: none). Updates `positionToken`, `pendingPositions`, `longIOByHeight` via `updateHistoricalInterest`. Transfers go to `liquidityAddress` (fee) and `listingAddr` (margins).
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddress)` before fee transfer.
  - **Post-Balance Check (Fee)**: `checkTransferAmount` confirms fee transfer.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(listingAddr)` before margin transfer.
  - **Post-Balance Check (Margin)**: `checkTransferAmount` confirms margin transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `pendingPositions`, `positionToken`, `longIOByHeight`, `historicalInterestTimestamps`, `pendingEntries`.
  - **Structs**: `EntryContext`, `PendingEntry`, `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PosParamsCore`, `PosParamsExt`, `EntryParamsBase`, `EntryParamsRisk`, `EntryParamsToken`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if listing is invalid, margin is zero, leverage is out of range, liquidity limit is exceeded, or transfers fail.
- **Gas Usage Controls**: Single-element array updates, balance checks, and pop-and-swap minimize gas.

### enterShort(address listingAddr, string entryPriceStr, uint256 initMargin, uint256 extraMargin, uint8 leverage, uint256 stopLoss, uint256 takeProfit)
- **Parameters**: Same as `enterLong`, for short positions.
- **Behavior**: Creates a pending short position, transferring margins in tokenB to the listing, computing fees, loans, and liquidation prices. Emits `PositionEntered`.
- **Internal Call Flow**: Mirrors `enterLong`, with `positionType = 1`. `prepareEntryContext` uses `ISSListing.tokenB`. `validateLeverageLimit` checks `xLiquid` via `ISSLiquidityTemplate.liquidityDetailsView`. Transfers use tokenB for fee (`ISSLiquidityTemplate.addFees` with `isX = false`) and margins. Updates `shortIOByHeight`. Other calls are identical.
- **Balance Checks**: Same as `enterLong`, for tokenB.
- **Mappings/Structs Used**: Same as `enterLong`, with `shortIOByHeight`.
- **Restrictions**: Same as `enterLong`.
- **Gas Usage Controls**: Identical to `enterLong`.

### addExcessMargin(uint256 positionId, uint256 amount, address token)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `amount` (uint256): Margin to add (denormalized).
  - `token` (address): Token address.
- **Behavior**: Adds margin to an open position, transferring to the listing contract, updating margin and interest, and recalculating liquidation price. Emits `ExcessMarginAdded`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status2 == 0`. Normalizes `amount` with `normalizeAmount` (`IERC20.decimals`). Calls `addExcessMarginInternal`, which invokes `validateExcessMargin` (checks `normalizedAmount <= leverageAmount`), `transferExcessMargin` (transfers via `IERC20.transferFrom`, input: `msg.sender`, `listingAddress`, `amount`, returns: `bool`), `updateMarginAndInterest` (updates `marginParams.marginExcess`, calls `transferMarginToListing` with `ISSListing.update`, updates `longIOByHeight` or `shortIOByHeight` via `updateHistoricalInterest`), and `updateLiquidationPrice` (recalculates `riskParams.priceLiquidation` using `computeParamsHelper`). Pre-balance check (`IERC20.balanceOf(listingAddress)`); post-balance check (`checkTransferAmount`). Transfer destination is `listingAddress`.
- **Balance Checks**:
  - **Pre-Balance Check**: `IERC20.balanceOf(listingAddress)` before transfer.
  - **Post-Balance Check**: `checkTransferAmount` confirms transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `LeverageParams`, `RiskParams`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is closed, amount is zero, exceeds leverage, or transfer fails.
- **Gas Usage Controls**: Single transfer and array update minimize gas.

### closeLongPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a long position, computing payout in tokenB, transferring to `msg.sender`, and removing the position. Emits `PositionClosed`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status2 == 0`, `status1 == true`, and owned by `msg.sender`. Calls `internalCloseLongPosition`: `prepareCloseBase` sets `PendingClose`; `prepareClosePrice` fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `uint256`) and `decimalsB`; `prepareClosePayout` uses `computeLongPayout`; `finalizeClose` updates `positionCoreStatus.status2 = 1`, calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `payout`, returns: none) for tokenB payout, adjusts `longIOByHeight`, increments `historicalInterestHeight`, and calls `removePositionIndex`. Pre-balance check in `validatePositionStatus`; no post-balance check as payout is handled by `ISSListing`. Payout destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` and `status1 == true` ensure position is open and executable.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `positionToken`, `positionsByType`, `pendingPositions`, `longIOByHeight`, `historicalInterestTimestamps`, `pendingCloses`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `ClosePositionBase`, `ClosePositionMargin`, `LongCloseParams`, `PendingClose`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, not executable, or not owned.
- **Gas Usage Controls**: Single position processing with pop-and-swap minimizes gas.

### closeShortPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a short position, paying out in tokenA to `msg.sender`, and removes the position. Emits `PositionClosed`.
- **Internal Call Flow**: Similar to `closeLongPosition`, but calls `internalCloseShortPosition` with `computeShortPayout` and `decimalsA` for tokenA payout. Updates `shortIOByHeight`. Payout destination is `msg.sender`.
- **Balance Checks**: Same as `closeLongPosition`.
- **Mappings/Structs Used**: Same as `closeLongPosition`, with `shortIOByHeight`.
- **Restrictions**: Same as `closeLongPosition`.
- **Gas Usage Controls**: Identical to `closeLongPosition`.

### cancelPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to cancel.
- **Behavior**: Cancels a pending position, returning margins to `msg.sender` and removing it. Emits `PositionCancelled`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status1 == false`, `status2 == 0`, and owned by `msg.sender`. Calls `internalCancelPosition`: sets `positionCoreStatus.status2 = 2`, calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `totalMargin`, returns: none) for `positionToken` margin return, adjusts `longIOByHeight` or `shortIOByHeight`, increments `historicalInterestHeight`, and calls `removePositionIndex`. Pre-balance check in `validatePositionStatus`; no post-balance check as transfer is handled by `ISSListing`. Margin destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status1 == false` and `status2 == 0` ensure position is pending and open.
  - **Post-Balance Check**: None, as transfer is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `positionToken`, `pendingPositions`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `ClosePositionBase`, `ClosePositionMargin`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, executable, closed, or not owned.
- **Gas Usage Controls**: Minimal updates with pop-and-swap for arrays.

### updateSL(uint256 positionId, uint256 newStopLossPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newStopLossPrice` (uint256): New stop-loss price (normalized).
- **Behavior**: Updates the stop-loss price for an open position. Emits `StopLossUpdated`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status2 == 0` and owned by `msg.sender`. Fetches `currentPrice` via `ISSListing.prices`. Validates `newStopLossPrice` (`< currentPrice` for long, `> currentPrice` for short). Calls `updateSLInternal` to set `riskParams.priceStopLoss`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `RiskParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, not owned, or stop-loss is invalid (`"Stop loss too high for long"` or `"Stop loss too low for short"`).
- **Gas Usage Controls**: Single state update, minimal gas.

### updateTP(uint256 positionId, uint256 newTakeProfitPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newTakeProfitPrice` (uint256): New take-profit price (normalized).
- **Behavior**: Updates the take-profit price for an open position. Emits `TakeProfitUpdated`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status2 == 0` and owned by `msg.sender`. Validates `newTakeProfitPrice` (`> priceAtEntry` for long, `< priceAtEntry` for short). Calls `updateTPInternal` to set `riskParams.priceTakeProfit`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `RiskParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid, closed, not owned, or take-profit is invalid (`"Take profit too low for long"` or `"Take profit too high for short"`).
- **Gas Usage Controls**: Single state update, minimal gas.

### closeAllLongs(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active long positions for `msg.sender`, transferring payouts in tokenB. Emits `AllLongsClosed` with count of closed positions.
- **Internal Call Flow**: Calls `closeAllLongsInternal`, iterating `positionsByType[0]` up to `maxIterations`. For each matching position (`status2 == 0`, `status1 == true`, owned), calls `internalCloseLongPosition` (see `closeLongPosition`) and emits `PositionClosed`. Payout destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` and `status1 == true` per position.
  - **Post-Balance Check**: None, as payouts are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `leverageParams`, `positionsByType`, `longIOByHeight`, `historicalInterestTimestamps`, `pendingCloses`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `LeverageParams`, `ClosePositionBase`, `ClosePositionMargin`, `LongCloseParams`, `PendingClose`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Skips non-matching positions.
- **Gas Usage Controls**: `maxIterations` and `gasleft() >= 100000`. Pop-and-swap optimizes array operations.

### cancelAllLong(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending long positions for `msg.sender`, returning margins in tokenA. Emits `AllLongsCancelled` with count of cancelled positions.
- **Internal Call Flow**: Calls `cancelAllLongInternal`, iterating `pendingPositions[msg.sender][0]` up to `maxIterations`. For each matching position (`status1 == false`, `status2 == 0`), calls `internalCancelPosition` (see `cancelPosition`) and emits `PositionCancelled`. Margin destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status1 == false` and `status2 == 0` per position.
  - **Post-Balance Check**: None, as transfers are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `pendingPositions`, `longIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `ClosePositionBase`, `ClosePositionMargin`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Skips non-matching positions.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### closeAllShort(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Closes all active short positions for `msg.sender`, paying out in tokenA. Emits `AllShortsClosed` with count of closed positions.
- **Internal Call Flow**: Calls `closeAllShortInternal`, iterating `positionsByType[1]` up to `maxIterations`. For each matching position, calls `internalCloseShortPosition` (see `closeShortPosition`) and emits `PositionClosed`. Payout destination is `msg.sender`.
- **Balance Checks**: Same as `closeAllLongs`.
- **Mappings/Structs Used**: Same as `closeAllLongs`, with `shortIOByHeight`.
- **Restrictions**: Same as `closeAllLongs`.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### cancelAllShort(uint256 maxIterations)
- **Parameters**:
  - `maxIterations` (uint256): Maximum positions to process.
- **Behavior**: Cancels all pending short positions for `msg.sender`, returning margins in tokenB. Emits `AllShortsCancelled` with count of cancelled positions.
- **Internal Call Flow**: Calls `cancelAllShortInternal`, iterating `pendingPositions[msg.sender][1]` up to `maxIterations`. For each matching position, calls `internalCancelPosition` (see `cancelPosition`) and emits `PositionCancelled`. Margin destination is `msg.sender`.
- **Balance Checks**: Same as `cancelAllLong`.
- **Mappings/Structs Used**: Same as `cancelAllLong`, with `shortIOByHeight`.
- **Restrictions**: Same as `closeAllLongs`.
- **Gas Usage Controls**: Same as `closeAllLongs`.

### executePositions(address listingAddress)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
- **Behavior**: Processes pending and active positions, activating or closing them based on price triggers (entry, liquidation, stop-loss, take-profit). Emits `PositionsExecuted` with count of processed positions.
- **Internal Call Flow**: Calls `prepareExecution`, creating `ExecutionContextBase` with `getCurrentPrice` (`ISSListing.prices`). Iterates `pendingPositions` via `processPendingActions` (checks entry conditions via `processPendingPosition`) and `positionsByType` via `processActiveActionsInternal` (checks triggers via `computeActiveAction`). `finalizeActions` stores actions. `executePositionsLogic` calls `updatePositionStatusHelper` (moves position to `positionsByType`, updates `status1 = true`) or `executeClosePosition` (invokes `internalCloseLongPosition` or `internalCloseShortPosition`). Payouts go to `makerAddress` in tokenB (long) or tokenA (short) via `ISSListing.ssUpdate`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` and `status1 == true` during `executeClosePosition`.
  - **Post-Balance Check**: None, as payouts are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionsByType`, `pendingPositions`, `positionToken`, `pendingCloses`, `pendingActions`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PositionAction`, `ExecutionContextBase`, `ExecutionContextCounts`, `PendingClose`, `PendingAction`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `listingAddress` is zero.
- **Gas Usage Controls**: `gasleft() >= 100000`, pop-and-swap for arrays.

### positionsByTypeView(uint8 positionType, uint256 step, uint256 maxIterations)
- **Parameters**:
  - `positionType` (uint8): 0 for long, 1 for short.
  - `step` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns active position IDs from `positionsByType` starting at `step`, up to `maxIterations`.
- **Internal Call Flow**: Iterates `positionsByType[positionType]` from `step` up to `maxIterations`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionsByType`.
- **Restrictions**: Reverts if `positionType > 1`.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### positionsByAddressView(address user, uint8 positionType, uint256 step, uint256 maxIterations)
- **Parameters**:
  - `user` (address): Position owner.
  - `positionType` (uint8): 0 for long, 1 for short.
  - `step` (uint256): Starting index.
  - `maxIterations` (uint256): Maximum positions to return.
- **Behavior**: Returns pending position IDs for `user` from `pendingPositions` starting at `step`, up to `maxIterations`.
- **Internal Call Flow**: Iterates `pendingPositions[user][positionType]` from `step` up to `maxIterations`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `pendingPositions`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

### positionByIndex(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID.
- **Behavior**: Returns all position data (core, status, price, margin, leverage, risk, token).
- **Internal Call Flow**: Retrieves data from `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`.
- **Restrictions**: Reverts if ID is invalid.
- **Gas Usage Controls**: View function, minimal gas.

### queryInterest(uint256 step, uint256 maxIterations)
- **Parameters**:
  - `step` (uint256): Starting block height.
  - `maxIterations` (uint256): Maximum entries to return.
- **Behavior**: Returns open interest (`longIOByHeight`, `shortIOByHeight`) and `historicalInterestTimestamps` from `step` up to `maxIterations`.
- **Internal Call Flow**: Iterates `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps` from `step` up to `maxIterations`. No external calls, transfers, or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, `maxIterations` limits gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization across token decimals, with `IERC20.decimals` for token-specific precision.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Employs `maxIterations`, `gasleft() >= 100000`, and pop-and-swap for array operations.
- **Listing Validation**: Uses `ISSAgent.getListing` for robust checks.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts.
- **Position Lifecycle**: Pending (`status1 = false`, `status2 = 0`) to executable (`status1 = true`, `status2 = 0`) to closed (`status2 = 1`) or cancelled (`status2 = 2`).
- **Events**: Emitted for entry (`PositionEntered`), closure (`PositionClosed`), cancellation (`PositionCancelled`), margin addition (`ExcessMarginAdded`), SL/TP updates (`StopLossUpdated`, `TakeProfitUpdated`), and batch operations (`AllLongsClosed`, `AllLongsCancelled`, `AllShortsClosed`, `AllShortsCancelled`, `PositionsExecuted`).
- **Safety**: Balance checks, explicit casting, no inline assembly, and modular helpers (`validateExcessMargin`, `transferExcessMargin`, `updateMarginAndInterest`, `updateLiquidationPrice`, `updateSLInternal`, `updateTPInternal`) ensure robustness.


