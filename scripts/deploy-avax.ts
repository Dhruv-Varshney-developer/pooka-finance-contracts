// @ts-nocheck

import hre from "hardhat";

async function main(): Promise<void> {
  console.log("🚀 Deploying Perps Protocol on AVAX Fuji...\n");

  const USDC_TOKEN_ADDRESS: string =
    "0x5425890298aed601595a70AB815c96711a31Bc65";
  const LINK_TOKEN_ADDRESS: string =
    "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846";
  const FUJI_CCIP_ROUTER: string = "0xF694E193200268f9a4868e4Aa017A0118C9a8177";
  const FUJI_CHAIN_SELECTOR: bigint = BigInt("14767482510784806043");

  const FUJI_VRF_COORDINATOR: string =
    "0x2eD832Ba664535e5886b75D64C46EB9a228C2610";
  const FUJI_VRF_KEYHASH: string =
    "0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61";
  const VRF_SUBSCRIPTION_ID: bigint = BigInt(
    "78089242584694303630769952839292814618695167473477384782355522507914412967813"
  );

  console.log("1. Deploying PriceOracle...");
  const priceOracle = await hre.viem.deployContract("PriceOracle");
  console.log(`✅ PriceOracle: ${priceOracle.address}`);

  console.log("\n2. Deploying PerpsFeeManager...");
  const feeManager = await hre.viem.deployContract("PerpsFeeManager");
  console.log(`✅ PerpsFeeManager: ${feeManager.address}`);

  console.log("\n3. Deploying PerpsCalculations...");
  const calculations = await hre.viem.deployContract("PerpsCalculations", [
    feeManager.address,
  ]);
  console.log(`✅ PerpsCalculations: ${calculations.address}`);

  console.log("\n4. Deploying VRFRandomizer...");
  const vrfRandomizer = await hre.viem.deployContract("VRFRandomizer", [
    FUJI_VRF_COORDINATOR,
    VRF_SUBSCRIPTION_ID,
    FUJI_VRF_KEYHASH,
  ]);
  console.log(`✅ VRFRandomizer: ${vrfRandomizer.address}`);

  console.log("\n5. Deploying VRFAutomation...");
  const vrfAutomation = await hre.viem.deployContract("VRFAutomation", [
    vrfRandomizer.address,
  ]);
  console.log(`✅ VRFAutomation: ${vrfAutomation.address}`);

  console.log("\n6. Deploying Perps (Main)...");
  const perps = await hre.viem.deployContract("Perps", [
    priceOracle.address,
    feeManager.address,
    calculations.address,
    USDC_TOKEN_ADDRESS,
    vrfRandomizer.address,
  ]);
  console.log(`✅ Perps: ${perps.address}`);

  console.log("\n7. Deploying PoolManager...");
  const poolManager = await hre.viem.deployContract("PoolManager", [
    priceOracle.address,
    perps.address,
    USDC_TOKEN_ADDRESS,
    LINK_TOKEN_ADDRESS,
  ]);
  console.log(`✅ PoolManager: ${poolManager.address}`);

  console.log("\n8. Deploying TimeLiquidationAutomation...");
  const timeAutomation = await hre.viem.deployContract(
    "TimeLiquidationAutomation",
    [perps.address]
  );
  console.log(`✅ TimeLiquidationAutomation: ${timeAutomation.address}`);

  console.log("\n9. Deploying LogLiquidationAutomation...");
  const logAutomation = await hre.viem.deployContract(
    "LogLiquidationAutomation",
    [perps.address]
  );
  console.log(`✅ LogLiquidationAutomation: ${logAutomation.address}`);

  console.log("\n10. Setting up contract connections...");
  await perps.write.setPoolManager([poolManager.address]);
  await vrfRandomizer.write.addAuthorizedCaller([vrfAutomation.address]);
  console.log("✅ Contract connections established");

  console.log("\n11. Funding PoolManager with USDC...");
  const [deployer] = await hre.viem.getWalletClients();
  const usdcContract = await hre.viem.getContractAt(
    "IERC20",
    USDC_TOKEN_ADDRESS
  );

  const fundingAmount: bigint = BigInt("10000000");
  await usdcContract.write.transfer([poolManager.address, fundingAmount]);
  console.log(`✅ Funded PoolManager with 10 USDC`);

  const poolManagerBalance = await usdcContract.read.balanceOf([
    poolManager.address,
  ]);
  console.log(
    `📊 PoolManager USDC balance: ${poolManagerBalance} (${
      Number(poolManagerBalance) / 1e6
    } USDC)`
  );

  console.log("\n12. Funding Automation Contracts with LINK...");
  const linkContract = await hre.viem.getContractAt(
    "IERC20",
    LINK_TOKEN_ADDRESS
  );

  const linkFundingAmount: bigint = BigInt("5000000000000000000");

  console.log("  Funding TimeLiquidationAutomation...");
  await linkContract.write.transfer([
    timeAutomation.address,
    linkFundingAmount,
  ]);

  console.log("  Funding LogLiquidationAutomation...");
  await linkContract.write.transfer([logAutomation.address, linkFundingAmount]);

  console.log("  Funding VRFAutomation...");
  await linkContract.write.transfer([vrfAutomation.address, linkFundingAmount]);

  console.log(`✅ Funded each automation contract with 5 LINK`);

  const timeAutomationBalance = await linkContract.read.balanceOf([
    timeAutomation.address,
  ]);
  const logAutomationBalance = await linkContract.read.balanceOf([
    logAutomation.address,
  ]);
  const vrfAutomationBalance = await linkContract.read.balanceOf([
    vrfAutomation.address,
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
  console.log(
    `📊 VRFAutomation LINK balance: ${Number(vrfAutomationBalance) / 1e18} LINK`
  );

  console.log("\n📋 AVAX FUJI DEPLOYMENT SUMMARY:");
  console.log(`PriceOracle: ${priceOracle.address}`);
  console.log(`PerpsFeeManager: ${feeManager.address}`);
  console.log(`PerpsCalculations: ${calculations.address}`);
  console.log(`VRFRandomizer: ${vrfRandomizer.address}`);
  console.log(`VRFAutomation: ${vrfAutomation.address}`);
  console.log(`Perps: ${perps.address}`);
  console.log(`PoolManager: ${poolManager.address}`);
  console.log(`TimeLiquidationAutomation: ${timeAutomation.address}`);
  console.log(`LogLiquidationAutomation: ${logAutomation.address}`);

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
    `npx hardhat verify --network avax_testnet ${vrfRandomizer.address} "${FUJI_VRF_COORDINATOR}" "${VRF_SUBSCRIPTION_ID}" "${FUJI_VRF_KEYHASH}"`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${vrfAutomation.address} "${vrfRandomizer.address}"`
  );
  console.log(
    `npx hardhat verify --network avax_testnet ${perps.address} "${priceOracle.address}" "${feeManager.address}" "${calculations.address}" "${USDC_TOKEN_ADDRESS}" "${vrfRandomizer.address}"`
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
  console.log("1. Create Chainlink VRF subscription and fund with LINK");
  console.log("2. Add VRFRandomizer as consumer to VRF subscription");
  console.log("3. Register all automation contracts with Chainlink Automation");
  console.log("4. Update VRF_SUBSCRIPTION_ID in script if needed");
  console.log(
    "5. Deploy CrossChainManager on Sepolia with this PoolManager address:"
  );
  console.log(`   ${poolManager.address}`);
  console.log("6. Test randomized liquidations!");
}

main().catch((error: Error) => {
  console.error(error);
  process.exit(1);
});
