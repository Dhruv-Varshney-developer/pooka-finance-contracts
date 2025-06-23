// SPDX-License-Identifier: MIT
// TODO: Add ETH support
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrossChainManager
 * @dev Handles cross-chain USDC transfers for perps platform
 * ONLY SUPPORTS: USDC (what CCIP supports!)
 * Sepolia → AVAX only (AVAX users deposit directly to PoolManager)
 * Deployed on both Sepolia and AVAX Fuji
 */
contract CrossChainManager is CCIPReceiver, Ownable {
    IRouterClient private immutable router;
    IERC20 private immutable linkToken;

    // ONLY supported token: USDC
    IERC20 public usdcToken;

    // Pool Manager address (only set on AVAX)
    address public poolManager;

    // Chain selectors
    uint64 public constant AVAX_FUJI_CHAIN = 14767482510784806043;
    uint64 public constant SEPOLIA_CHAIN = 16015286601757825753;

    // Current chain selector
    uint64 public immutable currentChain;

    event TokensSent(
        address indexed user,
        address token,
        uint256 amount,
        uint64 targetChain
    );
    event TokensReceived(address indexed user, address token, uint256 amount);

    constructor(
        address _router,
        address _linkToken,
        address _usdcToken,
        uint64 _currentChain
    ) CCIPReceiver(_router) Ownable() {
        router = IRouterClient(_router);
        linkToken = IERC20(_linkToken);
        usdcToken = IERC20(_usdcToken);
        currentChain = _currentChain;
    }

    /**
     * @dev User deposits USDC to be sent cross-chain from Sepolia to AVAX
     * @param token Token address (ONLY USDC supported!)
     * @param amount Token amount
     */
    function depositAndSend(address token, uint256 amount) external {
        require(currentChain == SEPOLIA_CHAIN, "Only call on Sepolia");
        require(token == address(usdcToken), "Only USDC supported for cross-chain");
        require(amount > 0, "Amount must be > 0");

        // Transfer USDC from user
        usdcToken.transferFrom(msg.sender, address(this), amount);

        // Send USDC cross-chain
        _sendTokensCrossChain(msg.sender, token, amount);
    }

    /**
     * @dev Internal function to send USDC cross-chain via CCIP
     */
    function _sendTokensCrossChain(
        address user,
        address token,
        uint256 amount
    ) internal {
        // Prepare USDC transfer
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: token,
            amount: amount
        });

        // Approve CCIP router to spend USDC
        IERC20(token).approve(address(router), amount);

        // Create CCIP message
        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)), // Same contract on AVAX
            data: abi.encode(user, token, amount), // User and token info
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 300_000})
            ),
            feeToken: address(linkToken)
        });

        // Calculate and pay CCIP fees in LINK
        uint256 fees = router.getFee(AVAX_FUJI_CHAIN, ccipMessage);
        require(linkToken.balanceOf(address(this)) >= fees, "Insufficient LINK for fees");
        linkToken.approve(address(router), fees);

        // Send USDC cross-chain
        router.ccipSend(AVAX_FUJI_CHAIN, ccipMessage);

        emit TokensSent(user, token, amount, AVAX_FUJI_CHAIN);
    }

    /**
     * @dev Receive CCIP message on AVAX chain
     */
    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        override
    {
        require(currentChain == AVAX_FUJI_CHAIN, "Only receive on AVAX");
        require(poolManager != address(0), "Pool manager not set");

        // Decode user and token info
        (address user, address originalToken, uint256 amount) = abi.decode(
            message.data,
            (address, address, uint256)
        );

        // Handle received USDC
        if (message.destTokenAmounts.length > 0) {
            Client.EVMTokenAmount memory tokenAmount = message.destTokenAmounts[0];
            
            require(tokenAmount.token == address(usdcToken), "Only USDC expected");

            // Approve and forward USDC to pool manager
            IERC20(tokenAmount.token).approve(poolManager, tokenAmount.amount);
            IPoolManager(poolManager).handleDeposit(
                user,
                tokenAmount.token,
                tokenAmount.amount
            );

            emit TokensReceived(user, tokenAmount.token, tokenAmount.amount);
        }
    }

    /**
     * @dev Set pool manager address (only on AVAX)
     */
    function setPoolManager(address _poolManager) external onlyOwner {
        require(currentChain == AVAX_FUJI_CHAIN, "Only on AVAX");
        poolManager = _poolManager;
    }

    /**
     * @dev Fund contract with LINK for CCIP fees
     */
    function fundWithLink(uint256 amount) external onlyOwner {
        linkToken.transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Emergency USDC withdrawal
     */
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    /**
     * @dev Get LINK balance for fees
     */
    function getLinkBalance() external view returns (uint256) {
        return linkToken.balanceOf(address(this));
    }
}

interface IPoolManager {
    function handleDeposit(
        address user,
        address token,
        uint256 amount
    ) external;
}