# **Premise**
A frontend application for interacting with Shock Space and Shockhopper Contracts.

# **General**
The frontend is made up of (3) pages; 
- Leveraged Multihop Interface 
- Liquidity Menu  
- Listing Menu 

## **Page 1 : Leveraged Multihop Interface**
1a ; Wallet Connect 

You know how this goes. 

**1b ; Dexhune Logo**

Is DXH logo. 

**1c ; Shock Space Multihop Menu**

1d to 1k.

**1d ; Token-A Ticker or selected position**

Allows (2) modes; the first prepares the frontend for a regular multihop.  

While the second prepares the frontend for a position "exit into hop" using a position selected for closing in 1k "close position". 


The expected output token for the position is used as the first token on the route - the frontend attempts to find a ShockSpace listing that has the output token. 
For longs this is Token-0, while shorts will expect Token-1 if closed. 

The output token is used for subsequent orders towards arriving at a target token set in "Token-B Ticker or selected position".


The frontend searches the shock space agent for listings to route through. 


**1e ; Token-A amount or selected position**

For the transacted amount of the token in "Token-A Ticker or selected position". Defaults to the position output if a position is selected. 

Calculates initial and excess margin limit for position entry, position cannot be created if the expected leverage amount and excess margin exceed the limit(s). 


**1f ; Switch Button**

Similar to 'multihopper', but does not work if a position is selected for close, returns "Can't do that!". 

...

**1g ; Order Options Button** 

Similar to "Slippage Button" in 'multihopper', but also has settings for "Stop Loss" - "Take Profit" - "Margin Ratio" - leverage slider and "Entry Price". 

Both Stop Loss and Take Profit start out blank, but automatically highlight in red if the stated SL/TP price is too high or too low relative to entry price. 

"Margin Ratio" is set to "40" by default, this determines how much of the swapped amount will be used as initial margin vs excess margin. 

This calculates; 

```
Expected Margin Amount / 100 * margin ratio = initial margin 

Expected Margin Amount / 100 * (100 - margin ratio) = excess margin
```

(Note; "Expected Margin Amount" is the estimated output of Multihops in a "hop into entry" before the final listing on the route is reached, which is then used as initial margin/excess margin). 


Default entry price is always equal to the impact price of the user's margin. 

For longs this is calculated as; 

```
Margin + [TOKEN] balance = [TOKEN] impact 

[STABLE] balance / [TOKEN] impact = Entry Price 
```

While for shorts; 

```
Margin + [STABLE] balance = [STABLE] impact 

[STABLE] impact / [TOKEN] balance = Entry Price 
```

However, this field allows the user to set any price as entry. 
Due to the sensitivity of this field, price data for it is updated every 5 seconds. If no custom price is set then the default entry price is adjusted to match the updated impact price. 
If custom data is cleared then this calculates default entry again. 

- Market Price Toggle 

Sets the position's entry price as "market". 

- Price Range Toggle

Presents fields for "min price" and "max price", allows the order to use price ranges. 
Turns off "Market Price" if already toggled. 
Returns to regular "limit price" if untoggled. 


- Leverage Slider 

Determines how much Leverage the position will have, starts at "1" by default, this initiates a regular order. 


**1h ; Token-B Ticker or selected position** 

Similar to "Token-A Ticker or selected position" but allows (4) additional modes; 
Mode-1 prepares the frontend to execute a "hop into entry" using the token in "Token-A Ticker or selected position" and amount in "Token-A amount or selected position", toggled by 1i "entry mode".   
Additional position details are added in "Leverage Slider" and "Order Options". 
This requires a token that has a valid Shock Space listing. 

Mode-2 prepares the frontend for an "exit into hop" depending on if a position is selected or not (this is mode-1 in "Token-A Ticker or selected position"). 

Mode-3 is a regular hop assuming no position is selected in "Token-A Ticker or selected position" via 1k "close position". 

Mode-4 prepares the frontend for an "exit into hop into entry" depending on if a position is selected or not, this exits an existing position and opens a new one using details in "Leverage Slider" and "Order Options". 

