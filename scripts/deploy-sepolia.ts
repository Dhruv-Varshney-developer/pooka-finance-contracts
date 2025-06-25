// @ts-nocheck

import hre from "hardhat";

async function main(): Promise<void> {
  console.log("🚀 Deploying CrossChainManager on Sepolia...\n");

  // Sepolia testnet addresses
  const SEPOLIA_CCIP_ROUTER: string =
    "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59";
  const SEPOLIA_LINK_TOKEN: string =
    "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const SEPOLIA_USDC_TOKEN: string =
    "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";

  // UPDATED: PoolManager address from AVAX deployment (FILL THIS IN!)
  const AVAX_POOL_MANAGER_ADDRESS: string =
    "YOUR_AVAX_POOL_MANAGER_ADDRESS_HERE";

  // Verify PoolManager address is set
  if (AVAX_POOL_MANAGER_ADDRESS === "YOUR_AVAX_POOL_MANAGER_ADDRESS_HERE") {
    console.error("❌ Please set AVAX_POOL_MANAGER_ADDRESS first!");
    console.log("1. Deploy contracts on AVAX Fuji first");
    console.log("2. Copy the PoolManager address from AVAX deployment");
    console.log("3. Update AVAX_POOL_MANAGER_ADDRESS in this script");
    process.exit(1);
  }

  // Deploy CrossChainManager on Sepolia (UPDATED constructor)
  console.log("Deploying CrossChainManager on Sepolia...");
  const crossChainManager = await hre.viem.deployContract("CrossChainManager", [
    SEPOLIA_CCIP_ROUTER,
    SEPOLIA_LINK_TOKEN,
    SEPOLIA_USDC_TOKEN,
    AVAX_POOL_MANAGER_ADDRESS, // UPDATED: Now takes PoolManager address
  ]);

  console.log(`✅ CrossChainManager (Sepolia): ${crossChainManager.address}`);

  // Fund CrossChainManager with LINK for CCIP fees
  console.log("\nFunding CrossChainManager with LINK for fees...");
  const [deployer] = await hre.viem.getWalletClients();
  const linkContract = await hre.viem.getContractAt(
    "IERC20",
    SEPOLIA_LINK_TOKEN
  );

  // Transfer 10 LINK for fees
  const linkFundingAmount: bigint = BigInt("10000000000000000000"); // 10 LINK
  await linkContract.write.transfer([
    crossChainManager.address,
    linkFundingAmount,
  ]);
  console.log(`✅ Funded CrossChainManager with 10 LINK for CCIP fees`);

  // Verify balance
  const linkBalance = await linkContract.read.balanceOf([
    crossChainManager.address,
  ]);
  console.log(
    `📊 CrossChainManager LINK balance: ${Number(linkBalance) / 1e18} LINK`
  );

  console.log("\n📋 SEPOLIA DEPLOYMENT SUMMARY:");
  console.log(`CrossChainManager: ${crossChainManager.address}`);
  console.log(`Target PoolManager (AVAX): ${AVAX_POOL_MANAGER_ADDRESS}`);

  console.log("\n🔍 VERIFICATION COMMAND:");
  console.log(
    `npx hardhat verify --network sepolia ${crossChainManager.address} "${SEPOLIA_CCIP_ROUTER}" "${SEPOLIA_LINK_TOKEN}" "${SEPOLIA_USDC_TOKEN}" "${AVAX_POOL_MANAGER_ADDRESS}"`
  );

  console.log("\n🎯 NEXT STEPS:");
  console.log("1. Verify contracts on both chains");
  console.log("2. Test cross-chain deposits!");
  console.log(
    `3. Users can now deposit USDC on Sepolia using: ${crossChainManager.address}`
  );
}

main().catch((error: Error) => {
  console.error(error);
  process.exit(1);
});
