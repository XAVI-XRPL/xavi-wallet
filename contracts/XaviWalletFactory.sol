// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./XaviWallet.sol";

/**
 * @title XaviWalletFactory
 * @author Agent Xavi — Autonomous Builder on XRPL EVM
 * @notice Factory for deploying secure AI agent wallets
 * @dev One factory serves the entire ecosystem. Pausable for emergencies.
 */
contract XaviWalletFactory is Ownable, Pausable {
    
    // ============ Events ============
    
    event WalletCreated(
        address indexed wallet,
        address indexed guardian,
        string agentName,
        uint256 dailyLimit,
        uint256 perTxLimit,
        uint256 walletIndex
    );
    
    // ============ State Variables ============
    
    /// @notice All deployed wallets
    address[] public allWallets;
    
    /// @notice Wallets by guardian address
    mapping(address => address[]) public walletsByGuardian;
    
    /// @notice Registry contract address
    address public registry;
    
    // ============ Constructor ============
    
    constructor() Ownable(msg.sender) {}
    
    // ============ Factory Functions ============
    
    /// @notice Deploy a new agent wallet
    /// @param guardian Human controller address (can freeze/recover/configure)
    /// @param agentName Identifier for the agent (e.g., "Xavi", "Sentinel")
    /// @param dailyLimit Maximum XRP the agent can spend per 24 hours
    /// @param perTxLimit Maximum XRP per single transaction
    /// @return wallet Address of the newly deployed wallet
    function createWallet(
        address guardian,
        string calldata agentName,
        uint256 dailyLimit,
        uint256 perTxLimit
    ) external whenNotPaused returns (address wallet) {
        require(guardian != address(0), "XaviWalletFactory: zero guardian");
        require(bytes(agentName).length > 0, "XaviWalletFactory: empty name");
        require(dailyLimit > 0, "XaviWalletFactory: zero daily limit");
        require(perTxLimit > 0, "XaviWalletFactory: zero per-tx limit");
        require(perTxLimit <= dailyLimit, "XaviWalletFactory: per-tx > daily");
        
        XaviWallet w = new XaviWallet(guardian, agentName, dailyLimit, perTxLimit);
        wallet = address(w);
        
        allWallets.push(wallet);
        walletsByGuardian[guardian].push(wallet);
        
        emit WalletCreated(
            wallet,
            guardian,
            agentName,
            dailyLimit,
            perTxLimit,
            allWallets.length - 1
        );
    }
    
    // ============ View Functions ============
    
    /// @notice Total number of wallets created
    function totalWallets() external view returns (uint256) {
        return allWallets.length;
    }
    
    /// @notice Get all wallets for a guardian
    function getWalletsByGuardian(address guardian) external view returns (address[] memory) {
        return walletsByGuardian[guardian];
    }
    
    /// @notice Get wallet count for a guardian
    function getWalletCountByGuardian(address guardian) external view returns (uint256) {
        return walletsByGuardian[guardian].length;
    }
    
    /// @notice Get all wallets (paginated)
    function getWallets(uint256 offset, uint256 limit) external view returns (address[] memory) {
        uint256 len = allWallets.length;
        if (offset >= len) {
            return new address[](0);
        }
        
        uint256 end = offset + limit;
        if (end > len) {
            end = len;
        }
        
        address[] memory wallets = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            wallets[i - offset] = allWallets[i];
        }
        
        return wallets;
    }
    
    // ============ Admin Functions ============
    
    /// @notice Set registry contract
    function setRegistry(address _registry) external onlyOwner {
        registry = _registry;
    }
    
    /// @notice Pause wallet creation (emergency)
    function pause() external onlyOwner {
        _pause();
    }
    
    /// @notice Unpause wallet creation
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /// @notice Prevent accidental renounce
    function renounceOwnership() public pure override {
        revert("XaviWalletFactory: cannot renounce");
    }
}
