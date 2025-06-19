// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract CrossChainManager is CCIPReceiver {
    // CCIP router for sending messages
    IRouterClient private immutable router;
    // LINK token for paying CCIP fees
    IERC20 private immutable linkToken;
    // USDC token being transferred
    IERC20 private immutable collateralToken;

    // Pool contract address (only on Avax)
    address public poolContract;
    // Chain selectors for CCIP
    uint64 public constant AVAX_CHAIN = 14767482510784806043;
    uint64 public constant SEPOLIA_CHAIN = 16015286601757825753;

    constructor(
        address _router,
        address _linkToken,
        address _collateralToken
    ) CCIPReceiver(_router) {
        router = IRouterClient(_router);
        linkToken = IERC20(_linkToken);
        collateralToken = IERC20(_collateralToken);
    }

    // Called on Sepolia when user deposits USDC
    function sendDeposit(address user, uint256 amount) external {
        // Take user's USDC
        collateralToken.transferFrom(user, address(this), amount);
        
        // Send CCIP message to Avax telling pool to front this amount
        _sendMessage(AVAX_CHAIN, true, user, amount);
    }

    // Called by Pool on Avax to send USDC back to user on Sepolia  
    function sendRefund(address user, uint256 amount) external {
        require(msg.sender == poolContract, "Only pool");
        _sendMessage(SEPOLIA_CHAIN, false, user, amount);
    }

    // Internal function to send CCIP message
    function _sendMessage(uint64 targetChain, bool isDeposit, address user, uint256 amount) internal {
        // Create CCIP message
        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)), // Send to same contract on other chain
            data: abi.encode(isDeposit, user, amount), // Pack the data
            tokenAmounts: new Client.EVMTokenAmount[](0), // No tokens, just message
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000})),
            feeToken: address(linkToken) // Pay fees in LINK
        });

        // Calculate and pay CCIP fees
        uint256 fees = router.getFee(targetChain, ccipMessage);
        linkToken.approve(address(router), fees);
        router.ccipSend(targetChain, ccipMessage);
    }

    // Receives CCIP messages from other chains
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Decode the message data
        (bool isDeposit, address user, uint256 amount) = abi.decode(message.data, (bool, address, uint256));

        if (isDeposit) {
            // On Avax: tell pool to front collateral for user
            IPool(poolContract).handleDeposit(user, amount);
        } else {
            // On Sepolia: send USDC back to user
            collateralToken.transfer(user, amount);
        }
    }

    // Set pool contract address (only needed on Avax)
    function setPoolContract(address _pool) external {
        poolContract = _pool;
    }
}

interface IPool {
    function handleDeposit(address user, uint256 amount) external;
}