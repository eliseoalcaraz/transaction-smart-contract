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

contract AgreementLedger is Ownable {
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
    function registerUser() external {
        require(!registered[msg.sender], "Already registered");
        registered[msg.sender] = true;

        uint256 reward = 100 * 10**18;
        _mint(msg.sender, reward);

        emit Registered(msg.sender, reward);
    }

    // =========================
    // AGREEMENTS
    // =========================
    function createAgreement(address otherParty, bytes32 detailsHash) external {
        require(registered[msg.sender], "Sender not registered");
        require(registered[otherParty], "Other party not registered");
        require(msg.sender != otherParty, "Cannot agree with self");

        _processVerificationFee(msg.sender);
        _processVerificationFee(otherParty);

        Agreement memory newAgreement = Agreement({
            partyA: msg.sender,
            partyB: otherParty,
            details: detailsHash,
            timestamp: block.timestamp
        });

        agreements.push(newAgreement);
        uint256 id = agreements.length - 1;

        agreementsByParty[msg.sender].push(id);
        agreementsByParty[otherParty].push(id);

        emit AgreementCreated(
            msg.sender,
            otherParty,
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
    function reportIssue(uint256 agreementId, address reportedParty, bytes32 reason) external {
        require(agreementId < agreements.length, "Invalid agreement ID");
        Agreement storage agreement = agreements[agreementId];

        require(msg.sender == agreement.partyA || msg.sender == agreement.partyB, "Not part of the agreement");
        require(reportedParty == agreement.partyA || reportedParty == agreement.partyB, "Reported party not in agreement");
        require(msg.sender != reportedParty, "Cannot report yourself");

        reports.push(Report({
            reporter: msg.sender,
            reportedParty: reportedParty,
            agreementId: agreementId,
            reason: reason,
            timestamp: block.timestamp
        }));

        uint256 reportId = reports.length - 1;
        reportsByReporter[msg.sender].push(reportId);
        reportsAgainstParty[reportedParty].push(reportId);

        emit ReportCreated(msg.sender, reportedParty, agreementId, reason, block.timestamp);
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
}
