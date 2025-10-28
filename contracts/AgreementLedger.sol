// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    AgreementLedger Token + Agreement + Reporting System
    ----------------------------------------------------
    - Users receive free tokens when they first register.
    - Each time two users create an agreement, both pay a verification fee.
    - 80% of the verification fee goes to the dev wallet.
    - 20% of the verification fee is burned.
    - Users can report other parties for a specific agreement.
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AgreementLedger is Ownable, ReentrancyGuard {
    // =========================
    // TOKEN VARIABLES
    // =========================
    string public constant name = "Sabot Token";
    string public constant symbol = "SBT";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // =========================
    // AGREEMENT LOGIC
    // =========================
    address public devWallet;

    uint256 public constant VERIFY_FEE = 10 * 10**18;
    uint256 public constant BURN_PERCENT = 20; // 20% burn of verification fee

    mapping(address => bool) public registered;
    mapping(address => uint256[]) private agreementsByParty;

    struct Agreement {
        address partyA;
        address partyB;
        bytes32 details;   // hashed details or description
        uint256 timestamp;
    }

    Agreement[] public agreements;

    // =========================
    // REPORT LOGIC
    // =========================
    struct Report {
        address reporter;
        address reportedParty;
        uint256 agreementId;
        bytes32 reason;
        uint256 timestamp;
    }

    Report[] public reports;
    mapping(address => uint256[]) private reportsByReporter;
    mapping(address => uint256[]) private reportsAgainstParty;

    // =========================
    // ESCROW LOGIC
    // =========================
    enum EscrowStatus { Pending, Active, Completed, Disputed, Cancelled, Expired }
    
    enum DeliverableType { 
        Crypto,              // ETH/crypto funds locked in contract
        BankTransfer,        // Digital bank transfer (proof hash)
        FileDeliverable,     // File delivery (IPFS/file hash)
        PhysicalItem,        // Physical item (description hash)
        Service,             // Service delivery (completion proof hash)
        Hybrid               // Multiple types combined
    }

    struct EscrowData {
        uint256 agreementId;
        address initiator;
        address participant;
        uint256 ethAmount;           // ETH locked (0 for non-crypto)
        bytes32 valueHash;           // Hash for non-crypto deliverables
        bytes32 proofHash;           // Hash of delivery proof (bank receipt, file CID, etc.)
        DeliverableType deliverableType;
        bool initiatorConfirmed;
        bool participantConfirmed;
        bool initiatorProofSubmitted;
        bool participantProofSubmitted;
        bool disputed;
        address proposedArbiter;
        bool initiatorApprovedArbiter;
        bool participantApprovedArbiter;
        address activeArbiter;
        uint256 createdAt;
        uint256 expiresAt;
        EscrowStatus status;
    }

    mapping(uint256 => EscrowData) public escrows;
    uint256 public escrowCount;
    mapping(address => uint256[]) private escrowsByUser;
    mapping(uint256 => uint256[]) private escrowsByAgreement;

    uint256 public constant ESCROW_FEE_PERCENT = 2;
    uint256 public constant ARBITER_FEE_PERCENT = 1;

    // Oracle whitelist (backend service addresses)
    mapping(address => bool) public authorizedOracles;
    
    // Oracle verification data per escrow
    mapping(uint256 => bool) public oracleVerified;
    mapping(uint256 => bytes32) public oracleVerificationHash;
    mapping(uint256 => uint256) public oracleVerifiedAt;

    // =========================
    // EVENTS
    // =========================
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Registered(address indexed user, uint256 reward);
    event AgreementCreated(
        address indexed partyA,
        address indexed partyB,
        uint256 totalFee,
        uint256 burned,
        uint256 toDev,
        bytes32 details,
        uint256 timestamp
    );
    event ReportCreated(
        address indexed reporter,
        address indexed reportedParty,
        uint256 agreementId,
        bytes32 reason,
        uint256 timestamp
    );
    event EscrowCreated(
        uint256 indexed escrowId,
        uint256 indexed agreementId,
        address indexed initiator,
        uint256 ethAmount,
        bytes32 valueHash,
        DeliverableType deliverableType,
        uint256 expiresAt
    );
    event EscrowJoined(uint256 indexed escrowId, address indexed participant);
    event EscrowConfirmed(uint256 indexed escrowId, address indexed confirmer, bool isInitiator);
    event ProofSubmitted(uint256 indexed escrowId, address indexed submitter, bytes32 proofHash, bool isInitiator);
    event EscrowReleased(uint256 indexed escrowId, address indexed recipient, uint256 amount);
    event EscrowDisputed(uint256 indexed escrowId, address indexed disputer);
    event ArbiterProposed(uint256 indexed escrowId, address indexed proposer, address indexed arbiter);
    event ArbiterApproved(uint256 indexed escrowId, address indexed approver);
    event ArbiterActivated(uint256 indexed escrowId, address indexed arbiter);
    event EscrowResolved(uint256 indexed escrowId, address indexed recipient, uint256 amount, string decision);
    event EscrowCancelled(uint256 indexed escrowId, uint256 refundAmount);
    event OracleAuthorized(address indexed oracle, bool authorized);
    event OracleVerificationSubmitted(
        uint256 indexed escrowId, 
        address indexed oracle, 
        bool verified, 
        bytes32 proofHash
    );

    constructor(address _devWallet) Ownable(msg.sender) {
        devWallet = _devWallet;
        _mint(msg.sender, 1_000_000 * 10**18); // initial supply for owner/dev
    }

    // =========================
    // ERC20-LIKE FUNCTIONS
    // =========================
    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "Insufficient balance");
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(allowance[from][msg.sender] >= value, "Not allowed");
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        require(balanceOf[from] >= value, "Not enough to burn");
        unchecked {
            balanceOf[from] -= value;
            totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }

    // =========================
    // REGISTRATION
    // =========================
    function registerUser(address user) external onlyOwner {
        require(user != address(0), "Invalid user address");
        require(!registered[user], "Already registered");

        registered[user] = true;

        uint256 reward = 100 * 10**18;
        _mint(user, reward);

        emit Registered(user, reward);
    }


    // =========================
    // AGREEMENTS
    // =========================
    function createAgreement(address partyA, address partyB, bytes32 detailsHash) external onlyOwner {
        require(registered[partyA], "Party A not registered");
        require(registered[partyB], "Party B not registered");
        require(partyA != partyB, "Cannot agree with self");

        _processVerificationFee(partyA);
        _processVerificationFee(partyB);

        Agreement memory newAgreement = Agreement({
            partyA: partyA,
            partyB: partyB,
            details: detailsHash,
            timestamp: block.timestamp
        });

        agreements.push(newAgreement);
        uint256 id = agreements.length - 1;

        agreementsByParty[partyA].push(id);
        agreementsByParty[partyB].push(id);

        emit AgreementCreated(
            partyA,
            partyB,
            VERIFY_FEE * 2,
            (VERIFY_FEE * 2 * BURN_PERCENT) / 100,
            (VERIFY_FEE * 2 * (100 - BURN_PERCENT)) / 100,
            detailsHash,
            block.timestamp
        );
    }

    function _processVerificationFee(address user) internal {
        require(balanceOf[user] >= VERIFY_FEE, "Insufficient tokens for verification fee");

        uint256 burnAmount = (VERIFY_FEE * BURN_PERCENT) / 100;
        uint256 devAmount = VERIFY_FEE - burnAmount;

        _burn(user, burnAmount);
        _transfer(user, devWallet, devAmount);
    }

    // =========================
    // REPORTS
    // =========================
    function reportIssue(uint256 agreementId, address reporterParty, address reportedParty, bytes32 reason) external onlyOwner {
        require(agreementId < agreements.length, "Invalid agreement ID");
        Agreement storage agreement = agreements[agreementId];

        require(reporterParty == agreement.partyA || reporterParty == agreement.partyB, "Not part of the agreement");
        require(reportedParty == agreement.partyA || reportedParty == agreement.partyB, "Reported party not in agreement");
        require(reporterParty != reportedParty, "Cannot report yourself");

        reports.push(Report({
            reporter: reporterParty,
            reportedParty: reportedParty,
            agreementId: agreementId,
            reason: reason,
            timestamp: block.timestamp
        }));

        uint256 reportId = reports.length - 1;
        reportsByReporter[reporterParty].push(reportId);
        reportsAgainstParty[reportedParty].push(reportId);

        emit ReportCreated(reporterParty, reportedParty, agreementId, reason, block.timestamp);
    }

    // =========================
    // VIEW FUNCTIONS
    // =========================
    function getAgreements() external view returns (Agreement[] memory) {
        return agreements;
    }

    function getAgreementsByParty(address party) external view returns (Agreement[] memory) {
        uint256[] storage ids = agreementsByParty[party];
        Agreement[] memory result = new Agreement[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = agreements[ids[i]];
        }

        return result;
    }

    function getReportsByReporter(address reporter) external view returns (Report[] memory) {
        uint256[] storage ids = reportsByReporter[reporter];
        Report[] memory result = new Report[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = reports[ids[i]];
        }

        return result;
    }

    function getReportsAgainstParty(address party) external view returns (Report[] memory) {
        uint256[] storage ids = reportsAgainstParty[party];
        Report[] memory result = new Report[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = reports[ids[i]];
        }

        return result;
    }

    // =========================
    // ADMIN
    // =========================
    function setDevWallet(address _new) external onlyOwner {
        devWallet = _new;
    }

    // =========================
    // ESCROW FUNCTIONS
    // =========================
    
    /**
     * @dev Create escrow for an agreement
     * @param agreementId The agreement to link escrow to
     * @param valueHash Hash of the deliverable description/details
     * @param deliverableType Type of deliverable
     * @param expirationDays Days until escrow expires
     */
    function createEscrow(
        uint256 agreementId,
        bytes32 valueHash,
        DeliverableType deliverableType,
        uint256 expirationDays
    ) external payable {
        require(agreementId < agreements.length, "Invalid agreement ID");
        require(expirationDays > 0 && expirationDays <= 365, "Invalid expiration period");
        require(valueHash != bytes32(0), "Value hash required");
        
        // For crypto type, require ETH to be sent
        if (deliverableType == DeliverableType.Crypto || deliverableType == DeliverableType.Hybrid) {
            require(msg.value > 0, "ETH required for crypto deliverable");
        }
        
        Agreement storage agreement = agreements[agreementId];
        require(
            msg.sender == agreement.partyA || msg.sender == agreement.partyB,
            "Not party to agreement"
        );
        
        uint256 escrowId = escrowCount++;
        uint256 expiresAt = block.timestamp + (expirationDays * 1 days);
        
        escrows[escrowId] = EscrowData({
            agreementId: agreementId,
            initiator: msg.sender,
            participant: address(0),
            ethAmount: msg.value,
            valueHash: valueHash,
            proofHash: bytes32(0),
            deliverableType: deliverableType,
            initiatorConfirmed: false,
            participantConfirmed: false,
            initiatorProofSubmitted: false,
            participantProofSubmitted: false,
            disputed: false,
            proposedArbiter: address(0),
            initiatorApprovedArbiter: false,
            participantApprovedArbiter: false,
            activeArbiter: address(0),
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            status: EscrowStatus.Pending
        });
        
        escrowsByUser[msg.sender].push(escrowId);
        escrowsByAgreement[agreementId].push(escrowId);
        
        emit EscrowCreated(
            escrowId,
            agreementId,
            msg.sender,
            msg.value,
            valueHash,
            deliverableType,
            expiresAt
        );
    }
    
    /**
     * @dev Join an existing escrow as participant
     * @param escrowId The escrow to join
     */
    function joinEscrow(uint256 escrowId) external {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(escrow.status == EscrowStatus.Pending, "Escrow not pending");
        require(escrow.participant == address(0), "Participant already set");
        require(msg.sender != escrow.initiator, "Cannot join own escrow");
        
        Agreement storage agreement = agreements[escrow.agreementId];
        require(
            msg.sender == agreement.partyA || msg.sender == agreement.partyB,
            "Not party to agreement"
        );
        
        escrow.participant = msg.sender;
        escrow.status = EscrowStatus.Active;
        
        escrowsByUser[msg.sender].push(escrowId);
        
        emit EscrowJoined(escrowId, msg.sender);
    }
    
    /**
     * @dev Submit proof of delivery/completion
     * @param escrowId The escrow ID
     * @param proofHash Hash of proof (bank receipt, file CID, delivery confirmation, etc.)
     */
    function submitProof(uint256 escrowId, bytes32 proofHash) external {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(escrow.status == EscrowStatus.Active, "Escrow not active");
        require(!escrow.disputed, "Escrow is disputed");
        require(proofHash != bytes32(0), "Proof hash required");
        require(
            msg.sender == escrow.initiator || msg.sender == escrow.participant,
            "Not party to escrow"
        );
        
        bool isInitiator = (msg.sender == escrow.initiator);
        
        if (isInitiator) {
            require(!escrow.initiatorProofSubmitted, "Proof already submitted");
            escrow.initiatorProofSubmitted = true;
        } else {
            require(!escrow.participantProofSubmitted, "Proof already submitted");
            escrow.participantProofSubmitted = true;
        }
        
        // Store the last submitted proof hash
        escrow.proofHash = proofHash;
        
        emit ProofSubmitted(escrowId, msg.sender, proofHash, isInitiator);
    }
    
    /**
     * @dev Confirm escrow completion
     * @param escrowId The escrow to confirm
     */
    function confirmCompletion(uint256 escrowId) external {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(escrow.status == EscrowStatus.Active, "Escrow not active");
        require(!escrow.disputed, "Escrow is disputed");
        require(
            msg.sender == escrow.initiator || msg.sender == escrow.participant,
            "Not party to escrow"
        );
        
        bool isInitiator = (msg.sender == escrow.initiator);
        
        if (isInitiator) {
            require(!escrow.initiatorConfirmed, "Already confirmed");
            escrow.initiatorConfirmed = true;
        } else {
            require(!escrow.participantConfirmed, "Already confirmed");
            escrow.participantConfirmed = true;
        }
        
        emit EscrowConfirmed(escrowId, msg.sender, isInitiator);
        
        // If both confirmed, release escrow
        if (escrow.initiatorConfirmed && escrow.participantConfirmed) {
            _releaseEscrow(escrowId);
        }
    }
    
    /**
     * @dev Dispute an escrow
     * @param escrowId The escrow to dispute
     */
    function raiseDispute(uint256 escrowId) external {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(escrow.status == EscrowStatus.Active, "Escrow not active");
        require(!escrow.disputed, "Already disputed");
        require(
            msg.sender == escrow.initiator || msg.sender == escrow.participant,
            "Not party to escrow"
        );
        
        escrow.disputed = true;
        escrow.status = EscrowStatus.Disputed;
        
        emit EscrowDisputed(escrowId, msg.sender);
    }
    
    /**
     * @dev Propose an arbiter for disputed escrow
     * @param escrowId The disputed escrow
     * @param arbiterAddress The arbiter address
     */
    function proposeArbiter(uint256 escrowId, address arbiterAddress) external {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(escrow.disputed, "Escrow not disputed");
        require(escrow.activeArbiter == address(0), "Arbiter already active");
        require(
            msg.sender == escrow.initiator || msg.sender == escrow.participant,
            "Not party to escrow"
        );
        require(
            arbiterAddress != escrow.initiator && arbiterAddress != escrow.participant,
            "Invalid arbiter"
        );
        require(arbiterAddress != address(0), "Invalid arbiter address");
        
        // Reset previous approvals if proposing new arbiter
        if (escrow.proposedArbiter != arbiterAddress) {
            escrow.initiatorApprovedArbiter = false;
            escrow.participantApprovedArbiter = false;
        }
        
        escrow.proposedArbiter = arbiterAddress;
        
        // Auto-approve for the proposer
        if (msg.sender == escrow.initiator) {
            escrow.initiatorApprovedArbiter = true;
        } else {
            escrow.participantApprovedArbiter = true;
        }
        
        emit ArbiterProposed(escrowId, msg.sender, arbiterAddress);
        emit ArbiterApproved(escrowId, msg.sender);
        
        // Check if both approved
        if (escrow.initiatorApprovedArbiter && escrow.participantApprovedArbiter) {
            escrow.activeArbiter = arbiterAddress;
            emit ArbiterActivated(escrowId, arbiterAddress);
        }
    }
    
    /**
     * @dev Approve proposed arbiter
     * @param escrowId The escrow ID
     */
    function approveArbiter(uint256 escrowId) external {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(escrow.disputed, "Escrow not disputed");
        require(escrow.proposedArbiter != address(0), "No arbiter proposed");
        require(escrow.activeArbiter == address(0), "Arbiter already active");
        require(
            msg.sender == escrow.initiator || msg.sender == escrow.participant,
            "Not party to escrow"
        );
        
        bool isInitiator = (msg.sender == escrow.initiator);
        
        if (isInitiator) {
            require(!escrow.initiatorApprovedArbiter, "Already approved");
            escrow.initiatorApprovedArbiter = true;
        } else {
            require(!escrow.participantApprovedArbiter, "Already approved");
            escrow.participantApprovedArbiter = true;
        }
        
        emit ArbiterApproved(escrowId, msg.sender);
        
        // If both approved, activate arbiter
        if (escrow.initiatorApprovedArbiter && escrow.participantApprovedArbiter) {
            escrow.activeArbiter = escrow.proposedArbiter;
            emit ArbiterActivated(escrowId, escrow.activeArbiter);
        }
    }
    
    /**
     * @dev Arbiter resolves dispute
     * @param escrowId The disputed escrow
     * @param decision "release", "refund", or "split"
     */
    function resolveDispute(
        uint256 escrowId,
        string calldata decision
    ) external nonReentrant {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(escrow.disputed, "Not disputed");
        require(escrow.activeArbiter != address(0), "No active arbiter");
        require(msg.sender == escrow.activeArbiter, "Only arbiter can resolve");
        require(escrow.status == EscrowStatus.Disputed, "Invalid status");
        
        escrow.status = EscrowStatus.Completed;
        
        // Only process ETH transfers for crypto or hybrid types
        if (escrow.ethAmount > 0) {
            uint256 arbiterFee = (escrow.ethAmount * ARBITER_FEE_PERCENT) / 100;
            uint256 remainingAmount = escrow.ethAmount - arbiterFee;
            
            // Transfer arbiter fee
            payable(escrow.activeArbiter).transfer(arbiterFee);
            
            bytes32 decisionHash = keccak256(bytes(decision));
            
            if (decisionHash == keccak256(bytes("release"))) {
                // Release to participant
                payable(escrow.participant).transfer(remainingAmount);
                emit EscrowResolved(escrowId, escrow.participant, remainingAmount, decision);
            } else if (decisionHash == keccak256(bytes("refund"))) {
                // Refund to initiator
                payable(escrow.initiator).transfer(remainingAmount);
                emit EscrowResolved(escrowId, escrow.initiator, remainingAmount, decision);
            } else if (decisionHash == keccak256(bytes("split"))) {
                // Split between both parties
                uint256 half = remainingAmount / 2;
                payable(escrow.initiator).transfer(half);
                payable(escrow.participant).transfer(remainingAmount - half);
                emit EscrowResolved(escrowId, escrow.initiator, half, "split-initiator");
                emit EscrowResolved(escrowId, escrow.participant, remainingAmount - half, "split-participant");
            } else {
                revert("Invalid decision");
            }
        } else {
            // For non-crypto escrows, just emit resolution event
            emit EscrowResolved(escrowId, address(0), 0, decision);
        }
    }
    
    /**
     * @dev Cancel escrow (only if pending)
     * @param escrowId The escrow to cancel
     */
    function cancelEscrow(uint256 escrowId) external nonReentrant {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(msg.sender == escrow.initiator, "Only initiator can cancel");
        require(escrow.status == EscrowStatus.Pending, "Can only cancel pending escrow");
        
        escrow.status = EscrowStatus.Cancelled;
        
        uint256 refundAmount = escrow.ethAmount;
        
        if (refundAmount > 0) {
            escrow.ethAmount = 0;
            payable(escrow.initiator).transfer(refundAmount);
        }
        
        emit EscrowCancelled(escrowId, refundAmount);
    }
    
    /**
     * @dev Handle expired escrows (can be called by anyone)
     * @param escrowId The escrow to check
     */
    function handleExpiredEscrow(uint256 escrowId) external nonReentrant {
        require(escrowId < escrowCount, "Invalid escrow ID");
        EscrowData storage escrow = escrows[escrowId];
        
        require(block.timestamp > escrow.expiresAt, "Not expired");
        require(
            escrow.status == EscrowStatus.Active || escrow.status == EscrowStatus.Pending,
            "Invalid status"
        );
        
        escrow.status = EscrowStatus.Expired;
        
        uint256 refundAmount = escrow.ethAmount;
        
        if (refundAmount > 0) {
            escrow.ethAmount = 0;
            payable(escrow.initiator).transfer(refundAmount);
        }
        
        emit EscrowCancelled(escrowId, refundAmount);
    }
    
    /**
     * @dev Internal function to release escrow funds
     * @param escrowId The escrow to release
     */
    function _releaseEscrow(uint256 escrowId) internal nonReentrant {
        EscrowData storage escrow = escrows[escrowId];
        
        require(
            escrow.initiatorConfirmed && escrow.participantConfirmed,
            "Not fully confirmed"
        );
        
        escrow.status = EscrowStatus.Completed;
        
        // Only process ETH transfers for crypto or hybrid types
        if (escrow.ethAmount > 0) {
            uint256 platformFee = (escrow.ethAmount * ESCROW_FEE_PERCENT) / 100;
            uint256 amountToParticipant = escrow.ethAmount - platformFee;
            
            // Transfer platform fee to dev wallet
            payable(devWallet).transfer(platformFee);
            
            // Transfer remaining amount to participant
            payable(escrow.participant).transfer(amountToParticipant);
            
            emit EscrowReleased(escrowId, escrow.participant, amountToParticipant);
        } else {
            // For non-crypto escrows, just emit completion event
            emit EscrowReleased(escrowId, escrow.participant, 0);
        }
    }
    
    // =========================
    // ESCROW VIEW FUNCTIONS
    // =========================
    
    /**
     * @dev Get escrow details
     * @param escrowId The escrow ID
     */
    function getEscrow(uint256 escrowId) external view returns (EscrowData memory) {
        require(escrowId < escrowCount, "Invalid escrow ID");
        return escrows[escrowId];
    }
    
    /**
     * @dev Get all escrows for a user
     * @param user The user address
     */
    function getEscrowsByUser(address user) external view returns (uint256[] memory) {
        return escrowsByUser[user];
    }
    
    /**
     * @dev Get escrows for an agreement
     * @param agreementId The agreement ID
     */
    function getEscrowsForAgreement(uint256 agreementId) external view returns (uint256[] memory) {
        return escrowsByAgreement[agreementId];
    }
    
    /**
     * @dev Check if escrow is expired
     * @param escrowId The escrow ID
     */
    function isEscrowExpired(uint256 escrowId) external view returns (bool) {
        require(escrowId < escrowCount, "Invalid escrow ID");
        return block.timestamp > escrows[escrowId].expiresAt;
    }

    // =========================
    // ORACLE VERIFICATION
    // =========================
    
    /**
     * @dev Authorize or deauthorize an oracle address
     * @param oracle The oracle address to authorize/deauthorize
     * @param authorized True to authorize, false to deauthorize
     */
    function authorizeOracle(address oracle, bool authorized) external onlyOwner {
        require(oracle != address(0), "Invalid oracle address");
        authorizedOracles[oracle] = authorized;
        emit OracleAuthorized(oracle, authorized);
    }

    /**
     * @dev Oracle submits verification result for an escrow
     * @param escrowId The escrow ID
     * @param verified Whether the oracle verified the deliverable
     * @param proofHash The proof hash being verified
     */
    function submitOracleVerification(
        uint256 escrowId,
        bool verified,
        bytes32 proofHash
    ) external {
        require(authorizedOracles[msg.sender], "Not authorized oracle");
        require(escrowId < escrowCount, "Invalid escrow");
        
        EscrowData storage escrow = escrows[escrowId];
        require(escrow.status == EscrowStatus.Active, "Escrow not active");
        
        oracleVerified[escrowId] = verified;
        oracleVerificationHash[escrowId] = proofHash;
        oracleVerifiedAt[escrowId] = block.timestamp;
        
        emit OracleVerificationSubmitted(escrowId, msg.sender, verified, proofHash);
        
        // If oracle verified, auto-confirm for the party that submitted proof
        // This is advisory - can still be disputed and arbiter can override
        if (verified) {
            // Determine which party submitted proof based on proof submission status
            if (escrow.initiatorProofSubmitted && !escrow.initiatorConfirmed) {
                escrow.initiatorConfirmed = true;
                emit EscrowConfirmed(escrowId, escrow.initiator, true);
            } else if (escrow.participantProofSubmitted && !escrow.participantConfirmed) {
                escrow.participantConfirmed = true;
                emit EscrowConfirmed(escrowId, escrow.participant, false);
            }
            
            // Auto-release if both confirmed
            if (escrow.initiatorConfirmed && escrow.participantConfirmed) {
                _releaseEscrow(escrowId);
            }
        }
    }
    
    /**
     * @dev Get oracle verification details for an escrow
     * @param escrowId The escrow ID
     */
    function getOracleVerification(uint256 escrowId) external view returns (
        bool verified,
        bytes32 verificationHash,
        uint256 verifiedAt
    ) {
        require(escrowId < escrowCount, "Invalid escrow ID");
        return (
            oracleVerified[escrowId],
            oracleVerificationHash[escrowId],
            oracleVerifiedAt[escrowId]
        );
    }
}
