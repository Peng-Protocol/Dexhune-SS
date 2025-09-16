# Shock Space Contracts Documentation
The System integrates of MFPAgent, MFPListingLogic, CCLiquidityLogic, MFPListingTemplate and CCLiquidityTemplate. These files are derived from 'Marker Foundry : Pairing (MFP)' and 'CoinClash (CC)'. Documentation on 'Routers' and 'Drivers' can be found within the directory. 

Together they form an AMM Orderbook Hybrid for leverage trading on the EVM. 

## CCLiquidityLogic Contract

The liquidity logic inherits `CCLiquidityTemplate` and is used by the `MFPAgent` to deploy new liquidity contracts tied to listing contracts for a unique `tokenA` and `tokenB` pair.

### Mappings and Arrays

- None defined in this contract.

### State Variables

- None defined in this contract.

### Functions

#### deploy

- **Parameters**:
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions**:
  - Deploys a new `CCLiquidityTemplate` contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns**:
  - `address`: Address of the newly deployed `CCLiquidityTemplate` contract.

## MFPListingLogic Contract

The listing logic inherits `MFPListingTemplate` and is used by the `MFPAgent` to deploy new listing contracts tied to liquidity contracts for a unique `tokenA` and `tokenB` pair.

### Mappings and Arrays

- None defined in this contract.

### State Variables

- None defined in this contract.

### Functions

#### deploy

- **Parameters**:
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions**:
  - Deploys a new `MFPListingTemplate` contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns**:
  - `address`: Address of the newly deployed `MFPListingTemplate` contract.

## MFPAgent Contract

The agent manages token listings, enables the creation of unique listings and liquidities for token pairs, verifies Uniswap V2 pair tokens (handling WETH for native ETH), and arbitrates valid listings, templates, and routers.

### Structs

- **ListingDetails**: Details of a listing contract.
  - `listingAddress` (address): Listing contract address.
  - `liquidityAddress` (address): Associated liquidity contract address.
  - `tokenA` (address): First token in pair.
  - `tokenB` (address): Second token in pair.
  - `listingId` (uint256): Listing ID.

### Mappings and Arrays

- `getListing` (mapping - address => address => address): Maps `tokenA` to `tokenB` to the listing address for a trading pair.
- `allListings` (address[]): Array of all listing addresses created.
- `allListedTokens` (address[]): Array of all unique tokens listed.
- `queryByAddress` (mapping - address => uint256[]): Maps a token to an array of listing IDs involving that token.
- `getLister` (mapping - address => address): Maps listing address to the lister’s address.
- `listingsByLister` (mapping - address => uint256[]): Maps a lister to an array of their listing IDs.

### State Variables

- `routers` (address[]): Array of router contract addresses, set post-deployment via `addRouter`.
- `listingLogicAddress` (address): Address of the `MFPListingLogic` contract, set post-deployment.
- `liquidityLogicAddress` (address): Address of the `SSLiquidityLogic` contract, set post-deployment.
- `registryAddress` (address): Address of the registry contract, set post-deployment.
- `listingCount` (uint256): Counter for the number of listings created, incremented per listing.
- `wethAddress` (address): Address of the WETH contract, set post-deployment via `setWETHAddress`.
- `globalizerAddress` (address): Address of the globalizer contract, set post-deployment via `setGlobalizerAddress`.

### Functions

#### Setter Functions

- **addRouter**
  - **Parameters**:
    - `router` (address): Address to add to the routers array.
  - **Actions**:
    - Requires non-zero address and that the router does not already exist.
    - Appends the router to the `routers` array.
    - Emits `RouterAdded` event.
    - Restricted to owner via `onlyOwner` modifier.
- **removeRouter**
  - **Parameters**:
    - `router` (address): Address to remove from the routers array.
  - **Actions**:
    - Requires non-zero address and that the router exists.
    - Removes the router by swapping with the last element and popping the array.
    - Emits `RouterRemoved` event.
    - Restricted to owner via `onlyOwner` modifier.
- **getRouters**
  - **Actions**:
    - Returns the current `routers` array.
  - **Returns**:
    - `address[]`: Array of all router addresses.
