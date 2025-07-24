## **Shock Space**

A permissionless leverage trading platform based on Dexhune-P, allows any token on Polygon POS to be listed. Integrates scalable synthetic RWA (real world assets) primitives for fiat currencies and commodities via Chainlink data feeds. Shock Space has (7) distinguishing qualities; 

**A. Inverse Price Impact**:

Positions create an inverse impact on price; longs decrease price, while shorts increase it. 
This is because the user's margin is added to the listing's market liquidity when the position is created, thereby altering the balance of tokens and affecting the price. 
Positions only have as much impact as the user's margin relative to the Listing contract's balance. 
Longs overall still increase price because the user has to buy the token in order to long it.

**B. Synthetic Leverage**:

Positions are created using "Synthetic Leverage" that is issued by the exchange rather than borrowed from a lender. With limitations based on how much leverage is used relative to the available liquidity. 

When a position closes; the leveraged amount is erased and the user is owed their excess margin - initial margin after fees and any profit or loss they may have made, payable in the opposing asset type (longs receive USD / Token-1, while shorts receive Token-0). 

Position closures create a unique order that is filled by opposing liquidity types either in the market liquidity or staked liquidity. 

**C. Customizable Isolated Margin**:

Users can customize how much is used as initial margin or excess margin in isolated positions, this affects liquidation price and position health. 

**D. Progressive Fees**:

Fees are billed once with no funding or maintainence fees. Entry fees are billed based on leverage used, with a maximum of 99% fees at 100x leverage and minimum of 1% at 2x. 
Fees are paid to liquidity providers of the opposing side; longs pay fees to USD or [TOKEN-1] LPs, while shorts pay fees to [TOKEN-0] LPs. 

**E. Cross Pairing and Cross Margin**:

Shock Space allows cross paired listings between any (2) tokens while also providing a comprehensive cross margin experience on cross pairings.

**F. Asset Types**
Tokens on the EVM are directly listed, creating markets that respond to demand and arbitrage.

**G. Micro-positions**
Positions can be opened with as little as $1e-6 or lower!" 

**Deployment**

***Pending...***

## **LUSD (Outdated)**
A highly scalable and accurately price stable synthetic stablecoin making use of "LP Rebase".
The token achieves a price of $1 by fetching the POL/USD price from a Chainlink oracle and rebases a target QuickSwap liquidity pool (that holds wPOL/LUSD) based on the LP Rebase formula. 

$LUSD does not require collateral to remain stable, however, users may encounter slippage depending on how much they intend to trade and how much liquidity is available. 

Users may profit by providing liquidity.  This is because the rebase function increases or reduces the balance of all Liquidity Providers depending on demand. 

$LUSD takes a 0.05% fee on every transfer, fees are distributed to Peng NFT holders via Marker DAO. 

LUSD can be acquired without slippage at the dispenser contract.

"Freebaser" contract incentivizes calling "rebase". 

$LUSD is tradable on CFAMM DEXs like Uniswap. 

**Deployment**
- **[LUSD](https://polygonscan.com/address/0xF0FD398Ca09444F771eC968d9cbF073a744A544c#readContract)**
- **[Dispenser](https://polygonscan.com/address/0xB709FafF4f731bfD767354738cB8A38D08a92920#writeContract)**
- **[Freebaser](https://polygonscan.com/address/0x3bA341ea464ae63372Bfe60B572E677CE0d9a3Ba#writeContract)**

- **[Dispenser Frontend](https://link.dexhune.eth.limo)**

- **Succession**; the system is currently outdated, new version can be found [here](https://github.com/Peng-Protocol/Dexhune-P/tree/main/LUSD-V2) and relies on OMF for price peg, solves the collateral issue somewhat. 
