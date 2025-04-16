# **Premise**
A leverage trading platform for any token on the EVM, based on Dexhune-P.

# **General**
The system wraps around existing MFP contracts but makes adjustments to MFP-Agent - MFP-Listing and MFP-Liquidity to allow multiple "routers" in the form of  SS-IsolatedDriver (SSD) and SS-CrossDriver (CSD) which are standalone contracts alongside the existing MFP-Router. 

Other contract(s) include:  `Shockhopper`. 

## **SS-Listing**
Same as MFP-Listing but with a few key differences: 

### **Data** 
- Routers

Stores the valid SS-Router - SSD and CSD addresses that can call `transact` and `update`. Set oncw by the SSA.

- longPayout 

Each long payout transaction is formatted as: 

LongPayoutStruct

Maker Address: Router (address),
Recipient Address: (address),
Required:  (`TOKEN-0`),
Filled : (uint256), 
Order ID: (uint256),
Status: (uint8), 

"Required" specifies an amount in Token-0 that the order requires to be filled, unlike regular orders this does not take max/min price, just a pure amount to be sent. 

"Filled" in this case specifies how much of the "Required" has been paid out in partial settlement and therefore how much is left. 

- shortPayout 

Each short payout transaction is formatted as: 

ShortPayoutStruct

Maker Address: Router (address),
Recipient Address: (address),
Required:  (`TOKEN-1`),
Filled : (uint256), 
Order ID: (uint256),
Status: (uint8), 

- shortPayoutByIndex 

A mapping that tracks short payouts, is added to when new short payout orders are created. Can be queried by index. Is never cleared. 

- longPayoutByIndex

Same as "shortPayoutByIndex"

- userPayoutIDs 

A mapping that stores the IDs of payout transactions per address. Is added to when a new payout is created, can be queried by address. 

### **Functions**
- ssUpdate

Similar to update but creates a long or short payout entry. 



## **SS-Liquidity**
Similar to MFP-Liquidity but each "withdrawal" takes a 10% fee to the tax collector. Moreover; x liquidity providers are entitled to y fees, and vice versa. 


### **Data**
- Routers

Stores the valid SS-Router - SSD and CSD addresses that can call `transact` and `update`. 

- taxCollector 

Stores the Agent contract address, set by the SSA.

## **Shock Space Agent**
The `Shock Space Agent` (SSA) is responsible for creating new `SS-Listing` and `SS-Liquidity` contracts and recording their associated details. 

### **Functions**
- listToken 

Similar to equivalent on MFP but sets SSD and CSD addresses as routers. Along with setting tax collector address, tokens, listingID and router. 

- listNative

Similar to equivalent on MFP but with SS specific changes. 

- determineCollector (ownerOnly)

Determines the tax collector address that is passed to new liquidity contracts, can be reset.

- setIsolatedDriver 

Determines the SSD address, is used as one of the passed routers for new listings. In total 3 routers are set. 

- setCrossDriver

Same as setIsolatedDriver but for CSD address. 

- queryByAddress

A mapping that returns up to (maxIteration) index numbers that store a specific token(a or b) address. 
Each additional (maxIteration) indexes require a `step` to be queried. 

- queryByIndex

Returns the full details of an SSD or CSD validation Index slot by its index number. 

- transferOwnership (ownerOnly)

Contract is ownable, ownership can be transferred.

### **Data**
- taxCollector 

Stores the address of the fee collector. 



## **SS-Router**
Same as the MFP-Router but can execute payout orders in SS-SettlementLibrary or SS-LiquidLibrary. 



## **SS-IsolatedDriver**
The shock Space drive is similar to an MFP-Listing and Router. It holds data about positions and executes position entry or exit via the SS-Listing and Liquidity which it validates from the agent. 

### **Data** 
- agent 

Stores the address of the SSA where listings are validated before position entry. 

- historicalInterest 

Stores all older IO (open interest) entries + time/date stamp,  is added-to after every position entry or close.
 
