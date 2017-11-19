
const web3 = global.web3;

const ERC20 = artifacts.require("./ERC20.sol");
const TokenAllocation = artifacts.require("./TokenAllocation.sol");
const VestingWallet = artifacts.require("./VestingWallet.sol");

var allocation;
var bonusTierSize = 10 * 1e6 * 1e2;
var firstSum = 4 * 1e6 * 1e2;
var secondSum = 13 * 1e6 * 1e2;
var thirdSum = 5 * 1e6 * 1e2;

contract("allocation", function(accounts) {
    const [icoManager, icoBackend, foundersWallet, partnersWallet] = accounts;

    //var token = TokenAllocation.deployed();
    //var issues = token.TokensAllocated({fromBlock: "latest"});
    //var bonuses = token.BonusIssued({fromBlock: "latest"});

    // TEST 1
    it("allocator can be created", () =>
        TokenAllocation.new(icoManager, icoBackend, foundersWallet, partnersWallet, {gas: 6500000}).then(res => {
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
    it("should issue tokens for " + String(firstSum / 1e6 / 1e2) + "m with 20% bonus", async () => {
        let acc = accounts[5];
        let expectedAllocations =
            [[acc, firstSum, firstSum * 125 ]]
        let expectedBonuses = 
            [[acc, firstSum * 125 * 10 / 100 ], // tier bonus
             [acc, firstSum * 125 * 10 / 100 ]] // size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener     = allocation.BonusIssued();

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

        /*
         * Not currently tracking bonus events due tue Truffle bug.
         * But if allocations add up with total, that means bonuses are correct.
         */

        /*
        assert.equal(bonusIssuedLog.length, 
                     expectedBonuses.length, 
                     'wrong number of bonuses');
                     */

        for (let i=0; i<expectedBonuses.length; i++) {
            /*
            let bonusIssuedArgs = bonusIssuedLog[0].args;

            assert.equal(bonusIssuedArgs._beneficiary,
                        expectedBonuses[i][0],
                        "incorrect address: " + bonusIssuedArgs._beneficiary);

            assert.equal(bonusIssuedArgs._bonusTokensIssued, 
                        expectedBonuses[i][1], 
                        "bonus mismatch: " + bonusIssuedArgs._bonusTokensIssued); 
                        */

        totalTokens += expectedBonuses[i][1];
        }

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(acc);

        assert.equal(Number(balance),
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 4
    it("bonus phase is still Phase One", async function() {
        let bonusPhase = (await allocation.bonusPhase()).toString();
        assert.equal(bonusPhase, 0);
    });

    // TEST 5
    it("should issue tokens for $13m more with 10% size bonus, 10% on 6m and 5% on 7m", async () => {
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

        for (let i=0; i<expectedBonuses.length; i++) {
            totalTokens += expectedBonuses[i][1];
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

    // TEST 7
    it("total cents gathered is worth 17m", async function() {
        let totalCents = Number(await allocation.totalCentsGathered());
        assert.equal(totalCents, 17 * 1e8, "sum mismatch");
    });

    // TEST 8: from tier 2 to tier 3
    it("should issue tokens for 5m more with 10% size bonus, 5% for 3m and 0% for 2m", async () => {
        let acc = accounts[7];
        let expectedAllocations =
            [[acc,
              3 * 1e8,
              3 * 1e8 * 125 ], 
             [acc,
              2 * 1e8,
              2 * 1e8 * 125 ]]
        let expectedBonuses = 
            [[acc,
              3 * 1e8 * 125 * 5 / 100 ], // Tier 2 bonus
             [acc,
              0 ], // Tier 3 bonus
             [acc,
              thirdSum * 125 * 10 / 100]] // Size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener = allocation.BonusIssued();

        await allocation.issueTokens(acc, thirdSum, {from: icoBackend});
        
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

            assert.equal(Number(allocationArgs._contribution), 
                        expectedAllocations[i][1],
                        "sum mismatch");

            assert.equal(allocationArgs._tokensIssued, 
                        expectedAllocations[i][2],
                        "allocation mismatch: " + allocationArgs._tokensIssued);

            totalTokens += Number(allocationArgs._tokensIssued);
        }

        let bonusIssuedLog = await new Promise(
                (resolve, reject) => bonusIssuedListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        for (let i=0; i<expectedBonuses.length; i++) {
            totalTokens += expectedBonuses[i][1];
        }

        /*
        assert.equal(bonusIssuedLog.length, 
                     expectedBonuses.length, 
                     'wrong number of bonuses');

        for (let i=0; i<expectedBonuses.length; i++) {
            let bonusIssuedArgs = bonusIssuedLog[0].args;

            assert.equal(String(bonusIssuedArgs._beneficiary),
                        expectedBonuses[i][0],
                        "incorrect address");

            assert.equal(Number(bonusIssuedArgs._bonusTokensIssued), 
                        expectedBonuses[i][1], 
                        "bonus mismatch"); 

            totalTokens += expectedBonuses[i][1];
        }
        */

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(acc);

        assert.equal(Number(balance),
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 9
    it("bonus phase is Phase Three", async function() {
        let bonusPhase = (await allocation.bonusPhase()).toString();
        assert.equal(bonusPhase, 2);
    });

    // TEST 10
    it("total cents gathered is worth 22m", async function() {
        let totalCents = Number(await allocation.totalCentsGathered());
        assert.equal(totalCents, 22 * 1e8, "sum mismatch");
    });

    // TEST 11
    it("issue tokens for $350k, 10% size bonus", async function() {
        let address = accounts[8];
        let sum = 350 * 1e3 * 1e2;

        let expectedAllocations = [ [address, sum, sum * 125] ];

        let expectedBonuses =
            [ [address, 0], // tier bonus
              [address, sum * 10 / 100 * 125] ] // size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener = allocation.BonusIssued();

        await allocation.issueTokens(address, sum, {from: icoBackend});
        
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

            assert.equal(String(allocationArgs._beneficiary), 
                        expectedAllocations[i][0],
                        "incorrect address");

            assert.equal(Number(allocationArgs._contribution), 
                        expectedAllocations[i][1],
                        "sum mismatch");

            assert.equal(Number(allocationArgs._tokensIssued), 
                        expectedAllocations[i][2],
                        "allocation mismatch");

            totalTokens += Number(allocationArgs._tokensIssued);
        }

        let bonusIssuedLog = await new Promise(
                (resolve, reject) => bonusIssuedListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        for (let i=0; i<expectedBonuses.length; i++) {
            totalTokens += expectedBonuses[i][1];
        }

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(address);

        assert.equal(Number(balance),
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 12
    it("issue tokens for $150k, 5% size bonus", async function() {
        let address = accounts[9];
        let sum = 150 * 1e3 * 1e2;

        let expectedAllocations = [ [address, sum, sum * 125] ];

        let expectedBonuses =
            [ [address, 0], // tier bonus
              [address, sum * 5 / 100 * 125] ] // size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener = allocation.BonusIssued();

        await allocation.issueTokens(address, sum, {from: icoBackend});
        
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

            assert.equal(String(allocationArgs._beneficiary), 
                        expectedAllocations[i][0],
                        "incorrect address");

            assert.equal(Number(allocationArgs._contribution), 
                        expectedAllocations[i][1],
                        "sum mismatch");

            assert.equal(Number(allocationArgs._tokensIssued), 
                        expectedAllocations[i][2],
                        "allocation mismatch");

            totalTokens += Number(allocationArgs._tokensIssued);
        }

        let bonusIssuedLog = await new Promise(
                (resolve, reject) => bonusIssuedListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        for (let i=0; i<expectedBonuses.length; i++) {
            totalTokens += expectedBonuses[i][1];
        }

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(address);

        assert.equal(Number(balance),
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 13: end phase one
    it("end phase 1, check founders' and partners' rewards to be 18% and 12% of total", async () => {
        let token = ERC20.at(await allocation.tokenContract());
        await allocation.rewardFoundersAndPartners({from: icoBackend});

        let totalSupply = await token.totalSupply();

        let rewardsListener = allocation.FoundersAndPartnersTokensIssued();

        let rewardsIssuedLog = await new Promise(
                (resolve, reject) => rewardsListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        let allocationArgs = rewardsIssuedLog[0].args;

        // Checking within bounds to account for rounding
        assert.isAtLeast(Number(allocationArgs._tokensForFounders), 
                    totalSupply * 1795 / 10000,
                    "wrong number of tokens for founders");

        assert.isAtMost(Number(allocationArgs._tokensForFounders), 
                    totalSupply * 1805 / 10000,
                    "wrong number of tokens for founders");

        let vestingWallet = await(allocation.vestingWallet());
        let vestingBalance = await token.balanceOf(vestingWallet);

        assert.equal(Number(vestingBalance),
                     allocationArgs._tokensForFounders,
                     "vesting wallet created and received founders' tokens");

        assert.isAtLeast(Number(allocationArgs._tokensForPartners), 
                    totalSupply * 1195 / 10000,
                    "wrong number of tokens for partners");

        assert.isAtMost(Number(allocationArgs._tokensForPartners), 
                    totalSupply * 1205 / 10000,
                    "wrong number of tokens for partners");

        let partnersBalance = await token.balanceOf(allocationArgs._partnersWallet);

        assert.equal(Number(partnersBalance),
                     allocationArgs._tokensForPartners,
                     "partners should receive their tokens");
    });

    // TEST 14
    let newRate = 99;
    it("begin phase two with " + String(newRate) + " as token rate", async () => {
        await allocation.beginPhaseTwo(newRate, {from: icoManager});
    });

    // TEST 15
    it("issue tokens for $450k, 10% tier bonus, 0% size bonus", async function() {
        let address = 0x45ce;
        let sum = 450 * 1e3 * 1e2;

        let expectedAllocations = [ [address, sum, sum * newRate] ];

        let expectedBonuses =
            [ [address, sum * 10 / 100 * newRate], // tier bonus
              [address, 0 ] ] // size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener = allocation.BonusIssued();

        await allocation.issueTokens(address, sum, {from: icoBackend});
        
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

            assert.equal(String(allocationArgs._beneficiary), 
                        expectedAllocations[i][0],
                        "incorrect address");

            assert.equal(Number(allocationArgs._contribution), 
                        expectedAllocations[i][1],
                        "sum mismatch");

            assert.equal(Number(allocationArgs._tokensIssued), 
                        expectedAllocations[i][2],
                        "allocation mismatch");

            totalTokens += Number(allocationArgs._tokensIssued);
        }

        let bonusIssuedLog = await new Promise(
                (resolve, reject) => bonusIssuedListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        for (let i=0; i<expectedBonuses.length; i++) {
            totalTokens += expectedBonuses[i][1];
        }

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(address);

        assert.equal(Number(balance),
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 16
    it("issue tokens for $11m, 10% tier bonus for $9.55m, 0% size bonus for $1.45m", async function() {
        let address = 0x45cd;
        let sum = 11 * 1e6 * 1e2;

        let expectedAllocations = 
            [ [address, 9550 * 1e3 * 1e2, 9550 * 1e3 * 1e2 * newRate],
              [address, 1450 * 1e3 * 1e2, 1450 * 1e3 * 1e2 * newRate] ];

        let expectedBonuses =
            [ [address, 9550 * 1e3 * 1e2 * 10 / 100 * newRate], // tier 1 bonus
              [address, 0 ], // tier 2 bonus
              [address, 0 ] ]; // size bonus

        let tokenAllocationListener = allocation.TokensAllocated();
        let bonusIssuedListener = allocation.BonusIssued();

        await allocation.issueTokens(address, sum, {from: icoBackend});
        
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

            assert.equal(String(allocationArgs._beneficiary), 
                        expectedAllocations[i][0],
                        "incorrect address");

            assert.equal(Number(allocationArgs._contribution), 
                        expectedAllocations[i][1],
                        "sum mismatch");

            assert.equal(Number(allocationArgs._tokensIssued), 
                        expectedAllocations[i][2],
                        "allocation mismatch");

            totalTokens += Number(allocationArgs._tokensIssued);
        }

        let bonusIssuedLog = await new Promise(
                (resolve, reject) => bonusIssuedListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));

        for (let i=0; i<expectedBonuses.length; i++) {
            totalTokens += expectedBonuses[i][1];
        }

        let token = ERC20.at(await allocation.tokenContract());
        let balance = await token.balanceOf(address);

        assert.equal(Number(balance),
                     totalTokens,
                     "beneficiary should actually receive tokens");
    });

    // TEST 17: end phase two
    it("end phase 2, check founders' and partners' rewards to be 18% and 12% of total", async () => {
        let token = ERC20.at(await allocation.tokenContract());
        await allocation.rewardFoundersAndPartners({from: icoBackend});

        let totalSupply = await token.totalSupply();

        let rewardsListener = allocation.FoundersAndPartnersTokensIssued();
        let rewardsIssuedLog = await new Promise(
                (resolve, reject) => rewardsListener.get(
                    (error, log) => error ? reject(error) : resolve(log)
                    ));
        let allocationArgs = rewardsIssuedLog[0].args;

        let vestingWallet = await(allocation.vestingWallet());
        let vestingBalance = await token.balanceOf(vestingWallet);

        // Checking within bounds to account for rounding
        assert.isAtLeast(Number(vestingBalance), 
                    totalSupply * 1795 / 10000,
                    "wrong number of tokens for founders in vesting");
        assert.isAtMost(Number(vestingBalance), 
                    totalSupply * 1805 / 10000,
                    "wrong number of tokens for founders in vesting");


        let partnersBalance = await token.balanceOf(allocationArgs._partnersWallet);

        assert.isAtLeast(Number(partnersBalance), 
                    totalSupply * 1195 / 10000,
                    "wrong number of tokens for partners");
        assert.isAtMost(Number(partnersBalance), 
                    totalSupply * 1205 / 10000,
                    "wrong number of tokens for partners");
    });

    it("vesting is enabled", async () => {
        let vestingWallet = VestingWallet.at(await(allocation.vestingWallet()));
        let started = await(vestingWallet.vestingStarted());
        assert.isTrue(started, "vesting has started");
    });

    it("can release vesting batch of 1/24 size after 31 days", async () => {
        let increaseTime = addSeconds => web3.currentProvider
            .send({jsonrpc: "2.0", method: "evm_increaseTime", params: [addSeconds], id: 0})

        let vestingAddress = await(allocation.vestingWallet());
        let vestingWallet = VestingWallet.at(vestingAddress);
        let token = ERC20.at(await allocation.tokenContract());

        increaseTime(3600 * 24 * 31);
        await vestingWallet.releaseBatch({from: foundersWallet});
        assert.equal(1, await(vestingWallet.periodsPassed()), "1 period passed");

        // Again, within bounds to account for rounding
        assert.isAtLeast(
                Number( await( token.balanceOf( foundersWallet ))) * 23 * 1.01,
                Number( await( token.balanceOf( vestingAddress ))),
                "1/24th is collected by the founders");

        assert.isAtMost(
                Number( await( token.balanceOf( foundersWallet ))) * 23 * 0.99,
                Number( await( token.balanceOf( vestingAddress ))),
                "1/24th is collected by the founders");
    });
})
