const BN = require("bn.js");
const chai = require("chai");
const { expect } = require("chai");
const helper = require("./utils/utils.js");
chai.use(require("chai-bn")(BN));

const TERC20 = artifacts.require("TERC20");
const Token = artifacts.require("Token");
const NativeSwap = artifacts.require("NativeSwap");
const Auction = artifacts.require("Auction");
const SubBalancesMock = artifacts.require("SubBalancesMock");
const StakingMock = artifacts.require("StakingMock");

const UniswapV2Router02Mock = artifacts.require("UniswapV2Router02Mock");

const DAY = 86400;
const STAKE_PERIOD = 350;
const DEADLINE = web3.utils.toWei("10000000");
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

contract(
  "Auction",
  ([
    setter,
    foreignSwap,
    weeklyAuction,
    staking,
    bigPayDay,
    recipient,
    account1,
    account2,
    account3,
    account4,
  ]) => {
    let swaptoken;
    let token;
    let nativeswap;
    let dailyauction;
    let uniswap;
    let subBalances;

    beforeEach(async () => {
      nativeswap = await NativeSwap.new();

      swaptoken = await TERC20.new(
        "2T Token",
        "2T",
        web3.utils.toWei("10000000000"),
        setter
      );

      token = await Token.new(
        "2X Token",
        "2X",
        swaptoken.address,
        nativeswap.address,
        setter
      );

      dailyauction = await Auction.new();

      uniswap = await UniswapV2Router02Mock.new();

      subBalances = await SubBalancesMock.new();

      staking = await StakingMock.new();

      await token.init([
        dailyauction.address,
        nativeswap.address,
        dailyauction.address,
        dailyauction.address,
        dailyauction.address,
      ]);

      await nativeswap.init(
        new BN(STAKE_PERIOD.toString(), 10),
        new BN(DAY.toString(), 10),
        swaptoken.address,
        token.address,
        dailyauction.address
      );

      await dailyauction.init(
        new BN(DAY.toString(), 10),
        setter,
        token.address,
        staking.address,
        uniswap.address,
        recipient,
        nativeswap.address,
        foreignSwap,
        subBalances.address
      );
    });

    describe("bet", () => {
      it("should update the contract state correctly", async () => {
        // Advance the date to day 100 after launch
        await helper.advanceTimeAndBlock(DAY * 100);

        // ---------------------------------- 1st bet ----------------------------
        const prevRecipientETHBalance1 = await web3.eth.getBalance(recipient);

        // Bet with 10 eth
        await dailyauction.bet(DEADLINE, ZERO_ADDRESS, {
          from: account1,
          value: web3.utils.toWei("10"),
        });

        // _saveAuctionData()
        const currentAuctionId1 = await dailyauction.lastAuctionEventId();
        expect(currentAuctionId1.toString()).to.eq("100");

        const {
          eth: auctionEth1,
          token: token1,
          uniswapLastPrice: uniswapLastPrice1,
          uniswapMiddlePrice: uniswapMiddlePrice1,
        } = await dailyauction.reservesOf(currentAuctionId1);

        // _updatePrice();
        expect(uniswapLastPrice1.toString()).to.eq("1000000000000000000");
        expect(uniswapMiddlePrice1.toString()).to.eq("1000000000000000000");

        // User auction bet
        const userAuctionBet1 = await dailyauction.auctionBetOf(
          currentAuctionId1,
          account1
        );
        const { eth: userEth1, ref: ref1 } = userAuctionBet1;
        expect(web3.utils.fromWei(userEth1.toString())).to.eq("10");
        expect(ref1).to.eq(ZERO_ADDRESS);

        // Check the reserves of the auction
        expect(web3.utils.fromWei(auctionEth1.toString())).to.eq("10");
        expect(token1.toString()).to.eq("0");

        const postRecipientETHBalance1 = await web3.eth.getBalance(recipient);

        // 80% to uniswap, 20% to recipient
        const recipientETHBalanceChange1 = new BN(postRecipientETHBalance1).sub(
          new BN(prevRecipientETHBalance1)
        );
        expect(web3.utils.fromWei(recipientETHBalanceChange1)).to.eq("2");

        // ---------------------------------- 2nd bet ----------------------------
        const prevRecipientETHBalance2 = await web3.eth.getBalance(recipient);

        // Bet with 20 eth
        await dailyauction.bet(DEADLINE, account2, {
          from: account1,
          value: web3.utils.toWei("20"),
        });

        // _saveAuctionData()
        const currentAuctionId2 = await dailyauction.lastAuctionEventId();
        expect(currentAuctionId2.toString()).to.eq("100");

        const {
          eth: auctionEth2,
          token: token2,
          uniswapLastPrice: uniswapLastPrice2,
          uniswapMiddlePrice: uniswapMiddlePrice2,
        } = await dailyauction.reservesOf(currentAuctionId1);

        // _updatePrice();
        expect(uniswapLastPrice2.toString()).to.eq("1000000000000000000");
        expect(uniswapMiddlePrice2.toString()).to.eq("1000000000000000000");

        // User auction bet
        const userAuctionBet2 = await dailyauction.auctionBetOf(
          currentAuctionId1,
          account1
        );
        const { eth: userEth2, ref: ref2 } = userAuctionBet2;
        expect(web3.utils.fromWei(userEth2.toString())).to.eq("30");
        expect(ref2).to.eq(account2);

        // Check the reserves of the auction
        expect(web3.utils.fromWei(auctionEth2.toString())).to.eq("30");
        expect(token2.toString()).to.eq("0");

        const postRecipientETHBalance2 = await web3.eth.getBalance(recipient);

        // 80% to uniswap, 20% to recipient
        const recipientETHBalanceChange2 = new BN(postRecipientETHBalance2).sub(
          new BN(prevRecipientETHBalance2)
        );
        expect(web3.utils.fromWei(recipientETHBalanceChange2)).to.eq("4");
      });
    });

    describe("withdraw", () => {
      describe("failure cases", () => {
        it("should fail if the user withdraws before betting", async () => {
          // Advance the date to day 51 after launch
          await helper.advanceTimeAndBlock(DAY * 51);

          try {
            // Withdraw on day 50
            await dailyauction.withdraw("50", { from: account1 });
            expect.fail("it should fail");
          } catch (err) {
            expect(err.reason).to.eq("zero balance in auction");
          }
        });

        it("should fail if the auction is still active", async () => {
          // Advance the date to day 51 after launch
          await helper.advanceTimeAndBlock(DAY * 50);

          try {
            // Withdraw on day 50
            await dailyauction.withdraw("50", { from: account1 });
            expect.fail("it should fail");
          } catch (err) {
            expect(err.reason).to.eq("auction is active");
          }
        });
      });

      describe("successful cases", () => {
        beforeEach(async () => {
          // setter swap swapToken to mainToken - to generate penalty
          await swaptoken.approve(
            nativeswap.address,
            web3.utils.toWei("10000000000"),
            { from: setter }
          );
          await nativeswap.deposit(web3.utils.toWei("100000"), {
            from: setter,
          });

          // Advance the date to day 175 after launch - so there is a penalty 50%
          await helper.advanceTimeAndBlock(DAY * 175);
          await nativeswap.swapNativeToken({ from: setter });
          // Advance to day 176, we will bet on this day
          await helper.advanceTimeAndBlock(DAY);

          const auctionMainTokenBalance = await token.balanceOf(
            dailyauction.address
          );
          // The penalty is transferred to the auction = 100000 * 50% = 50000
          expect(web3.utils.fromWei(auctionMainTokenBalance.toString())).to.eq(
            "50000"
          );
        });

        it("should success and update the contract state correctly (without ref)", async () => {
          // User1 & User 2: Bet with 10 eth
          await dailyauction.bet(DEADLINE, ZERO_ADDRESS, {
            from: account1,
            value: web3.utils.toWei("10"),
          });
          await dailyauction.bet(DEADLINE, ZERO_ADDRESS, {
            from: account2,
            value: web3.utils.toWei("20"),
          });

          // Advance the date to day 177 after launch, so the auction on day 176 is ended
          await helper.advanceTimeAndBlock(DAY);

          // User1 & User2: Withdraw on day 8
          await dailyauction.withdraw("176", { from: account1 });
          await dailyauction.withdraw("176", { from: account2 });

          // Check state of user1 and user2
          const user1AuctionBet = await dailyauction.auctionBetOf(
            "176",
            account1
          );
          const { eth: user1Eth, ref: user1Ref } = user1AuctionBet;
          expect(web3.utils.fromWei(user1Eth)).to.eq("0");
          expect(user1Ref).to.eq(ZERO_ADDRESS);

          const user2AuctionBet = await dailyauction.auctionBetOf(
            "176",
            account1
          );
          const { eth: user2Eth, ref: user2Ref } = user2AuctionBet;
          expect(web3.utils.fromWei(user2Eth)).to.eq("0");
          expect(user2Ref).to.eq(ZERO_ADDRESS);

          const [event1, event2] = await dailyauction.getPastEvents(
            "Withdraval",
            {
              fromBlock: 0,
              toBlock: "latest",
            }
          );
          expect(event1.returnValues.value).to.eq("12000000000000000000");
          expect(event2.returnValues.value).to.eq("24000000000000000000");
        });

        it("should success and update the contract state correctly (with ref)", async () => {
          // User1 & User 2: Bet with 10 eth
          await dailyauction.bet(DEADLINE, account3, {
            from: account1,
            value: web3.utils.toWei("10"),
          });
          await dailyauction.bet(DEADLINE, account3, {
            from: account2,
            value: web3.utils.toWei("30"),
          });

          // Advance the date to day 177 after launch, so the auction on day 176 is ended
          await helper.advanceTimeAndBlock(DAY);

          // User1 & User2: Withdraw on day 8
          await dailyauction.withdraw("176", { from: account1 });
          await dailyauction.withdraw("176", { from: account2 });

          // Check state of user1 and user2
          const user1AuctionBet = await dailyauction.auctionBetOf(
            "176",
            account1
          );
          const { eth: user1Eth, ref: user1Ref } = user1AuctionBet;
          expect(web3.utils.fromWei(user1Eth)).to.eq("0");
          expect(user1Ref).to.eq(account3);

          const user2AuctionBet = await dailyauction.auctionBetOf(
            "176",
            account1
          );
          const { eth: user2Eth, ref: user2Ref } = user2AuctionBet;
          expect(web3.utils.fromWei(user2Eth)).to.eq("0");
          expect(user2Ref).to.eq(account3);

          const [event1, event2] = await dailyauction.getPastEvents(
            "Withdraval",
            {
              fromBlock: 0,
              toBlock: "latest",
            }
          );
          expect(event1.returnValues.value).to.eq("13200000000000000000");
          expect(event2.returnValues.value).to.eq("39600000000000000000");
        });
      });
    });
  }
);
