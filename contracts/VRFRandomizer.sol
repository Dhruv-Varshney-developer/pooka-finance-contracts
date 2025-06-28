// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title VRFRandomizer
 * @dev VRF V2Plus contract following official Chainlink pattern
 */
contract VRFRandomizer is VRFConsumerBaseV2Plus {
    uint256 public s_subscriptionId;
    bytes32 public s_keyHash;
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;

    uint256 public currentRandomness;
    uint256 public lastUpdateTime;

    address public contractOwner;
    mapping(address => bool) public authorizedCallers;

    event RandomnessUpdated(uint256 randomness, uint256 timestamp);
    event RandomnessRequested(uint256 requestId);

    modifier onlyContractOwner() {
        require(msg.sender == contractOwner, "Only owner");
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorizedCallers[msg.sender] || msg.sender == contractOwner,
            "Not authorized"
        );
        _;
    }

    constructor(
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        contractOwner = msg.sender;
        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;

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

    function requestRandomness()
        external
        onlyAuthorized
        returns (uint256 requestId)
    {
        // Use s_vrfCoordinator from base contract - EXACTLY like official example
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        emit RandomnessRequested(requestId);
        return requestId;
    }

    function fulfillRandomWords(
        uint256,
        uint256[] calldata randomWords
    ) internal override {
        currentRandomness = randomWords[0];
        lastUpdateTime = block.timestamp;
        emit RandomnessUpdated(currentRandomness, block.timestamp);
    }

    function shuffleAddresses(
        address[] memory array
    ) external view returns (address[] memory) {
         if (array.length <= 1) return array; // Handle empty/single arrays
        uint256 randomness = currentRandomness;


        for (uint256 i = array.length - 1; i > 0; i--) {
            uint256 j = randomness % (i + 1);
            (array[i], array[j]) = (array[j], array[i]);
            randomness = uint256(keccak256(abi.encodePacked(randomness, i)));
        }
        return array;
    }

    function addAuthorizedCaller(address caller) external onlyContractOwner {
        authorizedCallers[caller] = true;
    }

    function updateSubscriptionId(
        uint256 _subscriptionId
    ) external onlyContractOwner {
        s_subscriptionId = _subscriptionId;
    }
}
