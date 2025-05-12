import { expect } from "chai";
import { network } from "hardhat";

import { createInstance } from "../instance";
import { reencryptEuint64 } from "../reencrypt";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";
import { deployFheAds, deployConfidentialERC20Fixture } from "./AdsAuction.fixture";

describe("AdsAuction", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const erc20 = await deployConfidentialERC20Fixture();
    this.erc20 = erc20;

    const contract = await deployFheAds(erc20);
    this.contractAddress = await contract.getAddress();
    this.adBidContract = contract;
    this.fhevm = await createInstance();
  });

  it("should accept bid", async function () {

    // Mint with Alice account
    const tx1 = await this.erc20.mint(this.signers.alice, 10000);
    tx1.wait();

    const input1 = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    input1.add64(1);
    const encryptedInput1 = await input1.encrypt();
    const input2 = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    input2.add64(2);
    const encryptedInput2 = await input2.encrypt();
    const input3 = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    input3.add64(3);
    const encryptedInput3 = await input3.encrypt();
    const input4 = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    input4.add64(10000);
    const encryptedInput4 = await input4.encrypt();
    
    const tx = await this.adBidContract["bid(bytes32,bytes,bytes32,bytes,bytes32,bytes,bytes32,bytes)"](
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
  });

  it("should accept two bids", async function () {

    // Mint with Alice account
    const tx1 = await this.erc20.mint(this.signers.alice, 10000);
    tx1.wait();
  });

});
