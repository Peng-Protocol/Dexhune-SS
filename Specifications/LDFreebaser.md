### **Premise** 
An incentivized smart contract and automated script for calling `rebase` on LUSD. 

### **General** 
The system is made up of a "Freebaser" Contract deployed to whichever chain LUSD is present, and an automated script built on Gellato. 

## **Contract** 
The Freebaser contract holds a large sum of LUSD which it pays out to whoever calls `freebase`. `freebase` triggers `rebase` at the LUSD contract. 

**Functions**
- **freebase**:
Calls `rebase` at the LUSD contract address, caller must hold at least (1) item of a target `NFT`. 
Caller is sent 0.10 LUSD from the contract's balance. Function has a cooldown of 30 seconds. 

- **setLUSD (ownerOnly)**:
Determines the `LUSD` contract address. 

- **setNFT (ownerOnly)**:
Determines the `NFT` contract address. 

**Data**
- **LUSD**
Stores the `LUSD` contract address.

- **NFT**
Stores the `NFT` contract address. 

## **Automated Script**
The Freebaser Auto-Script (bot) is deployed via Gellato to scan the liquidity pool (LP) address for incoming or outgoing swaps and call "rebase" after it. 
The bot is given (1) Peng NFT. 
Bot remains funded by selling rewards. 

**Functions** 
- **Scan** 
A basic routine that scans each block for swap transactions in relation to a set LP address. Prompts `doFreebase` if a swap is detected. 

- **doFreebase** 
Calls `freebase` at the Freebaser contract, then executes a swap for 0.10 LUSD in exchange for POL. 
