// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "contracts/PriceOracle.sol";
import "./PerpsStructs.sol";
import "./PerpsEvents.sol";
import "./PerpsFeeManager.sol";
import "./PerpsCalculations.sol";

/**
 * @title Perps
 * @dev Main perpetual trading contract
 */
contract Perps is PerpsEvents {
    
    // State variables
    PriceOracle public priceOracle;
    PerpsFeeManager public feeManager;
    PerpsCalculations public calculator;

    mapping(address => mapping(string => PerpsStructs.Position))
        public positions;
    mapping(string => PerpsStructs.Market) public markets;
    mapping(address => uint256) public balances;

    string[] public marketSymbols;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(
        address _priceOracle,
        address _feeManager,
        address _calculator
    ) {
        owner = msg.sender;
        priceOracle = PriceOracle(_priceOracle);
        feeManager = PerpsFeeManager(_feeManager);
        calculator = PerpsCalculations(_calculator);

        // Initialize default markets
        _addMarket("BTC/USD", 20, 500);
        _addMarket("ETH/USD", 15, 667);
    }

    // Deposit collateral
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be > 0");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    // Withdraw collateral
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(!_hasOpenPositions(msg.sender), "Close all positions first");

        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

    // Open position 
    function openPosition(
        string memory symbol,
        uint256 collateralAmount,
        uint256 leverage,
        bool isLong
    ) external {
        PerpsStructs.Market memory market = markets[symbol];
        require(market.isActive, "Market not active");
        require(collateralAmount > 0, "Collateral must be > 0");
        require(
            leverage > 0 && leverage <= market.maxLeverage,
            "Invalid leverage"
        );
        require(
            !positions[msg.sender][symbol].isOpen,
            "Position already exists"
        );

        // Calculate fees using fee manager
        uint256 openingFee = feeManager.calculateOpeningFee(collateralAmount);
        uint256 totalRequired = collateralAmount + openingFee;
        require(balances[msg.sender] >= totalRequired, "Insufficient balance");

        // Get current price
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);

        // Calculate position size
        uint256 positionSize = (collateralAmount * leverage * currentPrice) /
            1e18;

        // Create position
        positions[msg.sender][symbol] = PerpsStructs.Position({
            size: positionSize,
            collateral: collateralAmount,
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
            markets[symbol].totalLongSize += positionSize;
        } else {
            markets[symbol].totalShortSize += positionSize;
        }

        emit PositionOpened(
            msg.sender,
            symbol,
            positionSize,
            collateralAmount,
            currentPrice,
            isLong,
            leverage
        );
    }

    // Close position
    function closePosition(string memory symbol) external {
        PerpsStructs.Position storage position = positions[msg.sender][symbol];
        require(position.isOpen, "No open position");

        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);

        // Use modules for calculations
        uint256 holdingFees = feeManager.calculateHoldingFee(position);
        int256 pnl = calculator.calculatePnL(position, currentPrice);
        uint256 closingFee = feeManager.calculateClosingFee(
            position.collateral
        );

        // Calculate final amount
        int256 finalAmount = int256(position.collateral) +
            pnl -
            int256(holdingFees) -
            int256(closingFee);

        // Update market totals
        if (position.isLong) {
            markets[symbol].totalLongSize -= position.size;
        } else {
            markets[symbol].totalShortSize -= position.size;
        }

        position.isOpen = false;
        position.lastFeeTime = block.timestamp;

        if (finalAmount > 0) {
            balances[msg.sender] += uint256(finalAmount);
        }

        emit PositionClosed(msg.sender, symbol, pnl, holdingFees);
    }

    // Get position info 
    function getPosition(address user, string memory symbol)
        external
        view
        returns (PerpsStructs.PositionInfo memory)
    {
        PerpsStructs.Position memory position = positions[user][symbol];
        (uint256 currentPrice, ) = priceOracle.getPrice(symbol);

        int256 unrealizedPnL = calculator.calculatePnL(position, currentPrice);
        uint256 accruedFees = feeManager.calculateHoldingFee(position);

        return
            PerpsStructs.PositionInfo({
                size: position.size,
                collateral: position.collateral,
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

    function _addMarket(
        string memory symbol,
        uint256 maxLeverage,
        uint256 maintenanceMargin
    ) internal {
        markets[symbol] = PerpsStructs.Market({
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
}