- **setListingLogic**
  - **Parameters**:
    - `_listingLogic` (address): Address to set as the listing logic contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `listingLogicAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setLiquidityLogic**
  - **Parameters**:
    - `_liquidityLogic` (address): Address to set as the liquidity logic contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `liquidityLogicAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setRegistry**
  - **Parameters**:
    - `_registryAddress` (address): Address to set as the registry contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `registryAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setWETHAddress**
  - **Parameters**:
    - `_wethAddress` (address): Address to set as the WETH contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `wethAddress` state variable.
    - Emits `WETHAddressSet` event.
    - Restricted to owner via `onlyOwner` modifier.
- **setGlobalizerAddress**
  - **Parameters**:
    - `_globalizerAddress` (address): Address to set as the globalizer contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `globalizerAddress` state variable.
    - Emits `GlobalizerAddressSet` event.
    - Restricted to owner via `onlyOwner` modifier.

#### Listing Functions
- **listToken**
  - **Parameters**:
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create listing and liquidity contracts.
    - Calls `_initializeListing` to set up listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Calls `_updateState` to update mappings and arrays, storing `msg.sender` as lister.
    - Emits `ListingCreated` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **listNative**
  - **Parameters**:
    - `token` (address): Token to pair with native currency.
    - `isA` (bool): If true, native currency is `tokenA`; else, `tokenB`.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Sets `nativeAddress` to `address(0)` for native currency.
    - Determines `tokenA` and `tokenB` based on `isA`.
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create listing and liquidity contracts.
    - Calls `_initializeListing` to set up listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Calls `_updateState` to update mappings and arrays, storing `msg.sender` as lister.
    - Emits `ListingCreated` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **relistToken**
  - **Parameters**:
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Checks tokens are not identical and pair is already listed.
    - Verifies `msg.sender` is the original lister via `getLister`.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create new listing and liquidity contracts.
    - Calls `_initializeListing` to set up new listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up new liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and `msg.sender` as lister.
    - Emits `ListingRelisted` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `newListingAddress` (address): Address of the new listing contract.
    - `newLiquidityAddress` (address): Address of the new liquidity contract.
- **relistNative**
  - **Parameters**:
    - `token` (address): Token paired with native currency.
    - `isA` (bool): If true, native currency is `tokenA`; else, `tokenB`.
    - `uniswapV2Pair` (address): Uniswap V2 pair address for the token pair.
  - **Actions**:
    - Sets `nativeAddress` to `address(0)` for native currency.
    - Determines `tokenA` and `tokenB` based on `isA`.
    - Checks tokens are not identical and pair is already listed.
    - Verifies `msg.sender` is the original lister via `getLister`.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create new listing and liquidity contracts.
    - Calls `_initializeListing` to set up new listing contract with `routers` array, listing ID, liquidity address, tokens, agent, registry, Uniswap V2 pair, and `globalizerAddress` if set.
    - Calls `_initializeLiquidity` to set up new liquidity contract with `routers` array, listing ID, listing address, tokens, and agent.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and `msg.sender` as lister.
    - Emits `ListingRelisted` event with lister address.
    - Increments `listingCount`.
  - **Returns**:
    - `newListingAddress` (address): Address of the new listing contract.
    - `newLiquidityAddress` (address): Address of the new liquidity contract.
- **transferLister**
  - **Parameters**:
    - `listingAddress` (address): Address of the listing to transfer lister status.
    - `newLister` (address): Address of the new lister.
  - **Actions**:
    - Verifies `msg.sender` is the current lister via `getLister`.
    - Requires non-zero `newLister` address.
    - Updates `getLister` mapping with `newLister`.
    - Retrieves `listingId` from `allListings` and appends to `listingsByLister` for `newLister`.
    - Emits `ListerTransferred` event.
- **getListingsByLister**
  - **Parameters**:
    - `lister` (address): Address of the lister to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Retrieves indices from `listingsByLister` mapping.
    - Calculates start and end bounds based on `step` and `maxIteration`.
    - Returns a subset of indices for pagination.
  - **Returns**:
    - `uint256[]`: Array of listing IDs for the lister.

#### View Functions
- **isValidListing**
  - **Parameters**:
    - `listingAddress` (address): Address to check.
  - **Actions**:
    - Iterates `allListings` to find matching address.
    - If found, retrieves `tokenA` and `tokenB` via `ICCListingTemplate.getTokens`.
    - Retrieves liquidity address via `ICCListing.liquidityAddressView`.
    - Constructs `ListingDetails` struct with `listingAddress`, `liquidityAddress`, `tokenA`, `tokenB`, and `listingId`.
  - **Returns**:
    - `isValid` (bool): True if listing is valid.
    - `details` (ListingDetails): Struct with `listingAddress`, `liquidityAddress`, `tokenA`, `tokenB`, and `listingId`.
- **queryByIndex**
  - **Parameters**:
    - `index` (uint256): Index to query.
  - **Actions**:
    - Validates index is within `allListings` length.
    - Retrieves listing address from `allListings` array.
  - **Returns**:
    - `address`: Listing address at the index.
- **queryByAddressView**
  - **Parameters**:
    - `target` (address): Token to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Retrieves indices from `queryByAddress` mapping.
    - Calculates start and end bounds based on `step` and `maxIteration`.
    - Returns a subset of indices for pagination.
  - **Returns**:
    - `uint256[]`: Array of listing IDs for the target token.
- **queryByAddressLength**
  - **Parameters**:
    - `target` (address): Token to query.
  - **Actions**:
    - Retrieves length of `queryByAddress` array for the target token.
  - **Returns**:
    - `uint256`: Number of listing IDs for the target token.
- **allListingsLength**
  - **Actions**:
    - Retrieves length of `allListings` array.
  - **Returns**:
    - `uint256`: Total number of listings.
- **allListedTokensLength**
  - **Actions**:
    - Retrieves length of `allListedTokens` array.
  - **Returns**:
    - `uint256`: Total number of listed tokens.

## Additional Details

- **Relisting Behavior**:
  - **Purpose**: `relistToken` and `relistNative` allow the original lister to replace a token pair listing with a new one to update routers, Uniswap V2 pair, or other configurations.
  - **Replacement**:
    - Deploys new `MFPListingTemplate` and `SSLiquidityTemplate` contracts with a new `listingId`.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and lister.
    - Old listing remains in `allListings` but is no longer referenced in `getListing` for the token pair.
  - **User Interaction with Old Listings**:
    - Old listings remain accessible via `CCOrderRouter` functions (e.g., `createTokenBuyOrder`, `createTokenSellOrder`, `clearSingleOrder`, `executeLongPayouts`, `executeShortPayouts`, `settleLongLiquid`, `settleShortLiquid`) because `isValidListing` validates against `allListings`.
    - Users can interact with old listings by explicitly providing their addresses, allowing order creation, cancellation, or payout execution, provided sufficient liquidity and valid order states.
    - New orders for the token pair will use the new listing address via `getListing[tokenA][tokenB]`, potentially causing confusion if users interact with the old listing unintentionally.
  - **Event**: Emits `ListingRelisted` with old and new listing addresses, token pair, new `listingId`, and lister.
- **Globalizer Integration**:
  - The `globalizerAddress` is set in new listing contracts via `setGlobalizerAddress` during `_initializeListing` if defined, enabling integration with a separate globalizer contract for order and liquidity management.
- **Lister Tracking**:
  - `msg.sender` is stored as the lister in `listToken` and `listNative` via `getLister` and `listingsByLister`.
  - `transferLister` allows the current lister to transfer control to a new address, updating `getLister` and `listingsByLister`.
  - `getListingsByLister` provides paginated access to a lister’s listing IDs.
  
# CCLiquidityTemplate Documentation

## Overview
The `CCLiquidityTemplate`, implemented in Solidity (^0.8.2), manages liquidity pools, fees, slot updates, and payout functionality in a decentralized trading platform. It integrates with `ICCAgent`, `ITokenRegistry`, `ICCListing`, `IERC20`, and `ICCGlobalizer` for registry updates, token operations, and liquidity globalization. State variables are public, accessed via getters or view functions, with amounts normalized to 1e18. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation with try-catch for external calls.

**SPDX License**: BSL 1.1 - Peng Protocol 2025

**Version**: 0.1.20 (Updated 2025-09-14)

**Changes**:
- v0.1.20: Added `updateType` 8 (xFees subtraction) and 9 (yFees subtraction) in `ccUpdate` to subtract from `xFees`/`yFees`, ensuring compatibility with `CCLiquidityPartial.sol` (v0.0.41). Updated `transactToken` and `transactNative` to limit withdrawals based on `xLiquid`/`yLiquid`.
- v0.1.19: Updated documentation to include all functions, clarified internal call trees, and corrected view function returns.
- v0.1.18: Added `updateType` 6 (xSlot dFeesAcc update) and 7 (ySlot dFeesAcc update) in `ccUpdate` to update `dFeesAcc` without modifying allocation or liquidity. Updated payout documentation.
- v0.1.17: Removed `xLiquid`/`yLiquid` reduction in `transactToken` and `transactNative` to prevent double reduction, as `ccUpdate` handles liquidity adjustments.
- v0.1.16: Added `updateType` 4 (xSlot depositor change) and 5 (ySlot depositor change) in `ccUpdate` to update depositor and `userXIndex`/`userYIndex`. Emits `SlotDepositorChanged`.
- v0.1.15: Removed unnecessary checks in `ccUpdate`.
- v0.1.14: Skipped allocation check for new slots in `ccUpdate` for `updateType` 2 and 3.
- v0.1.13: Updated `ccUpdate` for `updateType` 2 and 3 to adjust `xLiquid`/`yLiquid` by allocation difference.
- v0.1.12: Added `updateType` 4 and 5 to `ccUpdate` for depositor changes.
- v0.1.11: Hid `routerAddresses` as `routerAddressesView` is preferred.
- v0.1.10: Removed `updateLiquidity` as `ccUpdate` is sufficient.
- v0.1.8: Added payout functionality (`ssUpdate`, `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`, etc.) from `CCListingTemplate.sol`.

**Compatibility**:
- CCListingTemplate.sol (v0.0.10)
- CCLiquidityRouter.sol (v0.0.25)
- CCMainPartial.sol (v0.0.10)
- CCGlobalizer.sol (v0.2.1)
- ICCLiquidity.sol (v0.0.4)
- ICCListing.sol (v0.0.7)
- CCSEntryPartial.sol (v0.0.18)

## State Variables
- `routersSet`: `bool private` - Tracks if routers are set.
- `listingAddress`: `address public` - Listing contract address.
- `tokenA`: `address public` - Token A address (ETH if zero).
- `tokenB`: `address public` - Token B address (ETH if zero).
- `listingId`: `uint256 public` - Listing identifier.
- `agent`: `address public` - Agent contract address.
- `liquidityDetail`: `LiquidityDetails private` - Stores `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- `activeXLiquiditySlots`: `uint256[] private` - Active xSlot indices.
- `activeYLiquiditySlots`: `uint256[] private` - Active ySlot indices.
- `routerAddresses`: `address[] private` - Authorized router addresses.
- `nextPayoutId`: `uint256 private` - Tracks next payout ID.

