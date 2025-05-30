# **Premise**
A frontend application for interacting with Red Marker DAO contracts.

# **General**


## **Page 1**
- **1a ; Wallet connect button**

Initiates wallet connect. 

- **1b ; DXH logo**

Is DXH logo. 

- **1c ; Gallery**


- **Balances**

If the wallet is connected; queries and presents the address's NFT and FFT balances. Displays the numbers with ticker symbols. 

- **Recent Proposals**

Queries and displays all pending listing proposals by their index number. 

- **Upvote**

Displayed next to each proposal, presents a pop-up with an "amount" field that allows the caller to state how much FFT they want to spend on the vote. Pop-up has "Vote" button to push upvote transaction. 

- **Passed Proposals**

Queries and displays first (1000) passed proposals by their index number. 

- **More Button**

Triggers the frontend to query additional (1000) passed proposals. 

- **Past Rejected Proposals**

Queries and displays first (1000) rejected proposals by their index number. 

- **More Button**

Triggers the frontend to query additional (1000) Rejected Proposals. 

...

1d ; Stake Menu 

- **Total Stake**

Queries and displays total staked tokens. 

- **User Stake**

Queries and displays a user's stake (if any). 

- **Add Stake Button**

Creates a pop-up with an amount field and "add" button, pushes a transaction to add the stated amount of tokens, if the contract is not approved then this first approves the amount being added. 
Updates user's stake balance. 

- **Remove Stake Button**

Same as "Add Stake Button" but for "pullStake" transactions. 

- **Fees**

Calculates the fees the user has accrued and presents it here. 

- **Claim Fees**

Pushes a transaction to claim fees. Refreshes all Blockchain data. 

- **Inactive Members**

Queries and displays the number of inactive members. 

- **Kick Button**

Only appears if there are inactive members, pushes a transaction to kick inactive. 
Refreshes all Blockchain data. 


- **1 ; links**

Text links to; GitHub, Telegram and Contract. 
