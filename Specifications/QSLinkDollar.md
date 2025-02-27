### **Premise**
A CFAMM stablecoin using Liquidity rebase and Chainlink price oracles to maintain a price of $1. No collateralization. 

## **Parameters** 

| Data     | Value       |
|----------|-------------|
| Ticker   | LUSD        |
| Price    | $1          |
| Decimals | 18          |

### **General**
The token is an ERC-20 with a few custom functions, the token achieves a price change by adding or subtracting token units to or from a target liquidity address. 

Because price on CFAMM liquidity pairs is calculated by dividing the sum of `Token0` in a pair by the sum of `Token1`, and `Token1` (LUSD) would be programmed with rebasing properties, it should be possible to alter the price by changing how much of `Token1` is present. 

When rebase is triggered; the token fetches the correct price from the target oracle contract, parses it then fetches the balances of `TOKEN0` and `TOKEN1` (in this case WPOL and LUSD). Then determines how much should be in the LP to achieve the target price and alters the LUSD amount towards that purpose. 

Because rebase offsets the LP's reserves, `sync` must be called after each rebase, `sync` is a function on the liquidity contract. 

The initial supply is (4.0e9), all of which is issued to the deployer at deployment. 
 
## **Functions**
- **approve**:
This is a standard ERC-20 function that specifies an amount an external address can transfer from the approver. This function however is adjusted to trigger `rebase` and `sync`, the latter is called at the LP address. 

- **rebase**:
This checks how much $WPOL and LUSD is present in the target LP address, then checks the POL/USD price from a target chainlink oracle, normalizes it and makes a decision based on the data acquired. The formula is; `LP WPOL balance * POL/USD price = expected LUSD amount in LP` **Example**
If price is 0.80 ($0.80 to 1 POL) while there is 500 WPOL in the LP, the contract calculates 500 * 0.80 = 400, therefore there should be 400 LUSD in the LP. This function can be independently called though is also triggered each time 'approve' is invoked. Rebase ideally will occur prior to each sell. Rebase starts once the contract is deployed and associated addresses are set.

- **collectorFees**
The contract takes a 0.05% fee on each 'transferFrom' and 'transfer', sending the amount to a designated "tax collector". If the swap amount is too low to take a fee then no fee is taken.

- **setOracleAddress**
Defines the current oracle address

- **oracleAddress**
Returns the current Chainlink oracle address where "latestAnser" is queried to get the price of POL/USD. 

- **setLiquidityAddress**
Determines the address where token pairs are fetched (ownerOnly).

- **liquidityAddress**
Returns liquidity address.

- **setWPOLAddress**
Determines the address where WPOL "balanceOf" is checked in relation to the LP pair address (ownerOnly).

- **taxCollector** 
Returns tax collector address

- **setTaxCollector**
Defines tax collector address (ownerOnly)


### **Notes**
- No constructor arguments, causes headaches during verification. 

- Contract is ownable.  