## Mappings
- `routers`: `mapping(address => bool) public` - Authorized routers.
- `xLiquiditySlots`: `mapping(uint256 => Slot) private` - Token A slot data.
- `yLiquiditySlots`: `mapping(uint256 => Slot) private` - Token B slot data.
- `userXIndex`: `mapping(address => uint256[]) private` - User xSlot indices.
- `userYIndex`: `mapping(address => uint256[]) private` - User ySlot indices.
- `longPayout`: `mapping(uint256 => LongPayoutStruct) private` - Long payout details.
- `shortPayout`: `mapping(uint256 => ShortPayoutStruct) private` - Short payout details.
- `userPayoutIDs`: `mapping(address => uint256[]) private` - Payout order IDs per user.
- `activeUserPayoutIDs`: `mapping(address => uint256[]) private` - Active payout order IDs per user.

## Arrays
- `longPayoutByIndex`: `uint256[] private` - Tracks all long payout order IDs.
- `shortPayoutByIndex`: `uint256[] private` - Tracks all short payout order IDs.
- `activeLongPayouts`: `uint256[] private` - Tracks active long payout order IDs (status = 1).
- `activeShortPayouts`: `uint256[] private` - Tracks active short payout order IDs (status = 1).

## Structs
1. **LiquidityDetails**:
   - `xLiquid`: Normalized token A liquidity.
   - `yLiquid`: Normalized token B liquidity.
   - `xFees`: Normalized token A fees.
   - `yFees`: Normalized token B fees.
   - `xFeesAcc`: Cumulative token A fee volume.
   - `yFeesAcc`: Cumulative token B fee volume.
