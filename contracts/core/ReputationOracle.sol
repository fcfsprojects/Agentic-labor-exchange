// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ReputationOracle
 * @dev On-chain reputation scoring system for AI agents
 * @notice Tracks performance metrics and computes trustless reputation scores
 */

contract ReputationOracle is Ownable, ReentrancyGuard {

    /// @dev Performance tiers
    enum ReputationTier {
        UNRANKED,      // 0-2000 points
        APPRENTICE,    // 2001-5000 points
        JOURNEYMAN,    // 5001-7500 points
        MASTER,        // 7501-9000 points
        LEGEND         // 9001-10000 points
    }

    /// @dev Agent reputation record
    struct AgentReputation {
        address agentAddress;
        
        // Task metrics
        uint256 totalTasksAttempted;
        uint256 totalTasksSucceeded;
        uint256 totalTasksFailed;
        uint256 totalTasksDisputed;
        
        // Performance metrics
        uint256 cumulativeLatencyMs;    // sum of all execution times
        uint256 avgLatencyMs;            // average execution time
        
        uint256 cumulativeCostWei;      // sum of all payments
        uint256 avgCostPerTaskWei;      // average cost per task
        
        // Quality metrics
        uint256 cumulativeQualityScore;
        uint256 avgQualityScore;        // 0-100 scale
        
        // Satisfaction
        uint256 totalRatings;
        uint256 satisfiedRatings;       // count of 4-5 star ratings
        uint256 userSatisfactionScore;  // 0-10000 basis points
        
        // Reliability
        uint256 uptimePercentage;       // 0-10000 basis points
        uint256 slashingCount;          // number of times slashed
        uint256 timeoutCount;           // failed to meet deadline
        
        // Temporal
        uint48 registrationTime;
        uint48 lastTaskCompletionTime;
        uint48 lastReputationUpdate;
        
        // Current state
        uint256 reputationScore;        // 0-10000 basis points
        ReputationTier tier;
    }

    /// @dev Task completion record
    struct TaskRecord {
        bytes32 taskId;
        address agent;
        uint256 latencyMs;
        uint256 costWei;
        uint8 qualityScore;            // 1-10
        bool succeeded;
        bool disputed;
        uint48 completionTime;
    }

    // ============ State Variables ============

    mapping(address => AgentReputation) public reputations;
    mapping(bytes32 => TaskRecord) public taskRecords;
    
    address[] public registeredAgents;
    
    // Scoring weights (sum to 10000 basis points)
    uint256 public successRateWeight = 4000;    // 40%
    uint256 public latencyScoreWeight = 2500;   // 25%
    uint256 public costEfficiencyWeight = 2000; // 20%
    uint256 public satisfactionWeight = 1500;   // 15%

    // Scoring parameters
    uint256 public targetLatencyMs = 5000;      // 5 seconds target
    uint256 public timeDecayDays = 30;          // 30 days half-life for old tasks

    // ============ Events ============

    event AgentRegistered(
        address indexed agent,
        uint48 timestamp
    );

    event TaskCompleted(
        bytes32 indexed taskId,
        address indexed agent,
        uint256 latencyMs,
        uint8 qualityScore,
        bool succeeded,
        uint48 timestamp
    );

    event ReputationUpdated(
        address indexed agent,
        uint256 newScore,
        ReputationTier newTier,
        uint256[] scoreComponents,
        uint48 timestamp
    );

    event AgentRated(
        address indexed agent,
        uint8 rating,              // 1-5 stars
        string feedback,
        uint48 timestamp
    );

    event AgentSlashed(
        address indexed agent,
        uint256 slashAmount,
        string reason,
        uint48 timestamp
    );

    // ============ Registration & Update Functions ============

    /**
     * @dev Register an agent for reputation tracking
     */
    function registerAgent(address agent) external onlyOwner {
        require(agent != address(0), "Invalid agent address");
        require(reputations[agent].agentAddress == address(0), "Agent already registered");

        reputations[agent] = AgentReputation({
            agentAddress: agent,
            totalTasksAttempted: 0,
            totalTasksSucceeded: 0,
            totalTasksFailed: 0,
            totalTasksDisputed: 0,
            cumulativeLatencyMs: 0,
            avgLatencyMs: 0,
            cumulativeCostWei: 0,
            avgCostPerTaskWei: 0,
            cumulativeQualityScore: 0,
            avgQualityScore: 0,
            totalRatings: 0,
            satisfiedRatings: 0,
            userSatisfactionScore: 5000,  // Start neutral
            uptimePercentage: 10000,      // Start at 100%
            slashingCount: 0,
            timeoutCount: 0,
            registrationTime: uint48(block.timestamp),
            lastTaskCompletionTime: 0,
            lastReputationUpdate: 0,
            reputationScore: 5000,        // Start at 5000/10000
            tier: ReputationTier.APPRENTICE
        });

        registeredAgents.push(agent);

        emit AgentRegistered(agent, uint48(block.timestamp));
    }

    /**
     * @dev Record task completion and update agent metrics
     */
    function recordTaskCompletion(
        bytes32 taskId,
        address agent,
        uint256 latencyMs,
        uint256 costWei,
        uint8 qualityScore,
        bool succeeded
    ) external onlyOwner nonReentrant {
        require(reputations[agent].agentAddress != address(0), "Agent not registered");
        require(qualityScore >= 1 && qualityScore <= 10, "Quality score must be 1-10");

        AgentReputation storage rep = reputations[agent];

        // Update task counts
        rep.totalTasksAttempted++;
        if (succeeded) {
            rep.totalTasksSucceeded++;
        } else {
            rep.totalTasksFailed++;
        }

        // Update performance metrics
        rep.cumulativeLatencyMs += latencyMs;
        rep.avgLatencyMs = rep.cumulativeLatencyMs / rep.totalTasksAttempted;

        rep.cumulativeCostWei += costWei;
        rep.avgCostPerTaskWei = rep.cumulativeCostWei / rep.totalTasksAttempted;

        rep.cumulativeQualityScore += qualityScore;
        rep.avgQualityScore = rep.cumulativeQualityScore / rep.totalTasksAttempted;

        rep.lastTaskCompletionTime = uint48(block.timestamp);

        // Record task details
        taskRecords[taskId] = TaskRecord({
            taskId: taskId,
            agent: agent,
            latencyMs: latencyMs,
            costWei: costWei,
            qualityScore: qualityScore,
            succeeded: succeeded,
            disputed: false,
            completionTime: uint48(block.timestamp)
        });

        emit TaskCompleted(
            taskId,
            agent,
            latencyMs,
            qualityScore,
            succeeded,
            uint48(block.timestamp)
        );

        // Update reputation score
        updateReputationScore(agent);
    }

    /**
     * @dev Submit rating for agent from end-user
     */
    function rateAgent(address agent, uint8 rating, string memory feedback) 
        external 
        onlyOwner 
    {
        require(reputations[agent].agentAddress != address(0), "Agent not registered");
        require(rating >= 1 && rating <= 5, "Rating must be 1-5 stars");

        AgentReputation storage rep = reputations[agent];

        rep.totalRatings++;
        if (rating >= 4) {
            rep.satisfiedRatings++;
        }

        // Update satisfaction score
        rep.userSatisfactionScore = (rep.satisfiedRatings * 10000) / rep.totalRatings;

        emit AgentRated(agent, rating, feedback, uint48(block.timestamp));

        updateReputationScore(agent);
    }

    /**
     * @dev Mark task as disputed
     */
    function disputeTask(bytes32 taskId, string memory reason) external onlyOwner {
        require(taskRecords[taskId].taskId != bytes32(0), "Task not found");

        address agent = taskRecords[taskId].agent;
        AgentReputation storage rep = reputations[agent];

        taskRecords[taskId].disputed = true;
        rep.totalTasksDisputed++;

        emit AgentSlashed(agent, 250, reason); // Slash 2.5%

        updateReputationScore(agent);
    }

    /**
     * @dev Slash agent reputation for misbehavior
     */
    function slashAgent(address agent, uint256 slashBasisPoints, string memory reason) 
        external 
        onlyOwner 
    {
        require(reputations[agent].agentAddress != address(0), "Agent not registered");

        AgentReputation storage rep = reputations[agent];

        // Apply slash
        uint256 reduction = (rep.reputationScore * slashBasisPoints) / 10000;
        rep.reputationScore = rep.reputationScore > reduction ? rep.reputationScore - reduction : 0;
        rep.slashingCount++;

        // Reduce uptime
        rep.uptimePercentage = rep.uptimePercentage > 500 ? rep.uptimePercentage - 500 : 0;

        emit AgentSlashed(agent, slashBasisPoints, reason);

        updateReputationScore(agent);
    }

    /**
     * @dev Record timeout failure
     */
    function recordTimeout(address agent, string memory reason) external onlyOwner {
        require(reputations[agent].agentAddress != address(0), "Agent not registered");

        AgentReputation storage rep = reputations[agent];
        rep.timeoutCount++;
        
        slashAgent(agent, 500, reason); // Slash 5%
    }

    // ============ Reputation Calculation ============

    /**
     * @dev Calculate success rate component (0-10000)
     */
    function calculateSuccessRate(address agent) public view returns (uint256) {
        AgentReputation storage rep = reputations[agent];
        if (rep.totalTasksAttempted == 0) return 5000; // Default 50%

        uint256 successRate = (rep.totalTasksSucceeded * 10000) / rep.totalTasksAttempted;
        return successRate > 10000 ? 10000 : successRate;
    }

    /**
     * @dev Calculate latency score component (0-10000)
     * Higher score = lower latency (faster is better)
     */
    function calculateLatencyScore(address agent) public view returns (uint256) {
        AgentReputation storage rep = reputations[agent];
        if (rep.avgLatencyMs == 0) return 5000; // Default 50%

        // Score decreases as latency increases
        if (rep.avgLatencyMs >= targetLatencyMs * 2) {
            return 0; // Very slow
        }

        uint256 score = 10000 - ((rep.avgLatencyMs * 10000) / (targetLatencyMs * 2));
        return score > 10000 ? 0 : score;
    }

    /**
     * @dev Calculate cost efficiency component (0-10000)
     * Assumes we track market average separately
     */
    function calculateCostEfficiency(address agent) public view returns (uint256) {
        AgentReputation storage rep = reputations[agent];
        if (rep.avgCostPerTaskWei == 0) return 5000; // Default 50%

        // Agents with lower cost score higher (up to a point)
        // Assumed market average: 0.1 ETH = 100000000000000000 wei
        uint256 marketAverageWei = 100000000000000000;

        if (rep.avgCostPerTaskWei > marketAverageWei * 2) {
            return 0; // Too expensive
        }

        uint256 efficiency = 10000 - ((rep.avgCostPerTaskWei * 10000) / (marketAverageWei * 2));
        return efficiency > 10000 ? 0 : efficiency;
    }

    /**
     * @dev Calculate satisfaction component (0-10000)
     */
    function calculateSatisfaction(address agent) public view returns (uint256) {
        return reputations[agent].userSatisfactionScore;
    }

    /**
     * @dev Apply time decay to older task records
     */
    function applyTimeDecay(uint48 lastTaskTime) public view returns (uint256) {
        if (lastTaskTime == 0) return 5000; // Default if no history

        uint256 daysSinceLastTask = (block.timestamp - lastTaskTime) / 86400;

        if (daysSinceLastTask >= timeDecayDays * 3) {
            return 5000; // Old data → neutral weight
        }

        // Decay formula: weight = exp(-0.1 * days)
        // Simplified: (10000 - (daysSinceLastTask * 100)) / 10000
        if (daysSinceLastTask > 100) {
            return 5000;
        }

        return 10000 - (daysSinceLastTask * 100);
    }

    /**
     * @dev Update agent reputation score with all components
     */
    function updateReputationScore(address agent) public {
        require(reputations[agent].agentAddress != address(0), "Agent not registered");

        AgentReputation storage rep = reputations[agent];

        // Calculate component scores
        uint256 successScore = calculateSuccessRate(agent);
        uint256 latencyScore = calculateLatencyScore(agent);
        uint256 costScore = calculateCostEfficiency(agent);
        uint256 satisfactionScore = calculateSatisfaction(agent);

        // Apply time decay
        uint256 timeDecay = applyTimeDecay(rep.lastTaskCompletionTime);
        
        // Weighted average
        uint256 newScore = 
            (successScore * successRateWeight * timeDecay / 10000) / 10000 +
            (latencyScore * latencyScoreWeight * timeDecay / 10000) / 10000 +
            (costScore * costEfficiencyWeight * timeDecay / 10000) / 10000 +
            (satisfactionScore * satisfactionWeight * timeDecay / 10000) / 10000;

        rep.reputationScore = newScore > 10000 ? 10000 : newScore;
        rep.lastReputationUpdate = uint48(block.timestamp);

        // Update tier
        ReputationTier newTier;
        if (rep.reputationScore >= 9001) {
            newTier = ReputationTier.LEGEND;
        } else if (rep.reputationScore >= 7501) {
            newTier = ReputationTier.MASTER;
        } else if (rep.reputationScore >= 5001) {
            newTier = ReputationTier.JOURNEYMAN;
        } else if (rep.reputationScore >= 2001) {
            newTier = ReputationTier.APPRENTICE;
        } else {
            newTier = ReputationTier.UNRANKED;
        }

        rep.tier = newTier;

        uint256[] memory components = new uint256[](4);
        components[0] = successScore;
        components[1] = latencyScore;
        components[2] = costScore;
        components[3] = satisfactionScore;

        emit ReputationUpdated(
            agent,
            rep.reputationScore,
            newTier,
            components,
            uint48(block.timestamp)
        );
    }

    // ============ Query Functions ============

    /**
     * @dev Get agent reputation details
     */
    function getReputation(address agent) external view returns (AgentReputation memory) {
        return reputations[agent];
    }

    /**
     * @dev Get agent tier
     */
    function getAgentTier(address agent) external view returns (ReputationTier) {
        return reputations[agent].tier;
    }

    /**
     * @dev Get task record details
     */
    function getTaskRecord(bytes32 taskId) external view returns (TaskRecord memory) {
        return taskRecords[taskId];
    }

    /**
     * @dev Get all registered agents
     */
    function getAllAgents() external view returns (address[] memory) {
        return registeredAgents;
    }

    /**
     * @dev Get agents sorted by reputation (top N)
     */
    function getTopAgents(uint256 limit) external view returns (address[] memory) {
        uint256 count = registeredAgents.length < limit ? registeredAgents.length : limit;
        address[] memory topAgents = new address[](count);

        // Simple sorting (not gas-efficient for large sets, use off-chain for production)
        uint256[] memory scores = new uint256[](registeredAgents.length);

        for (uint256 i = 0; i < registeredAgents.length; i++) {
            scores[i] = reputations[registeredAgents[i]].reputationScore;
        }

        for (uint256 i = 0; i < count; i++) {
            uint256 maxScore = 0;
            uint256 maxIndex = 0;

            for (uint256 j = 0; j < registeredAgents.length; j++) {
                if (scores[j] > maxScore) {
                    maxScore = scores[j];
                    maxIndex = j;
                }
            }

            topAgents[i] = registeredAgents[maxIndex];
            scores[maxIndex] = 0;
        }

        return topAgents;
    }

    // ============ Admin Functions ============

    /**
     * @dev Update scoring weights
     */
    function setScoringWeights(
        uint256 _successRateWeight,
        uint256 _latencyScoreWeight,
        uint256 _costEfficiencyWeight,
        uint256 _satisfactionWeight
    ) external onlyOwner {
        require(
            _successRateWeight + _latencyScoreWeight + _costEfficiencyWeight + _satisfactionWeight == 10000,
            "Weights must sum to 10000"
        );

        successRateWeight = _successRateWeight;
        latencyScoreWeight = _latencyScoreWeight;
        costEfficiencyWeight = _costEfficiencyWeight;
        satisfactionWeight = _satisfactionWeight;
    }

    /**
     * @dev Update scoring parameters
     */
    function setScoringParameters(uint256 _targetLatencyMs, uint256 _timeDecayDays) external onlyOwner {
        targetLatencyMs = _targetLatencyMs;
        timeDecayDays = _timeDecayDays;
    }
}
