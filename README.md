# Pooka Finance - Smart Contracts

AI powered Cross-chain perpetual trading protocol built on Avalanche with Ethereum integration via Chainlink CCIP.

## Overview

Pooka Finance enables leveraged cryptocurrency trading across multiple blockchain networks. Users can deposit USDC from Ethereum (Sepolia) and trade BTC/USD and ETH/USD perpetual futures on Avalanche (Fuji) with up to 3x leverage.

## Architecture

The protocol consists of smart contracts deployed across two chains:

### Avalanche Fuji (Main Trading Chain)
- **Perps.sol** - Core perpetual trading engine
- **Pool.sol** - Multi-token deposit handler and liquidity management
- **PriceOracle.sol** - Chainlink price feed integration
- **Automation contracts** - Automated liquidation systems

### Ethereum Sepolia (Cross-Chain Bridge)
- **CrossChainManager.sol** - CCIP-based USDC bridging to Avalanche

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

#### `Pool.sol` (Avalanche)
Multi-token deposit handler:
- Accepts AVAX, LINK, and USDC deposits
- Converts tokens to USDC using Chainlink price feeds
- Forwards converted USDC to Perps contract
- Handles both direct deposits and cross-chain CCIP messages

### Automation & Oracles

#### `VRFRandomizer.sol`
Chainlink VRF integration for fair liquidation ordering:
- Generates verifiable randomness
- Shuffles user arrays to prevent liquidation front-running
- Auto-refreshes randomness every 6 hours

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

### Ethereum Sepolia Testnet
- **USDC Token**: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- **LINK Token**: `0x779877A7B0D9E8603169DdbD7836e478b4624789`
- **CCIP Router**: `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59`
- **Chain Selector**: `16015286601757825753`

## Usage Example

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

### Cross-Chain Deposit

```solidity
// On Sepolia: Deposit USDC to bridge to Avalanche
crossChainManager.depositAndSend(10_000_000); // $10 USDC
// Automatically appears in user's Avalanche balance
```

## Key Features

- **Leverage Trading**: Up to 3x leverage on BTC/USD and ETH/USD
- **Cross-Chain Deposits**: Seamless USDC bridging from Ethereum
- **Automated Liquidations**: Chainlink Automation with VRF fairness
- **Real-Time Pricing**: Chainlink price feeds with 8-decimal precision
- **Risk Management**: Position limits and maintenance margins
- **Multi-Token Support**: Accept AVAX, LINK, USDC deposits

## Development

### Code Structure
```
contracts/
├── Perps.sol                    # Main trading engine
├── CrossChainManager.sol        # CCIP bridge (Sepolia)
├── Pool.sol                     # Multi-token deposits (Avalanche)
├── PriceOracle.sol             # Chainlink price feeds
├── PerpsCalculations.sol       # Risk calculations
├── PerpsFeeManager.sol         # Fee management
├── VRFRandomizer.sol           # Chainlink VRF integration
├── TimeLiquidationAutomation.sol # Time-based automation
├── LogLiquidationAutomation.sol  # Event-based automation
└── PerpsStructs.sol            # Shared data structures
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

## License

MIT License - see [LICENSE](LICENSE) file for details.