2. **Slot**:
   - `depositor`: Slot owner.
   - `recipient`: Address receiving withdrawals.
   - `allocation`: Normalized liquidity allocation.
   - `dFeesAcc`: Cumulative fees at deposit (`yFeesAcc` for xSlots, `xFeesAcc` for ySlots).
   - `timestamp`: Slot creation timestamp.
3. **UpdateType**:
   - `updateType`: Update type (0=balance, 1=fees addition, 2=xSlot, 3=ySlot, 4=xSlot depositor change, 5=ySlot depositor change, 6=xSlot dFeesAcc, 7=ySlot dFeesAcc, 8=xFees subtraction, 9=yFees subtraction).
   - `index`: Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot).
   - `value`: Normalized amount/allocation.
   - `addr`: Depositor address.
   - `recipient`: Recipient address for withdrawals.
4. **PreparedWithdrawal**:
   - `amountA`: Normalized token A withdrawal.
   - `amountB`: Normalized token B withdrawal.
5. **LongPayoutStruct**:
   - `makerAddress`: Payout creator.
   - `recipientAddress`: Payout recipient.
   - `required`: Normalized token B amount required.
   - `filled`: Normalized amount filled.
   - `amountSent`: Normalized amount of token A sent.
   - `orderId`: Payout order ID.
   - `status`: 0=cancelled, 1=pending, 2=partially filled, 3=filled.
6. **ShortPayoutStruct**:
   - `makerAddress`: Payout creator.
   - `recipientAddress`: Payout recipient.
   - `amount`: Normalized token A amount required.
   - `filled`: Normalized amount filled.
   - `amountSent`: Normalized amount of token B sent.
   - `orderId`: Payout order ID.
   - `status`: 0=cancelled, 1=pending, 2=partially filled, 3=filled.
7. **PayoutUpdate**:
   - `payoutType`: 0=long, 1=short.
   - `recipient`: Payout recipient.
   - `orderId`: Explicit order ID.
   - `required`: Amount required.
   - `filled`: Amount filled.
   - `amountSent`: Amount of opposite token sent.

## External Functions and Internal Call Trees
### setTokens(address _tokenA, address _tokenB)
- **Purpose**: Sets `tokenA` and `tokenB`, callable once.
- **Parameters**: `_tokenA`: Token A address (ETH if zero). `_tokenB`: Token B address (ETH if zero).
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: None.
- **Gas**: Two assignments.
- **Callers**: External setup.

### setAgent(address _agent)
- **Purpose**: Sets `agent`, callable once.
- **Parameters**: `_agent`: Agent contract address.
- **Restrictions**: Reverts if `agent` set or `_agent` invalid.
- **Internal Call Tree**: None.
- **Gas**: Single assignment.
- **Callers**: External setup.

### setListingId(uint256 _listingId)
- **Purpose**: Sets `listingId`, callable once.
- **Parameters**: `_listingId`: Listing identifier.
- **Restrictions**: Reverts if `listingId` set.
- **Internal Call Tree**: None.
- **Gas**: Single assignment.
- **Callers**: External setup.

### setListingAddress(address _listingAddress)
- **Purpose**: Sets `listingAddress`, callable once.
- **Parameters**: `_listingAddress`: Listing contract address.
- **Restrictions**: Reverts if `listingAddress` set or `_listingAddress` invalid.
- **Internal Call Tree**: None.
- **Gas**: Single assignment.
- **Callers**: External setup.

### setRouters(address[] memory _routers)
- **Purpose**: Sets router addresses, callable once.
- **Parameters**: `_routers`: Array of router addresses.
- **Restrictions**: Reverts if routers set or no valid routers provided.
- **Internal Call Tree**: None.
- **Gas**: Loop over `_routers`, array push.
- **Callers**: External setup.

### resetRouters()
- **Purpose**: Resets `routers` and `routerAddresses` to `ICCAgent.getRouters()`, restricted to lister.
- **Parameters**: None.
- **Restrictions**: Reverts if `msg.sender != ICCAgent.getLister(listingAddress)` or no routers available.
- **Internal Call Tree**: `ICCAgent.getLister`, `ICCAgent.getRouters`.
- **Gas**: Loop over `routerAddresses` to clear, loop over new routers, array operations.
- **Callers**: Lister via external call.

