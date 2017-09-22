
pragma solidity ^0.4.15;

contract GenericCrowdsale {
    address public icoBackend;
    address public icoManager;
    bool paused = false;

    /**
     * @dev Confirms that token issuance for an off-chain purchase was processed successfully.
     * @param _beneficiary Token holder.
     * @param _contribution Money received (in USD cents).
     * @param _txHash Transaction hash from the medium where the money was received.
     * @param _tokensIssued The amount of tokens that was assigned to the holder, not counting bonuses.
     */
    event OffchainTokenPurchase(address _beneficiary, uint _contribution, string _txHash, 
                                uint _tokensIssued);
    /**
     * @dev Notifies about bonus token issuance. Is raised even if the bonus is 0.
     * @param _beneficiary Token holder.
     * @param _bonusTokensIssued The amount of bonus tokens that was assigned to the holder.
     */
    event BonusIssued(address _beneficiary, uint _bonusTokensIssued);
    /**
     * @dev Issues tokens for founders and partners and closes the current phase.
     * @param foundersWallet Wallet address holding the vested tokens.
     * @param tokensForFounders The amount of tokens vested for founders.
     * @param partnersWallet Wallet address holding the tokens for early contributors.
     * @param tokensForPartners The amount of tokens issued for rewarding early contributors.
     */
    event FoundersAndPartnersTokensIssued(address foundersWallet, uint tokensForFounders, 
                                          address partnersWallet, uint tokensForPartners);
    event Paused();
    event Unpaused();

    /**
     * @dev Issues tokens for the off-chain contributors by accepting calls from the trusted address. 
     *        Supposed to be run by the backend.
     * @param _beneficiary Token holder.
     * @param _contribution The Ether equivalent (in wei) of the contribution received off-chain.
     * @param _txHash Transaction hash from the chain where the contribution was received.
     */
    function offchainBuyTokens(address _beneficiary, 
                               uint _contribution, 
                               string _txHash) 
                           onlyBackend external returns (bool success);

    /**
     * @dev Pauses the crowdsale.
     */
    function pause() onlyManager external {
        paused = true;
        Paused();
    }

    /**
     * @dev Unpauses the crowdsale.
     */
    function unpause() onlyManager external {
        paused = false;
        Unpaused();
    }

    /**
     * @dev Issues the rewards for founders and early contributors. 18% and 12% of the total token supply by the end 
     *        of the crowdsale, respectively, including all the token bonuses on early contributions. Can only be
     *        called after the end of the crowdsale phase, ends the current phase.
     */
    function rewardFoundersAndPartners() external;

    modifier onlyManager() {
        require( msg.sender == icoManager );
        _;
    }

    modifier onlyBackend() {
        require( msg.sender == icoBackend );
        _;
    }
}
