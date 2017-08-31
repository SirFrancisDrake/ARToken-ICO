var TokenAllocation = artifacts.require("./TokenAllocation.sol");

var icoManager = "0x0";     // Public key for the backend script that mints tokens
var foundersWallet = "0x0"; // Public key of Kosta's wallet that will receive tokens after vesting
var partnersWallet = "0x0"; // Public key of the wallet that allocates early contributors' bonus
var totalWeiGathered = 0;   // Total sum of all the money gathered throughout the crowdsale

module.exports = function(deployer) {
 deployer.deploy(TokenAllocation, icoManager, foundersWallet, partnersWallet, totalWeiGathered);
}; 

