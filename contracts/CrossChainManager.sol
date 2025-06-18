// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract CrossChainManager is CCIPReceiver {
    enum MessageType {
        DEPOSIT,
        REFUND
    }

    struct Message {
        MessageType msgType;
        address user;
        uint256 amount;
    }

    IRouterClient private immutable router;
    IERC20 private immutable linkToken;
    IERC20 public immutable collateralToken;

    address public owner;
    address public poolContract;
    uint64 public avaxChainSelector;
    uint64 public sepoliaChainSelector;

    mapping(address => bool) public allowedSenders;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyPool() {
        require(msg.sender == poolContract, "Only pool");
        _;
    }

    constructor(
        address _router,
        address _linkToken,
        address _collateralToken,
        uint64 _avaxChainSelector,
        uint64 _sepoliaChainSelector
    ) CCIPReceiver(_router) {
        router = IRouterClient(_router);
        linkToken = IERC20(_linkToken);
        collateralToken = IERC20(_collateralToken);
        owner = msg.sender;
        avaxChainSelector = _avaxChainSelector;
        sepoliaChainSelector = _sepoliaChainSelector;
    }

    // Called on Sepolia when user deposits
    function sendDeposit(address user, uint256 amount) external {
        require(allowedSenders[msg.sender], "Not allowed");

        collateralToken.transferFrom(user, address(this), amount);

        _sendMessage(avaxChainSelector, MessageType.DEPOSIT, user, amount);
    }

    // Called by Pool on Avax to send refund to Sepolia
    function sendRefund(address user, uint256 amount) external onlyPool {
        _sendMessage(sepoliaChainSelector, MessageType.REFUND, user, amount);
    }

    function _sendMessage(
        uint64 targetChain,
        MessageType msgType,
        address user,
        uint256 amount
    ) internal {
        Message memory message = Message(msgType, user, amount);

        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(message),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000})
            ),
            feeToken: address(linkToken)
        });

        uint256 fees = router.getFee(targetChain, ccipMessage);
        linkToken.approve(address(router), fees);
        router.ccipSend(targetChain, ccipMessage);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        override
    {
        Message memory decoded = abi.decode(message.data, (Message));

        if (decoded.msgType == MessageType.DEPOSIT) {
            // On Avax: notify pool
            IPool(poolContract).handleDeposit(decoded.user, decoded.amount);
        } else {
            // On Sepolia: send refund to user
            collateralToken.transfer(decoded.user, decoded.amount);
        }
    }

    function setPoolContract(address _pool) external onlyOwner {
        poolContract = _pool;
    }

    function setAllowedSender(address sender, bool allowed) external onlyOwner {
        allowedSenders[sender] = allowed;
    }
}

interface IPool {
    function handleDeposit(address user, uint256 amount) external;
}
