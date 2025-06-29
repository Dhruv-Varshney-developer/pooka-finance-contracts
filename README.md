# Pooka Finance - Smart Contracts

AI powered Cross-chain perpetual trading protocol built on Avalanche with Ethereum integration via Chainlink CCIP.

## Overview

Pooka Finance enables leveraged cryptocurrency trading across multiple blockchain networks. Users can deposit USDC from Ethereum (Sepolia) and trade BTC/USD and ETH/USD perpetual futures on Avalanche (Fuji) with up to 3x leverage.

## Architecture

[![image](https://github.com/user-attachments/assets/fe2577de-3a31-46c7-8375-29c15fa8a385)](https://subnets-test.avax.network/c-chain/tx/0x243c0be7bf8c353932e845277fd6b76d36c1e606ea9b6636d9177072c03a39e9)


### Cross-Chain Trading Flow

Pooka Finance solves the fundamental problem of cross-chain DeFi by enabling seamless trading across networks:

#### **Direct Deposits on Avalanche**
- Users depositing **USDC** can directly interact with the **Perps Contract** on Avalanche Fuji
- Users depositing **AVAX** or **LINK** tokens are routed through the **PoolManager** which converts assets to USDC and forwards to the Perps Contract

#### **Cross-Chain Deposits (Sepolia → Avalanche)**
- Users deposit **USDC** on Sepolia through the **CrossChainManager** contract
- **Chainlink CCIP** bridges funds to Avalanche PoolManager (takes ~25 minutes)
- **Pre-funding architecture**: PoolManager immediately credits users for instant trading while CCIP settles in background
- Final settlement via `depositUSDCForUser()` once CCIP message arrives

#### **Automated Risk Management**
- **Perps.sol** and **PriceOracle.sol** handle all trading logic on Avalanche Fuji
- All positions managed in **USDC** with real-time Chainlink price feeds
- **Chainlink Automation** monitors positions 24/7 and triggers liquidations
- **VRF randomization** ensures fair liquidation ordering

### Protocol Components

The protocol consists of smart contracts deployed across two chains:

### Avalanche Fuji (Main Trading Chain)
- **Perps.sol** - Core perpetual trading engine
- **PoolManager.sol** - Multi-token deposit handler and liquidity management
- **PriceOracle.sol** - Chainlink price feed integration
- **Automation contracts** - Automated liquidation systems
- **VRFRandomizer.sol** - Fair liquidation ordering

### Ethereum Sepolia (Cross-Chain Bridge)
- **CrossChainManager.sol** - CCIP-based USDC bridging to Avalanche

## Deployed Contracts

### Avalanche Fuji Testnet
```
PriceOracle:              0x9f2b180d135c46012c97f5beb02307cc7dc32cbd
PerpsFeeManager:          0x117d284f89fe797a65145e67cc31e21dbbf60cdc
PerpsCalculations:        0xb6fc2a81fc5803a1e5a855e69cdad79eae9a91bc
VRFRandomizer:            0xbb0599742317d4a77841d3f0d6c9bf076d83bd5a
VRFAutomation:            0x0687d4d5ea6122d975ef845c0e55a514d65da64a
Perps:                    0x9d2b2005ec13fb8a7191b0df208dfbd541827c19
PoolManager:              0xb5abc3e5d2d3b243974f0a323c4f6514f70598cf
TimeLiquidationAutomation: 0x636f1b91cfd7b91a4f7fb01e52a5df5d818a6060
LogLiquidationAutomation:  0xaa3ffc9a984d4fcac150a9d5f2b3ce004234b471
```

### Ethereum Sepolia Testnet
```
CrossChainManager:        0x0bb4543671f72a41efcaa6f089f421446264cc49
```

## Smart Contracts

### Core Trading Engine

#### `Perps.sol`
Main perpetual futures contract handling:
- Position management (open/close with leverage)
- USDC collateral deposits/withdrawals
- Automated liquidations with VRF randomization
- Risk management and user limits

**Key Functions:**
```solidity
function depositUSDC(uint256 usdcAmount)
function openPosition(string symbol, uint256 collateralUSDC, uint256 leverage, bool isLong)
function closePosition(string symbol)
function liquidatePositions() returns (uint256 liquidated)
function depositUSDCForUser(address user, uint256 usdcAmount) // For cross-chain deposits
```

#### `PerpsCalculations.sol`
Risk calculation engine:
- P&L calculations for long/short positions
- Liquidation price computation
- Margin ratio monitoring
- Position health checks

#### `PerpsFeeManager.sol`
Fee structure management:
- Opening fee: 1% of collateral
- Closing fee: 1% of collateral  
- Holding fee: 1% daily on collateral
- Profit tax: 30% on realized gains

### Cross-Chain Infrastructure

#### `CrossChainManager.sol` (Sepolia)
CCIP bridge for cross-chain USDC deposits:
- Transfers USDC from Sepolia to Avalanche PoolManager
- Includes safety limits (max 100 USDC per transaction)
- Handles CCIP message construction and fees

**Key Functions:**
```solidity
function depositAndSend(uint256 usdcAmount)
```

#### `PoolManager.sol` (Avalanche)
Multi-token deposit handler:
- Accepts AVAX, LINK, and USDC deposits
- Converts tokens to USDC using Chainlink price feeds
- Forwards converted USDC to Perps contract
- Handles both direct deposits and cross-chain CCIP messages

**Key Functions:**
```solidity
function depositUSDCForUser(address user, uint256 usdcAmount) // Pre-funding for instant UX
function depositDirect(address user, uint256 usdcAmount) // Final CCIP settlement
```

### Automation & Oracles

#### `VRFRandomizer.sol`
Chainlink VRF integration for fair liquidation ordering:
- Generates verifiable randomness
- Shuffles user arrays to prevent liquidation front-running
- Auto-refreshes randomness every 6 hours

#### `VRFAutomation.sol`
Automation contract for VRF randomness refresh:
- Automatically calls `requestRandomWords()` every 6 hours
- Ensures liquidation fairness is maintained

#### `TimeLiquidationAutomation.sol` & `LogLiquidationAutomation.sol`
Chainlink Automation contracts:
- Time-based: Triggers liquidations every 4 hours
- Log-based: Triggers on position events for immediate liquidation checks

#### `PriceOracle.sol`
Chainlink price feed aggregator:
- Supports BTC/USD, ETH/USD, AVAX/USD, LINK/USD
- Normalizes all prices to 8 decimals
- Real-time price data for position calculations

## Installation

```bash
# Clone repository
git clone https://github.com/Dhruv-Varshney-developer/pooka-finance-contracts
cd pooka-finance-contracts

# Install dependencies
npm install

# Copy environment template
cp .env.example .env
```

## Environment Setup

Create `.env` file with the following variables:

```bash
PRIVATE_KEY=your_deployer_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key  
SEPOLIA_RPC_URL=your_sepolia_rpc_url
AVAX_RPC_URL=your_avalanche_fuji_rpc_url
```

## Deployment

### 1. Deploy on Avalanche Fuji

```bash
npx hardhat run scripts/deploy-avax.ts --network avax_testnet
```

This deploys the complete trading infrastructure and outputs all contract addresses.

### 2. Deploy Cross-Chain Manager on Sepolia

```bash
# Update AVAX_POOL_MANAGER_ADDRESS in scripts/deploy-sepolia.ts
# with the PoolManager address from step 1

npx hardhat run scripts/deploy-sepolia.ts --network sepolia
```

### 3. Verify Contracts

```bash
# Verification commands are output by deployment scripts
npx hardhat verify --network avax_testnet <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

## Testing

```bash
# Run all tests
npm test

# Run specific test suites
npm run test:perps          # Core trading functionality
npm run test:price-oracle   # Price feed integration
npm run test:fee-manager    # Fee calculations
npm run test:calculations   # Risk calculations
npm run test:automation     # Liquidation automation
npm run test:crosschain     # CCIP integration
npm run test:integration    # End-to-end workflows
```

## Network Configuration

### Avalanche Fuji Testnet
- **USDC Token**: `0x5425890298aed601595a70AB815c96711a31Bc65`
- **LINK Token**: `0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846`
- **CCIP Router**: `0xF694E193200268f9a4868e4Aa017A0118C9a8177`
- **Chain Selector**: `14767482510784806043`
- **VRF Coordinator**: `0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE`
- **VRF Key Hash**: `0xc799bd1e3bd4d1a41cd4968997a4e03dfd2a3c7c04b695881138580163f42887`
- **VRF Subscription ID**: `78089242584694303630769952839292814618695167473477384782355522507914412967813`

### Ethereum Sepolia Testnet
- **USDC Token**: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- **LINK Token**: `0x779877A7B0D9E8603169DdbD7836e478b4624789`
- **CCIP Router**: `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59`
- **Chain Selector**: `16015286601757825753`

## Usage Examples

### Opening a Position

```solidity
// 1. Deposit USDC collateral
perps.depositUSDC(50_000_000); // $50 USDC (6 decimals)

// 2. Open 2x leveraged long position on BTC/USD
perps.openPosition("BTC/USD", 25_000_000, 2, true);
// Uses $25 collateral for $50 position size

// 3. Close position when ready
perps.closePosition("BTC/USD");
```

### Cross-Chain Deposit Flow

```solidity
// On Sepolia: Deposit USDC to bridge to Avalanche
crossChainManager.depositAndSend(10_000_000); // $10 USDC

// On Avalanche: PoolManager immediately credits user for instant trading
// CCIP settlement happens in background via depositDirect()
```

### Multi-Token Deposits on Avalanche

```solidity
// Deposit AVAX (automatically converted to USDC)
poolManager.deposit{value: 1 ether}(address(0), 1 ether);

// Deposit LINK tokens (automatically converted to USDC)  
poolManager.deposit(LINK_ADDRESS, 10 * 1e18);
```

## Key Features

- **Leverage Trading**: Up to 3x leverage on BTC/USD and ETH/USD
- **Cross-Chain Deposits**: Seamless USDC bridging from Ethereum with instant UX
- **Automated Liquidations**: Chainlink Automation with VRF fairness
- **Real-Time Pricing**: Chainlink price feeds with 8-decimal precision
- **Risk Management**: Position limits and maintenance margins
- **Multi-Token Support**: Accept AVAX, LINK, USDC deposits
- **Fair Liquidations**: VRF randomization prevents MEV exploitation

## Development

### Code Structure
```
contracts/
├── Perps.sol                     # Main trading engine
├── CrossChainManager.sol         # CCIP bridge (Sepolia)
├── PoolManager.sol               # Multi-token deposits (Avalanche)
├── PriceOracle.sol              # Chainlink price feeds
├── PerpsCalculations.sol        # Risk calculations
├── PerpsFeeManager.sol          # Fee management
├── VRFRandomizer.sol            # Chainlink VRF integration
├── VRFAutomation.sol            # VRF randomness refresh
├── TimeLiquidationAutomation.sol # Time-based automation
├── LogLiquidationAutomation.sol  # Event-based automation
└── PerpsStructs.sol             # Shared data structures
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass: `npm test`
5. Submit a pull request

### Code Standards
- Follow Solidity style guide
- Maintain comprehensive test coverage
- Document all public functions with NatSpec
- Use descriptive variable names

## Links

### Project Resources
- **Live Application**: [https://pooka-finance-app.vercel.app/](https://pooka-finance-app.vercel.app/)
- **Documentation**: [https://pookafinance.gitbook.io/pookafinance-docs/](https://pookafinance.gitbook.io/pookafinance-docs/)

### GitHub Repositories
- **Frontend Application**: [https://github.com/Dhruv-Varshney-developer/pooka-finance-app](https://github.com/Dhruv-Varshney-developer/pooka-finance-app)
- **Smart Contracts**: [https://github.com/Dhruv-Varshney-developer/pooka-finance-contracts](https://github.com/Dhruv-Varshney-developer/pooka-finance-contracts)
- **AI Agent Backend**: [https://github.com/Devanshgoel-123/AgenticBackendPooka](https://github.com/Devanshgoel-123/AgenticBackendPooka)

## License

MIT License - see [LICENSE](LICENSE) file for details.
