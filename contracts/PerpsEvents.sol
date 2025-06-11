// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PerpsEvents {
    event PositionOpened(
        address indexed user,
        string symbol,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        bool isLong,
        uint256 leverage
    );
    
    event PositionClosed(
        address indexed user, 
        string symbol, 
        int256 pnl, 
        uint256 holdingFees
    );

    
    event MarketAdded(string symbol, uint256 maxLeverage);
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
}