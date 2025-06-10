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
    event DailyDataUpdated(string symbol, uint256 high, uint256 low, uint256 change);

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

    /**
     * @dev View 24h data WITHOUT updating state 
     * @notice ⚠️ This shows historical data only - may be stale or show zeros if never updated
     * @notice Call get24hData() first to initialize/update the tracking data
     * 
     * FRONTEND USAGE:
     * - Use this for quick reads without gas costs
     * - But call get24hData() periodically to update the underlying data
     * - If all values are 0, it means get24hData() was never called for this symbol
     */
    function view24hDataWithoutUpdate(string memory symbol)
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
        (currentPrice, ) = this.getPrice(symbol);
        DailyData memory daily = dailyData[symbol];

        // Calculate change with existing data (may be stale)
        if (daily.price24hAgo > 0) {
            if (currentPrice >= daily.price24hAgo) {
                priceChange = currentPrice - daily.price24hAgo;
                changePercent = int256((priceChange * 10000) / daily.price24hAgo);
            } else {
                priceChange = daily.price24hAgo - currentPrice;
                changePercent = -int256((priceChange * 10000) / daily.price24hAgo);
            }
        }

        return (currentPrice, daily.high24h, daily.low24h, priceChange, changePercent);
    }

    /**
     * @dev Get 24h data WITH state updates (always fresh and accurate)
     * @notice This updates the tracking data and returns current 24h statistics
     * FRONTEND USAGE:
     * - Call this function to get updated 24h data
     * - Set up periodic calls (every 1-4 hours) for better accuracy
     * - Price values need to be divided by 1e8 for display
     */
    function get24hData(string memory symbol)
        external
        returns (
            uint256 currentPrice, // Divide by 1e8 for actual price
            uint256 high24h,// Divide by 1e8 for actual price
            uint256 low24h,// Divide by 1e8 for actual price
            uint256 priceChange, // Absolute change (divide by 1e8)
            int256 changePercent // Percentage in basis points (150 = 1.50%)
        )
    {
        (currentPrice, ) = this.getPrice(symbol);
        
        // Update daily tracking with current price
        _updateDailyData(symbol, currentPrice);
        
        DailyData memory daily = dailyData[symbol];

        // Calculate change with updated data
        if (daily.price24hAgo > 0) {
            if (currentPrice >= daily.price24hAgo) {
                priceChange = currentPrice - daily.price24hAgo;
                changePercent = int256((priceChange * 10000) / daily.price24hAgo);
            } else {
                priceChange = daily.price24hAgo - currentPrice;
                changePercent = -int256((priceChange * 10000) / daily.price24hAgo);
            }
        }

        return (currentPrice, daily.high24h, daily.low24h, priceChange, changePercent);
    }

    /**
     * @dev Update 24h data manually
     */
    function update24hData(string memory symbol) external {
        (uint256 currentPrice, ) = this.getPrice(symbol);
        _updateDailyData(symbol, currentPrice);
    }

    /**
     * @dev Internal: Update 24h tracking data
     * 
     * WHY THE 24H CONDITION?
     * Every 24 hours, we need to "reset" our tracking window:
     * - Set new "24h ago" price (current price becomes the new baseline)
     * - Reset high/low to current price (start fresh 24h window)
     * 
     * Without this reset, we'd track data from the beginning of time,
     * not just the last 24 hours.
     */
    function _updateDailyData(string memory symbol, uint256 currentPrice) internal {
        DailyData storage daily = dailyData[symbol];

        // RESET CONDITION: First time OR 24 hours have passed
        if (
            daily.lastUpdateTime == 0 ||                              // First time
            block.timestamp >= daily.lastUpdateTime + 24 hours        // 24h window ended
        ) {
            // Start new 24h tracking window
            daily.price24hAgo = currentPrice;    // Current price becomes "24h ago" baseline
            daily.high24h = currentPrice;        // Reset high to current
            daily.low24h = currentPrice;         // Reset low to current
            daily.lastUpdateTime = block.timestamp;  // Mark start of new window
        }
        // UPDATE CONDITION: Within same 24h window
        else {
            // Just update high/low within current window
            if (currentPrice > daily.high24h) {
                daily.high24h = currentPrice;
            }
            if (currentPrice < daily.low24h) {
                daily.low24h = currentPrice;
            }
        }

        lastDailyUpdate[symbol] = block.timestamp;
        emit DailyDataUpdated(symbol, daily.high24h, daily.low24h, currentPrice);
    }
}