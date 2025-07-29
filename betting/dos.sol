// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DecentralizedSportsBetting
 * @dev A peer-to-peer sports betting contract without intermediaries
 * @author Your Name
 */
contract DecentralizedSportsBetting {
    
    // Struct to represent a betting market
    struct BettingMarket {
        uint256 id;
        string description;
        uint256 endTime;
        bool resolved;
        uint8 outcome; // 0 = not resolved, 1 = team A wins, 2 = team B wins, 3 = draw
        uint256 totalBetsTeamA;
        uint256 totalBetsTeamB;
        uint256 totalBetsDraw;
        address creator;
        bool active;
    }
    
    // Struct to represent a bet
    struct Bet {
        uint256 marketId;
        address bettor;
        uint256 amount;
        uint8 prediction; // 1 = team A, 2 = team B, 3 = draw
        bool claimed;
    }
    
    // State variables
    mapping(uint256 => BettingMarket) public bettingMarkets;
    mapping(uint256 => Bet[]) public marketBets;
    mapping(address => uint256[]) public userBets;
    
    uint256 public nextMarketId = 1;
    uint256 public platformFee = 2; // 2% platform fee
    address public owner;
    
    // Events
    event MarketCreated(uint256 indexed marketId, string description, uint256 endTime);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, uint256 amount, uint8 prediction);
    event MarketResolved(uint256 indexed marketId, uint8 outcome);
    event WinningsClaimed(uint256 indexed marketId, address indexed winner, uint256 amount);
    event MarketCanceled(uint256 indexed marketId);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier marketExists(uint256 _marketId) {
        require(_marketId < nextMarketId && bettingMarkets[_marketId].active, "Market does not exist or is inactive");
        _;
    }
    
    modifier marketActive(uint256 _marketId) {
        require(block.timestamp < bettingMarkets[_marketId].endTime, "Betting period has ended");
        require(!bettingMarkets[_marketId].resolved, "Market already resolved");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Function 1: Create a new betting market
     * @param _description Description of the sporting event
     * @param _duration Duration in seconds from now when betting ends
     */
    function createMarket(string memory _description, uint256 _duration) external {
        require(_duration > 0, "Duration must be greater than 0");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        uint256 endTime = block.timestamp + _duration;
        
        bettingMarkets[nextMarketId] = BettingMarket({
            id: nextMarketId,
            description: _description,
            endTime: endTime,
            resolved: false,
            outcome: 0,
            totalBetsTeamA: 0,
            totalBetsTeamB: 0,
            totalBetsDraw: 0,
            creator: msg.sender,
            active: true
        });
        
        emit MarketCreated(nextMarketId, _description, endTime);
        nextMarketId++;
    }
    
    /**
     * @dev Function 2: Place a bet on a market
     * @param _marketId ID of the betting market
     * @param _prediction Prediction (1 = team A, 2 = team B, 3 = draw)
     */
    function placeBet(uint256 _marketId, uint8 _prediction) 
        external 
        payable 
        marketExists(_marketId) 
        marketActive(_marketId) 
    {
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(_prediction >= 1 && _prediction <= 3, "Invalid prediction");
        
        // Create the bet
        Bet memory newBet = Bet({
            marketId: _marketId,
            bettor: msg.sender,
            amount: msg.value,
            prediction: _prediction,
            claimed: false
        });
        
        // Add bet to market bets
        marketBets[_marketId].push(newBet);
        userBets[msg.sender].push(marketBets[_marketId].length - 1);
        
        // Update market totals
        if (_prediction == 1) {
            bettingMarkets[_marketId].totalBetsTeamA += msg.value;
        } else if (_prediction == 2) {
            bettingMarkets[_marketId].totalBetsTeamB += msg.value;
        } else {
            bettingMarkets[_marketId].totalBetsDraw += msg.value;
        }
        
        emit BetPlaced(_marketId, msg.sender, msg.value, _prediction);
    }
    
    /**
     * @dev Function 3: Resolve a betting market (only market creator or owner)
     * @param _marketId ID of the betting market
     * @param _outcome Outcome of the event (1 = team A, 2 = team B, 3 = draw)
     */
    function resolveMarket(uint256 _marketId, uint8 _outcome) 
        external 
        marketExists(_marketId) 
    {
        BettingMarket storage market = bettingMarkets[_marketId];
        require(
            msg.sender == market.creator || msg.sender == owner, 
            "Only market creator or owner can resolve"
        );
        require(block.timestamp >= market.endTime, "Betting period has not ended");
        require(!market.resolved, "Market already resolved");
        require(_outcome >= 1 && _outcome <= 3, "Invalid outcome");
        
        market.resolved = true;
        market.outcome = _outcome;
        
        emit MarketResolved(_marketId, _outcome);
    }
    
    /**
     * @dev Function 4: Claim winnings from a resolved market
     * @param _marketId ID of the betting market
     */
    function claimWinnings(uint256 _marketId) external marketExists(_marketId) {
        BettingMarket storage market = bettingMarkets[_marketId];
        require(market.resolved, "Market not resolved yet");
        
        uint256 totalWinnings = 0;
        Bet[] storage bets = marketBets[_marketId];
        
        // Calculate total pool and winning pool
        uint256 totalPool = market.totalBetsTeamA + market.totalBetsTeamB + market.totalBetsDraw;
        uint256 winningPool;
        
        if (market.outcome == 1) {
            winningPool = market.totalBetsTeamA;
        } else if (market.outcome == 2) {
            winningPool = market.totalBetsTeamB;
        } else {
            winningPool = market.totalBetsDraw;
        }
        
        // If no one bet on the winning outcome, refund all bets
        if (winningPool == 0) {
            for (uint256 i = 0; i < bets.length; i++) {
                if (bets[i].bettor == msg.sender && !bets[i].claimed) {
                    totalWinnings += bets[i].amount;
                    bets[i].claimed = true;
                }
            }
        } else {
            // Calculate winnings for correct predictions
            for (uint256 i = 0; i < bets.length; i++) {
                if (bets[i].bettor == msg.sender && 
                    bets[i].prediction == market.outcome && 
                    !bets[i].claimed) {
                    
                    // Winner gets their bet back plus proportional share of losing bets
                    uint256 winnerShare = (bets[i].amount * totalPool) / winningPool;
                    uint256 platformFeeAmount = (winnerShare * platformFee) / 100;
                    totalWinnings += winnerShare - platformFeeAmount;
                    bets[i].claimed = true;
                }
            }
        }
        
        require(totalWinnings > 0, "No winnings to claim");
        
        payable(msg.sender).transfer(totalWinnings);
        emit WinningsClaimed(_marketId, msg.sender, totalWinnings);
    }
    
    /**
     * @dev Function 5: Cancel a market (only before betting ends and if no bets placed)
     * @param _marketId ID of the betting market to cancel
     */
    function cancelMarket(uint256 _marketId) external marketExists(_marketId) {
        BettingMarket storage market = bettingMarkets[_marketId];
        require(
            msg.sender == market.creator || msg.sender == owner, 
            "Only market creator or owner can cancel"
        );
        require(!market.resolved, "Cannot cancel resolved market");
        
        uint256 totalBets = market.totalBetsTeamA + market.totalBetsTeamB + market.totalBetsDraw;
        require(totalBets == 0, "Cannot cancel market with existing bets");
        
        market.active = false;
        emit MarketCanceled(_marketId);
    }
    
    // View functions
    function getMarket(uint256 _marketId) external view returns (BettingMarket memory) {
        return bettingMarkets[_marketId];
    }
    
    function getMarketBets(uint256 _marketId) external view returns (Bet[] memory) {
        return marketBets[_marketId];
    }
    
    function getUserBets(address _user) external view returns (uint256[] memory) {
        return userBets[_user];
    }
    
    // Owner functions
    function withdrawPlatformFees() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 10, "Platform fee cannot exceed 10%");
        platformFee = _newFee;
    }
}
