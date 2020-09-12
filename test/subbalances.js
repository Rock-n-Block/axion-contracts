const BN = require("bn.js");
const chai = require("chai");
const { expect } = require("chai");
const helper = require("./utils/utils.js");
const expectRevert = require("./utils/expectRevert.js");
chai.use(require("chai-bn")(BN));
const EthCrypto = require("eth-crypto");


const TERC20 = artifacts.require("TERC20");
const Token = artifacts.require("Token");
const ForeignSwap = artifacts.require("ForeignSwap");
const AuctionMock = artifacts.require("AuctionMock");
const StakingMock = artifacts.require("StakingMock");
const BPD = artifacts.require("BPD");
const SubBalances = artifacts.require("SubBalances")

const DAY = 86400;

const testSigner = web3.utils.toChecksumAddress("0xCC64d26Dab6c7B971d26846A4B2132985fe8C358");
const testSignerPriv = "eaac3bee2ca2316bc2dad3f2efcc91c17cee394d45cebc8529bfa250061dac89";
const totalSnapshotAmount = new BN(10 ** 10);
const totalSnapshotAddresses = new BN(10);

const getMessageHash = (encodeTypes, args) => {
  let encoded = web3.eth.abi.encodeParameters(encodeTypes, args);
  return web3.utils.soliditySha3(encoded);
};
 
const sign = (address, pkey, messageParamsTypes, messageParams) => {
  const messageHash = getMessageHash(
    messageParamsTypes,
    messageParams
  );
 
  return EthCrypto.sign(pkey, messageHash);
};


