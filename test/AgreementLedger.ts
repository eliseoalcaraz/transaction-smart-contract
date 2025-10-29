import { expect } from "chai";
import { network } from "hardhat";
import type { Signer, Contract, BigNumberish } from "ethers";
const { ethers } = await network.connect();


describe("AgreementLedger", function () {
  let ledger: Contract;
  let owner: Signer;
  let devWallet: Signer;
  let user1: Signer;
  let user2: Signer;
  let user3: Signer;
  
  const initialMint: BigNumberish = ethers.parseEther("1000000");
  const registerReward: BigNumberish = ethers.parseEther("100");
  const verifyFee: BigNumberish = ethers.parseEther("10");
  const burnPercent = 20n;

  beforeEach(async function () {
    [owner, devWallet, user1, user2, user3] = await ethers.getSigners();

    const LedgerFactory = await ethers.getContractFactory("AgreementLedger");
    ledger = await LedgerFactory.deploy(devWallet.address);
    await ledger.waitForDeployment();
  });

  it("should set initial supply for owner", async function () {
    const balance = await ledger.balanceOf(owner.address);
    expect(balance).to.equal(initialMint);
  });

  it("should allow owner to register user and mint reward", async function () {
    await ledger.connect(owner).registerUser(user1.address);

    const balance = await ledger.balanceOf(user1.address);
    expect(balance).to.equal(registerReward);
    expect(await ledger.registered(user1.address)).to.be.true;
  });

  it("should revert if non-owner tries to register a user", async function () {
    await expect(
      ledger.connect(user1).registerUser(user2.address)
    ).to.be.revertedWithCustomError(ledger, "OwnableUnauthorizedAccount");
  });

  it("should create agreement and deduct verification fees correctly", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);

    const detailsHash = ethers.keccak256(
      ethers.toUtf8Bytes("Agreement between user1 and user2")
    );

    await ledger.connect(owner).createAgreement(user1.address, user2.address, detailsHash);

    const agreements = await ledger.getAgreements();
    expect(agreements.length).to.equal(1);
    expect(agreements[0].partyA).to.equal(user1.address);
    expect(agreements[0].partyB).to.equal(user2.address);
    expect(agreements[0].details).to.equal(detailsHash);

    const burnAmount = (verifyFee * burnPercent) / 100n;
    const devAmount = verifyFee - burnAmount;

    const expectedUserBalance = registerReward - verifyFee;
    const expectedDevBalance = devAmount * 2n;

    const user1Balance = await ledger.balanceOf(user1.address);
    const user2Balance = await ledger.balanceOf(user2.address);
    const devBalance = await ledger.balanceOf(devWallet.address);

    expect(user1Balance).to.equal(expectedUserBalance);
    expect(user2Balance).to.equal(expectedUserBalance);
    expect(devBalance).to.equal(expectedDevBalance);

    const totalSupply = await ledger.totalSupply();
    const expectedTotalSupply =
      initialMint + registerReward * 2n - burnAmount * 2n;
    expect(totalSupply).to.equal(expectedTotalSupply);
  });

  it("should allow owner to report an issue with hashed reason", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
    await ledger.connect(owner).createAgreement(user1.address, user2.address, detailsHash);

    const reason = ethers.keccak256(ethers.toUtf8Bytes("Did not deliver on time"));

    await ledger.connect(owner).reportIssue(0, user1.address, user2.address, reason);

    const reports = await ledger.getReportsByReporter(user1.address);
    expect(reports.length).to.equal(1);
    expect(reports[0].reporter).to.equal(user1.address);
    expect(reports[0].reportedParty).to.equal(user2.address);
    expect(reports[0].reason).to.equal(reason);

    const reportsAgainst = await ledger.getReportsAgainstParty(user2.address);
    expect(reportsAgainst.length).to.equal(1);
    expect(reportsAgainst[0].reason).to.equal(reason);
  });

  it("should revert if non-owner tries to create agreement", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Unauthorized attempt"));

    await expect(
      ledger.connect(user1).createAgreement(user1.address, user2.address, detailsHash)
    ).to.be.revertedWithCustomError(ledger, "OwnableUnauthorizedAccount");
  });

  it("should revert if non-owner tries to report issue", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
    await ledger.connect(owner).createAgreement(user1.address, user2.address, detailsHash);

    const reason = ethers.keccak256(ethers.toUtf8Bytes("Unauthorized report"));

    await expect(
      ledger.connect(user1).reportIssue(0, user1.address, user2.address, reason)
    ).to.be.revertedWithCustomError(ledger, "OwnableUnauthorizedAccount");
  });

  it("should retrieve multiple reports correctly", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);
    await ledger.connect(owner).registerUser(user3.address);

    const detailsHash1 = ethers.keccak256(ethers.toUtf8Bytes("A1"));
    const detailsHash2 = ethers.keccak256(ethers.toUtf8Bytes("A2"));

    await ledger.connect(owner).createAgreement(user1.address, user2.address, detailsHash1);
    await ledger.connect(owner).createAgreement(user2.address, user3.address, detailsHash2);

    const reason1 = ethers.keccak256(ethers.toUtf8Bytes("Issue 1"));
    const reason2 = ethers.keccak256(ethers.toUtf8Bytes("Issue 2"));

    await ledger.connect(owner).reportIssue(0, user1.address, user2.address, reason1);
    await ledger.connect(owner).reportIssue(1, user2.address, user3.address, reason2);

    const reportsAgainstUser2 = await ledger.getReportsAgainstParty(user2.address);
    expect(reportsAgainstUser2.length).to.equal(1);
    expect(reportsAgainstUser2[0].reason).to.equal(reason1);

    const reportsAgainstUser3 = await ledger.getReportsAgainstParty(user3.address);
    expect(reportsAgainstUser3.length).to.equal(1);
    expect(reportsAgainstUser3[0].reason).to.equal(reason2);

    const reportsAgainstUser1 = await ledger.getReportsAgainstParty(user1.address);
    expect(reportsAgainstUser1.length).to.equal(0);
  });

  it("should prevent reporting if reporter not in agreement", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);
    await ledger.connect(owner).registerUser(user3.address);

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
    await ledger.connect(owner).createAgreement(user1.address, user2.address, detailsHash);

    const reason = ethers.keccak256(ethers.toUtf8Bytes("Bad behavior"));

    await expect(
      ledger.connect(owner).reportIssue(0, user3.address, user2.address, reason)
    ).to.be.revertedWith("Not part of the agreement");
  });

  it("should prevent self-reporting", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
    await ledger.connect(owner).createAgreement(user1.address, user2.address, detailsHash);

    const reason = ethers.keccak256(ethers.toUtf8Bytes("Self report"));

    await expect(
      ledger.connect(owner).reportIssue(0, user1.address, user1.address, reason)
    ).to.be.revertedWith("Cannot report yourself");
  });

  it("should retrieve agreements by party", async function () {
    await ledger.connect(owner).registerUser(user1.address);
    await ledger.connect(owner).registerUser(user2.address);

    const hash1 = ethers.keccak256(ethers.toUtf8Bytes("A1"));
    const hash2 = ethers.keccak256(ethers.toUtf8Bytes("A2"));

    await ledger.connect(owner).createAgreement(user1.address, user2.address, hash1);
    await ledger.connect(owner).createAgreement(user1.address, user2.address, hash2);

    const user1Agreements = await ledger.getAgreementsByParty(user1.address);
    expect(user1Agreements.length).to.equal(2);
    expect(user1Agreements[0].details).to.equal(hash1);
    expect(user1Agreements[1].details).to.equal(hash2);
  });

  // =========================
  // ESCROW TESTS
  // =========================

  describe("Escrow Functions", function () {
    let agreementId: number;
    let valueHash: string;

    beforeEach(async function () {
      // Setup: Create an agreement for escrow tests
      await ledger.connect(user1).registerUser();
      await ledger.connect(user2).registerUser();

      const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Test Agreement"));
      await ledger.connect(user1).createAgreement(user2.address, detailsHash);

      agreementId = 0;
      valueHash = ethers.keccak256(ethers.toUtf8Bytes("Deliverable description"));
    });

    describe("createEscrow", function () {
      it("should create crypto escrow with ETH", async function () {
        const escrowAmount = ethers.parseEther("1.0");
        const expirationDays = 30;

        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          0, // Crypto type
          expirationDays,
          { value: escrowAmount }
        );

        const escrow = await ledger.getEscrow(0);
        expect(escrow.agreementId).to.equal(agreementId);
        expect(escrow.initiator).to.equal(user1.address);
        expect(escrow.ethAmount).to.equal(escrowAmount);
        expect(escrow.valueHash).to.equal(valueHash);
        expect(escrow.deliverableType).to.equal(0); // Crypto
        expect(escrow.status).to.equal(0); // Pending
      });

      it("should create bank transfer escrow without ETH", async function () {
        const expirationDays = 30;

        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          1, // BankTransfer type
          expirationDays
        );

        const escrow = await ledger.getEscrow(0);
        expect(escrow.ethAmount).to.equal(0);
        expect(escrow.deliverableType).to.equal(1); // BankTransfer
      });

      it("should create file deliverable escrow", async function () {
        const fileHash = ethers.keccak256(ethers.toUtf8Bytes("QmFileHashIPFS"));

        await ledger.connect(user1).createEscrow(
          agreementId,
          fileHash,
          2, // FileDeliverable type
          30
        );

        const escrow = await ledger.getEscrow(0);
        expect(escrow.deliverableType).to.equal(2); // FileDeliverable
        expect(escrow.valueHash).to.equal(fileHash);
      });

      it("should revert if creating crypto escrow without ETH", async function () {
        await expect(
          ledger.connect(user1).createEscrow(agreementId, valueHash, 0, 30)
        ).to.be.revertedWith("ETH required for crypto deliverable");
      });

      it("should revert if not party to agreement", async function () {
        await ledger.connect(user3).registerUser();

        await expect(
          ledger.connect(user3).createEscrow(
            agreementId,
            valueHash,
            1,
            30
          )
        ).to.be.revertedWith("Not party to agreement");
      });

      it("should add escrow to user's list", async function () {
        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          1,
          30
        );

        const userEscrows = await ledger.getEscrowsByUser(user1.address);
        expect(userEscrows.length).to.equal(1);
        expect(userEscrows[0]).to.equal(0);
      });
    });

    describe("joinEscrow", function () {
      beforeEach(async function () {
        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          1, // BankTransfer
          30
        );
      });

      it("should allow participant to join escrow", async function () {
        await ledger.connect(user2).joinEscrow(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.participant).to.equal(user2.address);
        expect(escrow.status).to.equal(1); // Active
      });

      it("should revert if not party to agreement", async function () {
        await ledger.connect(user3).registerUser();

        await expect(
          ledger.connect(user3).joinEscrow(0)
        ).to.be.revertedWith("Not party to agreement");
      });

      it("should revert if initiator tries to join own escrow", async function () {
        await expect(
          ledger.connect(user1).joinEscrow(0)
        ).to.be.revertedWith("Cannot join own escrow");
      });

      it("should add escrow to participant's list", async function () {
        await ledger.connect(user2).joinEscrow(0);

        const userEscrows = await ledger.getEscrowsByUser(user2.address);
        expect(userEscrows.length).to.equal(1);
      });
    });

    describe("submitProof", function () {
      beforeEach(async function () {
        await ledger.connect(user1).createEscrow(agreementId, valueHash, 1, 30);
        await ledger.connect(user2).joinEscrow(0);
      });

      it("should allow initiator to submit proof", async function () {
        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("Bank receipt proof"));

        await ledger.connect(user1).submitProof(0, proofHash);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.initiatorProofSubmitted).to.be.true;
        expect(escrow.proofHash).to.equal(proofHash);
      });

      it("should allow participant to submit proof", async function () {
        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("File CID: QmXYZ"));

        await ledger.connect(user2).submitProof(0, proofHash);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.participantProofSubmitted).to.be.true;
      });

      it("should revert if not party to escrow", async function () {
        await ledger.connect(user3).registerUser();
        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("Proof"));

        await expect(
          ledger.connect(user3).submitProof(0, proofHash)
        ).to.be.revertedWith("Not party to escrow");
      });
    });

    describe("confirmCompletion", function () {
      beforeEach(async function () {
        const escrowAmount = ethers.parseEther("1.0");
        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          0, // Crypto
          30,
          { value: escrowAmount }
        );
        await ledger.connect(user2).joinEscrow(0);
      });

      it("should allow initiator to confirm", async function () {
        await ledger.connect(user1).confirmCompletion(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.initiatorConfirmed).to.be.true;
      });

      it("should allow participant to confirm", async function () {
        await ledger.connect(user2).confirmCompletion(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.participantConfirmed).to.be.true;
      });

      it("should release escrow when both confirm", async function () {
        const escrowAmount = ethers.parseEther("1.0");
        const platformFee = (escrowAmount * 2n) / 100n; // 2%
        const expectedAmount = escrowAmount - platformFee;

        const participantBalanceBefore = await ethers.provider.getBalance(user2.address);

        await ledger.connect(user1).confirmCompletion(0);
        const tx = await ledger.connect(user2).confirmCompletion(0);
        const receipt = await tx.wait();

        const gasUsed = receipt.gasUsed * receipt.gasPrice;

        const escrow = await ledger.getEscrow(0);
        expect(escrow.status).to.equal(2); // Completed

        const participantBalanceAfter = await ethers.provider.getBalance(user2.address);
        const balanceIncrease = participantBalanceAfter - participantBalanceBefore + gasUsed;

        expect(balanceIncrease).to.be.closeTo(expectedAmount, ethers.parseEther("0.001"));
      });

      it("should revert if already confirmed", async function () {
        await ledger.connect(user1).confirmCompletion(0);

        await expect(
          ledger.connect(user1).confirmCompletion(0)
        ).to.be.revertedWith("Already confirmed");
      });
    });

    describe("raiseDispute", function () {
      beforeEach(async function () {
        await ledger.connect(user1).createEscrow(agreementId, valueHash, 1, 30);
        await ledger.connect(user2).joinEscrow(0);
      });

      it("should allow initiator to raise dispute", async function () {
        await ledger.connect(user1).raiseDispute(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.disputed).to.be.true;
        expect(escrow.status).to.equal(3); // Disputed
      });

      it("should allow participant to raise dispute", async function () {
        await ledger.connect(user2).raiseDispute(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.disputed).to.be.true;
      });

      it("should revert if not party to escrow", async function () {
        await ledger.connect(user3).registerUser();

        await expect(
          ledger.connect(user3).raiseDispute(0)
        ).to.be.revertedWith("Not party to escrow");
      });
    });

    describe("Arbiter workflow", function () {
      let arbiter: Signer;

      beforeEach(async function () {
        [, , , , , arbiter] = await ethers.getSigners();

        const escrowAmount = ethers.parseEther("1.0");
        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          0,
          30,
          { value: escrowAmount }
        );
        await ledger.connect(user2).joinEscrow(0);
        await ledger.connect(user1).raiseDispute(0);
      });

      it("should allow proposing arbiter", async function () {
        await ledger.connect(user1).proposeArbiter(0, arbiter.address);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.proposedArbiter).to.equal(arbiter.address);
        expect(escrow.initiatorApprovedArbiter).to.be.true;
      });

      it("should activate arbiter when both approve", async function () {
        await ledger.connect(user1).proposeArbiter(0, arbiter.address);
        await ledger.connect(user2).approveArbiter(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.activeArbiter).to.equal(arbiter.address);
      });

      it("should allow arbiter to resolve with release", async function () {
        await ledger.connect(user1).proposeArbiter(0, arbiter.address);
        await ledger.connect(user2).approveArbiter(0);

        const participantBalanceBefore = await ethers.provider.getBalance(user2.address);

        await ledger.connect(arbiter).resolveDispute(0, "release");

        const escrow = await ledger.getEscrow(0);
        expect(escrow.status).to.equal(2); // Completed

        const participantBalanceAfter = await ethers.provider.getBalance(user2.address);
        expect(participantBalanceAfter).to.be.gt(participantBalanceBefore);
      });

      it("should allow arbiter to resolve with refund", async function () {
        await ledger.connect(user1).proposeArbiter(0, arbiter.address);
        await ledger.connect(user2).approveArbiter(0);

        const initiatorBalanceBefore = await ethers.provider.getBalance(user1.address);

        await ledger.connect(arbiter).resolveDispute(0, "refund");

        const initiatorBalanceAfter = await ethers.provider.getBalance(user1.address);
        expect(initiatorBalanceAfter).to.be.gt(initiatorBalanceBefore);
      });

      it("should allow arbiter to resolve with split", async function () {
        await ledger.connect(user1).proposeArbiter(0, arbiter.address);
        await ledger.connect(user2).approveArbiter(0);

        const initiatorBalanceBefore = await ethers.provider.getBalance(user1.address);
        const participantBalanceBefore = await ethers.provider.getBalance(user2.address);

        await ledger.connect(arbiter).resolveDispute(0, "split");

        const initiatorBalanceAfter = await ethers.provider.getBalance(user1.address);
        const participantBalanceAfter = await ethers.provider.getBalance(user2.address);

        expect(initiatorBalanceAfter).to.be.gt(initiatorBalanceBefore);
        expect(participantBalanceAfter).to.be.gt(participantBalanceBefore);
      });

      it("should pay arbiter fee", async function () {
        await ledger.connect(user1).proposeArbiter(0, arbiter.address);
        await ledger.connect(user2).approveArbiter(0);

        const arbiterBalanceBefore = await ethers.provider.getBalance(arbiter.address);

        const tx = await ledger.connect(arbiter).resolveDispute(0, "release");
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed * receipt.gasPrice;

        const arbiterBalanceAfter = await ethers.provider.getBalance(arbiter.address);
        const arbiterFeeReceived = arbiterBalanceAfter - arbiterBalanceBefore + gasUsed;

        const escrowAmount = ethers.parseEther("1.0");
        const expectedFee = (escrowAmount * 1n) / 100n; // 1%

        expect(arbiterFeeReceived).to.be.closeTo(expectedFee, ethers.parseEther("0.001"));
      });
    });

    describe("cancelEscrow", function () {
      it("should allow cancelling pending escrow", async function () {
        const escrowAmount = ethers.parseEther("1.0");
        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          0,
          30,
          { value: escrowAmount }
        );

        const balanceBefore = await ethers.provider.getBalance(user1.address);

        const tx = await ledger.connect(user1).cancelEscrow(0);
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed * receipt.gasPrice;

        const escrow = await ledger.getEscrow(0);
        expect(escrow.status).to.equal(4); // Cancelled

        const balanceAfter = await ethers.provider.getBalance(user1.address);
        const refundReceived = balanceAfter - balanceBefore + gasUsed;

        expect(refundReceived).to.be.closeTo(escrowAmount, ethers.parseEther("0.001"));
      });

      it("should revert if not pending", async function () {
        await ledger.connect(user1).createEscrow(agreementId, valueHash, 1, 30);
        await ledger.connect(user2).joinEscrow(0);

        await expect(
          ledger.connect(user1).cancelEscrow(0)
        ).to.be.revertedWith("Can only cancel pending escrow");
      });

      it("should revert if not initiator", async function () {
        await ledger.connect(user1).createEscrow(agreementId, valueHash, 1, 30);

        await expect(
          ledger.connect(user2).cancelEscrow(0)
        ).to.be.revertedWith("Only initiator can cancel");
      });
    });

    describe("handleExpiredEscrow", function () {
      it("should handle expired escrow and refund initiator", async function () {
        const escrowAmount = ethers.parseEther("1.0");
        const expirationDays = 1;

        await ledger.connect(user1).createEscrow(
          agreementId,
          valueHash,
          0,
          expirationDays,
          { value: escrowAmount }
        );
        await ledger.connect(user2).joinEscrow(0);

        // Advance time by 2 days
        await ethers.provider.send("evm_increaseTime", [2 * 24 * 60 * 60]);
        await ethers.provider.send("evm_mine", []);

        const balanceBefore = await ethers.provider.getBalance(user1.address);

        await ledger.connect(user3).handleExpiredEscrow(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.status).to.equal(5); // Expired

        const balanceAfter = await ethers.provider.getBalance(user1.address);
        expect(balanceAfter - balanceBefore).to.equal(escrowAmount);
      });

      it("should revert if not expired", async function () {
        await ledger.connect(user1).createEscrow(agreementId, valueHash, 1, 30);

        await expect(
          ledger.connect(user2).handleExpiredEscrow(0)
        ).to.be.revertedWith("Not expired");
      });
    });

    describe("View functions", function () {
      it("should get escrows for agreement", async function () {
        await ledger.connect(user1).createEscrow(agreementId, valueHash, 1, 30);
        await ledger.connect(user2).createEscrow(agreementId, valueHash, 1, 30);

        const escrows = await ledger.getEscrowsForAgreement(agreementId);
        expect(escrows.length).to.equal(2);
      });

      it("should check if escrow is expired", async function () {
        await ledger.connect(user1).createEscrow(agreementId, valueHash, 1, 1);

        let isExpired = await ledger.isEscrowExpired(0);
        expect(isExpired).to.be.false;

        // Advance time
        await ethers.provider.send("evm_increaseTime", [2 * 24 * 60 * 60]);
        await ethers.provider.send("evm_mine", []);

        isExpired = await ledger.isEscrowExpired(0);
        expect(isExpired).to.be.true;
      });
    });

    describe("Oracle Verification", function () {
      let oracle: Signer;
      let arbiter: Signer;

      beforeEach(async function () {
        [owner, devWallet, user1, user2, user3, oracle, arbiter] =
          await ethers.getSigners();

        // Re-deploy with new signers
        const LedgerFactory = await ethers.getContractFactory(
          "AgreementLedger"
        );
        ledger = await LedgerFactory.deploy(devWallet.address);
        await ledger.waitForDeployment();

        // Authorize oracle
        await ledger.authorizeOracle(oracle.address, true);
      });

      it("should allow owner to authorize oracle", async function () {
        expect(await ledger.authorizedOracles(oracle.address)).to.be.true;
      });

      it("should allow owner to deauthorize oracle", async function () {
        await ledger.authorizeOracle(oracle.address, false);
        expect(await ledger.authorizedOracles(oracle.address)).to.be.false;
      });

      it("should reject oracle authorization from non-owner", async function () {
        await expect(
          ledger.connect(user1).authorizeOracle(user2.address, true)
        ).to.be.revertedWithCustomError(ledger, "OwnableUnauthorizedAccount");
      });

      it("should allow authorized oracle to verify file deliverable", async function () {
        await ledger.connect(user1).registerUser();
        await ledger.connect(user2).registerUser();
        const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
        await ledger.connect(user1).createAgreement(user2.address, detailsHash);

        const valueHash = ethers.keccak256(
          ethers.toUtf8Bytes("File deliverable")
        );
        await ledger.connect(user1).createEscrow(0, valueHash, 2, 30); // FileDeliverable

        await ledger.connect(user2).joinEscrow(0);

        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("IPFS CID"));
        await ledger.connect(user1).submitProof(0, proofHash);

        await ledger
          .connect(oracle)
          .submitOracleVerification(0, true, proofHash);

        expect(await ledger.oracleVerified(0)).to.be.true;
        expect(await ledger.oracleVerificationHash(0)).to.equal(proofHash);
      });

      it("should auto-confirm initiator when oracle verifies", async function () {
        await ledger.connect(user1).registerUser();
        await ledger.connect(user2).registerUser();
        const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
        await ledger.connect(user1).createAgreement(user2.address, detailsHash);

        const valueHash = ethers.keccak256(
          ethers.toUtf8Bytes("Service deliverable")
        );
        await ledger.connect(user1).createEscrow(0, valueHash, 4, 30); // Service

        await ledger.connect(user2).joinEscrow(0);

        const proofHash = ethers.keccak256(
          ethers.toUtf8Bytes("Service proof")
        );
        await ledger.connect(user1).submitProof(0, proofHash);

        await ledger
          .connect(oracle)
          .submitOracleVerification(0, true, proofHash);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.initiatorConfirmed).to.be.true;
      });

      it("should auto-release when oracle verifies and both parties confirm", async function () {
        await ledger.connect(user1).registerUser();
        await ledger.connect(user2).registerUser();
        const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
        await ledger.connect(user1).createAgreement(user2.address, detailsHash);

        const valueHash = ethers.keccak256(
          ethers.toUtf8Bytes("File deliverable")
        );
        const escrowAmount = ethers.parseEther("1.0");
        await ledger
          .connect(user1)
          .createEscrow(0, valueHash, 0, 30, { value: escrowAmount }); // Crypto

        await ledger.connect(user2).joinEscrow(0);

        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("Proof"));
        await ledger.connect(user1).submitProof(0, proofHash);

        // Oracle verifies (auto-confirms initiator)
        await ledger
          .connect(oracle)
          .submitOracleVerification(0, true, proofHash);

        // Participant confirms manually
        await ledger.connect(user2).confirmCompletion(0);

        const escrow = await ledger.getEscrow(0);
        expect(escrow.status).to.equal(2); // Completed
      });

      it("arbiter should override oracle verification", async function () {
        await ledger.connect(user1).registerUser();
        await ledger.connect(user2).registerUser();
        const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
        await ledger.connect(user1).createAgreement(user2.address, detailsHash);

        const valueHash = ethers.keccak256(
          ethers.toUtf8Bytes("File deliverable")
        );
        const escrowAmount = ethers.parseEther("1.0");
        await ledger
          .connect(user1)
          .createEscrow(0, valueHash, 2, 30, { value: escrowAmount }); // FileDeliverable

        await ledger.connect(user2).joinEscrow(0);

        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("Proof"));
        await ledger.connect(user1).submitProof(0, proofHash);

        // Oracle says no
        await ledger
          .connect(oracle)
          .submitOracleVerification(0, false, proofHash);

        // Raise dispute
        await ledger.connect(user1).raiseDispute(0);

        // Propose and approve arbiter
        await ledger.connect(user1).proposeArbiter(0, arbiter.address);
        await ledger.connect(user2).approveArbiter(0);

        // Arbiter overrides oracle and releases
        await ledger.connect(arbiter).resolveDispute(0, "release");

        const escrow = await ledger.getEscrow(0);
        expect(escrow.status).to.equal(2); // Completed - arbiter overrode oracle
      });

      it("should reject verification from unauthorized oracle", async function () {
        await ledger.connect(user1).registerUser();
        await ledger.connect(user2).registerUser();
        const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
        await ledger.connect(user1).createAgreement(user2.address, detailsHash);

        const valueHash = ethers.keccak256(
          ethers.toUtf8Bytes("File deliverable")
        );
        await ledger.connect(user1).createEscrow(0, valueHash, 2, 30);

        await ledger.connect(user2).joinEscrow(0);

        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("Proof"));

        await expect(
          ledger.connect(user3).submitOracleVerification(0, true, proofHash)
        ).to.be.revertedWith("Not authorized oracle");
      });

      it("should reject verification for non-active escrow", async function () {
        await ledger.connect(user1).registerUser();
        await ledger.connect(user2).registerUser();
        const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
        await ledger.connect(user1).createAgreement(user2.address, detailsHash);

        const valueHash = ethers.keccak256(
          ethers.toUtf8Bytes("File deliverable")
        );
        await ledger.connect(user1).createEscrow(0, valueHash, 2, 30);

        // Escrow is Pending, not Active
        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("Proof"));

        await expect(
          ledger.connect(oracle).submitOracleVerification(0, true, proofHash)
        ).to.be.revertedWith("Escrow not active");
      });

      it("should return oracle verification details", async function () {
        await ledger.connect(user1).registerUser();
        await ledger.connect(user2).registerUser();
        const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));
        await ledger.connect(user1).createAgreement(user2.address, detailsHash);

        const valueHash = ethers.keccak256(
          ethers.toUtf8Bytes("File deliverable")
        );
        await ledger.connect(user1).createEscrow(0, valueHash, 2, 30);

        await ledger.connect(user2).joinEscrow(0);

        const proofHash = ethers.keccak256(ethers.toUtf8Bytes("Proof"));
        await ledger.connect(user1).submitProof(0, proofHash);

        await ledger
          .connect(oracle)
          .submitOracleVerification(0, true, proofHash);

        const verification = await ledger.getOracleVerification(0);
        expect(verification.verified).to.be.true;
        expect(verification.verificationHash).to.equal(proofHash);
        expect(verification.verifiedAt).to.be.gt(0);
      });
    });
  });
});
