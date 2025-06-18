// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Perps.sol";

contract Pool {
    
    Perps public immutable perpsContract;
    IERC20 public immutable collateralToken;
    address public crossChainManager;
    address public owner;
    
    uint256 public totalLiquidity;
    uint256 public totalFronted;
    
    mapping(address => uint256) public liquidityProvided;
    mapping(address => uint256) public frontedAmounts; // Amount fronted per user

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyCrossChainManager() {
        require(msg.sender == crossChainManager, "Only manager");
        _;
    }

    constructor(address _perpsContract, address _collateralToken, address _crossChainManager) {
        perpsContract = Perps(_perpsContract);
        collateralToken = IERC20(_collateralToken);
        crossChainManager = _crossChainManager;
        owner = msg.sender;
    }

    // Liquidity providers deposit
    function depositLiquidity(uint256 amount) external {
        collateralToken.transferFrom(msg.sender, address(this), amount);
        liquidityProvided[msg.sender] += amount;
        totalLiquidity += amount;
    }

    // Liquidity providers withdraw
    function withdrawLiquidity(uint256 amount) external {
        require(liquidityProvided[msg.sender] >= amount, "Insufficient balance");
        require(totalLiquidity - totalFronted >= amount, "Cannot withdraw fronted liquidity");
        
        liquidityProvided[msg.sender] -= amount;
        totalLiquidity -= amount;
        collateralToken.transfer(msg.sender, amount);
    }

    // Called by CrossChainManager when deposit comes from Sepolia
    function handleDeposit(address user, uint256 amount) external onlyCrossChainManager {
        require(totalLiquidity >= totalFronted + amount, "Insufficient liquidity");
        
        frontedAmounts[user] += amount;
        totalFronted += amount;
        
        // Update user balance in Perps contract
        perpsContract.deposit{value: amount}();
        // Note: Requires modification to Perps contract to credit specific user
    }

    // User requests refund (must close all positions first)
    function requestRefund(uint256 amount) external {
        require(frontedAmounts[msg.sender] >= amount, "Insufficient fronted amount");
        require(!_userHasOpenPositions(msg.sender), "Close positions first");
        
        frontedAmounts[msg.sender] -= amount;
        totalFronted -= amount;
        
        ICrossChainManager(crossChainManager).sendRefund(msg.sender, amount);
    }

    function _userHasOpenPositions(address user) internal view returns (bool) {
        string[] memory symbols = perpsContract.getMarketSymbols();
        for (uint i = 0; i < symbols.length; i++) {
(
    , // size
    , // collateral  
    , // entryPrice
    , // leverage
    , // isLong
    bool isOpen, // isOpen
    , // openTime
      // lastFeeTime
) = perpsContract.positions(user, symbols[i]);            if (isOpen) return true;
        }
        return false;
    }

    function getAvailableLiquidity() external view returns (uint256) {
        return totalLiquidity - totalFronted;
    }
}

interface ICrossChainManager {
    function sendRefund(address user, uint256 amount) external;
}