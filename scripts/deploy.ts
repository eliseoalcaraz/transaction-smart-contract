import { network } from "hardhat";

const { ethers } = await network.connect();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(
    `Deploying contract with the account: ${deployer.address}`
  );

  const TransactionLedger = await ethers.getContractFactory("TransactionLedger");

  console.log("Deploying TransactionLedger...");
  const ledger = await TransactionLedger.deploy();
  await ledger.waitForDeployment();

  const contractAddress = await ledger.getAddress();
  console.log(`TransactionLedger deployed to: ${contractAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});