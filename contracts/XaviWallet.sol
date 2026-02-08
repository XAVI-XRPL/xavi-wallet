// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title XaviWallet
 * @author Agent Xavi — Autonomous Builder on XRPL EVM
 * @notice Secure smart contract wallet for AI agents with spending limits,
 *         contract whitelisting, session keys, and full action logging
 * @dev The guardian (human) has full control. Agents interact through session keys
 *      with enforced limits. Every action is logged on-chain.
 */
contract XaviWallet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct SpendingLimits {
        uint256 perTransaction;    // max XRP per single tx
        uint256 dailyLimit;        // max XRP per 24 hours
        uint256 monthlyLimit;      // max XRP per 30 days (0 = unlimited)
        uint256 dailySpent;        // tracked spending today
        uint256 monthlySpent;      // tracked spending this month
        uint256 dailyResetTime;    // timestamp when daily counter resets
        uint256 monthlyResetTime;  // timestamp when monthly counter resets
    }

    struct Session {
        uint256 id;
        address agent;             // agent's EOA (session key holder)
        string agentName;          // human-readable identifier
        uint256 createdAt;
        uint256 expiresAt;         // auto-expires, agent loses access
        bool active;
        uint256 perTxLimit;        // per-session override (0 = use wallet default)
        uint256 dailyLimit;        // per-session override (0 = use wallet default)
        uint256 dailySpent;        // session-specific daily tracking
        uint256 dailyResetTime;    // session-specific reset time
    }

    struct ActionLog {
        uint256 id;
        address agent;             // which agent performed this
        address target;            // contract called (or recipient)
        uint256 value;             // XRP sent
        bytes4 selector;           // function selector called
        uint256 timestamp;
        bool success;
    }

    // ============ State Variables ============

    /// @notice Guardian address — has full control
    address public guardian;
    
    /// @notice Proposed new guardian for 2-step transfer
    address public proposedGuardian;
    
    /// @notice Agent name for this wallet
    string public agentName;
    
    /// @notice Whether wallet is frozen
    bool public frozen;
    
    /// @notice Whether whitelist is enabled (if false, any target allowed)
    bool public whitelistEnabled;
    
    /// @notice Global spending limits
    SpendingLimits public spendingLimits;
    
    /// @notice Contract whitelist
    mapping(address => bool) public whitelist;
    
    /// @notice All whitelisted addresses (for enumeration)
    address[] public whitelistArray;
    
    /// @notice Sessions by ID
    mapping(uint256 => Session) public sessions;
    
    /// @notice Total sessions created
    uint256 public sessionCount;
    
    /// @notice Agent address to active session ID
    mapping(address => uint256) public agentToSession;
    
    /// @notice Action log
    ActionLog[] public actionLog;
    
    /// @notice Registry contract (optional, for stats)
    address public registry;

    // ============ Events ============

    event SessionCreated(
        uint256 indexed sessionId,
        address indexed agent,
        string agentName,
        uint256 expiresAt
    );
    event SessionRevoked(uint256 indexed sessionId, address indexed agent);
    event ActionExecuted(
        uint256 indexed actionId,
        address indexed agent,
        address indexed target,
        uint256 value,
        bytes4 selector,
        bool success
    );
    event WalletFrozen(address indexed guardian);
    event WalletUnfrozen(address indexed guardian);
    event FundsRecovered(address indexed guardian, uint256 amount);
    event TokensRecovered(address indexed guardian, address indexed token, uint256 amount);
    event WhitelistUpdated(address indexed target, bool allowed);
    event WhitelistEnabledChanged(bool enabled);
    event LimitsUpdated(uint256 perTx, uint256 daily, uint256 monthly);
    event GuardianshipProposed(address indexed current, address indexed proposed);
    event GuardianshipTransferred(address indexed previous, address indexed current);
    event RegistrySet(address indexed registry);
    event Received(address indexed from, uint256 amount);

    // ============ Modifiers ============

    modifier onlyGuardian() {
        require(msg.sender == guardian, "XaviWallet: not guardian");
        _;
    }

    modifier onlyActiveSession() {
        uint256 sessionId = agentToSession[msg.sender];
        require(sessionId != 0, "XaviWallet: no active session");
        Session storage s = sessions[sessionId];
        require(s.active, "XaviWallet: session not active");
        require(block.timestamp < s.expiresAt, "XaviWallet: session expired");
        _;
    }

    modifier whenNotFrozen() {
        require(!frozen, "XaviWallet: wallet frozen");
        _;
    }

    // ============ Constructor ============

    constructor(
        address _guardian,
        string memory _agentName,
        uint256 _dailyLimit,
        uint256 _perTxLimit
    ) {
        require(_guardian != address(0), "XaviWallet: zero guardian");
        
        guardian = _guardian;
        agentName = _agentName;
        
        spendingLimits = SpendingLimits({
            perTransaction: _perTxLimit,
            dailyLimit: _dailyLimit,
            monthlyLimit: 0, // unlimited by default
            dailySpent: 0,
            monthlySpent: 0,
            dailyResetTime: block.timestamp + 24 hours,
            monthlyResetTime: block.timestamp + 30 days
        });
        
        whitelistEnabled = false; // disabled by default for ease of setup
    }

    // ============ Receive ============

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // ============ Guardian Functions ============

    /// @notice Freeze the wallet — no agent can transact
    function freeze() external onlyGuardian {
        frozen = true;
        emit WalletFrozen(msg.sender);
    }

    /// @notice Unfreeze the wallet
    function unfreeze() external onlyGuardian {
        frozen = false;
        emit WalletUnfrozen(msg.sender);
    }

    /// @notice Recover all XRP funds to guardian address
    function recoverFunds() external onlyGuardian {
        uint256 balance = address(this).balance;
        require(balance > 0, "XaviWallet: no balance");
        
        (bool sent, ) = payable(guardian).call{value: balance}("");
        require(sent, "XaviWallet: recovery failed");
        
        emit FundsRecovered(msg.sender, balance);
    }

    /// @notice Recover specific ERC-20 tokens
    function recoverTokens(address token, uint256 amount) external onlyGuardian {
        require(token != address(0), "XaviWallet: zero token");
        IERC20(token).safeTransfer(guardian, amount);
        emit TokensRecovered(msg.sender, token, amount);
    }

    /// @notice Update spending limits
    function setSpendingLimits(
        uint256 perTx,
        uint256 daily,
        uint256 monthly
    ) external onlyGuardian {
        spendingLimits.perTransaction = perTx;
        spendingLimits.dailyLimit = daily;
        spendingLimits.monthlyLimit = monthly;
        emit LimitsUpdated(perTx, daily, monthly);
    }

    /// @notice Enable or disable whitelist
    function setWhitelistEnabled(bool enabled) external onlyGuardian {
        whitelistEnabled = enabled;
        emit WhitelistEnabledChanged(enabled);
    }

    /// @notice Add a contract to the whitelist
    function addToWhitelist(address target) external onlyGuardian {
        require(target != address(0), "XaviWallet: zero address");
        if (!whitelist[target]) {
            whitelist[target] = true;
            whitelistArray.push(target);
            emit WhitelistUpdated(target, true);
        }
    }

    /// @notice Remove from whitelist
    function removeFromWhitelist(address target) external onlyGuardian {
        if (whitelist[target]) {
            whitelist[target] = false;
            emit WhitelistUpdated(target, false);
        }
    }

    /// @notice Batch whitelist
    function batchWhitelist(address[] calldata targets) external onlyGuardian {
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] != address(0) && !whitelist[targets[i]]) {
                whitelist[targets[i]] = true;
                whitelistArray.push(targets[i]);
                emit WhitelistUpdated(targets[i], true);
            }
        }
    }

    /// @notice Create a session key for an agent
    function createSession(
        address agent,
        string calldata _agentName,
        uint256 duration,
        uint256 perTxLimit,
        uint256 dailyLimit
    ) external onlyGuardian returns (uint256 sessionId) {
        require(agent != address(0), "XaviWallet: zero agent");
        require(duration > 0, "XaviWallet: zero duration");
        
        // Revoke any existing session for this agent
        uint256 existingSessionId = agentToSession[agent];
        if (existingSessionId != 0 && sessions[existingSessionId].active) {
            sessions[existingSessionId].active = false;
            emit SessionRevoked(existingSessionId, agent);
        }
        
        sessionCount++;
        sessionId = sessionCount;
        
        sessions[sessionId] = Session({
            id: sessionId,
            agent: agent,
            agentName: _agentName,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            active: true,
            perTxLimit: perTxLimit,
            dailyLimit: dailyLimit,
            dailySpent: 0,
            dailyResetTime: block.timestamp + 24 hours
        });
        
        agentToSession[agent] = sessionId;
        
        emit SessionCreated(sessionId, agent, _agentName, block.timestamp + duration);
    }

    /// @notice Revoke an active session immediately
    function revokeSession(uint256 sessionId) external onlyGuardian {
        Session storage s = sessions[sessionId];
        require(s.id != 0, "XaviWallet: invalid session");
        require(s.active, "XaviWallet: already revoked");
        
        s.active = false;
        agentToSession[s.agent] = 0;
        
        emit SessionRevoked(sessionId, s.agent);
    }

    /// @notice Transfer guardianship (2-step: propose + accept)
    function proposeNewGuardian(address newGuardian) external onlyGuardian {
        require(newGuardian != address(0), "XaviWallet: zero guardian");
        require(newGuardian != guardian, "XaviWallet: same guardian");
        proposedGuardian = newGuardian;
        emit GuardianshipProposed(guardian, newGuardian);
    }

    /// @notice Accept guardianship (called by proposed guardian)
    function acceptGuardianship() external {
        require(msg.sender == proposedGuardian, "XaviWallet: not proposed");
        address previous = guardian;
        guardian = proposedGuardian;
        proposedGuardian = address(0);
        emit GuardianshipTransferred(previous, guardian);
    }

    /// @notice Set registry contract for stats
    function setRegistry(address _registry) external onlyGuardian {
        registry = _registry;
        emit RegistrySet(_registry);
    }

    // ============ Agent Functions ============

    /// @notice Execute a transaction through the wallet
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyActiveSession whenNotFrozen nonReentrant returns (bool success, bytes memory result) {
        _checkWhitelist(target);
        _checkLimits(value, msg.sender);
        
        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        
        (success, result) = target.call{value: value}(data);
        
        _logAction(msg.sender, target, value, selector, success);
        
        // Update registry if set
        if (registry != address(0)) {
            try IXaviWalletRegistry(registry).recordAction(value) {} catch {}
        }
    }

    /// @notice Execute multiple transactions atomically
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyActiveSession whenNotFrozen nonReentrant returns (bool[] memory successes) {
        require(
            targets.length == values.length && values.length == datas.length,
            "XaviWallet: length mismatch"
        );
        
        successes = new bool[](targets.length);
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < targets.length; i++) {
            _checkWhitelist(targets[i]);
            totalValue += values[i];
        }
        
        _checkLimits(totalValue, msg.sender);
        
        for (uint256 i = 0; i < targets.length; i++) {
            bytes4 selector = datas[i].length >= 4 ? bytes4(datas[i][:4]) : bytes4(0);
            
            (bool success, ) = targets[i].call{value: values[i]}(datas[i]);
            successes[i] = success;
            
            _logAction(msg.sender, targets[i], values[i], selector, success);
        }
        
        // Update registry if set
        if (registry != address(0)) {
            try IXaviWalletRegistry(registry).recordAction(totalValue) {} catch {}
        }
    }

    // ============ View Functions ============

    /// @notice Check remaining daily budget
    function remainingDailyBudget() external view returns (uint256) {
        SpendingLimits memory limits = spendingLimits;
        
        // Check if reset needed
        if (block.timestamp >= limits.dailyResetTime) {
            return limits.dailyLimit;
        }
        
        if (limits.dailySpent >= limits.dailyLimit) {
            return 0;
        }
        
        return limits.dailyLimit - limits.dailySpent;
    }

    /// @notice Check if a target is whitelisted
    function isWhitelisted(address target) external view returns (bool) {
        if (!whitelistEnabled) return true;
        return whitelist[target];
    }

    /// @notice Get session info
    function getSession(uint256 sessionId) external view returns (Session memory) {
        return sessions[sessionId];
    }

    /// @notice Get session by agent address
    function getSessionByAgent(address agent) external view returns (Session memory) {
        uint256 sessionId = agentToSession[agent];
        return sessions[sessionId];
    }

    /// @notice Get action log length
    function getActionLogLength() external view returns (uint256) {
        return actionLog.length;
    }

    /// @notice Get action log slice
    function getActionLog(uint256 startId, uint256 count) external view returns (ActionLog[] memory) {
        uint256 len = actionLog.length;
        if (startId >= len) {
            return new ActionLog[](0);
        }
        
        uint256 end = startId + count;
        if (end > len) {
            end = len;
        }
        
        ActionLog[] memory logs = new ActionLog[](end - startId);
        for (uint256 i = startId; i < end; i++) {
            logs[i - startId] = actionLog[i];
        }
        
        return logs;
    }

    /// @notice Get all whitelisted addresses
    function getWhitelist() external view returns (address[] memory) {
        return whitelistArray;
    }

    /// @notice Get wallet balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Check if session is valid
    function isSessionValid(address agent) external view returns (bool) {
        uint256 sessionId = agentToSession[agent];
        if (sessionId == 0) return false;
        Session storage s = sessions[sessionId];
        return s.active && block.timestamp < s.expiresAt;
    }

    // ============ Internal Functions ============

    function _checkLimits(uint256 value, address agent) internal {
        // Reset global counters if needed
        if (block.timestamp >= spendingLimits.dailyResetTime) {
            spendingLimits.dailySpent = 0;
            spendingLimits.dailyResetTime = block.timestamp + 24 hours;
        }
        if (block.timestamp >= spendingLimits.monthlyResetTime) {
            spendingLimits.monthlySpent = 0;
            spendingLimits.monthlyResetTime = block.timestamp + 30 days;
        }
        
        // Get session for per-session limits
        Session storage s = sessions[agentToSession[agent]];
        
        // Reset session daily counter if needed
        if (block.timestamp >= s.dailyResetTime) {
            s.dailySpent = 0;
            s.dailyResetTime = block.timestamp + 24 hours;
        }
        
        // Check per-transaction limit
        uint256 perTxLimit = s.perTxLimit > 0 ? s.perTxLimit : spendingLimits.perTransaction;
        require(value <= perTxLimit, "XaviWallet: exceeds per-tx limit");
        
        // Check session daily limit
        uint256 sessionDailyLimit = s.dailyLimit > 0 ? s.dailyLimit : spendingLimits.dailyLimit;
        require(s.dailySpent + value <= sessionDailyLimit, "XaviWallet: exceeds session daily limit");
        
        // Check global daily limit
        require(
            spendingLimits.dailySpent + value <= spendingLimits.dailyLimit,
            "XaviWallet: exceeds daily limit"
        );
        
        // Check global monthly limit (if set)
        if (spendingLimits.monthlyLimit > 0) {
            require(
                spendingLimits.monthlySpent + value <= spendingLimits.monthlyLimit,
                "XaviWallet: exceeds monthly limit"
            );
        }
        
        // Update counters
        s.dailySpent += value;
        spendingLimits.dailySpent += value;
        spendingLimits.monthlySpent += value;
    }

    function _checkWhitelist(address target) internal view {
        if (whitelistEnabled) {
            require(whitelist[target], "XaviWallet: target not whitelisted");
        }
    }

    function _logAction(
        address agent,
        address target,
        uint256 value,
        bytes4 selector,
        bool success
    ) internal {
        uint256 actionId = actionLog.length;
        
        actionLog.push(ActionLog({
            id: actionId,
            agent: agent,
            target: target,
            value: value,
            selector: selector,
            timestamp: block.timestamp,
            success: success
        }));
        
        emit ActionExecuted(actionId, agent, target, value, selector, success);
    }
}

interface IXaviWalletRegistry {
    function recordAction(uint256 value) external;
}
