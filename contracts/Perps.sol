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
    mapping(string => PerpsStructs.Market) public markets;
    mapping(address => uint256) public balances; // USDC balances (6 decimals)

    string[] public marketSymbols;
    address public owner;
    IERC20 public usdcToken;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
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
        // Initialize default markets
        _addMarket("BTC/USD", 20, 500);
        _addMarket("ETH/USD", 15, 667);
    }

    /**
     * @dev Deposit USDC collateral
     * @param usdcAmount Amount of USDC to deposit (6 decimals)
     */
    function depositUSDC(uint256 usdcAmount) external {
        require(usdcAmount > 0, "Deposit amount must be > 0");

        // Transfer USDC from user
        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);
        
        // Add to user's balance (USDC has 6 decimals)
        balances[msg.sender] += usdcAmount;

        emit Deposit(msg.sender, usdcAmount);
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
            leverage > 0 && leverage <= market.maxLeverage,
            "Invalid leverage"
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

        // Calculate final USDC amount
        int256 finalUSDCAmount = int256(position.collateralUSDC) + 
                                pnlUSDC - 
                                int256(holdingFees) - 
                                int256(closingFee);

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

        emit PositionClosed(msg.sender, symbol, pnlUSDC, holdingFees);
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

    // Getters
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function getMarketSymbols() external view returns (string[] memory) {
        return marketSymbols;
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
}