 # Shock Space Contracts Documentation
The System comprises of SSAgent, SSListingLogic, SSLiquidityLogic, SSListingTemplate, SSLiquidityTemplate, SSRouter, SSCrossDriver, and SSIsolatedDriver.

Together they form an AMM Orderbook Hybrid for leverage trading on the EVM. 

## SSLiquidityLogic Contract
The liquidity logic inherits liquidity Template and is used by the SSAgent to deploy new liquidity contracts tied to listing contracts for a unique TokeA and B pair. 

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
The listing logic inherits listing Template and is used by the SSAgent to deploy new listing contracts tied to liquidity contracts for a unique TokeA and B pair. 

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
The agent manages token listings and global data, it enables the creation of unique listings + liquidities for token pairs and is the arbitrator for valid listings - templates and routers. 

### Mappings and Arrays
- `getListing` (mapping - address, address, address): Maps tokenA to tokenB to the listing address for a trading pair.
- `allListings` (address[]): Array of all listing addresses created.
- `allListedTokens` (address[]): Array of all unique tokens listed.
- `queryByAddress` (mapping - address, uint256[]): Maps a token to an array of listing IDs involving that token.
- `globalLiquidity` (mapping - address, address, address, uint256): Tracks liquidity per user for each tokenA-tokenB pair.
- `totalLiquidityPerPair` (mapping - address, address, uint256): Total liquidity for each tokenA-tokenB pair.
- `userTotalLiquidity` (mapping - address, uint256): Total liquidity contributed by each user across all pairs.
- `listingLiquidity` (mapping - uint256, address, uint256): Liquidity per user for each listing ID.
- `liquidityProviders` (mapping - uint256, address[]): Maps listing ID to an array of users who provided liquidity.
- `historicalLiquidityPerPair` (mapping - address, address, uint256, uint256): Historical liquidity for each tokenA-tokenB pair at specific timestamps.
- `historicalLiquidityPerUser` (mapping - address, address, address, uint256, uint256): Historical liquidity per user for each tokenA-tokenB pair at specific timestamps.
- `globalOrders` (mapping - address, address, uint256, GlobalOrder): Stores order details for each tokenA-tokenB pair by order ID.
- `pairOrders` (mapping - address, address, uint256[]): Array of order IDs for each tokenA-tokenB pair.
- `userOrders` (mapping - address, uint256[]): Array of order IDs created by each user.
- `historicalOrderStatus` (mapping - address, address, uint256, uint256, uint8): Historical status of orders for each tokenA-tokenB pair at specific timestamps.
- `userTradingSummaries` (mapping - address, address, address, uint256): Trading volume per user for each tokenA-tokenB pair.

### State Variables
- `routers` (address[]): Array of router contract addresses, set post-deployment via addRouter.
- `listingLogicAddress` (address): Address of the SSListingLogic contract, set post-deployment.
- `liquidityLogicAddress` (address): Address of the SSLiquidityLogic contract, set post-deployment.
- `registryAddress` (address): Address of the registry contract, set post-deployment.
- `listingCount` (uint256): Counter for the number of listings created, incremented per listing.

### Functions

#### Setter Functions
- **addRouter**
  - **Parameters:**
    - `router` (address): Address to add to the routers array.
  - **Actions:**
    - Requires non-zero address and that the router does not already exist.
    - Appends the router to the routers array.
    - Emits RouterAdded event.
    - Restricted to owner via onlyOwner modifier.
- **removeRouter**
  - **Parameters:**
    - `router` (address): Address to remove from the routers array.
  - **Actions:**
    - Requires non-zero address and that the router exists.
    - Removes the router by swapping with the last element and popping the array.
    - Emits RouterRemoved event.
    - Restricted to owner via onlyOwner modifier.
- **getRouters**
  - **Actions:**
    - Returns the current routers array.
  - **Returns:**
    - `address[]`: Array of all router addresses.
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
    - Verifies at least one router, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract with routers array, listing ID, liquidity address, tokens, agent, and registry.
    - Calls _initializeLiquidity to set up liquidity contract with routers array, listing ID, listing address, tokens, and agent.
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
    - Verifies at least one router, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract with routers array, listing ID, liquidity address, tokens, agent, and registry.
    - Calls _initializeLiquidity to set up liquidity contract with routers array, listing ID, listing address, tokens, and agent.
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
    - If isDeposit, adds amount to globalLiquidity, totalLiquidityPerPair, userTotalLiquidity, and listingLiquidity, and appends user to liquidityProviders if their liquidity was previously zero.
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
    - Constructs ListingDetails struct with listingAddress, liquidityAddress, tokenA, tokenB, and listingId.
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
    - Validates non-zero maxIterations and valid listingId.
    - Limits to maxIterations or liquidityProviders length for the listing.
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

# SSListingTemplate Documentation

## Overview
The `SSListingTemplate` contract, implemented in Solidity (^0.8.2), forms part of a decentralized trading platform. `SSListingTemplate` manages buy/sell orders, payouts, and volume balances, it inherits `ReentrancyGuard` for security and use `SafeERC20` for token operations, integrating with `ISSAgent` and `ITokenRegistry` for global updates and synchronization. State variables are private, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision across token decimals. The contracts avoid reserved keywords, use explicit casting, and ensure graceful degradation.

**SPDX License**: BSD-3-Clause

**Version**: 0.0.10 (Updated 2025-06-23)

### State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set, prevents re-setting.
- **`tokenX`**: `address private` - Address of token X (or ETH if zero).
- **`tokenY`**: `address private` - Address of token Y (or ETH if zero).
- **`decimalX`**: `uint8 private` - Decimals of token X (18 for ETH).
- **`decimalY`**: `uint8 private` - Decimals of token Y (18 for ETH).
- **`listingId`**: `uint256 public` - Unique identifier for the listing.
- **`agent`**: `address public` - Address of the agent contract for global updates.
- **`registryAddress`**: `address public` - Address of the token registry contract.
- **`liquidityAddress`**: `address public` - Address of the liquidity contract.
- **`nextOrderId`**: `uint256 public` - Next available order ID for payouts/orders.
- **`lastDayFee`**: `LastDayFee public` - Stores `xFees`, `yFees`, and `timestamp` for daily fee tracking.
- **`volumeBalance`**: `VolumeBalance public` - Stores `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **`price`**: `uint256 public` - Current price, calculated as `(xBalance * 1e18) / yBalance`.
- **`pendingBuyOrders`**: `uint256[] public` - Array of pending buy order IDs.
- **`pendingSellOrders`**: `uint256[] public` - Array of pending sell order IDs.
- **`longPayoutsByIndex`**: `uint256[] public` - Array of long payout order IDs.
- **`shortPayoutsByIndex`**: `uint256[] public` - Array of short payout order IDs.
- **`historicalData`**: `HistoricalData[] public` - Array of historical market data.

### Mappings
- **`routers`**: `mapping(address => bool)` - Maps addresses to authorized routers.
- **`buyOrderCores`**: `mapping(uint256 => BuyOrderCore)` - Maps order ID to buy order core data (`makerAddress`, `recipientAddress`, `status`).
- **`buyOrderPricings`**: `mapping(uint256 => BuyOrderPricing)` - Maps order ID to buy order pricing (`maxPrice`, `minPrice`).
- **`buyOrderAmounts`**: `mapping(uint256 => BuyOrderAmounts)` - Maps order ID to buy order amounts (`pending`, `filled`, `amountSent`).
- **`sellOrderCores`**: `mapping(uint256 => SellOrderCore)` - Maps order ID to sell order core data (`makerAddress`, `recipientAddress`, `status`).
- **`sellOrderPricings`**: `mapping(uint256 => SellOrderPricing)` - Maps order ID to sell order pricing (`maxPrice`, `minPrice`).
- **`sellOrderAmounts`**: `mapping(uint256 => SellOrderAmounts)` - Maps order ID to sell order amounts (`pending`, `filled`, `amountSent`).
- **`longPayouts`**: `mapping(uint256 => LongPayoutStruct)` - Maps order ID to long payout data (`makerAddress`, `recipientAddress`, `required`, `filled`, `orderId`, `status`).
- **`shortPayouts`**: `mapping(uint256 => ShortPayoutStruct)` - Maps order ID to short payout data (`makerAddress`, `recipientAddress`, `amount`, `filled`, `orderId`, `status`).
- **`makerPendingOrders`**: `mapping(address => uint256[])` - Maps maker address to their pending order IDs.
- **`userPayoutIDs`**: `mapping(address => uint256[])` - Maps user address to their payout order IDs.

### Structs
1. **LastDayFee**:
   - `xFees`: `uint256` - Token X fees at start of day.
   - `yFees`: `uint256` - Token Y fees at start of day.
   - `timestamp`: `uint256` - Timestamp of last fee update.

2. **VolumeBalance**:
   - `xBalance`: `uint256` - Normalized balance of token X.
   - `yBalance`: `uint256` - Normalized balance of token Y.
   - `xVolume`: `uint256` - Normalized trading volume of token X.
   - `yVolume`: `uint256` - Normalized trading volume of token Y.

3. **BuyOrderCore**:
   - `makerAddress`: `address` - Address of the order creator.
   - `recipientAddress`: `address` - Address to receive tokens.
   - `status`: `uint8` - Order status (0=cancelled, 1=pending, 2=partially filled, 3=filled).

4. **BuyOrderPricing**:
   - `maxPrice`: `uint256` - Maximum acceptable price (normalized).
   - `minPrice`: `uint256` - Minimum acceptable price (normalized).

5. **BuyOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenY).
   - `filled`: `uint256` - Normalized filled amount (tokenY).
   - `amountSent`: `uint256` - Normalized amount of tokenX sent during settlement.

6. **SellOrderCore**:
   - Same as `BuyOrderCore` for sell orders.

7. **SellOrderPricing**:
   - Same as `BuyOrderPricing` for sell orders.

8. **SellOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenX).
   - `filled`: `uint256` - Normalized filled amount (tokenX).
   - `amountSent`: `uint256` - Normalized amount of tokenY sent during settlement.

9. **PayoutUpdate**:
   - `payoutType`: `uint8` - Type of payout (0=long, 1=short).
   - `recipient`: `address` - Address to receive payout.
   - `required`: `uint256` - Normalized amount required.

10. **LongPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `required`: `uint256` - Normalized amount required (tokenY).
    - `filled`: `uint256` - Normalized amount filled (tokenY).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).

11. **ShortPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `amount`: `uint256` - Normalized payout amount (tokenX).
    - `filled`: `uint256` - Normalized amount filled (tokenX).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).

12. **HistoricalData**:
    - `price`: `uint256` - Market price at timestamp (normalized).
    - `xBalance`: `uint256` - Token X balance (normalized).
    - `yBalance`: `uint256` - Token Y balance (normalized).
    - `xVolume`: `uint256` - Token X volume (normalized).
    - `yVolume`: `uint256` - Token Y volume (normalized).
    - `timestamp`: `uint256` - Time of data snapshot.

13. **UpdateType**:
    - `updateType`: `uint8` - Update type (0=balance, 1=buy order, 2=sell order, 3=historical).
    - `structId`: `uint8` - Struct to update (0=core, 1=pricing, 2=amounts).
    - `index`: `uint256` - Order ID or balance index (0=xBalance, 1=yBalance, 2=xVolume, 3=yVolume).
    - `value`: `uint256` - Normalized amount or price.
    - `addr`: `address` - Maker address.
    - `recipient`: `address` - Recipient address.
    - `maxPrice`: `uint256` - Max price or packed xBalance/yBalance (historical).
    - `minPrice`: `uint256` - Min price or packed xVolume/yVolume (historical).
    - `amountSent`: `uint256` - Normalized amount of opposite token sent during settlement.

### Formulas
1. **Price Calculation**:
   - **Formula**: `price = (xBalance * 1e18) / yBalance`
   - **Used in**: `update`, `transact`
   - **Description**: Computes current price when `xBalance` and `yBalance` are non-zero, used for order pricing and historical data.

2. **Daily Yield**:
   - **Formula**: `dailyYield = ((feeDifference * 0.0005) * 1e18) / liquidity * 365`
   - **Used in**: `queryYield`
   - **Description**: Calculates annualized yield from `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`), using 0.05% fee rate and liquidity from `SSLiquidityTemplate`.

### External Functions
#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet` to true.
- **Restrictions**: Reverts if `routersSet` is true or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` - Listing ID.
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setLiquidityAddress(address _liquidityAddress)
- **Parameters**: `_liquidityAddress` - Liquidity contract address.
- **Behavior**: Sets `liquidityAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `liquidityAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` - Token addresses.
- **Behavior**: Sets `tokenX`, `tokenY`, `decimalX`, `decimalY`, callable once.
- **Internal Call Flow**: Fetches decimals via `IERC20.decimals` (18 for ETH).
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes and external calls.

