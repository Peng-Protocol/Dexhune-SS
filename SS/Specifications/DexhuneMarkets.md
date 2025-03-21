# **Premise**
A decentralized listing platform for Dexhune.

# **General**
The system has (2) contracts; "Dexhune Markets" and "Red Marker DAO". 

## **Dexhune Markets Contract**
This is responsible for storing listed token addresses and their names + ticker symbols. 
This contract is ownable, the owner approves new listing requests. 

### **Functions**
- **requestListing**

Creates a new listing request which is stored by the contract under "pendingListings" with an index number and boolean condition. 
The owner can set the listing's boolean condition to 'true', in which case it is stored under "fullListings"
Takes a fee based on the amount in "listPrice. 
Fee is billed in "feeToken" and is sent to the owner. 
Fails if fee cannot be paid. 
Ensures that the requested address is not already listed, else fails. 
Ensures that another request to list the same token does not already exist, else fails. 
Optionally the user can provide an ETHscription image hash and "exceptions" string. 

- **requestDelisting**

Creates a new delisting request with a stated listed token contract address. This is stored in "pendingDelistings". 
Takes a fee based on the amount in "listPrice. 
Fee is billed in "feeToken" and is sent to the owner. 
Fails if fee cannot be paid. 
Ensures that the requested asset is listed, else fails. 
Ensures that another request to delist the same token does not already exist, else fails. 

- **approveListing (ownerOnly)**

Sets a listing request to "true" and moves it to "fullListings".
Queries and stores the token name and ticker symbol. 

- **approveDelisting (ownerOnly)**

Sets a delisting request to "true" and moves the associated token out of "fullListings". Reduces the totalListings number by (1). 

- **setFeeToken (ownerOnly)**

Determines the fee token. 

- **QueryByIndex**

Returns the details of a request or listing by its index number.
Requires: status (pending - passed -rejected, 1 - 2 - 3), and index number. 

### **Data**
- **listPrice**

List price is set by fetching the balance of the fee token at the owner address and calculating; 

Owner Balance / (1000 + total listings) 

List price can be "0". 

- **feeToken**

Stores the address of the fee token. 

- **listings**

A struct for listings, stores the contract address of a listing request - index number - ETHscription hash (if any). 
Stores the status; "pending", "listed", or "rejected" (1, 2, 3). 
Stores the token name, ticker, and "exceptions" string. 

- **totalListings** 

Stores the number of all fully listed tokens, updated when listings are passed or removed. 

- **deadline**

Determines when requests can be deleted with _clearRequests. _clearRequests iterate over up to 10 pending listing requests to check their deadline. Is triggered by write functions. 

## **Red Marker DAO**
A simple DAO for approving or rejecting requests to list or unlist tokens on Dexhune Markets.
Each vote requires a permanent deduction of token units from the voter.
How much the user can vote is determined by their stake amount. 
But every staked balance is subject to a rebase mechanism, which redistributes all tokens of all stakers to create a "normal" or equak distribution. 


### **Functions**
- **proposeAction**

Used to propose approving a 'Dexhune Markets' listing or delisting. 
Each proposal requires the proposer to own at least (1) unit of the set ERC-20. 
 
A proposal to approve a listing/delisting requires the listing/delisting request index number. 

Proposals require at least 51% of the total staked token to pass.

- **upvote**

All actions are assumed rejected by the totality of the staked token until upvoted otherwise.
Each upvote is a permanent deduction of the vote amount which is held within the contract and later becomes fees. 
Is limited by how much the address has staked. 
Increases tVolume by the amount spent. 
If an upvote tips the votes cast above 51% then the proposal passes and executes `approveListing` or `approveDelisting` depending on the type of proposal. 
Updates callers `lastVote`. 
Required params : proposal index, amount. 

- **stakeToken**

Staking one's tokens makes a deduction of the tokens being staked and creates a "staker" data slot. 
Users can add to their stake by calling this function again, restaking does not reset one's dVolume. 

- **pullStake**

Removes a stated amount of a user's staked tokens, returning them to their address, clears their staker slot if the deduction wipes the entire balance, caller must be a staker. 

- **claimFees**

Allows the user to claim a certain portion of the "fees" storage.
This is effected using the following formula; 

```
total volume / volume at deposit * 100 - 100 = contributed volume 

user stake / total stake * 100 = stake contribution 

(fees / 100 * stake contribution) / 100 * contributed volume 
```

Output amount cannot be greater than available fees, if greater then only pay available fees.

Once a user claims fees their dVolume is set to current tVolume, thereby resetting how much they are entitled to claim. 

- **ejectInactive**

Iterates through a specified number of staked addresses and determines if they are inactive. Gives back the staked tokens of addresses that have missed more than (10) listing proposals and clears their staker slot. 

- **setMarkets (ownerOnly)**

Determines the Dexhune Markets contract address. 

- **queryProposal**

Each pending proposal stores the index of the listing/delisting request and votes. This function returns the full details of a  proposal by index number. 

- **queryLatest** 

Fetches and the details the current active proposal, if any. 

Required params; Index. 

- **queryInactive**

Iterates through a specified number of staked addresses and determines if they are inactive, returns the addresses of inactive members up to the specified number of iterations. Ensure this doesn't exceed stack depth limit. 

- **queryStake**

Returns the full details of an address's stalker slot. 

-- **setMarkets(ownerOnly)**

Determines the Dexhune Markets contract. 

- **setStakingToken**

Determines the staking token. 

- **_clearProposal**

Iterates over (5) pending proposals to determine if their deadline has elapsed, moves them to "rejected" if elapsed. 
Is triggered by; `propose`, `upvote, `stakeToken` and `pullStake`. Is private.

- **_rebase** 
Fetches the stake balances of all staker addresses and attempts to create a normal distribution. Is triggered by `stakeToken` and `pullStake`.  

### **Staker Slots**

Each Staker gets a data entry formatted as follows; 

- Staker Address ; (Address)
- Staked Amount ; (uint256)
- dVolume ; (uint256) 
- Last Vote ; (uint256) 

"Staker Address" stores the address of the staker and is necessary during withdrawals. 

"Staked Amount" stores how much they have staked cumulatively and is necessary for claiming fees.

"dVolume" stores the tVolume at the time of deposit and is necessary for calculating fee allocation. 

"Last Vote" stores the "totalProposals" height at the time of a staker's last logged vote. Is needed for `ejectInactive`. 

### **Data**
- **tVolume**

Stores the current amount of [TOKEN] that has been transacted by the contract, is added to whenever a vote is cast.  

- **fees**

Stores any unallocated [TOKEN] found in the contract. This is calculated as; 

Total Balance - totalStake 

- **stakingToken**

Stores the address of the token used for staking. Is set into the contract pre-deployment. 

- **totalStake**

Stores how much of the `TOKEN` is currently staked, is increased whenever more stake is added or reduced when stake is withdrawn. 

- **passedProposalsCount**

Stores the number of proposals passed by the DAO. 

- **pendingProposalsCount**

Stores the number of pending proposals stored by the DAO. Updated whenever a proposal is passed. 

- **rejectedProposalsCount**

Stores the number of rejected proposals stored by the DAO. Updated whenever a proposal is rejected. 

- **proposals**

A struct, each proposal stores; request index on markets, votes, type (listing or delisting request, 0 or 1) and deadline. 
The deadline is set once the proposal is made and is 10 minutes by default. 

- **Markets**

Stores the Dexhune Markets contract address. 
