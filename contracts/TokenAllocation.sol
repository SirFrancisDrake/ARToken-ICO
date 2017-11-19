pragma solidity ^0.4.18;

import './Cappasity.sol';
import './GenericCrowdsale.sol';
import './SafeMath.sol';
import './VestingWallet.sol';

   /**
    * @dev Prepaid token allocation for a capped crowdsale with bonus structure sliding on sales
    *      Written with OpenZeppelin sources as a rough reference.     
    */

contract TokenAllocation is GenericCrowdsale, SafeMath {
    // Events
    event TokensAllocated(address _beneficiary, uint _contribution, uint _tokensIssued);
    event BonusIssued(address _beneficiary, uint _bonusTokensIssued);
    event FoundersAndPartnersTokensIssued(address _foundersWallet, uint _tokensForFounders, 
                                          address _partnersWallet, uint _tokensForPartners);

    // Token information
    uint public tokenRate = 125; // 1 USD = 125 CAPP; so 1 cent = 1.25 CAPP \
                                   // assuming CAPP has 2 decimals (as set in token contract)
    Cappasity public tokenContract;

    address public foundersWallet; // A wallet permitted to request tokens from the time vaults.
    address public partnersWallet; // A wallet that distributes the tokens to early contributors.
    
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

    enum CrowdsalePhase { PhaseOne, BetweenPhases, PhaseTwo, Finished }
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
        
        tokenContract = new Cappasity(address(this));

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
    function issueTokens(address _beneficiary, uint _contribution) external onlyOffChain onlyValidPhase onlyUnpaused {
        require( totalCentsGathered + _contribution <= hardCap );
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            require( totalCentsGathered + _contribution <= phaseOneCap );
        }

        uint remainingContribution = _contribution;

        // Check if the contribution fills the current bonus phase. If so, break it up in parts,
        // mint tokens for each part separately, assign bonuses, trigger events. For transparency.
        do {
            // 1 - calculate contribution part for current bonus stage
            uint centsLeftInPhase = calculateCentsLeftInPhase( remainingContribution );
            uint contributionPart = min( remainingContribution, centsLeftInPhase );
            
            // 3 - mint tokens
            uint tokensToMint = safeMul( tokenRate, contributionPart );
            mintAndUpdate( _beneficiary, tokensToMint );
            TokensAllocated( _beneficiary, contributionPart, tokensToMint );

            // 4 - mint bonus
            uint tierBonus = calculateTierBonus( contributionPart );
            if (tierBonus > 0) {
                mintAndUpdate( _beneficiary, tierBonus );
            }
            BonusIssued( _beneficiary, tierBonus );

            // 5 - advance bonus phase
            if ((bonusPhase != BonusPhase.None) && (contributionPart == centsLeftInPhase)) {
                advanceBonusPhase();
            }

            // 6 - log the processed part of the contribution
            totalCentsGathered = safeAdd( totalCentsGathered, contributionPart );
            remainingContribution = safeSub( remainingContribution, contributionPart );

            // 7 - continue?
        } while (remainingContribution > 0);

        // Mint contribution size bonus
        uint sizeBonus = calculateSizeBonus(_contribution);
        if ( sizeBonus>0 ) { 
            mintAndUpdate(_beneficiary, sizeBonus);
        }
        BonusIssued(_beneficiary, sizeBonus);
    }

    /**
     * @dev Issues tokens for the off-chain contributors by accepting calls from the trusted address. 
     *        Supposed to be run by the backend.
     * @param _beneficiary Token holder.
     * @param _contribution The equivalent (in USD cents) of the contribution received off-chain.
     * @param _bonus Custom bonus size in percents, will be issued as one batch after the contribution. 
     */
    function issueTokensWithCustomBonus(address _beneficiary, uint _contribution, uint _bonus) 
                                            onlyOffChain  onlyValidPhase onlyUnpaused external {
        require( totalCentsGathered + _contribution <= hardCap );
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            require( totalCentsGathered + _contribution <= phaseOneCap );
        }

        uint remainingContribution = _contribution;

        // Check if the contribution fills the current bonus phase. If so, break it up in parts,
        // mint tokens for each part separately, assign bonuses, trigger events. For transparency.
        do {
            // 1 - calculate contribution part for current bonus stage
            uint centsLeftInPhase = calculateCentsLeftInPhase( remainingContribution );
            uint contributionPart = min( remainingContribution, centsLeftInPhase );

            // 2 - mint tokens
            uint tokensToMint = safeMul( tokenRate, contributionPart );
            mintAndUpdate( _beneficiary, tokensToMint );
            TokensAllocated( _beneficiary, contributionPart, tokensToMint );

            // 3 - log the processed part of the contribution
            totalCentsGathered = safeAdd( totalCentsGathered, contributionPart );
            remainingContribution = safeSub( remainingContribution, contributionPart );

            // 4 - advance bonus phase
            if ((remainingContribution == centsLeftInPhase) && (bonusPhase != BonusPhase.None)) {
                advanceBonusPhase();
            }

            // 5 - log the processed part of the contribution
            totalCentsGathered = safeAdd( totalCentsGathered, contributionPart );
            remainingContribution = safeSub( remainingContribution, contributionPart );

            // 6 - continue?
        } while (remainingContribution > 0);

        // Mint custom bonus
        mintAndUpdate( _beneficiary, _bonus );
        BonusIssued (_beneficiary, _bonus );
    }

    /**
     * @dev Issue tokens for founders and partners, end the current phase.
     */
    function rewardFoundersAndPartners() external onlyOffChain onlyValidPhase onlyUnpaused {
        uint tokensDuringThisPhase;
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            tokensDuringThisPhase = totalTokenSupply;
        } else {
            tokensDuringThisPhase = totalTokenSupply - tokensDuringPhaseOne;
        }

        // Total tokens sold is 70% of the overall supply, founders' share is 18%, early contributors' is 12%
        // So to obtain those from tokens sold, multiply them by 0.18 / 0.7 and 0.12 / 0.7 respectively.
        uint tokensForFounders = safeDiv(safeMul(tokensDuringThisPhase, 257), 1000); // 0.257 of 0.7 is 0.18 of 1
        uint tokensForPartners = safeDiv(safeMul(tokensDuringThisPhase, 171), 1000); // 0.171 of 0.7 is 0.12 of 1

        tokenContract.mint(partnersWallet, tokensForPartners);

        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            vestingWallet = new VestingWallet(foundersWallet, address(tokenContract));
            tokenContract.mint(address(vestingWallet), tokensForFounders);
            FoundersAndPartnersTokensIssued(address(vestingWallet), tokensForFounders, 
                                            partnersWallet,         tokensForPartners);

            // Store the total sum collected during phase one for calculations in phase two. 
            centsInPhaseOne = totalCentsGathered;
            tokensDuringPhaseOne = totalTokenSupply;
            // Enable token transfer.   
            tokenContract.unfreeze();
            crowdsalePhase = CrowdsalePhase.BetweenPhases;
        } else {
            tokenContract.mint(address(vestingWallet), tokensForFounders);
            vestingWallet.launchVesting();
            FoundersAndPartnersTokensIssued(address(vestingWallet), tokensForFounders, 
                                            partnersWallet,         tokensForPartners);
          crowdsalePhase = CrowdsalePhase.Finished;
        }
        
      tokenContract.endMinting();
   }

    /**
     * @dev Set the CAPP / USD rate for Phase two, and then start the second phase of token allocation. 
     *        Can only be called by the crowdsale manager.
     * _tokenRate How many CAPP per 1 USD cent. As dollars, CAPP has two decimals.
     *            For instance: tokenRate = 125 means "1.25 CAPP per USD cent" <=> "125 CAPP per USD".
     */
    function beginPhaseTwo(uint _tokenRate) external onlyManager {
        require( crowdsalePhase == CrowdsalePhase.BetweenPhases );
        require(_tokenRate != 0);

        tokenRate = _tokenRate;
        crowdsalePhase = CrowdsalePhase.PhaseTwo;
        bonusPhase = BonusPhase.TenPercent;
        tokenContract.startMinting();
    }

    // INTERNAL FUNCTIONS
    // ====================
    function calculateCentsLeftInPhase (uint _remainingContribution)
                    internal 
                    returns(uint) {
        // Ten percent bonuses happen in both Phase One and Phase two, therefore:
        // Take the bonus tier size, subtract the total money gathered in the current phase
        if (bonusPhase == BonusPhase.TenPercent) {
            return safeSub( bonusTierSize, 
                            safeSub( totalCentsGathered, 
                                     centsInPhaseOne ) );
        } else if (bonusPhase == BonusPhase.FivePercent) {
            // Five percent bonuses only happen in Phase One, so no need to account
            // for the first phase separately.
            return safeSub( safeMul(bonusTierSize, 2), totalCentsGathered );
        } else return _remainingContribution;
    }

    function mintAndUpdate(address _beneficiary, uint _tokensToMint) internal {
        tokenContract.mint( _beneficiary, _tokensToMint );
        totalTokenSupply = safeAdd( totalTokenSupply, _tokensToMint );
    }

    function calculateTierBonus(uint _contribution) constant internal returns (uint ) {
        // All bonuses are additive and not multiplicative
        // Calculate bonus on contribution size, then convert it to bonus tokens.
        uint tierBonus = 0;

        // tierBonus tier tierBonuses. We make sure in issueTokens that the processed contribution \
        // falls entirely into one tier
        if (bonusPhase == BonusPhase.TenPercent) {
            tierBonus = safeDiv(_contribution, 10);
        } else if (bonusPhase == BonusPhase.FivePercent) {
            tierBonus = safeDiv( safeMul(_contribution, 5), 100 );
        }

        tierBonus = safeMul( tierBonus, tokenRate );
        return tierBonus;
    }

    function calculateSizeBonus(uint _contribution) constant internal returns (uint) {
        uint sizeBonus = 0;
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            // 5% for contributions above bigContributionBound
            if (_contribution >= bigContributionBound)  {
                sizeBonus = safeDiv( safeMul(_contribution, 5), 100 );
            }
            // additional 5% for contributions above hugeContributionBound, 10% total
            if (_contribution >= hugeContributionBound) { 
                sizeBonus = safeMul(sizeBonus, 2);
            }
            sizeBonus = safeMul(sizeBonus, tokenRate);
        }
        return sizeBonus;
    }


    /**
     * @dev Advance the bonus phase to next tier when appropriate, do nothing otherwise.
     */
    function advanceBonusPhase() internal onlyValidPhase {
        if (crowdsalePhase == CrowdsalePhase.PhaseOne) {
            if (bonusPhase == BonusPhase.TenPercent) { 
                bonusPhase = BonusPhase.FivePercent;
            } else if (bonusPhase == BonusPhase.FivePercent) {
                bonusPhase = BonusPhase.None;
            }
        } else if (bonusPhase == BonusPhase.TenPercent) {
            bonusPhase = BonusPhase.None;
        }
    }

    function min(uint _a, uint _b) internal pure returns (uint result) {
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

    modifier onlyOffChain() {
        require( msg.sender == icoBackend );
        _;
    }

    // Do not allow to send money directly to this contract
    function() payable {
         revert();
    }
}