#### setAgent(address _agent)
- **Parameters**: `_agent` - Agent contract address.
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setRegistry(address _registryAddress)
- **Parameters**: `_registryAddress` - Registry contract address.
- **Behavior**: Sets `registryAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `registryAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` - Router address.
  - `updates` - Array of update structs.
- **Behavior**: Updates balances, orders, or historical data, triggers `globalizeUpdate`.
- **Internal Call Flow**:
  - Checks `volumeUpdated` to update `lastDayFee` if new day.
  - Processes `updates`:
    - `updateType=0`: Updates `xBalance`, `yBalance`, `xVolume`, `yVolume`.
    - `updateType=1`: Updates buy order `core`, `pricing`, or `amounts` (including `amountSent` for tokenX), adjusts `pendingBuyOrders`, `makerPendingOrders`, `yBalance`, `yVolume`, `xBalance`.
    - `updateType=2`: Updates sell order `core`, `pricing`, or `amounts` (including `amountSent` for tokenY), adjusts `pendingSellOrders`, `makerPendingOrders`, `xBalance`, `xVolume`, `yBalance`.
    - `updateType=3`: Adds `HistoricalData` with packed balances/volumes.
  - Updates `price`, calls `globalizeUpdate`, emits `BalancesUpdated` or `OrderUpdated`.
- **Balance Checks**: Ensures sufficient `xBalance`/`yBalance` for order updates, adjusts for `amountSent`.
- **Mappings/Structs Used**:
  - **Mappings**: `buyOrderCores`, `buyOrderPricings`, `buyOrderAmounts`, `sellOrderCores`, `sellOrderPricings`, `sellOrderAmounts`, `pendingBuyOrders`, `pendingSellOrders`, `makerPendingOrders`, `historicalData`.
  - **Structs**: `UpdateType`, `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`, `HistoricalData`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`, emits events for updates.

#### ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates)
- **Parameters**:
  - `caller` - Router address.
  - `payoutUpdates` - Array of payout updates.
- **Behavior**: Creates long/short payout orders, increments `nextOrderId`.
- **Internal Call Flow**:
  - Creates `LongPayoutStruct` (tokenY) or `ShortPayoutStruct` (tokenX), updates `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`.
  - Increments `nextOrderId`, emits `PayoutOrderCreated`.
- **Balance Checks**: None, defers to `transact`.
- **Mappings/Structs Used**:
  - **Mappings**: `longPayouts`, `shortPayouts`, `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`.
  - **Structs**: `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`.
- **Gas Usage Controls**: Loop over `payoutUpdates`, dynamic arrays, minimal state writes.

#### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - Router address.
  - `token` - TokenX or tokenY.
  - `amount` - Denormalized amount.
  - `recipient` - Recipient address.
- **Behavior**: Transfers tokens/ETH, updates balances, and registry.
- **Internal Call Flow**:
  - Normalizes `amount` using `decimalX` or `decimalY`.
  - Checks `xBalance` (tokenX) or `yBalance` (tokenY).
  - Transfers via `SafeERC20.safeTransfer` or ETH call with try-catch.
  - Updates `xVolume`/`yVolume`, `lastDayFee`, `price`.
  - Calls `_updateRegistry`, emits `BalancesUpdated`.
- **Balance Checks**: Pre-transfer balance check for `xBalance` or `yBalance`.
- **Mappings/Structs Used**:
  - **Mappings**: `volumeBalance`.
  - **Structs**: `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal state updates, try-catch error handling.

#### queryYield(bool isA, uint256 maxIterations)
- **Parameters**:
  - `isA` - True for tokenX, false for tokenY.
  - `maxIterations` - Max historical data iterations.
- **Behavior**: Returns annualized yield based on daily fees.
- **Internal Call Flow**:
  - Checks `lastDayFee.timestamp`, ensures same-day calculation.
  - Computes `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`).
  - Fetches liquidity (`xLiquid` or `yLiquid`) via `ISSLiquidityTemplate.liquidityAmounts`.
  - Calculates `dailyYield = (feeDifference * 0.0005 * 1e18) / liquidity * 365`.
- **Balance Checks**: None, relies on external `liquidityAmounts` call.
- **Mappings/Structs Used**:
  - **Mappings**: `volumeBalance`, `lastDayFee`.
  - **Structs**: `LastDayFee`, `VolumeBalance`.
- **Restrictions**: Reverts if `maxIterations` is zero or no historical data/same-day timestamp.
- **Gas Usage Controls**: Minimal, single external call, try-catch for `liquidityAmounts`.

#### prices(uint256) view returns (uint256)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns current `price`.
- **Gas Usage Controls**: Minimal, single state read.

#### volumeBalances(uint256) view returns (uint256 xBalance, uint256 yBalance)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns `xBalance`, `yBalance` from `volumeBalance`.
- **Mappings/Structs Used**: `volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### liquidityAddressView(uint256) view returns (address)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns `liquidityAddress`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenA() view returns (address)
- **Behavior**: Returns `tokenX`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenB() view returns (address)
- **Behavior**: Returns `tokenY`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsA() view returns (uint8)
- **Behavior**: Returns `decimalX`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsB() view returns (uint8)
- **Behavior**: Returns `decimalY`.
- **Gas Usage Controls**: Minimal, single state read.

#### getListingId() view returns (uint256)
- **Behavior**: Returns `listingId`.
- **Gas Usage Controls**: Minimal, single state read.

#### getNextOrderId() view returns (uint256)
- **Behavior**: Returns `nextOrderId`.
- **Gas Usage Controls**: Minimal, single state read.

#### listingVolumeBalancesView() view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)
- **Behavior**: Returns all fields from `volumeBalance`.
- **Mappings/Structs Used**: `volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### listingPriceView() view returns (uint256)
- **Behavior**: Returns `price`.
- **Gas Usage Controls**: Minimal, single state read.

#### pendingBuyOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `pendingBuyOrders`.
- **Mappings/Structs Used**: `pendingBuyOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### pendingSellOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `pendingSellOrders`.
- **Mappings/Structs Used**: `pendingSellOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### makerPendingOrdersView(address maker) view returns (uint256[] memory)
- **Parameters**: `maker` - Maker address.
- **Behavior**: Returns maker's pending order IDs.
- **Mappings/Structs Used**: `makerPendingOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### longPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `longPayoutsByIndex`.
- **Mappings/Structs Used**: `longPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### shortPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `shortPayoutsByIndex`.
- **Mappings/Structs Used**: `shortPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### userPayoutIDsView(address user) view returns (uint256[] memory)
- **Parameters**: `user` - User address.
- **Behavior**: Returns user's payout order IDs.
- **Mappings/Structs Used**: `userPayoutIDs`.
- **Gas Usage Controls**: Minimal, array read.

