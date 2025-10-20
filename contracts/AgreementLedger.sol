// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    AgreementLedger Token + Agreement System
    ----------------------------------------
    - Users receive free tokens when they first register.
    - Each time two users create an agreement, both pay a verification fee.
    - 80% of the verification fee goes to the dev wallet.
    - 20% of the verification fee is burned (reducing total supply).
    - Actual payment between users happens off-chain — tokens are only for verification.
*/

import "@openzeppelin/contracts/access/Ownable.sol";

contract AgreementLedger is Ownable {
    // ================
    // TOKEN VARIABLES
    // ================
    string public constant name = "Sabot Token";
    string public constant symbol = "SBT";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256[]) private agreementsByParty;

    // ================
    // AGREEMENT LOGIC
    // ================
    address public devWallet;

    uint256 public constant VERIFY_FEE = 10 * 10**18;
    uint256 public constant BURN_PERCENT = 20; // 20% burn of verification fee

    mapping(address => bool) public registered;

    struct Agreement {
        address partyA;
        address partyB;
        bytes32 details;       // hashed details or description
        uint256 timestamp;
    }

    Agreement[] public agreements;

    // ================
    // EVENTS
    // ================
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

    constructor(address _devWallet) Ownable (msg.sender) {
        devWallet = _devWallet;
        _mint(msg.sender, 1_000_000 * 10**18); // initial supply for owner/dev
    }

    // ==================================================
    // ERC20-LIKE INTERNAL FUNCTIONS
    // ==================================================
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

    // ==================================================
    // REGISTRATION
    // ==================================================
    function registerUser() external {
        require(!registered[msg.sender], "Already registered");
        registered[msg.sender] = true;

        uint256 reward = 100 * 10**18; // free tokens for first-time user
        _mint(msg.sender, reward);

        emit Registered(msg.sender, reward);
    }

    // ==================================================
    // AGREEMENT CREATION
    // ==================================================
    function createAgreement(address otherParty, bytes32 detailsHash) external {
        require(registered[msg.sender], "Sender not registered");
        require(registered[otherParty], "Other party not registered");
        require(msg.sender != otherParty, "Cannot agree with self");

        _processVerificationFee(msg.sender);
        _processVerificationFee(otherParty);

        agreements.push(Agreement({
            partyA: msg.sender,
            partyB: otherParty,
            details: detailsHash,
            timestamp: block.timestamp
        }));
        uint256 id = agreements.length - 1;

        // Index the agreement for both parties
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

        // Burn 20%
        _burn(user, burnAmount);

        // Send 80% to dev wallet
        _transfer(user, devWallet, devAmount);
    }

    // ==================================================
    // ADMIN
    // ==================================================
    function setDevWallet(address _new) external onlyOwner {
        devWallet = _new;
    }

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

}
