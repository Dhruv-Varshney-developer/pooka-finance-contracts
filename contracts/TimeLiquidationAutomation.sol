// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Perps.sol";

/**
 * @title TimeLiquidationAutomation  
 * @dev Time-based automation - every 4 hours for holding fees
 */
contract TimeLiquidationAutomation {
    Perps public perpsContract;
    uint256 public lastRun;
    address public owner;
    
    event AutoLiquidationExecuted(uint256 positionsLiquidated, uint256 timestamp);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor(address _perpsContract) {
        perpsContract = Perps(_perpsContract);
        lastRun = block.timestamp;
        owner = msg.sender;
    }
    
    function checkUpkeep(bytes calldata) 
        external 
        view 
        returns (bool upkeepNeeded, bytes memory) 
    {
        upkeepNeeded = (block.timestamp - lastRun) >= 4 hours;
        return (upkeepNeeded, "");
    }
    
    function performUpkeep(bytes calldata) external {
        require((block.timestamp - lastRun) >= 4 hours, "Too soon");
        
        uint256 liquidated = perpsContract.liquidatePositions();
        lastRun = block.timestamp;
        
        emit AutoLiquidationExecuted(liquidated, block.timestamp);
    }
    
    // Emergency functions
    function updatePerpsContract(address _newPerps) external onlyOwner {
        perpsContract = Perps(_newPerps);
    }
    
    function forceRun() external onlyOwner {
        uint256 liquidated = perpsContract.liquidatePositions();
        lastRun = block.timestamp;
        emit AutoLiquidationExecuted(liquidated, block.timestamp);
    }
}
