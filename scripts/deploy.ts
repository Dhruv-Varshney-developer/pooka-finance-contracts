const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Deploying Perps Protocol...\n");

  // Step 1: Deploy PriceOracle
  console.log("1. Deploying PriceOracle...");
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracle.deploy();
  await priceOracle.waitForDeployment();
  const priceOracleAddress = await priceOracle.getAddress();
  console.log(`✅ PriceOracle: ${priceOracleAddress}`);

  // Step 2: Deploy PerpsFeeManager
  console.log("\n2. Deploying PerpsFeeManager...");
  const PerpsFeeManager = await ethers.getContractFactory("PerpsFeeManager");
  const feeManager = await PerpsFeeManager.deploy();
  await feeManager.waitForDeployment();
  const feeManagerAddress = await feeManager.getAddress();
  console.log(`✅ PerpsFeeManager: ${feeManagerAddress}`);

  // Step 3: Deploy PerpsCalculations
  console.log("\n3. Deploying PerpsCalculations...");
  const PerpsCalculations = await ethers.getContractFactory(
    "PerpsCalculations"
  );
  const calculations = await PerpsCalculations.deploy(feeManagerAddress);
  await calculations.waitForDeployment();
  const calculationsAddress = await calculations.getAddress();
  console.log(`✅ PerpsCalculations: ${calculationsAddress}`);

  // Step 4: Deploy Main Perps Contract
  console.log("\n4. Deploying Perps (Main)...");
  const Perps = await ethers.getContractFactory("Perps");
  const perps = await Perps.deploy(
    priceOracleAddress,
    feeManagerAddress,
    calculationsAddress
  );
  await perps.waitForDeployment();
  const perpsAddress = await perps.getAddress();
  console.log(`✅ Perps: ${perpsAddress}`);

  // Verification commands
  console.log("\n🔍 VERIFICATION COMMANDS:");
  console.log(`npx hardhat verify --network \${NETWORK} ${priceOracleAddress}`);
  console.log(`npx hardhat verify --network \${NETWORK} ${feeManagerAddress}`);
  console.log(
    `npx hardhat verify --network \${NETWORK} ${calculationsAddress} "${feeManagerAddress}"`
  );
  console.log(
    `npx hardhat verify --network \${NETWORK} ${perpsAddress} "${priceOracleAddress}" "${feeManagerAddress}" "${calculationsAddress}"`
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
