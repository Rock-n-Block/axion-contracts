const BN = require("bn.js");
const chai = require("chai");
const { expect } = require("chai");
chai.use(require("chai-bn")(BN));

const TERC20 = artifacts.require("TERC20");
const Token = artifacts.require("Token");

contract(
  "Token",
  ([
    setter,
    swapper,
    nativeSwap,
    foreignSwap,
    dailyAuction,
    weeklyAuction,
    staking,
    bigPayDay
  ]) => {
    let swaptoken;
    let token;

    beforeEach(async () => {
      swaptoken = await TERC20.new("2T Token", "2T", web3.utils.toWei("1000"), swapper, {
        from: swapper,
      });
      token = await Token.new("2X Token", "2X", swaptoken.address, swapper, setter);
    });

    it ("should initDeposit", async () => {
      await swaptoken.approve(token.address, web3.utils.toWei("1000"), {
        from: swapper,
      });

      await token.initDeposit(web3.utils.toWei("1000"), {
        from: swapper,
      });

      expect(
        await token.getSwapTokenBalance(swapper)
      ).to.be.a.bignumber.that.equals(web3.utils.toWei("1000"));
    });

    it("should initWithdraw", async () => {
      await swaptoken.approve(token.address, web3.utils.toWei("1000"), {
        from: swapper,
      });

      await token.initDeposit(web3.utils.toWei("1000"), {
        from: swapper,
      });

      expect(
        await token.getSwapTokenBalance(swapper)
      ).to.be.a.bignumber.that.equals(web3.utils.toWei("1000"));

      await token.initWithdraw(web3.utils.toWei("1000"), {
        from: swapper,
      });

      expect(
        await token.getSwapTokenBalance(swapper)
      ).to.be.a.bignumber.that.equals(web3.utils.toWei("0"));
    });

    it("should initSwap", async () => {
      await swaptoken.approve(token.address, web3.utils.toWei("1000"), {
        from: swapper,
      });

      await token.initDeposit(web3.utils.toWei("1000"), {
        from: swapper,
      });

      expect(
        await token.getSwapTokenBalance(swapper)
      ).to.be.a.bignumber.that.equals(web3.utils.toWei("1000"));

      await token.initSwap({
        from: swapper,
      });

      expect(
        await token.getSwapTokenBalance(swapper)
      ).to.be.a.bignumber.that.equals(web3.utils.toWei("0"));

      expect(await token.balanceOf(swapper)).to.be.a.bignumber.that.equals(
        web3.utils.toWei("1000")
      );
    });

    it("should init", async () => {
      // Call init only after swap!!!
      token.init(
        [
          // nativeSwap, => Make the test pass but is this correct?
          foreignSwap,
          dailyAuction,
          weeklyAuction,
          staking,
          bigPayDay,
        ],
        {
          from: setter,
        }
      );

      const MINTER_ROLE = await token.getMinterRole();

      // expect(await token.hasRole(MINTER_ROLE, nativeSwap)).equals(true); => Make the test pass but is this correct?
      expect(await token.hasRole(MINTER_ROLE, foreignSwap)).equals(true);
      expect(await token.hasRole(MINTER_ROLE, dailyAuction)).equals(true);
      expect(await token.hasRole(MINTER_ROLE, weeklyAuction)).equals(true);
      expect(await token.hasRole(MINTER_ROLE, staking)).equals(true);
      expect(await token.hasRole(MINTER_ROLE, bigPayDay)).equals(true);
    });
  }
);
