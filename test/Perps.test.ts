// @ts-nocheck

import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { deployFixture } from "./fixtures/deployFixture";

describe("Perps", function () {
  async function setupUserWithUSDC(fixture: any, user: any, amount = "1") {
    const depositAmount = ethers.parseUnits(amount, 6);
    await fixture.usdcToken
      .connect(user)
      .approve(await fixture.perps.getAddress(), depositAmount);
    await fixture.perps.connect(user).depositUSDC(depositAmount);
    return depositAmount;
  }

  describe("USDC Deposits", function () {
    it("Should deposit USDC correctly", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);

      const balance = await fixture.perps.getBalance(
        await fixture.user1.getAddress()
      );
      expect(balance).to.equal(ethers.parseUnits("100", 6));
    });

   it("Should enforce maximum deposit limit", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      const overLimit = ethers.parseUnits("101", 6);

      await fixture.usdcToken
        .connect(fixture.user1)
        .approve(await fixture.perps.getAddress(), overLimit);
      await expect(
        fixture.perps.connect(fixture.user1).depositUSDC(overLimit)
      ).to.be.rejectedWith("Max $100 per user");
    });
  });

  describe("USDC Withdrawals", function () {
    it("Should withdraw USDC correctly", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);

      const withdrawAmount = ethers.parseUnits("50", 6);
      await fixture.perps.connect(fixture.user1).withdrawUSDC(withdrawAmount);

      const balance = await fixture.perps.getBalance(
        await fixture.user1.getAddress()
      );
      expect(balance).to.equal(ethers.parseUnits("50", 6));
    });

    it("Should not allow withdrawal with open positions", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);

      // Open position
      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits("25", 6), 2, true);

      await expect(
        fixture.perps
          .connect(fixture.user1)
          .withdrawUSDC(ethers.parseUnits("25", 6))
      ).to.be.rejectedWith("Close all positions first");
    });
  });

  describe("Position Opening", function () {
    it("Should open long position correctly", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);

      await expect(
        fixture.perps
          .connect(fixture.user1)
          .openPosition("BTC/USD", ethers.parseUnits("50", 6), 2, true)
      ).to.emit(fixture.perps, "PositionOpened");

      const position = await fixture.perps.getPosition(
        await fixture.user1.getAddress(),
        "BTC/USD"
      );
      expect(position.isOpen).to.be.true;
      expect(position.sizeUSD).to.equal(ethers.parseUnits("100", 6)); // 2x leverage
      expect(position.isLong).to.be.true;
    });

    it("Should open short position correctly", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);

      await fixture.perps
        .connect(fixture.user1)
        .openPosition("ETH/USD", ethers.parseUnits("50", 6), 2, false);

      const position = await fixture.perps.getPosition(
        await fixture.user1.getAddress(),
        "ETH/USD"
      );
      expect(position.isLong).to.be.false;
    });

    it("Should enforce maximum leverage", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);

      await expect(
        fixture.perps
          .connect(fixture.user1)
          .openPosition("BTC/USD", ethers.parseUnits("50", 6), 4, true)
      ).to.be.rejectedWith("Max leverage is 3x");
    });

    it("Should deduct opening fees", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);

      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits(".50", 6), 2, true);

      const balance = await fixture.perps.getBalance(
        await fixture.user1.getAddress()
      );
      // $100 - $50 collateral - $0.5 opening fee = $49.5
      expect(balance).to.equal(ethers.parseUnits("49.5", 6));
    });
  });

  describe("Position Closing", function () {
    it("Should close profitable position with tax", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);
      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits("50", 6), 2, true);

      // Price goes up 10%
      await fixture.btcFeed.updateAnswer(ethers.parseUnits("55000", 8));

      const balanceBefore = await fixture.perps.getBalance(
        await fixture.user1.getAddress()
      );
      await fixture.perps.connect(fixture.user1).closePosition("BTC/USD");
      const balanceAfter = await fixture.perps.getBalance(
        await fixture.user1.getAddress()
      );

      // Should have profit but less than $10 due to fees and 30% tax
      expect(balanceAfter).to.be.gt(balanceBefore);
      expect(Number(balanceAfter - balanceBefore)).to.be.lt(Number(ethers.parseUnits("10", 6)));
    });

    it("Should close losing position", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);
      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits("50", 6), 2, true);

      // Price goes down 10%
      await fixture.btcFeed.updateAnswer(ethers.parseUnits("45000", 8));

      await fixture.perps.connect(fixture.user1).closePosition("BTC/USD");

      const position = await fixture.perps.getPosition(
        await fixture.user1.getAddress(),
        "BTC/USD"
      );
      expect(position.isOpen).to.be.false;
    });
  });

  describe("Liquidations", function () {
    it("Should liquidate underwater position", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);
      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits("50", 6), 2, true);

      // Crash price
      await fixture.btcFeed.updateAnswer(ethers.parseUnits("25000", 8));

      await expect(
        fixture.perps
          .connect(fixture.liquidator)
          .liquidatePosition(await fixture.user1.getAddress(), "BTC/USD")
      ).to.emit(fixture.perps, "PositionLiquidated");

      const position = await fixture.perps.getPosition(
        await fixture.user1.getAddress(),
        "BTC/USD"
      );
      expect(position.isOpen).to.be.false;
    });

    it("Should not liquidate healthy position", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);
      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits("50", 6), 2, true);

      // Small price drop
      await fixture.btcFeed.updateAnswer(ethers.parseUnits("48000", 8));

      await expect(
        fixture.perps
          .connect(fixture.liquidator)
          .liquidatePosition(await fixture.user1.getAddress(), "BTC/USD")
      ).to.be.rejectedWith("Not liquidatable");
    });

    it("Should liquidate multiple positions", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;

      // Setup two users with positions
      await setupUserWithUSDC(fixture, fixture.user1);
      await setupUserWithUSDC(fixture, fixture.user2);
      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits("50", 6), 2, true);
      await fixture.perps
        .connect(fixture.user2)
        .openPosition("ETH/USD", ethers.parseUnits("50", 6), 2, false);

      // Make both liquidatable
      await fixture.btcFeed.updateAnswer(ethers.parseUnits("25000", 8)); // Crash BTC
      await fixture.ethFeed.updateAnswer(ethers.parseUnits("6000", 8)); // Pump ETH

      const liquidatedCount = await fixture.perps
        .connect(fixture.liquidator)
        .liquidatePositions();
      expect(liquidatedCount).to.be.gt(0);
    });
  });

  describe("User Limits", function () {
    it("Should get user limits correctly", async function () {
      const fixture = (await loadFixture(deployFixture)) as any;
      await setupUserWithUSDC(fixture, fixture.user1);
      await fixture.perps
        .connect(fixture.user1)
        .openPosition("BTC/USD", ethers.parseUnits("50", 6), 2, true);

      const [
        maxBalance,
        currentBalance,
        maxExposure,
        currentExposure,
        remainingCapacity,
      ] = await fixture.perps.getUserLimits(await fixture.user1.getAddress());

      expect(maxBalance).to.equal(ethers.parseUnits("100", 6));
      expect(maxExposure).to.equal(ethers.parseUnits("300", 6));
      expect(currentExposure).to.equal(ethers.parseUnits("100", 6));
      expect(remainingCapacity).to.equal(ethers.parseUnits("200", 6));
    });
  });
});
