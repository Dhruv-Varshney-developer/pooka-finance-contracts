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
  const SEPOLIA_WETH_TOKEN: string =
    "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"; // Sepolia WETH
  const SEPOLIA_CHAIN_SELECTOR: bigint = BigInt("16015286601757825753");

  // Deploy CrossChainManager on Sepolia
  console.log("Deploying CrossChainManager on Sepolia...");
  const crossChainManager = await hre.viem.deployContract("CrossChainManager", [
    SEPOLIA_CCIP_ROUTER,
    SEPOLIA_LINK_TOKEN,
    SEPOLIA_USDC_TOKEN,
    SEPOLIA_WETH_TOKEN,
    SEPOLIA_CHAIN_SELECTOR,
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

  console.log("\n🔍 VERIFICATION COMMAND:");
  console.log(
    `npx hardhat verify --network sepolia ${crossChainManager.address} "${SEPOLIA_CCIP_ROUTER}" "${SEPOLIA_LINK_TOKEN}" "${SEPOLIA_USDC_TOKEN}" "${SEPOLIA_CHAIN_SELECTOR}"`
  );

  console.log("\n🎯 NEXT STEPS:");
  console.log("1. Deploy contracts on AVAX Fuji");
  console.log("2. Update AVAX CrossChainManager with PoolManager address");
  console.log("3. Test cross-chain deposits!");
}

main().catch((error: Error) => {
  console.error(error);
  process.exit(1);
});
