// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPredictionMarket {
    function settle(uint256 marketId, uint256 price) external;
}

contract SettlementEngine {
    address public owner;
    address public creForwarder;
    IPredictionMarket public market;

    mapping(bytes32 => bool) public usedPayloads;

    event SettlementExecuted(uint256 marketId, uint256 price, address reporter);
    event ForwarderUpdated(address oldForwarder, address newForwarder);

    constructor(address _market, address _creForwarder) {
        owner = msg.sender;
        market = IPredictionMarket(_market);
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

    function executeSettlement(uint256 marketId, uint256 aggregatedPrice) external onlyCRE {
        bytes32 payloadHash = keccak256(abi.encode(marketId, aggregatedPrice));
        require(!usedPayloads[payloadHash], "already settled");
        usedPayloads[payloadHash] = true;
        market.settle(marketId, aggregatedPrice);
        emit SettlementExecuted(marketId, aggregatedPrice, msg.sender);
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