### ccUpdate(address depositor, UpdateType[] memory updates)
- **Purpose**: Updates liquidity, slots, fees, or depositors, adjusts `xLiquid`, `yLiquid`, `xFees`, `yFees`, updates `userXIndex` or `userYIndex`, calls `globalizeUpdate`, emits `LiquidityUpdated`, `FeesUpdated`, or `SlotDepositorChanged`.
- **Parameters**: `depositor`: Address for update. `updates`: Array of `UpdateType` structs.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Internal Call Flow**:
  - Iterates `updates`:
    - `updateType == 0`: Sets `xLiquid` (`index == 0`) or `yLiquid` (`index == 1`).
    - `updateType == 1`: Adds to `xFees` (`index == 0`) or `yFees` (`index == 1`), emits `FeesUpdated`.
    - `updateType == 2`: Updates `xLiquiditySlots`, adjusts `xLiquid`, updates `activeXLiquiditySlots`, `userXIndex`, calls `globalizeUpdate` (tokenA).
    - `updateType == 3`: Updates `yLiquiditySlots`, adjusts `yLiquid`, updates `activeYLiquiditySlots`, `userYIndex`, calls `globalizeUpdate` (tokenB).
    - `updateType == 4`: Updates `xLiquiditySlots` depositor, updates `userXIndex`, emits `SlotDepositorChanged`.
    - `updateType == 5`: Updates `yLiquiditySlots` depositor, updates `userYIndex`, emits `SlotDepositorChanged`.
    - `updateType == 6`: Updates `xLiquiditySlots.dFeesAcc` for fee claims.
    - `updateType == 7`: Updates `yLiquiditySlots.dFeesAcc` for fee claims.
    - `updateType == 8`: Subtracts from `xFees` (`index == 0`), emits `FeesUpdated`.
    - `updateType == 9`: Subtracts from `yFees` (`index == 1`), emits `FeesUpdated`.
  - Calls `globalizeUpdate`: Invokes `ICCGlobalizer.globalizeLiquidity` and `ITokenRegistry.initializeBalances`.
- **Internal Call Tree**: `globalizeUpdate` (`ICCAgent.globalizerAddress`, `ICCGlobalizer.globalizeLiquidity`, `ICCAgent.registryAddress`, `ITokenRegistry.initializeBalances`).
- **Gas**: Loop over `updates`, array operations, `globalizeUpdate` calls.
- **Callers**: `CCLiquidityPartial.sol` (`_updateDeposit`, `_executeWithdrawal`, `_executeFeeClaim`, `_changeDepositor`).

### ssUpdate(PayoutUpdate[] calldata updates)
- **Purpose**: Manages long (tokenB) and short (tokenA) payouts, updates `longPayout`, `shortPayout`, arrays, emits `PayoutOrderCreated` or `PayoutOrderUpdated`.
- **Parameters**: `updates`: Array of `PayoutUpdate` structs.
- **Restrictions**: Router-only (`routers[msg.sender]`).
- **Internal Call Flow**:
  - Iterates `updates`:
    - Validates `recipient`, `payoutType`, `required`/`filled`.
    - For `payoutType == 0` (long): Sets/updates `longPayout`, `longPayoutByIndex`, `activeLongPayouts`, `userPayoutIDs`, `activeUserPayoutIDs`, emits events.
    - For `payoutType == 1` (short): Sets/updates `shortPayout`, `shortPayoutByIndex`, `activeShortPayouts`, `userPayoutIDs`, `activeUserPayoutIDs`, emits events.
    - Calls `removePendingOrder` for cancelled or filled orders.
    - Increments `nextPayoutId` for new payouts.
- **Internal Call Tree**: `removePendingOrder`.
- **Gas**: Loop over `updates`, array operations.
- **Callers**: `CCOrderRouter.sol` for payout settlements.

### transactToken(address depositor, address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens, checks `xLiquid`/`yLiquid`, emits `TransactFailed` on failure.
- **Parameters**: `depositor`, `token` (tokenA or tokenB), `amount` (denormalized), `recipient`.
- **Restrictions**: Router-only, valid token, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Internal Call Tree**: `normalize`, `IERC20.decimals`, `IERC20.transfer`.
- **Gas**: Single transfer, balance check.
- **Callers**: `CCLiquidityPartial.sol` (`_transferWithdrawalAmount`, `_executeFeeClaim`).

### transactNative(address depositor, uint256 amount, address recipient)
- **Purpose**: Transfers ETH, checks `xLiquid`/`yLiquid`, emits `TransactFailed` on failure.
- **Parameters**: `depositor`, `amount` (denormalized), `recipient`.
- **Restrictions**: Router-only, non-zero amount, sufficient `xLiquid`/`yLiquid`.
- **Internal Call Tree**: `normalize`.
- **Gas**: Single transfer, balance check.
- **Callers**: `CCLiquidityPartial.sol` (`_transferWithdrawalAmount`, `_executeFeeClaim`).

### getNextPayoutID() view returns (uint256 payoutId)
- **Purpose**: Returns `nextPayoutId`.
- **Parameters**: None.
- **Internal Call Tree**: None.
- **Gas**: Single read.
- **Callers**: External contracts or frontends.

### removePendingOrder(uint256[] storage orders, uint256 orderId) internal
- **Purpose**: Removes order ID from specified array.
- **Parameters**: `orders`: Storage array. `orderId`: ID to remove.
- **Internal Call Tree**: None.
- **Gas**: Linear search, array pop.
- **Callers**: `ssUpdate` for payout cancellations or completions.

## View Functions
- `getListingAddress(uint256)`: Returns `listingAddress`.
- `liquidityAmounts()`: Returns `xLiquid`, `yLiquid`.
- `liquidityDetailsView()`: Returns `xLiquid`, `yLiquid`, `xFees`, `yFees`.
- `userXIndexView(address)`: Returns `userXIndex[user]`.
- `userYIndexView(address)`: Returns `userYIndex[user]`.
- `getActiveXLiquiditySlots()`: Returns `activeXLiquiditySlots`.
- `getActiveYLiquiditySlots()`: Returns `activeYLiquiditySlots`.
- `getXSlotView(uint256)`: Returns xSlot details.
- `getYSlotView(uint256)`: Returns ySlot details.
- `routerAddressesView()`: Returns `routerAddresses`.
- `userPayoutIDsView(address)`: Returns `userPayoutIDs[user]`.
- `activeLongPayoutsView()`: Returns `activeLongPayouts`.
- `activeShortPayoutsView()`: Returns `activeShortPayouts`.
- `activeUserPayoutIDsView(address)`: Returns `activeUserPayoutIDs[user]`.
- `getLongPayout(uint256)`: Returns `longPayout[orderId]`.
- `getShortPayout(uint256)`: Returns `shortPayout[orderId]`.

