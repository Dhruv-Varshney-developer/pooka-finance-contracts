// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrossChainManager
 * @dev Handles cross-chain token transfers for perps platform
 * Sepolia → AVAX only (AVAX users deposit directly to PoolManager)
 * Deployed on both Sepolia and AVAX Fuji
 */
contract CrossChainManager is CCIPReceiver, Ownable {
    IRouterClient private immutable router;
    IERC20 private immutable linkToken;

    // Supported tokens on each chain
    IERC20 public usdcToken;

    // Pool Manager address (only set on AVAX)
    address public poolManager;

    // Chain selectors
    uint64 public constant AVAX_FUJI_CHAIN = 14767482510784806043;
    uint64 public constant SEPOLIA_CHAIN = 16015286601757825753;

    // Current chain selector
    uint64 public immutable currentChain;

    IERC20 public wethToken;

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
        address _wethToken,
        uint64 _currentChain
    ) CCIPReceiver(_router) Ownable() {
        router = IRouterClient(_router);
        linkToken = IERC20(_linkToken);
        usdcToken = IERC20(_usdcToken);
        wethToken = IERC20(_wethToken);

        currentChain = _currentChain;
    }

    /**
     * @dev User deposits tokens to be sent cross-chain from Sepolia to AVAX
     * @param token Token address (use address(0) for native ETH)
     * @param amount Token amount
     */
    function depositAndSend(address token, uint256 amount) external payable {
        require(currentChain == SEPOLIA_CHAIN, "Only call on Sepolia");

        if (token == address(0)) {
            // Native ETH deposit
            require(msg.value > 0, "Send ETH");
            IWETH(address(wethToken)).deposit{value: msg.value}();

            token = address(wethToken); // Send WETH instead
            amount = msg.value;
        }
        // Handle WETH/USDC/LINK
        require(
            token == address(usdcToken) ||
                token == address(linkToken) ||
                token == address(wethToken),
            "Unsupported token"
        );
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        _sendTokensCrossChain(msg.sender, token, amount, 0);
    }

    /**
     * @dev Internal function to send tokens cross-chain via CCIP
     */
    function _sendTokensCrossChain(
        address user,
        address token,
        uint256 amount,
        uint256 nativeAmount
    ) internal {
        Client.EVMTokenAmount[] memory tokenAmounts;

        if (token == address(0)) {
            // Native token transfer
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: address(0), // Native token
                amount: nativeAmount
            });
        } else {
            // ERC20 token transfer
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: token,
                amount: amount
            });

            // Approve CCIP router to spend tokens
            IERC20(token).approve(address(router), amount);
        }

        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)), // Same contract on AVAX
            data: abi.encode(user, token, amount), // User and token info
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 300_000})
            ),
            feeToken: address(linkToken)
        });

        // Calculate and pay CCIP fees
        uint256 fees = router.getFee(AVAX_FUJI_CHAIN, ccipMessage);
        linkToken.transferFrom(msg.sender, address(this), fees);
        linkToken.approve(address(router), fees);

        // Send message
        router.ccipSend{value: nativeAmount}(AVAX_FUJI_CHAIN, ccipMessage);

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

        // Handle received tokens
        if (message.destTokenAmounts.length > 0) {
            Client.EVMTokenAmount memory tokenAmount = message.destTokenAmounts[
                0
            ];

            if (tokenAmount.token == address(0)) {
                // Native AVAX received - forward to pool manager
                IPoolManager(poolManager).handleDeposit{
                    value: tokenAmount.amount
                }(user, address(0), tokenAmount.amount);
            } else {
                // ERC20 token received - approve and forward to pool manager
                IERC20(tokenAmount.token).approve(
                    poolManager,
                    tokenAmount.amount
                );
                IPoolManager(poolManager).handleDeposit(
                    user,
                    tokenAmount.token,
                    tokenAmount.amount
                );
            }

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
     * @dev Emergency native token withdrawal
     */
    function withdrawNative(uint256 amount) external onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    /**
     * @dev Emergency ERC20 token withdrawal
     */
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    receive() external payable {}
}

interface IPoolManager {
    function handleDeposit(
        address user,
        address token,
        uint256 amount
    ) external payable;
}

interface IWETH {
    function deposit() external payable;
}
