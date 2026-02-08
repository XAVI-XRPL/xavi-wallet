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

    // ============ Constants ============
    
    string public constant VERSION = "1.1.0";
    uint256 public constant GUARDIAN_TRANSFER_DELAY = 48 hours;
    uint256 public constant MAX_SESSION_DURATION = 30 days;
    uint256 public constant MAX_SESSIONS_PER_DAY = 5;
    uint256 public constant MAX_BATCH_SIZE = 10;

    // ============ Structs ============

    struct SpendingLimits {
        uint256 perTransaction;
        uint256 dailyLimit;
        uint256 monthlyLimit;
        uint256 dailySpent;
        uint256 monthlySpent;
        uint256 dailyResetTime;
        uint256 monthlyResetTime;
    }

    struct Session {
        uint256 id;
        address agent;
        string agentName;
        uint256 createdAt;
        uint256 expiresAt;
        bool active;
        uint256 perTxLimit;
        uint256 dailyLimit;
        uint256 dailySpent;
        uint256 dailyResetTime;
    }

    struct ActionLog {
        uint256 id;
        address agent;
        address target;
        uint256 value;
        bytes4 selector;
        uint256 timestamp;
        bool success;
    }

    // ============ State Variables ============

    address public guardian;
    address public proposedGuardian;
    uint256 public guardianTransferProposedAt;
    string public agentName;
    bool public frozen;
    bool public whitelistEnabled;
    SpendingLimits public spendingLimits;
    mapping(address => bool) public whitelist;
    address[] public whitelistArray;
    mapping(uint256 => Session) public sessions;
    uint256 public sessionCount;
    mapping(address => uint256) public agentToSession;
    ActionLog[] public actionLog;
    address public registry;
    
    // Security: Nonce for replay protection
    mapping(address => uint256) public agentNonces;
    
    // Security: Session creation rate limiting
    uint256 public sessionsCreatedToday;
    uint256 public sessionCreationResetTime;

    // ============ Events ============

    event SessionCreated(uint256 indexed sessionId, address indexed agent, string agentName, uint256 expiresAt);
    event SessionRevoked(uint256 indexed sessionId, address indexed agent);
    event AllSessionsRevoked(uint256 count);
    event ActionExecuted(uint256 indexed actionId, address indexed agent, address indexed target, uint256 value, bytes4 selector, bool success);
    event ActionFailed(address indexed agent, address indexed target, uint256 value, bytes4 selector, string reason);
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
            monthlyLimit: 0,
            dailySpent: 0,
            monthlySpent: 0,
            dailyResetTime: block.timestamp + 24 hours,
            monthlyResetTime: block.timestamp + 30 days
        });
        
        sessionCreationResetTime = block.timestamp + 24 hours;
        whitelistEnabled = false;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // ============ Guardian Functions ============

    function freeze() external onlyGuardian {
        frozen = true;
        emit WalletFrozen(msg.sender);
    }

    function unfreeze() external onlyGuardian {
        frozen = false;
        emit WalletUnfrozen(msg.sender);
    }

    function recoverFunds() external onlyGuardian {
        uint256 balance = address(this).balance;
        require(balance > 0, "XaviWallet: no balance");
        (bool sent, ) = payable(guardian).call{value: balance}("");
        require(sent, "XaviWallet: recovery failed");
        emit FundsRecovered(msg.sender, balance);
    }

    function recoverTokens(address token, uint256 amount) external onlyGuardian {
        require(token != address(0), "XaviWallet: zero token");
        IERC20(token).safeTransfer(guardian, amount);
        emit TokensRecovered(msg.sender, token, amount);
    }

    function setSpendingLimits(uint256 perTx, uint256 daily, uint256 monthly) external onlyGuardian {
        spendingLimits.perTransaction = perTx;
        spendingLimits.dailyLimit = daily;
        spendingLimits.monthlyLimit = monthly;
        emit LimitsUpdated(perTx, daily, monthly);
    }

    function setWhitelistEnabled(bool enabled) external onlyGuardian {
        whitelistEnabled = enabled;
        emit WhitelistEnabledChanged(enabled);
    }

    function addToWhitelist(address target) external onlyGuardian {
        require(target != address(0), "XaviWallet: zero address");
        if (!whitelist[target]) {
            whitelist[target] = true;
            whitelistArray.push(target);
            emit WhitelistUpdated(target, true);
        }
    }

    function removeFromWhitelist(address target) external onlyGuardian {
        if (whitelist[target]) {
            whitelist[target] = false;
            emit WhitelistUpdated(target, false);
        }
    }

    function batchWhitelist(address[] calldata targets) external onlyGuardian {
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] != address(0) && !whitelist[targets[i]]) {
                whitelist[targets[i]] = true;
                whitelistArray.push(targets[i]);
                emit WhitelistUpdated(targets[i], true);
            }
        }
    }

    function createSession(
        address agent,
        string calldata _agentName,
        uint256 duration,
        uint256 perTxLimit,
        uint256 dailyLimit
    ) external onlyGuardian returns (uint256 sessionId) {
        require(agent != address(0), "XaviWallet: zero agent");
        require(duration > 0, "XaviWallet: zero duration");
        require(duration <= MAX_SESSION_DURATION, "XaviWallet: max 30 days");
        
        // Rate limiting: max 5 sessions per 24 hours
        if (block.timestamp >= sessionCreationResetTime) {
            sessionsCreatedToday = 0;
            sessionCreationResetTime = block.timestamp + 24 hours;
        }
        require(sessionsCreatedToday < MAX_SESSIONS_PER_DAY, "XaviWallet: session limit reached");
        sessionsCreatedToday++;
        
        // Revoke existing session
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

    function revokeSession(uint256 sessionId) external onlyGuardian {
        Session storage s = sessions[sessionId];
        require(s.id != 0, "XaviWallet: invalid session");
        require(s.active, "XaviWallet: already revoked");
        
        s.active = false;
        agentToSession[s.agent] = 0;
        emit SessionRevoked(sessionId, s.agent);
    }

    /// @notice Emergency: revoke ALL active sessions
    function revokeAllSessions() external onlyGuardian {
        uint256 revokedCount = 0;
        for (uint256 i = 1; i <= sessionCount; i++) {
            if (sessions[i].active) {
                sessions[i].active = false;
                agentToSession[sessions[i].agent] = 0;
                revokedCount++;
            }
        }
        emit AllSessionsRevoked(revokedCount);
    }

    /// @notice 2-step guardian transfer with 48-hour delay
    function proposeNewGuardian(address newGuardian) external onlyGuardian {
        require(newGuardian != address(0), "XaviWallet: zero guardian");
        require(newGuardian != guardian, "XaviWallet: same guardian");
        proposedGuardian = newGuardian;
        guardianTransferProposedAt = block.timestamp;
        emit GuardianshipProposed(guardian, newGuardian);
    }

    function acceptGuardianship() external {
        require(msg.sender == proposedGuardian, "XaviWallet: not proposed");
        require(
            block.timestamp >= guardianTransferProposedAt + GUARDIAN_TRANSFER_DELAY,
            "XaviWallet: 48hr delay not met"
        );
        address previous = guardian;
        guardian = proposedGuardian;
        proposedGuardian = address(0);
        guardianTransferProposedAt = 0;
        emit GuardianshipTransferred(previous, guardian);
    }

    function setRegistry(address _registry) external onlyGuardian {
        registry = _registry;
        emit RegistrySet(_registry);
    }

    // ============ Agent Functions ============

    /// @notice Execute a transaction with nonce for replay protection
    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 nonce
    ) external onlyActiveSession whenNotFrozen nonReentrant returns (bool success, bytes memory result) {
        // Nonce check for replay protection
        require(nonce == agentNonces[msg.sender], "XaviWallet: invalid nonce");
        agentNonces[msg.sender]++;
        
        // Input validation
        require(target != address(0), "XaviWallet: zero target");
        require(target != address(this), "XaviWallet: cannot call self");
        require(target != guardian, "XaviWallet: cannot call guardian");
        require(data.length > 0 || value > 0, "XaviWallet: empty call");
        
        _checkWhitelist(target);
        _checkLimits(value, msg.sender);
        
        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        
        (success, result) = target.call{value: value}(data);
        
        _logAction(msg.sender, target, value, selector, success);
        
        if (!success) {
            emit ActionFailed(msg.sender, target, value, selector, "execution reverted");
        }
        
        if (registry != address(0)) {
            try IXaviWalletRegistry(registry).recordAction(value) {} catch {}
        }
    }

    /// @notice Execute multiple transactions atomically with batch size limit
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        uint256 nonce
    ) external onlyActiveSession whenNotFrozen nonReentrant returns (bool[] memory successes) {
        require(nonce == agentNonces[msg.sender], "XaviWallet: invalid nonce");
        agentNonces[msg.sender]++;
        
        require(targets.length == values.length && values.length == datas.length, "XaviWallet: length mismatch");
        require(targets.length <= MAX_BATCH_SIZE, "XaviWallet: batch too large");
        require(targets.length > 0, "XaviWallet: empty batch");
        
        successes = new bool[](targets.length);
        uint256 totalValue = 0;
        
        // Validate all targets first
        for (uint256 i = 0; i < targets.length; i++) {
            require(targets[i] != address(0), "XaviWallet: zero target");
            require(targets[i] != address(this), "XaviWallet: cannot call self");
            require(targets[i] != guardian, "XaviWallet: cannot call guardian");
            _checkWhitelist(targets[i]);
            
            // Overflow check
            require(totalValue + values[i] >= totalValue, "XaviWallet: overflow");
            totalValue += values[i];
        }
        
        _checkLimits(totalValue, msg.sender);
        
        for (uint256 i = 0; i < targets.length; i++) {
            bytes4 selector = datas[i].length >= 4 ? bytes4(datas[i][:4]) : bytes4(0);
            (bool success, ) = targets[i].call{value: values[i]}(datas[i]);
            successes[i] = success;
            _logAction(msg.sender, targets[i], values[i], selector, success);
            
            if (!success) {
                emit ActionFailed(msg.sender, targets[i], values[i], selector, "batch item failed");
            }
        }
        
        if (registry != address(0)) {
            try IXaviWalletRegistry(registry).recordAction(totalValue) {} catch {}
        }
    }

    // ============ View Functions ============

    function remainingDailyBudget() external view returns (uint256) {
        SpendingLimits memory limits = spendingLimits;
        if (block.timestamp >= limits.dailyResetTime) return limits.dailyLimit;
        if (limits.dailySpent >= limits.dailyLimit) return 0;
        return limits.dailyLimit - limits.dailySpent;
    }

    function isWhitelisted(address target) external view returns (bool) {
        if (!whitelistEnabled) return true;
        return whitelist[target];
    }

    function getSession(uint256 sessionId) external view returns (Session memory) {
        return sessions[sessionId];
    }

    function getSessionByAgent(address agent) external view returns (Session memory) {
        return sessions[agentToSession[agent]];
    }

    function getActionLogLength() external view returns (uint256) {
        return actionLog.length;
    }

    function getActionLog(uint256 startId, uint256 count) external view returns (ActionLog[] memory) {
        uint256 len = actionLog.length;
        if (startId >= len) return new ActionLog[](0);
        uint256 end = startId + count > len ? len : startId + count;
        ActionLog[] memory logs = new ActionLog[](end - startId);
        for (uint256 i = startId; i < end; i++) {
            logs[i - startId] = actionLog[i];
        }
        return logs;
    }

    function getWhitelist() external view returns (address[] memory) {
        return whitelistArray;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function isSessionValid(address agent) external view returns (bool) {
        uint256 sessionId = agentToSession[agent];
        if (sessionId == 0) return false;
        Session storage s = sessions[sessionId];
        return s.active && block.timestamp < s.expiresAt;
    }

    function getAgentNonce(address agent) external view returns (uint256) {
        return agentNonces[agent];
    }

    function getVersion() external pure returns (string memory) {
        return VERSION;
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
        
        Session storage s = sessions[agentToSession[agent]];
        
        if (block.timestamp >= s.dailyResetTime) {
            s.dailySpent = 0;
            s.dailyResetTime = block.timestamp + 24 hours;
        }
        
        uint256 perTxLimit = s.perTxLimit > 0 ? s.perTxLimit : spendingLimits.perTransaction;
        require(value <= perTxLimit, "XaviWallet: exceeds per-tx limit");
        
        uint256 sessionDailyLimit = s.dailyLimit > 0 ? s.dailyLimit : spendingLimits.dailyLimit;
        require(s.dailySpent + value <= sessionDailyLimit, "XaviWallet: exceeds session daily limit");
        
        // Overflow check
        require(spendingLimits.dailySpent + value >= spendingLimits.dailySpent, "XaviWallet: overflow");
        require(spendingLimits.dailySpent + value <= spendingLimits.dailyLimit, "XaviWallet: exceeds daily limit");
        
        if (spendingLimits.monthlyLimit > 0) {
            require(spendingLimits.monthlySpent + value >= spendingLimits.monthlySpent, "XaviWallet: overflow");
            require(spendingLimits.monthlySpent + value <= spendingLimits.monthlyLimit, "XaviWallet: exceeds monthly limit");
        }
        
        s.dailySpent += value;
        spendingLimits.dailySpent += value;
        spendingLimits.monthlySpent += value;
    }

    function _checkWhitelist(address target) internal view {
        if (whitelistEnabled) {
            require(whitelist[target], "XaviWallet: target not whitelisted");
        }
    }

    function _logAction(address agent, address target, uint256 value, bytes4 selector, bool success) internal {
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
