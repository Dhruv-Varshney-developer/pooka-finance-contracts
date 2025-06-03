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
    
    event PriceFeedUpdated(string symbol, address feedAddress);
    
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
    
    function getPrice(string memory symbol) external view returns (uint256, uint256) {
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
            normalizedPrice = normalizedPrice * (10 ** (8 - decimals));
     } else if (decimals > 8) {
            normalizedPrice = normalizedPrice / (10 ** (decimals - 8));
        }
        
        return (normalizedPrice, updatedAt);
    }
    
    function isPriceStale(string memory symbol, uint256 maxAge) external view returns (bool) {
        (, uint256 updatedAt) = this.getPrice(symbol);
        return (block.timestamp - updatedAt) > maxAge;
    }
}