// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PerpsStructs.sol";
import "./PerpsFeeManager.sol";

/**
 * @title PerpsCalculations
 * @dev USD/USDC-based calculations for perpetual trading
 */
contract PerpsCalculations {
    PerpsFeeManager public feeManager;

    constructor(address _feeManager) {
        feeManager = PerpsFeeManager(_feeManager);
    }

    /**
     * @dev Calculate unrealized P&L in USDC terms
     * @param position The position to calculate PnL for
     * @param currentPrice Current market price (8 decimals)
     * @return PnL in USDC (6 decimals) - positive for profit, negative for loss
     * 
     * Formula:
     * - Long: PnL = (currentPrice - entryPrice) / entryPrice * sizeUSD
     * - Short: PnL = (entryPrice - currentPrice) / entryPrice * sizeUSD
     */
    function calculatePnL(
        PerpsStructs.Position memory position,
        uint256 currentPrice
    ) external pure returns (int256) {
        if (!position.isOpen) return 0;

        require(position.entryPrice > 0, "Invalid entry price");
        require(currentPrice > 0, "Invalid current price");

        // Calculate price difference percentage (in basis points for precision)
        int256 priceDiff = int256(currentPrice) - int256(position.entryPrice);
        
        // PnL = (price change %) * position size
        // Using basis points (10000) for precision in percentage calculation
        int256 pnlUSDC = (priceDiff * int256(position.sizeUSD)) / int256(position.entryPrice);

        // Return based on position direction
        return position.isLong ? pnlUSDC : -pnlUSDC;
    }

    /**
     * @dev Calculate liquidation price for a position
     * @param position The position to calculate liquidation price for
     * @param market Market configuration
     * @return Liquidation price (8 decimals) - 0 if already liquidatable
     */
    function calculateLiquidationPrice(
        PerpsStructs.Position memory position,
        PerpsStructs.Market memory market
    ) external view returns (uint256) {
        if (!position.isOpen) return 0;

        // Calculate total fees that will be deducted
        uint256 holdingFees = feeManager.calculateHoldingFee(position);
        uint256 maintenanceMargin = (position.collateralUSDC * market.maintenanceMargin) / 10000;

        // Total deductions from collateral
        uint256 totalDeductions = maintenanceMargin + holdingFees;

        // If deductions exceed collateral, liquidatable at current price
        if (position.collateralUSDC <= totalDeductions) {
            return position.entryPrice;
        }

        // Available collateral for losses
        uint256 availableCollateral = position.collateralUSDC - totalDeductions;
        
        // Maximum loss as percentage of position size
        uint256 maxLossPercent = (availableCollateral * 10000) / position.sizeUSD;
        
        // Calculate liquidation price based on max loss percentage
        uint256 priceChangePercent = maxLossPercent;
        uint256 priceChange = (position.entryPrice * priceChangePercent) / 10000;

        if (position.isLong) {
            // Long position: liquidated when price drops
            return position.entryPrice > priceChange 
                ? position.entryPrice - priceChange 
                : 0;
        } else {
            // Short position: liquidated when price rises
            return position.entryPrice + priceChange;
        }
    }

    /**
     * @dev Check if a position can be liquidated
     * @param position The position to check
     * @param market Market configuration
     * @param currentPrice Current market price (8 decimals)
     * @return True if position can be liquidated
     */
    function canLiquidate(
        PerpsStructs.Position memory position,
        PerpsStructs.Market memory market,
        uint256 currentPrice
    ) external view returns (bool) {
        if (!position.isOpen) return false;

        // Calculate current position value
        int256 unrealizedPnL = this.calculatePnL(position, currentPrice);
        uint256 holdingFees = feeManager.calculateHoldingFee(position);

        // Current collateral value = initial collateral + PnL - fees
        int256 currentCollateralValue = int256(position.collateralUSDC) + 
                                       unrealizedPnL - 
                                       int256(holdingFees);

        // Minimum required collateral (maintenance margin)
        int256 requiredMargin = int256((position.collateralUSDC * market.maintenanceMargin) / 10000);

        // Liquidatable if current value falls below required margin
        return currentCollateralValue <= requiredMargin;
    }

    /**
     * @dev Calculate the margin ratio for a position
     * @param position The position to check
     * @param currentPrice Current market price (8 decimals)
     * @return Margin ratio in basis points (e.g., 1500 = 15%)
     */
    function calculateMarginRatio(
        PerpsStructs.Position memory position,
        uint256 currentPrice
    ) external view returns (uint256) {
        if (!position.isOpen) return 0;

        int256 unrealizedPnL = this.calculatePnL(position, currentPrice);
        uint256 holdingFees = feeManager.calculateHoldingFee(position);

        int256 currentCollateralValue = int256(position.collateralUSDC) + 
                                       unrealizedPnL - 
                                       int256(holdingFees);

        if (currentCollateralValue <= 0) return 0;

        // Margin ratio = (current collateral / position size) * 10000
        return (uint256(currentCollateralValue) * 10000) / position.sizeUSD;
    }
}