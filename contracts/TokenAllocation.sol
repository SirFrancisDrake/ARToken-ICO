pragma solidity ^0.4.15;

import './ARToken.sol';
import './VestingWallet.sol';

   /**
    * @dev A capped crowdsale with Fibonacci bonus structure and minting allowed by manager.
    * Written with OpenZeppelin sources as a rough reference.     
    * Alexander Bokhenek (Modern Token Team) for the ICO of Cappasity's ARToken.
    */

contract TokenAllocation {
    // Token information
    uint constant tokenRate = 34996; // 1 ETH = 34996 ARTokens; so 1 wei = 34996 / 1e18 ARTokens
    ARToken tokenContract;
    address foundersWallet; // A wallet permitted to request tokens from the time vault.
    address partnersWallet; // A wallet that distributes the tokens to early contributors.
    address crowdsaleWallet; // A wallet where the money goes to
    address public icoManager;
    
    // Events
    event TokenPurchase(address _beneficiary, uint _contribution, uint _tokensIssued, uint _overcap);
    event OffchainTokenPurchase(address _beneficiary, uint _contribution, string _txHash, 
                                uint _tokensIssued, uint _overcap, uint totalWeiBeforeContribution);
    event BonusIssued(address _beneficiary, uint _bonusTokensIssued);
    event FoundersAndPartnersTokensIssued(address foundersWallet, uint tokensForFounders,   //Warning: This declaration shadows an existing declaration (line 16)
                                          address partnersWallet, uint tokensForPartners);  //Warning: This declaration shadows an existing declaration (line 17)
                                          
    
    // Crowdsale progress
    uint constant hardCap = 175000 ether;
    uint totalWeiGathered = 0;
    bool foundersAndPartnersTokensIssued = false;
    VestingWallet vestingWallet;

    // Tracking the bonuses
    uint milestonesReached = 0; // each milestone corresponds to 17500 ETH
    uint constant milestoneSize = 17500 ether;
    
    // Bonus staircase, a reversed Fibonacci sequence starting with 55
    uint8[10] fibonacci = [55, 34, 21, 13, 8, 5, 3, 2, 1, 1]; 

    /**
     * @dev Constructs the crowdsale.
     * @param _icoManager Wallet address that should be owned by the off-chain backend, from which \
     *          \ it mints the tokens for contributions accepted in other currencies.
     * @param _crowdsaleWallet A wallet where all the Ether from successful purchases is sent immediately.
     * @param _foundersWallet Where the founders' tokens to to after vesting.
     * @param _partnersWallet A wallet that distributes tokens to early contributors.
     */
    function Crowdsale(address _icoManager
                     , address _crowdsaleWallet
                     , address _foundersWallet
                     , address _partnersWallet
                     , uint _totalWeiGathered
                     ) { 
        require(_icoManager != 0x0);
        require(_crowdsaleWallet != 0x0);
        require(_foundersWallet != 0x0);
        require(_partnersWallet != 0x0);
        require(_totalWeiGathered == 0);              //dunno, is it necessary or not
        
        tokenContract = new ARToken(address(this));

        icoManager = _icoManager;
        crowdsaleWallet = _crowdsaleWallet;
        foundersWallet = _foundersWallet;
        partnersWallet = _partnersWallet;
        totalWeiGathered = _totalWeiGathered;         //dunno, is it necessary or not
    }

    // PUBLIC FUNCTIONS
    // ================

    function rewardFoundersAndPartners() external {
        require( !foundersAndPartnersTokensIssued );

        // Calculating the total amount of tokens in the system, including not yet issued bonuses:
        // 1. Total wei received * rate of tokens created per wei;
        // 2. For each milestone reached, a bonus on enough ether to fill a milestone entirely.
        // 3. If there's a tier that was reached but was not filled, it gets no bonuses.
        uint totalTokenSupply = totalWeiGathered * tokenRate;
        for (uint i = 0; i<milestonesReached; i++)
            totalTokenSupply += calculateBonusForTier(milestoneSize, i);

        uint tokensForFounders = totalTokenSupply * 18 / 100;
        uint tokensForPartners = totalTokenSupply * 12 / 100;

        foundersAndPartnersTokensIssued = true;

        vestingWallet = new VestingWallet(foundersWallet, 
                                          address(tokenContract), 
                                          tokensForFounders);
        tokenContract.mint(vestingWallet, tokensForFounders);
        tokenContract.mint(partnersWallet, tokensForPartners);
        FoundersAndPartnersTokensIssued(vestingWallet, tokensForFounders, partnersWallet, tokensForPartners);
    }

    // PRIVILEGED FUNCTIONS
    // ====================
    
     /**
     * @dev Mints the bonus tokens for a particular address, erasing the record.
     * @param _beneficiary The address for which the bonuses are issued.
     */
    
    function offchainBuyTokens(address _beneficiary
                              , uint _contribution
                              , string _txHash) 
                          external onlyManager returns (bool success,              //Warning: Unused local variable (success)
                                                        uint overcap, 
                                                        uint totalWeiBeforeContribution) {
        uint truncatedContribution;
                                                                                   //{ former issueBonus function
        uint totalBonus = 0;                                
        for (uint i = 0; i<milestonesReached; i++) {
            totalBonus += calculateBonusForTier( contributedAtMilestone[_beneficiary][i], i ); //references to contributedAtMilestone
            contributedAtMilestone[_beneficiary][i] = 0;
        }        
        if (totalBonus > 0) tokenContract.mint(_beneficiary, totalBonus);
        BonusIssued(_beneficiary, totalBonus);
                                                                                   //  former issueBonus function }
        (truncatedContribution, overcap) = calculateOvercap(_contribution);
        totalWeiBeforeContribution = totalWeiGathered;
        if (issueTokens(_beneficiary, truncatedContribution)) {
            uint tokensIssued = truncatedContribution * tokenRate;
            OffchainTokenPurchase(_beneficiary, _contribution, _txHash, 
                                  tokensIssued, overcap, totalWeiBeforeContribution);
            return (true, overcap, totalWeiBeforeContribution);
        }
    }

    // INTERNAL FUNCTIONS
    // ==================
    /**
     * @dev We track purchases by funding milestones at the time of the contribution.
     */
    function recordTransaction(address _beneficiary, uint _contribution) internal {           //Warning: Unused local variable (_beneficiary)
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
            contributedAtMilestone[_beneficiary][milestonesReached] += contributionPart;      //last reference to contributedAtMilestone
            if (contributionPart == weiToNextTier) milestonesReached += 1;
        } while (remainingContribution > 0);
    }

    function issueTokens(address _beneficiary, uint _contribution) internal returns (bool success) { //Warning: Unused local variable (success)
        //same warnings apply to "bool success" arguments for "tranfer", "tranferFrom" and "approve" functions from ARToken.sol
        
        require( totalWeiGathered + _contribution <= hardCap );                                      
        require( totalWeiGathered + _contribution > totalWeiGathered );

        uint tokensToMint = _contribution * tokenRate;

        tokenContract.mint(msg.sender, tokensToMint);
        totalWeiGathered += _contribution;
        recordTransaction(_beneficiary, _contribution);
        return true;
    }

    function calculateOvercap(uint _contribution) constant internal returns (uint overcap, 
                                                                             uint truncatedContribution) {
        require( _contribution + totalWeiGathered > totalWeiGathered ); // Overflow protection just in case.
        if (_contribution + totalWeiGathered > hardCap) {
            overcap = _contribution + totalWeiGathered - hardCap;
            truncatedContribution = _contribution - overcap;
            return (overcap, truncatedContribution);
        } else return (0, 0);
    }

    function calculateBonusForTier(uint _contribution, uint _tier) constant internal returns (uint bonus) {
        // For each failed funding milestone, the descending bonus staircase loses a step from the left.
        // Thus to calculate the bonus, offset the sequence by 10 - (total milestones reached)
        return ( _contribution * fibonacci[10 - milestonesReached + _tier] / 100 );
    }

    function min(uint _a, uint _b) constant internal returns (uint result) {
        if (_a < _b) return _a;
        else return _b;
    }
    
    modifier onlyManager() {
        require( msg.sender == icoManager );
        _;
    }
}
