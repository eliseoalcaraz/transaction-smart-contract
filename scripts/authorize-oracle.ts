import { network } from "hardhat";

async function main() {
    const { ethers } = await network.connect();
    const [owner] = await ethers.getSigners();

    // Replace with your deployed contract address
    const contractAddress = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";

    const AgreementLedger = await ethers.getContractFactory("AgreementLedger");
    const ledger = AgreementLedger.attach(contractAddress);

    // Use account #1 as oracle (or any other account)
    const oracleAddress = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; // Account #1

    const tx = await ledger.authorizeOracle(oracleAddress, true);
    await tx.wait();

    console.log(`✅ Oracle authorized: ${oracleAddress}`);

    // Verify
    const isAuthorized = await ledger.authorizedOracles(oracleAddress);
    console.log(`Oracle authorized status: ${isAuthorized}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });