// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceOracle
 * @dev Handles Chainlink price feed integration with 24h tracking
 */
contract PriceOracle {
    mapping(string => AggregatorV3Interface) public priceFeeds;

    event PriceFeedUpdated(string symbol, address feedAddress);

    constructor() {
        // Real Chainlink price feeds on Fuji
        _setPriceFeed("BTC/USD", 0x31CF013A08c6Ac228C94551d535d5BAfE19c602a);
        _setPriceFeed("ETH/USD", 0x86d67c3D38D2bCeE722E601025C25a575021c6EA);
        _setPriceFeed("AVAX/USD", 0x5498BB86BC934c8D34FDA08E81D444153d0D06aD);
        _setPriceFeed("LINK/USD", 0x34C4c526902d88a3Aa98DB8a9b802603EB1E3470);
    }

    function _setPriceFeed(string memory symbol, address feedAddress) internal {
        priceFeeds[symbol] = AggregatorV3Interface(feedAddress);
        emit PriceFeedUpdated(symbol, feedAddress);
    }

    function setPriceFeed(string memory symbol, address feedAddress) external {
        _setPriceFeed(symbol, feedAddress);
    }

    /**
     * @dev Get current price from Chainlink
     * @return normalizedPrice Price with 8 decimals (divide by 1e8 for actual price)
     * @return updatedAt Timestamp when price was last updated
     *
     * FRONTEND EXPLANATION:
     * - BTC/USD returns: 10924049875600 = $109,240.49875600 (divide by 1e8)
     * - ETH/USD returns: 267698271300 = $2,676.98271300 (divide by 1e8)
     * - Formula: actualPrice = returnedValue / 100000000
     * - Example: 10924049875600 / 100000000 = 109240.49875600
     */
    function getPrice(string memory symbol)
        external
        view
        returns (uint256 normalizedPrice, uint256 updatedAt)
    {
        AggregatorV3Interface priceFeed = priceFeeds[symbol];
        require(address(priceFeed) != address(0), "Price feed not set");

        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAtChainlink,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        require(price > 0, "Invalid price");
        require(updatedAtChainlink > 0, "Price not updated");

        // Normalize all prices to 8 decimals for consistency
        uint8 decimals = priceFeed.decimals();
        normalizedPrice = uint256(price);

        if (decimals < 8) {
            normalizedPrice = normalizedPrice * (10**(8 - decimals));
        } else if (decimals > 8) {
            normalizedPrice = normalizedPrice / (10**(decimals - 8));
        }

        return (normalizedPrice, updatedAtChainlink);
    }
}
