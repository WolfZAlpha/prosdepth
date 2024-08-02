import { ethers, upgrades, run, network, artifacts } from "hardhat";
import * as dotenv from "dotenv";
import * as fs from 'fs';

dotenv.config();

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Starting deployment process on", network.name);
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");

  // Define addresses
  console.log("\nInitializing wallet addresses...");
  const gnosisSafeWallet = process.env.GNOSIS_SAFE_ADDRESS as string;
  const taxWallet = "0xcb199b6Fd0F6af233E57Ce97E6374244F9EEF6E6"; // tax collection wallet .
  const stakingWallet = "0xc0018f6264255BEE54963ccA623624c443a23829"; // staking supply wallet . 
  const icoWallet = "0xAa1E93255DC04DDA3a2E9bF7337CE9C934f26F9f"; // raise collection wallet .
  const liquidityWallet = "0x3226B58F05F5aB6Cd42C93909D4878ed97AeA0bE"; // supply for LP .
  const farmingWallet = "0xcc12E202D52825E4056690E4476b90Da29187709"; // farming supply .
  const listingWallet = "0x1ed12B8aD96dD65F5c0c31Dd5cadFAC06170D243"; // listing wallet supply .
  const reserveWallet = "0x85f604F216d5f095B0DF090930202983c4767204"; // reserves supply .
  const marketingWallet = "0xAb5b9F315aA9fb30A3fAe23A279219aAD0ecC2a2"; // marketing supply .
  const teamWallet = "0x58fa9d070410e3F9599C984E5e83064be0bB0966"; // team supply .
  const devWallet = "0x8F27d3D862f3530aEB9c5f1D36d5d5e56C46a1CD"; // dev supply .
  console.log("Wallet addresses initialized successfully.");

  // Define vesting wallets
  console.log("\nInitializing vesting wallets...");
  const vestingWallets = [
    { address: "0xfDFe01A804DaF737a1a44B062aA09e2A0807620A", vestingType: 0, amount: ethers.parseEther("8750") }, // mods
    { address: "0x8716462a8F18bef868c228ADc95dD08c1d4817E9", vestingType: 0, amount: ethers.parseEther("8750") }, // mods
    { address: "0xB37D13e92058a33A6bc306D8836a2Cb7308c7Cb0", vestingType: 0, amount: ethers.parseEther("8750") }, // mods
    { address: "0xA4d0A68f581DD7F0360520fcBA9Bf6D9c8368Dd5", vestingType: 0, amount: ethers.parseEther("8750") }, // mods
    { address: "0x156841B0541F11522656A8FA6d0542B737754E8e", vestingType: 0, amount: ethers.parseEther("105000") },
    { address: "0x156841B0541F11522656A8FA6d0542B737754E8e", vestingType: 0, amount: ethers.parseEther("105000") },
    { address: "0x87715D8cC9F32e694CB644fce3b86F4C7311aD15", vestingType: 0, amount: ethers.parseEther("105000") },
    { address: "0x4c6A8Ff3bADe54BCFf3c63Aa84Cb8985c68F0A30", vestingType: 0, amount: ethers.parseEther("105000") },
    { address: "0x3bda56ef07bf6f996f8e3defddde6c8109b7e7be", vestingType: 0, amount: ethers.parseEther("105000") },
    { address: "0xA2526C8DD2560ef4ad8D0A8E2d8201819A92Ae96", vestingType: 0, amount: ethers.parseEther("105000") },
    { address: "0xb6b6E3a54BCAF861ac456b38D15389dC8E638450", vestingType: 0, amount: ethers.parseEther("700000") }, // milli
    { address: "0x0fcD04410E6DA9339c1578C9f7aC1e48AED4B73C", vestingType: 0, amount: ethers.parseEther("1750000") }, // bones
    { address: "0x0c45809731a3E88373b63DcA6A1a19dE98843568", vestingType: 0, amount: ethers.parseEther("5000000") }, //books
    { address: "0xC0fF3Af640B344AaDfdC8909BF9826D452bf1718", vestingType: 1, amount: ethers.parseEther("10000000") },
    { address: "0xB50516982524DFF3d8d563F46AD54891Aa61944E", vestingType: 1, amount: ethers.parseEther("35000000") },
    { address: "0x89D6a038D902fEAb8c506C3F392b1B91CA8461B7", vestingType: 1, amount: ethers.parseEther("40000000") },
    { address: "0x8F27d3D862f3530aEB9c5f1D36d5d5e56C46a1CD", vestingType: 1, amount: ethers.parseEther("60000000") },
  ];
  console.log("Vesting wallets initialized successfully.");

  async function delay(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async function verifyContract(address: string, constructorArguments: any[] = []) {
    console.log(`Attempting to verify contract at ${address}`);
    try {
      await run("verify:verify", {
        address: address,
        constructorArguments: constructorArguments,
      });
      console.log("Contract verified successfully");
    } catch (error: any) {
      if (error.message.toLowerCase().includes("already verified")) {
        console.log("Contract is already verified!");
      } else {
        console.error("Error verifying contract:", error);
      }
    }
  }

  async function deployAndVerify(name: string, factory: any, args: any[] = [], initializer = 'initialize') {
    console.log(`\nDeploying ${name}...`);
    console.log(`Deployment arguments:`, args);
    try {
      const contract = await upgrades.deployProxy(factory, args, { initializer: initializer, kind: 'uups' });
      await contract.waitForDeployment();
      const address = await contract.getAddress();
      console.log(`${name} deployed successfully.`);
      console.log(`Contract address: ${address}`);

      console.log("Waiting for 1 minute before verification...");
      await delay(60000);

      console.log(`Verifying ${name} implementation...`);
      const implementationAddress = await upgrades.erc1967.getImplementationAddress(address);
      await verifyContract(implementationAddress);

      const artifact = await artifacts.readArtifact(name);
      fs.writeFileSync(`${name}_ABI.json`, JSON.stringify(artifact.abi, null, 2));
      console.log(`${name} ABI saved to ${name}_ABI.json`);

      return { contract, address };
    } catch (error) {
      console.error(`Error deploying or verifying ${name}:`, error);
      throw error;
    }
  }

  // Deploy PROSPERAICO
  console.log("\nDeploying PROSPERAICO contract...");
  const PROSPERAICO = await ethers.getContractFactory("PROSPERAICO");
  const { contract: prosperaICO, address: icoAddress } = await deployAndVerify("PROSPERAICO", PROSPERAICO, [icoWallet, taxWallet]);

  // Deploy PROSPERAVesting
  console.log("\nDeploying PROSPERAVesting contract...");
  const PROSPERAVesting = await ethers.getContractFactory("PROSPERAVesting");
  const { contract: prosperaVesting, address: vestingAddress } = await deployAndVerify("PROSPERAVesting", PROSPERAVesting);

  // Deploy main PROSPERA contract
  console.log("\nDeploying main PROSPERA contract...");
  const PROSPERAFactory = await ethers.getContractFactory("PROSPERA");
  const { contract: prospera, address: prosperaAddress } = await deployAndVerify("PROSPERA", PROSPERAFactory, [{
    deployerWallet: deployer.address,
    taxWallet,
    stakingWallet,
    icoWallet,
    liquidityWallet,
    farmingWallet,
    listingWallet,
    reserveWallet,
    marketingWallet,
    teamWallet,
    devWallet
  }, {
    vestingContract: vestingAddress,
    icoContract: icoAddress
  }, true]); // Added 'true' for _icoActive parameter

  // Update the PROSPERA address in child contracts
  console.log("\nUpdating PROSPERA address in child contracts...");
  await (await prosperaICO.setProsperaContract(prosperaAddress)).wait();
  await (await prosperaVesting.setProsperaContract(prosperaAddress)).wait();

  // Set up PROSPERAICO
  console.log("\nSetting up PROSPERAICO...");
  await (await prosperaICO.setProsperaContractAndTransferTokens(prosperaAddress)).wait();

  // Add vesting schedules
  console.log("\nAdding vesting schedules...");
  for (const wallet of vestingWallets) {
    try {
      const addToVestingTx = await prospera.addAccountToVesting(wallet.address, wallet.amount, wallet.vestingType);
      await addToVestingTx.wait();
      console.log(`Vesting schedule added for ${wallet.address}`);
    } catch (error) {
      console.error(`Error adding vesting schedule for ${wallet.address}:`, error);
    }
  }
  console.log("All vesting schedules added successfully.");

  // Transfer ownership of all contracts to the Gnosis Safe wallet
  console.log("\nTransferring ownership to Gnosis Safe wallet...");
  const contracts = [prospera, prosperaICO, prosperaVesting];
  for (const contract of contracts) {
    try {
      const currentOwner = await contract.owner();
      if (currentOwner.toLowerCase() !== gnosisSafeWallet.toLowerCase()) {
        console.log(`Transferring ownership of ${await contract.getAddress()} from ${currentOwner} to ${gnosisSafeWallet}`);
        const transferTx = await contract.transferOwnership(gnosisSafeWallet);
        await transferTx.wait();
        console.log(`Ownership of ${await contract.getAddress()} transferred successfully to Gnosis Safe wallet: ${gnosisSafeWallet}`);
      } else {
        console.log(`${await contract.getAddress()} is already owned by ${gnosisSafeWallet}`);
      }
    } catch (error) {
      console.error(`Error transferring ownership for contract ${await contract.getAddress()}:`, error);
    }
  }

  // Save proxy addresses
  const proxyAddresses = {
    PROSPERA: prosperaAddress,
    PROSPERAICO: icoAddress,
    PROSPERAVesting: vestingAddress
  };

  fs.writeFileSync('proxyAddresses.json', JSON.stringify(proxyAddresses, null, 2));
  console.log("\nProxy addresses saved successfully to proxyAddresses.json");

  console.log("\nDeployment, verification, and setup completed successfully.");
}

main().catch((error) => {
  console.error("Deployment failed with error:", error);
  process.exitCode = 1;
});