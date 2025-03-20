# **Premise**

A DAO for collecting and using protocol fees on Dexhune. 

# **General**

All fees from listing tokens on Dexhune are sent to MarkerDAO. Participants can pass custom transactions for the contract to execute. 

Participants are regarded as holders of a target NFT collection set by the initial owner, once an NFT collection is set, it can only be changed by DAO vote. 

Each vote requires expenditure of a set fungible token (FFT) with a (1) unit minimum but no upper limit, the amount of FFT spent does not influence the vote but can be used to fund proposals before they pass. 

A proposal requires 33.3% turnout in the set NFT and 51% upvotes to pass. 

The DAO can execute "routines", which occur at stated intervals, these are custom transactions that occur periodically. 

Routines have "runways", which is a duration for which the routine will run. 



### **Functions**

- **Propose**

Creates a new proposal entry, requires; string detail which need to be voted on by the DAO. Proposer must be an NFT holder, charges a (1) FFT fee - else proposal is rejected. 
Requres; address (where calldata is executed), callData (custom transaction for smart contracts), value (native tokens sent). 
Each proposal has a deadline equal to (1) week in seconds. 

- **Vote**

Requires proposal index, proposal type (regular or routine), vote type, proposal must exist and status must be "pending", adds an upvote or downvote equal to number of NFTs the address owns. Max iteration is 30 NFTs per vote, callers with more than 30 can vote again, contract will iterate over NFTs owned and exact items used to vote per proposal. 


- **finalizeProposal**

Requires index number, proposal type, proposal status must be "pending", executes the custom transaction of the proposal if "regular" and passed  - else ignores the custom transaction. 
Changes the status to "passed" if passed or "rejected" if rejected. 
Can only be called after 24 hours since the proposal was created. 
If proposal type is routine, does not execute calldata but moves routine details into active routines. 

...

- **proposeRoutine**

Creates a new routine proposal, requires; address - calldata - native token value - string detail - interval and runway, which need to be voted on by the DAO. Proposer must be an NFT holder, charges a (1) FFT fee  - else proposal is rejected. 


- **pushRoutine**

Executes a routine's custom transaction if its "interval" has elapsed since the last time it was called and its runway is still active. All other proposal/routine functions trigger this function. 

...

- **setNFT (ownerOnly)**

Determines the NFT whose holders are allowed to vote. Contract queries NFT holdings per voter. 

- **setFFT (ownerOnly)**

Determines the FFT used for voting. 

- **setFinalizeTime (ownerOnly)**

Determines when the proposal can be finalized, default is 24 hours in seconds, after which a proposal is eligible for execution or routine activation. 

...

- **queryProposals**

This returns the full details of a proposal by its index number. This returns both active and passed proposals. 

- **queryRoutines**

This returns the full details of a routine by its index number. This returns both active and expired routines. 


### **Data**
The following data is public:

- **NFT**

Stores the address of the DAO's NFT collection, whose holders are allowed to vote. 

- **FFT**

Stores the address of the DAO's FFT, which is used for voting. 

- **proposals**

Stores all proposals (+ routine proposals) with the following details; Index, string detail, custom transaction, type (regular/routine) status (pending - rejected - passed). 

- **routines**

Stores all routines with the following details; Index, string detail, custom transaction, status (pending - rejected - passed - removed), interval, runway. 

- **finalizeTimeLimit**

Stores the time limit before each proposal can be finalized. 

- **proposalCount**

Stores the number of proposals made, incremented by each new proposal. 


## **Frontend**
A frontend application for interacting with MarkerDAO.  

### **General**
Has (1) page. 

### **Page 1**
- **1a ; Wallet connect button, initiates wallet connect. 

- **1b ; DXH logo**

Is DXH logo. 

- **1c ; Gallery**

- **Balances**

If the wallet is connected; queries and presents the address's NFT and FFT balance. Displays the numbers with ticker symbols. 

- **Recent Proposals**

Queries up to (1000) proposals incremently till the "proposalCount" height, filters and displays all pending regular  proposals by their index number. 

Has "more" button to query additional (1000) proposals. 

Displays text that reads; "Nobody here but us chickens!" if there are no pending regular proposals. 

- **Upvote**

Displayed next to each proposal, presents a pop-up with an "amount" field that allows the caller to state how much FFT they want to spend on the vote. Pop-up has "Vote" button to push upvote transaction. 

Checks of the user has approved enough FFT for their vote, otherwise pushes a transaction for "approve" at the FFT contract address with popup "You need to approve first!". "Vote" button visibly changes to "approve".

- **Downvote**

Same as "Upvote" but for Downvote transactions. 

- **Recent Routine Proposals**

Queries up to (1000) proposals incremently till the "proposalCount" height, filters and displays all routine proposals by their index number. 

Has "more" button to query additional (1000) proposals. 

Displays text that reads; "Nobody here but us chickens!" if there are no routine proposals. 

This also presents passed or rejected routine proposals  

- **Upvote**
Same as "upvote" in "Recent Proposals" but uses type "2". 
...

- **Downvote**
Same as "downvote" in "Recent Proposals" but uses type "2".
...

- ** Routines**

Queries and displays first (1000) routines by their index number. 

Each routine entry has a timer for when it can be executed, once it exceeds this time the timer becomes a button that reads; "execute". If clicked; the frontend will query the routine to see if it is unexecuted, if unexecuted then pushes transaction to execute the routine.
Each routine has a "runway", which is how long it will run for, this is parsed from its timestamp into human readable time. 

Has "More Button" that to query additional (1000) active routines. 

- **Passed Proposals**

Same as "Recent Proposals" but for passed proposals. 

- **Past Rejected Proposals**

Same as "Recent Proposals" but for rejected proposals. 

- **1d ; Proposal Builder**

This section is only visible if the wallet is connected and owns >1 NFT. 

Has text that reads; "Create a new Proposal". 

Has  fields for "toAddress", "callData", "POL Value", "Details". Which are passed to the contract "propose" parameters and pushed for signing in the user's wallet. 

Checks if the user has >1 FFT, otherwise presents error popup "You need more LUSD!".  Amount must be approved, if not "Propose" Button changes to "Approve" and instead pushes a transaction to approve the contract. 

Has toggle for routine or regular. 

If routine is toggled this presents additional fields for "interval" and "runway". Also when "Propose" is clicked it pushes a transaction to propose routine instead. 

- **1e ; links**

Text links to; GitHub, Telegram and X
