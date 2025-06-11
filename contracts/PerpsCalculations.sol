// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PerpsStructs.sol";
import "./PerpsFeeManager.sol";

contract PerpsCalculations {
    PerpsFeeManager public feeManager;

    constructor(address _feeManager) {
        feeManager = PerpsFeeManager(_feeManager);
    }

    // Calculate unrealized P&L in wei
    function calculatePnL(
        PerpsStructs.Position memory position,
        uint256 currentPrice
    ) external pure returns (int256) {
        if (!position.isOpen) return 0;

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

    // Calculate liquidation price
    function calculateLiquidationPrice(
        PerpsStructs.Position memory position,
        PerpsStructs.Market memory market
    ) external view returns (uint256) {
        if (!position.isOpen) return 0;

        // Include holding fees in liquidation calculation
        uint256 holdingFees = feeManager.calculateHoldingFee(position);
        uint256 maintenanceMargin = (position.collateral *
            market.maintenanceMargin) / 10000;

        // Available collateral = collateral - maintenance margin - holding fees
        if (position.collateral <= maintenanceMargin + holdingFees) {
            return position.entryPrice; // Liquidatable at current price
        }

        uint256 availableCollateral = position.collateral -
            maintenanceMargin -
            holdingFees;
        uint256 maxLossUSD = (availableCollateral * position.entryPrice) / 1e18;
        uint256 priceChange = (maxLossUSD * position.entryPrice) /
            position.size;

        if (position.isLong) {
            return
                position.entryPrice > priceChange
                    ? position.entryPrice - priceChange
                    : 0;
        } else {
            return position.entryPrice + priceChange;
        }
    }

    // Check if position can be liquidated
    function canLiquidate(
        PerpsStructs.Position memory position,
        PerpsStructs.Market memory market,
        uint256 currentPrice
    ) external view returns (bool) {
        if (!position.isOpen) return false;

        int256 pnl = this.calculatePnL(position, currentPrice);
        uint256 holdingFees = feeManager.calculateHoldingFee(position);

        // Current value = collateral + PnL - holding fees
        int256 currentValue = int256(position.collateral) +
            pnl -
            int256(holdingFees);
        int256 maintenanceMargin = int256(
            (position.collateral * market.maintenanceMargin) / 10000
        );

        return currentValue <= maintenanceMargin;
    }
}
