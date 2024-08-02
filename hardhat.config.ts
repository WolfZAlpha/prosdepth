import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

const {
  ARBITRUM_RPC_URL,
  ARBISCAN_API_KEY,
  DEPLOYER_PRIVATE_KEY
} = process.env;

if (!ARBITRUM_RPC_URL || !ARBISCAN_API_KEY || !DEPLOYER_PRIVATE_KEY) {
  throw new Error("Please set your ARBITRUM_RPC_URL, ARBISCAN_API_KEY, and DEPLOYER_PRIVATE_KEY in a .env file");
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "cancun",
    },
  },
  networks: {
    arbitrum: {
      url: ARBITRUM_RPC_URL,
      chainId: 42161,
      accounts: [DEPLOYER_PRIVATE_KEY],
      gasPrice: "auto",
    },
  },
  etherscan: {
    apiKey: {
      arbitrumOne: ARBISCAN_API_KEY,
    },
  },
  sourcify: {
    enabled: true,
  },
};

export default config;