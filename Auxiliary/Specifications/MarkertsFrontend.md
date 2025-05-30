# **Premise**
A frontend application for interacting with Dexhune Markets. 

# **General**
This app is made up of (2) pages; 
- Page 1 ; All Markets
- Page 2 ; Listing 

## **Page 1 ; All Markets**
- **1a ; Connect Wallet Button**

Initiates wallet connect, does not use external dependencies.

- **1b ; Dexhune Logo**

Is Dexhune logo. 

- **1c ; Markets Menu**

Queries and displays up to 20 tokens listed on 'Dexhune Markets'. 
Each entry shows the token name and ticker.

- Price 

Presents price from the token's oldest listing. Displayed next to each entry. 

- Market Cap 

Displayed next to price. Queries the Token's supply, queries and subtracts burn address's balance of the token, calculates;

Price * unburnt supply = market capitalization 

- 24hr volume 

Queries historical (x and y)volume for the token's highest listing contract by xBalance up to 24 hours, gets the difference between the earliest and latest entries - presents the result. 

- Image 

Queries the listing's ETHscription image and presents it. Image must be less than 100kb. Presents as square profile image. 

(Note; "market cap" and "volume" headers can be clicked to sort all tokens by either volume or marketcap in ascending or descending order. Doing this will force the frontend to query all entries on the markets contract then sort them in the requested order. Presents a pop-up that reads; "loading..." and stalls any interaction with the app until the operation is done). 


- **1d ; Shock Space Button**

Titled; "Isolated Margin Leveraged Market Price Listing".
Is an image link of a Dexhune logo, indicates if the token has a shock space listing, if clicked, presents a closeable pop-up that queries and presents all SSD data; balances - liquids - number of pending orders etc, for up to (100) shock space listings the token may have. 
 
Has a button at the end that says "trade", sends the user to "trade(.)dexhune" with a query string for the token selected to be put in Token-A selection. 

Queries and displays yield rate. 

- **1e ; Cross Space Button**

Titled; "Cross Margin Leveraged Market Price Listing".
Is an image link with a purple(red minus 40) Dexhune logo, similar to "Shock Space Button" but queries the Shock Space Agent for CSD listings. 

Queries and displays yield rate. 

- **1f ; Chart Button**

Displayed next to each entry, same as "Order-Flow" from Multihopper Frontend. Displays a closeable pop-up of the Order-Flow chart using the shock space listing with the highest xBalance. 

- **1g ; More Button**

A text button at the bottom of 1c, queries additional (100) tokens on 'Dexhune Markets' and displays them in "Markets Menu". 

- **1h ; Search Button**

Displayed at the top right of the page, allows the user to search for a token by address - name or ticker. 
Uses query functions once the field is deselected or if the user hits "enter". 
Can return results for partial names or tickers. 
Presents a pop-up that reads; "Loading..." and prevents all interaction with the frontend until all results are found. 


- **1i ; List Button**

Text button titled "List", replaces Page 1 with Page 2.  

- **1m ; Links**

Text Links to ; 'Telegram' - 'Github' - 'Contract' and 'DAO'. 

"DAO" directs to the Red Marker DAO frontend. 

## **Page 2**
- **2a ; Listing Menu**

Is 2b to 2f. 

- **2b ; Address field**

- ETHscription image hash

A field for specifying an ETHscription image hash that will be appended to the listing. (optional).


- ETHscription image selection button

Prompts the user to provide an image from their device, image must be a non-animated gif and 50 x 50 else throw error "image must be 50 x 50 non-animated gif". 


If the image is acceptable then push a transaction to inscribe the image in a transaction input using the ETHscription standard. 

Presents a pop-up that reads; "Your image needs to be inscribed to the Blockchain, a transaction will be pushed for you to sign, please wait". 

Once the image is inscribed, frontend retrieves the transaction hash and uses it to replace "ETHscription image hash". 

Presents pop-up; "Image inscribed and appended!"

Is optional. 

- **2c ; Check Status Button**

Assumes the token is pending listing, fetches the request's status on the 'Dexhune Markets' contract, queries the 'Red Marker DAO' contract for the token's request, presents the data in 2e.    

If the token is listed, instead perform 1d - 1j but with the specified token contract and present the results in 2e.

If the token is not listed and does not have a pending listing, present a temporary pop-up that says "Token unavailable on Dexhune, click "List" to join us!". 

- **2d ; Request Listing Button**

Assumes the token is not listed, 

If the user does not have enough balance to pay the listing fee this returns "you need (listing fee amount) DOHL to list this token!" 
Else pushes listing transaction. 

If the token is pending this returns "Check Status Button", 
if the token is already listed; see "Check Status Button". 

- **2e ; Request details**

If the token is pending listing, this displays the Token Address - Name - Ticker Symbol - full ETHscription image and percent of votes gotten (votes gotten is a horizontal bar with a cutoff mark at 51%). 

If the token is listed this displays text details of its various listings, displaying their listing type - price - xBalance - yBalance and ETHscription image. 

If the contract is not approved, then this first approves the contract to deduct the amount for fees. 

- **2f ; Listing Cost**

Displayed next to the address field, queries and presents the 'listPrice' at the 'Dexhune Markets' contract. 

- **2g ; Retvrn Button**

Returns to Page 1. 
