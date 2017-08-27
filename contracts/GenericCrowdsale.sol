
pragma solidity ^0.4.15;

contract GenericCrowdsale {
    address public icoManager;
    uint startTime;
    uint endTime;

    // Wallet information
    address crowdsaleWallet; // Where the money goes to

    /**
     * @dev Confirms a token purchase completed successfully.
     * @param _beneficiary Token holder.
     * @param _contribution Ether that was sent to the contract (in wei).
     * @param _tokensIssued The amount of tokens that was assigned to the holder.
     * @param _overcap The amount of Ether (in wei) that went over the cap and was returned.
     */
    event TokenPurchase(address _beneficiary, uint _contribution, uint _tokensIssued, uint _overcap);
    /**
     * @dev Confirms token issuance for a token purchase that happened off-chain was processed successfully.
     * @param _beneficiary Token holder.
     * @param _contribution Ether that was sent to the contract (in wei).
     * @param _txHash Transaction hash from the chain where the money was received.
     * @param _tokensIssued The amount of tokens that was assigned to the holder.
     * @param _overcap The amount of Ether (in wei) that went over the cap and SHOUD BE returned off-chain.
     */
    event OffchainTokenPurchase(address _beneficiary, uint _contribution, string _txHash, uint _tokensIssued, uint _overcap);
    event BonusIssued(address _beneficiary, uint _bonusTokensIssued);
    event FoundersAndPartnersTokensIssued(address foundersWallet, uint tokensForFounders, address partnersWallet, uint tokensForPartners);

    // For contributors on Ethereum
    function buyTokens() public payable returns (bool success);

    /**
     * @dev Issues tokens for the off-chain contributors by accepting calls from the trusted address. Supposed to be run by the backend.
     * @param _beneficiary Token holder.
     * @param _contribution The Ether equivalent (in wei) of the contribution received off-chain.
     * @param _txHash Transaction hash from the chain where the contribution was received.
     * @param _tokensIssued The amount of tokens that was assigned to the holder.
     * @param _overcap The amount of Ether (in wei) that went over the cap and SHOUD BE refunded off-chain by the backend.
     */
    function offchainBuyTokens(address _beneficiary, uint _contribution) onlyManager external returns (bool success);
    function issueBonus(address _beneficiary) external;
    function rewardFoundersAndPartners() external;

    modifier onlyManager() {
        require( msg.sender == icoManager );
        _;
    }
}
