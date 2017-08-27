
pragma solidity ^0.4.15;

import './ARToken.sol';
import './GenericCrowdsale.sol';

   /**
    * @title ARToken Crowdsale
    * @dev A capped crowdsale with Fibonacci bonus structure and minting allowed by manager.
    * Written with OpenZeppelin sources as a rough reference.     
    * Alexander Bokhenek (Modern Token Team) for the ICO of Cappasity's ARToken.
    */

contract Crowdsale is GenericCrowdsale {
    // Token information
    uint constant tokenRate = 34996; // 1 ETH = 34996 ARTokens, 1 wei = 34996 / 1e18 ARTokens
    uint constant hardCap = 7 * 1e9 * 1e18; // 7 billion tokens with 18 decimal digits
    ARToken tokenContract;
    address foundersWallet;          // Where do the founders' token go to, a smart contract with vesting.
    address partnersWallet; // A wallet that distributes the tokens to the early contributors.

    // Crowdsale progress
    uint tokensSold = 0;
    uint totalWeiGathered = 0;
    bool foundersAndPartnersTokensIssued = false;

    // Tracking the bonuses
    uint milestonesReached = 0; // each milestone corresponds to 17500 ETH
    uint constant milestoneSize = 17500 ether;
    mapping (address => uint[10]) contributedAtMilestone;
    // Bonus staircase, a reversed Fibonacci sequence starting with 55
    uint8[10] fibonacci = [55, 34, 21, 13, 8, 5, 3, 2, 1, 1]; 

    /**
     * @dev Constructs the crowdsale.
     * @param _startTime Timestamp when the crowdsale opens.
     * @param _endTime Timestamp when the crowdsale closes (unless the hard cap is reached earlier).
     * @param _icoManager Wallet address that should be owned by the off-chain backend, from which \
     *          \ it mints the tokens for contributions accepted in other currencies.
     * @param _crowdsaleWallet A wallet where all the Ether from successful purchases is sent immediately.
     */
    function Crowdsale(uint _startTime
                      , uint _endTime
                      , address _icoManager
                      , address _crowdsaleWallet
                      , address _foundersWallet
                      , address _partnersWallet
                      ) { 
        require(_startTime >= now);
        require(_endTime >= _startTime);
        require(_icoManager != 0x0);
        require(_crowdsaleWallet != 0x0);

        tokenContract = new ARToken(address(this));

        startTime = _startTime;
        endTime = _endTime;
        icoManager = _icoManager;
        crowdsaleWallet = _crowdsaleWallet;
        foundersWallet = _foundersWallet;
        partnersWallet = _partnersWallet;
    }

    // Fallback function, referring to the token purchase function
    function () { buyTokens(); }

    // PUBLIC FUNCTIONS
    // ================
    // Allows to buy tokens through fallback.
    function buyTokens() public payable crowdsaleOpen returns (bool success) {
        require(msg.value >= 1e16); // only accepting contributions starting from 0.01 ETH

        uint overcap = calculateOvercap(msg.value);
        uint truncatedContribution = msg.value - overcap;
        uint tokensIssued = truncatedContribution * tokenRate;

        if (overcap > 0) (msg.sender).transfer(overcap);
        issueTokens(msg.sender, truncatedContribution);
        TokenPurchase(msg.sender, msg.value, tokensIssued, overcap);
        crowdsaleWallet.transfer(truncatedContribution); 
        return true;
    }

    /**
     * @dev Mints the bonus tokens for a particular address, erasing the record.
     * @param _beneficiary The address for which the bonuses are issued.
     */
    function issueBonus(address _beneficiary) external crowdsaleFinished {
        // Walk through the tier list, assign the bonus for each contribution.
        uint tierBonus;
        uint totalBonus = 0;
        for (uint i = 0; i<milestonesReached; i++) {
            // For each failed funding milestone, the descending bonus staircase loses a step from the left.
            // Thus to calculate the bonus, offset the sequence by 10 - (total milestones reached)
            tierBonus = contributedAtMilestone[_beneficiary][i] * fibonacci[10 - milestonesReached + i] / 100;
            tokenContract.mint(_beneficiary, tierBonus);
            contributedAtMilestone[_beneficiary][i] = 0;
            totalBonus += tierBonus;
        }
        BonusIssued(_beneficiary, totalBonus);
    }

    function rewardFoundersAndPartners() external crowdsaleFinished {
        require( !foundersAndPartnersTokensIssued );

        uint tokensForFounders = tokensSold * 18 / 100;
        uint tokensForPartners = tokensSold * 12 / 100;

        foundersAndPartnersTokensIssued = true;
        tokenContract.mint(foundersWallet, tokensForFounders);
        tokenContract.mint(partnersWallet, tokensForPartners);
        FoundersAndPartnersTokensIssued(foundersWallet, tokensForFounders, partnersWallet, tokensForPartners);
    }

    // PRIVILEGED FUNCTIONS
    // ====================
    function offchainBuyTokens(address _beneficiary
                              , uint _contribution
                              , string _txHash) 
                          external onlyManager crowdsaleOpen returns (bool success, uint overcap) {
        overcap = calculateOvercap(_contribution);
        uint truncatedContribution = _contribution - overcap;
        if (issueTokens(_beneficiary, truncatedContribution)) {
            uint tokensIssued = truncatedContribution * tokenRate;
            OffchainTokenPurchase(_beneficiary, _contribution, _txHash, tokensIssued, overcap);
            return (true, overcap);
        }
    }

    // INTERNAL FUNCTIONS
    // ==================
    /**
     * @dev We track purchases by funding milestones at the time of the contribution.
     */
    function recordTransaction(address _beneficiary, uint _contribution) internal {
        // One contribution may not entirely fit in the current tier. So we'll cut it in parts that fit,
        // updating the current tier as necessary.
        uint remainingContribution = _contribution;
        uint weiToNextTier;
        uint contributionPart;
        do { // If the contribution doesn't fit the current tier, fill the current tier and iterate.
            weiToNextTier = (milestonesReached + 1) * milestoneSize - totalWeiGathered;
            contributionPart = min(remainingContribution, weiToNextTier);
            remainingContribution -= contributionPart;
            totalWeiGathered += contributionPart;
            contributedAtMilestone[_beneficiary][milestonesReached] += contributionPart;
            if (contributionPart == weiToNextTier) milestonesReached += 1;
        } while (remainingContribution > 0);
    }

    function issueTokens(address _beneficiary, uint _contribution) internal returns (bool success) {
        uint tokensToMint = _contribution * tokenRate;
        require( tokensToMint + tokensSold <= hardCap );

        require( tokensToMint + tokensSold <= hardCap );
        require( tokensToMint + tokensSold > tokensSold ); // uint overflow protection just in case

        tokensSold += tokensToMint;
        tokenContract.mint(msg.sender, tokensToMint);
        totalWeiGathered += _contribution;
        recordTransaction(_beneficiary, _contribution);
        return true;
        
    }

    function calculateOvercap(uint _contribution) constant internal returns (uint overcap) {
        if (_contribution * tokenRate + tokensSold > hardCap) {
            uint weiToCap = (hardCap - tokensSold) / tokenRate;
            return _contribution - weiToCap;
        } else return 0;
    }

    function min(uint _a, uint _b) constant internal returns (uint result) {
        if (_a < _b) return _a;
        else return _b;
    }

    modifier crowdsaleOpen() {
        require( (totalWeiGathered < hardCap) && (now > startTime) && (now < endTime) );
        _;
    }

    modifier crowdsaleFinished() {
        require( (totalWeiGathered == hardCap) || (now > endTime) );
        _;
    }
}