`IO` is just all margin in shorts vs longs at any particular point in time. Stored as; `uint256, uint256`. (Short IO, Long IO). 

- historicalInterestHeight

Stores the total number of historical interest entries.

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
- Position ID 
- Listing Address 

Note : split position data into (5) prep&execute functions. Split user params into (2) prep functions. 

User only provides; Listing Address - Entry Price - Initial Margin - Excess Margin - leverage - Stop Loss Price and Take Profit Price. 


The `entry price` is a price stated by the caller. If an unexecuted position is cancelled before the entry price is reached it loses to fees. 

The caller can state `market` as their entry price, this executes their position immediately at the current price. 

If "," is used in the stated entry price, this implies a range order. The position will only execute within the `min` and `max` prices. E.g; `900000000000000000, 1200000000000000000`. 



`Initial Margin` is the amount the user initially put down in real `Token-1`. 



`Taxed Margin` is the user`s initial margin after fees, and is held by the contract in yBalance. 


This is calculated as; 

`Initial Margin - (Initial Margin / 100 * fee percent)`



`Excess Margin` is any additional amount added to a position which acts as a buffer on the position. 

`Excess Margin` cannot exceed `Leverage Amount` else the position will not be created. 



`Leverage` is a multiple of Paper assets that the user has borrowed. The number stored here represents how much the Initial margin is multiplied by to achieve the `leverage amount`. 

Example; if a user has an initial margin of 25 `Token-1` and a leverage of `5`, then their leverage amount is 125. 

The maximum leverage is 100.

The minimum leverage is 2. 


Both longs and shorts get credited as; 

`Initial Margin * leverage = Leverage amount`


 

`Initial Loan` for longs is; 

Leverage amount / entry price 

Initial loan on longs is the `TOKEN-1` equivalent of the leveraged amount, calculated at the entry price. 



`Liquidation Price` on longs is acquired as; 

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



`Position ID` is a fixed incremental number given to each order. Is queryable. Also called "index". 



`Initial Loan` on Shorts is; 

`Leverage amount * entry price` 

Initial loan on shorts is the `Token-0` equivalent of the leveraged amount, calculated at the entry price. 



Liquidation Price on shorts is calculated as; 

```
(excess margin + taxed margin) / leverage amount = margin ratio 

Entry price + margin ratio = liquidation price 
```

An active short position is closed when current price is above the liquidation price. 



On Shorts; stop Loss price must be greater than entry price, while Take Profit must be less than entry price. 



`Price-at-Entry` for shorts is actionable the same as on longs. 

`Listing Address` - `Token Address` and `Liquidity Address` are stored for closing the position. 


### **Functions**
- enterLong

Entering a long position deducts a stated `Initial Margin` amount in `Token-1` from the user's address. Long positions record a leveraged amount in `Token-1` which in the SSD's positions database. 

Longs take a fee calculated as; 

`Leverage - 1 = fee percent`

This represents the percent of the initial margin that is taken as fees once the position is opened. Long fees get added to the `xFees` balance in the Liquidity contract once the position is made. 



- cancelPosition 

If a position's Status-1 is `false` this allows the user to cancel it and retrieve their taxed margin. Creates a payout order to settle the user their taxed margin, can be settled with yBalance or yLiquid (longs), xBalance or xLiquid (shorts).  

Requires position ID. 

Both long and short positions share the same order ID scheme. 


- closeLongPosition 

Closes the user`s long position with profit or loss. Leverage amount is completely erased once payout is calculated. 

Calculates payout as; 

`(taxed margin + excess margin + Leverage amount) / current price) - initial Loan`

If a user`s payout is `0` or less, then this pays nothing and only closes the position.

Requires position ID. 

 

Creates a unique order that instructs the contract to pay the user from xBalance or xLiquid. This is effected using `settleOrders` or `settleLiquid`. 

Their pending settlement is in `TOKEN-0`. 



- enterShort 

A Short position is similar to a long position but each Short entry is billed `TOKEN-0` and settled Paper `TOKEN-0`. 

Short fees get added to the yFees balance on the Liquidity contract. 

- closeShortPosition

Similar to `closeLongPosition` but deals with shorts and yBalance or yLiquid. 

Closes the user`s short position with profit or loss. 

