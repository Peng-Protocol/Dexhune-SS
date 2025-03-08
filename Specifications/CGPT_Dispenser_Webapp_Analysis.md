### **Step-by-Step Walkthrough of the Web App Usage**  

This walkthrough covers all major functionalities from a **user's perspective**.  

---

## **Step 1: Open the Web App**  
When the user loads the page, they see:  
✅ A **"Connect Wallet" button** at the top right.  
✅ A 🌐 **network switch button** next to it.  
✅ A **logo and tagline** in the center.  
✅ **Action buttons**:  
   - **Trade (DexScreener)**  
   - **Dispense (LUSD to WPOL conversion)**  
   - **Freebase (hidden unless NFT balance >1)**  
✅ **Dark Mode Toggle** (🌙/🌞) at the bottom.  

---

## **Step 2: Connect a Wallet**  
### **Option 1: Browser Wallet (e.g., MetaMask)**
1. Click **"Connect Wallet"**.  
2. A **wallet modal** appears with the **"Browser Wallet"** option.  
3. Click **"Browser Wallet"**, which prompts MetaMask (or another provider).  
4. Approve the connection in MetaMask.  
5. The button updates to show the **shortened wallet address** (e.g., `0x123...789`).  
6. The app **checks Polygon network status** and updates `isPolygon`.  

### **Option 2: WalletConnect (QR Code)**
1. Click **"Connect Wallet"**.  
2. In the modal, click **"QR Code"**.  
3. A **QR code is displayed** (once the WalletConnect URI is ready).  
4. Scan the QR code with **a mobile wallet app** (e.g., Trust Wallet).  
5. Once connected, the button updates to show the **wallet address**.  

---

## **Step 3: Switch to Polygon Network (If Needed)**  
1. If the wallet is not on **Polygon**, click the **🌐 button**.  
2. The app attempts to **switch networks automatically**.  
3. If Polygon isn’t added, MetaMask prompts to **add Polygon as a custom network**.  
4. If successful, `isPolygon = true`, enabling transactions.  

---

## **Step 4: Check Eligibility for Freebase (NFT Ownership Check)**  
1. If the connected wallet **owns at least 1 Peng NFT**, the **"Freebase" button** appears.  
2. Clicking **"Freebase"** triggers a **smart contract call** (`freebase` function).  
3. After confirmation, the transaction executes.  

---

## **Step 5: Convert LUSD to WPOL (Using the Dispenser)**  
### **Step 5.1: Open the Dispenser Modal**
1. Click **"Dispense"**.  
2. A modal appears with:  
   - **LUSD input field** (`v-model="appStore.dispenseAmount"`).  
   - **Conversion cost in WPOL** (`v-text="appStore.wpolCost"`).  
   - **Execute button** (changes to "Approve" if needed).  

### **Step 5.2: Approve WPOL Spending (If Required)**
1. If the contract requires approval, the **button shows "Approve"** instead of "Execute".  
2. Clicking "Approve" sends an **approval transaction** (`approve()` function).  
3. Once approved, the button changes to **"Execute"**.  

### **Step 5.3: Execute the Conversion**
1. Clicking **"Execute"** calls the **`convert()` function** in the dispenser contract.  
2. MetaMask prompts for confirmation.  
3. After execution, the modal closes, and `appStore.status = "Dispense executed"`.  

---

## **Step 6: Trade LUSD on DexScreener**
1. Click **"Trade"**.  
2. The app redirects to **DexScreener** for Polygon LUSD trading.  

---

## **Step 7: Disconnect the Wallet**  
1. Click **"Connect Wallet"** (now showing the connected account).  
2. The **disconnect modal** appears.  
3. Click **"Yes"** to disconnect, resetting the state.  

---

## **Step 8: Toggle Dark Mode**
1. Click the **🌙/🌞 button**.  
2. The app toggles dark mode using **Vue’s state**.  
3. The setting remains until a **page refresh**.  

---