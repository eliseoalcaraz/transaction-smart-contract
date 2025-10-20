# AgreementLedger Smart Contract

`AgreementLedger` is a Solidity smart contract that provides a complete system for users to register, create on-chain agreements, and report on those agreements. It features a built-in utility token, "Sabot Token" (SBT), which is used to power the ecosystem.

The core loop involves users registering to receive a free token allotment, then spending those tokens to create verified agreements with other users. A portion of every agreement fee is burned (creating a deflationary mechanism), and the rest is sent to a developer wallet as a service fee.

This project is built using Hardhat and is configured for deployment on the **Lisk Sepolia Testnet**.

---

## Features

* **SBT Utility Token:** A simple ERC20-like token (`name`, `symbol`, `decimals`, `balanceOf`, `transfer`, `approve`) built directly into the contract.
* **User Registration:** A one-time `registerUser()` function that acts as an entry point, granting new users **100 SBT** to start.
* **Agreement Creation:** Allows any two registered users to create an immutable, timestamped agreement record on the blockchain.
* **Fee Mechanism:** To create an agreement, **both** parties must pay a `VERIFY_FEE` of **10 SBT**.
* **Deflation & Revenue:** The 20 SBT total fee is split:
    * **80% (16 SBT)** is transferred to the developer wallet.
    * **20% (4 SBT)** is burned, reducing the total supply of SBT.
* **Reporting System:** If a dispute arises, either party of an agreement can call `reportIssue()` to create a public, on-chain report against the other party.
* **Admin Controls:** The contract is `Ownable` (via OpenZeppelin), allowing the owner to update the `devWallet` address.

---

## How It Works: User Flow

1.  **Deployment:** The contract owner deploys the `AgreementLedger.sol` contract, passing a `_devWallet` address to the constructor. The owner's address receives an initial supply of 1,000,000 SBT.
2.  **Registration:**
    * Alice calls `registerUser()`. The contract checks she isn't already registered, marks her as `registered`, and mints 100 SBT to her balance.
    * Bob calls `registerUser()` and also receives 100 SBT.
3.  **Agreement Creation:**
    * Alice and Bob agree to terms off-chain. They hash the details of their agreement (e.g., using `keccak256`) to produce a `bytes32` hash.
    * Alice calls `createAgreement(bob_address, details_hash)`.
4.  **Fee Processing:**
    * The `createAgreement` function automatically processes the fees for **both** parties in a single transaction.
    * It deducts 10 SBT from Alice's balance (2 SBT burned, 8 SBT sent to `devWallet`).
    * It deducts 10 SBT from Bob's balance (2 SBT burned, 8 SBT sent to `devWallet`).
    * **Note:** This requires both users to have at least 10 SBT. It works by having the contract's internal functions (`_transfer`, `_burn`) directly manipulate the `balanceOf` mapping, bypassing the need for Bob to pre-approve the contract.
5.  **Logging:** A new `Agreement` struct is created and stored on-chain, and an `AgreementCreated` event is emitted.
6.  **Reporting (Optional):**
    * Bob fails to honor the agreement.
    * Alice calls `reportIssue(agreementId, bob_address, "Did not fulfill terms")`.
    * A new `Report` struct is created, and a `ReportCreated` event is emitted. This data can be used by dApps to build reputation systems.

---

## Core Contract Logic

### State Variables

* `VERIFY_FEE`: `10 * 10**18` (10 SBT)
* `BURN_PERCENT`: `20` (20%)
* `devWallet`: The address that receives 80% of all fees.
* `registered`: `mapping(address => bool)` to track active users.
* `agreements`: `Agreement[]` array storing all agreements.
* `reports`: `Report[]` array storing all reports.

### Key Functions

* `registerUser()`: `external`
    * Mints 100 SBT to `msg.sender`.
    * Requires user is not already registered.

* `createAgreement(address otherParty, bytes32 detailsHash)`: `external`
    * Requires `msg.sender` and `otherParty` are both registered.
    * Requires `msg.sender != otherParty`.
    * Calls `_processVerificationFee(msg.sender)`.
    * Calls `_processVerificationFee(otherParty)`.
    * Creates and stores the new `Agreement`.

* `_processVerificationFee(address user)`: `internal`
    * Calculates `burnAmount` (2 SBT) and `devAmount` (8 SBT).
    * Calls `_burn(user, burnAmount)`.
    * Calls `_transfer(user, devWallet, devAmount)`.

* `reportIssue(uint256 agreementId, address reportedParty, bytes32 reason)`: `external`
    * Requires `msg.sender` is one of the parties in the agreement.
    * Requires `reportedParty` is the *other* party in the agreement.
    * Creates and stores the new `Report`.

* `setDevWallet(address _new)`: `external onlyOwner`
    * Allows the contract owner to change the `devWallet` address.

---

## Local Development & Deployment

This project is a Hardhat environment.

### 1. Setup

Clone the repository and install dependencies:

```bash
git clone <repository_url>
cd agreement-ledger
pnpm install