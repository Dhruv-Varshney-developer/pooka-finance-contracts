// SPDX-License-Identifier: MIT
// Note: The contracts are built for POC purposes for pooka finance & have not been audited.
// Do not deploy in production unless audited and improved.

pragma solidity ^0.8.0;

import "contracts/PriceOracle.sol";

/**
 * @title CrossChainPerps
 * @dev Main perpetual trading contract with cross-chain capabilities
 */
contract Perps {
    // Position struct to store user positions
    struct Position {
        uint256 size; // Position size in USD (8 decimals)
        uint256 collateral; // Collateral deposited (18 decimals ETH)
        uint256 entryPrice; // Price when position was opened (8 decimals)
        uint256 leverage; // Leverage for the position
        bool isLong; // true for long, false for short
        bool isOpen; // Position status
        uint256 openTime;       // When position was opened
    }

    // Market data
    struct Market {
        string symbol;          // e.g., "BTC/USD"
        uint256 maxLeverage;    // Maximum allowed leverage
        uint256 maintenanceMargin; // Maintenance margin percentage (basis points)
        uint256 totalLongSize;   // Total long positions in USD (for risk management)
        uint256 totalShortSize;  // Total short positions in USD (for risk management)
        bool isActive;          // Market status
    }

    // Position info struct for getPosition return
    struct PositionInfo {
        //Basic Position Data
        uint256 size;
        uint256 collateral;
        uint256 entryPrice;
                uint256 leverage; 

        bool isLong;
        bool isOpen;
        // Real time computed data
        uint256 currentPrice;
        uint256 liquidationPrice;
        int256 unrealizedPnL;
        int256 netPnL; // Same as unrealizedPnL (no funding)
        bool canBeLiquidated;
    }

    
    // Constants
    // TODO: In production, make them configurable by owner/admin.
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 hours; // Max price age
    uint256 public constant PRECISION = 1e8; // Price precision

    // State variables
    PriceOracle public priceOracle;
    mapping(address => mapping(string => Position)) public positions;
    mapping(string => Market) public markets;
    mapping(address => uint256) public balances; // User collateral balances in wei

    string[] public marketSymbols;
    address public owner;

    // Events
    event PositionOpened(
        address indexed user,
        string symbol,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        bool isLong,
        uint256 leverage
    );
    event PositionClosed(address indexed user, string symbol, int256 pnl);
    event PositionLiquidated(address indexed user, string symbol, int256 pnl, uint256 liquidationPrice);
    event MarketAdded(string symbol, uint256 maxLeverage);
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address _priceOracle) {
        owner = msg.sender;
        priceOracle = PriceOracle(_priceOracle);

        // Initialize default markets
        _addMarket("BTC/USD", 20, 500); // 20x leverage, 5% maintenance margin
        _addMarket("ETH/USD", 15, 667); // 15x leverage, 6.67% maintenance margin
    }

    function _addMarket(string memory symbol, uint256 maxLeverage, uint256 maintenanceMargin) internal {
        markets[symbol] = Market({
            symbol: symbol,
            maxLeverage: maxLeverage,
            maintenanceMargin: maintenanceMargin,
            totalLongSize: 0,
            totalShortSize: 0,
            isActive: true
        });
        marketSymbols.push(symbol);
        emit MarketAdded(symbol, maxLeverage);
    }
    
    function addMarket(string memory symbol, uint256 maxLeverage, uint256 maintenanceMargin) external onlyOwner {
        require(!markets[symbol].isActive && bytes(markets[symbol].symbol).length == 0, "Market already exists");
        _addMarket(symbol, maxLeverage, maintenanceMargin);
    }

    function removeMarket(string memory symbol) external onlyOwner {
        require(markets[symbol].isActive, "Market does not exist");
        require(
            markets[symbol].totalLongSize == 0 &&
                markets[symbol].totalShortSize == 0,
            "Market has open positions"
        );

        // Remove from marketSymbols array
        for (uint256 i = 0; i < marketSymbols.length; i++) {
            if (
                keccak256(bytes(marketSymbols[i])) == keccak256(bytes(symbol))
            ) {
                marketSymbols[i] = marketSymbols[marketSymbols.length - 1];
                marketSymbols.pop();
                break;
            }
        }

        // Reset market struct
        delete markets[symbol];
    }

    // Deposit collateral
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be > 0");
        balances[msg.sender] += msg.value;
    }

    // Withdraw collateral (if no open positions)
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(!_hasOpenPositions(msg.sender), "Close all positions first");

        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

    // Open a new position
    function openPosition(
        string memory symbol,
        uint256 collateralAmount,
        uint256 leverage,
        bool isLong
    ) external {
        Market memory market = markets[symbol];
        require(market.isActive, "Market not active");
        require(collateralAmount > 0, "Collateral must be > 0");
        require(leverage > 0 && leverage <= market.maxLeverage, "Invalid leverage");
        require(balances[msg.sender] >= collateralAmount, "Insufficient balance");
        require(!positions[msg.sender][symbol].isOpen, "Position already exists");
        
        // Get current price
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);
        require(!priceOracle.isPriceStale(symbol, PRICE_STALENESS_THRESHOLD), "Price too stale");
        
        // Calculate position size
        uint256 positionSize = (collateralAmount * leverage * currentPrice) / 1e18;
        
        // Create simplified position (NO FUNDING FIELDS)
        positions[msg.sender][symbol] = Position({
            size: positionSize,
            collateral: collateralAmount,
            entryPrice: currentPrice,
            leverage: leverage,
            isLong: isLong,
            isOpen: true,
            openTime: block.timestamp
        });
        
        // Update balances and market data
        balances[msg.sender] -= collateralAmount;
        
        if (isLong) {
            markets[symbol].totalLongSize += positionSize;
        } else {
            markets[symbol].totalShortSize += positionSize;
        }
        
        emit PositionOpened(msg.sender, symbol, positionSize, collateralAmount, currentPrice, isLong, leverage);
    }

    // Close position
    function closePosition(string memory symbol) external {
        Position storage position = positions[msg.sender][symbol];
        require(position.isOpen, "No open position");
        
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);
        require(!priceOracle.isPriceStale(symbol, PRICE_STALENESS_THRESHOLD), "Price too stale");
        
        // Calculate PnL only (no funding)
        int256 pnl = _calculatePnL(msg.sender, symbol, currentPrice);
        
        // Calculate final collateral after PnL
        int256 finalCollateral = int256(position.collateral) + pnl;
        
        // Update market totals
        if (position.isLong) {
            markets[symbol].totalLongSize -= position.size;
        } else {
            markets[symbol].totalShortSize -= position.size;
        }
        
        // Close position
        position.isOpen = false;
        
        // Return remaining collateral (ensure non-negative)
        if (finalCollateral > 0) {
            balances[msg.sender] += uint256(finalCollateral);
        }
        
        emit PositionClosed(msg.sender, symbol, pnl);
    }

    // Calculate unrealized P&L in wei
    function _calculatePnL(
        address user,
        string memory symbol,
        uint256 currentPrice
    ) internal view returns (int256) {
        Position memory position = positions[user][symbol];
        if (!position.isOpen) return 0;
            // Check for zero prices to prevent division by zero
    require(position.entryPrice > 0, "Invalid entry price");
    require(currentPrice > 0, "Invalid current price");


        // PnL = (currentPrice - entryPrice) * positionSize / entryPrice
        int256 priceDiff = int256(currentPrice) - int256(position.entryPrice);
        int256 pnlUSD = (priceDiff * int256(position.size)) /
            int256(position.entryPrice);

        // Convert USD PnL to wei using current price
        int256 pnlWei = (pnlUSD * 1e18) / int256(currentPrice);

        return position.isLong ? pnlWei : -pnlWei;
    }

    

