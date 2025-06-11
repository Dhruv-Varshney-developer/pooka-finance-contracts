// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PerpsStructs.sol";

contract PerpsFeeManager {
    using PerpsStructs for PerpsStructs.Position;
    
    // Fee constants
    uint256 public constant HOLDING_FEE_RATE = 1; // 0.01% in basis points
    uint256 public constant FEE_INTERVAL = 1 days; // Daily fee
    uint256 public constant OPENING_FEE_BPS = 10; // 0.1% opening fee
    uint256 public constant CLOSING_FEE_BPS = 10; // 0.1% closing fee
    
    address public owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // Calculate holding fees for a position
    function calculateHoldingFee(PerpsStructs.Position memory position) 
        external view returns (uint256) 
    {
        if (!position.isOpen) return 0;
        
        uint256 timeHeld = block.timestamp - position.lastFeeTime;
        uint256 periodsHeld = timeHeld / FEE_INTERVAL;
        
        return (position.collateral * HOLDING_FEE_RATE * periodsHeld) / 10000;
    }
    
    // Calculate opening fee
    function calculateOpeningFee(uint256 collateralAmount) 
        external pure returns (uint256) 
    {
        return (collateralAmount * OPENING_FEE_BPS) / 10000;
    }
    
    // Calculate closing fee
    function calculateClosingFee(uint256 collateralAmount) 
        external pure returns (uint256) 
    {
        return (collateralAmount * CLOSING_FEE_BPS) / 10000;
    }
    
}