## Additional Details
- **Decimal Handling**: Normalizes to 1e18 using `IERC20.decimals`, denormalizes for transfers.
- **Reentrancy Protection**: Handled by routers (`CCLiquidityRouter`).
- **Gas Optimization**: Dynamic arrays, minimal external calls, try-catch for safety.
- **Token Usage**: xSlots provide token A, claim yFees; ySlots provide token B, claim xFees. Long payouts (tokenB), short payouts (tokenA).
- **Fee System**: Cumulative fees (`xFeesAcc`, `yFeesAcc`) never decrease; `dFeesAcc` tracks fees at slot updates.
- **Payout System**: Long/short payouts tracked in `longPayout`, `shortPayout`, with active arrays for status=1, historical arrays for all orders.
- **Globalization**: `ccUpdate` calls `globalizeUpdate` for slot updates or withdrawals.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly, high-level Solidity.
  - Try-catch for external calls with detailed revert strings.
  - Public state variables accessed via getters or view functions.
  - No reserved keywords, no `virtual`/`override`.
- **Router Security**: Only `routers[msg.sender]` can call restricted functions.
- **Events**: Comprehensive emission for state changes and failures.

# MFPListingTemplate Documentation

## Overview
The `MFPListingTemplate` contract (Solidity ^0.8.2) supports decentralized trading for a token pair, with price discovery via `IERC20.balanceOf`. It manages buy/sell orders and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement/cancellation, with auto-generated historical data if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

**Version**: 0.3.9 (Updated 2025-09-11)

