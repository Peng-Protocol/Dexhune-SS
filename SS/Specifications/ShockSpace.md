# **Premise**
A leverage trading platform for any token on the EVM, based on Dexhune-P. 

# **General**
The system is made up of (6) contracts; `Shock Space Agent` (SSA) - `Shock Space Drive` (SSD) - `Shock Space Liquidity` (SSL) - `Cross Space Drive` (CSD) - `Cross Space Coordinator` (CSC) and `Shockhopper`. 

## **Paper Tokens**
Paper tokens are standard ERC-20s built into each SSD with some custom functions. 
Each SSD creates a pair of `STABLE` and `Token-1` Papers. 
 
Papers cannot be transfered, or transfered from, they can only be used to create or close positions on the respective listing. 

### **Functions**
- balanceOf 

Returns the Paper balance of a target address. 

- decimals 

Returns the Paper's decimals (should be the same number as the `real` token). 

## **Shock Space Drive**
The shock Space drive is similar to `Pairing Foundry`, with a few added functions.

### **Data** 
- liquidityAddress 

Stores the address of the Liquidity contract, set by the SSA. 

- xBalance 

Stores the listing's `STABLE` balance, is updated by each order. 

- yBalance 

Stores the listing's `Token-1` balance, is updated by each order.

- TOKEN 

Stores the `Token-1` contract address, set by the SSA.  

- STABLE 

Stores the `STABLE` contract address, set by the SSA. 

- Agent 

Stores the Agent contract address, set by the SSA. 

- taxCollector 

Stores the address of the tax collector. Set by the SSA. 

- Name 

Stores the ticker of `Token-1` + `(Isolated)`. 

Example; 

`USD - TKN (Isolated)`. 

Set by the SSA. 

- Price 

Stores the latest price, is updated after every order - settlement - position entry or close. 

- HistoricalPrice

Stores all older prices + time/date stamp,  is added-to after every order - settlement - position entry or close. 

- historicalMarketCap 

Stores all older mcap + time/date stamp, is added-to after every order - settlement - position entry or close. 

- historicalSellVolume
  
Same as on `Pairing Foundry`

- historicalBuyVolume
  
Same as on `Pairing Foundry`

- Interest 

Stores all older IO (open interest) entries + time/date stamp,  is added-to after every order - settlement - position entry or close.
 
`IO` is just all margin in shorts vs longs at any particular point in time. Stored as; `uint256, uint256`. (Short IO, Long IO). 

- positionDetails 

Each position has the following details; 

- Maker Address 
- Entry Price 
- Initial Margin 
- Taxed Margin
- Excess Margin 
- Leverage 
- Leverage amount 
- Initial Loan
- Liquidation Price 
- Stop Loss Price 
- Take Profit Price 
- Position Type
- Status-1
- Status-2
- Close Price
- Price at Entry 
- Margin Price
- Index 
- Position ID 

User only provides; Entry Price - Initial Margin - Excess Margin - leverage - Stop Loss Price and Take Profit Price. 



The `entry price` is a price stated by the caller. If an unexecuted position is cancelled before the entry price is reached it loses to fees. 

The caller can state `market` as their entry price, this executes their position immediately at the current price. 

If "," is used in the stated entry price, this implies a range order. The position will only execute within the `min` and `max` prices. E.g; `900000000000000000, 1200000000000000000`. 



`Initial Margin` is the amount the user initially put down in real `Token-1`. 



`Taxed Margin` is the user`s initial margin after fees, and is held by the contract in yBalance. 


This is calculated as; 

`Initial Margin - (Initial Margin / 100 * fee percent)`



`Excess Margin` is any additional amount added to a position which acts as a buffer on the position. 



`Leverage` is a multiple of Paper assets that the user has borrowed. The number stored here represents how much the Initial margin is multiplied by to achieve the `leverage amount`. 

Example; if a user has an initial margin of 25 `Token-1` and a leverage of `5`, then their leverage amount is 125. 

The maximum leverage is 100.

The minimum leverage is 2. 


Each long is settled as; 

`Initial Margin * leverage = Leverage amount`


 

`Initial Loan` is; 

Leverage amount * entry price 

Initial loan is the `STABLE` equivalent of the leveraged amount, calculated at the entry price. 



`Liquidation Price` is an estimate of when the position's total value will hit `0`. 

This is acquired as; 

```
(excess margin + taxed margin) / leverage amount = margin ratio 