#### getLongPayout(uint256 orderId) view returns (LongPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `LongPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `longPayouts` (`LongPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getShortPayout(uint256 orderId) view returns (ShortPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `ShortPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `shortPayouts` (`ShortPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `buyOrderCores` (`BuyOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `buyOrderPricings` (`BuyOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenX).
- **Mappings/Structs Used**: `buyOrderAmounts` (`BuyOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `sellOrderCores` (`SellOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `sellOrderPricings` (`SellOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenY).
- **Mappings/Structs Used**: `sellOrderAmounts` (`SellOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getHistoricalDataView(uint256 index) view returns (HistoricalData memory)
- **Parameters**: `index` - Historical data index.
- **Behavior**: Returns `HistoricalData` at given index.
- **Mappings/Structs Used**: `historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if `index` is invalid.
- **Gas Usage Controls**: Minimal, single array read.

#### historicalDataLengthView() view returns (uint256)
- **Behavior**: Returns length of `historicalData`.
- **Mappings/Structs Used**: `historicalData`.
- **Gas Usage Controls**: Minimal, single state read.

#### getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) view returns (HistoricalData memory)
- **Parameters**: `targetTimestamp` - Target timestamp.
- **Behavior**: Returns `HistoricalData` with timestamp closest to `targetTimestamp`.
- **Mappings/Structs Used**: `historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if no historical data exists.
- **Gas Usage Controls**: Loop over `historicalData`, minimal state reads.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts, fetched via `IERC20.decimals` or `decimalX`/`decimalY`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, try-catch for external calls (`globalizeOrders`, `initializeBalances`, `liquidityAmounts`).
- **Token Usage**:
  - Buy orders: Input tokenY, output tokenX, `amountSent` tracks tokenX.
  - Sell orders: Input tokenX, output tokenY, `amountSent` tracks tokenY.
  - Long payouts: Output tokenY, no `amountSent`.
  - Short payouts: Output tokenX, no `amountSent`.
- **Events**: `OrderUpdated`, `PayoutOrderCreated`, `BalancesUpdated`.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ISSListingTemplate`, `IERC20`).
  - No inline assembly, uses high-level Solidity.
  - Try-catch for external calls to handle failures gracefully.
  - Hidden state variables (`tokenX`, `tokenY`, `decimalX`, `decimalY`) accessed via view functions.
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
- **Compatibility**: Aligned with `SSRouter` (v0.0.48), `SSAgent` (v0.0.2), `SSLiquidityTemplate` (v0.0.6), `SSOrderPartial` (v0.0.18).

# SSLiquidityTemplate Documentation

## Overview
The `SSLiquidityTemplate`, implemented in Solidity (^0.8.2), forms part of a decentralized trading platform, handling liquidity deposits, withdrawals, and fee claims. It inherits `ReentrancyGuard` for security and uses `SafeERC20` for token operations, integrating with `ISSAgent` and `ITokenRegistry` for global updates and synchronization. State variables are private, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision across token decimals. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License**: BSD-3-Clause

**Version**: 0.0.13 (Updated 2025-06-30)

### State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set, prevents re-setting.
- **`listingAddress`**: `address public` - Address of the listing contract.
- **`tokenA`**: `address public` - Address of token A (or ETH if zero).
- **`tokenB`**: `address public` - Address of token B (or ETH if zero).
- **`listingId`**: `uint256 public` - Unique identifier for the listing.
- **`agent`**: `address public` - Address of the agent contract for global updates.
- **`liquidityDetail`**: `LiquidityDetails public` - Stores `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- **`activeXLiquiditySlots`**: `uint256[] public` - Array of active xSlot indices.
- **`activeYLiquiditySlots`**: `uint256[] public` - Array of active ySlot indices.

### Mappings
- **`routers`**: `mapping(address => bool)` - Maps addresses to authorized routers.
- **`xLiquiditySlots`**: `mapping(uint256 => Slot)` - Maps slot index to token A slot data.
- **`yLiquiditySlots`**: `mapping(uint256 => Slot)` - Maps slot index to token B slot data.
- **`userIndex`**: `mapping(address => uint256[])` - Maps user address to their slot indices.

### Structs
1. **LiquidityDetails**:
   - `xLiquid`: `uint256` - Normalized liquidity for token A.
   - `yLiquid`: `uint256` - Normalized liquidity for token B.
   - `xFees`: `uint256` - Normalized fees for token A.
   - `yFees`: `uint256` - Normalized fees for token B.
   - `xFeesAcc`: `uint256` - Cumulative fee volume for token A.
   - `yFeesAcc`: `uint256` - Cumulative fee volume for token B.

2. **Slot**:
   - `depositor`: `address` - Address of the slot owner.
   - `recipient`: `address` - Unused recipient address.
   - `allocation`: `uint256` - Normalized liquidity allocation.
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit or last claim (yFeesAcc for xSlots, xFeesAcc for ySlots).
   - `timestamp`: `uint256` - Slot creation timestamp.

3. **UpdateType**:
   - `updateType`: `uint8` - Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
   - `index`: `uint256` - Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot index).
   - `value`: `uint256` - Normalized amount or allocation.
   - `addr`: `address` - Depositor address.
   - `recipient`: `address` - Unused recipient address.

4. **PreparedWithdrawal**:
   - `amountA`: `uint256` - Normalized withdrawal amount for token A.
   - `amountB`: `uint256` - Normalized withdrawal amount for token B.

5. **FeeClaimContext**:
   - `caller`: `address` - User address.
   - `isX`: `bool` - True for token A, false for token B.
   - `liquid`: `uint256` - Total liquidity (xLiquid or yLiquid).
   - `allocation`: `uint256` - Slot allocation.
   - `fees`: `uint256` - Available fees (yFees for xSlots, xFees for ySlots).
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit or last claim.
   - `liquidityIndex`: `uint256` - Slot index.

### Formulas
1. **Fee Share**:
   - **Formula**: 
     ```
     contributedFees = feesAcc - dFeesAcc
     liquidityContribution = (allocation * 1e18) / liquid
     feeShare = (contributedFees * liquidityContribution) / 1e18
     feeShare = feeShare > fees ? fees : feeShare
     ```
   - **Used in**: `_claimFeeShare`
   - **Description**: Computes fee share for a liquidity slot based on accumulated fees since deposit or last claim (`feesAcc` is `yFeesAcc` for xSlots, `xFeesAcc` for ySlots) and liquidity proportion, capped at available fees (`yFees` for xSlots, `xFees` for ySlots).

### External Functions
#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet`.
- **Restrictions**: Reverts if `routersSet` is true or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` - Listing ID.
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setListingAddress(address _listingAddress)
- **Parameters**: `_listingAddress` - Listing contract address.
- **Behavior**: Sets `listingAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` - Token addresses.
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes.

#### setAgent(address _agent)
- **Parameters**: `_agent` - Agent contract address.
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` - User address.
  - `updates` - Array of update structs.
- **Behavior**: Updates liquidity or fees, manages slots.
- **Internal Call Flow**:
  - Processes `updates`:
    - `updateType=0`: Updates `xLiquid` or `yLiquid`.
    - `updateType=1`: Updates `xFees` or `yFees`, emits `FeesUpdated`.
    - `updateType=2`: Updates `xLiquiditySlots`, `activeXLiquiditySlots`, `userIndex`, sets `dFeesAcc` to `yFeesAcc`.
    - `updateType=3`: Updates `yLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, sets `dFeesAcc` to `xFeesAcc`.
  - Emits `LiquidityUpdated`.
- **Balance Checks**: Checks `xLiquid` or `yLiquid` for balance updates.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`, no external calls.

#### changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `slotIndex` - Slot index.
  - `newDepositor` - New depositor address.
- **Behavior**: Transfers slot ownership to `newDepositor`.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots` or `yLiquiditySlots`, adjusts `userIndex`.
  - Emits `SlotDepositorChanged`.
- **Balance Checks**: Verifies slot `allocation` is non-zero.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `userIndex`.
  - **Structs**: `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, caller must be current depositor.
- **Gas Usage Controls**: Single slot update, array adjustments.

#### deposit(address caller, address token, uint256 amount)
- **Parameters**:
  - `caller` - User address.
  - `token` - Token A or B.
  - `amount` - Denormalized amount.
- **Behavior**: Deposits tokens/ETH to liquidity pool, creates new slot.
- **Internal Call Flow**:
  - Performs pre/post balance checks for tokens, validates `msg.value` for ETH.
  - Transfers via `SafeERC20.transferFrom` or ETH deposit.
  - Normalizes `amount`, creates `UpdateType` for slot allocation (sets `dFeesAcc`).
  - Calls `update`, `globalizeUpdate`, `updateRegistry`.
- **Balance Checks**: Pre/post balance for tokens, `msg.value` for ETH.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal updates, try-catch for external calls.

#### xPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Parameters**:
  - `caller` - User address.
  - `amount` - Normalized amount.
  - `index` - Slot index.
- **Behavior**: Prepares token A withdrawal, calculates compensation in token B.
- **Internal Call Flow**:
  - Checks `xLiquid` and slot `allocation` in `xLiquiditySlots`.
  - Fetches `ISSListing.getPrice` to compute `withdrawAmountB` if liquidity deficit.
  - Returns `PreparedWithdrawal` with `amountA` and `amountB`.
- **Balance Checks**: Verifies `xLiquid`, `yLiquid` sufficiency.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `PreparedWithdrawal`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid slot.
- **Gas Usage Controls**: Minimal, single external call to `getPrice`.

#### xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**:
  - `caller` - User address.
  - `index` - Slot index.
  - `withdrawal` - Withdrawal amounts (`amountA`, `amountB`).
- **Behavior**: Executes token A withdrawal, transfers tokens/ETH.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots`, `liquidityDetail` via `update`.
  - Transfers `amountA` (token A) and `amountB` (token B) via `SafeERC20` or ETH.
  - Calls `globalizeUpdate`, `updateRegistry` for both tokens.
- **Balance Checks**: Verifies `xLiquid`, `yLiquid` before transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `activeXLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `PreparedWithdrawal`, `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid slot.
- **Gas Usage Controls**: Two transfers, minimal updates, try-catch for transfers.

#### yPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Parameters**: Same as `xPrepOut`.
- **Behavior**: Prepares token B withdrawal, calculates compensation in token A.
- **Internal Call Flow**: Checks `yLiquid`, `xLiquid`, uses `ISSListing.getPrice` for `withdrawAmountA`.
- **Balance Checks**: Verifies `yLiquid`, `xLiquid` sufficiency.
- **Mappings/Structs Used**: `yLiquiditySlots`, `liquidityDetail`, `PreparedWithdrawal`, `Slot`.
- **Restrictions**: Same as `xPrepOut`.
- **Gas Usage Controls**: Same as `xPrepOut`.

#### yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**: Same as `xExecuteOut`.
- **Behavior**: Executes token B withdrawal, transfers tokens/ETH.
- **Internal Call Flow**: Updates `yLiquiditySlots`, transfers `amountB` (token B) and `amountA` (token A).
- **Balance Checks**: Verifies `yLiquid`, `xLiquid` before transfers.
- **Mappings/Structs Used**: `yLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`, `PreparedWithdrawal`, `UpdateType`, `Slot`.
- **Restrictions**: Same as `xExecuteOut`.
- **Gas Usage Controls**: Same as `xExecuteOut`.

#### claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 volume)
- **Parameters**:
  - `caller` - User address.
  - `_listingAddress` - Listing contract address.
  - `liquidityIndex` - Slot index.
  - `isX` - True for token A, false for token B.
  - `volume` - Unused (ignored for compatibility).
- **Behavior**: Claims fees (yFees for xSlots, xFees for ySlots), resets `dFeesAcc` to current `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots).
- **Internal Call Flow**:
  - Validates listing via `ISSListing.volumeBalances`.
  - Creates `FeeClaimContext` to optimize stack usage (~7 variables).
  - Calls `_processFeeClaim`, which:
    - Fetches slot data (`xLiquiditySlots` or `yLiquiditySlots`).
    - Calls `_claimFeeShare` to compute `feeShare` using `contributedFees = feesAcc - dFeesAcc` and liquidity proportion.
    - Updates `xFees`/`yFees` and slot allocation via `update`.
    - Resets `dFeesAcc` to `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots) to track fees since last claim.
    - Transfers fees via `transact` (yFees for xSlots, xFees for ySlots).
    - Emits `FeesClaimed` with fee amounts.
- **Balance Checks**: Verifies `xBalance` (from `volumeBalances`), `xLiquid`/`yLiquid`, `xFees`/`yFees`.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `FeeClaimContext`, `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, caller must be depositor, valid listing address.
- **Gas Usage Controls**: Single transfer, struct-based stack optimization, try-catch for `transact`, minimal external calls.

#### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - User address.
  - `token` - Token A or B.
  - `amount` - Denormalized amount.
  - `recipient` - Recipient address.
- **Behavior**: Transfers tokens/ETH, updates liquidity (`xLiquid` or `yLiquid`).
- **Internal Call Flow**:
  - Normalizes `amount` using `IERC20.decimals`.
  - Checks `xLiquid` (token A) or `yLiquid` (token B).
  - Transfers via `SafeERC20.safeTransfer` or ETH call with try-catch.
  - Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Pre-transfer liquidity check for `xLiquid` or `yLiquid`.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal state updates, try-catch for transfers.

#### addFees(address caller, bool isX, uint256 fee)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `fee` - Normalized fee amount.
- **Behavior**: Adds fees to `xFees`/`yFees` and increments `xFeesAcc`/`yFeesAcc` in `liquidityDetail`.
- **Internal Call Flow**:
  - Increments `xFeesAcc` (isX=true) or `yFeesAcc` (isX=false).
  - Creates `UpdateType` to update `xFees` or `yFees`.
  - Calls `update`, emits `FeesUpdated`.
- **Balance Checks**: None, assumes normalized input.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`.
- **Gas Usage Controls**: Minimal, single update, additional `xFeesAcc`/`yFeesAcc` write.

#### updateLiquidity(address caller, bool isX, uint256 amount)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `amount` - Normalized amount.
- **Behavior**: Reduces `xLiquid` or `yLiquid` in `liquidityDetail`.
- **Internal Call Flow**:
  - Checks `xLiquid` or `yLiquid` sufficiency.
  - Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Verifies `xLiquid` or `yLiquid` sufficiency.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routersเ**Behavior**: Resets `dFeesAcc` to the latest `xFeesAcc` (for ySlots) or `yFeesAcc` (for xSlots) after a successful fee claim in `_processFeeClaim` to prevent double-counting of fees in subsequent claims.
- **Internal Call Flow**: Updates slot's `dFeesAcc` within the `if (feeShare > 0)` block in `_processFeeClaim`, ensuring it reflects the current cumulative fees post-claim.
- **Balance Checks**: None specific to this change, as it relies on existing fee and liquidity checks.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `Slot`, `LiquidityDetails`.
- **Restrictions**: No additional restrictions beyond existing `claimFees` checks.
- **Gas Usage Controls**: Minimal additional gas cost for single state write to `dFeesAcc`.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts, fetched via `IERC20.decimals`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, struct-based stack management in `claimFees` (~7 variables).
- **Token Usage**:
  - xSlots: Provide token A liquidity, claim yFees.
  - ySlots: Provide token B liquidity, claim xFees.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `FeesClaimed`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ISSListing`, `IERC20`, `ITokenRegistry`).
  - No inline assembly, uses high-level Solidity.
  - Try-catch for external calls (`transact`, `globalizeUpdate`, `updateRegistry`, `ISSListing.volumeBalances`, `ISSListing.getPrice`) to handle failures.
  - Hidden state variables accessed via view functions (e.g., `getXSlotView`, `liquidityDetailsView`).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
