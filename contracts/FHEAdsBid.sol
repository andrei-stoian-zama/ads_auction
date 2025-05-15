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
    /// @notice Auction end time
    uint256 public endTime;

    /// @notice Address of the beneficiary
    address public beneficiary;

    /// @notice Mapping from bidder to their bid value
    mapping(address account => euint64 depositAmount) private deposits;

    /// @notice Decryption of winningTicket
    /// @dev Can be requested by anyone after auction ends
    uint256 private decryptedWinningTicket;

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

    /// @notice Flag indicating whether the auction object has been claimed
    /// @dev WARNING : If there is a draw, only the first highest bidder will get the prize
    ///      An improved implementation could handle this case differently
    ebool private objectClaimed;

    /// @notice Flag to check if the token has been transferred to the beneficiary
    bool public tokenTransferred;

    /// @notice Flag to determine if the auction can be stopped manually
    bool public stoppable;

    /// @notice Flag to check if the auction has been manually stopped
    bool public manuallyStopped = false;

    /// @notice Error thrown when a function is called too early
    /// @dev Includes the time when the function can be called
    error TooEarly(uint256 time);

    /// @notice Error thrown when a function is called too late
    /// @dev Includes the time after which the function cannot be called
    error TooLate(uint256 time);

    /// @notice Constructor to initialize the auction
    /// @param _beneficiary Address of the beneficiary who will receive the highest bid
    /// @param _tokenContract Address of the ConfidentialERC20 token contract used for bidding
    constructor(
        address _beneficiary,
        ConfidentialERC20 _tokenContract
    ) Ownable(msg.sender) {
        // TFHE.setFHEVM(FHEVMConfig.defaultConfig());
        // Gateway.setGateway(GatewayConfig.defaultGatewayContract());
        beneficiary = _beneficiary;
        tokenContract = _tokenContract;
        tokenTransferred = false;
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

        euint64 currentDeposit = deposits[msg.sender];
        if (TFHE.isInitialized(currentDeposit)) {
            deposits[msg.sender] = TFHE.add(currentDeposit, depositEncrypted);
        } else {
            deposits[msg.sender] = depositEncrypted;
        }

        TFHE.allowTransient(deposits[msg.sender], address(tokenContract));
        tokenContract.transferFrom(msg.sender, address(this), deposits[msg.sender]);

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

            ebool isHigher = TFHE.gt(bids_i, bestBid);
            
            bestBid = TFHE.select(isHigher, bids_i, bestBid);
            bestBidToken = TFHE.select(isHigher, TFHE.asEaddress(adProviderAddresses[i]), bestBidToken);
        }
        
        bidWinners[msg.sender] = bestBidToken;
        TFHE.allowThis(bidWinners[msg.sender]);
        TFHE.allow(bidWinners[msg.sender], msg.sender);
    }

/*    /// @notice Initiate the decryption of the winning ticket
    /// @dev Can only be called after the auction ends
    function decryptWinningTicket() public onlyAfterEnd {
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(winningTicket);
        Gateway.requestDecryption(cts, this.setDecryptedWinningTicket.selector, 0, block.timestamp + 100, false);
    }*/

    /// @notice Callback function to set the decrypted winning ticket
    /// @dev Can only be called by the Gateway
    /// @param resultDecryption The decrypted winning ticket
    function setDecryptedWinningTicket(uint256, uint256 resultDecryption) public onlyGateway {
        decryptedWinningTicket = resultDecryption;
    }

    /// @notice Get the decrypted winning ticket
    /// @dev Can only be called after the winning ticket has been decrypted - if `userTickets[account]` is an encryption of decryptedWinningTicket, then `account` won and can call `claim` succesfully
    /// @return The decrypted winning ticket
    function getAdProvider() external view returns (eaddress) {        
        return bidWinners[msg.sender];
    }

/*
    /// @notice Claim the auction object
    /// @dev Succeeds only if the caller was the first to get the highest bid
    function claim() public onlyAfterEnd {
        ebool canClaim = TFHE.and(TFHE.eq(winningTicket, userTickets[msg.sender]), TFHE.not(objectClaimed));
        objectClaimed = TFHE.or(canClaim, objectClaimed);
        TFHE.allowThis(objectClaimed);
        euint64 newBid = TFHE.select(canClaim, TFHE.asEuint64(0), bids[msg.sender]);
        bids[msg.sender] = newBid;
        TFHE.allowThis(bids[msg.sender]);
        TFHE.allow(bids[msg.sender], msg.sender);
    }
    */
/*
    /// @notice Withdraw a bid from the auction
    /// @dev Can only be called after the auction ends and by non-winning bidders
    function withdraw() public onlyAfterEnd {
        euint64 bidValue = bids[msg.sender];
        ebool canWithdraw = TFHE.ne(winningTicket, userTickets[msg.sender]);
        euint64 amount = TFHE.select(canWithdraw, bidValue, TFHE.asEuint64(0));
        TFHE.allowTransient(amount, address(tokenContract));
        tokenContract.transfer(msg.sender, amount);
        euint64 newBid = TFHE.select(canWithdraw, TFHE.asEuint64(0), bids[msg.sender]);
        bids[msg.sender] = newBid;
        TFHE.allowThis(newBid);
        TFHE.allow(newBid, msg.sender);
    }
*/
}