Entry price - margin ratio = liquidation price 
```

When current price is below an active long position`s liquidation price; the position is closed with full loss. 



Leverage amount  Limit is;

`101 - Leverage = Limit percent`.

A user's leverage amount cannot exceed the limit percent relative to the listing's `Token-1` Liquidity. 

Example; yLiquid is 200, the user`s leverage is 20, thus their limit is; 

```
101 - 20 = 81 

200 / 100 * 81 = 162 
```

If the stated leverage and initial margin produce a leverage amount greater than the calculated limit then the position is rejected. 



`Stop Loss price` defines a price at which the user`s position is automatically closed. 
This is set by the user. 
This is triggered by new orders or positions. 

Is optional. 

On longs, will only execute if the entry price is above the stop loss price. 

Must be lower than entry. 



`Take Profit price` is similar to `Stop Loss price`. 

Is optional also. 

On longs, will only execute if the entry price is below the take profit price. 

Must be greater than entry price. 



`Position Type` is `Long` or `Short`, is used for indexing. 



`Status-1` Determines if the position can be closed for profit/loss or cancelled. 
Position status is set to `false` when created, 
New orders or positions change the status of the position depending on the `Price-at-entry`. 



`Status-2` determines if a position has been cancelled or closed or is still open.  



`Close Price` stores the price at which a position was closed. 
The details of all closed or cancelled positions are stored indefinitely. 



`Price-at-Entry` is the current price at the time of position creation and is used to determine when the position status can be set to `true`. 

If Price-at-Entry > Entry Price, then status is true if current price =< entry price 

Whereas if Price-at-Entry < Entry Price, then status is true if current price => entry price 

Example-A ; if price is `4.80` at the time of setting the position but entry price is set to `5`, then the position won't execute until price is either `5` or more. 

Example-B ; if price is `5.20` at the time of setting the position but entry price is set to `5`, then the position won`t execute until price is either `5` or less. 

 

`Margin Price` is the price at the time the position was created and is used for `STABLE Cross` positions. 



`Index` is a number assigned to each position (both long and short) that the user has, this is a generalized indexing scheme for all addresses which is required for cancelling or closing a position. 



`Position ID` is a fixed incremental number given to each order. Is queryable. 



`Initial Loan` on Shorts is; 

`Leverage amount / entry pric` 

Initial loan is the `Token-1` equivalent of the leveraged amount, calculated at the entry price. 



Liquidation Price on shorts is calculated as; 

```
(excess margin + taxed margin) / leverage amount = margin ratio 

Entry price + margin ratio = liquidation price 
```

An active short position is closed when current price is above the liquidation price. 



On Shorts; atop Loss price must be greater than entry price, while Take Profit must be less than entry price. 



`Price-at-Entry` for shorts is actionable the same as on longs. 




### **Functions**
- enterLong

Entering a long position deducts a stated `Initial Margin` amount in `Token-1` from the user's address. Long positions pay out a leveraged amount in Paper `Token-1` which is minted by the contract. 

Longs take a fee calculated as; 

`Leverage - 1 = fee percent`

This represents the percent of the initial margin that is taken as fees once the position is opened. Long fees get added to the `xFees` balance in the Liquidity contract once the position is made. 



- cancelPosition 

If a position's Status-1 is `false` this allows the user to cancel it and retrieve their taxed margin. Creates a custom order to settle the user their taxed margin, can be settled with yBalance or yLiquid (longs), xBalance or xLiquid (shorts).  

Requires position ID. 

Both long and short positions share the same order ID scheme. 



- closeLongPosition 

Closes the user`s long position with profit or loss. Leverage amount is completely erased once payout is calculated. 

Calculates payout as; 

`(taxed margin + excess margin + Leverage amount) * current price) - initial Loan`

