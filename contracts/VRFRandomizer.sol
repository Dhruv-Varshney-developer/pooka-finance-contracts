// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * @title VRFRandomizer
 * @dev VRF contract for generating randomness
 */
contract VRFRandomizer is VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface private vrfCoordinator;
    uint64 private subscriptionId;
    bytes32 private keyHash;
    uint32 private callbackGasLimit = 100000;
    uint16 private requestConfirmations = 3;

    // Current randomness
    uint256 public currentRandomness;
    uint256 public lastUpdateTime;

    // Simple access control
    address public owner;
    mapping(address => bool) public authorizedCallers;

    event RandomnessUpdated(uint256 randomness, uint256 timestamp);
    event RandomnessRequested(uint256 requestId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorizedCallers[msg.sender] || msg.sender == owner,
            "Not authorized"
        );
        _;
    }

    constructor(
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _keyHash
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        owner = msg.sender;
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;

        // Initialize with block-based randomness
        currentRandomness = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    block.number
                )
            )
        );
        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Request fresh randomness from VRF
     */
    function requestRandomness()
        external
        onlyAuthorized
        returns (uint256 requestId)
    {
        requestId = vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1 // numWords
        );

        emit RandomnessRequested(requestId);
        return requestId;
    }

    /**
     * @dev VRF callback - receives randomness
     */
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        currentRandomness = randomWords[0];
        lastUpdateTime = block.timestamp;
        emit RandomnessUpdated(currentRandomness, block.timestamp);
    }

    /**
     * @dev Get current randomness (public view - no auth needed)
     */
    function getRandomness() external view returns (uint256) {
        return currentRandomness;
    }

    /**
     * @dev Shuffle array using current randomness (public view - no auth needed)
     */
    function shuffleAddresses(
        address[] memory array
    ) external view returns (address[] memory) {
        uint256 randomness = currentRandomness;

        for (uint256 i = array.length - 1; i > 0; i--) {
            uint256 j = randomness % (i + 1);

            // Swap array[i] and array[j]
            address temp = array[i];
            array[i] = array[j];
            array[j] = temp;

            // Update randomness for next iteration
            randomness = uint256(keccak256(abi.encodePacked(randomness, i)));
        }

        return array;
    }

    /**
     * @dev Add authorized caller
     */
    function addAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = true;
    }

    /**
     * @dev Update subscription ID (in case you need to switch)
     */
    function updateSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }
}
