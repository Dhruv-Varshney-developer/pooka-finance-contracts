// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/PriceOracle.sol";
import "./Perps.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/**
 * @title PoolManager
 * @dev Converts tokens to USDC and deposits to Perps platform
 * Two deposit paths:
 * 1. Cross-chain: CrossChainManager → _ccipReceive() → _processDeposit()
 * 2. Direct: AVAX users → depositDirect() → _processDeposit()
 * Deployed only on AVAX Fuji
 */
contract PoolManager is CCIPReceiver, Ownable {
    PriceOracle public priceOracle;
    Perps public perpsContract;

    address public constant FUJI_CCIP_ROUTER =
        0xF694E193200268f9a4868e4Aa017A0118C9a8177; // CCIP Router address for AVAX Fuji

    // Supported tokens on AVAX
    IERC20 public usdcToken; // 6 decimals
    IERC20 public linkToken; // 18 decimals

    // Track deposited amounts per user (in original tokens for accounting)
    mapping(address => mapping(address => uint256)) public userDeposits;

    event TokensConverted(
        address indexed user,
        address indexed fromToken,
        uint256 fromAmount,
        uint256 usdcAmount
    );
    event DepositedToPerps(address indexed user, uint256 usdcAmount);
    event OwnerWithdraw(address indexed token, uint256 amount, address owner);

    constructor(
        address _priceOracle,
        address _perpsContract,
        address _usdcToken,
        address _linkToken
    ) CCIPReceiver(FUJI_CCIP_ROUTER) Ownable() {
        priceOracle = PriceOracle(_priceOracle);
        perpsContract = Perps(_perpsContract);
        usdcToken = IERC20(_usdcToken);
        linkToken = IERC20(_linkToken);
    }

    /**
     * @dev Direct deposit for AVAX native users (AVAX/LINK/USDC)
     * @param token Token address (address(0) for native AVAX)
     * @param amount Token amount
     */
    function depositDirect(address token, uint256 amount) external payable {
        _processDeposit(msg.sender, token, amount);
    }

    /**
     * @dev CCIP message receiver - handles cross-chain USDC deposits
     */
    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        override
    {
        // Decode user info
        (address user, address originalToken, uint256 amount) = abi.decode(
            message.data,
            (address, address, uint256)
        );

        // Handle received USDC tokens
        if (message.destTokenAmounts.length > 0) {
            Client.EVMTokenAmount memory tokenAmount = message.destTokenAmounts[
                0
            ];
            require(
                tokenAmount.token == address(usdcToken),
                "Only USDC expected"
            );

            // Call _processDeposit directly (bypass handleDeposit)
            _processDeposit(user, tokenAmount.token, tokenAmount.amount);

            emit TokensConverted(
                user,
                originalToken,
                amount,
                tokenAmount.amount
            );
        }
    }

    /**
     * @dev Internal function to process deposits (both cross-chain and direct)
     * @param user User address
     * @param token Token address (address(0) for native AVAX)
     * @param amount Token amount
     */
    function _processDeposit(
        address user,
        address token,
        uint256 amount
    ) internal {
        require(amount > 0, "Amount must be > 0");

        uint256 usdcAmount;

        if (token == address(0)) {
            // Native AVAX - convert to USDC
            require(msg.value == amount, "AVAX amount mismatch");
            usdcAmount = _convertAvaxToUsdc(amount);
            userDeposits[user][token] += amount;
        } else if (token == address(usdcToken)) {
            // ONLY cross-chain CCIP USDC should reach here
            // Tokens already in contract from CCIP transfer
            usdcAmount = amount;
            userDeposits[user][token] += amount;
        } else if (token == address(linkToken)) {
            // LINK token - convert to USDC

            // Direct deposit - transfer from user
            linkToken.transferFrom(msg.sender, address(this), amount);

            usdcAmount = _convertLinkToUsdc(amount);
            userDeposits[user][token] += amount;
        } else {
            revert("Unsupported token");
        }

        require(usdcAmount > 0, "Conversion resulted in 0 USDC");

        // Approve Perps contract to spend converted USDC
        usdcToken.approve(address(perpsContract), usdcAmount);

        // Deposit USDC to Perps contract on behalf of user
        _depositToPerps(user, usdcAmount);

        emit TokensConverted(user, token, amount, usdcAmount);
        emit DepositedToPerps(user, usdcAmount);
    }

    /**
     * @dev Convert native AVAX to USDC using price oracle
     */
    function _convertAvaxToUsdc(uint256 avaxAmount)
        internal
        view
        returns (uint256)
    {
        // Get AVAX price from oracle (8 decimals)
        (uint256 avaxPriceUSD, ) = priceOracle.getPrice("AVAX/USD");

        // Convert AVAX (18 decimals) to USD value
        // avaxAmount * price / 1e18 = USD value (8 decimals from price)
        uint256 usdValue = (avaxAmount * avaxPriceUSD) / 1e18;

        // Convert to USDC (6 decimals)
        // USD value (8 decimals) -> USDC (6 decimals)
        return usdValue / 1e2;
    }

    /**
     * @dev Convert LINK tokens to USDC using price oracle
     */
    function _convertLinkToUsdc(uint256 linkAmount)
        internal
        view
        returns (uint256)
    {
        // Get LINK price from oracle (8 decimals)
        (uint256 linkPriceUSD, ) = priceOracle.getPrice("LINK/USD");

        // Convert LINK (18 decimals) to USD value
        uint256 usdValue = (linkAmount * linkPriceUSD) / 1e18;

        // Convert to USDC (6 decimals)
        return usdValue / 1e2;
    }

    /**
     * @dev Deposit USDC to Perps contract on behalf of user
     */
    function _depositToPerps(address user, uint256 usdcAmount) internal {
        // Approve Perps contract to spend USDC
        usdcToken.approve(address(perpsContract), usdcAmount);

        // Call new depositUSDCForUser function
        perpsContract.depositUSDCForUser(user, usdcAmount);
    }

    /**
     * @dev Get user's deposit history
     */
    function getUserDeposits(address user, address token)
        external
        view
        returns (uint256)
    {
        return userDeposits[user][token];
    }

    /**
     * @dev Preview conversion rates for any token
     */
    function previewConversion(address token, uint256 amount)
        external
        view
        returns (uint256 usdcAmount)
    {
        if (token == address(0)) {
            return _convertAvaxToUsdc(amount);
        } else if (token == address(usdcToken)) {
            return amount;
        } else if (token == address(linkToken)) {
            return _convertLinkToUsdc(amount);
        }
        return 0;
    }

    /**
     * @dev Preview conversion for direct deposits (convenience function)
     */
    function previewDirectDeposit(address token, uint256 amount)
        external
        view
        returns (uint256 usdcAmount, string memory tokenName)
    {
        usdcAmount = this.previewConversion(token, amount);

        if (token == address(0)) {
            tokenName = "AVAX";
        } else if (token == address(usdcToken)) {
            tokenName = "USDC";
        } else if (token == address(linkToken)) {
            tokenName = "LINK";
        } else {
            tokenName = "UNSUPPORTED";
        }
    }

    /**
     * @dev Get current token prices in USD
     */
    function getTokenPrices()
        external
        view
        returns (uint256 avaxPrice, uint256 linkPrice)
    {
        (avaxPrice, ) = priceOracle.getPrice("AVAX/USD");
        (linkPrice, ) = priceOracle.getPrice("LINK/USD");
    }

    /**
     * @dev Emergency function to update contracts
     */
    function updateContracts(address _priceOracle, address _perpsContract)
        external
        onlyOwner
    {
        if (_priceOracle != address(0)) priceOracle = PriceOracle(_priceOracle);
        if (_perpsContract != address(0)) perpsContract = Perps(_perpsContract);
    }

    receive() external payable {}

    /**
     * @dev Owner withdraw ERC20 tokens only
     */
    function ownerWithdrawToken(address token, uint256 amount)
        external
        onlyOwner
    {
        require(token != address(0), "Use withdrawAVAX for native AVAX");
        IERC20 tokenContract = IERC20(token);
        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "Insufficient token balance"
        );
        tokenContract.transfer(owner(), amount);

        emit OwnerWithdraw(token, amount, owner());
    }

    /**
     * @dev Withdraw all AVAX (convenience function)
     */
    function withdrawAllAVAX() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No AVAX to withdraw");
        payable(owner()).transfer(balance);

        emit OwnerWithdraw(address(0), balance, owner());
    }
}