If a user`s payout is `0` or less, then this pays nothing and only closes the position.

Requires position ID. 

 

Creates a unique order that instructs the contract to pay the user from xBalance or xLiquid. This is effected using `settleOrders` or `settleLiquid`. 

Their pending settlement is in `STABLE`. 



- enterShort 

A Short position is similar to a long position but each Short entry is billed `STABLE` and settled Paper `STABLE`. 

Short fees get added to the yFees balance on the Liquidity contract. 

- closeShortPosition

Similar to `closeLongPosition` but deals with shorts and yBalance or yLiquid. 

Closes the user`s short position with profit or loss. 

Calculates payout as; 

`(entry price - exit price) * initial margin * leverage + (taxed margin + excess margin) / current price`

User is settled from yBalance or yLiquid using `settleOrders` or `settleLiquid`. 

Their pending settlement is in `Token-1`. 

Requires position ID. 



- closeAllShort 

Closes up to (100) active short positions a caller may have. 

- cancelAllShort

Cancels up to (100) pending short positions a caller may have. 

- closeAllLongs 

Same as `closeAllShorts` but closes longs. 

- cancelAllLong

Same as `cancelAllShorts` but for longs. 



- updateSL

Allows the user to update their stop loss price, changes the existing stop loss, can only be executed by the order maker.  

New SL cannot be greater than current price on longs, or lower than current price on shorts. 

Requires position ID, must be an active position. 

- updateTP

Similar to `updateSL` but for take profit price. 

New TP cannot be lesser than entry price on longs, or greater than entry price on shorts. 



- addExcessMargin 

Deducts a stated amount from the caller (must be the corresponding asset of a position)
Increases a target position`s excess margin by the deducted amount. 
Requires; position ID. 
New excess margin is added to respective x or y balances. 
Can be called by anyone, not necessarily the maker. 

- createBuyOrder 

Same as on `PairingFoundry`.



- createSellOrder 

Same as on `PairingFoundry`.



- settleOrders 

Similar to function on `PairingFoundry`.

But Triggers `forceExecution`. 



- forceExecution 

Used to execute positions. 

Checks up to (100) pending position entries and changes their status if true. 
Checks up to (100) pending `stop loss` for active positions and closes the positions if true. 
Checks up to (100) pending `take profit` for active positions and closes the positions if true. 
Checks up to (100) pending `liquidations` for active positions and closes the positions if true. 

Has a maximum of (100) checks/updates in total per transaction. 



- clearSingleOrder 

Same as on `PairingFoundry`.

- clearOrders 

Same as on `PairingFoundry`.

- queryPositionsByType 

Returns up to (1000) index numbers for positions with a specific type (long or short). 
Requires `step` to return the subsequent (1000) indexes. 

- queryPositionsByAddress 

Returns up to (1000) index numbers for positions with a specific address. 
Requires `step` to return the subsequent (1000) indexes. 

- queryByLeverage 

Returns up to (1000) index numbers for positions with a specific leverage number. 
Requires `step` to return the subsequent (1000) indexes. 

- queryPositionByIndex 

Returns the full details of a position by its index number.
Note that indexes are not localized to each maker address and instead are generalized for the entire system. 

- queryPositionByID 

Returns the full details of a position by its position ID.

- queryOrderByAddress 

Returns up to (1000) index numbers for orders with a specific address. 
Requires `step` to return the subsequent (1000) indexes. 

- queryOrderByType 

Returns up to (1000) index numbers for orders with a specific type (buy or sell). 
Requires `step` to return the subsequent (1000) indexes. 

- queryOrderByIndex 

Returns the full details of an order by its index number. 

- queryOrderByID 

Same as on `PairingFoundry`.

- queryHistoricalPrice 

Same as on `PairingFoundry`.

- queryInterest 

Returns up to (1000) older IO (open interest) entries + their time/date stamp.  
Requires `step` to return the prior (1000) indexes. 


## **Shock Space Liquidity**
This contract stores x and y liquid positions, similar to Liquidity contracts on `Pairing Foundry`. 

Notable difference between SSD Liquidity and `Pairing Foundry` Liquidity is the fee + volume storages. 

SSD LPs have (4) distinct fee and volume storages; 

xFees : (uint256)
yFees : (uint256)
xVolume : (uint256)
yVolume : (uint256) 

`xFees` store all fees accrued from sells and long positions. While `yFees` store all fees from buys and short positions. 

xFees can only be claimed by `STABLE` Liquidity providers, and yFees can only be claimed by `Token-1` Liquidity providers. 

`xVolume` stores all volume from buys - short entry margin and long payouts. 

`yVolume` stores all volume from sells - long entry margin and short payouts. 

xVolume tracks `STABLE` on SSDs, or [TOKEN-0] in the case of CSDs. 

While yVolume tracks `Token-1` on SSDs, or [TOKEN-1] in the case of CSDs. 



In addition to other details, SSD/CSD Liquidity slots have a `Fee-at-Deposit` entry, this stores the `xFees` or `yFees` value at the time of deposit. 



`claimFees` on SSD uses a slightly different formula from `PairingFoundry`; 

When someone calls `claimFees` the contract uses the following formula; 

```
current (x or y) fees - Fee-at-Deposit = contributed fees  

