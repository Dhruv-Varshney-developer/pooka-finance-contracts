// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Pool {
    // USDC token that users deposit
    IERC20 public immutable collateralToken;
    // CrossChain Manager that triggers deposits
    address public crossChainManager;
    // Perps contract where we execute trades
    address public perpsContract;
    // Platform backend that sends trade instructions
    address public platform;

    // Track which cross-chain user owns each position
    // poolAddress -> symbol -> actualUserAddress
    mapping(string => address) public positionOwners;
    
    // Track how much collateral each cross-chain user has deposited
    mapping(address => uint256) public userCollateral;
    
    // Track total collateral we're managing
    uint256 public totalManagedCollateral;

    modifier onlyPlatform() {
        require(msg.sender == platform, "Only platform");
        _;
    }

    modifier onlyCrossChainManager() {
        require(msg.sender == crossChainManager, "Only manager");
        _;
    }

    constructor(
        address _collateralToken,
        address _crossChainManager, 
        address _perpsContract,
        address _platform
    ) {
        collateralToken = IERC20(_collateralToken);
        crossChainManager = _crossChainManager;
        perpsContract = _perpsContract;
        platform = _platform;
    }

    // Called by CrossChainManager when user deposits on Sepolia
    function handleDeposit(address user, uint256 amount) external onlyCrossChainManager {
        // Track user's collateral balance
        userCollateral[user] += amount;
        totalManagedCollateral += amount;
        
        // Convert USDC to ETH and deposit to Perps contract
        uint256 ethAmount = amount; // 1:1 for hackathon simplicity
        IPerps(perpsContract).deposit{value: ethAmount}();
    }

    // Platform calls this to open position for cross-chain user
    function openPositionForUser(
        address user,
        string memory symbol,
        uint256 collateralAmount,
        uint256 leverage,
        bool isLong
    ) external onlyPlatform {
        require(userCollateral[user] >= collateralAmount, "Insufficient user collateral");
        require(positionOwners[symbol] == address(0), "Position already exists for this symbol");
        
        // Mark this position as belonging to the user
        positionOwners[symbol] = user;
        
        // Reduce user's available collateral
        userCollateral[user] -= collateralAmount;
        
        // Open position in Perps contract (Pool contract is the position holder)
        IPerps(perpsContract).openPosition(symbol, collateralAmount, leverage, isLong);
    }

    // Platform calls this to close position for cross-chain user  
    function closePositionForUser(
        address user,
        string memory symbol
    ) external onlyPlatform {
        require(positionOwners[symbol] == user, "User doesn't own this position");
        
        // Get position details before closing
        (uint256 collateral, , , , , bool isOpen, , ) = IPerps(perpsContract).positions(address(this), symbol);
        require(isOpen, "Position not open");
        
        // Close position in Perps contract
        IPerps(perpsContract).closePosition(symbol);
        
        // Get final balance after close (profit/loss applied)
        uint256 finalBalance = IPerps(perpsContract).balances(address(this));
        
        // Calculate what belongs to this user (simplified for hackathon)
        userCollateral[user] += finalBalance;
        
        // Clear position ownership
        positionOwners[symbol] = address(0);
    }

    // User requests refund back to Sepolia
    function requestRefund(address user, uint256 amount) external onlyPlatform {
        require(userCollateral[user] >= amount, "Insufficient balance");
        require(!_userHasOpenPositions(user), "User has open positions");
        
        // Reduce user's collateral
        userCollateral[user] -= amount;
        totalManagedCollateral -= amount;
        
        // Withdraw from Perps contract
        IPerps(perpsContract).withdraw(amount);
        
        // Tell CrossChainManager to send refund to Sepolia
        ICrossChainManager(crossChainManager).sendRefund(user, amount);
    }

    // Check if user has any open positions
    function _userHasOpenPositions(address user) internal view returns (bool) {
        string[] memory symbols = IPerps(perpsContract).getMarketSymbols();
        
        for (uint i = 0; i < symbols.length; i++) {
            if (positionOwners[symbols[i]] == user) {
                (, , , , , bool isOpen, , ) = IPerps(perpsContract).positions(address(this), symbols[i]);
                if (isOpen) return true;
            }
        }
        return false;
    }

    // Get user's available collateral
    function getUserCollateral(address user) external view returns (uint256) {
        return userCollateral[user];
    }

    // Get who owns a specific position
    function getPositionOwner(string memory symbol) external view returns (address) {
        return positionOwners[symbol];
    }

    // Get all positions owned by a cross-chain user
    function getUserPositions(address user) external view returns (string[] memory userSymbols) {
        string[] memory allSymbols = IPerps(perpsContract).getMarketSymbols();
        uint256 count = 0;
        
        // Count user's positions first
        for (uint i = 0; i < allSymbols.length; i++) {
            if (positionOwners[allSymbols[i]] == user) {
                count++;
            }
        }
        
        // Create array with user's symbols
        userSymbols = new string[](count);
        uint256 index = 0;
        for (uint i = 0; i < allSymbols.length; i++) {
            if (positionOwners[allSymbols[i]] == user) {
                userSymbols[index] = allSymbols[i];
                index++;
            }
        }
        
        return userSymbols;
    }

    // Get basic position details for cross-chain user
    function getUserPositionDetails(address user, string memory symbol) external view returns (
        uint256 size, uint256 collateral, uint256 entryPrice, uint256 leverage, 
        bool isLong, bool isOpen, uint256 openTime, uint256 lastFeeTime
    ) {
        require(positionOwners[symbol] == user, "User doesn't own this position");
        
        // Get position data from Perps contract (using Pool's address as holder)
        return IPerps(perpsContract).positions(address(this), symbol);
    }

    // Get rich position data with calculations for cross-chain user (same as getPosition in Perps)
    function getUserPositionInfo(address user, string memory symbol) external view returns (
        IPerps.PositionInfo memory
    ) {
        require(positionOwners[symbol] == user, "User doesn't own this position");
        
        // Get rich position data from Perps contract (using Pool's address as holder)
        // This includes currentPrice, unrealizedPnL, liquidationPrice, canBeLiquidated, etc.
        return IPerps(perpsContract).getPosition(address(this), symbol);
    }

    // Fund pool with ETH for trading (hackathon demo)
    receive() external payable {}
}

interface ICrossChainManager {
    function sendRefund(address user, uint256 amount) external;
}

interface IPerps {
    struct PositionInfo {
        uint256 size;
        uint256 collateral;
        uint256 entryPrice;
        uint256 leverage;
        bool isLong;
        bool isOpen;
        uint256 currentPrice;
        uint256 liquidationPrice;
        int256 unrealizedPnL;
        uint256 accruedFees;
        int256 netPnL;
        bool canBeLiquidated;
    }
    
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function openPosition(string memory symbol, uint256 collateralAmount, uint256 leverage, bool isLong) external;
    function closePosition(string memory symbol) external;
    function positions(address user, string memory symbol) external view returns (
        uint256 size, uint256 collateral, uint256 entryPrice, uint256 leverage, bool isLong, bool isOpen, uint256 openTime, uint256 lastFeeTime
    );
    function balances(address user) external view returns (uint256);
    function getMarketSymbols() external view returns (string[] memory);
    function getPosition(address user, string memory symbol) external view returns (PositionInfo memory);
}