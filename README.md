# AgreementLedger Smart Contract for Sabot

`AgreementLedger` is a comprehensive Solidity smart contract that provides a complete ecosystem for users to register, create on-chain agreements, manage escrow transactions, and report disputes. It features a built-in utility token, "Sabot Token" (SBT), and a robust escrow system supporting both crypto and non-crypto deliverables.

The core loop involves users registering to receive a free token allotment, then spending those tokens to create verified agreements with other users. Users can optionally create blockchain-backed escrow transactions for these agreements, with support for ETH-based payments, bank transfers, file deliverables, physical items, and services.

This project is built using Hardhat and is configured for deployment on the **Lisk Sepolia Testnet**.

---

## Features

### Token & Agreement System
* **SBT Utility Token:** A simple ERC20-like token (`name`, `symbol`, `decimals`, `balanceOf`, `transfer`, `approve`) built directly into the contract.
* **User Registration:** A one-time `registerUser()` function that acts as an entry point, granting new users **100 SBT** to start.
* **Agreement Creation:** Allows any two registered users to create an immutable, timestamped agreement record on the blockchain.
* **Fee Mechanism:** To create an agreement, **both** parties must pay a `VERIFY_FEE` of **10 SBT**.
* **Deflation & Revenue:** The 20 SBT total fee is split:
   * **80% (16 SBT)** is transferred to the developer wallet.
   * **20% (4 SBT)** is burned, reducing the total supply of SBT.
* **Reporting System:** If a dispute arises, either party of an agreement can call `reportIssue()` to create a public, on-chain report against the other party.
* **Admin Controls:** The contract is `Ownable` (via OpenZeppelin), allowing the owner to update the `devWallet` address.

### Escrow System
* **Multiple Deliverable Types:** Support for Crypto (ETH), BankTransfer, FileDeliverable, PhysicalItem, Service, and Hybrid escrows.
* **ETH Locking:** Securely locks ETH funds in the contract for crypto-based escrows.
* **Hash-Based Verification:** Uses cryptographic hashes for non-crypto deliverables (bank receipts, file CIDs, delivery confirmations).
* **Dual Confirmation:** Both parties must confirm completion before funds are released.
* **Proof Submission:** Parties can submit proof of delivery/completion on-chain.
* **Mutual Arbiter Selection:** Disputes require both parties to approve an arbiter.
* **Arbiter Resolution:** Independent arbiters can resolve disputes with three options: release to participant, refund to initiator, or split.
* **Fee Structure:** 
   * **2% platform fee** on successful escrow completion
   * **1% arbiter fee** when arbiters resolve disputes
* **Expiration Handling:** Automatic refund to initiator if escrow expires.
* **Cancellation:** Initiators can cancel pending escrows.
* **Security:** ReentrancyGuard protection against reentrancy attacks.

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

### Escrow Functions

* `createEscrow(uint256 agreementId, bytes32 valueHash, DeliverableType deliverableType, uint256 expirationDays)`: `external payable`
    * Creates a new escrow linked to an existing agreement.
    * For Crypto or Hybrid types, requires ETH to be sent with the transaction.
    * Parameters:
        - `agreementId`: ID of the existing agreement
        - `valueHash`: Hash of deliverable description (use `keccak256(deliverableDetails)`)
        - `deliverableType`: Type (0=Crypto, 1=BankTransfer, 2=FileDeliverable, 3=PhysicalItem, 4=Service, 5=Hybrid)
        - `expirationDays`: Number of days until escrow expires (1-365)

* `joinEscrow(uint256 escrowId)`: `external`
    * Allows the other party of the agreement to join a pending escrow.
    * Changes escrow status from Pending to Active.

* `submitProof(uint256 escrowId, bytes32 proofHash)`: `external`
    * Submit proof of delivery/completion.
    * `proofHash`: Hash of proof data (bank receipt, file CID, delivery confirmation, etc.)

* `confirmCompletion(uint256 escrowId)`: `external`
    * Confirm that the deliverable has been completed satisfactorily.
    * When both parties confirm, funds are automatically released.

* `raiseDispute(uint256 escrowId)`: `external`
    * Raise a dispute for an active escrow.
    * Changes escrow status to Disputed.

* `proposeArbiter(uint256 escrowId, address arbiterAddress)`: `external`
    * Propose an arbiter to resolve a dispute.
    * Auto-approves for the proposer.
    * When both parties approve, arbiter is activated.

* `approveArbiter(uint256 escrowId)`: `external`
    * Approve a proposed arbiter.
    * Required from the non-proposing party.

* `resolveDispute(uint256 escrowId, string decision)`: `external`
    * Arbiter-only function to resolve a dispute.
    * `decision`: "release" (to participant), "refund" (to initiator), or "split" (50/50)
    * Deducts 1% arbiter fee from the escrow amount.

* `cancelEscrow(uint256 escrowId)`: `external`
    * Initiator can cancel a Pending escrow.
    * Automatically refunds any locked ETH.

* `handleExpiredEscrow(uint256 escrowId)`: `external`
    * Anyone can call this for expired escrows.
    * Refunds ETH to initiator.

### Escrow View Functions

* `getEscrow(uint256 escrowId)`: `external view returns (EscrowData)`
    * Returns complete escrow details.

* `getEscrowsByUser(address user)`: `external view returns (uint256[])`
    * Returns array of escrow IDs for a user.

* `getEscrowsForAgreement(uint256 agreementId)`: `external view returns (uint256[])`
    * Returns array of escrow IDs for an agreement.

* `isEscrowExpired(uint256 escrowId)`: `external view returns (bool)`
    * Checks if an escrow has expired.

### Oracle Verification Functions

The contract includes an oracle system for automatic verification of FileDeliverable and Service escrows.

* `authorizeOracle(address oracle, bool authorized)`: `external onlyOwner`
    * Authorizes or deauthorizes an oracle address.
    * Only the contract owner can manage oracle permissions.
    * Parameters:
        - `oracle`: The address of the oracle service
        - `authorized`: true to authorize, false to revoke

* `submitOracleVerification(uint256 escrowId, bool verified, bytes32 proofHash)`: `external`
    * Allows an authorized oracle to submit automated verification results.
    * Automatically confirms completion for the party that submitted proof if verified.
    * Only callable by authorized oracle addresses.
    * Parameters:
        - `escrowId`: ID of the escrow being verified
        - `verified`: Whether the oracle successfully verified the deliverable
        - `proofHash`: The proof hash that was verified
    * **Important**: Arbiter decisions always override oracle verification.

* `getOracleVerification(uint256 escrowId)`: `external view returns (bool verified, bytes32 verificationHash, uint256 verifiedAt)`
    * Returns oracle verification details for an escrow.
    * Returns:
        - `verified`: Whether oracle verified the deliverable
        - `verificationHash`: The proof hash that was verified
        - `verifiedAt`: Timestamp of verification

**Oracle Verification Flow:**
1. Party submits proof hash for FileDeliverable or Service escrow
2. Backend oracle service automatically triggered
3. IPFS verification (files) or AI verification (services) runs
4. If successful, oracle calls `submitOracleVerification()`
5. Smart contract auto-confirms for submitting party
6. If both parties confirm, escrow releases automatically

**Key Oracle Principles:**
- Automatic: Runs when proof is submitted for applicable types
- Advisory: Assists confirmation but doesn't control release
- Overridable: Arbiter decisions always supersede oracle verification
- Fail-safe: Oracle failures never block escrow completion

---

This project is a **Hardhat** environment. It provides a complete toolkit to compile, test, and deploy this smart contract.