user Liquidity / total Liquidity = Liquidity contribution 

contributed fees * liquidity contribution = output amount 
```

Output amount cannot be greater than available fees, if greater then only pay available fees. 

Once a user claims fees, their `Fee-at-Deposit` is reset to current (x or y) fees. 

### **Functions**
- depositX

Same as on `PairingFoundry`.

- depositY

Same as on `PairingFoundry`.

- withdrawX 

Same as on `PairingFoundry`.

- withdrawY 

Same as on `PairingFoundry`.

- claimFees 

Similar to function on `PairingFoundry` but with new formula , this also takes a 10% fee on withdrawal and sends it to the `taxCollector`. 

- transferLiquidity 

Same as on `PairingFoundry`.

- transact (CSD or SSD only) 

Similar to  function on `PairingFoundry` but allowed caller is the CSD or SSD. 

- update (CSD or SSD only)

Similar to  function on `PairingFoundry` but allowed caller is the CSD or SSD. 

- queryByIndex 

Returns the full details of a Liquidity slot by its index number. 

- queryByAddress 

Returns up to (1000) index numbers for slots with a specific address. 
Requires `step` to return the subsequent (1000) indexes. 

- queryByType

Returns up to (1000) index numbers for slots with a specific type (STABLE or TOKEN). 
Requires `step` to return the subsequent (1000) indexes. 

### **Data**
- CSD/SSD 

Stores the address of the CSD or SSD, set by the SSA at deployment. 

- xLiquid

Stores the liquidity's `STABLE` amount. 

- yLiquid

Stores the liquidity's `Token-1` amount.

- xFees 

Stores the liquidity's `STABLE` fees value. 
 
- yFees 

Stores the liquidity's `Token-1` fees value. 

- xVolume 

Stores the liquidity's `STABLE` volume value. 

- yVolume 

Stores the liquidity's `Token-1` volume value. 

- TOKEN 

Stores the `Token-1` contract address, set by the SSA. 

- STABLE 

Stores the `STABLE` contract address, set by the SSA. 

- Agent 

Stores the Agent contract address, set by the SSA.

- taxCollector 
Stores the Agent contract address, set by the SSA.



## **Cross Space Drive**
This contract is functionally similar to SSD but allows pairing any token to any other and uses `cross margin`. 

Each CSD is created with [TOKEN-0] in place of `STABLE`, all functions previously ascribed to `STABLE` are now assigned to [TOKEN-0]. 

### **Coordination**
Each CSD first sends data of each position to the cross space Coordinator, this updates the total margin of a user setting or updating a position, or updates other positions' total margins when `forceExecution` is called. 

### **Stable Coordination**
CSDs with `STABLE` as [TOKEN-0] are `STABLE Cross`, they store and update total margin in `STABLE` value. 

These positions store the `margin price`, which is the price at the time the position was created and is required for closing or cancelling the position. 



These positions convert the [TOKEN-1] excess margin for longs as; 


`Excess Margin * Margin Price = Added Margin`


The `Added Margin` is how much the `STABLE Cross` `Total Margin` is increased by. 

Whereas with [TOKEN-0] on shorts, excess margin is already in `STABLE`. 



When these long positions are cancelled or closed, the deducted `Excess Margin` is first converted back to `TOKEN-1` as; 


`Excess Margin / Margin Price = Deducted Margin`

The `Excess Margin` in the `CloseLongPosition` formula is replaced by `Deducted Margin`. 



Therefore all `STABLE Cross` positions share a common total margin unit. 


### **Functions**
Most functions are identical to SSD with a few exceptions; 

- enterLong 

Similar to SSD but calculates liquidation price as; 

```
(total margin + taxed margin) / leverage amount = margin ratio 

