// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PerpsStructs {
    /**
     * @dev Position struct - all USD/USDC based
     * @notice All values are in their respective decimals:
     * - USDC amounts: 6 decimals (e.g., 1000000 = $1.00)
     * - USD sizes: 6 decimals (e.g., 50000000 = $50.00)
     * - Prices: 8 decimals from oracle (e.g., 10000000000 = $100.00)
     */
    struct Position {
        uint256 sizeUSD;        // Position size in USD (6 decimals)
        uint256 collateralUSDC; // Collateral in USDC (6 decimals)
        uint256 entryPrice;     // Entry price (8 decimals from oracle)
        uint256 leverage;       // Leverage multiplier
        bool isLong;           // Position direction
        bool isOpen;           // Position status
        uint256 openTime;      // Opening timestamp
        uint256 lastFeeTime;   // Last fee calculation timestamp
    }

    /**
     * @dev Market configuration and tracking
     */
    struct Market {
        string symbol;              // Trading pair (e.g., "BTC/USD")
        uint256 maxLeverage;        // Maximum leverage allowed
        uint256 maintenanceMargin;  // Maintenance margin in basis points
        uint256 totalLongSizeUSD;   // Total long positions in USD (6 decimals)
        uint256 totalShortSizeUSD;  // Total short positions in USD (6 decimals)
        bool isActive;             // Market availability
    }

    /**
     * @dev Comprehensive position information for frontend
     * @notice All monetary values maintain their decimal precision:
     * - USDC: 6 decimals
     * - USD: 6 decimals  
     * - Prices: 8 decimals
     * - PnL: 6 decimals (in USDC terms)
     */
    struct PositionInfo {
        // Core position data
        uint256 sizeUSD;           // Position size in USD (6 decimals)
        uint256 collateralUSDC;    // Collateral amount in USDC (6 decimals)
        uint256 entryPrice;        // Entry price (8 decimals)
        uint256 leverage;          // Leverage used
        bool isLong;              // Position direction
        bool isOpen;              // Position status
        
        // Real-time computed data
        uint256 currentPrice;      // Current market price (8 decimals)
        uint256 liquidationPrice;  // Liquidation trigger price (8 decimals)
        int256 unrealizedPnL;     // Unrealized PnL in USDC (6 decimals)
        uint256 accruedFees;      // Accrued holding fees in USDC (6 decimals)
        int256 netPnL;            // Net PnL after fees in USDC (6 decimals)
        bool canBeLiquidated;     // Liquidation eligibility
    }
}