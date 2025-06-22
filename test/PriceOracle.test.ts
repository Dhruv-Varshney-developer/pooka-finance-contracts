import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployFixture } from "./fixtures/deployFixture";

describe("PriceOracle", function () {
  it("Should get BTC price in realistic range", async function () {
    const { priceOracle } = await loadFixture(deployFixture);
    
    const [price, timestamp] = await priceOracle.getPrice("BTC/USD");
    
    // BTC typically between $80,000 - $120,000 (8 decimals)
    expect(Number(price)).to.be.gte(Number(ethers.parseUnits("80000", 8)));
    expect(Number(price)).to.be.lte(Number(ethers.parseUnits("120000", 8)));
    expect(Number(timestamp)).to.be.gt(0);
  });

  it("Should get ETH price in realistic range", async function () {
    const { priceOracle } = await loadFixture(deployFixture);
    
    const [price, timestamp] = await priceOracle.getPrice("ETH/USD");
    
    // ETH typically between $1,000 - $4,000 (8 decimals)
    expect(Number(price)).to.be.gte(Number(ethers.parseUnits("1000", 8)));
    expect(Number(price)).to.be.lte(Number(ethers.parseUnits("4000", 8)));
    expect(Number(timestamp)).to.be.gt(0);
  });

  it("Should get both asset prices", async function () {
    const { priceOracle } = await loadFixture(deployFixture);
    
    const [btcPrice] = await priceOracle.getPrice("BTC/USD");
    const [ethPrice] = await priceOracle.getPrice("ETH/USD");

    // Both prices should be positive and in realistic ranges
    expect(Number(btcPrice)).to.be.gte(Number(ethers.parseUnits("80000", 8)));
    expect(Number(ethPrice)).to.be.gte(Number(ethers.parseUnits("1000", 8)));
  });

  it("Should have recent timestamps", async function () {
    const { priceOracle } = await loadFixture(deployFixture);
    
    const currentTime = Math.floor(Date.now() / 1000);
    const [, btcTimestamp] = await priceOracle.getPrice("BTC/USD");
    const [, ethTimestamp] = await priceOracle.getPrice("ETH/USD");

    // Timestamps should be recent (within last hour)
    expect(Number(btcTimestamp)).to.be.gte(currentTime - 3600);
    expect(Number(ethTimestamp)).to.be.gte(currentTime - 3600);
  });

  it("Should revert for non-existent feeds", async function () {
    const { priceOracle } = await loadFixture(deployFixture);
    
    await expect(priceOracle.getPrice("INVALID/USD"))
      .to.be.rejectedWith("Price feed not set");
  });


});