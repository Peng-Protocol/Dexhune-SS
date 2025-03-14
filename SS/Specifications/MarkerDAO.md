# **Premise**

A DAO for collecting and using protocol fees on Dexhune. 

# **General**

All fees from listing tokens on Dexhune are sent to MarkerDAO. Participants can pass custom transactions for the contract to execute. 

Participants are regarded as holders of a target NFT collection set by the initial owner, once an NFT collection is set, it can only be changed by DAO vote. 

Each vote requires expenditure of a set fungible token (FFT). A proposal requires 33.3% turnout in the set NFT collection's supply and 51% upvotes to pass. 

The DAO can execute "routines", which occur at stated intervals, these are custom transactions that occur periodically. 

Routines have "runways", which is a duration for which the routine will run. 



### **Functions**

- **Propose**

Creates a new proposal entry, requires; custom transaction and string detail which need to be voted on by the DAO. Proposer must be an NFT holder, charges a fee in FFT equal to 0.0001% of the DAO's FFT balance - else proposal is rejected. 

- **upvoteProposal**

Requires proposal index, proposal must exist and status must be "pending", adds an upvote equal to a stated amount in FFT. 

- **downvoteProposal**

Requires proposal index, proposal must exist and status must be "pending", adds a downvote equal to a stated amount in FFT. 

- **finalizeProposal**

Requires index number, proposal status must be "pending", executes the custom transaction of the proposal if passed - else ignores the custom transaction.
Changes the status to "passed" if passed or "rejected" if rejected. 
Can only be called after 24 hours since the proposal was created. 

...

- **proposeRoutine**

Creates a new routine entry, requires; custom transaction - string detail - interval and runway, which need to be voted on by the DAO. Proposer must be an NFT holder, charges a fee in FFT equal to 0.0001% of the DAO's FFT balance - else proposal is rejected. 

- **upvoteRoutineProposal**

Requires routine index, routine must exist and status cannot be "rejected", adds an upvote equal to a stated amount in FFT. 

- **downvoteRoutineProposal**

Requires routine index, routine must exist and status cannot be "rejected", adds a downvote equal to a stated amount in FFT.

- **ProposeRoutineRemoval**

Creates a new routine removal entry, requires routine index, routine must exist and status must be "passed". 

- **pushRoutine**

Executes a routine's custom transaction if it's "interval" has elapsed since the last time it was called and its runway is still active. All other proposal/routine functions trigger this function. 

...

- **setNFT (ownerOnly)**

Determines the NFT whose holders are allowed to vote. Contract queries NFT holdings per voter. 

- **setFFT (ownerOnly)**

Determines the FFT used for voting. 

...

- **queryActiveProposalByIndex**

This returns the full details of an active proposal by its index number. 

- **queryRejectedProposalByIndex**

This returns the full details of a rejected proposal by its index number. 

- **queryPassedProposalByIndex**

This returns the full details of a passed proposal by its index number. 

- **queryProposalByIndex**

Returns the full details of a proposal by its index number. 

- **queryLatestProposal**

Returns the full details of the proposal with the highest index. 

...

- **queryActiveRoutineByIndex**

This returns the full details of an active routine by its index number. 

- **queryRejectedRoutineByIndex**

This returns the full details of a rejected routine by its index number. 

- **queryPassedRoutineByIndex**

This returns the full details of a passed routine by its index number. 

- **queryRemovedRoutineByIndex**

This returns the full details of a removed routine by its index number. 

- **queryRoutineByIndex**

Returns the full details of a routine by its index number. 

- **queryLatestRoutine**

Returns the full details of the routine with the highest index. 

...

### **Data**
- **NFT**

Stores the address of the DAO's NFT collection, whose holders are allowed to vote. 

- **FFT**

Stores the address of the DAO's FFT, which is used for voting. 

- **Proposals**

Stores all proposals (+ routine proposals) with the following details; Index, string detail, custom transaction, status (regular/routine - pending - rejected - passed). 

- **Routines**

Stores all routines with the following details; Index, string detail, custom transaction, status (pending - rejected - passed - removed), interval, runway. 

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

Queries and displays all pending proposals by their index number. 

- **Upvote**

Displayed next to each proposal, presents a pop-up with an "amount" field that allows the caller to state how much FFT they want to spend on the vote. Pop-up has "Vote" button to push upvote transaction. 

- **Downvote**

Same as "Upvote" but for Downvote transactions. 

- **Recent Routine Proposals**

Queries and displays all pending routine proposals by their index number. 

- **Upvote**

...

- **Downvote**

...

- ** Active Routines**

Queries and displays first (1000) active routines by their index number. 

Each routine entry has a timer for when it can be executed, once it exceeds this time the timer becomes a button that reads; "execute". If clicked; the frontend will query the routine to see if it is unexecuted, if true then pushes transaction to execute the routine.
Each routine has a "runway", which is how long it will run for. 

- **More Button**

Triggers the frontend to query additional (1000) active routines. 

- **Passed Proposals**

Queries and displays first (1000) passed proposals by their index number. 

- **More Button**

Triggers the frontend to query additional (1000) passed proposals. 

- **Past Rejected Proposals**

Queries and displays first (1000) rejected proposals by their index number. 

- **More Button**

Triggers the frontend to query additional (1000) Rejected Proposals. 

- **Past Rejected Routines**

Queries and displays first (1000) rejected routine proposals by their index number. 

- **More Button**

Triggers the frontend to query additional (1000) rejected routines. 

- **Removed Routines**

Queries and displays first (1000) removed routines by their index number. 

- **More Button**

Triggers the frontend to query additional (1000) removes routines. 

- **1d ; links**

Text links to; GitHub, Telegram and X
