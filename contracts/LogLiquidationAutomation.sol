// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Perps.sol";

/**
 * @title LogLiquidationAutomation
 * @dev Log-based automation - triggers on position opens/closes
 */
contract LogLiquidationAutomation {
    Perps public perpsContract;
    uint256 public lastRun;
    address public owner;

    event LogTriggeredLiquidation(
        uint256 positionsLiquidated,
        uint256 timestamp
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address _perpsContract) {
        perpsContract = Perps(_perpsContract);
        owner = msg.sender;
    }

    /**
     * @dev Check if liquidation needed based on position events
     */
    function checkLog(Log calldata log, bytes memory)
        external
        pure
        returns (bool upkeepNeeded, bytes memory)
    {
        // Only trigger on position opens/closes (when fresh prices are fetched)
        bytes32 positionOpened = keccak256(
            "PositionOpened(address,string,uint256,uint256,uint256,bool,uint256)"
        );
        bytes32 positionClosed = keccak256(
            "PositionClosed(address,string,int256,uint256)"
        );

        return (
            log.topics[0] == positionOpened || log.topics[0] == positionClosed,
            ""
        );
    }

    /**
     * @dev Perform liquidations after position activity
     */
    function performUpkeep(bytes calldata) external {
        // Rate limit - max once per minute
        require(block.timestamp > lastRun + 60, "Too frequent");

        uint256 liquidated = perpsContract.liquidatePositions();
        lastRun = block.timestamp;

        emit LogTriggeredLiquidation(liquidated, block.timestamp);
    }

    // Emergency functions
    function updatePerpsContract(address _newPerps) external onlyOwner {
        perpsContract = Perps(_newPerps);
    }

    function forceRun() external onlyOwner {
        uint256 liquidated = perpsContract.liquidatePositions();
        lastRun = block.timestamp;
        emit LogTriggeredLiquidation(liquidated, block.timestamp);
    }
}

// Log struct for Chainlink Log Trigger
struct Log {
    uint256 index;
    uint256 timestamp;
    bytes32 txHash;
    uint256 blockNumber;
    bytes32 blockHash;
    address source;
    bytes32[] topics;
    bytes data;
}
