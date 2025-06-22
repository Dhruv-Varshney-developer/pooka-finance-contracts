// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceOracle
 * @dev Handles Chainlink price feed integration with 24h tracking
 */
contract PriceOracle {
    mapping(string => AggregatorV3Interface) public priceFeeds;
    mapping(string => uint256) public lastUpdated;

    struct DailyData {
        uint256 price24hAgo; // Price 24h ago
        uint256 high24h; // 24h high
        uint256 low24h; // 24h low
        uint256 lastUpdateTime; // When this was last updated
    }
    mapping(string => DailyData) public dailyData;
    mapping(string => uint256) public lastDailyUpdate;

    uint256 public constant UPDATE_INTERVAL = 1 hours;

    event PriceFeedUpdated(string symbol, address feedAddress);
    event DailyDataUpdated(
        string symbol,
        uint256 high,
        uint256 low,
        uint256 change
    );

    constructor() {
        _setPriceFeed("BTC/USD", 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
        _setPriceFeed("ETH/USD", 0x694AA1769357215DE4FAC081bf1f309aDC325306);
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