Calculates payout as; 

`(entry price - exit price) * initial margin * leverage + (taxed margin + excess margin) * current price`

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

Allows the user to update their stop loss price, changes the existing stop loss, can only be executed by the position maker.  

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

- forceExecution 
Used to execute positions. 

Checks up to (100) pending position entries and changes their status if true. 
Checks up to (100) pending "stop loss" for active positions and closes the positions if true. 
Checks up to (100) pending "take profit" for active positions and closes the positions if true. 
Checks up to (100) pending "liquidations" for active positions and closes the positions if true. 

Has a maximum of (100) checks/updates in total per transaction, triggered by every position entry - exit or addMargin. 

Requires listing address, functions that call ForceExecution pass listing address param. 


- PositionsByTypeView

A function tied to a mapping that returns up to (maxIteraion) index numbers for positions with a specific type (long or short). 
Requires `step` to return the subsequent (maxIteration) indexes. 

- PositionsByAddressView

A function tied to a mapping that returns up to (maxIteration) index numbers for positions with a specific address. 
Requires `step` to return the subsequent (maxIteration) indexes. 

- PositionByIndex 

A mapping that returns the full details of a position by its index number / ID.
Note that indexes are not localized to each maker address and instead are generalized for the entire system. 


- queryInterest 

Returns up to (maxIteration) older IO (open interest) entries + their time/date stamp.  
Requires `step` to return the prior (maxIteration) indexes. 

- setAgent (ownerOnly) 

Determines the Agent address. 



## **SS-CrossDriver**
This contract is functionally similar to SSD but allows `cross margin`. 

### **Coordination**
Each CSD creates its positions with a "totalMargin" entry for a user setting or updating a position, or updates other positions' total margins when `forceExecution` is called. 

When a user enters a position; their excess margin record is added to a total margin storage for a given token.

Positions must be executed to add margin. 

If a user's position is liquidated or cancelled or closed; this removes an amount from the total margin equal to the excess margin of the closed/liquidated position. 

Each total margin record is indexed per maker and token. 

# **Functions**
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

`((taxed margin + total margin + Leverage amount) / current price) - initial Loan`




- closeShortPosition 

Functionally similar to SSD but calculates position close as;

`(entry price - exit price) * initial margin * leverage + (taxed margin + total margin) * current price`




- addExcessMargin 

Similar to SSD but adds to total margin. 
Can be used to add margin before positions are created. Requires token address. 



- pullMargin

Deducts a stated amount of total margin the user has in a stated token. 



- forceExecution 

Similar to SSD but updates liquidation prices based on adjusted total margin. 
Is limited to (50) entries per call. 


- makerTokenMarginView

A function tied to mapping (makerTokenMargin) that returns the total margin of a maker address to a given token (if any). 


- makerMarginIndex

A mapping that returns (maxIterations) of index numbers that store total margin entries for a given address. 



# **Data**
Stores the same data as the SSD with some exceptions; 


- MakerTotalMargin 

Stores the total margin details of every active address as; `(address), (token address), (total margin)`. 

Note : gaps in indexes are not closed when total margin is "0", rather they are permanently mapped to a given maker and token. Will be reused if the user opens new positions. 

- Agent 

Stores the Agent address. 



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



# **Examples*
E1 : Adding excess margin to total margin can strengthen an order and push liquidation price further away. 

E2 : Single liquidation or close on CSD can cause a cascade of liquidations if not managed properly. 

E3 : If the price goes down there will be more `Token-1` in the yBalance or yLiquid, all successful shorts are paid out in `Token-1`. 
Whereas if the price goes up there will be more `TOKEN-1` in xBalance or xLiquid, all successful longs are paid out in `TOKEN-1`.

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

- TOKEN-1 Coordination is required for situations where the user wants to long multiple tokens with cross margin and use a common total margin unit to strengthen their positions.
