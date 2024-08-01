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
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    arbitrum: {
      url: ARBITRUM_RPC_URL,
      chainId: 42161,
      accounts: [DEPLOYER_PRIVATE_KEY],
      gasPrice: "auto",
      gas: 8000000,  // Adjusted gas limit for safety
    },
  },
  etherscan: {
    apiKey: {
      arbitrumOne: ARBISCAN_API_KEY,  // Ensure this key name is correct
    },
  },
  sourcify: {
    enabled: true,  // Optional: Enable Sourcify verification if needed
  },
};

export default config;
