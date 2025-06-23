import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-verify";
import "dotenv/config";
import "@nomicfoundation/hardhat-ethers";

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    sepolia: {
      url:
        process.env.SEPOLIA_RPC_URL ||
        "https://ethereum-sepolia.publicnode.com",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    avax_testnet: {
      url:
        process.env.AVAX_RPC_URL ||
        "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      // Snowtrace is used for avax_testnet.
      // Details:
      // https://testnet.snowtrace.io/documentation/recipes/hardhat-verification
      // https://docs.avax.network/build/tools/snowtrace/hardhat-verification
      avax_testnet: "snowtrace", // apiKey is not required.
    },
    customChains: [
      {
        network: "avax_testnet",
        chainId: 43113,
        urls: {
          apiURL:
            "https://api.routescan.io/v2/network/testnet/evm/43113/etherscan",
          browserURL: "https://avalanche.testnet.localhost:8080",
        },
      },
    ],
  },
};

export default config;
