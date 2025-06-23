import { ethers } from "hardhat";

export async function deployFixture() {
  const [owner, user1, user2, liquidator] = await ethers.getSigners();

  // Real Fuji testnet addresses
  const USDC_TOKEN = "0x5425890298aed601595a70AB815c96711a31Bc65"; // Fuji USDC
  const LINK_TOKEN = "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846"; // Fuji LINK

  // Real Chainlink price feeds on Fuji
  const BTC_PRICE_FEED = "0x31CF013A08c6Ac228C94551d535d5BAfE19c602a"; // BTC/USD
  const ETH_PRICE_FEED = "0x86d67c3D38D2bCeE722E601025C25a575021c6EA"; // ETH/USD
  const AVAX_PRICE_FEED = "0x5498BB86BC934c8D34FDA08E81D444153d0D06aD"; // AVAX/USD
  const LINK_PRICE_FEED = "0x34C4c526902d88a3Aa98DB8a9b802603EB1E3470"; // LINK/USD

  // Real CCIP addresses
  const FUJI_CCIP_ROUTER = "0xF694E193200268f9a4868e4Aa017A0118C9a8177";
  const FUJI_CHAIN_SELECTOR = BigInt("14767482510784806043");
  const SEPOLIA_CHAIN_SELECTOR = BigInt("16015286601757825753");

  // Connect to real tokens
  const usdcToken = await ethers.getContractAt("IERC20", USDC_TOKEN);
  const linkToken = await ethers.getContractAt("IERC20", LINK_TOKEN);

  const MockPriceOracle = await ethers.getContractFactory("MockPriceOracle");
  const priceOracle = await MockPriceOracle.deploy();
  // Deploy core contracts
  const PerpsFeeManager = await ethers.getContractFactory("PerpsFeeManager");
  const feeManager = await PerpsFeeManager.deploy();

  const PerpsCalculations = await ethers.getContractFactory(
    "PerpsCalculations"
  );
  const calculator = await PerpsCalculations.deploy(
    await feeManager.getAddress()
  );

  const Perps = await ethers.getContractFactory("Perps");
  const perps = await Perps.deploy(
    await priceOracle.getAddress(),
    await feeManager.getAddress(),
    await calculator.getAddress(),
    USDC_TOKEN
  );

  // Deploy PoolManager (AVAX Fuji only)
  const PoolManager = await ethers.getContractFactory("PoolManager");
  const poolManager = await PoolManager.deploy(
    await priceOracle.getAddress(),
    await perps.getAddress(),
    ethers.ZeroAddress, // CrossChain manager set later
    USDC_TOKEN,
    LINK_TOKEN
  );

  // Real Sepolia testnet addresses
  const SEPOLIA_CCIP_ROUTER = "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59";
  const SEPOLIA_LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const SEPOLIA_USDC_TOKEN = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";

  // Deploy CrossChainManager (simulating both Sepolia and AVAX deployments)
  const CrossChainManager = await ethers.getContractFactory(
    "CrossChainManager"
  );

  // AVAX deployment (receives CCIP messages)
  const crossChainManagerAVAX = await CrossChainManager.deploy(
    FUJI_CCIP_ROUTER,
    LINK_TOKEN,
    USDC_TOKEN,
    LINK_TOKEN,
    FUJI_CHAIN_SELECTOR.toString()
  );

  // Sepolia deployment (sends CCIP messages)
  const crossChainManagerSepolia = await CrossChainManager.deploy(
    SEPOLIA_CCIP_ROUTER,
    SEPOLIA_LINK_TOKEN,
    SEPOLIA_USDC_TOKEN,
    SEPOLIA_LINK_TOKEN,
    SEPOLIA_CHAIN_SELECTOR.toString()
  );

  // Deploy automation
  const TimeLiquidationAutomation = await ethers.getContractFactory(
    "TimeLiquidationAutomation"
  );
  const timeAutomation = await TimeLiquidationAutomation.deploy(
    await perps.getAddress()
  );

  const LogLiquidationAutomation = await ethers.getContractFactory(
    "LogLiquidationAutomation"
  );
  const logAutomation = await LogLiquidationAutomation.deploy(
    await perps.getAddress()
  );

  // Setup connections (owner calls)
  await perps.setPoolManager(await poolManager.getAddress());
  await poolManager.updateContracts(
    ethers.ZeroAddress, // Keep current priceOracle
    ethers.ZeroAddress, // Keep current perps
    await crossChainManagerAVAX.getAddress()
  );
  await crossChainManagerAVAX.setPoolManager(await poolManager.getAddress());

  return {
    perps,
    priceOracle,
    feeManager,
    calculator,
    poolManager,
    crossChainManagerAVAX,
    crossChainManagerSepolia,
    timeAutomation,
    logAutomation,
    usdcToken,
    linkToken,
    owner,
    user1,
    user2,
    liquidator,
    // Constants for testing
    USDC_TOKEN,
    LINK_TOKEN,
    FUJI_CHAIN_SELECTOR: FUJI_CHAIN_SELECTOR.toString(),
    SEPOLIA_CHAIN_SELECTOR: SEPOLIA_CHAIN_SELECTOR.toString(),
  };
}
