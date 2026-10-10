
# PulsePay 💸
### Salary Streaming on Monad

PulsePay lets an employer send salary to an employee gradually using a smart contract on the Monad blockchain.

Instead of waiting for a fixed payday, an employee earns salary continuously while the salary stream is active. The employee can withdraw the amount earned so far.

---

## 🌐 Open PulsePay

**Live application:** https://pulsepay-qfmz.onrender.com

Open this link in Chrome or another modern browser.

You need MetaMask installed and connected to Monad Testnet to use the blockchain features.

---


## 📜 Deployed Smart Contract

PulsePay's SalaryStream contract is deployed on **Monad Testnet**.

- **Contract address:** `0x292aA0c8da23e6F0E9aDC0D0ED80EE82151590C5`
- **Network:** Monad Testnet
- **Chain ID:** `10143`
- **RPC URL:** `https://testnet-rpc.monad.xyz`

**View the contract:** [Open on Monad Testnet Explorer](https://testnet.monadscan.com/address/0x292aA0c8da23e6F0E9aDC0D0ED80EE82151590C5)

The frontend must use this same address to read and interact with this deployment.


## 👥 Who uses PulsePay?

PulsePay has two types of users:

### 1. Employer
The employer creates a salary stream for an employee by entering the employee's wallet address, choosing a duration, and depositing MON.

The employer can also cancel a stream later.

### 2. Employee
The employee connects the wallet whose address the employer entered.

The employee can view the salary stream, check how much salary has been earned, and withdraw available salary.

**Important:** The employer and employee must use their own correct wallet addresses. A blockchain transaction cannot simply be edited if the wrong address is entered.

---

## 🦊 Step 1: Set up MetaMask

1. Install MetaMask from its official website: https://metamask.io/
2. Create a wallet or import your existing wallet.
3. Keep your recovery phrase and private key secret.
4. Add or select Monad Testnet.

PulsePay uses these network settings:

- Network: Monad Testnet
- Chain ID: `10143`
- RPC URL: `https://testnet-rpc.monad.xyz`
- Currency: MON

You need **testnet MON** to pay transaction fees and to create salary streams.

Only use testnet funds for testing.

---

## 💼 Step 2: Employer creates a salary stream

1. Open PulsePay.
2. Click **Connect Wallet** and connect the employer's MetaMask wallet.
3. Enter the employee's wallet address.
4. Enter the salary amount to deposit, in MON.
5. Choose the stream duration.
6. Submit the transaction.
7. Confirm the transaction in MetaMask.
8. Wait for the transaction to be confirmed.

After successful creation, note the **Stream ID** shown by the application or the transaction's `StreamCreated` event.

The Stream ID is a number, such as `1` or `2`. It is **not** the transaction hash.

Keep the Stream ID so the employee can find the correct stream.

---

## 👩‍💻 Step 3: Employee checks their salary

1. Open PulsePay.
2. Connect the employee's MetaMask wallet — the same address the employer entered.
3. Enter or select the correct Stream ID, depending on the interface.
4. Open the stream details.
5. Check the earned salary and the amount available to withdraw.

The employee must use the correct wallet and Stream ID. If PulsePay says the stream does not exist, verify both before trying again.

---

## 💰 Step 4: Employee withdraws salary

1. Connect the employee wallet.
2. Open the correct salary stream.
3. Choose the withdrawal option.
4. Confirm the transaction in MetaMask.
5. Wait for confirmation.

The employee receives the salary that has accrued but has not already been withdrawn.

The amount available depends on the stream's deposit, duration, elapsed time, and any previous withdrawals.

---

## 🛑 Step 5: Employer cancels a stream

1. Connect the employer wallet that created the stream.
2. Open the correct stream.
3. Select the cancellation option.
4. Confirm the transaction in MetaMask.

When the stream is cancelled:

- Salary accrual stops at the cancellation time.
- The employer receives the unearned portion of the deposit back.
- The employee can still withdraw salary earned before cancellation.

For example, if a stream contains `1 MON` over `3600 seconds`, approximately `45 seconds` of accrual earns `0.0125 MON`, before accounting for rounding or previous withdrawals.

In that example, cancellation refunds approximately `0.9875 MON` to the employer while preserving the employee's earned salary.

---

## ⚠️ Important things to remember

- **A confirmed transaction is not always proof that you created the stream you intended.** Check the transaction logs and Stream ID.
- Never share your MetaMask recovery phrase or private key.
- Blockchain transactions generally cannot be reversed.
- Always double-check the employee's wallet address before creating a stream.
- Make sure both users are connected to Monad Testnet.
- Test with small amounts of testnet MON first.
- Transaction fees are paid separately from the salary deposit.
- If the app says "Stream ID does not exist," verify the contract address, network, and Stream ID.
- Never send real funds to a testnet contract.

---

## 🔧 Developer setup

### Requirements

- Node.js and npm
- Foundry
- MetaMask
- A Monad Testnet wallet with testnet MON

### Run the frontend

From the project root:

```powershell
cd apps/web
npm install
npm run dev
```

Open the local URL printed in your terminal.

### Build and test the smart contract

```powershell
cd packages/contracts
forge build
forge test -vv
```

### Environment configuration

The frontend uses Vite environment variables. Configure the deployed contract address and Monad Testnet settings in the appropriate environment file:

```dotenv
VITE_CONTRACT_ADDRESS=YOUR_DEPLOYED_CONTRACT_ADDRESS
VITE_CHAIN_ID=10143
VITE_RPC_URL=https://testnet-rpc.monad.xyz
```

Do not commit private keys or secret values to GitHub.

---

## 📍 Project information

**Project:** PulsePay  
**Network:** Monad Testnet  
**Purpose:** Continuous salary accrual and employee withdrawals using smart contracts.

PulsePay is a testnet application. It is intended for experimentation and demonstration, not for holding or distributing real salaries.