Entry price - margin ratio = liquidation price 
```


- enterShort 

Similar to SSD but calculates liquidation price as; 

```
(total margin + taxed margin) / leverage amount = margin ratio 

Entry price + margin ratio = liquidation price 
```

- closeLongPosition 

This is functionally similar to the SSD, but calculates position close as; 

`((taxed margin + total margin + Leverage amount) * current price) - initial Loan`




- closeShortPosition 

Functionally similar to SSD but calculates position close as;

`(entry price - exit price) * initial margin * leverage + (taxed margin + total margin) / current price`




- addExcessMargin 

Similar to SSD but adds to total margin. 
Can be used to add margin before positions are created.



- pullMargin

Deducts a stated amount of total margin the user has in a stated token. 



- forceExecution 

Similar to SSD but updates liquidation prices based on adjusted total margin. 
Is limited to (50) entries per call. 

- claimFees

Similar to SSD but takes a 10% fee on withdrawal and sends it to the `collector`. 


### **Data**
Stores the same data as the SSD with some exceptions; 

- taxCollector 

Stores the address where `claimFees` fees are sent to, set by the SSA. 

- coordinator 

Stores the address of the cross space Coordinator, set by the SSA. 

- TOKEN-1

Stores the address of the second listed token, used for long positions - yBalance and yLiquid. 

- TOKEN-0

Stores the address of the first listed token, used for short positions - xBalance and xLiquid. 

- Name 

Stores the tickers of the [TOKEN-0] and [TOKEN-1] + "(Cross)". 

Example; 

`CNI - TKN (Cross)`. 

Set by the SSA. 



## **Cross Space Coordinator**
The CSC stores the data of various user's `total margin` across all CSDs. 

When a user enters a long position; their excess margin is recorded in a total margin storage for `TOKEN-1` in the CSC. 

Whereas if a user enters a short position; their excess margin is recorded to the total margin storage for `TOKEN-0`. 

Positions must be executed to add margin. 

If a user`s position is liquidated or closed; this removes an amount from the total margin equal to the excess margin of the closed/liquidated position. 


### **Functions**
- setAgent (ownerOnly) 

Determines the Agent address. 

- queryTotalMarginByAddress 

Returns up to (1000) index numbers for total margin entries for a given maker address. 
Requires a `step` to query an additional (1000) indexes. 

- queryTotalMarginByIndex 

Returns the full details of a total margin entry based on index number. 

- queryTotalMarginByToken 

Returns up to (1000) index numbers for total margin entries for a given token. 
Requires a `step` to query an additional (1000) indexes. 

- queryTotalMarginByID

Returns the full details of a total margin entry based on ID number. 

- queryAddressID

Returns up to (1000) ID numbers for total margin entries for a given maker address. 
Requires a `step` to query an additional (1000) IDs. 

### **Data**
- totalMargin 

Stores the total margin details of every active address as; `(address), (token address), (total margin)`. 

Used for CSDs whose [TOKEN-0] is not `STABLE`.

- totalSTABLEMargin

Stores the total margin details of every address for `STABLE Cross` as; `(address), (token address), (total margin)`.  

Used for CSDs whose [TOKEN-0] is `STABLE`.

- Agent 
Stores the Agent address. 



## **Shock Space Agent**
The `Shock Space Agent` (SSA) is responsible for creating new `Shock Space Drives` (SSDs) - `Cross Space Drives` (CSDs) and recording their associated details. 

### **Functions**
- deploySSD 

Creates a new SSD contract and accompanying SSL using a stated token contract address.
Stores the token contract address and the new SSD + SSL address in the SSD/CSD `Listing Validation`. 
`STABLE` cannot be listed.

- deployCSD

Creates a new CSD contract and accompanying SSL using stated token addresses for Token-0 and Token-1. 
Stores the token contract addresses and the new CSD + SSL addresses in the SSD/CSD `Listing Validation`. 
`STABLE` cannot be listed.

