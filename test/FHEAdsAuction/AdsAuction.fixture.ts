import { ethers } from "hardhat";

import type { AdsAuction, MyConfidentialERC20 } from "../../types";
import { getSigners } from "../signers";
import { AddressLike } from "ethers";


export async function deployConfidentialERC20Fixture(): Promise<MyConfidentialERC20> {
  const [deployer] = await ethers.getSigners();

  const contractFactory = await ethers.getContractFactory("MyConfidentialERC20");
  const contract = await contractFactory.connect(deployer).deploy("Naraggara", "NARA"); // City of Zama's battle
  await contract.waitForDeployment();

  return contract;
}

export async function deployFheAds(erc20: AddressLike): Promise<AdsAuction> {

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const adsAuctionFactory = await ethers.getContractFactory("AdsAuction");
  const adsAuctionInst = await adsAuctionFactory.connect(deployer).deploy(deployer.address, erc20) as AdsAuction;

  return adsAuctionInst;
}
