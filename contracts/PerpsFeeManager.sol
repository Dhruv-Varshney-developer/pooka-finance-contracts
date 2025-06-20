// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PerpsStructs.sol";

/**
 * @title PerpsFeeManager
 * @dev USDC-based fee calculations for perpetual trading
 */
contract PerpsFeeManager {
    // Fee constants (in basis points)
    uint256 public constant HOLDING_FEE_RATE = 1; // 0.01% daily
    uint256 public constant FEE_INTERVAL = 1 days;
    uint256 public constant OPENING_FEE_BPS = 10; // 0.1%
    uint256 public constant CLOSING_FEE_BPS = 10; // 0.1%

    /**
     * @dev Calculate holding fees for a position
     * @param position The position to calculate fees for
     * @return Holding fees in USDC (6 decimals)
     * 
     * Formula: (collateral * daily_rate * days_held)
     * Example: $100 collateral * 0.01% * 5 days = $0.05 fees
     */
    function calculateHoldingFee(PerpsStructs.Position memory position)
        external
        view
        returns (uint256)
    {
        if (!position.isOpen) return 0;

        uint256 timeHeld = block.timestamp - position.lastFeeTime;
        uint256 periodsHeld = timeHeld / FEE_INTERVAL;

        // Calculate fee on collateral amount
        return (position.collateralUSDC * HOLDING_FEE_RATE * periodsHeld) / 10000;
    }

    /**
     * @dev Calculate opening fee
     * @param collateralUSDC Collateral amount in USDC (6 decimals)
     * @return Opening fee in USDC (6 decimals)
     * 
     * Formula: collateral * 0.1%
     * Example: $100 collateral = $0.10 opening fee
     */
    function calculateOpeningFee(uint256 collateralUSDC)
        external
        pure
        returns (uint256)
    {
        return (collateralUSDC * OPENING_FEE_BPS) / 10000;
    }

    /**
     * @dev Calculate closing fee
     * @param collateralUSDC Collateral amount in USDC (6 decimals)
     * @return Closing fee in USDC (6 decimals)
     * 
     * Formula: collateral * 0.1%
     * Example: $100 collateral = $0.10 closing fee
     */
    function calculateClosingFee(uint256 collateralUSDC)
        external
        pure
        returns (uint256)
    {
        return (collateralUSDC * CLOSING_FEE_BPS) / 10000;
    }

    /**
     * @dev Calculate total fees for a position (opening + holding + closing)
     * @param position The position to calculate total fees for
     * @return Total fees in USDC (6 decimals)
     */
    function calculateTotalFees(PerpsStructs.Position memory position)
        external
        view
        returns (uint256)
    {
        uint256 openingFee = this.calculateOpeningFee(position.collateralUSDC);
        uint256 holdingFee = this.calculateHoldingFee(position);
        uint256 closingFee = this.calculateClosingFee(position.collateralUSDC);
        
        return openingFee + holdingFee + closingFee;
    }

    /**
     * @dev Calculate estimated daily holding cost for a position
     * @param collateralUSDC Collateral amount in USDC (6 decimals)
     * @return Daily holding cost in USDC (6 decimals)
     */
    function calculateDailyHoldingCost(uint256 collateralUSDC)
        external
        pure
        returns (uint256)
    {
        return (collateralUSDC * HOLDING_FEE_RATE) / 10000;
    }
}