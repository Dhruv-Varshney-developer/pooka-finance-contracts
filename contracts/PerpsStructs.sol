// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PerpsStructs {
    // Position struct to store user positions
    struct Position {
        uint256 size; // Position size in USD (8 decimals)
        uint256 collateral; // Collateral deposited (18 decimals ETH)
        uint256 entryPrice; // Price when position was opened (8 decimals)
        uint256 leverage; // Leverage for the position
        bool isLong; // true for long, false for short
        bool isOpen; // Position status
        uint256 openTime; // When position was opened
        uint256 lastFeeTime; // Last time holding fee was calculated
    }

    // Market data
    struct Market {
        string symbol; // e.g., "BTC/USD"
        uint256 maxLeverage; // Maximum allowed leverage
        uint256 maintenanceMargin; // Maintenance margin percentage (basis points)
        uint256 totalLongSize; // Total long positions in USD (for risk management)
        uint256 totalShortSize; // Total short positions in USD (for risk management)
        bool isActive; // Market status
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
        uint256 accruedFees;
        int256 netPnL;
        bool canBeLiquidated;
    }
}
