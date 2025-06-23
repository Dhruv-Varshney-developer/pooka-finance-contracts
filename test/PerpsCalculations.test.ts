import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { deployFixture } from "./fixtures/deployFixture";

describe("PerpsCalculations", function () {
  const createPosition = async (isLong = true) => {
    const currentTime = await time.latest();
    return {
      sizeUSD: ethers.parseUnits("100", 6), //$100 position
      collateralUSDC: ethers.parseUnits("50", 6), //$50 collateral
      entryPrice: ethers.parseUnits("50000", 8), // $50,000 entry
      leverage: 2,
      isLong,
      isOpen: true,
      openTime: currentTime, // Use block timestamp
      lastFeeTime: currentTime, // Use block timestamp
    };
  };

  const createMarket = () => ({
    symbol: "BTC/USD",
    maxLeverage: 3,
    maintenanceMargin: 500, // 5%
    totalLongSizeUSD: 0,
    totalShortSizeUSD: 0,
    isActive: true,
  });

  it("Should calculate positive PnL for long position", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const position = await createPosition(true);
    const currentPrice = ethers.parseUnits("55000", 8); // 10% up

    const pnl = await calculator.calculatePnL(position, currentPrice);
    expect(pnl).to.equal(ethers.parseUnits("10", 6)); // $10 profit
  });

  it("Should calculate negative PnL for long position", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const position = await createPosition(true);
    const currentPrice = ethers.parseUnits("45000", 8); // 10% down

    const pnl = await calculator.calculatePnL(position, currentPrice);
    expect(pnl).to.equal(ethers.parseUnits("-10", 6)); // $10 loss
  });

  it("Should calculate positive PnL for short position", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const position = await createPosition(false); // Short
    const currentPrice = ethers.parseUnits("45000", 8); // 10% down

    const pnl = await calculator.calculatePnL(position, currentPrice);
    expect(pnl).to.equal(ethers.parseUnits("10", 6)); // $10 profit for short
  });

  it("Should calculate liquidation price for long position", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const position = await createPosition(true);
    const market = createMarket();

    const liqPrice = await calculator.calculateLiquidationPrice(
      position,
      market
    );
    // Should be around $27,500 (50% drop from $50k)
    expect(Number(liqPrice)).to.be.closeTo(
      Number(ethers.parseUnits("26250", 8)),
      Number(ethers.parseUnits("1000", 8))
    );
  });

  it("Should detect liquidatable position", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const position = await createPosition(true);
    const market = createMarket();
    const crashPrice = ethers.parseUnits("25000", 8); // 50% crash

    const canLiquidate = await calculator.canLiquidate(
      position,
      market,
      crashPrice
    );
    expect(canLiquidate).to.be.true;
  });

  it("Should not liquidate healthy position", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const position = await createPosition(true);
    const market = createMarket();
    const healthyPrice = ethers.parseUnits("48000", 8); // Small drop

    const canLiquidate = await calculator.canLiquidate(
      position,
      market,
      healthyPrice
    );
    expect(canLiquidate).to.be.false;
  });

  it("Should calculate margin ratio", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const position = await createPosition(true);
    const currentPrice = ethers.parseUnits("50000", 8); // No change

    const ratio = await calculator.calculateMarginRatio(position, currentPrice);
    expect(Number(ratio)).to.equal(5000); // 50% = 5000 basis points
  });

  it("Should liquidate due to accumulated fees", async function () {
    const { calculator } = await loadFixture(deployFixture);
    const currentTime = await time.latest();

    const position = {
      ...await createPosition(true),
      lastFeeTime: currentTime - 86400 * 90, // 90 days of fees
    };
    const market = createMarket();
    const currentPrice = ethers.parseUnits("48000", 8); // Small drop

    const canLiquidate = await calculator.canLiquidate(
      position,
      market,
      currentPrice
    );
    expect(canLiquidate).to.be.true; // Should liquidate due to fees
  });
});