The expected input token for position entry is used in Mode-1 the frontend attempts to find a shock space listing that has the input token. 
For longs this is Token-1, while shorts will expect Token-0 if the position is to be made. 


**1i ; Token-B Amount or selected position** 

Same as "Token-A Amount or selected position". 

- Entry mode toggle 

Titled "Entry", displayed inside "Token-B Amount or selected position" at its right end. 
Determines if the transaction will carry out a "hop + entry" or regular multihop. 
Can only be toggled if there is no position selected in 1k "close position", is grayed out otherwise. 

**1j ; Swap Button**

Similar to the same button on Multihopper but executes; "hop + entry" or "exit + hop" or "exit + hop + entry" or a regular multihop using shock space listings. 

**1k ; Order Summary**

Can be opened even if no positions are active. 

Similar to similar modal on Multihopper but displays every active position the user has, along with some additional data; 

- Force Execution Button 

Has a "Gift box" symbol, pushes "forceExecution" on the SSD/CSD. 
If executed will present a pop-up saying "Thanks for clicking me! You just helped execute any pending positions! Contact the Dexhune team for your reward!" 


- **Reset SL/TP**

Is grayed out if the position status is "unexecuted". 
Displayed directly above the positions panel, is a text button that says "SL/TP". if clicked displays a closeable menu as follows; 

- Stop Loss Price 

A field for stating "Stop Loss Price".
Has a percentage slider that sets SL price to a negative percent of the entry price. 

Once a price is set the frontend calculates the actual loss percent. 

On longs this slider calculates; 

```
((taxed margin + excess margin + Leverage amount) * SL price) - initial Loan = output value 

(taxed margin + excess margin) * current price = relative initial value 

Output value / relative initial value * 100 - 100 = loss percent 
```

Frontend displays warning if 'loss percent' is greater than '99'; "loss cannot exceed 100%, your position will be liquidated". 

SL price cannot be greater than entry price on longs. 

Pushes updateSL with the stated price. 

While on shorts; 

```
(entry price - SL price) * initial margin * leverage + (taxed margin + excess margin) / current price = output value

(taxed margin + excess margin) / current price = relative initial value 

Output value / Relative initial value  * 100 - 100 = loss percent 
```


SL price cannot be lesser than entry price on shorts. 

Pushes updateSL with the stated details. 



- Take Profit Price 

A field for stating "Take Profit Price".

Uses the same formula for Stop Loss but must be greater than entry price on longs and less than entry on shorts. 

Pushes updateTP with the stated price. 


- **Simulate Position**

A button at the top of "Order Summary" that presents a closeable menu with the following; 

- Amount 

A field that allows the user to state their margin amount. 

- Ratio

A field that allows the user to state their margin ratio. 

- Total Margin 

A field that displays "optional" and another text under the field that reads; "only if the contract is cross margin". 
Allows the user to state their total margin prior to the position being created. 

- Leverage 

A field that allows the user to state their leverage. Cannot be above 100 or below 2. 

- Type 

A toggle that allows the user to determine if the position is a long or short. 

- Entry Price 

A field that allows the user to state their entry price. 

- Exit Price 

A field that allows the user to state their exit price. 

- Simulate Button 

Takes the above details and simulates the position till close, presents estimated profit or loss and liquidation price. 



- **Orders/Positions toggle**

Arranges entries with positions first or orders first, both positions and orders are displayed in "Order Summary". 

- Position Type 

Displayed in each position entry, shows the position type. 

- Status 

Displayed in each position entry, is either "Executed" or "Unexecuted". 

- Taxed Margin 

Displayed in each position entry, shows the position's taxed margin. 

- Excess Margin / Total Margin

Displayed in each position entry, shows the position's excess margin. 
Displays "Total Margin" for CSD listings. 

- Leverage 

Displayed in each position entry, shows the position's leverage. 

- Leverage Amount 

Displayed in each position entry, shows the position's leverage amount. 

