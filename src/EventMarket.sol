// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract EventMarket {
    enum Outcome {
        UNRESOLVED,
        YES,
        NO,
        INVALID
    }
    enum Side {
        YES,
        NO
    }

    struct Market {
        bytes32 questionId; // keccak256(questionText)
        string questionText; // human-readable, immutable
        uint256 expiry;
        uint256 totalYes;
        uint256 totalNo;
        Outcome outcome;
    }

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => mapping(Side => uint256))) public positions;
    mapping(uint256 => mapping(address => bool)) public refundClaimed;

    uint256 public nextMarketId;
    address public settlementEngine;

    event MarketCreated(uint256 indexed id, bytes32 indexed questionId, string question, uint256 expiry);
    event PositionTaken(uint256 indexed id, address user, Side side, uint256 amount);
    event MarketSettled(uint256 indexed id, Outcome outcome);
    event Claimed(uint256 indexed id, address user, uint256 amount);
    event Refunded(uint256 indexed id, address user, uint256 amount);

    constructor(address _settlementEngine) {
        settlementEngine = _settlementEngine;
    }

    modifier onlySettlementEngine() {
        require(msg.sender == settlementEngine, "unauthorized");
        _;
    }

    function createMarket(string calldata questionText, uint256 expiry) external returns (uint256 id) {
        require(expiry > block.timestamp, "bad expiry");
        require(bytes(questionText).length > 0, "empty question");
        bytes32 questionId = keccak256(abi.encodePacked(questionText));
        id = nextMarketId++;
        markets[id] = Market({
            questionId: questionId,
            questionText: questionText,
            expiry: expiry,
            totalYes: 0,
            totalNo: 0,
            outcome: Outcome.UNRESOLVED
        });
        emit MarketCreated(id, questionId, questionText, expiry);
    }

    function takePosition(uint256 marketId, Side side) external payable {
        Market storage m = markets[marketId];
        require(m.outcome == Outcome.UNRESOLVED, "market closed");
        require(block.timestamp < m.expiry, "market expired");
        require(msg.value > 0, "zero value");
        positions[marketId][msg.sender][side] += msg.value;
        if (side == Side.YES) m.totalYes += msg.value;
        else m.totalNo += msg.value;
        emit PositionTaken(marketId, msg.sender, side, msg.value);
    }

    function settle(uint256 marketId, Outcome outcome) external onlySettlementEngine {
        Market storage m = markets[marketId];
        require(m.outcome == Outcome.UNRESOLVED, "already settled");
        require(block.timestamp >= m.expiry, "not expired yet");
        require(outcome != Outcome.UNRESOLVED, "invalid outcome");
        m.outcome = outcome;
        emit MarketSettled(marketId, outcome);
    }

    // ── Claim for YES or NO winner ──────────────────────────────────
    function claim(uint256 marketId) external {
        Market storage m = markets[marketId];
        require(m.outcome == Outcome.YES || m.outcome == Outcome.NO, "not claimable");

        Side winningSide = m.outcome == Outcome.YES ? Side.YES : Side.NO;
        uint256 userStake = positions[marketId][msg.sender][winningSide];
        require(userStake > 0, "nothing to claim");

        positions[marketId][msg.sender][winningSide] = 0;
        uint256 totalPool = m.totalYes + m.totalNo;
        uint256 winnerPool = winningSide == Side.YES ? m.totalYes : m.totalNo;
        require(winnerPool > 0, "empty winner pool");
        uint256 payout = (userStake * totalPool) / winnerPool;

        (bool success,) = payable(msg.sender).call{value: payout}("");
        require(success, "transfer failed");
        emit Claimed(marketId, msg.sender, payout);
    }

    // ── Refund for INVALID outcome ──────────────────────────────────
    function claimRefund(uint256 marketId) external {
        Market storage m = markets[marketId];
        require(m.outcome == Outcome.INVALID, "not invalid");
        require(!refundClaimed[marketId][msg.sender], "already refunded");

        uint256 yesStake = positions[marketId][msg.sender][Side.YES];
        uint256 noStake = positions[marketId][msg.sender][Side.NO];
        uint256 total = yesStake + noStake;
        require(total > 0, "nothing to refund");

        refundClaimed[marketId][msg.sender] = true;
        positions[marketId][msg.sender][Side.YES] = 0;
        positions[marketId][msg.sender][Side.NO] = 0;

        (bool success,) = payable(msg.sender).call{value: total}("");
        require(success, "refund failed");
        emit Refunded(marketId, msg.sender, total);
    }

    function updateSettlementEngine(address newEngine) external onlySettlementEngine {
        require(newEngine != address(0), "zero address");
        settlementEngine = newEngine;
    }
}
