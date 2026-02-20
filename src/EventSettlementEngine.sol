// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEventMarket {
    enum Outcome { UNRESOLVED, YES, NO, INVALID }
    function settle(uint256 marketId, Outcome outcome) external;
}

contract EventSettlementEngine {
    address public owner;
    address public creForwarder;
    IEventMarket public market;

    mapping(bytes32 => bool) public usedPayloads;

    event EventSettled(uint256 marketId, IEventMarket.Outcome outcome, address reporter);
    event ForwarderUpdated(address oldForwarder, address newForwarder);

    constructor(address _market, address _creForwarder) {
        owner       = msg.sender;
        market      = IEventMarket(_market);
        creForwarder = _creForwarder;
    }

    modifier onlyCRE() {
        require(msg.sender == creForwarder, "only CRE forwarder");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    // outcome: 1=YES, 2=NO, 3=INVALID
    function executeSettlement(
        uint256 marketId,
        uint8   outcome    // matches IEventMarket.Outcome enum
    ) external onlyCRE {
        require(outcome >= 1 && outcome <= 3, "invalid outcome value");
        bytes32 payloadHash = keccak256(abi.encode(marketId, outcome));
        require(!usedPayloads[payloadHash], "already settled");
        usedPayloads[payloadHash] = true;

        IEventMarket.Outcome o = IEventMarket.Outcome(outcome);
        market.settle(marketId, o);
        emit EventSettled(marketId, o, msg.sender);
    }

    function updateForwarder(address newForwarder) external onlyOwner {
        require(newForwarder != address(0), "zero address");
        emit ForwarderUpdated(creForwarder, newForwarder);
        creForwarder = newForwarder;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }
}
