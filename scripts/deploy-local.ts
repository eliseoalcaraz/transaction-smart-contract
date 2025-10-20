import { network } from "hardhat";

const { ethers } = await network.connect();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying contract with the account: ${deployer.address}`);

  const AgreementLedger = await ethers.getContractFactory("AgreementLedger");

  const ledger = await AgreementLedger.deploy(deployer.address);
  await ledger.waitForDeployment();

  const contractAddress = await ledger.getAddress();
  console.log(`AgreementLedger deployed to: ${contractAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
