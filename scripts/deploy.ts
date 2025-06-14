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
  const perps = await hre.viem.deployContract("Perps", [
    priceOracle.address,
    feeManager.address,
    calculations.address
  ]);
  console.log(`✅ Perps: ${perps.address}`);

  // Verification commands
  console.log("\n🔍 VERIFICATION COMMANDS:");
  console.log(`npx hardhat verify --network avax_testnet ${priceOracle.address}`);
  console.log(`npx hardhat verify --network avax_testnet ${feeManager.address}`);
  console.log(`npx hardhat verify --network avax_testnet ${calculations.address} "${feeManager.address}"`);
  console.log(`npx hardhat verify --network avax_testnet ${perps.address} "${priceOracle.address}" "${feeManager.address}" "${calculations.address}"`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});