contract(
  "SubBalances",
  ([
    bank,
    setter,
    signer,
    nativeSwap,
    stakingCaller,
    account1,
    account2
  ]) => {
    let swaptoken;
    let token;
    let foreignswap;
    let auction;
    let stakingContract;
    let bpd;
    let signAmount;
    let testSignature;
    let maxClaimAmount;

    beforeEach(async () => {
      maxClaimAmount = new BN(10 ** 7);
      signAmount = maxClaimAmount;
      testSignature = sign(
        testSigner,
        testSignerPriv,
        ["uint256", "address"],
        [signAmount.toString(), account1]
      );

      swaptoken = await TERC20.new("2T Token", "2T", web3.utils.toWei("1000"), {
        from: bank,
      });
      token = await Token.new("2X Token", "2X", swaptoken.address, setter);

      auction = await AuctionMock.new();
      stakingContract = await StakingMock.new();

      // Deploy foreign swap
      foreignswap = await ForeignSwap.new(setter);

      // Deploy BigPayDay Pool
      bpd = await BPD.new(setter);

      // Deploy SubBalances Contract
      subbalances = await SubBalances.new(setter);

      // Init token
      token.init(
        [
          nativeSwap,
          foreignswap.address,
          auction.address,
          stakingContract.address,
          subbalances.address,
        ],
        { from: setter }
      );

      // Init foreign swap
      foreignswap.init(
        testSigner, 
        new BN(DAY.toString(), 10),
        maxClaimAmount,
        token.address,
        auction.address,
        stakingContract.address,
        bpd.address,
        totalSnapshotAmount,
        totalSnapshotAddresses,
        { from: setter }
      );

      // Init BPD Pool
      bpd.init(
        token.address,
        foreignswap.address,
        subbalances.address,
        { from: setter }
      );

      // Init SubBalances Contract
      subbalances.init(
        token.address,
        foreignswap.address,
        bpd.address,
        auction.address,
        stakingCaller,
        new BN(DAY.toString(), 10),
        new BN("350"),
        { from: setter }
      );

    });


    const getBlockchainTimestamp = async () => {
        const latestBlock = await web3.eth.getBlock('latest');
        return latestBlock.timestamp;
    };


    it("should generate payout pool on 350 day", async () => {
        const amountBefore = await foreignswap.getUserClaimableAmountFor(
            signAmount
        );

        await helper.advanceTimeAndBlock(DAY * 175);

        const amountAfter = await foreignswap.getUserClaimableAmountFor(
            signAmount
        );

        expect(amountAfter[0]).to.be.a.bignumber.that.equals(amountBefore[0].div(new BN("2")));

        await foreignswap.claimFromForeign(signAmount, testSignature, {
            from: account1,
        });

        const dividedAmount = signAmount.div(new BN("2"))
        expect(
            await token.balanceOf(account1)
        ).to.be.a.bignumber.that.equals(dividedAmount);

        const dividedAmountPart = dividedAmount.div(new BN("350"));
        expect(
            await token.balanceOf(auction.address)
        ).to.be.a.bignumber.that.equals(dividedAmountPart.mul(new BN("349")));
        expect(
            await token.balanceOf(bpd.address)
        ).to.be.a.bignumber.that.equals(dividedAmountPart);

        const bpdAmountPercent = dividedAmountPart.div(new BN("100"));

        const currentPoolAmounts = await bpd.getPoolYearAmounts();
        const yearOnePool = currentPoolAmounts[0];
        console.log(yearOnePool.toString());

        expect(
            yearOnePool
        ).to.be.a.bignumber.that.equals(bpdAmountPercent.mul(new BN("10")));

        expect(
            await token.balanceOf(subbalances.address)
        ).to.be.a.bignumber.zero;

        // Switch time once again to 350
        await helper.advanceTimeAndBlock((DAY * 175) + 10);

        const times = await subbalances.getStartTimes()

        expect(new BN(await getBlockchainTimestamp()))
        .to.be.a.bignumber.that.above(times[0]);

        await subbalances.generatePool();

        expect(
            (await subbalances.getPoolsMinted())[0]
        ).to.be.a.true;


        expect(
            await token.balanceOf(subbalances.address)
        ).to.be.a.bignumber.that.above(yearOnePool);

        expect(
            await token.balanceOf(bpd.address)
        ).to.be.a.bignumber.that.equals(dividedAmountPart.sub(yearOnePool));

        const firstPoolAmount = (await subbalances.getPoolsMintedAmounts())[0]
        console.log(firstPoolAmount.toString());
        expect(
            firstPoolAmount
        ).to.be.a.bignumber.that.above(yearOnePool);
    });

    it("should withdraw payout for staker", async () => {
        const amountBefore = await foreignswap.getUserClaimableAmountFor(
            signAmount
        );

        await helper.advanceTimeAndBlock(DAY * 175);

        const amountAfter = await foreignswap.getUserClaimableAmountFor(
            signAmount
        );

        expect(amountAfter[0]).to.be.a.bignumber.that.equals(amountBefore[0].div(new BN("2")));

        await foreignswap.claimFromForeign(signAmount, testSignature, {
            from: account1,
        });

        const stakeId = new BN("1");
        const stakeStartTime = new BN(await getBlockchainTimestamp());
        const stakeEndTime = stakeStartTime.add(new BN((DAY * 350) + 10));
        const stakeShares = signAmount;

        await subbalances.callIncomeStakerTrigger(
          account1,
          stakeId,
          stakeStartTime,
          stakeEndTime,
          signAmount,
          { from: stakingCaller }
        )

        const dividedAmount = signAmount.div(new BN("2"))
        expect(
            await token.balanceOf(account1)
        ).to.be.a.bignumber.that.equals(dividedAmount);

        const dividedAmountPart = dividedAmount.div(new BN("350"));
        expect(
            await token.balanceOf(auction.address)
        ).to.be.a.bignumber.that.equals(dividedAmountPart.mul(new BN("349")));
        expect(
            await token.balanceOf(bpd.address)
        ).to.be.a.bignumber.that.equals(dividedAmountPart);

        const bpdAmountPercent = dividedAmountPart.div(new BN("100"));

        const currentPoolAmounts = await bpd.getPoolYearAmounts();
        const yearOnePool = currentPoolAmounts[0];

        expect(
            yearOnePool
        ).to.be.a.bignumber.that.equals(bpdAmountPercent.mul(new BN("10")));

        expect(
            await token.balanceOf(subbalances.address)
        ).to.be.a.bignumber.zero;

        // Switch time once again to 350
        await helper.advanceTimeAndBlock((DAY * 175) + 5);

        const times = await subbalances.getStartTimes()

        expect(new BN(await getBlockchainTimestamp()))
        .to.be.a.bignumber.that.above(times[0]);

        await subbalances.callOutcomeStakerTrigger(
          account1,
          stakeId,
          stakeStartTime,
          stakeEndTime,
          signAmount,
          { from: stakingCaller }
        )

        const payoutAmountsBefore = await subbalances.calculateSessionPayout(stakeId); 
        // const payoutBefore = payoutAmountsBefore[0];
        // const penaltyBefore = payoutAmountsBefore[1];
        // console.log(payoutBefore.toString());
        // console.log(penaltyBefore.toString());

        await subbalances.generatePool();

        expect(
            (await subbalances.getPoolsMinted())[0]
        ).to.be.a.true;

        expect(
            await token.balanceOf(subbalances.address)
        ).to.be.a.bignumber.that.above(yearOnePool);

        expect(
            await token.balanceOf(bpd.address)
        ).to.be.a.bignumber.that.equals(dividedAmountPart.sub(yearOnePool));

        expect(
            (await subbalances.getPoolsMintedAmounts())[0]
        ).to.be.a.bignumber.that.above(yearOnePool);

        const payoutAmounts = await subbalances.calculateSessionPayout(stakeId); 
        // const payout = payoutAmountsBefore[0];
        // const penalty = payoutAmountsBefore[1];
        // console.log(payout.toString());
        // console.log(penalty.toString());


        const userBalanceBefore = await token.balanceOf(account1);
        console.log(userBalanceBefore.toString());

        const stakeSessions = await subbalances.getSessionEligibility(stakeId);
        console.log(stakeSessions);

        await subbalances.withdrawPayout(stakeId, {from: account1});

        const userBalanceAfter = await token.balanceOf(account1);
        console.log(userBalanceAfter.toString());

        expect(userBalanceAfter).to.be.a.bignumber.that.above(userBalanceBefore);


    });

  }
);
