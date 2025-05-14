import { expect } from "chai";
import { network } from "hardhat";

import { createInstance } from "../instance";
import { reencryptEuint64 } from "../reencrypt";
import { getSigners, initSigners } from "../signers";
import { debug } from "../utils";
import { deployFheAds, deployConfidentialERC20Fixture, mintAndAllow, bidAndDeposit} from "./AdsAuction.fixture";

describe("AdsAuction", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const erc20 = await deployConfidentialERC20Fixture();
    this.erc20 = erc20;
    this.erc20Address = await erc20.getAddress();

    const contract = await deployFheAds(erc20);
    this.contractAddress = await contract.getAddress();
    this.adBidContract = contract;
    this.fhevm = await createInstance();
  });

  it("should accept bids", async function () {

    // Alice has 10 000, Bob has 20 000
    await mintAndAllow(this.fhevm, this.erc20, this.erc20Address, this.contractAddress, this.signers.alice, 10000);
    await mintAndAllow(this.fhevm, this.erc20, this.erc20Address, this.contractAddress, this.signers.bob, 20000);
    
    // Both Alice and Bob deposit 10 000 and set up bid rules
    await bidAndDeposit(this.fhevm, this.adBidContract, this.contractAddress, this.signers.alice, 1000, 1000, 1000, 10000);
    //await bidAndDeposit(this.fhevm, this.adBidContract, this.contractAddress, this.signers.bob, 2000, 1000, 5000, 10000);

    const aliceBalanceHandle = await this.erc20.balanceOf(this.signers.alice);
    const aliceBalance = await reencryptEuint64(
      this.signers.alice,
      this.fhevm,
      aliceBalanceHandle,
      this.erc20Address,
    );
    expect(aliceBalance).to.equal(0);


    const bobBalanceHandle = await this.erc20.balanceOf(this.signers.bob);
    const bobBalance = await reencryptEuint64(
      this.signers.bob,
      this.fhevm,
      bobBalanceHandle,
      this.erc20Address,
    );
    expect(bobBalance).to.equal(20000);    
  });

  it("should accept two bids", async function () {

    // Mint with Alice account
    const tx1 = await this.erc20.mint(this.signers.alice, 10000);
    tx1.wait();
  });

});
