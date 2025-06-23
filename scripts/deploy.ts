const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying Perps Protocol...\n");

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
  const calculations = await hre.viem.deployContract("PerpsCalculations", [feeManager.address]);
  console.log(`✅ PerpsCalculations: ${calculations.address}`);

  // Step 4: Deploy Main Perps Contract
  console.log("\n4. Deploying Perps (Main)...");
  // Note: You'll need to replace USDC_TOKEN_ADDRESS with actual USDC address on your network
  const USDC_TOKEN_ADDRESS = "0x5425890298aed601595a70AB815c96711a31Bc65"; // Fuji USDC
  const perps = await hre.viem.deployContract("Perps", [
    priceOracle.address,
    feeManager.address,
    calculations.address,
    USDC_TOKEN_ADDRESS
  ]);
  console.log(`✅ Perps: ${perps.address}`);

  // Step 5: Deploy PoolManager
  console.log("\n5. Deploying PoolManager...");
  const LINK_TOKEN_ADDRESS = "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846"; // Fuji LINK
  const poolManager = await hre.viem.deployContract("PoolManager", [
    priceOracle.address,
    perps.address,
    "0x0000000000000000000000000000000000000000", // Will be set after CrossChainManager deployment
    USDC_TOKEN_ADDRESS,
    LINK_TOKEN_ADDRESS
  ]);
  console.log(`✅ PoolManager: ${poolManager.address}`);

  // Step 6: Deploy CrossChainManager
  console.log("\n6. Deploying CrossChainManager...");
  const CCIP_ROUTER_ADDRESS = "0xF694E193200268f9a4868e4Aa017A0118C9a8177"; // Fuji CCIP Router
  const CURRENT_CHAIN_SELECTOR = BigInt("14767482510784806043"); // Fuji chain selector
  const crossChainManager = await hre.viem.deployContract("CrossChainManager", [
    CCIP_ROUTER_ADDRESS,
    LINK_TOKEN_ADDRESS,
    USDC_TOKEN_ADDRESS,
    LINK_TOKEN_ADDRESS,
    CURRENT_CHAIN_SELECTOR
  ]);
  console.log(`✅ CrossChainManager: ${crossChainManager.address}`);

  // Step 7: Deploy Time-based Liquidation Automation
  console.log("\n7. Deploying TimeLiquidationAutomation...");
  const timeAutomation = await hre.viem.deployContract("TimeLiquidationAutomation", [perps.address]);
  console.log(`✅ TimeLiquidationAutomation: ${timeAutomation.address}`);

  // Step 8: Deploy Log-based Liquidation Automation  
  console.log("\n8. Deploying LogLiquidationAutomation...");
  const logAutomation = await hre.viem.deployContract("LogLiquidationAutomation", [perps.address]);
  console.log(`✅ LogLiquidationAutomation: ${logAutomation.address}`);

  // Step 9: Setup connections
  console.log("\n9. Setting up contract connections...");
  await perps.write.setPoolManager([poolManager.address]);
  await crossChainManager.write.setPoolManager([poolManager.address]);
  console.log("✅ Contract connections established");

  // Step 10: Fund PoolManager with USDC
  console.log("\n10. Funding PoolManager with USDC...");
  const [deployer] = await hre.viem.getWalletClients();
  const usdcContract = await hre.viem.getContractAt("IERC20", USDC_TOKEN_ADDRESS);
  
  // Transfer 100 USDC (100 * 10^6 = 100,000,000) to PoolManager
  const fundingAmount = BigInt("100000000"); // 100 USDC (6 decimals)
  await usdcContract.write.transfer([poolManager.address, fundingAmount]);
  console.log(`✅ Funded PoolManager with 100 USDC`);

  // Verify PoolManager balance
  const poolManagerBalance = await usdcContract.read.balanceOf([poolManager.address]);
  console.log(`📊 PoolManager USDC balance: ${poolManagerBalance} (${Number(poolManagerBalance) / 1e6} USDC)`);

  // Summary
  console.log("\n📋 DEPLOYMENT SUMMARY:");
  console.log(`PriceOracle: ${priceOracle.address}`);
  console.log(`PerpsFeeManager: ${feeManager.address}`);
  console.log(`PerpsCalculations: ${calculations.address}`);
  console.log(`Perps: ${perps.address}`);
  console.log(`PoolManager: ${poolManager.address}`);
  console.log(`CrossChainManager: ${crossChainManager.address}`);
  console.log(`TimeLiquidationAutomation: ${timeAutomation.address}`);
  console.log(`LogLiquidationAutomation: ${logAutomation.address}`);

  // Verification commands
  console.log("\n🔍 VERIFICATION COMMANDS:");
  console.log(`npx hardhat verify --network avax_testnet ${priceOracle.address}`);
  console.log(`npx hardhat verify --network avax_testnet ${feeManager.address}`);
  console.log(`npx hardhat verify --network avax_testnet ${calculations.address} "${feeManager.address}"`);
  console.log(`npx hardhat verify --network avax_testnet ${perps.address} "${priceOracle.address}" "${feeManager.address}" "${calculations.address}" "${USDC_TOKEN_ADDRESS}"`);
  console.log(`npx hardhat verify --network avax_testnet ${poolManager.address} "${priceOracle.address}" "${perps.address}" "0x0000000000000000000000000000000000000000" "${USDC_TOKEN_ADDRESS}" "${LINK_TOKEN_ADDRESS}"`);
  console.log(`npx hardhat verify --network avax_testnet ${crossChainManager.address} "${CCIP_ROUTER_ADDRESS}" "${LINK_TOKEN_ADDRESS}" "${USDC_TOKEN_ADDRESS}" "${LINK_TOKEN_ADDRESS}" "${CURRENT_CHAIN_SELECTOR}"`);
  console.log(`npx hardhat verify --network avax_testnet ${timeAutomation.address} "${perps.address}"`);
  console.log(`npx hardhat verify --network avax_testnet ${logAutomation.address} "${perps.address}"`);

  console.log("\n🎯 NEXT STEPS:");
  console.log("1. Set up Chainlink price feeds in PriceOracle");
  console.log("2. Register automation contracts with Chainlink Automation");
  console.log("3. Fund automation contracts with LINK tokens");
  console.log("4. PoolManager is now funded and ready for deposits!");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});