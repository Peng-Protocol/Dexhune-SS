# **Premise**
A decentralized listing platform for Dexhune.

# **General**
The system has (2) contracts; "Dexhune Markets" and "Red Marker DAO". 

## **Dexhune Markets Contract**
This is responsible for storing listed tokens and their names + ticker symbols. 
This contract is owned by an admin, the admin approves new listing requests. 

### **Functions**
- **requestListing**

Creates a new listing request which is stored by the contract under "pendingListings" with an index number and boolean condition. 
The admin can set the listing's boolean condition to 'true', in which case it is stored under "fullListings"
Takes a fee based on the amount in "listPrice. 
Fee is billed in "feeToken" and is sent to the admin. 
Fails if fee cannot be paid. 
Ensures that the requested asset is not already listed, else fails. 
Ensures that another request to list the same token does not already exist, else fails. 
Optionally the user can provide an ETHscription image hash. 

- **requestDelisting**

Creates a new delisting request with a stated listed token contract address. This is stored in "pendingDelistings". 
Takes a fee based on the amount in "listPrice. 
Fee is billed in "feeToken" and is sent to the admin. 
Fails if fee cannot be paid. 
Ensures that the requested asset is listed, else fails. 
Ensures that another request to delist the same token does not already exist, else fails. 

- **approveListing (adminOnly)**

Sets a listing request to "true" and moves it to "fullListings".

- **approveDelisting (adminOnly)**

Sets a delisting request to "true" and moves the associated token out of "fullListings".

- **setAdmin (adminOnly)**

Transfers ownership of the contract, the "admin" role is the same as "owner" but with a different name. 
Deployer is the original admin. 

- **setFeeToken (adminOnly)**

Determines the fee token. 

- **queryListingByName**

Returns the details of a full listing by its name. 

- **queryListingByIndex**

Returns the details of a full listing by its index number. 

- **queryListingByTicker**

Returns the details of a full listing by its ticker symbol. 

- **queryListingByAddress**

Returns the details of a full listing by its address. 

- **queryPendingListingByAddress**

Returns the index numbers of all pending listings by their address.

- **queryPendingListingByIndex**

Returns the full details of a pending listing by its index number. 

- **queryPendingDelistingByAddress**

Returns the index numbers of all pending delistings by their address. 

- **queryPendingDelistingByIndex**

Returns the full details of a pending listings by its index number. 

### **Data**
- **listPrice**

List price is set by fetching the balance of the fee token at the admin address and calculating; 

Admin Balance / (1000 + total listings) 

List price can be "0". 

- **feeToken**

Stores the address of the fee token. 

- **admin**

Stores the address of the admin.

- **pendingListings**

Stores the contract address of a listing request - index number - ETHscription hash (if any) and boolean condition. 

- **pendingDelistings**

Stores the contract address of a delisting request - index number - ETHscription hash (if any) and boolean condition.  

- **fullListings**

Stores the contract address - ETHscription hash (if any) - name and symbol of an approved listing. Name and symbol are queried and stored upon admin confirmation. 

## **Red Marker DAO**
A simple DAO for approving or rejecting proposals to list or unlist tokens from Dexhune Markets.
However, each vote requires a permanent deduction of token units from the voter.
How much the user can vote is determined by their stake amount. 
But every staked balance is subject to a gaussian rebase mechanism, which redistributes all tokens of all stakers to create a "normal distribution" curve. 


### **Functions**
- **proposeAction**

Used to propose approving a 'Dexhune Markets' listing or delisting. 
Each proposal requires the proposer to own at least (1) unit of the set ERC-20. 
 
A proposal to approve a listing/delisting requires the listing/delisting request index number. 

Proposals require at least 51% of the total staked token to pass.

- **upvoteAction**

All actions are assumed rejected by the totality of the staked token until upvoted otherwise.
Each upvote is a permanent deduction of the vote amount which is held within the contract and later becomes fees. 
Is limited by how much the address has staked. 

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

Returns the staked tokens of addresses that have missed more than (10) listing proposals and clears their staker slot. 

- **setMarkets (ownerOnly)**

Determines the Dexhune Markets contract address. 

- **queryProposalByAddress**

Each proposal stores the full details of the listing/delisting request, including the token address and votes. This function returns the full details of a listing/delisting request, including how many votes have been cast in favor. 

- **queryActiveProposalByIndex**

Returns the full details of an active proposal by its index number. 

- **queryPassedProposalByIndex**

Returns the full details of a passed proposal by its index number. 

- **queryRejectedProposalByIndex**

Returns the full details of a rejected proposal by its index number. 

- **queryInactiveByIndex**

Returns the address of an inactive member by its index number. 

- **queryStakeByAddress**

Returns the number of staked tokens an address has. 

- **queryStakeByIndex**

Returns the number of staked tokens an address has. 


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

Stores the current amount of [TOKEN] that has been transacted by the contract, is updated whenever a vote is cast. 

- **fees**

Stores any unallocated [TOKEN] found in the contract. This is calculated as; 

Total Balance - totalStake 

- **stakingToken**

Stores the address of the token used for staking. Is set into the contract pre-deployment. 

- **totalStake**

Stores how much of the `TOKEN` is currently staked, is increased whenever more stake is added or reduced when stake is withdrawn. 

- **totalProposals**

Stores the number of proposals passed by the DAO. 

- **Markets**

Stores the Dexhune Markets contract address. 
