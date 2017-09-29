
pragma solidity ^0.4.11;

import "./StandardToken.sol";

contract ARToken is StandardToken {

  // Constants
  // =========
  string public constant name = "ARToken";
  string public constant symbol = "AR";
  uint public constant decimals = 2;
  uint public constant TOKEN_LIMIT = 10 * 1e9 * 1e2; // 10 billion tokens, 2 decimals

  // State variables
  // ===============
  address public manager;

  // Block token transfers until ICO is finished.
  bool public tokensAreFrozen = true;
  bool public mintingIsAllowed = true;

  // Constructor
  // ===========
  function ARToken(address _manager) {
    manager = _manager;
  }

  // ERC20 functions
  // =========================
  function transfer(address _to, uint _value) returns (bool success) {
    require(!tokensAreFrozen);
    super.transfer(_to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) returns (bool success) {
    require(!tokensAreFrozen);
    super.transferFrom(_from, _to, _value);
  }

  function approve(address _spender, uint _value) returns (bool success) {
    require(!tokensAreFrozen);
    super.approve(_spender, _value);
  }

  // PRIVILEGED FUNCTIONS
  // ====================
  modifier onlyByManager() {
    require(msg.sender == manager);
    _;
  }

  // Mint some tokens and assign them to an address
  function mint(address _beneficiary, uint _value) onlyByManager external {
    require(_value != 0);
    require(totalSupply + _value <= TOKEN_LIMIT);
    // Making double sure uint doesn't overflow and wrap back
    require(totalSupply + _value > totalSupply); 
    require(mintingIsAllowed);

    balances[_beneficiary] += _value;
    totalSupply += _value;
  }

  // Disable minting. Can be enabled later, but only once (see TokenAllocation.sol)
  function endMinting() onlyByManager external {
    mintingIsAllowed = false;
  }
  
  // Enable minting. See TokenAllocation.sol
  function startMinting() onlyByManager external {
    mintingIsAllowed = true;
  }

  // Allow token transfer
  function unfreeze() onlyByManager external {
    tokensAreFrozen = false;
  }
}
