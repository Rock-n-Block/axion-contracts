const BN = require("bn.js");
const chai = require("chai");
const { expect } = require("chai");
const helper = require("./utils/utils.js");
chai.use(require("chai-bn")(BN));

const TERC20 = artifacts.require("TERC20");
const Token = artifacts.require("Token");
const NativeSwap = artifacts.require("NativeSwap");
const Auction = artifacts.require("Auction");

const UniswapV2Router02Mock = artifacts.require("UniswapV2Router02Mock");

const DAY = 86400;
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

    beforeEach(async () => {
      swaptoken = await TERC20.new(
        "2T Token",
        "2T",
        web3.utils.toWei("10000000000"),
        {
          from: setter,
        }
      );

      // SYSTEM DEPLOY
      uniswap = await UniswapV2Router02Mock.new();

      token = await Token.new("2X Token", "2X", swaptoken.address, setter);

      // Deploy and init native swap
      nativeswap = await NativeSwap.new();

      // Deploy and init daily auction
      dailyauction = await Auction.new();
      dailyauction.init(
        DAY,
        token.address,
        staking,
        uniswap.address,
        recipient,
        nativeswap.address,
        foreignSwap
      );

      nativeswap.init(
        new BN(DAY.toString(), 10),
        swaptoken.address,
        token.address,
        dailyauction.address
      );

      // Owners 1/1 native swap
      await swaptoken.approve(token.address, web3.utils.toWei("10000"), {
        from: setter,
      });

      await token.initDeposit(web3.utils.toWei("10000"), {
        from: setter,
      });

      await token.initSwap({ from: setter });

      // Uniswap liquidity in main token
      token.transfer(uniswap.address, web3.utils.toWei("10000"), {
        from: setter,
      });

      // Init token
      token.init(
        [
          nativeswap.address,
          foreignSwap,
          dailyauction.address,
          weeklyAuction,
          staking,
          bigPayDay,
        ],
        { from: setter }
      );

      // NATIVE SWAP
      swaptoken.transfer(account3, web3.utils.toWei("100"), { from: setter });

      await swaptoken.approve(nativeswap.address, web3.utils.toWei("100"), {
        from: account3,
      });

      await nativeswap.deposit(web3.utils.toWei("100"), {
        from: account3,
      });

      // Change node time and swap
      await helper.advanceTimeAndBlock(DAY * 350);
      await nativeswap.swapNativeToken({ from: account3 });
    });

    it("should bet", async () => {
      const prevRecipientETHBAlance = await web3.eth.getBalance(recipient);

      await dailyauction.bet(DEADLINE, ZERO_ADDRESS, {
        from: account1,
        value: web3.utils.toWei("10"),
      });

      const currentAuctionId = await dailyauction.currentAuctionId();

      // User Auiction 0 ETH balance
      expect(
        (await dailyauction.auctionEthBalanceOf(currentAuctionId, account1)).eth
      ).to.be.a.bignumber.that.equals(web3.utils.toWei("10"));

      // Recipient ETH balance 20%
      expect(
        await web3.eth.getBalance(recipient)
      ).to.be.a.bignumber.that.equals(
        new BN(prevRecipientETHBAlance, 10).add(
          new BN(web3.utils.toWei("2"), 10)
        )
      );

      // Staking main token balance (80% 1/1 to eth only in test)
      expect(await token.balanceOf(staking)).to.be.a.bignumber.that.equals(
        web3.utils.toWei("8")
      );
    });

    it("should withdraw without ref", async () => {
      await dailyauction.bet(DEADLINE, ZERO_ADDRESS, {
        from: account1,
        value: web3.utils.toWei("10"),
      });

      await dailyauction.bet(DEADLINE, ZERO_ADDRESS, {
        from: account2,
        value: web3.utils.toWei("10"),
      });

      const currentAuctionId = await dailyauction.currentAuctionId();

      // Change node time and swap
      await helper.advanceTimeAndBlock(DAY * 1);

      await dailyauction.withdraw(currentAuctionId, {
        from: account1,
      });

      await dailyauction.withdraw(currentAuctionId, {
        from: account2,
      });

      expect(await token.balanceOf(account1)).to.be.a.bignumber.that.equals(
        web3.utils.toWei("50")
      );

      expect(await token.balanceOf(account2)).to.be.a.bignumber.that.equals(
        web3.utils.toWei("50")
      );
    });

    it("should withdraw with ref", async () => {
      await dailyauction.bet(DEADLINE, account4, {
        from: account1,
        value: web3.utils.toWei("10"),
      });

      await dailyauction.bet(DEADLINE, ZERO_ADDRESS, {
        from: account2,
        value: web3.utils.toWei("10"),
      });

      const currentAuctionId = await dailyauction.currentAuctionId();

      // Change node time and swap
      await helper.advanceTimeAndBlock(DAY * 1);

      await dailyauction.withdraw(currentAuctionId, {
        from: account1,
      });

      await dailyauction.withdraw(currentAuctionId, {
        from: account2,
      });

      expect(await token.balanceOf(account1)).to.be.a.bignumber.that.equals(
        web3.utils.toWei("60")
      );

      expect(await token.balanceOf(account2)).to.be.a.bignumber.that.equals(
        web3.utils.toWei("50")
      );

      expect(await token.balanceOf(account4)).to.be.a.bignumber.that.equals(
        web3.utils.toWei("5")
      );
    });
  }
);
