// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "contracts/PriceOracle.sol";
import "./PerpsStructs.sol";
import "./PerpsEvents.sol";
import "./PerpsFeeManager.sol";
import "./PerpsCalculations.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Perps
 * @dev Main perpetual trading contract - USDC-based collateral
 */
contract Perps is PerpsEvents {
    // State variables
    PriceOracle public priceOracle;
    PerpsFeeManager public feeManager;
    PerpsCalculations public calculator;

    mapping(address => mapping(string => PerpsStructs.Position)) public positions;
    mapping(address => mapping(uint256 => PerpsStructs.Deposit)) public deposits;
    mapping(string => PerpsStructs.Market) public markets;
    mapping(address => uint256) public userDepositCount;
    mapping(address => uint256) public balances; // USDC balances (6 decimals)

    string[] public marketSymbols;
    address public owner;
    address public poolManager; // Pool manager for cross-chain deposits
    IERC20 public usdcToken;

    // User tracking for liquidations
    address[] public allUsers;
    mapping(address => bool) public hasPositionHistory;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyPoolManager() {
        require(msg.sender == poolManager, "Only pool manager");
        _;
    }

    constructor(
        address _priceOracle,
        address _feeManager,
        address _calculator,
        address _usdcToken
    ) {
        owner = msg.sender;
        priceOracle = PriceOracle(_priceOracle);
        feeManager = PerpsFeeManager(_feeManager);
        calculator = PerpsCalculations(_calculator);
        usdcToken = IERC20(_usdcToken);
        // Initialize default markets with 3x max leverage
        _addMarket("BTC/USD", 3, 500);
        _addMarket("ETH/USD", 3, 667);
    }

    /**
     * @dev Set pool manager address (for cross-chain deposits)
     */
    function setPoolManager(address _poolManager) external onlyOwner {
        poolManager = _poolManager;
    }

    /**
     * @dev Deposit USDC collateral
     * @param usdcAmount Amount of USDC to deposit (6 decimals)
     */
    function depositUSDC(uint256 usdcAmount) external {
        require(usdcAmount > 0, "Deposit amount must be > 0");
        require(balances[msg.sender] + usdcAmount <= 100_000_000, "Max $100 per user"); // 100 USDC (6 decimals)

        // Transfer USDC from user
        bool success = usdcToken.transferFrom(msg.sender, address(this), usdcAmount);
        require(success, "Transfer failed");

        PerpsStructs.Deposit memory userDeposit = PerpsStructs.Deposit(
            block.timestamp,
            usdcAmount
        );
        
        // Increase no. of deposits by user
        uint256 depositIndex = ++userDepositCount[msg.sender];

        // Insert the deposit struct into the mapping
        deposits[msg.sender][depositIndex] = userDeposit;
        // Add to user's balance (USDC has 6 decimals)
        balances[msg.sender] += usdcAmount;

        emit Deposit(msg.sender, usdcAmount);
    }

    /**
     * @dev Deposit USDC collateral on behalf of user (for cross-chain deposits)
     * @param user User address to credit the deposit to
     * @param usdcAmount Amount of USDC to deposit (6 decimals)
     */
    function depositUSDCForUser(address user, uint256 usdcAmount) external onlyPoolManager {
        require(user != address(0), "Invalid user address");
        require(usdcAmount > 0, "Deposit amount must be > 0");
        require(balances[user] + usdcAmount <= 100_000_000, "Max $100 per user"); // 100 USDC (6 decimals)

        // Transfer USDC from PoolManager to Perps
        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);
        
        // Add to user's balance (USDC has 6 decimals)
        balances[user] += usdcAmount;

        emit Deposit(user, usdcAmount);
    }

    /**
     * @dev Withdraw USDC collateral
     * @param usdcAmount Amount of USDC to withdraw (6 decimals)
     */
    function withdrawUSDC(uint256 usdcAmount) external {
        require(balances[msg.sender] >= usdcAmount, "Insufficient balance");
        require(!_hasOpenPositions(msg.sender), "Close all positions first");

        balances[msg.sender] -= usdcAmount;
        usdcToken.transfer(msg.sender, usdcAmount);

        emit Withdrawal(msg.sender, usdcAmount);
    }

    /**
     * @dev Open position with USDC collateral
     * @param symbol Market symbol (e.g., "BTC/USD")
     * @param collateralUSDC Collateral amount in USDC (6 decimals)
     * @param leverage Leverage multiplier
     * @param isLong Position direction
     */
    function openPosition(
        string memory symbol,
        uint256 collateralUSDC,
        uint256 leverage,
        bool isLong
    ) external {
        PerpsStructs.Market memory market = markets[symbol];
        require(market.isActive, "Market not active");
        require(collateralUSDC > 0, "Collateral must be > 0");
        require(
            leverage > 0 && leverage <= 3,
            "Max leverage is 3x"
        );
        require(
            !positions[msg.sender][symbol].isOpen,
            "Position already exists"
        );

        // Calculate fees using fee manager
        uint256 openingFee = feeManager.calculateOpeningFee(collateralUSDC);
        uint256 totalRequired = collateralUSDC + openingFee;
        require(balances[msg.sender] >= totalRequired, "Insufficient balance");

        // Get current price (8 decimals from oracle)
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);

        // Calculate position size in USD (normalize to 6 decimals like USDC)
        // collateralUSDC (6 decimals) * leverage = position size in USD (6 decimals)
        uint256 positionSizeUSD = collateralUSDC * leverage;
        
        // Ensure user doesn't exceed $100 total exposure
        require(
            _getUserTotalExposure(msg.sender) + positionSizeUSD <= 300_000_000,
            "Max $300 total exposure per user (3x $100 collateral)"
        );

        // Track user for liquidations
        if (!hasPositionHistory[msg.sender]) {
            allUsers.push(msg.sender);
            hasPositionHistory[msg.sender] = true;
        }

        // Create position
        positions[msg.sender][symbol] = PerpsStructs.Position({
            sizeUSD: positionSizeUSD,
            collateralUSDC: collateralUSDC,
            entryPrice: currentPrice,
            leverage: leverage,
            isLong: isLong,
            isOpen: true,
            openTime: block.timestamp,
            lastFeeTime: block.timestamp
        });

        // Update balances and market data
        balances[msg.sender] -= totalRequired;

        if (isLong) {
            markets[symbol].totalLongSizeUSD += positionSizeUSD;
        } else {
            markets[symbol].totalShortSizeUSD += positionSizeUSD;
        }

        emit PositionOpened(
            msg.sender,
            symbol,
            positionSizeUSD,
            collateralUSDC,
            currentPrice,
            isLong,
            leverage
        );
    }

    /**
     * @dev Close position and settle in USDC
     */
    function closePosition(string memory symbol) external {
        PerpsStructs.Position storage position = positions[msg.sender][symbol];
        require(position.isOpen, "No open position");

        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);

        // Calculate all fees and PnL in USDC
        uint256 holdingFees = feeManager.calculateHoldingFee(position);
        int256 pnlUSDC = calculator.calculatePnL(position, currentPrice);
        uint256 closingFee = feeManager.calculateClosingFee(position.collateralUSDC);
        
        // Apply 30% profit tax if position is profitable
        uint256 profitTax = 0;
        if (pnlUSDC > 0) {
            profitTax = (uint256(pnlUSDC) * 30) / 100;
        }

        // Calculate final USDC amount
        int256 finalUSDCAmount = int256(position.collateralUSDC) + 
                                pnlUSDC - 
                                int256(holdingFees) - 
                                int256(closingFee) -
                                int256(profitTax);

        // Update market totals
        if (position.isLong) {
            markets[symbol].totalLongSizeUSD -= position.sizeUSD;
        } else {
            markets[symbol].totalShortSizeUSD -= position.sizeUSD;
        }

        position.isOpen = false;
        position.lastFeeTime = block.timestamp;

        // Add final amount to user's balance if positive
        if (finalUSDCAmount > 0) {
            balances[msg.sender] += uint256(finalUSDCAmount);
        }

        emit PositionClosed(msg.sender, symbol, pnlUSDC, holdingFees + profitTax);
    }

    /**
     * @dev Liquidate a single position if liquidatable
     */
    function liquidatePosition(address user, string memory symbol) 
        external 
        returns (bool) 
    {
        PerpsStructs.Position storage position = positions[user][symbol];
        require(position.isOpen, "No open position");

        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);
        require(
            calculator.canLiquidate(position, markets[symbol], currentPrice),
            "Not liquidatable"
        );

        // Update market totals before closing
        if (position.isLong) {
            markets[symbol].totalLongSizeUSD -= position.sizeUSD;
        } else {
            markets[symbol].totalShortSizeUSD -= position.sizeUSD;
        }

        // Close position - user loses all remaining collateral
        uint256 collateralLost = position.collateralUSDC;
        position.isOpen = false;
        position.lastFeeTime = block.timestamp;
        
        emit PositionLiquidated(user, symbol, collateralLost, msg.sender);
        return true;
    }

    /**
     * @dev Liquidate all liquidatable positions (for automation)
     */
    function liquidatePositions() external returns (uint256 liquidated) {
        liquidated = 0;
        
        // Iterate through all users who ever had positions
        for (uint256 i = 0; i < allUsers.length; i++) {
            address user = allUsers[i];
            
            // Check all markets for this user
            for (uint256 j = 0; j < marketSymbols.length; j++) {
                string memory symbol = marketSymbols[j];
                PerpsStructs.Position storage position = positions[user][symbol];
                
                if (!position.isOpen) continue;
                
                (uint256 currentPrice, ) = priceOracle.getPrice(symbol);
                
                if (calculator.canLiquidate(position, markets[symbol], currentPrice)) {
                    // Update market totals
                    if (position.isLong) {
                        markets[symbol].totalLongSizeUSD -= position.sizeUSD;
                    } else {
                        markets[symbol].totalShortSizeUSD -= position.sizeUSD;
                    }
                    
                    // Close position
                    uint256 collateralLost = position.collateralUSDC;
                    position.isOpen = false;
                    position.lastFeeTime = block.timestamp;
                    
                    emit PositionLiquidated(user, symbol, collateralLost, msg.sender);
                    liquidated++;
                }
            }
        }
        
        return liquidated;
    }

    /**
     * @dev Get comprehensive position information
     */
    function getPosition(address user, string memory symbol)
        external
        view
        returns (PerpsStructs.PositionInfo memory)
    {
        PerpsStructs.Position memory position = positions[user][symbol];
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);

        int256 unrealizedPnL = calculator.calculatePnL(position, currentPrice);
        uint256 accruedFees = feeManager.calculateHoldingFee(position);

        return PerpsStructs.PositionInfo({
            sizeUSD: position.sizeUSD,
            collateralUSDC: position.collateralUSDC,
            entryPrice: position.entryPrice,
            leverage: position.leverage,
            isLong: position.isLong,
            isOpen: position.isOpen,
            currentPrice: currentPrice,
            liquidationPrice: calculator.calculateLiquidationPrice(
                position,
                markets[symbol]
            ),
            unrealizedPnL: unrealizedPnL,
            accruedFees: accruedFees,
            netPnL: unrealizedPnL - int256(accruedFees),
            canBeLiquidated: calculator.canLiquidate(
                position,
                markets[symbol],
                currentPrice
            )
        });
    }

    /**
     * @dev Internal function to add new trading markets
     */
    function _addMarket(
        string memory symbol,
        uint256 maxLeverage,
        uint256 maintenanceMargin
    ) internal {
        markets[symbol] = PerpsStructs.Market({
            symbol: symbol,
            maxLeverage: maxLeverage,
            maintenanceMargin: maintenanceMargin,
            totalLongSizeUSD: 0,
            totalShortSizeUSD: 0,
            isActive: true
        });
        marketSymbols.push(symbol);
        emit MarketAdded(symbol, maxLeverage);
    }

    /**
     * @dev Check if user has any open positions
     */
    function _hasOpenPositions(address user) internal view returns (bool) {
        for (uint256 i = 0; i < marketSymbols.length; i++) {
            if (positions[user][marketSymbols[i]].isOpen) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Calculate user's total position exposure across all markets
     */
    function _getUserTotalExposure(address user) internal view returns (uint256) {
        uint256 totalExposure = 0;
        for (uint256 i = 0; i < marketSymbols.length; i++) {
            if (positions[user][marketSymbols[i]].isOpen) {
                totalExposure += positions[user][marketSymbols[i]].sizeUSD;
            }
        }
        return totalExposure;
    }

    // Getters
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function getMarketSymbols() external view returns (string[] memory) {
        return marketSymbols;
    }

    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    function getAllUsersCount() external view returns (uint256) {
        return allUsers.length;
    }

    /**
     * @dev Get market information
     */
    function getMarket(string memory symbol) 
        external 
        view 
        returns (PerpsStructs.Market memory) 
    {
        return markets[symbol];
    }

    /**
     * @dev Get user's remaining capacity for new positions
     */
    function getUserRemainingCapacity(address user) external view returns (uint256) {
        uint256 currentExposure = _getUserTotalExposure(user);
        uint256 maxExposure = 300_000_000; // $300 max exposure
        
        if (currentExposure >= maxExposure) {
            return 0;
        }
        return maxExposure - currentExposure;
    }

    /**
     * @dev Get user limits and current usage
     */
    function getUserLimits(address user) 
        external 
        view 
        returns (
            uint256 maxBalance,
            uint256 currentBalance, 
            uint256 maxExposure,
            uint256 currentExposure,
            uint256 remainingCapacity
        ) 
    {
        return (
            100_000_000, // $100 max balance
            balances[user],
            300_000_000, // $300 max exposure  
            _getUserTotalExposure(user),
            this.getUserRemainingCapacity(user)
        );
    }
}