- **Fee System**:
  - Cumulative fees_signed char tf8;fees (`xFeesAcc`, `yFeesAcc`) track total fees added, never decrease.
  - `dFeesAcc` stores `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots) at deposit or last claim, reset after claim to track fees since last claim.
  - Fee share based on `contributedFees = feesAcc - dFeesAcc`, proportional to liquidity contribution, capped at available fees.
- **Compatibility**: Aligned with `SSRouter` (v0.0.44), `SSAgent` (v0.0.2), `SSListingTemplate` (v0.0.10), `SSOrderPartial` (v0.0.18).
- **Caller Param**: Functionally unused in `addFees` and `updateLiquidity`, included for router validation.

# SSRouter Contract Documentation

## Overview
The `SSRouter` contract, implemented in Solidity (`^0.8.2`), facilitates order creation, settlement, liquidity management, and order cancellation for a decentralized trading platform. It inherits functionality from `SSSettlementPartial`, which extends `SSOrderPartial` and `SSMainPartial`, integrating with external interfaces (`ISSListingTemplate`, `ISSLiquidityTemplate`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles buy/sell order creation, settlement, liquidity deposits, withdrawals, fee claims, depositor changes, and order cancellations, with rigorous gas optimization and safety mechanisms. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation. Zero-amount payouts are explicitly handled to prevent indefinite pending states, ensuring system efficiency.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.62 (updated 2025-07-10)

**Inheritance Tree:** `SSRouter` → `SSSettlementPartial` → `SSOrderPartial` → `SSMainPartial`

## Mappings
- **orderPendingAmounts**: Tracks pending order amounts per listing and order ID (normalized to 1e18).
- **payoutPendingAmounts**: Tracks pending payout amounts per listing and payout order ID (normalized to 1e18).

## Structs
- **OrderPrep**: Contains `maker` (address), `recipient` (address), `amount` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256).
- **BuyOrderDetails**: Includes `orderId` (uint256), `maker` (address), `recipient` (address), `pending` (uint256, normalized), `filled` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `status` (uint8).
- **SellOrderDetails**: Same as `BuyOrderDetails` for sell orders.
- **OrderClearData**: Contains `orderId` (uint256), `isBuy` (bool), `amount` (uint256, normalized).
- **OrderContext**: Contains `listingContract` (ISSListingTemplate), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **BuyOrderUpdateContext**: Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized, tokenA for buy).
- **SellOrderUpdateContext**: Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).
- **PayoutContext**: Contains `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).

## Formulas
1. **Price Impact**:
   - **Formula**: `impactPrice = (newXBalance * 1e18) / newYBalance`
   - **Used in**: `_computeImpact`, `_checkPricing`, `_prepareLiquidityTransaction`.
   - **Description**: Represents the post-settlement price after processing a buy or sell order, calculated using updated pool balances (`newXBalance` for tokenA, `newYBalance` for tokenB). In `_computeImpact`:
     - Fetches current pool balances via `listingVolumeBalancesView` (includes input amount).
     - Computes `amountOut` using constant product formula:
       - For buy: `amountOut = (inputAmount * xBalance) / yBalance`.
       - For sell: `amountOut = (inputAmount * yBalance) / xBalance`.
     - Adjusts balances: `newXBalance -= amountOut` (buy), `newYBalance -= amountOut` (sell).
     - Normalizes to 1e18 for precision: `impactPrice = (newXBalance * 1e18) / newYBalance`.
   - **Usage**:
     - **Pricing Validation**: In `_checkPricing`, `impactPrice` is compared against order’s `maxPrice` and `minPrice` (fetched via `getBuy/SellOrderPricing`). Ensures trade does not exceed price constraints, preventing unfavorable executions (e.g., excessive slippage).
     - **Output Calculation**: In `_prepareLiquidityTransaction`, used to compute `amountOut` for buy (`amountOut = (inputAmount * impactPrice) / 1e18`) or sell (`amountOut = (inputAmount * 1e18) / impactPrice`), ensuring accurate token swaps.
     - **Settlement**: Critical in `settleBuy/SellOrders` and `settleBuy/SellLiquid` to validate order execution against liquidity pool or listing contract, maintaining market stability.

2. **Buy Order Output**:
   - **Formula**: `amountOut = (inputAmount * xBalance) / yBalance`
   - **Used in**: `executeBuyOrder`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenA) for a buy order given the input amount (tokenB), using constant product formula. Relies on `impactPrice` for validation.

3. **Sell Order Output**:
   - **Formula**: `amountOut = (inputAmount * yBalance) / xBalance`
   - **Used in**: `executeSellOrder`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenB) for a sell order given the input amount (tokenA), using constant product formula. Relies on `impactPrice` for validation.

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
- **Behavior**: Creates a buy order, transferring tokenB to the listing contract, and updating order state with `amountSent=0`.
- **Internal Call Flow**:
  - Calls `_handleOrderPrep` to validate inputs and create `OrderPrep` struct, normalizing `inputAmount` using `listingContract.decimalsB`.
  - `_checkTransferAmount` transfers `inputAmount` in tokenB from `msg.sender` to `listingAddress` via `IERC20.transferFrom` or ETH transfer, with pre/post balance checks.
  - `_executeSingleOrder` calls `listingContract.getNextOrderId`, creates `UpdateType[]` for pending order status, pricing, and amounts (with `amountSent=0`), invoking `listingContract.update`.
  - Transfer destination: `listingAddress`.
- **Balance Checks**:
  - **Pre-Balance Check**: Captures `listingAddress` balance before transfer.
  - **Post-Balance Check**: Ensures `postBalance > preBalance`, computes `amountReceived`.
- **Mappings/Structs Used**:
  - **Structs**: `OrderPrep`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `maker`, `recipient`, or `amount` is invalid, or transfer fails.
- **Gas Usage Controls**: Single transfer, minimal array updates (3 `UpdateType` elements).

### createSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createBuyOrder`, but for sell orders with tokenA input.
- **Behavior**: Creates a sell order, transferring tokenA to the listing contract, with `amountSent=0`.
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
- **Behavior**: Settles pending buy orders, transferring tokenA to recipients, tracking `amountSent` (tokenA).
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - Calls `_processBuyOrder` for each order:
    - Fetches `(pendingAmount, filled, amountSent)` via `getBuyOrderAmounts` with explicit destructuring.
    - Validates pricing via `_checkPricing`, using `_computeImpact` to calculate `impactPrice`, ensuring it is within `maxPrice` and `minPrice` (from `getBuyOrderPricing`).
    - Computes output via `_computeImpact` and `amountOut = (inputAmount * xBalance) / yBalance`.
    - Calls `_prepBuyOrderUpdate` for tokenA transfer via `listingContract.transact`, with denormalized amounts.
    - Updates `orderPendingAmounts` and creates `UpdateType[]` via `_createBuyOrderUpdates`, including `amountSent`.
  - Applies `finalUpdates[]` via `listingContract.update`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - `_prepBuyOrderUpdate` (inherited) ensures transfer success via try-catch.
- **Mappings/Structs Used**:
  - **Mappings**: `orderPendingAmounts`.
  - **Structs**: `UpdateType`, `BuyOrderUpdateContext`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders with zero pending amount or invalid pricing (based on `impactPrice`).
- **Gas Usage Controls**: `maxIterations` limits iteration, dynamic array resizing, `_processBuyOrder` reduces stack depth (~12 variables).

### settleSellOrders(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles pending sell orders, transferring tokenB to recipients, tracking `amountSent` (tokenB).
- **Internal Call Flow**:
  - Similar to `settleBuyOrders`, using `pendingSellOrdersView[]` and `_processSellOrder`.
  - Computes `amountOut = (inputAmount * yBalance) / xBalance`, validated by `impactPrice`.
  - Uses `_prepSellOrderUpdate` for tokenB transfers, includes `amountSent`.
- **Balance Checks**: Same as `settleBuyOrders`.
- **Mappings/Structs Used**: Same as `settleBuyOrders`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyOrders`.
- **Gas Usage Controls**: Same as `settleBuyOrders`, uses `_processSellOrder`.

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles buy orders with liquidity pool, transferring tokenA to recipients, updating liquidity (tokenB), and tracking `amountSent` (tokenA).
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - Calls `executeSingleBuyLiquid`:
    - Validates pricing via `_checkPricing`, using `_computeImpact` to ensure `impactPrice` is within `maxPrice` and `minPrice`.
    - `_prepBuyLiquidUpdates` uses `_prepareLiquidityTransaction` to compute `amountOut` based on `impactPrice` and tokens.
    - Transfers tokenA via `liquidityContract.transact`.
    - Updates liquidity via `_updateLiquidity` (tokenB, isX=false).
    - Creates `UpdateType[]` via `_createBuyOrderUpdates`, including `amountSent`.
  - Applies `finalUpdates[]` via `listingContract.update`.
  - Transfer destinations: `recipientAddress` (tokenA), `liquidityAddr` (tokenB).
- **Balance Checks**:
  - `_checkAndTransferPrincipal` checks listing and liquidity balances pre/post transfer.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `BuyOrderUpdateContext`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if pricing invalid (based on `impactPrice`) or transfer fails.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays, try-catch error handling.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles sell orders with liquidity pool, transferring tokenB, updating liquidity (tokenA), and tracking `amountSent` (tokenB).
- **Internal Call Flow**:
  - Similar to `settleBuyLiquid`, using `executeSingleSellLiquid` and `_prepSellLiquidUpdates`.
  - Computes `amountOut` using `impactPrice`, transfers tokenB, updates liquidity (tokenA, isX=true).
- **Balance Checks**: Same as `settleBuyLiquid`.
- **Mappings/Structs Used**: Same as `settleBuyLiquid`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyLiquid`.
- **Gas Usage Controls**: Same as `settleBuyLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long position payouts, transferring tokenB to holders. Zero-amount payouts (`required=0`) are skipped, returning an empty `PayoutUpdate[]`.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `executeLongPayout` (inherited):
    - Uses `_prepPayoutContext` (tokenB, decimalsB).
    - Checks `payout.required > 0`, returns empty array if zero.
    - Transfers `amountOut` via `listingContract.transact`.
    - Updates `payoutPendingAmounts` and creates `PayoutUpdate[]` via `_createPayoutUpdate`.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipientAddress` (tokenB).
- **Balance Checks**:
  - `_transferListingPayoutAmount` (inherited) checks pre/post balances.
- **Mappings/Structs Used**:
  - **Mappings**: `payoutPendingAmounts`.
  - **Structs**: `PayoutContext`, `PayoutUpdate`, `LongPayoutStruct`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `listingContract`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Settles short position payouts, transferring tokenA to holders. Zero-amount payouts (`amount=0`) are skipped, returning an empty `PayoutUpdate[]`.
- **Internal Call Flow**:
  - Similar to `settleLongPayouts`, using `shortPayoutByIndexView[]` and `executeShortPayout`.
  - Checks `payout.amount > 0`, returns empty array if zero.
  - Uses `_prepPayoutContext` with tokenA and `decimalsA`.
- **Balance Checks**: Same as `settleLongPayouts`.
- **Mappings/Structs Used**: Same as `settleLongPayouts`, with `ShortPayoutStruct`.
- **Restrictions**: Same as `settleLongPayouts`.
- **Gas Usage Controls**: Same as `settleLongPayouts`.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long position payouts from liquidity pool, transferring tokenB to holders. Zero-amount payouts (`required=0`) are marked as completed (status 3) via `listingContract.update` to prevent indefinite pending states.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `settleSingleLongLiquid` (inherited):
    - Uses `_prepPayoutContext` (tokenB, decimalsB).
    - Checks `payout.required > 0`:
      - If zero, creates `PayoutUpdate[]` with `required=0` and `UpdateType[]` to set status to 3 (completed), calls `listingContract.update`, and returns the `PayoutUpdate[]`.
      - If non-zero, checks liquidity via `_checkLiquidityBalance`.
      - Transfers `amountOut` via `liquidityContract.transact`.
      - Updates `payoutPendingAmounts` and creates `PayoutUpdate[]` via `_createPayoutUpdate`.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipientAddress` (tokenB).
- **Balance Checks**:
  - `_transferPayoutAmount` (inherited) checks liquidity pre/post balances.
- **Mappings/Structs Used**:
  - **Mappings**: `payoutPendingAmounts`.
  - **Structs**: `PayoutContext`, `PayoutUpdate`, `LongPayoutStruct`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Settles short position payouts from liquidity pool, transferring tokenA to holders. Zero-amount payouts (`amount=0`) are marked as completed (status 3) via `listingContract.update` to prevent indefinite pending states.
- **Internal Call Flow**:
  - Similar to `settleLongLiquid`, using `settleSingleShortLiquid` and `_prepPayoutContext` with tokenA and `decimalsA`.
  - Checks `payout.amount > 0`:
    - If zero, creates `PayoutUpdate[]` with `required=0` and `UpdateType[]` to set status to 3 (completed), calls `listingContract.update`, and returns the `PayoutUpdate[]`.
    - If non-zero, proceeds with liquidity transfer and updates.
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
- **Behavior**: Deposits tokens or ETH to the liquidity pool on behalf of `user`, allowing anyone to deposit for any valid `user`.
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
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` is zero or deposit fails.
- **Gas Usage Controls**: Single transfer and call, minimal state writes.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `liquidityIndex` (uint256): Liquidity slot index.
  - `isX` (bool): True for tokenA (claims yFees), false for tokenB (claims xFees).
  - `volumeAmount` (uint256): Unused parameter (maintained for interface compatibility).
  - `user` (address): User claiming fees, must be the slot depositor.
