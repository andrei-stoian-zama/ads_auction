import { expect } from "chai";
import { network } from "hardhat";

import { getFHEGasFromTxReceipt } from "../coprocessorUtils";
import { createInstance } from "../instance";
import { getSigners, initSigners } from "../signers";
import { deployFheAds } from "./AdsAuction.fixture";

/*
describe("AdsAuction:FHEGas", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const contract = await deployFheAds();
    this.contractAddress = await contract.getAddress();
    this.erc20 = contract;
    this.fhevm = await createInstance();
  });

  it("gas consumed during bid", async function () {
    const transaction = await this.erc20.mint(this.signers.alice, 10000);
    const t1 = await transaction.wait();
    expect(t1?.status).to.eq(1);

    const input = this.fhevm.createEncryptedInput(this.contractAddress, this.signers.alice.address);
    input.add64(1337);

    const encryptedTransferAmount = await input.encrypt();
    const tx = await this.erc20["transfer(address,bytes32,bytes)"](
      this.signers.bob,
      encryptedTransferAmount.handles[0],
      encryptedTransferAmount.inputProof,
    );
    const t2 = await tx.wait();
    expect(t2?.status).to.eq(1);
    if (network.name === "hardhat") {
      // `getFHEGasFromTxReceipt` function only works in mocked mode but gives same exact FHEGas consumed than on the real fhEVM
      const FHEGasConsumedTransfer = getFHEGasFromTxReceipt(t2);
      console.log("FHEGas Consumed during transfer", FHEGasConsumedTransfer);
    }
    // contrarily to FHEGas, native gas in mocked mode slightly differs from the real gas consumption on fhevm (underestimated by ~20%)
    console.log("Native Gas Consumed during transfer", t2.gasUsed);
  });

});
    */
