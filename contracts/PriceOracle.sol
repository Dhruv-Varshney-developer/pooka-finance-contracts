// SPDX-License-Identifier: MIT
// Note: The contracts are built for POC purposes for pooka finance & have not been audited.
// Do not deploy in production unless audited and improved.

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceOracle
 * @dev Handles Chainlink price feed integration
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
    mapping(string => uint256) public lastDailyUpdate; // When we last updated daily data

    uint256 public constant UPDATE_INTERVAL = 1 hours; // Update daily data every hour

    event PriceFeedUpdated(string symbol, address feedAddress);
    event DailyDataUpdated(
        string symbol,
        uint256 high,
        uint256 low,
        uint256 change
    );

    constructor() {
        // Initialize common price feeds (Sepolia testnet addresses)
        _setPriceFeed("BTC/USD", 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43); // BTC/USD
        _setPriceFeed("ETH/USD", 0x694AA1769357215DE4FAC081bf1f309aDC325306); // ETH/USD
    }

    function _setPriceFeed(string memory symbol, address feedAddress) internal {
        priceFeeds[symbol] = AggregatorV3Interface(feedAddress);
        emit PriceFeedUpdated(symbol, feedAddress);
    }

    // Security note: In production, this should have onlyOwner modifier
    function setPriceFeed(string memory symbol, address feedAddress) external {
        _setPriceFeed(symbol, feedAddress);
    }

    function getPrice(string memory symbol)
        external
        view
        returns (uint256, uint256)
    {
        AggregatorV3Interface priceFeed = priceFeeds[symbol];
        require(address(priceFeed) != address(0), "Price feed not set");

        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        require(price > 0, "Invalid price");
        require(updatedAt > 0, "Price not updated");

        // Chainlink prices have different decimals, normalize to 8 decimals
        uint8 decimals = priceFeed.decimals();
        uint256 normalizedPrice = uint256(price);

        if (decimals < 8) {
            normalizedPrice = normalizedPrice * (10**(8 - decimals));
        } else if (decimals > 8) {
            normalizedPrice = normalizedPrice / (10**(decimals - 8));
        }

        return (normalizedPrice, updatedAt);
    }

    // Pure view function for 24h data
    function view24hData(string memory symbol)
        external
        view
        returns (
            uint256 currentPrice,
            uint256 high24h,
            uint256 low24h,
            uint256 priceChange,
            int256 changePercent
        )
    {
        // Get current price (view only)
        (currentPrice, ) = this.getPrice(symbol);

        // Read existing daily data (no updates)
        DailyData memory daily = dailyData[symbol];

        // Calculate change with existing data
        if (daily.price24hAgo > 0) {
            if (currentPrice >= daily.price24hAgo) {
                priceChange = currentPrice - daily.price24hAgo;
                changePercent = int256(
                    (priceChange * 10000) / daily.price24hAgo
                );
            } else {
                priceChange = daily.price24hAgo - currentPrice;
                changePercent = -int256(
                    (priceChange * 10000) / daily.price24hAgo
                );
            }
        }

        return (
            currentPrice,
            daily.high24h,
            daily.low24h,
            priceChange,
            changePercent
        );
    }

    //  State-changing function for updates
    function update24hData(string memory symbol) external {
        (uint256 currentPrice, ) = this.getPrice(symbol);
        _updateDailyData(symbol, currentPrice);
    }

    /**
     * @dev Internal: Update 24h data if needed
     */
    function _updateDailyData(string memory symbol, uint256 currentPrice)
        internal
    {
        DailyData storage daily = dailyData[symbol];

        // If first time or 24h passed, reset the 24h tracking
        if (
            daily.lastUpdateTime == 0 ||
            block.timestamp >= daily.lastUpdateTime + 24 hours
        ) {
            daily.price24hAgo = currentPrice;
            daily.high24h = currentPrice;
            daily.low24h = currentPrice;
            daily.lastUpdateTime = block.timestamp;
        }
        // Otherwise, just update high/low
        else {
            if (currentPrice > daily.high24h) {
                daily.high24h = currentPrice;
            }
            if (currentPrice < daily.low24h) {
                daily.low24h = currentPrice;
            }
        }

        lastDailyUpdate[symbol] = block.timestamp;
        emit DailyDataUpdated(
            symbol,
            daily.high24h,
            daily.low24h,
            currentPrice
        );
    }

    function isPriceStale(string memory symbol, uint256 maxAge)
        external
        view
        returns (bool)
    {
        (, uint256 updatedAt) = this.getPrice(symbol);
        return (block.timestamp - updatedAt) > maxAge;
    }
}
