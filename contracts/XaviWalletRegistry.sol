// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./XaviWallet.sol";

/**
 * @title XaviWalletRegistry
 * @author Agent Xavi — Autonomous Builder on XRPL EVM
 * @notice Public registry of all agent wallets for discovery, reputation, and ecosystem stats
 * @dev Wallets self-register after creation. Guardians verify ownership.
 */
contract XaviWalletRegistry is Ownable {
    
    // ============ Constants ============
    
    string public constant VERSION = "1.1.0";
    uint256 public constant MIN_WALLET_BALANCE = 1 ether; // 1 XRP minimum to register
    
    // ============ Structs ============
    
    struct WalletInfo {
        address wallet;
        address guardian;
        string agentName;
        string agentPlatform;       // "openclaw", "autogpt", "crewai", "custom"
        uint256 createdAt;
        uint256 totalTransactions;
        uint256 totalVolumeXRP;
        bool verified;              // guardian confirmed ownership
        bool active;                // not deregistered
    }
    
    // ============ State Variables ============
    
    /// @notice Wallet info by address
    mapping(address => WalletInfo) public walletInfo;
    
    /// @notice All registered wallet addresses
    address[] public allWallets;
    
    /// @notice Wallets by guardian
    mapping(address => address[]) public walletsByGuardian;
    
    /// @notice Wallets by platform
    mapping(string => address[]) public walletsByPlatform;
    
    /// @notice Ecosystem totals
    uint256 public totalRegisteredWallets;
    uint256 public totalVerifiedWallets;
    uint256 public totalTransactionsAllWallets;
    uint256 public totalVolumeAllWallets;
    
    /// @notice Approved platforms
    mapping(string => bool) public approvedPlatforms;
    
    // ============ Events ============
    
    event WalletRegistered(
        address indexed wallet,
        address indexed guardian,
        string agentName,
        string agentPlatform
    );
    event WalletVerified(address indexed wallet, address indexed guardian);
    event WalletDeregistered(address indexed wallet);
    event ActionRecorded(address indexed wallet, uint256 value);
    event PlatformApproved(string platform);
    
    // ============ Constructor ============
    
    constructor() Ownable(msg.sender) {
        // Approve default platforms
        approvedPlatforms["openclaw"] = true;
        approvedPlatforms["autogpt"] = true;
        approvedPlatforms["crewai"] = true;
        approvedPlatforms["langchain"] = true;
        approvedPlatforms["custom"] = true;
    }
    
    // ============ Registration Functions ============
    
    /// @notice Register a wallet in the public directory
    /// @dev Caller must be the guardian of the wallet
    function registerWallet(
        address wallet,
        string calldata agentName,
        string calldata agentPlatform
    ) external {
        require(wallet != address(0), "XaviWalletRegistry: zero wallet");
        require(walletInfo[wallet].wallet == address(0), "XaviWalletRegistry: already registered");
        require(approvedPlatforms[agentPlatform], "XaviWalletRegistry: unknown platform");
        
        // Verify caller is the guardian
        XaviWallet w = XaviWallet(payable(wallet));
        require(w.guardian() == msg.sender, "XaviWalletRegistry: not guardian");
        
        // Spam prevention: minimum wallet balance
        require(wallet.balance >= MIN_WALLET_BALANCE, "XaviWalletRegistry: min 1 XRP balance");
        
        walletInfo[wallet] = WalletInfo({
            wallet: wallet,
            guardian: msg.sender,
            agentName: agentName,
            agentPlatform: agentPlatform,
            createdAt: block.timestamp,
            totalTransactions: 0,
            totalVolumeXRP: 0,
            verified: false,
            active: true
        });
        
        allWallets.push(wallet);
        walletsByGuardian[msg.sender].push(wallet);
        walletsByPlatform[agentPlatform].push(wallet);
        totalRegisteredWallets++;
        
        emit WalletRegistered(wallet, msg.sender, agentName, agentPlatform);
    }
    
    /// @notice Verify wallet (guardian confirms they own it)
    function verifyWallet(address wallet) external {
        WalletInfo storage info = walletInfo[wallet];
        require(info.wallet != address(0), "XaviWalletRegistry: not registered");
        require(info.guardian == msg.sender, "XaviWalletRegistry: not guardian");
        require(!info.verified, "XaviWalletRegistry: already verified");
        
        info.verified = true;
        totalVerifiedWallets++;
        
        emit WalletVerified(wallet, msg.sender);
    }
    
    /// @notice Deregister a wallet
    function deregisterWallet(address wallet) external {
        WalletInfo storage info = walletInfo[wallet];
        require(info.wallet != address(0), "XaviWalletRegistry: not registered");
        require(info.guardian == msg.sender || msg.sender == owner(), "XaviWalletRegistry: not authorized");
        require(info.active, "XaviWalletRegistry: already deregistered");
        
        info.active = false;
        totalRegisteredWallets--;
        if (info.verified) {
            totalVerifiedWallets--;
        }
        
        emit WalletDeregistered(wallet);
    }
    
    /// @notice Update stats (called by wallet contract after each action)
    /// @dev Only callable by registered wallets
    function recordAction(uint256 value) external {
        WalletInfo storage info = walletInfo[msg.sender];
        require(info.wallet != address(0), "XaviWalletRegistry: not registered");
        require(info.active, "XaviWalletRegistry: not active");
        
        info.totalTransactions++;
        info.totalVolumeXRP += value;
        totalTransactionsAllWallets++;
        totalVolumeAllWallets += value;
        
        emit ActionRecorded(msg.sender, value);
    }
    
    // ============ View Functions ============
    
    /// @notice Get wallet info
    function getWalletInfo(address wallet) external view returns (WalletInfo memory) {
        return walletInfo[wallet];
    }
    
    /// @notice Get wallets by platform
    function getWalletsByPlatform(string calldata platform) external view returns (address[] memory) {
        return walletsByPlatform[platform];
    }
    
    /// @notice Get wallets by guardian
    function getWalletsByGuardian(address guardian) external view returns (address[] memory) {
        return walletsByGuardian[guardian];
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
    
    /// @notice Get ecosystem stats
    function getEcosystemStats() external view returns (
        uint256 registered,
        uint256 verified,
        uint256 transactions,
        uint256 volume
    ) {
        return (
            totalRegisteredWallets,
            totalVerifiedWallets,
            totalTransactionsAllWallets,
            totalVolumeAllWallets
        );
    }
    
    /// @notice Check if wallet is registered and active
    function isRegistered(address wallet) external view returns (bool) {
        WalletInfo storage info = walletInfo[wallet];
        return info.wallet != address(0) && info.active;
    }
    
    /// @notice Check if wallet is verified
    function isVerified(address wallet) external view returns (bool) {
        return walletInfo[wallet].verified;
    }
    
    // ============ Admin Functions ============
    
    /// @notice Approve a new platform
    function approvePlatform(string calldata platform) external onlyOwner {
        approvedPlatforms[platform] = true;
        emit PlatformApproved(platform);
    }
    
    /// @notice Prevent accidental renounce
    function renounceOwnership() public pure override {
        revert("XaviWalletRegistry: cannot renounce");
    }
    
    /// @notice Get contract version
    function getVersion() external pure returns (string memory) {
        return VERSION;
    }
}
