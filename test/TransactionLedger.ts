import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();

describe("TransactionLedger", function () {
  let ledger: any;
  let owner: any, addr1: any, addr2: any;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    ledger = await ethers.deployContract("TransactionLedger");
  });

  it("should record a transaction correctly", async function () {
    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Test details"));

    const tx = await ledger
      .connect(addr1)
      .recordTransaction(addr2.address, 100, 0, detailsHash);
    await tx.wait();

    const total = await ledger.totalTransactions();
    expect(total).to.equal(1n);

    const storedTx = await ledger.getTransactions(0);
    expect(storedTx.sender).to.equal(addr1.address);
    expect(storedTx.receiver).to.equal(addr2.address);
    expect(storedTx.amount).to.equal(100n);
    expect(storedTx.detailsHash).to.equal(detailsHash);
  });

  it("should emit TransactionRecorded event", async function () {
    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Event check"));
    const amount = 50n;
    const txType = 1;

    const block = await ethers.provider.getBlock("latest");
    const expectedTimestamp = (block?.timestamp ?? 0) + 1;

    await expect(
      ledger.connect(addr1).recordTransaction(addr2.address, amount, txType, detailsHash)
    )
      .to.emit(ledger, "TransactionRecorded")
      .withArgs(
        0n,
        addr1.address,
        addr2.address,
        txType,
        amount,
        detailsHash,
        expectedTimestamp
      );
  });

  it("should get all user transactions", async function () {
    const detailsHash = ethers.keccak256(ethers.toUtf8Bytes("Tx 1"));
    await ledger.connect(addr1).recordTransaction(addr2.address, 100, 0, detailsHash);
    await ledger.connect(addr2).recordTransaction(addr1.address, 200, 1, detailsHash);

    const user1Txs = await ledger.getUserTransactions(addr1.address);
    const user2Txs = await ledger.getUserTransactions(addr2.address);

    expect(user1Txs.length).to.equal(2);
    expect(user2Txs.length).to.equal(2);
  });

  it("should revert if receiver is zero address", async function () {
    const hash = ethers.keccak256(ethers.toUtf8Bytes("Invalid"));
    await expect(
      ledger.connect(addr1).recordTransaction(ethers.ZeroAddress, 10, 0, hash)
    ).to.be.revertedWith("Invalid receiver");
  });
});
