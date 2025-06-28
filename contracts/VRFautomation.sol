// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFRandomizer.sol";

contract VRFAutomation {
    VRFRandomizer public vrfRandomizer;
    uint256 public lastRandomnessRequest;

    // Request fresh randomness every 6 hours
    uint256 public constant RANDOMNESS_INTERVAL = 6 hours;

    event RandomnessRequested(uint256 requestId, uint256 timestamp);

    constructor(address _vrfRandomizer) {
        vrfRandomizer = VRFRandomizer(_vrfRandomizer);
        lastRandomnessRequest = block.timestamp;
    }

    /**
     * @dev Check if randomness refresh is needed
     */
    function checkUpkeep(
        bytes calldata
    ) external view returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded =
            (block.timestamp - lastRandomnessRequest) >= RANDOMNESS_INTERVAL;
        return (upkeepNeeded, "");
    }

    /**
     * @dev Request fresh randomness
     */
    function performUpkeep(bytes calldata) external {
        require(
            (block.timestamp - lastRandomnessRequest) >= RANDOMNESS_INTERVAL,
            "Too soon"
        );

        uint256 requestId = vrfRandomizer.requestRandomness();
        lastRandomnessRequest = block.timestamp;
        emit RandomnessRequested(requestId, block.timestamp);
    }

    /**
     * @dev Manual randomness request (emergency)
     */
    function forceRandomnessRequest() external {
        uint256 requestId = vrfRandomizer.requestRandomness();
        lastRandomnessRequest = block.timestamp;
        emit RandomnessRequested(requestId, block.timestamp);
    }
}