- **Behavior**: Claims fees from the liquidity pool for `user`, restricted to the slot’s depositor.
- **Internal Call Flow**:
  - Calls `liquidityContract.claimFees(user, listingAddress, liquidityIndex, isX, volumeAmount)`.
  - `liquidityContract` verifies `user` is the slot depositor.
  - No direct transfers or balance checks in `SSRouter`.
- **Balance Checks**: None, handled by `liquidityContract` via `_processFeeClaim` with pre/post balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` is zero, `user` is not the slot depositor, or claim fails.
- **Gas Usage Controls**: Minimal, single external call.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `inputAmount` (uint256): Withdrawal amount (denormalized).
  - `index` (uint256): Liquidity slot index.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `user` (address): User withdrawing liquidity, must be the slot depositor.
- **Behavior**: Withdraws liquidity from the pool for `user`, restricted to the slot’s depositor.
- **Internal Call Flow**:
  - Calls `xPrepOut` or `yPrepOut` with `user` to prepare withdrawal, verifying `user` is the slot depositor in `liquidityContract`.
  - Executes via `xExecuteOut` or `yExecuteOut` with `user`, transferring tokens to `user`.
  - No direct transfers in `SSRouter`, handled by `liquidityContract`.
- **Balance Checks**: None in `SSRouter`, handled by `liquidityContract` with pre/post balance checks in `xExecuteOut` or `yExecuteOut`.
- **Mappings/Structs Used**:
  - **Structs**: `PreparedWithdrawal`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` is zero, `user` is not the slot depositor, or preparation/execution fails.
- **Gas Usage Controls**: Minimal, two external calls.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `orderIdentifier` (uint256): Order ID.
  - `isBuyOrder` (bool): True for buy, false for sell.
- **Behavior**: Cancels a single order, refunding pending amounts to `recipientAddress`, restricted to the order’s maker via `_clearOrderData`, and accounting for `amountSent`.
- **Internal Call Flow**:
  - Calls `_clearOrderData`:
    - Retrieves order data via `getBuyOrderCore` or `getSellOrderCore`, and `getBuyOrderAmounts` or `getSellOrderAmounts` (including `amountSent`).
    - Verifies `msg.sender` is the order’s maker, reverts if not (`"Only maker can cancel"`).
    - Refunds pending amount via `listingContract.transact` (tokenB for buy, tokenA for sell), using denormalized amount based on `decimalsB` or `decimalsA`.
    - Sets status to 0 (cancelled) via `listingContract.update` with `UpdateType[]`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - `_clearOrderData` uses try-catch for refund transfer to ensure success or revert (`"Refund failed"`).
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `msg.sender` is not the maker, refund fails, or order is not pending (status != 1 or 2).
- **Gas Usage Controls**: Single transfer and update, minimal array (1 `UpdateType`).

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Cancels pending buy and sell orders for `msg.sender` up to `maxIterations`, using `makerPendingOrdersView` to fetch orders, refunding pending amounts, and accounting for `amountSent`.
- **Internal Call Flow**:
  - Fetches `orderIds` via `listingContract.makerPendingOrdersView(msg.sender)`.
  - Iterates up to `maxIterations`:
    - For each `orderId`, checks if `msg.sender` is the maker via `getBuyOrderCore` or `getSellOrderCore`.
    - Calls `_clearOrderData` for valid orders, refunding pending amounts (tokenB for buy, tokenA for sell) and setting status to 0.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - Same as `clearSingleOrder`, handled by `_clearOrderData` with try-catch.
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders where `msg.sender` is not the maker or if order is not pending.
  - Reverts if refund fails in `_clearOrderData`.
- **Gas Usage Controls**: `maxIterations` limits iteration, minimal updates per order (1 `UpdateType`).

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `slotIndex` (uint256): Liquidity slot index.
  - `newDepositor` (address): New depositor address.
  - `user` (address): Current slot owner, must be the slot depositor.
- **Behavior**: Changes the depositor for a liquidity slot on behalf of `user`, restricted to the slot’s depositor.
- **Internal Call Flow**:
  - Calls `liquidityContract.changeSlotDepositor(user, isX, slotIndex, newDepositor)`, which verifies `user` is the slot depositor.
  - No direct transfers or balance checks in `SSRouter`.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` or `newDepositor` is zero, `user` is not the slot depositor, or change fails.
- **Gas Usage Controls**: Minimal, single external call.

## Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` from `SSMainPartial.sol` (1e18) for token amounts, fetched via `IERC20.decimals` or `listingContract.decimalsA/B`. Ensures consistent precision across tokens.
- **Zero-Amount Payout Handling**: In `settleSingleLongLiquid` and `settleSingleShortLiquid`, zero-amount payouts (`required=0` for long, `amount=0` for short) are marked as completed (status 3) by creating an `UpdateType[]` to update the payout status via `listingContract.update`. This ensures zero-amount payouts are removed from `longPayoutByIndexView` or `shortPayoutByIndexView`, preventing indefinite pending states and array clogging in `SSListingTemplate.sol`. Non-zero payouts proceed with liquidity checks and transfers as usual.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Uses `maxIterations` to limit loops, dynamic arrays for updates, `_checkAndTransferPrincipal` for efficient transfers, and `_processBuy/SellOrder` to reduce stack depth in `settleBuy/SellOrders` (~12 variables).
- **Listing Validation**: Uses `onlyValidListing` modifier with `ISSAgent.getListing` checks to ensure listing integrity.
- **Router Restrictions**: Functions interacting with `liquidityContract` (e.g., `deposit`, `withdraw`, `claimFees`, `changeDepositor`, `settleBuy/SellLiquid`, `settleLong/ShortLiquid`) require `msg.sender` to be a registered router in `liquidityContract.routers(address(this))`, ensuring only authorized routers can call these functions. The `liquidityContract` further restricts actions like withdrawals and depositor changes to the slot’s depositor via the `caller` parameter.
- **Order Cancellation**:
  - `clearSingleOrder`: Callable by anyone, but restricted to the order’s maker via `_clearOrderData`’s maker check (`msg.sender == maker`).
  - `clearOrders`: Cancels only `msg.sender`’s orders, fetched via `makerPendingOrdersView`, ensuring no unauthorized cancellations.
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
  - Long payouts: Output tokenB, no `amountSent`.
  - Short payouts: Output tokenA, no `amountSent`.
- **Events**: No events explicitly defined; relies on `listingContract` and `liquidityContract` events for logging.
- **Safety**:
  - Explicit casting used for all interface and address conversions (e.g., `ISSListingTemplate(listingAddress)`).
  - No inline assembly, adhering to high-level Solidity for safety.
  - Try-catch blocks handle external call failures (e.g., transfers, liquidity updates).
  - Hidden state variables accessed via unique view functions (e.g., `agentView`, `liquidityAddressView`, `makerPendingOrdersView`).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
  - Ensures graceful degradation with zero-length array returns on failure (e.g., `_prepBuyLiquidUpdates`).
  - Maker-only cancellation enforced in `_clearOrderData` to prevent unauthorized order cancellations.

# SSCrossDriver Contract Documentation

