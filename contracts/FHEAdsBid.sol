// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;


import {FHE, externalEuint64, euint256, eaddress, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaFHEVMConfig} from "@fhevm/solidity/config/FHEVMConfig.sol";

import {FHEVMConfigStruct} from "@fhevm/solidity/lib/Impl.sol";
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "fhevm/config/ZamaGatewayConfig.sol";

/// @notice Main contract for the blind auction
contract AdsAuction is SepoliaFHEVMConfig, SepoliaZamaGatewayConfig, Ownable2Step {
    /// @notice Mapping from bidder to their bid value
    mapping(address account => euint64 depositAmount) private deposits;

    /// @notice Ticket randomly sampled for each user
    mapping(address account => euint256 ticket) private userTickets;

    struct AdBid { 
        euint64 weightAgeGroup1;
        euint64 weightAgeGroup2;
        euint64 weightGenderM;
    }

    /// @notice Mapping from bidder to their bid value
    mapping(address account => AdBid bidRules) private bidRules;

    /// @notice Mapping from bidder to their bid value
    mapping(address account => eaddress bidWinner) private bidWinners;

    /// @notice List of ad providers
    address[] public adProviderAddresses;

    /// @notice The token contract used for encrypted bids
    ConfidentialERC20 public tokenContract;

    /// @notice Constructor to initialize the auction
    /// @param _tokenContract Address of the ConfidentialERC20 token contract used for bidding
    constructor(
        ConfidentialERC20 _tokenContract
    ) Ownable(msg.sender) {
        FHE.setCoprocessor(FHEVMConfigStruct({
                ACLAddress: 0x687820221192C5B662b25367F70076A37bc79b6c,
                FHEVMExecutorAddress: 0x848B0066793BcC60346Da1F49049357399B8D595,
                KMSVerifierAddress: 0x1364cBBf2cDF5032C47d8226a6f6FBD2AFCDacAC,
                InputVerifierAddress: 0xbc91f3daD1A5F19F8390c400196e58073B6a0BC4
            }));
          FHE.setDecryptionOracle(0xb6E160B1ff80D67Bfe90A85eE06Ce0A2613607D1);
        tokenContract = _tokenContract;
    }

    /// @notice Deposit tokens for use on the ad platform
    /// @dev Transfers tokens from the bidder to the contract
    /// @param newDepositAmount The encrypted bid amount
    function deposit(externalEuint64 newDepositAmount) external {
        euint64 depositEncrypted = FHE.fromExternal(newDepositAmount);
        FHE.allowTransient(depositEncrypted, address(tokenContract));
        tokenContract.transferFrom(msg.sender, address(this), depositEncrypted);

        euint64 currentDeposit = deposits[msg.sender];
        if (FHE.isInitialized(currentDeposit)) {
            deposits[msg.sender] = FHE.add(currentDeposit, depositEncrypted);
            FHE.allow(deposits[msg.sender], msg.sender);
        } else {
            deposits[msg.sender] = depositEncrypted;
            FHE.allowThis(deposits[msg.sender]);
            FHE.allow(deposits[msg.sender], msg.sender);
        }

        bool exists = false;
        for (uint256 i = 0; i < adProviderAddresses.length; i++) {
            if (adProviderAddresses[i] == msg.sender) {
                exists = true;
            }
        }

        if (!exists) {
            adProviderAddresses.push(msg.sender);
        }
    }

    /// @notice Submit a bid with an encrypted value
    /// @dev Transfers tokens from the bidder to the contract
    /// @param profileWeight1 The encrypted bid amount
    /// @param profileWeight2 The encrypted bid amount
    /// @param profileWeight3 The encrypted bid amount
    function bid(externalEuint64 profileWeight1, 
        externalEuint64 profileWeight2, 
        externalEuint64 profileWeight3) external {
                
        AdBid memory bidData = AdBid(FHE.fromExternal(profileWeight1),
                                        FHE.fromExternal(profileWeight2),
                                    FHE.fromExternal(profileWeight3));
        
        FHE.allowThis(bidData.weightAgeGroup1);
        FHE.allowThis(bidData.weightAgeGroup2);
        FHE.allowThis(bidData.weightGenderM);

        bidRules[msg.sender] = bidData;        
    }

    function computeAdProvider(externalEuint64 profileWeight1, 
        externalEuint64 profileWeight2, 
        externalEuint64 profileWeight3) external {

        AdBid memory userProfile = AdBid(FHE.fromExternal(profileWeight1),
                                FHE.fromExternal(profileWeight2),
                                FHE.fromExternal(profileWeight3));

        euint64 bestBid = FHE.asEuint64(0);
        eaddress bestBidToken = FHE.asEaddress(address(0));

        for (uint256 i = 0; i < adProviderAddresses.length; i++) {
            AdBid memory bidRule_i = bidRules[adProviderAddresses[i]];
            
            euint64 bids_i = FHE.asEuint64(0);

            bids_i = FHE.add(bids_i, FHE.mul(userProfile.weightAgeGroup1, bidRule_i.weightAgeGroup1));
            bids_i = FHE.add(bids_i, FHE.mul(userProfile.weightAgeGroup2, bidRule_i.weightAgeGroup2));
            bids_i = FHE.add(bids_i, FHE.mul(userProfile.weightGenderM, bidRule_i.weightGenderM));

            ebool isHigher = FHE.and(FHE.gt(bids_i, bestBid), FHE.le(bids_i, deposits[adProviderAddresses[i]]));
            
            bestBid = FHE.select(isHigher, bids_i, bestBid);
            bestBidToken = FHE.select(isHigher, FHE.asEaddress(adProviderAddresses[i]), bestBidToken);
        }
        
        for (uint256 i = 0; i < adProviderAddresses.length; i++) {
            euint64 debitThisDepositAmount = FHE.select(FHE.eq(bestBidToken, adProviderAddresses[i]), bestBid, FHE.asEuint64(0));
            deposits[adProviderAddresses[i]] = FHE.sub(deposits[adProviderAddresses[i]], debitThisDepositAmount);
            FHE.allowThis(deposits[adProviderAddresses[i]]);
            FHE.allow(deposits[adProviderAddresses[i]], adProviderAddresses[i]);
        }

        bidWinners[msg.sender] = bestBidToken;
        FHE.allowThis(bidWinners[msg.sender]);
        FHE.allow(bidWinners[msg.sender], msg.sender);
    }

    /// @notice Get the decrypted winning ticket
    /// @dev Can only be called after the winning ticket has been decrypted - if `userTickets[account]` is an encryption of decryptedWinningTicket, then `account` won and can call `claim` succesfully
    /// @return The decrypted winning ticket
    function getAdProvider() external view returns (eaddress) {        
        return bidWinners[msg.sender];
    }

    function withdraw() external {
        if (FHE.isInitialized(deposits[msg.sender])) {
            FHE.allow(deposits[msg.sender], address(tokenContract));
            tokenContract.transfer(msg.sender, deposits[msg.sender]);
            deposits[msg.sender] = FHE.asEuint64(0);
        }
    }

    function getDeposit() external view returns (euint64) {
        return deposits[msg.sender];
    }
}