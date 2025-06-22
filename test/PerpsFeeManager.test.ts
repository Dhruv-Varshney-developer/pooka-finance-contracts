import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { deployFixture } from "./fixtures/deployFixture";

describe("PerpsFeeManager", function () {
  it("Should calculate opening fee (1%)", async function () {
    const { feeManager } = await loadFixture(deployFixture);
    const collateral = ethers.parseUnits("100", 6); // $100
    const fee = await feeManager.calculateOpeningFee(collateral);
    expect(fee).to.equal(ethers.parseUnits("1", 6)); // $1
  });

  it("Should calculate closing fee (1%)", async function () {
    const { feeManager } = await loadFixture(deployFixture);
    const collateral = ethers.parseUnits("100", 6);
    const fee = await feeManager.calculateClosingFee(collateral);
    expect(fee).to.equal(ethers.parseUnits("1", 6));
  });

  it("Should calculate holding fee for 1 day (1%)", async function () {
    const { feeManager } = await loadFixture(deployFixture);
    const currentTime = await time.latest();

    const position = {
      sizeUSD: ethers.parseUnits("100", 6),
      collateralUSDC: ethers.parseUnits("100", 6), // $100 collateral
      entryPrice: ethers.parseUnits("50000", 8),
      leverage: 2,
      isLong: true,
      isOpen: true,
      openTime: currentTime,
      lastFeeTime: currentTime - 86400, // 1 day ago
    };

    const fee = await feeManager.calculateHoldingFee(position);
    expect(fee).to.equal(ethers.parseUnits("1", 6)); // $1 for 1 day
  });

  it("Should calculate holding fee for multiple days", async function () {
    const { feeManager } = await loadFixture(deployFixture);
    const currentTime = await time.latest();

    const position = {
      sizeUSD: ethers.parseUnits("100", 6),
      collateralUSDC: ethers.parseUnits("100", 6),
      entryPrice: ethers.parseUnits("50000", 8),
      leverage: 2,
      isLong: true,
      isOpen: true,
      openTime: currentTime,
      lastFeeTime: currentTime - 86400 * 5, // 5 days ago
    };

    const fee = await feeManager.calculateHoldingFee(position);
    expect(fee).to.equal(ethers.parseUnits("5", 6)); // $5 for 5 days
  });

  it("Should calculate profit tax (30%)", async function () {
    const { feeManager } = await loadFixture(deployFixture);
    const profit = ethers.parseUnits("10", 6); // $10 profit
    const tax = await feeManager.calculateProfitTax(profit);
    expect(tax).to.equal(ethers.parseUnits("3", 6)); // $3 tax
  });

  it("Should calculate total fees", async function () {
    const { feeManager } = await loadFixture(deployFixture);
    const currentTime = await time.latest();

    const position = {
      sizeUSD: ethers.parseUnits("100", 6),
      collateralUSDC: ethers.parseUnits("50", 6), // $50 collateral
      entryPrice: ethers.parseUnits("50000", 8),
      leverage: 2,
      isLong: true,
      isOpen: true,
      openTime: currentTime,
      lastFeeTime: currentTime - 86400, // 1 day
    };

    const totalFees = await feeManager.calculateTotalFees(position);
    // Opening (1%) + Closing (1%) + Holding (1 day) = $1.5
    expect(totalFees).to.equal(ethers.parseUnits("1.5", 6));
  });
});
