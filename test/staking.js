const BN = require("bn.js");
const chai = require("chai");
const { expect } = require("chai");
const helper = require("./utils/utils.js");
chai.use(require("chai-bn")(BN));

const TERC20 = artifacts.require("TERC20");
const Staking = artifacts.require("Staking");
const SubBalancesMock = artifacts.require("SubBalancesMock");

const DAY = 86400;

contract("Staking", ([bank, foreignSwap, subBalances, staker1, staker2]) => {
  let token;
  let staking;
  let subbalances;

  beforeEach(async () => {
    token = await TERC20.new("2X Token", "2X", web3.utils.toWei("10000"), {
      from: bank,
    });

    subbalances = await SubBalancesMock.new();

    await token.transfer(staker1, web3.utils.toWei("100"), { from: bank });
    await token.transfer(staker2, web3.utils.toWei("100"), { from: bank });

    staking = await Staking.new();
    await staking.init(token.address, subbalances.address, foreignSwap);
  });

  // it("should stake", async () => {
  //   await token.approve(staking.address, web3.utils.toWei("10"), {
  //     from: staker1,
  //   });

  //   await staking.stake(web3.utils.toWei("10"), 100, {
  //     from: staker1,
  //   });

  //   expect(
  //     await staking.getAccountSessionsLen(staker1)
  //   ).to.be.a.bignumber.that.equals(new BN("1", 10));

  //   const sessionId = await staking.sessionsOf(staker1, 0);

  //   const sessionData = await staking.sessionDataOf(staker1, sessionId);

  //   expect(sessionData.amount).to.be.a.bignumber.that.equals(
  //     web3.utils.toWei("10")
  //   );

  //   expect(sessionData.sessionIsActive).equals(true);
  // });

  it("should make payout", async () => {
    await token.approve(staking.address, web3.utils.toWei("10"), {
      from: staker1,
    });

    await staking.stake(web3.utils.toWei("10"), 100, {
      from: staker1,
    });

    await token.transfer(staking.address, web3.utils.toWei("100"), {
      from: bank,
    });

    // Change node time and swap
    await helper.advanceTimeAndBlock(DAY * 1);

    await staking.makePayout();

    const { payout, sharesTotalSupply } = await staking.payouts(0);

    console.log({
      payout: payout.toString(),
      sharesTotalSupply: sharesTotalSupply.toString(),
    });

    // expect(
    //   await staking.getAccountSessionsLen(staker1)
    // ).to.be.a.bignumber.that.equals(new BN("1", 10));

    // expect(sessionData.amount).to.be.a.bignumber.that.equals(
    //   web3.utils.toWei("10")
    // );

    // expect(sessionData.sessionIsActive).equals(true);
  });

  // it("should unstake", async () => {
  //   await token.approve(staking.address, web3.utils.toWei("10"), {
  //     from: staker1,
  //   });

  //   await staking.stake(web3.utils.toWei("10"), 100, {
  //     from: staker1,
  //   });

  //   await token.approve(staking.address, web3.utils.toWei("10"), {
  //     from: staker2,
  //   });

  //   await staking.stake(web3.utils.toWei("10"), 100, {
  //     from: staker2,
  //   });

  //   await token.transfer(staker1, web3.utils.toWei("100"), { from: bank });

  //   await staking.makePayout();

  //   // Change node time and swap
  //   await helper.advanceTimeAndBlock(DAY * 100);

  //   await staking.unstake(web3.utils.toWei("10"), 100, {
  //     from: staker1,
  //   });

  //   expect(
  //     await staking.getAccountSessionsLen(staker1)
  //   ).to.be.a.bignumber.that.equals(new BN("1", 10));

  //   const sessionId = await staking.sessionsOf(staker1, 0);

  //   const sessionData = await staking.sessionDataOf(staker1, sessionId);

  //   expect(sessionData.amount).to.be.a.bignumber.that.equals(
  //     web3.utils.toWei("10")
  //   );

  //   expect(sessionData.sessionIsActive).equals(true);
  // });
});