## Overview
The `SSCrossDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short cross margin strategies, inheriting functionality through `CSDExecutionPartial` to `CSDPositionPartial` to `CSDUtilityPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`) and uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles position creation (including market orders with zeroed price bounds), closure, cancellation, margin adjustments, stop-loss/take-profit updates, and mux-driven operations, with rigorous gas optimization and safety mechanisms. State variables are hidden, accessed via view functions, and decimal precision is maintained across tokens with varying decimals.

**Inheritance Tree:** `SSCrossDriver` → `CSDExecutionPartial` → `CSDPositionPartial` → `CSDUtilityPartial`

**SPDX License:** BSD-3-Clause

**Version:** 0.0.42 (last updated 2025-07-13)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals (defined in `CSDUtilityPartial`).
- **agentAddress** (address, public): Stores the address of the ISSAgent contract for listing validation.
- **positionCount** (uint256, public): Tracks the total number of positions created, used to generate unique position IDs.

## Mappings
- **makerTokenMargin** (mapping(address => mapping(address => uint256))): Tracks margin balances per maker and token, normalized to 1e18.
- **makerMarginTokens** (mapping(address => address[])): Lists tokens with non-zero margin balances for each maker.
- **positionCore1** (mapping(uint256 => PositionCore1)): Stores core position data (positionId, listingAddress, makerAddress, positionType).
- **positionCore2** (mapping(uint256 => PositionCore2)): Tracks position status (status1 for active, status2 for closed).
- **priceParams1** (mapping(uint256 => PriceParams1)): Holds price-related data (minEntryPrice, maxEntryPrice, minPrice, priceAtEntry, leverage).
- **priceParams2** (mapping(uint256 => PriceParams2)): Stores liquidation price for each position.
- **marginParams1** (mapping(uint256 => MarginParams1)): Manages margin details (initialMargin, taxedMargin, excessMargin, fee).
- **marginParams2** (mapping(uint256 => MarginParams2)): Tracks initial loan amount for each position.
- **exitParams** (mapping(uint256 => ExitParams)): Stores exit conditions (stopLossPrice, takeProfitPrice, exitPrice).
- **openInterest** (mapping(uint256 => OpenInterest)): Records leverage amount and timestamp for each position.
- **positionsByType** (mapping(uint8 => uint256[])): Lists position IDs by type (0 for long, 1 for short).
- **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by listing address and position type.
- **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short).
- **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
- **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.
- **historicalInterestTimestamps** (mapping(uint256 => uint256)): Stores timestamps for open interest updates.
- **muxes** (mapping(address => bool)): Tracks authorized mux contracts for delegated position closure (defined in `CSDUtilityPartial`).

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

### addMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to authorize.
- **Behavior**: Adds a mux contract to the authorized list, enabling it to call `drift`. Emits `MuxAdded`.
- **Internal Call Flow**: Validates `mux` is non-zero and not already authorized. Sets `muxes[mux] = true`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is zero (`"Invalid mux address"`) or already authorized (`"Mux already exists"`).
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### removeMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to remove.
- **Behavior**: Removes a mux contract from the authorized list, disabling its access to `drift`. Emits `MuxRemoved`.
- **Internal Call Flow**: Validates `mux` is authorized, sets `muxes[mux] = false`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is not authorized (`"Mux does not exist"`).
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### getMuxesView()
- **Parameters**: None.
- **Behavior**: Returns an array of authorized mux addresses.
- **Internal Call Flow**: Iterates over a fixed range (0 to 999) to count and collect addresses where `muxes[address] == true`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, fixed iteration limit (1000) for gas safety.

### drive(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
- **Parameters**:
  - `maker` (address): Position owner.
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (denormalized).
  - `maxEntryPrice` (uint256): Maximum entry price (denormalized).
  - `initialMargin` (uint256): Initial margin (denormalized).
  - `excessMargin` (uint256): Additional margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (denormalized).
  - `takeProfitPrice` (uint256): Take-profit price (denormalized).
  - `positionType` (uint8): 0 for long, 1 for short.
- **Behavior**: Allows any address to create a position on behalf of `maker`, transferring margins, computing fees, loans, and liquidation prices, and storing data. Executes instantly as a market order if `minEntryPrice` and `maxEntryPrice` are zero. Emits `PositionEntered`.
- **Internal Call Flow**:
  - Validates `maker` and `positionType` (0 or 1).
  - Calls `_initiateEntry` with provided parameters:
    - `_prepareEntryContext` creates `EntryContext`, overriding `maker` with provided address.
    - `_validateEntry` calls `_validateAndInit`, incrementing `positionCount`, validating listing via `ISSAgent.getListing`, and selecting `tokenA` (long) or `tokenB` (short).
    - `_computeEntryParams` uses `prepEnterLong` or `prepEnterShort`:
      - `_parseEntryPriceInternal` fetches `currentPrice` via `ISSListing.prices`. If `minEntryPrice` and `maxEntryPrice` are zero, sets `priceAtEntry = currentPrice` for instant execution as a market order.
      - Computes fee, taxed margin, leverage amount, and loan.
      - `_checkLiquidityLimitLong` or `_checkLiquidityLimitShort` verifies liquidity via `ISSLiquidityTemplate.liquidityDetailsView`.
      - `_transferMarginToListing` transfers fee to `liquidityAddress` and margins to `listingAddress` with pre/post balance checks.
      - Calls `ISSLiquidityTemplate.addFees`.
    - `_storeEntryData` updates `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `pendingPositions`, `positionToken`, and `longIOByHeight` or `shortIOByHeight`.
  - Transfer destinations: `liquidityAddress` (fee), `listingAddress` (margins).
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddr)` before fee transfer.
  - **Post-Balance Check (Fee)**: `balanceAfter - balanceBefore == denormalizedFee`.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(listingAddress)` before margin transfer.
  - **Post-Balance Check (Margin)**: `balanceAfter - balanceBefore == denormalizedAmount`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `marginParams1`, `marginParams2`, `exitParams`, `openInterest`, `pendingPositions`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `EntryContext`, `PrepPosition`, `PositionCore1`, `PositionCore2`, `PriceParams1`, `PriceParams2`, `MarginParams1`, `MarginParams2`, `ExitParams`, `OpenInterest`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maker` is zero, `positionType > 1`, or transfers fail.
- **Gas Usage Controls**: Single-element updates, no loops in critical paths, pop-and-swap for arrays.

### drift(uint256 positionId, address maker)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
  - `maker` (address): Position owner.
- **Behavior**: Allows authorized mux contracts to close a specific position for the given `maker`, computing payouts in tokenB (long) or tokenA (short), transferring to the mux (`msg.sender`) for delegated closures, updating state, and removing the position from arrays. Emits `PositionClosed`.
- **Internal Call Flow**:
  - Validates position exists (`positionCore1.positionId == positionId`), is not closed (`positionCore2.status2 == 0`), and belongs to `maker` (`positionCore1.makerAddress == maker`).
  - Determines token: `ISSListing.tokenB()` for long, `ISSListing.tokenA()` for short.
  - Calls `prepCloseLong` (long) or `prepCloseShort` (short):
    - `_computePayoutLong` or `_computePayoutShort` calculates payout using respective formulas.
    - `_deductMarginAndRemoveToken` deducts `taxedMargin + excessMargin` from `makerTokenMargin` with pre-balance check.
    - `_executePayoutUpdate` sets `exitParams.exitPrice` and `positionCore2.status2 = 1`.
  - Calls `removePositionIndex` to update `positionsByType` and `pendingPositions` using pop-and-swap.
  - Calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `msg.sender`, `denormalizedPayout`, returns: none) to transfer payout to the mux (`msg.sender`) for delegated closures.
  - Payout destination: `msg.sender` (mux) for delegated closures.
- **Balance Checks**:
  - **Pre-Balance Check (Margin)**: `makerTokenMargin[maker][positionToken] >= taxedMargin + excessMargin` during `prepCloseLong` or `prepCloseShort`.
  - **Pre-Balance Check (Payout)**: `IERC20.balanceOf(listingAddress)` captures balance before payout transfer via `ISSListing.ssUpdate`.
  - **Post-Balance Check (Payout)**: `balanceAfter - balanceBefore == denormalizedPayout` confirms payout transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCore1`, `positionCore2`, `marginParams1`, `exitParams`, `makerTokenMargin`, `makerMarginTokens`, `positionToken`, `positionsByType`, `pendingPositions`.
  - **Structs**: `PositionCore1`, `PositionCore2`, `MarginParams1`, `ExitParams`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyMux`.
  - Reverts if position is invalid (`"Invalid position"`), closed (`"Position closed"`), or maker mismatches (`"Maker mismatch"`).
- **Gas Usage Controls**: Single position processing, pop-and-swap for arrays, minimal gas usage.

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
- **Behavior**: Creates a pending long position, transferring margins in tokenA to the listing contract, computing fees, loans, and liquidation prices, and storing position data. Executes instantly as a market order if `minEntryPrice` and `maxEntryPrice` are zero. Emits `PositionEntered`.
- **Internal Call Flow**: 
  - Invokes `_initiateEntry` with `positionType = 0`.
  - `_prepareEntryContext` creates `EntryContext` with inputs and `positionId` from `positionCount + 1`.
  - `_validateEntry` calls `_validateAndInit`, incrementing `positionCount`, invoking `ISSAgent.getListing` (input: `tokenA`, `tokenB` from `ISSListing`, returns: `listingAddress`) to validate listing, and selecting `tokenA` for margins. Ensures `initialMargin > 0` and `leverage` is 2–100.
  - `_computeEntryParams` calls `prepEnterLong`:
    - `_parseEntryPriceInternal` fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `currentPrice`). If `minEntryPrice` and `maxEntryPrice` are zero, sets `priceAtEntry = currentPrice` for instant execution; otherwise, validates against `minEntryPrice` and `maxEntryPrice`.
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
- **Behavior**: Creates a pending short position, transferring margins in tokenB to the listing contract, computing fees, loans, and liquidation prices. Executes instantly as a market order if `minEntryPrice` and `maxEntryPrice` are zero. Emits `PositionEntered`.
- **Internal Call Flow**: 
  - Mirrors `enterLong`, calling `_initiateEntry` with `positionType = 1`.
  - `prepEnterShort`:
    - Uses `_parseEntryPriceInternal` for price validation. If `minEntryPrice` and `maxEntryPrice` are zero, sets `priceAtEntry = currentPrice` for instant execution.
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
- **Restrictions**: Same as `enterLong`, with tokenB liquidity checks.
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
  - `_updateListingMargin` calls `ISSListing.update` (input: `UpdateType[]` with type 0, `denormalizedAmount`, returns: none).
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
  - **Mappings**: `makerTokenMargin`, `makerMarginTokens`, `positionCore1`, `positionCore2`, `priceParams1`, `priceParams2`, `shortIOByHeight`, `historicalInterestTimestamps`.
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
    - Uses `_parseEntryPriceInternal` (via `ISSListing.prices`) to check liquidation (`currentPrice <= priceParams2.liquidationPrice` for long, `>=` for short) or entry conditions. If `minEntryPrice` and `maxEntryPrice` are zero, activates instantly if not liquidated.
    - If liquidating, calls `prepCloseLong` or `prepCloseShort` with pre-balance checks, updates `ISSListing.ssUpdate`, and removes position via `removePositionIndex`.
    - If within entry range or zeroed bounds, sets `positionCore2.status1 = true` and moves to `positionsByType`.
  - For active positions in `positionsByType`, `_processActivePosition`:
    - Updates liquidation price via `_updateLiquidationPrices`.
    - Checks triggers (stop-loss, take-profit, liquidation) using `normalizePrice` and `ISSListing.prices`, closing positions with payouts.
  - Payouts go to `positionCore1.makerAddress` in tokenB (long) or tokenA (short).
- **Balance Checks**:
  - **Pre-Balance Check**: `makerTokenMargin[makerAddress][positionToken] >= taxedMargin + excessMargin` during `prepCloseLong` or `prepCloseShort`.
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
- **Gas Usage Controls**: `maxIterations`, view function, minimal gas.

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
- **Market Orders**: If `minEntryPrice` and `maxEntryPrice` are zero in `enterLong`, `enterShort`, `drive`, or `executePositions`, positions execute instantly at the current price as market orders, bypassing price bound validation in `_parseEntryPriceInternal`.
- **Events**: Emitted for entry (`PositionEntered`), closure (`PositionClosed`), cancellation (`PositionCancelled`), SL/TP updates (`StopLossUpdated`, `TakeProfitUpdated`), batch operations (`AllLongsClosed`, `AllLongsCancelled`, `AllShortsClosed`, `AllShortsCancelled`), and mux management (`MuxAdded`, `MuxRemoved`).
- **Safety**: Balance checks, explicit casting, no inline assembly, and liquidation price updates ensure robustness.
- **Liquidation Price Updates**: `addExcessMargin` and `pullMargin` update liquidation prices for all relevant positions to reflect margin changes, ensuring accurate risk assessment.
- **Mux Functionality**: Authorized mux contracts can close (`drift`) positions, restricted by `onlyMux` modifier, with `muxes` mapping tracking authorization. The `drift` function directs payouts to the mux (`msg.sender`) for delegated closures, ensuring proper fund routing. The `drive` function is open to any address, enabling flexible position creation while maintaining validation.

# SSIsolatedDriver Contract Documentation

## Overview
The `SSIsolatedDriver` contract, implemented in Solidity (^0.8.2), manages trading positions for long and short isolated margin strategies, inheriting functionality through `SSDExecutionPartial` to `SSDPositionPartial` to `SSDUtilityPartial`. It integrates with external interfaces (`ISSListing`, `ISSLiquidityTemplate`, `ISSAgent`) and uses `IERC20` for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract supports position creation, closure, cancellation, margin adjustments, stop-loss/take-profit updates, and mux operations for external contract interactions. It handles market-based execution by using the current price when minimum and maximum entry prices are zeroed. State variables are hidden, accessed via view functions, and decimal precision is maintained across tokens.

**Inheritance Tree:** `SSIsolatedDriver` → `SSDExecutionPartial` → `SSDPositionPartial` → `SSDUtilityPartial`

**SPDX License:** BSD-3-Clause

**Version:** 0.0.18 (last updated 2025-07-13)

## State Variables
- **DECIMAL_PRECISION** (uint256, constant, public): Set to 1e18 for normalizing amounts and prices across token decimals.
- **agent** (address, public): Stores the address of the ISSAgent contract for listing validation.
- **historicalInterestHeight** (uint256, public): Tracks the current block height for open interest updates, initialized to 1.
- **nonce** (uint256, public): Nonce for unique transaction tracking, initialized to 0.
- **positionIdCounter** (uint256, public): Counter for generating unique position IDs, initialized to 1.
- **muxes** (mapping(address => bool), public): Tracks authorized mux contracts for external position management.

## Mappings
- **positionCoreBase** (mapping(uint256 => PositionCoreBase)): Stores core position data (maker address, listing address, position ID, position type).
- **positionCoreStatus** (mapping(uint256 => PositionCoreStatus)): Tracks position status (pending/executable, open/closed/cancelled).
- **priceParams** (mapping(uint256 => PriceParams)): Holds price data (minimum/maximum entry prices, entry price, close price).
- **marginParams** (mapping(uint256 => MarginParams)): Manages margin details (initial margin, taxed margin, excess margin).
- **leverageParams** (mapping(uint256 => LeverageParams)): Stores leverage details (leverage value, leverage amount, initial loan).
- **riskParams** (mapping(uint256 => RiskParams)): Contains risk parameters (liquidation price, stop-loss price, take-profit price).
- **pendingPositions** (mapping(address => mapping(uint8 => uint256[]))): Tracks pending position IDs by maker address and position type (0 for long, 1 for short).
- **positionsByType** (mapping(uint8 => uint256[])): Stores position IDs by type (0 for long, 1 for short).
- **positionToken** (mapping(uint256 => address)): Maps position ID to margin token (tokenA for long, tokenB for short).
- **longIOByHeight** (mapping(uint256 => uint256)): Tracks long open interest by block height.
- **shortIOByHeight** (mapping(uint256 => uint256)): Tracks short open interest by block height.
- **historicalInterestTimestamps** (mapping(uint256 => uint256)): Stores timestamps for open interest updates.
- **pendingEntries** (mapping(uint256 => PendingEntry)): Temporary storage for position entry parameters.

## Structs
- **PositionCoreBase**: Contains `makerAddress` (address), `listingAddress` (address), `positionId` (uint256), `positionType` (uint8: 0 for long, 1 for short).
- **PositionCoreStatus**: Tracks `status1` (bool: false for pending, true for executable), `status2` (uint8: 0 for open, 1 for closed, 2 for cancelled).
- **PriceParams**: Stores `priceMin` (uint256), `priceMax` (uint256), `priceAtEntry` (uint256), `priceClose` (uint256), all normalized to 1e18.
- **MarginParams**: Holds `marginInitial` (uint256), `marginTaxed` (uint256), `marginExcess` (uint256), all normalized to 1e18.
- **LeverageParams**: Contains `leverageVal` (uint8), `leverageAmount` (uint256), `loanInitial` (uint256), with amounts normalized to 1e18.
- **RiskParams**: Stores `priceLiquidation` (uint256), `priceStopLoss` (uint256), `priceTakeProfit` (uint256), all normalized to 1e18.
- **PosParamsCore**: Combines `priceParams` (PriceParams), `marginParams` (MarginParams).
- **PosParamsExt**: Combines `leverageParams` (LeverageParams), `riskParams` (RiskParams).
- **EntryParamsBase**: Stores `listingAddr` (address), `entryPriceStr` (string), `initMargin` (uint256, denormalized), `extraMargin` (uint256, denormalized).
- **EntryParamsRisk**: Stores `leverageVal` (uint8), `stopLoss` (uint256, normalized), `takeProfit` (uint256, normalized).
- **EntryParamsToken**: Stores `tokenAddr` (address), `normInitMargin` (uint256, normalized), `normExtraMargin` (uint256, normalized), `driverAddr` (address).
- **ClosePositionBase**: Stores `positionId` (uint256), `listingAddress` (address), `makerAddress` (address), `driver` (address).
- **ClosePositionMargin**: Stores `taxedMargin` (uint256, normalized), `excessMargin` (uint256, normalized).
- **LongCloseParams**: Stores `leverageAmount` (uint256, normalized), `loanInitial` (uint256, normalized) for long positions.
- **ShortCloseParams**: Stores `minPrice` (uint256, normalized), `initialMargin` (uint256, normalized), `leverage` (uint8) for short positions.
- **PositionAction**: Stores `positionId` (uint256), `actionType` (uint8: 0 for update status, 1 for close).
- **ExecutionContextBase**: Stores `listingAddress` (address), `driver` (address), `currentPrice` (uint256, normalized).
- **ExecutionContextCounts**: Stores `actionCount` (uint256), `maxActions` (uint256).
- **EntryContext**: Stores `listingAddr` (address), `tokenAddr` (address), `normInitMargin` (uint256), `normExtraMargin` (uint256).
- **PendingEntry**: Stores `listingAddr` (address), `tokenAddr` (address), `positionId` (uint256), `positionType` (uint8), `initialMargin` (uint256), `extraMargin` (uint256), `entryPriceStr` (string), `makerAddress` (address), `leverageVal` (uint8), `stopLoss` (uint256), `takeProfit` (uint256), `normInitMargin` (uint256), `normExtraMargin` (uint256).
- **PayoutUpdate**: Stores `recipient` (address), `required` (uint256, denormalized), `payoutType` (uint8: 0 for long, 1 for short).
- **UpdateType**: Stores `updateType` (uint8), `index` (uint256), `value` (uint256), `addr` (address), `recipient` (address).

## Formulas
Formulas drive position calculations, detailed in their functional context.

1. **Fee Calculation**:
   - **Formula**: `fee = (leverageVal - 1) * normMarginInitial / 100`
   - **Used in**: `updateLiquidityFees` (called by `finalizeEntryFees` in `enterLong`, `enterShort`, `drive`).
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

### addMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to authorize.
- **Behavior**: Adds a mux contract to the authorized list, enabling it to call `drift`. Emits `MuxAdded`.
- **Internal Call Flow**: Validates `mux != address(0)` and `!muxes[mux]`. Sets `muxes[mux] = true`. Emits `MuxAdded` (defined in `SSDUtilityPartial`). No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is zero (`"Invalid mux address"`) or already authorized (`"Mux already authorized"`).
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### removeMux(address mux)
- **Parameters**:
  - `mux` (address): Address of the mux contract to deauthorize.
- **Behavior**: Removes a mux contract from the authorized list. Emits `MuxRemoved`.
- **Internal Call Flow**: Validates `mux != address(0)` and `muxes[mux]`. Sets `muxes[mux] = false`. Emits `MuxRemoved` (defined in `SSDUtilityPartial`). No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `mux` is zero (`"Invalid mux address"`) or not authorized (`"Mux not authorized"`).
- **Gas Usage Controls**: Minimal gas due to single mapping update.

### getMuxesView()
- **Parameters**: None.
- **Behavior**: Returns an array of authorized mux addresses.
- **Internal Call Flow**: Iterates over a fixed range (0 to 999) to count and collect addresses where `muxes[address] == true`. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **Mappings**: `muxes`.
- **Restrictions**: None.
- **Gas Usage Controls**: View function, fixed iteration limit (1000) for gas safety.

### drive(address maker, address listingAddress, uint256 minEntryPrice, uint256 maxEntryPrice, uint256 initialMargin, uint256 excessMargin, uint8 leverage, uint256 stopLossPrice, uint256 takeProfitPrice, uint8 positionType)
- **Parameters**:
  - `maker` (address): Position owner.
  - `listingAddress` (address): Listing contract address.
  - `minEntryPrice` (uint256): Minimum entry price (normalized).
  - `maxEntryPrice` (uint256): Maximum entry price (normalized).
  - `initialMargin` (uint256): Initial margin (denormalized).
  - `excessMargin` (uint256): Excess margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLossPrice` (uint256): Stop-loss price (normalized).
  - `takeProfitPrice` (uint256): Take-profit price (normalized).
  - `positionType` (uint8): 0 for long, 1 for short.