/**
 * @dev Calculate the liquidation price for a position
 * @param user The user's address
 * @param symbol The market symbol
 * @return liquidationPrice The price at which position will be liquidated (8 decimals)
 */
function _calculateLiquidationPrice(address user, string memory symbol) internal view returns (uint256) {
    Position memory position = positions[user][symbol];
    if (!position.isOpen) return 0;
    
    Market memory market = markets[symbol];
    
    // Step 1: Calculate maintenance margin required
    uint256 maintenanceMargin = (position.collateral * market.maintenanceMargin) / 10000;
    
    // Step 2: Available collateral that can be lost before liquidation
    uint256 availableCollateral = position.collateral - maintenanceMargin;
    
    // Step 3: Convert available collateral (ETH) to USD value at entry price
    uint256 maxLossUSD = (availableCollateral * position.entryPrice) / 1e18;
    
    // Step 4: Calculate what price change would cause this loss
    uint256 priceChange = (maxLossUSD * position.entryPrice) / position.size;
    
    // Step 5: Calculate liquidation price based on position direction
    if (position.isLong) {
        // Long: liquidated when price drops
        return position.entryPrice > priceChange ? position.entryPrice - priceChange : 0;
    } else {
        // Short: liquidated when price rises  
        return position.entryPrice + priceChange;
    }
}




    // Check if position can be liquidated
        function canLiquidate(address user, string memory symbol) public view returns (bool) {
        Position memory position = positions[user][symbol];
        if (!position.isOpen) return false;
        
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);
        
        int256 pnl = _calculatePnL(user, symbol, currentPrice);
        int256 currentValue = int256(position.collateral) + pnl;
        int256 maintenanceMargin = int256((position.collateral * markets[symbol].maintenanceMargin) / 10000);
        
        return currentValue <= maintenanceMargin;
    }

    // Liquidate position
    function liquidatePosition(address user, string memory symbol) external {
        require(canLiquidate(user, symbol), "Position not liquidatable");
        
        Position storage position = positions[user][symbol];
        
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);
        int256 pnl = _calculatePnL(user, symbol, currentPrice);
        
        // Update market totals
        if (position.isLong) {
            markets[symbol].totalLongSize -= position.size;
        } else {
            markets[symbol].totalShortSize -= position.size;
        }
        
        // Close position
        position.isOpen = false;
        
        emit PositionLiquidated(user, symbol, pnl, currentPrice);
    }



    // Get basic position info
    function getPosition(address user, string memory symbol) external view returns (PositionInfo memory) {
        Position memory position = positions[user][symbol];
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);
        
        int256 unrealizedPnL = _calculatePnL(user, symbol, currentPrice);
        
        return PositionInfo({
            size: position.size,
            collateral: position.collateral,
            entryPrice: position.entryPrice,
            leverage: position.leverage,
            isLong: position.isLong,
            isOpen: position.isOpen,
            currentPrice: currentPrice,
            liquidationPrice: _calculateLiquidationPrice(user, symbol),
            unrealizedPnL: unrealizedPnL,
            netPnL: unrealizedPnL, // Same as unrealized (no funding)
            canBeLiquidated: canLiquidate(user, symbol)
        });
    }

    
    // Get market info with current price
    function getMarket(string memory symbol) external view returns (
        uint256 currentPrice,
        uint256 priceTimestamp,
        uint256 totalLongSize,
        uint256 totalShortSize,
        uint256 maxLeverage,
        bool isActive
    ) {
        Market memory market = markets[symbol];
        (uint256 price, uint256 timestamp) = priceOracle.getPrice(symbol);
        
        return (price, timestamp, market.totalLongSize, market.totalShortSize, market.maxLeverage, market.isActive);
    }

    // Check if user has any open positions
    function _hasOpenPositions(address user) internal view returns (bool) {
        for (uint256 i = 0; i < marketSymbols.length; i++) {
            if (positions[user][marketSymbols[i]].isOpen) {
                return true;
            }
        }
        return false;
    }

    // Get user's available balance
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    // Get all market symbols
    function getMarketSymbols() external view returns (string[] memory) {
        return marketSymbols;
    }

    // Emergency functions
    function setPriceOracle(address _priceOracle) external onlyOwner {
        priceOracle = PriceOracle(_priceOracle);
    }

    function toggleMarket(string memory symbol) external onlyOwner {
        markets[symbol].isActive = !markets[symbol].isActive;
    }
}
