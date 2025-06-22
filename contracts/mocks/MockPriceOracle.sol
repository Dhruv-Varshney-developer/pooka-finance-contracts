contract MockPriceOracle {
    function getPrice(string memory pair) external view returns (uint256, uint256) {
        if (keccak256(bytes(pair)) == keccak256(bytes("BTC/USD"))) {
            return (8000000000000, block.timestamp); // $80,000 with 8 decimals
        }
        if (keccak256(bytes(pair)) == keccak256(bytes("ETH/USD"))) {
            return (300000000000, block.timestamp); // $3,000 with 8 decimals
        }
        revert("Price feed not set");
    }
}