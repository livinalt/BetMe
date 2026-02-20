// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract PredictionMarket {
    enum Side {
        ABOVE,
        BELOW
    }
    enum State {
        OPEN,
        SETTLED
    }

    struct Market {
        uint256 strikePrice;
        uint256 expiry;
        uint256 totalAbove;
        uint256 totalBelow;
        uint256 settledPrice;
        State state;
    }

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => mapping(Side => uint256))) public positions;

    uint256 public nextMarketId;
    address public settlementEngine;

    event MarketCreated(uint256 indexed id, uint256 strike, uint256 expiry);
    event PositionTaken(uint256 indexed id, address user, Side side, uint256 amount);
    event MarketSettled(uint256 indexed id, uint256 settledPrice, Side winner);

    constructor(address _settlementEngine) {
        settlementEngine = _settlementEngine;
    }

    modifier onlySettlementEngine() {
        require(msg.sender == settlementEngine, "unauthorized");
        _;
    }

    function createMarket(uint256 strike, uint256 expiry) external returns (uint256 id) {
        require(expiry > block.timestamp, "bad expiry");
        id = nextMarketId++;
        markets[id] = Market(strike, expiry, 0, 0, 0, State.OPEN);
        emit MarketCreated(id, strike, expiry);
    }

    function takePosition(uint256 marketId, Side side) external payable {
        Market storage m = markets[marketId];
        require(m.state == State.OPEN, "market not open");
        require(block.timestamp < m.expiry, "market expired");
        require(msg.value > 0, "zero value");
        positions[marketId][msg.sender][side] += msg.value;
        if (side == Side.ABOVE) m.totalAbove += msg.value;
        else m.totalBelow += msg.value;
        emit PositionTaken(marketId, msg.sender, side, msg.value);
    }

    function settle(uint256 marketId, uint256 price) external onlySettlementEngine {
        Market storage m = markets[marketId];
        require(m.state == State.OPEN, "already settled");
        require(block.timestamp >= m.expiry, "not expired yet");
        m.settledPrice = price;
        m.state = State.SETTLED;
        Side winner = price >= m.strikePrice ? Side.ABOVE : Side.BELOW;
        emit MarketSettled(marketId, price, winner);
    }

    function claim(uint256 marketId) external {
        Market storage m = markets[marketId];
        require(m.state == State.SETTLED, "not settled");
        Side winner = m.settledPrice >= m.strikePrice ? Side.ABOVE : Side.BELOW;
        uint256 userStake = positions[marketId][msg.sender][winner];
        require(userStake > 0, "nothing to claim");
        positions[marketId][msg.sender][winner] = 0;
        uint256 totalPool = m.totalAbove + m.totalBelow;
        uint256 winnerPool = winner == Side.ABOVE ? m.totalAbove : m.totalBelow;
        require(winnerPool > 0, "empty winner pool");
        uint256 payout = (userStake * totalPool) / winnerPool;
        (bool success,) = payable(msg.sender).call{value: payout}("");
        require(success, "transfer failed");
    }

    function updateSettlementEngine(address newEngine) external {
        require(msg.sender == settlementEngine, "unauthorized");
        settlementEngine = newEngine;
    }
}