- Initial Loan 

 Displayed in each position entry, shows the position's initial loan amount. 

- Stop Loss Price 

Displayed in each position entry, shows the position's stop loss price. 

- Take Profit Price 

Displayed in each position entry, shows the position's take profit price. 


- Profit/Loss

Calculates and displays a position's Profit/Loss amount and percent. 

Each long position calculates profit/loss (PnL) and PnL percent as; 

```
((taxed margin + excess margin + Leverage amount) * current price) - initial Loan = payout 

payout / ((taxed margin + excess margin) * current price) * 100 - 100  = PnL percent 

payout - ((taxed margin + excess margin) * current price) = PnL
```

While shorts; 

```
(entry price - exit price) * initial margin * leverage + (taxed margin + excess margin) / current price = payout 

payout / ((taxed margin + excess margin) / current price) * 100 - 100  = PnL percent 

payout - ((taxed margin + excess margin) / current price) = PnL
```

"PnL" on longs is displayed with the ticker symbol of [TOKEN-0], while on shorts is displayed with the ticker symbol of [TOKEN-1].

PnL amount is presented with "+" if the output is positive or "-" if the output is negative. Same with PnL percent but has a "%" symbol after the number. 


- **Add Margin Button** 

Displayed in each position entry, presents a closeable pop-up with an "amount" field and "add" button, allows the user to state an amount of token units in the position's token they want to add as excess or total margin. 
Pushes a transaction to add margin. 

If the contract is not approved, then this first pushes an approval transaction. Presents browser pop-up; "Amount not approved! Approve first!". 

If no positions are open, the "Add Margin" Button and "Total Margin" indicator are still displayed. "Add Margin" can be used for CSDs without an open position. 



- Close Position Button 

Is grayed out if the position status is "unexecuted". 
Displayed next to each position, allows the user to close an executed position with profit or loss. 

Presents a browser pop-up every time a position is closed that reads; "Thanks for playing!".  

- Cancel Position Button 

Is grayed out if the position status is "executed". 
Displayed next to each position, allows the user to cancel an unexecuted position with loss. 


Note; Both 'cancel position' and 'close position' produce an order, these orders should be added to "Order Summary".


- Share Position Button

Is grayed out if the position status is "unexecuted". 
Displayed next to each position, generates a PnL card displaying; -position type - entry price - leverage - current price - liquidation price - PnL percent and QR code to the transaction on Polygonscan. 


- Close All Active Longs Button 

Pushes a transaction for 'closeAllLong'. 

- Cancel All Pending Longs Button 

Pushes a transaction for 'cancelAllLong'.

- Close All Active Shorts Button 

Pushes a transaction for 'closeAllShort'. 

- Cancel All Pending Shorts Button 

Pushes a transaction for 'cancelAllShort'..



- Scroll bar 

"Order Summary" can expand to the maximum length of the page, scroll bar is needed if positions or orders exceed this capacity. 



1l ; List Button 

Same as on Multihopper. 

1m ; LP Button 

Same as on Multihopper. 

1n ; Chart button 

Same as on Multihopper. 
But chart displays "IO" data at the bottom as a 2-variable stacked bar chart. 



1o ; Links
Text links to "Telegram", "GitHub", "Contract", "Projects". 




## **Page 2 : Liquidity Menu**
Similar to "Multihopper Frontend", but "Order-Flow" displays "IO" data at the bottom of the chart as a 2-variable stacked bar chart. 

## **Page 3 : Listing Menu**
Similar to "Multihopper Fromtend", but has toggle for listing "Cross Margin" or "Isolated Margin". 
Hovering over the toggle presents a pop-up that reads; 

"Cross Margin allows each position for the same token to share the same excess margin, this strengthens them and gives a further off liquidation price. However, if one position is closed or liquidated this will affect the total margin. 
A Cross listing also allows you to list your token against any other asset, not just synthetic USD." 

If CSD is selected, the page presents an additional field for specifying "paired" token, which is used as Token-0. 
Whereas if SSD is selected, the page presents only one field for specifying "listed token". 