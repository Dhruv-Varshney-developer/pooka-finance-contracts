// @ts-nocheck

import hre from "hardhat";

async function main(): Promise<void> {
  console.log("🚀 Deploying Perps Protocol on AVAX Fuji...\n");

  // AVAX Fuji testnet addresses
  const USDC_TOKEN_ADDRESS: string =
    "0x5425890298aed601595a70AB815c96711a31Bc65"; // Fuji USDC
  const LINK_TOKEN_ADDRESS: string =
    "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846"; // Fuji LINK

  const FUJI_CCIP_ROUTER: string = "0xF694E193200268f9a4868e4Aa017A0118C9a8177";
  const FUJI_CHAIN_SELECTOR: bigint = BigInt("14767482510784806043");

  // Step 1: Deploy PriceOracle
  console.log("1. Deploying PriceOracle...");
  const priceOracle = await hre.viem.deployContract("PriceOracle");
  console.log(`✅ PriceOracle: ${priceOracle.address}`);

  // Step 2: Deploy PerpsFeeManager
  console.log("\n2. Deploying PerpsFeeManager...");
  const feeManager = await hre.viem.deployContract("PerpsFeeManager");
  console.log(`✅ PerpsFeeManager: ${feeManager.address}`);

  // Step 3: Deploy PerpsCalculations
  console.log("\n3. Deploying PerpsCalculations...");
  const calculations = await hre.viem.deployContract("PerpsCalculations", [
    feeManager.address,
  ]);
  console.log(`✅ PerpsCalculations: ${calculations.address}`);

  // Step 4: Deploy Main Perps Contract
  console.log("\n4. Deploying Perps (Main)...");
  const perps = await hre.viem.deployContract("Perps", [
    priceOracle.address,
    feeManager.address,
    calculations.address,
    USDC_TOKEN_ADDRESS,
  ]);
  console.log(`✅ Perps: ${perps.address}`);

  // Step 5: Deploy PoolManager (UPDATED - no crossChainManager parameter)
  console.log("\n5. Deploying PoolManager...");
  const poolManager = await hre.viem.deployContract("PoolManager", [
    priceOracle.address,
    perps.address,
    USDC_TOKEN_ADDRESS,
    LINK_TOKEN_ADDRESS,
  ]);
  console.log(`✅ PoolManager: ${poolManager.address}`);

  // REMOVED: CrossChainManager deployment (only deployed on Sepolia)

  // Step 6: Deploy Time-based Liquidation Automation
  console.log("\n6. Deploying TimeLiquidationAutomation...");
  const timeAutomation = await hre.viem.deployContract(
    "TimeLiquidationAutomation",
    [perps.address]
  );
  console.log(`✅ TimeLiquidationAutomation: ${timeAutomation.address}`);

  // Step 7: Deploy Log-based Liquidation Automation
  console.log("\n7. Deploying LogLiquidationAutomation...");
  const logAutomation = await hre.viem.deployContract(
    "LogLiquidationAutomation",
    [perps.address]
  );
  console.log(`✅ LogLiquidationAutomation: ${logAutomation.address}`);

  // Step 8: Setup connections (UPDATED - no crossChainManager)
  console.log("\n8. Setting up contract connections...");
  await perps.write.setPoolManager([poolManager.address]);
  console.log("✅ Contract connections established");

  // Step 9: Fund PoolManager with USDC
  console.log("\n9. Funding PoolManager with USDC...");
  const [deployer] = await hre.viem.getWalletClients();
  const usdcContract = await hre.viem.getContractAt(
    "IERC20",
    USDC_TOKEN_ADDRESS
  );

  // Transfer 10 USDC (10 * 10^6 = 10,000,000) to PoolManager
  const fundingAmount: bigint = BigInt("10000000"); // 10 USDC (6 decimals)
  await usdcContract.write.transfer([poolManager.address, fundingAmount]);
  console.log(`✅ Funded PoolManager with 10 USDC`);

  // Verify PoolManager balance
  const poolManagerBalance = await usdcContract.read.balanceOf([
    poolManager.address,
  ]);
  console.log(
    `📊 PoolManager USDC balance: ${poolManagerBalance} (${
      Number(poolManagerBalance) / 1e6
    } USDC)`
  );

  // Step 10: Fund Automation Contracts with LINK
  console.log("\n10. Funding Automation Contracts with LINK...");
  const linkContract = await hre.viem.getContractAt(
    "IERC20",
    LINK_TOKEN_ADDRESS
  );

  // Fund each automation contract with 5 LINK (5 * 10^18)
  const linkFundingAmount: bigint = BigInt("5000000000000000000"); // 5 LINK (18 decimals)

  console.log("  Funding TimeLiquidationAutomation...");
  await linkContract.write.transfer([
    timeAutomation.address,
    linkFundingAmount,
  ]);

  console.log("  Funding LogLiquidationAutomation...");
  await linkContract.write.transfer([logAutomation.address, linkFundingAmount]);

  console.log(`✅ Funded each automation contract with 5 LINK`);

  // Verify automation contract balances
  const timeAutomationBalance = await linkContract.read.balanceOf([
    timeAutomation.address,
  ]);
  const logAutomationBalance = await linkContract.read.balanceOf([
    logAutomation.address,
  ]);
  console.log(
    `📊 TimeLiquidationAutomation LINK balance: ${
      Number(timeAutomationBalance) / 1e18
    } LINK`
  );
  console.log(
    `📊 LogLiquidationAutomation LINK balance: ${
      Number(logAutomationBalance) / 1e18
    } LINK`
  );

  // Summary (UPDATED - no CrossChainManager)
  console.log("\n📋 AVAX FUJI DEPLOYMENT SUMMARY:");
  console.log(`PriceOracle: ${priceOracle.address}`);
  console.log(`PerpsFeeManager: ${feeManager.address}`);
  console.log(`PerpsCalculations: ${calculations.address}`);
  console.log(`Perps: ${perps.address}`);
  console.log(`PoolManager: ${poolManager.address}`);
  console.log(`TimeLiquidationAutomation: ${timeAutomation.address}`);
  console.log(`LogLiquidationAutomation: ${logAutomation.address}`);

  // Verification commands (UPDATED)
  console.log("\n🔍 VERIFICATION COMMANDS:");
  console.log(
    `npx hardhat verify --network avax_testnet ${priceOracle.address}`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${feeManager.address}`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${calculations.address} "${feeManager.address}"`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${perps.address} "${priceOracle.address}" "${feeManager.address}" "${calculations.address}" "${USDC_TOKEN_ADDRESS}"`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${poolManager.address} "${priceOracle.address}" "${perps.address}" "${USDC_TOKEN_ADDRESS}" "${LINK_TOKEN_ADDRESS}"`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${timeAutomation.address} "${perps.address}"`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${logAutomation.address} "${perps.address}"`
  );

  console.log("\n🎯 NEXT STEPS:");
  console.log("1. Register automation contracts with Chainlink Automation");
  console.log(
    "2. Deploy CrossChainManager on Sepolia with this PoolManager address:"
  );
  console.log(`   ${poolManager.address}`);
  console.log("3. Test cross-chain deposits!");
}

main().catch((error: Error) => {
  console.error(error);
  process.exit(1);
});
