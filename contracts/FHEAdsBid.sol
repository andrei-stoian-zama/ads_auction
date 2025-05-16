// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";

/// @notice Main contract for the blind auction
contract AdsAuction is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller, Ownable2Step {
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
        // TFHE.setFHEVM(FHEVMConfig.defaultConfig());
        // Gateway.setGateway(GatewayConfig.defaultGatewayContract());
        tokenContract = _tokenContract;
    }


    /// @notice Submit a bid with an encrypted value
    /// @dev Transfers tokens from the bidder to the contract
    /// @param profileWeight1 The encrypted bid amount
    /// @param inputProof1 Proof for the encrypted input
    /// @param profileWeight2 The encrypted bid amount
    /// @param inputProof2 Proof for the encrypted input
    /// @param profileWeight3 The encrypted bid amount
    /// @param inputProof3 Proof for the encrypted input
    /// @param profileWeight3 The encrypted bid amount
    /// @param inputProof3 Proof for the encrypted input
    /// @param depositAmount The encrypted bid amount
    /// @param depositProof Proof for the encrypted input
    function bid(einput profileWeight1, 
        bytes calldata inputProof1, 
        einput profileWeight2, 
        bytes calldata inputProof2, 
        einput profileWeight3, 
        bytes calldata inputProof3,
        einput depositAmount, 
        bytes calldata depositProof) external {
        

        AdBid memory bidData = AdBid(TFHE.asEuint64(profileWeight1, inputProof1),
                                        TFHE.asEuint64(profileWeight2, inputProof2),
                                    TFHE.asEuint64(profileWeight3, inputProof3));
        
        TFHE.allowThis(bidData.weightAgeGroup1);
        TFHE.allowThis(bidData.weightAgeGroup2);
        TFHE.allowThis(bidData.weightGenderM);

        bidRules[msg.sender] = bidData;        

        euint64 depositEncrypted = TFHE.asEuint64(depositAmount, depositProof);

        TFHE.allowTransient(depositEncrypted, address(tokenContract));
        tokenContract.transferFrom(msg.sender, address(this), depositEncrypted);

        euint64 currentDeposit = deposits[msg.sender];
        if (TFHE.isInitialized(currentDeposit)) {
            deposits[msg.sender] = TFHE.add(currentDeposit, depositEncrypted);
        } else {
            deposits[msg.sender] = depositEncrypted;
            TFHE.allowThis(deposits[msg.sender]);
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

    function computeAdProvider(einput profileWeight1, 
        bytes calldata inputProof1, 
        einput profileWeight2, 
        bytes calldata inputProof2, 
        einput profileWeight3, 
        bytes calldata inputProof3) external {

        AdBid memory userProfile = AdBid(TFHE.asEuint64(profileWeight1, inputProof1),
                                TFHE.asEuint64(profileWeight2, inputProof2),
                                TFHE.asEuint64(profileWeight3, inputProof3));

        euint64 bestBid = TFHE.asEuint64(0);
        eaddress bestBidToken = TFHE.asEaddress(address(0));

        for (uint256 i = 0; i < adProviderAddresses.length; i++) {
            AdBid memory bidRule_i = bidRules[adProviderAddresses[i]];
            
            euint64 bids_i = TFHE.asEuint64(0);

            bids_i = TFHE.add(bids_i, TFHE.mul(userProfile.weightAgeGroup1, bidRule_i.weightAgeGroup1));
            bids_i = TFHE.add(bids_i, TFHE.mul(userProfile.weightAgeGroup2, bidRule_i.weightAgeGroup2));
            bids_i = TFHE.add(bids_i, TFHE.mul(userProfile.weightGenderM, bidRule_i.weightGenderM));

            ebool isHigher = TFHE.and(TFHE.gt(bids_i, bestBid), TFHE.le(bids_i, deposits[adProviderAddresses[i]]));
            
            bestBid = TFHE.select(isHigher, bids_i, bestBid);
            bestBidToken = TFHE.select(isHigher, TFHE.asEaddress(adProviderAddresses[i]), bestBidToken);
        }
        
        for (uint256 i = 0; i < adProviderAddresses.length; i++) {
            euint64 debitThisDepositAmount = TFHE.select(TFHE.eq(bestBidToken, adProviderAddresses[i]), bestBid, TFHE.asEuint64(0));
            deposits[adProviderAddresses[i]] = TFHE.sub(deposits[adProviderAddresses[i]], debitThisDepositAmount);
            TFHE.allowThis(deposits[adProviderAddresses[i]]);
        }

        bidWinners[msg.sender] = bestBidToken;
        TFHE.allowThis(bidWinners[msg.sender]);
        TFHE.allow(bidWinners[msg.sender], msg.sender);
    }

    /// @notice Get the decrypted winning ticket
    /// @dev Can only be called after the winning ticket has been decrypted - if `userTickets[account]` is an encryption of decryptedWinningTicket, then `account` won and can call `claim` succesfully
    /// @return The decrypted winning ticket
    function getAdProvider() external view returns (eaddress) {        
        return bidWinners[msg.sender];
    }

    function withdraw() external {
        if (TFHE.isInitialized(deposits[msg.sender])) {
            TFHE.allow(deposits[msg.sender], address(tokenContract));
            tokenContract.transfer(msg.sender, deposits[msg.sender]);
            deposits[msg.sender] = TFHE.asEuint64(0);
        }
    }
}