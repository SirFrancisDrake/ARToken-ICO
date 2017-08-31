pragma solidity ^0.4.15;

import './ARToken.sol';
import './VestingWallet.sol';

   /**
    * @dev Prepaid token allocation for a capped crowdsale with Fibonacci bonus structure
    *      Written with OpenZeppelin sources as a rough reference.     
    *      Modern Token Team for the ICO of Cappasity's ARToken.
    */

contract TokenAllocation {
    // Token information
    uint constant tokenRate = 34996; // 1 ETH = 34996 ARTokens; so 1 wei = 34996 / 1e18 ARTokens
    ARToken public tokenContract;
    address foundersWallet; // A wallet permitted to request tokens from the time vault.
    address partnersWallet; // A wallet that distributes the tokens to early contributors.
    address public icoManager;
    
    // Events
    event TokensAllocated(address _beneficiary, uint _contribution, string _currency, string _txHash);
    event BonusIssued(address _beneficiary, uint _bonusTokensIssued);
    event FoundersAndPartnersTokensIssued(address _foundersWallet, uint _tokensForFounders, 
                                          address _partnersWallet, uint _tokensForPartners);
    
    // Crowdsale progress
    uint constant hardCap = 175000 ether;
    uint totalWeiGathered = 0;
    // Track how many wei we have processed into tokens. Need this to assign bonuses.
    uint totalWeiProcessed = 0;
    bool foundersAndPartnersTokensIssued = false;
    VestingWallet vestingWallet;

    // Tracking the bonuses
    uint milestonesReached = 0; // each milestone corresponds to 17500 ETH
    uint constant milestoneSize = 17500 ether;
    // Bonus staircase, a reversed Fibonacci sequence starting with 55
    uint8[10] fibonacci = [55, 34, 21, 13, 8, 5, 3, 2, 1, 1]; 

    /**
     * @dev Constructs the allocator.
     * @param _icoManager Wallet address that should be owned by the off-chain backend, from which \
     *          \ it mints the tokens for contributions accepted in other currencies.
     * @param _foundersWallet Where the founders' tokens to to after vesting.
     * @param _partnersWallet A wallet that distributes tokens to early contributors.
     * @param _totalWeiGathered How much money was collected during the crowdsale.
     */
    function TokenAllocation(address _icoManager, 
                             address _foundersWallet,
                             address _partnersWallet, 
                             uint _totalWeiGathered
                             ) { 
        require(_icoManager != 0x0);
        require(_foundersWallet != 0x0);
        require(_partnersWallet != 0x0);
        require(_totalWeiGathered != 0);
        
        tokenContract = new ARToken(address(this));

        icoManager       = _icoManager;
        foundersWallet   = _foundersWallet;
        partnersWallet   = _partnersWallet;
        totalWeiGathered = _totalWeiGathered;

        milestonesReached = totalWeiGathered / milestoneSize;
    }

    // PRIVILEGED FUNCTIONS
    // ====================
    /**
     * @dev Issues tokens for a particular address as for a contribution of size _contribution, \
     *          \ then issues bonuses in proportion. Currency and txHash passed for tracking.
     * @param _beneficiary Receiver of the tokens.
     * @param _contribution Size of the contribution (in wei).
     * @param _currency Ticker of the currency that this contribution was made in.
     * @param _txHash Hash of the received transaction in whatever currency was accepted.
     */ 
    function issueTokens(address _beneficiary, uint _contribution, 
                         string _currency, string _txHash) external onlyManager {
        // Cannot issue new tokens after founders and partners have been rewarded
        require( !foundersAndPartnersTokensIssued );
        // Make sure that the total sum of the received funding is recorded, so we can calculate the bonus
        require( totalWeiGathered != 0);
        require( _contribution != 0);
        uint tokensToMint = _contribution * tokenRate;
        tokenContract.mint(_beneficiary, tokensToMint);
        TokensAllocated(_beneficiary, _contribution, _currency, _txHash);

        // Calculating the total bonus to be issued.
        // 1. Count the bonus for the part of the contribution inside the current bonus tier
        // 2. If the contribution goes over the current milestone, iterate through 1 again
        uint remainingContribution = _contribution;
        uint lastPassedMilestone = totalWeiProcessed / milestoneSize;
        uint totalBonus = 0;                                
        do {
            uint weiToFillCurrentMilestone = (lastPassedMilestone + 1) * milestoneSize - totalWeiGathered;
            uint contributionChunk = min( weiToFillCurrentMilestone, remainingContribution );
            totalWeiProcessed += contributionChunk;
            remainingContribution -= contributionChunk;
            totalBonus += calculateBonusForTier( contributionChunk, lastPassedMilestone );
            if (contributionChunk == weiToFillCurrentMilestone) lastPassedMilestone += 1;
        } while (remainingContribution > 0);

        if (totalBonus > 0) {
            tokenContract.mint(_beneficiary, totalBonus);
            BonusIssued(_beneficiary, totalBonus);
        }
    }

    /**
     * @dev Issues tokens for founders and partners.
     */
    function rewardFoundersAndPartners() external onlyManager {
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

    // INTERNAL FUNCTIONS
    // ====================
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
