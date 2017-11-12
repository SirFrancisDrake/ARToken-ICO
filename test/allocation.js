
const web3 = global.web3;

const ERC20 = artifacts.require("./ERC20.sol");
const TokenAllocation = artifacts.require("./TokenAllocation.sol");

var allocation;
var bonusTierSize = 10 * 1e6 * 1e2;
var firstSum = 5 * 1e6 * 1e2;
var secondSum = 13 * 1e6 * 1e2;

contract("allocation", function(accounts) {
    const [icoManager, icoBackend, foundersWallet, partnersWallet] = accounts;

    //var token = TokenAllocation.deployed();
    //var issues = token.TokensAllocated({fromBlock: "latest"});
    //var bonuses = token.BonusIssued({fromBlock: "latest"});

    // TEST 1
    it("allocator can be created", () =>
        TokenAllocation.new(icoManager, icoBackend, foundersWallet, partnersWallet).then(res => {
            assert.isOk(res && res.address, "should have valid address");
            allocation = res;
        })
      );

    // TEST 2
    it("bonus phase is Phase One", async function() {
        let bonusPhase = (await allocation.bonusPhase()).toString();
        assert.equal(bonusPhase, 0);
    });

    // TEST 3
    let testSum = (allocation, sum, expectedAllocations, expectedBonuses) => {
    }

    it("should issue tokens for $4m with 20% bonus", async () => {
        let acc = accounts[5];
        let expectedAllocations =
            [[acc, firstSum, firstSum * 125 ]]
        let expectedBonuses = 
            [[acc, firstSum * 125 * 10 / 100 ], // tier bonus
             [acc, firstSum * 125 * 10 / 100 ]] // size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener = allocation.BonusIssued();

        await allocation.issueTokens(acc, firstSum, {from: icoBackend});
        
        let tokenAllocationLog = await new Promise(
                (resolve, reject) => tokenAllocationListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        assert.equal(tokenAllocationLog.length, 
                     expectedAllocations.length, 
                     "wrong number of allocations");

        let totalTokens = 0;
        
        for (let i=0; i<expectedAllocations.length; i++) {
        let allocationArgs = tokenAllocationLog[i].args;

        assert.equal(allocationArgs._beneficiary, 
                     expectedAllocations[i][0],
                     "incorrect address: " + allocationArgs._beneficiary);

        assert.equal(allocationArgs._contribution, 
                     expectedAllocations[i][1],
                     "sum mismatch: " + allocationArgs._contribution);

        assert.equal(allocationArgs._tokensIssued, 
                     expectedAllocations[i][2],
                     "allocation mismatch: " + allocationArgs._tokensIssued);

        totalTokens += Number(allocationArgs._tokensIssued);
        }

        let bonusIssuedLog = await new Promise(
                (resolve, reject) => bonusIssuedListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        assert.equal(bonusIssuedLog.length, 
                     expectedBonuses.length, 
                     'wrong number of bonuses');

        for (let i=0; i<expectedBonuses.length; i++) {
        let bonusIssuedArgs = bonusIssuedLog[0].args;

        assert.equal(bonusIssuedArgs._beneficiary,
                     expectedBonuses[i][0],
                     "incorrect address: " + bonusIssuedArgs._beneficiary);

        assert.equal(bonusIssuedArgs._bonusTokensIssued, 
                     expectedBonuses[i][1], 
                     "bonus mismatch: " + bonusIssuedArgs._bonusTokensIssued); 

        totalTokens += Number(bonusIssuedArgs._bonusTokensIssued);
        }

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(acc);

        assert.equal(balance,
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 4
    it("bonus phase is still Phase One", async function() {
        let bonusPhase = (await allocation.bonusPhase()).toString();
        assert.equal(bonusPhase, 0);
    });

    // TEST 5
    it("should issue tokens for $11m more with 20% and 15% bonus", async () => {
        let acc = accounts[6];
        let expectedAllocations =
            [[acc,
              bonusTierSize - firstSum,
              (bonusTierSize - firstSum) * 125 ],
             [acc,
              secondSum + firstSum - bonusTierSize,
              (secondSum + firstSum - bonusTierSize) * 125 ]]
        let expectedBonuses = 
            [[acc,
              (bonusTierSize - firstSum) * 125 * 10 / 100 ], // Tier 1 bonus
             [acc,
              (secondSum + firstSum - bonusTierSize) * 125 * 5 / 100], // Tier 2 bonus
             [acc,
              secondSum * 125 * 10 / 100]] // Size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener = allocation.BonusIssued();

        await allocation.issueTokens(acc, secondSum, {from: icoBackend});
        
        let tokenAllocationLog = await new Promise(
                (resolve, reject) => tokenAllocationListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        assert.equal(tokenAllocationLog.length, 
                     expectedAllocations.length, 
                     "wrong number of allocations");

        let totalTokens = 0;
        
        for (let i=0; i<expectedAllocations.length; i++) {
        let allocationArgs = tokenAllocationLog[i].args;

        assert.equal(allocationArgs._beneficiary, 
                     expectedAllocations[i][0],
                     "incorrect address: " + allocationArgs._beneficiary);

        assert.equal(allocationArgs._contribution, 
                     expectedAllocations[i][1],
                     "sum mismatch: " + allocationArgs._contribution);

        assert.equal(allocationArgs._tokensIssued, 
                     expectedAllocations[i][2],
                     "allocation mismatch: " + allocationArgs._tokensIssued);

        totalTokens += Number(allocationArgs._tokensIssued);
        }

        let bonusIssuedLog = await new Promise(
                (resolve, reject) => bonusIssuedListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        assert.equal(bonusIssuedLog.length, 
                     expectedBonuses.length, 
                     'wrong number of bonuses');

        for (let i=0; i<expectedBonuses.length; i++) {
        let bonusIssuedArgs = bonusIssuedLog[i].args;

        assert.equal(bonusIssuedArgs._beneficiary,
                     expectedBonuses[i][0],
                     "incorrect address: " + bonusIssuedArgs._beneficiary);

        assert.equal(bonusIssuedArgs._bonusTokensIssued, 
                     expectedBonuses[i][1], 
                     "bonus mismatch: " + bonusIssuedArgs._bonusTokensIssued); 

        totalTokens += Number(bonusIssuedArgs._bonusTokensIssued);
        }

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(acc);

        assert.equal(Number(balance),
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 6
    it("bonus phase is Phase Two", async function() {
        let bonusPhase = (await allocation.bonusPhase()).toString();
        assert.equal(bonusPhase, 1);
    });
})