- setStable (ownerOnly)

Determines the base token address. 

- setCollector (ownerOnly)

Determines the collector address, is set as the deployer upon deployment. 

- setCoordinator (ownerOnly) 

Determines the address of the CSD coordinator contract. 

- queryByAddress

Returns up to (1000) index numbers that store a specific token address - Liquidity address or SSD/CSD address. 
Each additional (1000) indexes require a `step` to be queried. 

- queryByIndex

Returns the full details of an SSD or CSD validation Index slot by its index number. 

- queryByType 

Returns up to (1000) index numbers that store a specific type of listing (SSD or CSD). 
Each additional (1000) indexes require a `step` to be queried. 

- withdraw (ownerOnly)

Allows the caller to withdraw all `NATIVE` in the contract. 

- transferOwnership (ownerOnly)

Contract is ownable, ownership can be transferred.

### **Data**
- owner 

Stores the address of the owner. 

- stable 

Stores the address of the base token. 

- taxCollector 

Stores the address of the fee collector. 

- coordinator 

Stores the coordinator address. 

-  listingValidation 

Stores the SSD/CSD address + Liquidity address for each listing, stores as; `(address), (address), SSD or CSD, xBalance, yBalance, xLiquid, yLiquid`. 

(Note; Balance and liquid data on the SSA is updated after every order and settlement by the SSD/CSD)




## **Shockhopper**
Based on `Multihopper`.

In addition to existing Multihopper `stalledHops`, the Shockhopper stores the details of a stalled position entry or exit transaction in relation to its stalled multihop and can be later continued or cancelled. 

### **Functions**
- All Relevant multihop functions. 

- entryExitHop 

Similar to `Hop` from the original `Multihopper`, but each start or end point in the hop can be a shock space position entry or exit. 

SSD positions require; 

entry (bool), this determines if the hop will end with a position entry or start with a position close. 

positionIndex, determines the index number of the user`s position during a position exit hop. 

positionType, determines the type of position being opened or closed. 

amount, determines the token amount deducted during a position entry hop, whatever settlement is acquired before the final listing on the route is reached; is used to create the position. 

ratio, determines what percent of the settled amount is used as initial margin vs excess margin. 

entryPrice, determines the entry price for the position. 

Leverage, determines the leverage used during position entry. 

SL/TP, entered as `uint256, uint256`, determines the stop loss and take profit prices. 



Each hop functions as either;

Order1 + settle >> Order2 + settle  >> Position Entry 

or 

Position Exit >> Order1 + settle >> Order2 + settle 



The Shock Space listing is entered as the first or last listing in the hop, this still only accommodates up to (4) listings. 

All prior requirements in Multihopper are carried over for each listing in the route. 



- setAgent 

Determines the Shock Space Agent address. All hop functions ensure that the stated listing is stored on the Agent before proceeding. 



### **Data**
- Agent 

Stores the Shock Space Agent address. 



# **Examples**
E1 : Adding excess margin to total margin can strengthen an order and push liquidation price further away. 

E2 : Single liquidation or close on CSD can cause a cascade of liquidations if not managed properly. 

E3 : If the price goes down there will be more `Token-1` in the yBalance or yLiquid, all successful shorts are paid out in `Token-1`. 
Whereas if the price goes up there will be more `STABLE` in xBalance or xLiquid, all successful longs are paid out in `STABLE`.

E4 : If a long gets liquidated their taxed margin remains in yBalance and can be used to settle victorious shorts. Vice versa with Shorts and xBalance. 

E5 : Successful Long closes behave like sells, while successful short closes behave like buys. 
Meaning each successful position makes it less likely that other positions of the same type will succeed. 

E6 : Given the leverage amount limit, no user can drop the price below their own liquidation. 

# **Notes**
- Ensure that all data storages are properly tagged. 

- Nearest number approximation applies for tokens with few or no decimals. 

- Price-at-Entry is necessary to ensure that users can place positions at prices that are currently out of range but are expected to be in range in the future. 
If an entry never comes into range then the position remains indefinitely unexecuted.

- If an initial margin is too low to take fees on then the order fails. 

- Stable Coordination is required for situations where the user wants to long multiple tokens with cross margin and use a common total margin unit to strengthen their positions.
