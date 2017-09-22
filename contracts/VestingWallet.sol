
pragma solidity ^0.4.15;

import "./ERC20.sol";

  /**
   * @dev For the tokens issued for founders.
   */

contract VestingWallet {
    event TokensReleased(uint _tokensReleased, uint _tokensRemaining, uint _nextPeriod);

    address foundersWallet;
    ERC20 tokenContract;
    // Two-year vesting with 1 month cliff. Roughly.
    uint constant cliffPeriod = 30 days;
    uint constant totalPeriods = 24;

    uint periodsPassed = 0;
    uint nextPeriod;
    uint tokensRemaining;
    uint tokensPerBatch;

    function VestingWallet(address _foundersWallet, address _tokenContract, uint _totalTokens) {
        foundersWallet  = _foundersWallet;
        tokenContract   = ERC20(_tokenContract);
        tokensRemaining = _totalTokens;
        nextPeriod      = now + cliffPeriod;
        tokensPerBatch  = _totalTokens / totalPeriods;
    }

    // PRIVILEGED FUNCTIONS
    // ====================
    function releaseBatch() external foundersOnly returns (uint _tokensReleased, 
                                                           uint _tokensRemaining, 
                                                           uint _nextPeriod) {
        require( now > nextPeriod );
        require( periodsPassed < totalPeriods );
        uint tokensToRelease = 0;
        do {
            periodsPassed   += 1;
            nextPeriod      += cliffPeriod;
            tokensToRelease += tokensPerBatch;
        } while (now > nextPeriod);
        // If vesting has finished, just transfer the remaining tokens.
        if (periodsPassed >= totalPeriods) {
            tokensToRelease = tokenContract.balanceOf(this);
            nextPeriod = 0x0;
        }
        tokensRemaining -= tokensToRelease;
        tokenContract.transfer(foundersWallet, tokensToRelease);
        TokensReleased(tokensToRelease, tokensRemaining, nextPeriod);
        return (tokensToRelease, tokensRemaining, nextPeriod);
    }

    // INTERNAL FUNCTIONS
    // ==================
    modifier foundersOnly() {
        require( msg.sender == foundersWallet );
        _;
    }
}
