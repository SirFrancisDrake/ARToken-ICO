pragma solidity ^0.4.15;

import './ARToken.sol';
import './GenericCrowdsale.sol';
import './VestingWallet.sol';

   /**
    * @dev Prepaid token allocation for a capped crowdsale with bonus structure sliding on sales
    *      Written with OpenZeppelin sources as a rough reference.     
    */

contract TokenAllocation is GenericCrowdsale {
    // Events
    event TokensAllocated(address _beneficiary, uint _contribution, uint _tokensIssued);
    event BonusIssued(address _beneficiary, uint _bonusTokensIssued);
    event FoundersAndPartnersTokensIssued(address _foundersWallet, uint _tokensForFounders, 
                                          address _partnersWallet, uint _tokensForPartners);

    // Token information
    uint public tokenRate = 125; // 1 USD = 125 ARTokens; so 1 cent = 1.25 ARTokens \
                                   // assuming ARToken has 2 decimals (as set in token contract)
    ARToken public tokenContract;
    address public foundersWallet; // A wallet permitted to request tokens from the time vaults.
    address public partnersWallet; // A wallet that distributes the tokens to early contributors.
    address public icoManager;
    address public icoBackend;
    
    // Crowdsale progress
    uint constant public hardCap     = 5 * 1e7 * 1e2; // 50 000 000 dollars * 100 cents per dollar
    uint constant public phaseOneCap = 3 * 1e7 * 1e2; // 30 000 000 dollars * 100 cents per dollar
    uint public totalCentsGathered = 0;
    // Total sum gathered in phase one, need this to adjust the bonus tiers in phase two.
    // Updated only once, when the phase one is concluded.
    uint public centsInPhaseOne = 0;
    uint public totalTokenSupply = 0;     // Counting the bonuses, not counting the founders' share.
    // Total tokens issued in phase one, including bonuses. Need this to correctly calculate the founders' \
    // share and issue it in parts, once after each round. Updated when issuing tokens.
    uint public tokensDuringPhaseOne = 0;
    VestingWallet public vestingWallet;

    enum CrowdsalePhase { PhaseOne, Paused, PhaseTwo, Finished }
    enum BonusPhase { TenPercent, FivePercent, None }

    uint public constant bonusTierSize = 1 * 1e7 * 1e2; // 10 000 000 dollars * 100 cents per dollar
    uint public constant bigContributionBound  = 1 * 1e5 * 1e2; // 100 000 dollars * 100 cents per dollar 
    uint public constant hugeContributionBound = 3 * 1e5 * 1e2; // 300 000 dollars * 100 cents per dollar 
    CrowdsalePhase public crowdsalePhase = CrowdsalePhase.PhaseOne;
    BonusPhase public bonusPhase = BonusPhase.TenPercent;

    /**
     * @dev Constructs the allocator.
     * @param _icoBackend Wallet address that should be owned by the off-chain backend, from which \
     *          \ it mints the tokens for contributions accepted in other currencies.
     * @param _icoManager Allowed to start phase 2.
     * @param _foundersWallet Where the founders' tokens to to after vesting.
     * @param _partnersWallet A wallet that distributes tokens to early contributors.
     */
    function TokenAllocation(address _icoManager, 
                             address _icoBackend,
                             address _foundersWallet,
                             address _partnersWallet 
                             ) { 
        require(_icoManager != 0x0);
        require(_icoBackend != 0x0);
        require(_foundersWallet != 0x0);
        require(_partnersWallet != 0x0);
        
        tokenContract = new ARToken(address(this));

        icoManager       = _icoManager;
        icoBackend       = _icoBackend;
        foundersWallet   = _foundersWallet;
        partnersWallet   = _partnersWallet;
    }

    // PRIVILEGED FUNCTIONS
    // ====================
    /**
     * @dev Issues tokens for a particular address as for a contribution of size _contribution, \
     *          \ then issues bonuses in proportion. 
     * @param _beneficiary Receiver of the tokens.
     * @param _contribution Size of the contribution (in USD cents).
     */ 
    function issueTokens(address _beneficiary, uint _contribution) external onlyBackend onlyValidPhase onlyUnpaused {
        require( totalCentsGathered + _contribution <= hardCap );
        if (crowdsalePhase == CrowdsalePhase.PhaseOne)
            require( totalCentsGathered + _contribution <= phaseOneCap );

        uint centsLeftInPhase;
        uint remainingContribution = _contribution;
        uint contributionPart;
        uint tokensToMint;
        uint bonus;

        totalCentsGathered += _contribution;

        // Check if the contribution fills the current bonus phase. If so, break it up in parts,
        // mint tokens for each part separately, assign bonuses, trigger events. For transparency.
        do {
            if (bonusPhase != BonusPhase.None) {
                centsLeftInPhase = ((totalCentsGathered - centsInPhaseOne) / bonusTierSize + 1) * bonusTierSize - 
                                                                            (totalCentsGathered - centsInPhaseOne);
                contributionPart = min(centsLeftInPhase, remainingContribution);
            } else contributionPart = remainingContribution;
            tokensToMint = tokenRate * contributionPart;
            tokenContract.mint(_beneficiary, tokensToMint);
            TokensAllocated(_beneficiary, contributionPart, tokensToMint);

            bonus = calculateBonus(contributionPart);
            if (bonus>0) tokenContract.mint(_beneficiary, bonus);
            BonusIssued(_beneficiary, bonus);
            if ((bonusPhase != BonusPhase.None) && (centsLeftInPhase == contributionPart))
                advanceBonusPhase();
            remainingContribution -= contributionPart;

            totalTokenSupply += tokensToMint + bonus;
            if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
                tokensDuringPhaseOne += tokensToMint + bonus;
            }
        } while (remainingContribution > 0);
    }

    /**
     * @dev Issues tokens for the off-chain contributors by accepting calls from the trusted address. 
     *        Supposed to be run by the backend.
     * @param _beneficiary Token holder.
     * @param _contribution The equivalent (in USD cents) of the contribution received off-chain.
     * @param _bonus Custom bonus size in percents, will be issued as one batch after the contribution. 
     */
    function issueTokensWithCustomBonus(address _beneficiary, uint _contribution, uint _bonus) 
                                            onlyBackend onlyUnpaused external {
        require( totalCentsGathered + _contribution <= hardCap );
        if (crowdsalePhase == CrowdsalePhase.PhaseOne)
            require( totalCentsGathered + _contribution <= phaseOneCap );

        uint centsLeftInPhase;
        uint remainingContribution = _contribution;
        uint contributionPart;
        uint bonus;

        totalCentsGathered += _contribution;

        // Advance bonus phases as needed with contribution filling the bonus tiers.
        do {
            if (bonusPhase != BonusPhase.None) {
                centsLeftInPhase = ((totalCentsGathered - centsInPhaseOne) / bonusTierSize + 1) * bonusTierSize - 
                                                                            (totalCentsGathered - centsInPhaseOne);
                contributionPart = min(centsLeftInPhase, remainingContribution);
            } else contributionPart = remainingContribution;

            if ((bonusPhase != BonusPhase.None) && (centsLeftInPhase == contributionPart))
                advanceBonusPhase();
            remainingContribution -= contributionPart;
        } while (remainingContribution > 0);

        uint tokensToMint = _contribution * tokenRate;
        tokenContract.mint(_beneficiary, tokensToMint);
        TokensAllocated(_beneficiary, _contribution, tokensToMint);

        bonus = _contribution * _bonus / 100;
        tokenContract.mint(_beneficiary, bonus);
        BonusIssued(_beneficiary, bonus);

        totalTokenSupply += tokensToMint + bonus;
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            tokensDuringPhaseOne += tokensToMint + bonus;
        }
    }

    /**
     * @dev Issue tokens for founders and partners, end the current phase.
     */
    function rewardFoundersAndPartners() external onlyBackend onlyValidPhase onlyUnpaused {
        uint tokensDuringThisPhase;
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) tokensDuringThisPhase = totalTokenSupply;
        else tokensDuringThisPhase = totalTokenSupply - tokensDuringPhaseOne;

        // Total tokens sold is 70% of the overall supply, founders' share is 18%, early contributors' is 12%
        // So to obtain those from tokens sold, multiply them by 0.18 / 0.7 and 0.12 / 0.7 respectively.
        uint tokensForFounders = tokensDuringThisPhase * 257 / 1000; // 0.257 of 0.7 is 0.18 of 1
        uint tokensForPartners = tokensDuringThisPhase * 171 / 1000; // 0.171 of 0.7 is 0.12 of 1

        tokenContract.mint(partnersWallet, tokensForPartners);

        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            vestingWallet = new VestingWallet(foundersWallet, address(tokenContract));
            tokenContract.mint(vestingWallet, tokensForFounders);
            FoundersAndPartnersTokensIssued(vestingWallet, tokensForFounders, partnersWallet, tokensForPartners);
        } else if (crowdsalePhase == CrowdsalePhase.PhaseTwo) {
            tokenContract.mint(vestingWallet, tokensForFounders);
            vestingWallet.launchVesting();
            FoundersAndPartnersTokensIssued(vestingWallet, tokensForFounders, partnersWallet, tokensForPartners);
        }
        
      // Store the total sum collected during phase one for calculations in phase two. Enable token transfer.   
      if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
         centsInPhaseOne = totalCentsGathered;
         tokenContract.unfreeze();
         crowdsalePhase = CrowdsalePhase.Paused;
      } else crowdsalePhase = CrowdsalePhase.Finished;
      tokenContract.endMinting();
   }

    /**
     * @dev Start the second phase of token allocation. Can only be called by the crowdsale manager.
     */
    function beginPhaseTwo() external onlyManager {
        require( crowdsalePhase == CrowdsalePhase.Paused );
        crowdsalePhase = CrowdsalePhase.PhaseTwo;
        bonusPhase = BonusPhase.TenPercent;
        tokenContract.startMinting();
    }

    /**
     * @dev Set the ART / 1 USD rate. Can only be called by the crowdsale manager in between the phases.
     * _tokenRate How many ART per 1 USD cent. As dollars, ART has two decimals.
     *            For instance: tokenRate = 125 means "1.25 ART per USD cent" <=> "125 ART per USD".
     */
    function setRateForPhaseTwo(uint _tokenRate) external onlyManager {
        require(crowdsalePhase == CrowdsalePhase.Paused);
        require(_tokenRate != 0);
        tokenRate = _tokenRate;
    }

    // INTERNAL FUNCTIONS
    // ====================
    function calculateBonus(uint _contribution) constant internal returns (uint bonusTokens) {
        // All bonuses are additive and not multiplicative
        // Calculate bonus on contribution size, then convert it to bonus tokens.
        uint bonus = 0;
        // Contribution size bonuses
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            // 5% for contributions above bigContributionBound
            if (_contribution >= bigContributionBound)  bonus += _contribution * 5 / 100;
            // additional 5% for contributions above hugeContributionBound, 10% total
            if (_contribution >= hugeContributionBound) bonus += _contribution * 5 / 100;
        }

        // Bonus tier bonuses. We make sure in issueTokens that the processed contribution \
        // falls entirely into one tier

        if (bonusPhase == BonusPhase.TenPercent) bonus += _contribution / 10;
        else if (bonusPhase == BonusPhase.FivePercent) bonus += _contribution * 5 / 100;

        bonusTokens = bonus * tokenRate;

        return bonusTokens;
    }

    /**
     * @dev Advance the bonus phase to next tier when appropriate, do nothing otherwise.
     */
    function advanceBonusPhase() internal onlyValidPhase {
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            if (bonusPhase == BonusPhase.TenPercent) bonusPhase = BonusPhase.FivePercent;
            else if (bonusPhase == BonusPhase.FivePercent) bonusPhase = BonusPhase.None;
        }
        else if (bonusPhase == BonusPhase.TenPercent)
            bonusPhase = BonusPhase.None;
    }

    function min(uint _a, uint _b) constant internal returns (uint result) {
        if (_a < _b) return _a;
        else return _b;
    }

    modifier onlyValidPhase() {
        require( crowdsalePhase == CrowdsalePhase.PhaseOne 
                 || crowdsalePhase == CrowdsalePhase.PhaseTwo );
        _;
    }
    
    modifier onlyManager() {
        require( msg.sender == icoManager );
        _;
    }

    modifier onlyBackend() {
        require( msg.sender == icoBackend );
        _;
    }
}
