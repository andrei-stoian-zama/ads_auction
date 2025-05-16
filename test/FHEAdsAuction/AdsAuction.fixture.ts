import { ethers } from "hardhat";
import { expect } from "chai";

import type { AdsAuction, ConfidentialERC20, MyConfidentialERC20 } from "../../types";
import { getSigners } from "../signers";
import { AddressLike } from "ethers";
import { reencryptEaddress, reencryptEuint256, reencryptEuint64 } from "../reencrypt";

import { FhevmInstance } from "fhevmjs/node";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";


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
  const adsAuctionInst = await adsAuctionFactory.connect(deployer).deploy(erc20) as AdsAuction;

  return adsAuctionInst;
}


export async function mintAndAllow(fhevm: FhevmInstance, erc20: MyConfidentialERC20, erc20Addr: string, bidContractAddr: string, owner: HardhatEthersSigner, amount: number) {


    // Mint with Alice account
    const tx1 = await erc20.mint(owner, amount);
    tx1.wait();

    const amountAliceBids = fhevm.createEncryptedInput(erc20Addr, owner.address);
    amountAliceBids.add64(amount);
    const encryptedAllowanceAmount = await amountAliceBids.encrypt();

    const txApprove = await erc20.connect(owner)["approve(address,bytes32,bytes)"](
      bidContractAddr,
      encryptedAllowanceAmount.handles[0],
      encryptedAllowanceAmount.inputProof,
    );

    await expect(txApprove)
      .to.emit(erc20, "Approval");

}

export async function bidAndDeposit(fhevm: FhevmInstance, bidContract: AdsAuction, bidContractAddr: string, owner: HardhatEthersSigner, weight1: number, weight2: number, weight3: number, amount: number) {

  const input1 = fhevm.createEncryptedInput(bidContractAddr, owner.address);
  input1.add64(weight1);
  const encryptedInput1 = await input1.encrypt();

  const input2 = fhevm.createEncryptedInput(bidContractAddr, owner.address);
  input2.add64(weight2);
  const encryptedInput2 = await input2.encrypt();

  const input3 = fhevm.createEncryptedInput(bidContractAddr, owner.address);
  input3.add64(weight3);
  const encryptedInput3 = await input3.encrypt();

  const input4 = fhevm.createEncryptedInput(bidContractAddr, owner.address);
  input4.add64(amount);
  const encryptedInput4 = await input4.encrypt();
  
  const tx = await bidContract.connect(owner)["bid(bytes32,bytes,bytes32,bytes,bytes32,bytes,bytes32,bytes)"](
    encryptedInput1.handles[0],
    encryptedInput1.inputProof,
    encryptedInput2.handles[0],
    encryptedInput2.inputProof,
    encryptedInput3.handles[0],
    encryptedInput3.inputProof,
    encryptedInput4.handles[0],
    encryptedInput4.inputProof,
  );
  const t2 = await tx.wait();
  expect(t2?.status).to.eq(1);

}

export async function getAd(fhevm: FhevmInstance, bidContract: AdsAuction, bidContractAddr: string, requester: HardhatEthersSigner, weight1: number, weight2: number, weight3: number): Promise<bigint> {
 
  const input1 = fhevm.createEncryptedInput(bidContractAddr, requester.address);
  input1.add64(weight1);
  const encryptedInput1 = await input1.encrypt();

  const input2 = fhevm.createEncryptedInput(bidContractAddr, requester.address);
  input2.add64(weight2);
  const encryptedInput2 = await input2.encrypt();

  const input3 = fhevm.createEncryptedInput(bidContractAddr, requester.address);
  input3.add64(weight3);
  const encryptedInput3 = await input3.encrypt();


  const tx = await bidContract.connect(requester).computeAdProvider(
    encryptedInput1.handles[0],
    encryptedInput1.inputProof,
    encryptedInput2.handles[0],
    encryptedInput2.inputProof,
    encryptedInput3.handles[0],
    encryptedInput3.inputProof,
  );
  const t2 = await tx.wait();
  expect(t2?.status).to.eq(1);

  const adProviderIdHandle = await bidContract.connect(requester).getAdProvider();

  console.log(typeof adProviderIdHandle);

  const adProviderId = await reencryptEaddress(
    requester,
    fhevm,
    adProviderIdHandle,
    bidContractAddr,
  );

  return adProviderId;
}