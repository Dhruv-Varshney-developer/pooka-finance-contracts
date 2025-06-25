// SPDX-License-Identifier: MIT
// TODO: Add ETH support
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrossChainManager
 * @dev Handles cross-chain USDC transfers for perps platform
 * ONLY SUPPORTS: USDC (what CCIP supports!)
 * Sends USDC to AVAX PoolManager (AVAX users deposit directly to PoolManager)
 * Deployed only on Sepolia.
 */
contract CrossChainManager is Ownable {
    IRouterClient private immutable router;
    IERC20 private immutable linkToken;

    // ONLY supported token: USDC
    IERC20 public usdcToken;

    address public immutable avaxPoolManager; // HARDCODED ADDRESSES - Set after PoolManager deployment

    uint64 public constant AVAX_FUJI_CHAIN = 14767482510784806043;

    // Current chain selector
    uint64 public immutable currentChain;

    event TokensSent(address indexed user, uint256 amount, bytes32 messageId);

    constructor(
        address _router, // Sepolia CCIP Router
        address _linkToken, // Sepolia LINK
        address _usdcToken, // Sepolia USDC
        address _avaxPoolManager // AVAX PoolManager address (deploy PM first!)
    ) Ownable() {
        router = IRouterClient(_router);
        linkToken = IERC20(_linkToken);
        usdcToken = IERC20(_usdcToken);
        avaxPoolManager = _avaxPoolManager;
    }

    /**
     * @dev User deposits USDC on Sepolia → sends to AVAX PoolManager
     * @param amount Token amount
     */
    function depositAndSend(uint256 amount)
        external
        returns (bytes32 messageId)
    {
        require(amount > 0, "Amount must be > 0");
        require(amount <= 100_000_000, "Max 100 USDC per tx"); // 6 decimals

        // Transfer USDC from user
        usdcToken.transferFrom(msg.sender, address(this), amount);

        // Send to AVAX
        messageId = _sendTokensCrossChain(
            msg.sender,
            address(usdcToken),
            amount
        );

        emit TokensSent(msg.sender, amount, messageId);
        return messageId;
    }

    /**
     * @dev Internal function to send USDC cross-chain via CCIP
     */
    function _sendTokensCrossChain(
        address user,
        address token,
        uint256 amount
    ) internal returns (bytes32 messageId) {
        // Prepare USDC transfer
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        // Approve router
        usdcToken.approve(address(router), amount);

        // Create message - SEND DIRECTLY TO POOLMANAGER
        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(avaxPoolManager), // Direct to PoolManager!
            data: abi.encode(user, token, amount),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 300_000})
            ),
            feeToken: address(linkToken)
        });

        // Pay fees and send
        uint256 fees = router.getFee(AVAX_FUJI_CHAIN, ccipMessage);
        require(
            linkToken.balanceOf(address(this)) >= fees,
            "Insufficient LINK"
        );
        linkToken.approve(address(router), fees);

        return router.ccipSend(AVAX_FUJI_CHAIN, ccipMessage);
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