- **Behavior**: Creates a position on behalf of `maker` by any caller, transferring margins to `listingAddress`, computing fees, loans, and liquidation prices, and storing position data. Supports market-based execution if `minEntryPrice` and `maxEntryPrice` are zero, using the current price from `ISSListing.prices`. Emits `PositionEntered` with `msg.sender` as the caller address.
- **Internal Call Flow**: Validates `maker`, `listingAddress`, `positionType <= 1`, `initialMargin > 0`, `leverage` (2–100). Calls `prepareEntryContext` to fetch `tokenA`/`tokenB` via `ISSListing.tokenA`/`tokenB` (input: `listingAddress`, returns: `address`) and normalize margins with `normalizeAmount` (`IERC20.decimals`, input: none, returns: `uint8`). Converts prices to `entryPriceStr` via `uint2str`. Calls `initiateEntry` with `positionType`. `prepareEntryBase` increments `positionIdCounter`, stores `PendingEntry` with `maker` overridden. `prepareEntryRisk`, `prepareEntryToken`, `validateEntryBase` (uses `ISSAgent.getListing`), `validateEntryRisk`, `updateEntryCore`, `updateEntryParams` (calls `parseEntryPriceHelper`, which uses `ISSListing.prices` for market orders if `entryPriceStr` is "0" or "0-0", `computeParams`, `validateLeverageLimit` with `ISSLiquidityTemplate.liquidityDetailsView`, `prepareCoreParams`, `prepareExtParams`, `updateLiquidityFees`), and `updateEntryIndexes` process the position. `finalizeEntry` transfers fee to `liquidityAddress` via `IERC20.transferFrom` (input: `maker`, `liquidityAddress`, `denormFee`, returns: `bool`) with pre/post balance checks (`IERC20.balanceOf(liquidityAddress)`), calls `ISSLiquidityTemplate.addFees` (input: `this`, `isX`, `actualFee`), transfers margins to `listingAddress` via `IERC20.transferFrom` (input: `maker`, `listingAddress`, `expectedAmount`, returns: `bool`) with pre/post balance checks (`IERC20.balanceOf(listingAddress)`), and calls `ISSListing.update`. Updates `positionToken`, `pendingPositions`, `longIOByHeight`/`shortIOByHeight` via `updateHistoricalInterest`. Emits `PositionEntered` with `msg.sender`. Returns `positionId`.
- **Balance Checks**:
  - **Pre-Balance Check (Fee)**: `IERC20.balanceOf(liquidityAddress)` before fee transfer.
  - **Post-Balance Check (Fee)**: `checkTransferAmount` confirms fee transfer.
  - **Pre-Balance Check (Margin)**: `IERC20.balanceOf(listingAddress)` before margin transfer.
  - **Post-Balance Check (Margin)**: `checkTransferAmount` confirms margin transfer.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `pendingPositions`, `positionToken`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`, `pendingEntries`.
  - **Structs**: `EntryContext`, `PendingEntry`, `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PosParamsCore`, `PosParamsExt`, `EntryParamsBase`, `EntryParamsRisk`, `EntryParamsToken`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `maker` is zero (`"Invalid maker address"`), `listingAddress` is zero (`"Invalid listing address"`), `positionType > 1` (`"Invalid position type"`), `initialMargin == 0` (`"Invalid initial margin"`), `leverage` is out of range (`"Invalid leverage"`), or transfers fail.
- **Gas Usage Controls**: Single-element array updates, balance checks, and pop-and-swap minimize gas.

### drift(uint256 positionId, address maker)
- **Parameters**:
  - `positionId` (uint256): Position ID to execute.
  - `maker` (address): Address of the position owner.
- **Behavior**: Closes an open position on behalf of an authorized mux for the specified `maker` based on price triggers (liquidation, stop-loss, take-profit), sending payouts to the mux (`msg.sender`) for further distribution to the user. Emits `PositionClosed`.
- **Internal Call Flow**: Restricted by `onlyMux`. Validates `positionId` in `positionCoreBase`, ensures `makerAddress == maker` (`"Maker address mismatch"`), `status2 == 0` (`"Position not open"`), and `status1 == true` (`"Position not executable"`). Calls `computeActiveAction` with `getCurrentPrice` (`ISSListing.prices`, input: `listingAddress`, returns: `uint256`) to check triggers. Requires `actionType == 1` (`"Position not ready to close"`). Calls `executeClosePosition` with `ExecutionContextBase` (`currentPrice`, `listingAddress`, `driver = this`), invoking `internalCloseLongPosition` or `internalCloseShortPosition`. Payout goes to `msg.sender` (mux) via `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `recipient = msg.sender`, returns: none) in tokenB (long) or tokenA (short). Updates `positionCoreStatus`, `positionsByType`, `pendingPositions`, `longIOByHeight` or `shortIOByHeight`, and emits `PositionClosed` with `maker`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` and `status1 == true` ensure position is open and executable.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `positionToken`, `positionsByType`, `pendingPositions`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `ClosePositionBase`, `ClosePositionMargin`, `LongCloseParams`, `ShortCloseParams`, `PositionAction`, `ExecutionContextBase`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyMux`.
  - Reverts if `positionId` is invalid (`"Invalid position ID"`), `maker` does not match (`"Maker address mismatch"`), position is not open (`"Position not open"`), not executable (`"Position not executable"`), or not ready to close (`"Position not ready to close"`).
- **Gas Usage Controls**: Single position processing with pop-and-swap minimizes gas.

### enterLong(address listingAddr, string entryPriceStr, uint256 initMargin, uint256 extraMargin, uint8 leverage, uint256 stopLoss, uint256 takeProfit)
- **Parameters**:
  - `listingAddr` (address): Listing contract address.
  - `entryPriceStr` (string): Entry price range (e.g., "100-200", "0", or "0-0" for market orders).
  - `initMargin` (uint256): Initial margin (denormalized).
  - `extraMargin` (uint256): Excess margin (denormalized).
  - `leverage` (uint8): Leverage multiplier (2–100).
  - `stopLoss` (uint256): Stop-loss price (normalized).
  - `takeProfit` (uint256): Take-profit price (normalized).
