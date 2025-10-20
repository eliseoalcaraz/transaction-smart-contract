import { expect } from "chai";
import { network } from "hardhat";
const { ethers } = await network.connect();

describe("AgreementLedger", function () {
  let ledger: any;
  let owner: any;
  let devWallet: any;
  let user1: any;
  let user2: any;
  let user3: any;

  const initialMint = ethers.parseEther("1000000");
  const registerReward = ethers.parseEther("100");
  const verifyFee = ethers.parseEther("10");
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

  it("should allow user registration and give reward", async function () {
    await ledger.connect(user1).registerUser();
    const balance = await ledger.balanceOf(user1.address);
    expect(balance).to.equal(registerReward);
    expect(await ledger.registered(user1.address)).to.be.true;
  });

  it("should create agreement and deduct verification fees", async function () {
    await ledger.connect(user1).registerUser();
    await ledger.connect(user2).registerUser();

    const detailsHash = ethers.keccak256(
      ethers.toUtf8Bytes("Agreement between user1 and user2")
    );

    await ledger.connect(user1).createAgreement(user2.address, detailsHash);

    const agreements = await ledger.getAgreements();
    expect(agreements.length).to.equal(1);
    expect(agreements[0].partyA).to.equal(user1.address);
    expect(agreements[0].partyB).to.equal(user2.address);

    const burnAmount = (verifyFee * burnPercent) / 100n;
    const devAmount = verifyFee - burnAmount;

    const user1Balance = await ledger.balanceOf(user1.address);
    const user2Balance = await ledger.balanceOf(user2.address);
    const devBalance = await ledger.balanceOf(devWallet.address);

    expect(user1Balance).to.equal(registerReward - verifyFee);
    expect(user2Balance).to.equal(registerReward - verifyFee);
    expect(devBalance).to.equal(devAmount * 2n);
  });

  it("should allow reporting of a party with hashed reason", async function () {
    await ledger.connect(user1).registerUser();
    await ledger.connect(user2).registerUser();

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));

    await ledger.connect(user1).createAgreement(user2.address, detailsHash);

    const reason = ethers.keccak256(
      ethers.toUtf8Bytes("Did not deliver on time")
    );

    await ledger.connect(user1).reportIssue(0, user2.address, reason);

    const reports = await ledger.getReportsByReporter(user1.address);
    expect(reports.length).to.equal(1);
    expect(reports[0].reporter).to.equal(user1.address);
    expect(reports[0].reportedParty).to.equal(user2.address);
    expect(reports[0].reason).to.equal(reason);

    const reportsAgainst = await ledger.getReportsAgainstParty(user2.address);
    expect(reportsAgainst.length).to.equal(1);
    expect(reportsAgainst[0].reason).to.equal(reason);
  });

  it("should retrieve all reports against a party (multiple reports)", async function () {
    await ledger.connect(user1).registerUser();
    await ledger.connect(user2).registerUser();
    await ledger.connect(user3).registerUser();

    const detailsHash1 = ethers.keccak256(ethers.toUtf8Bytes("A1"));
    const detailsHash2 = ethers.keccak256(ethers.toUtf8Bytes("A2"));

    await ledger.connect(user1).createAgreement(user2.address, detailsHash1);
    await ledger.connect(user2).createAgreement(user3.address, detailsHash2);

    const reason1 = ethers.keccak256(ethers.toUtf8Bytes("Issue 1"));
    const reason2 = ethers.keccak256(ethers.toUtf8Bytes("Issue 2"));

    await ledger.connect(user1).reportIssue(0, user2.address, reason1);
    await ledger.connect(user2).reportIssue(1, user3.address, reason2);

    // Reports against user2
    const reportsAgainstUser2 = await ledger.getReportsAgainstParty(user2.address);
    expect(reportsAgainstUser2.length).to.equal(1);
    expect(reportsAgainstUser2[0].reason).to.equal(reason1);

    // Reports against user3
    const reportsAgainstUser3 = await ledger.getReportsAgainstParty(user3.address);
    expect(reportsAgainstUser3.length).to.equal(1);
    expect(reportsAgainstUser3[0].reason).to.equal(reason2);

    // Reports against user1 (should be empty)
    const reportsAgainstUser1 = await ledger.getReportsAgainstParty(user1.address);
    expect(reportsAgainstUser1.length).to.equal(0);
  });

  it("should prevent reporting if not part of the agreement", async function () {
    await ledger.connect(user1).registerUser();
    await ledger.connect(user2).registerUser();
    await ledger.connect(user3).registerUser();

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));

    await ledger.connect(user1).createAgreement(user2.address, detailsHash);

    const reason = ethers.keccak256(ethers.toUtf8Bytes("Bad behavior"));

    await expect(
      ledger.connect(user3).reportIssue(0, user2.address, reason)
    ).to.be.revertedWith("Not part of the agreement");
  });

  it("should prevent reporting self", async function () {
    await ledger.connect(user1).registerUser();
    await ledger.connect(user2).registerUser();

    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Agreement"));

    await ledger.connect(user1).createAgreement(user2.address, detailsHash);

    const reason = ethers.keccak256(ethers.toUtf8Bytes("Self report"));

    await expect(
      ledger.connect(user1).reportIssue(0, user1.address, reason)
    ).to.be.revertedWith("Cannot report yourself");
  });

  it("should retrieve agreements by party", async function () {
    await ledger.connect(user1).registerUser();
    await ledger.connect(user2).registerUser();

    const hash1 = ethers.keccak256(ethers.toUtf8Bytes("A1"));
    const hash2 = ethers.keccak256(ethers.toUtf8Bytes("A2"));

    await ledger.connect(user1).createAgreement(user2.address, hash1);
    await ledger.connect(user1).createAgreement(user2.address, hash2);

    const user1Agreements = await ledger.getAgreementsByParty(user1.address);
    expect(user1Agreements.length).to.equal(2);
    expect(user1Agreements[0].details).to.equal(hash1);
    expect(user1Agreements[1].details).to.equal(hash2);
  });
});
