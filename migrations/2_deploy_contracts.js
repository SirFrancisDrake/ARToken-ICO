var ARToken = artifacts.require("./ARToken.sol");

module.exports = function(deployer) {
 deployer.deploy(ARToken, "0x7fb504439b8a99cf1e31dfd0490fd19a7bb502d0");
}; 