- **Behavior**: Creates a pending long position, transferring margins in tokenA to the listing contract, computing fees, loans, and liquidation prices, and storing position data. Supports market-based execution if `entryPriceStr` is "0" or "0-0", using the current price from `ISSListing.prices`. Emits `PositionEntered` with `mux = address(0)`.
- **Internal Call Flow**: Calls `initiateEntry` with `positionType = 0`. `prepareEntryContext` fetches `tokenA` via `ISSListing.tokenA` (input: `listingAddr`, returns: `address`) and normalizes margins with `normalizeAmount` (`IERC20.decimals`, input: none, returns: `uint8`). Creates `EntryContext`. `prepareEntryBase` increments `positionIdCounter` and stores `PendingEntry`. `prepareEntryRisk` and `prepareEntryToken` set parameters. `validateEntryBase` calls `validateListing` with `ISSAgent.getListing` (input: `tokenA`, `tokenB`, returns: `listingAddr`) and checks `initMargin > 0`. `validateEntryRisk` ensures `leverage` is 2–100. `updateEntryCore` sets `PositionCoreBase` and `PositionCoreStatus`. `updateEntryParams` calls `updateEntryParamsCompute` (`parseEntryPriceHelper` uses `ISSListing.prices` for market orders if `entryPriceStr` is "0" or "0-0", `computeParams`), `updateEntryParamsValidate` (`validateLeverageLimit` uses `ISSLiquidityTemplate.liquidityDetailsView`, input: `this`, returns: `yLiquid`), and `updateEntryParamsStore` (`prepareCoreParams`, `prepareExtParams`, `updateLiquidityFees`). `updateLiquidityFees` transfers fee in tokenA to `liquidityAddress` via `IERC20.transferFrom` (input: `msg.sender`, `liquidityAddress`, `denormFee`, returns: `bool`), with pre-balance check (`IERC20.balanceOf(liquidityAddress)`) and post-balance check (`checkTransferAmount`). Calls `ISSLiquidityTemplate.addFees` (input: `this`, `true`, `actualFee`, returns: none). `finalizeEntry` transfers `remainingMargin + extraMargin` in tokenA to `listingAddr` via `IERC20.transferFrom` (input: `msg.sender`, `listingAddr`, `expectedAmount`, returns: `bool`), with pre/post balance checks (`IERC20.balanceOf(listingAddr)`). Calls `ISSListing.update` (input: `UpdateType[]` with `io`, returns: none). Updates `positionToken`, `pendingPositions`, `longIOByHeight` via `updateHistoricalInterest`. Emits `PositionEntered` with `mux = address(0)`.
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
  - Reverts if listing is invalid (`"Invalid listing"`), margin is zero (`"Invalid margin"`), leverage is out of range (`"Invalid leverage"`), liquidity limit is exceeded, or transfers fail.
- **Gas Usage Controls**: Single-element array updates, balance checks, and pop-and-swap minimize gas.

### enterShort(address listingAddr, string entryPriceStr, uint256 initMargin, uint256 extraMargin, uint8 leverage, uint256 stopLoss, uint256 takeProfit)
- **Parameters**: Same as `enterLong`, for short positions.
- **Behavior**: Creates a pending short position, transferring margins in tokenB to the listing, computing fees, loans, and liquidation prices. Supports market-based execution if `entryPriceStr` is "0" or "0-0", using the current price from `ISSListing.prices`. Emits `PositionEntered` with `mux = address(0)`.
- **Internal Call Flow**: Mirrors `enterLong`, with `positionType = 1`. `prepareEntryContext` uses `ISSListing.tokenB`. `validateLeverageLimit` checks `xLiquid` via `ISSLiquidityTemplate.liquidityDetailsView`. Transfers use tokenB for fee (`ISSLiquidityTemplate.addFees` with `isX = false`) and margins. Updates `shortIOByHeight`. Emits `PositionEntered` with `mux = address(0)`.
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
  - Reverts if position is closed (`"Position not open"`), amount is zero, exceeds leverage (`"Excess margin exceeds leverage"`), or transfer fails.
- **Gas Usage Controls**: Single transfer and array update minimize gas.

### closeLongPosition(uint256 positionId)
- **Parameters**:
  - `positionId` (uint256): Position ID to close.
- **Behavior**: Closes a long position, computing payout in tokenB, transferring to `msg.sender`, and removing the position. Emits `PositionClosed`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status2 == 0`, `status1 == true`, and owned by `msg.sender` (`"Not position owner"`). Calls `internalCloseLongPosition`: `prepareCloseBase` sets `ClosePositionBase`; `prepareClosePrice` fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `uint256`) and `decimalsB`; `prepareClosePayout` uses `computeLongPayout`; `finalizeClose` updates `positionCoreStatus.status2 = 1`, calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `payout`, returns: none) for tokenB payout, adjusts `longIOByHeight`, increments `historicalInterestHeight`, and calls `removePositionIndex`. Pre-balance check in `validatePositionStatus`; no post-balance check as payout is handled by `ISSListing`. Payout destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status2 == 0` and `status1 == true` ensure position is open and executable.
  - **Post-Balance Check**: None, as payout is handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `positionToken`, `positionsByType`, `pendingPositions`, `longIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `ClosePositionBase`, `ClosePositionMargin`, `LongCloseParams`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position ID"`), closed (`"Position not open"`), not executable, or not owned (`"Not position owner"`).
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
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status1 == false`, `status2 == 0`, and owned by `msg.sender` (`"Not position owner"`). Calls `internalCancelPosition`: sets `positionCoreStatus.status2 = 2`, calls `ISSListing.ssUpdate` (input: `PayoutUpdate[]` with `totalMargin`, returns: none) for `positionToken` margin return, adjusts `longIOByHeight` or `shortIOByHeight`, increments `historicalInterestHeight`, and calls `removePositionIndex`. Pre-balance check in `validatePositionStatus`; no post-balance check as transfer is handled by `ISSListing`. Margin destination is `msg.sender`.
- **Balance Checks**:
  - **Pre-Balance Check**: `status1 == false` and `status2 == 0` ensure position is pending and open.
  - **Post-Balance Check**: None, as transfers are handled by `ISSListing`.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `positionToken`, `pendingPositions`, `longIOByHeight`, `shortIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `ClosePositionBase`, `ClosePositionMargin`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position ID"`), executable (`"Position executable"`), closed (`"Position not open"`), or not owned (`"Not position owner"`).
- **Gas Usage Controls**: Minimal updates with pop-and-swap for arrays.

### updateSL(uint256 positionId, uint256 newStopLossPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newStopLossPrice` (uint256): New stop-loss price (normalized).
- **Behavior**: Updates the stop-loss price for an open position. Emits `StopLossUpdated`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status2 == 0` and owned by `msg.sender` (`"Not position owner"`). Fetches `currentPrice` via `ISSListing.prices` (input: `listingAddress`, returns: `uint256`). Validates `newStopLossPrice` (`< currentPrice` for long, `> currentPrice` for short). Calls `updateSLInternal` to set `riskParams.priceStopLoss`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `RiskParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position ID"`), closed (`"Position not open"`), not owned (`"Not position owner"`), or stop-loss is invalid (`"Stop loss too high for long"` or `"Stop loss too low for short"`).
- **Gas Usage Controls**: Single state update, minimal gas.

### updateTP(uint256 positionId, uint256 newTakeProfitPrice)
- **Parameters**:
  - `positionId` (uint256): Position ID.
  - `newTakeProfitPrice` (uint256): New take-profit price (normalized).
- **Behavior**: Updates the take-profit price for an open position. Emits `TakeProfitUpdated`.
- **Internal Call Flow**: Validates position in `positionCoreBase`, ensures `status2 == 0` and owned by `msg.sender` (`"Not position owner"`). Validates `newTakeProfitPrice` (`> priceAtEntry` for long, `< priceAtEntry` for short). Calls `updateTPInternal` to set `riskParams.priceTakeProfit`. No transfers or balance checks.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `riskParams`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `RiskParams`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if position is invalid (`"Invalid position ID"`), closed (`"Position not open"`), not owned (`"Not position owner"`), or take-profit is invalid (`"Take profit too low for long"` or `"Take profit too high for short"`).
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
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `marginParams`, `leverageParams`, `positionsByType`, `longIOByHeight`, `historicalInterestTimestamps`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `MarginParams`, `LeverageParams`, `ClosePositionBase`, `ClosePositionMargin`, `LongCloseParams`, `PayoutUpdate`.
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
  - **Mappings**: `positionCoreBase`, `positionCoreStatus`, `priceParams`, `marginParams`, `leverageParams`, `riskParams`, `positionsByType`, `pendingPositions`, `positionToken`.
  - **Structs**: `PositionCoreBase`, `PositionCoreStatus`, `PriceParams`, `MarginParams`, `LeverageParams`, `RiskParams`, `PositionAction`, `ExecutionContextBase`, `ExecutionContextCounts`, `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant`.
  - Reverts if `listingAddress` is zero (`"Invalid listing"`).
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
- **Restrictions**: Reverts if `positionType > 1` (`"Invalid position type"`).
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
- **Restrictions**: Reverts if `positionId` is invalid (`"Invalid position ID"`).
- **Gas Usage Controls**: Minimal gas, view function.

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
- **Gas Usage Controls**: `maxIterations`, view function, minimal gas.

## Additional Details
- **Decimal Handling**: Uses `DECIMAL_PRECISION` (1e18) for normalization across token decimals, with `IERC20.decimals()` for token-specific precision (assumes `decimals <= 18`).
- **Market-Based Execution**: Supported in `drive` when `minEntryPrice` and `maxEntryPrice` are zero, and in `enterLong`/`enterShort` when `entryPriceStr` is "0" or "0-0", using the current price from `ISSListing.prices` via `parseEntryPrice` in `SSDUtilityPartial`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant`.
- **Gas Optimization**: Employs `maxIterations`, `gasleft() >= 100000`, and pop-and-swap for array operations. Fixed iteration limit (1000) in `getMuxesView` ensures gas safety.
- **Listing Validation**: Uses `ISSAgent.getListing` for robust checks.
- **Token Usage**: Long positions use tokenA margins, tokenB payouts; short positions use tokenB margins, tokenA payouts.
- **Position Lifecycle**: Pending (`status1 == false`, `status2 == 0`) to executable (`status1 == true`, `status2 == 0`) to closed (`status2 == 1`) or cancelled (`status2 == 2`).
- **Events**: Emitted for mux operations (`MuxAdded`, `MuxRemoved`), position entry (`PositionEntered` with `positionId`, `maker`, `positionType`, `minEntryPrice`, `maxEntryPrice`, `mux`), closure (`PositionClosed`), cancellation (`PositionCancelled`), margin addition (`ExcessMarginAdded`), SL/TP updates (`StopLossUpdated`, `TakeProfitUpdated`), and batch operations (`AllLongsClosed`, `AllLongsCancelled`, `AllShortsClosed`, `AllShortsCancelled`, `PositionsExecuted`).
- **Mux Integration**: `muxes` mapping (moved to `SSDUtilityPartial`) authorizes external contracts. `drive` creates positions for `maker` by any caller, `drift` closes them with payouts to `msg.sender` (mux) for authorized muxes. `PositionEntered` includes `mux` (`msg.sender` for `drive`, `address(0)` for `enterLong`/`enterShort`).
- **Safety**: Balance checks, explicit casting (e.g., `uint8`, `uint256`, `address(uint160)`), no inline assembly, and modular helpers (`validateExcessMargin`, `transferExcessMargin`, `updateMarginAndInterest`, `updateLiquidationPrice`, `updateSLInternal`, `updateTPInternal`, `uint2str`) ensure robustness.