**Changes**:
- v0.3.9: Replaced `UpdateType` struct with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate` structs. Updated `ccUpdate` to accept new struct arrays, removing `updateType`, `updateSort`, `updateData` arrays. Modified `_processBuyOrderUpdate` and `_processSellOrderUpdate` to handle new structs directly without encoding/decoding. Ensured direct struct field assignments for clarity and gas efficiency.
- Updated `_processHistoricalUpdate` to handle full `HistoricalUpdate` struct, using helper functions `_updateHistoricalData` and `_updateDayStartIndex` for clarity and reduced complexity.
- v0.3.8: Added minimum price "1" in `prices`.
- v0.3.7: Derived "MFP" from "CC".

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.9)

## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **ICCLiquidityTemplate**: Defines `liquidityDetail()`.
- **ITokenRegistry**: Defines `initializeTokens(address, address[])`.
- **ICCGlobalizer**: Defines `globalizeOrders(address, address)`.
- **ICCAgent**: Defines `getLister(address)`, `getRouters()`.

## Structs
- **DayStartFee**: `dayStartXFeesAcc`, `dayStartYFeesAcc`, `timestamp`.
- **HistoricalData**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **BuyOrderUpdate**: `structId` (0: Core, 1: Pricing, 2: Amounts), `orderId`, `makerAddress`, `recipientAddress`, `status`, `maxPrice`, `minPrice`, `pending`, `filled`, `amountSent`.
- **SellOrderUpdate**: Similar to `BuyOrderUpdate`.
- **BalanceUpdate**: `xBalance`, `yBalance` (normalized, 1e18).
- **HistoricalUpdate**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## State Variables
- **`routers`**: `mapping(address => bool) public` - Authorized routers.
- **`routerAddresses`**: `address[] private` - Router addresses.
- **`_routersSet`**: `bool private` - Locks router settings.
- **`tokenA`, `tokenB`**: `address public` - Token pair (ETH as `address(0)`).
- **`decimalsA`, `decimalsB`**: `uint8 public` - Token decimals.
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agentView`**: `address public` - Agent address.
- **`registryAddress`**: `address public` - Registry address.
- **`liquidityAddressView`**: `address public` - Liquidity contract.
- **`globalizerAddress`**: `address public` - Globalizer contract.
- **`_globalizerSet`**: `bool private` - Locks globalizer setting.
- **`nextOrderId`**: `uint256 private` - Order ID counter.
- **`dayStartFee`**: `DayStartFee public` - Daily fee tracking.
- **`_pendingBuyOrders`, `_pendingSellOrders`**: `uint256[] private` - Pending order IDs.
- **`makerPendingOrders`**: `mapping(address => uint256[]) private` - Maker order IDs.
- **`_historicalData`**: `HistoricalData[] private` - Price/volume history.
- **`_dayStartIndices`**: `mapping(uint256 => uint256) private` - Midnight timestamps to indices.
- **`buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`**: `mapping(uint256 => ...)` - Buy order data.
- **`sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`**: `mapping(uint256 => ...)` - Sell order data.
- **`orderStatus`**: `mapping(uint256 => OrderStatus) private` - Order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets globalizer contract address (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Restrictions**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `globalizerAddress_` for `globalizeUpdate` calls to `ICCGlobalizer.globalizeOrders`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for `ccUpdate`, `transactToken`, `transactNative`.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if `_routersSet` or `routers_` invalid/empty.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `routers` entries to true, populates `routerAddresses`.

#### resetRouters()
- **Purpose**: Fetches lister via `ICCAgent.getLister`, restricts to lister, clears `routers`, updates with `ICCAgent.getRouters`.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if `msg.sender` not lister or no routers.
- **Internal Call Tree**: None (directly calls `ICCAgent.getLister`, `ICCAgent.getRouters`).
- **Parameters/Interactions**: Uses `agentView`, updates `routers`, `routerAddresses`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, initializes `_historicalData`, `dayStartFee` (callable once).
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Calls `IERC20.decimals` for `tokenA_`, `tokenB_`.

#### setAgent(address agent_)
- **Purpose**: Sets `agentView` (callable once).
- **State Changes**: `agentView`.
- **Restrictions**: Reverts if `agentView` set or `agent_` invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `agentView` for `resetRouters`.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `listingId` (callable once).
- **State Changes**: `listingId`.
- **Restrictions**: Reverts if `listingId` set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `listingId` for event emissions.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress` (callable once).
- **State Changes**: `registryAddress`.
- **Restrictions**: Reverts if `registryAddress` set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `registryAddress` for `_updateRegistry`.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView` (callable once).
- **State Changes**: `liquidityAddressView`.
- **Restrictions**: Reverts if `liquidityAddressView` set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `liquidityAddressView` for `ccUpdate` fee fetching.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens via `IERC20.transfer` with pre/post balance checks.
- **State Changes**: None directly (affects token balances).
- **Restrictions**: Router-only, valid token (`tokenA` or `tokenB`), non-zero `amount`, valid `recipient`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Uses `routers`, `tokenA`, `tokenB`, `IERC20.transfer`, `IERC20.balanceOf`. Emits `TransactionFailed` on failure.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH via low-level `call` with pre/post balance checks.
- **State Changes**: None directly (affects ETH balance).
- **Restrictions**: Router-only, one token must be `address(0)`, non-zero `amount`, valid `recipient`, `msg.value` matches `amount`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Uses `routers`, `tokenA`, `tokenB`, low-level `call`. Emits `TransactionFailed` on failure.

#### ccUpdate(BuyOrderUpdate[] calldata buyUpdates, SellOrderUpdate[] calldata sellUpdates, BalanceUpdate[] calldata balanceUpdates, HistoricalUpdate[] calldata historicalUpdates)
- **Purpose**: Updates buy/sell orders, balances, or historical data, callable by routers.
- **Parameters**:
  - `buyUpdates`: Array of `BuyOrderUpdate` structs for buy orders.
  - `sellUpdates`: Array of `SellOrderUpdate` structs for sell orders.
  - `balanceUpdates`: Array of `BalanceUpdate` structs for balances.
  - `historicalUpdates`: Array of `HistoricalUpdate` structs for historical data.
- **Logic**:
  1. Verifies router caller via `routers`.
  2. Processes `buyUpdates` via `_processBuyOrderUpdate`:
     - `structId=0` (Core): Updates `buyOrderCore`, manages `_pendingBuyOrders`, `makerPendingOrders` via `removePendingOrder` if `status=0` or `3`, increments `nextOrderId` if `status=1`. Sets `orderStatus.hasCore`. Emits `OrderUpdated`.
     - `structId=1` (Pricing): Updates `buyOrderPricing`. Sets `orderStatus.hasPricing`.
     - `structId=2` (Amounts): Updates `buyOrderAmounts`, adds difference of old/new `filled` to `_historicalData.yVolume`, `amountSent` to `_historicalData.xVolume`. Sets `orderStatus.hasAmounts`.
     - Invalid `structId` emits `UpdateFailed`.
  3. Processes `sellUpdates` via `_processSellOrderUpdate` (similar, updates `sellOrder*`, `_pendingSellOrders`, `_historicalData.xVolume`, `_historicalData.yVolume`).
  4. Processes `balanceUpdates`: Pushes `HistoricalData` with current price (`(balanceB * 1e18) / balanceA` or 1), `xBalance`, `yBalance`. Emits `BalancesUpdated`.
  5. Processes `historicalUpdates` via `_processHistoricalUpdate`: Creates `HistoricalData` with `price`, balances, timestamp, updates `_dayStartIndices`. Emits `UpdateFailed` if `price=0`.
  6. Checks `orderStatus` for completeness, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
  7. Updates `dayStartFee` if not same day, fetching fees via `ICCLiquidityTemplate.liquidityDetail`.
  8. Calls `globalizeUpdate`.
- **State Changes**: `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`, `nextOrderId`.
- **External Interactions**: `IERC20.balanceOf` (`ccUpdate`, `prices`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`).
- **Internal Call Tree**: `_processBuyOrderUpdate` (`removePendingOrder`, `_updateRegistry`), `_processSellOrderUpdate` (`removePendingOrder`, `_updateRegistry`), `_processHistoricalUpdate` (`_updateHistoricalData`, `_updateDayStartIndex`, `_floorToMidnight`), `_updateRegistry` (`ITokenRegistry.initializeTokens`), `globalizeUpdate` (`ICCGlobalizer.globalizeOrders`), `_floorToMidnight`, `_isSameDay`, `removePendingOrder`, `normalize`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate`, `prices`, `volumeBalances`, `_updateHistoricalData`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: `transactToken`, `transactNative`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.
- **Parameters/Interactions**: Used for `dayStartFee`, `_dayStartIndices`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate`, `_updateHistoricalData`, `_updateDayStartIndex`.
- **Parameters/Interactions**: Used for `HistoricalData.timestamp`, `dayStartFee.timestamp`, `_dayStartIndices`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None (intended for analytics).
- **Parameters/Interactions**: Queries `_historicalData` with `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `_processBuyOrderUpdate`, `_processSellOrderUpdate`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Calls `ITokenRegistry.initializeTokens` with `tokenA`, `tokenB`. Emits `RegistryUpdateFailed`, `ExternalCallFailed`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Calls `ICCGlobalizer.globalizeOrders` with `maker`, `tokenA` or `tokenB`. Emits `GlobalUpdateFailed`, `ExternalCallFailed`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes order ID from array.
- **Callers**: `_processBuyOrderUpdate`, `_processSellOrderUpdate`.
- **Parameters/Interactions**: Modifies `_pendingBuyOrders` or `_pendingSellOrders`.

#### _processBuyOrderUpdate(BuyOrderUpdate memory update)
- **Purpose**: Updates buy order structs, manages `_pendingBuyOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `_historicalData.yVolume`, `_historicalData.xVolume`, `orderStatus`, `nextOrderId`. Emits `OrderUpdated`, `UpdateFailed`.

#### _processSellOrderUpdate(SellOrderUpdate memory update)
- **Purpose**: Updates sell order structs, manages `_pendingSellOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_historicalData.xVolume`, `_historicalData.yVolume`, `orderStatus`, `nextOrderId`. Emits `OrderUpdated`, `UpdateFailed`.

#### _processHistoricalUpdate(HistoricalUpdate memory update) returns (bool historicalUpdated)
- **Purpose**: Creates `HistoricalData` entry.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `_updateHistoricalData`, `_updateDayStartIndex`, `_floorToMidnight`.
- **Parameters/Interactions**: Uses `price`, balances, timestamp. Updates `_historicalData`, `_dayStartIndices`. Emits `UpdateFailed`.

#### _updateHistoricalData(HistoricalUpdate memory update)
- **Purpose**: Pushes new `HistoricalData` entry.
- **Callers**: `_processHistoricalUpdate`.
- **Internal Call Tree**: `normalize`, `_floorToMidnight`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `IERC20.balanceOf`.

#### _updateDayStartIndex(uint256 timestamp)
- **Purpose**: Updates `_dayStartIndices` for midnight timestamp.
- **Callers**: `_processHistoricalUpdate`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Updates `_dayStartIndices`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for error messages.
- **Callers**: `_updateRegistry`, `globalizeUpdate`, `transactToken`, `transactNative`.
- **Parameters/Interactions**: Supports error messages.

### View Functions
#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns `tokenA`, `tokenB`.
- **Restrictions**: Reverts if tokens not set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### getNextOrderId() returns (uint256 orderId_)
- **Purpose**: Returns `nextOrderId`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### routerAddressesView() returns (address[] memory addresses)
- **Purpose**: Returns `routerAddresses`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### prices(uint256 _listingId) returns (uint256 price)
- **Purpose**: Computes price as `(balanceB * 1e18) / balanceA` or 1 if either balance is zero.
- **Internal Call Tree**: `normalize`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `IERC20.balanceOf`, `decimalsA`, `decimalsB`.

#### floorToMidnightView(uint256 inputTimestamp) returns (uint256 midnight)
- **Purpose**: Rounds `inputTimestamp` to midnight UTC.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### getDayStartIndex(uint256 midnightTimestamp) returns (uint256 index)
- **Purpose**: Returns `_dayStartIndices[midnightTimestamp]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_dayStartIndices`.

#### volumeBalances(uint256 _listingId) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns normalized `tokenA`, `tokenB` balances.
- **Internal Call Tree**: `normalize`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `IERC20.balanceOf`, `decimalsA`, `decimalsB`.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending buy order IDs for `maker`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`, `buyOrderCore`.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending sell order IDs for `maker`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`, `sellOrderCore`.

#### getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns `buyOrderCore[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderCore`.

#### getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns `buyOrderPricing[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderPricing`.

#### getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns `buyOrderAmounts[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderAmounts`.

#### getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns `sellOrderCore[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderCore`.

#### getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns `sellOrderPricing[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderPricing`.

#### getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns `sellOrderAmounts[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderAmounts`.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns `makerPendingOrders[maker]` subset.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`.

#### makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)
- **Purpose**: Returns all `makerPendingOrders[maker]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`.

#### getHistoricalDataView(uint256 index) returns (HistoricalData memory data)
- **Purpose**: Returns `_historicalData[index]`.
- **Restrictions**: Reverts if `index` out of bounds.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_historicalData`.

#### historicalDataLengthView() returns (uint256 length)
- **Purpose**: Returns `_historicalData.length`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

## Parameters and Interactions
- **Orders**: `ccUpdate` with `buyUpdates`/`sellUpdates` updates orders. Buy: inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`). Sell: inputs `tokenA` (`amounts.filled`), outputs `tokenB` (`amounts.amountSent`). Buy adds to `yVolume`, sell to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Price**: Computed via `IERC20.balanceOf` in `prices`, returns `(balanceB * 1e18) / balanceA` or 1.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate` with `maker`, `tokenA` or `tokenB`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`, stored in `dayStartFee`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`historicalUpdates`) or auto-generated in `balanceUpdates`, using `prices`.
- **External Calls**: `IERC20.balanceOf` (`prices`, `volumeBalances`, `transactToken`, `ccUpdate`), `IERC20.transfer` (`transactToken`), `IERC20.decimals` (`setTokens`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`), `ICCAgent.getLister` (`resetRouters`), `ICCAgent.getRouters` (`resetRouters`), low-level `call` (`transactNative`).
- **Security**: Router checks, try-catch, explicit casting, relaxed validation, emits `UpdateFailed`, `TransactionFailed`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`, `OrderUpdated`, `BalancesUpdated`, `OrderUpdatesComplete`, `OrderUpdateIncomplete`.
- **Optimization**: Normalized amounts, `maxIterations` in view functions, auto-generated historical data, direct struct assignments in `ccUpdate`.
