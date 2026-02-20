// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EventMarket.sol";
import "../src/EventSettlementEngine.sol";

contract EventMarketTest is Test {
    EventMarket public em;
    EventSettlementEngine public ese;

    address public creWallet = makeAddr("cre");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    string public constant QUESTION = "Will ETH 24h Binance volume exceed $1B on expiry?";
    uint256 public expiry;

    function _deploy() internal {
        em = new EventMarket(address(this));
        ese = new EventSettlementEngine(address(em), creWallet);
        em.updateSettlementEngine(address(ese));
        expiry = block.timestamp + 1 hours;
    }

    function _setupMarketWithPositions() internal returns (uint256 id) {
        id = em.createMarket(QUESTION, expiry);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.prank(alice);
        em.takePosition{value: 1 ether}(id, EventMarket.Side.YES);
        vm.prank(bob);
        em.takePosition{value: 1 ether}(id, EventMarket.Side.NO);
        vm.warp(expiry + 1);
    }

    function setUp() public {
        _deploy();
    }

    // ── Creation ─────────────────────────────────────────────────────

    function test_createMarket() public {
        uint256 id = em.createMarket(QUESTION, expiry);
        (bytes32 qId,,, uint256 tYes, uint256 tNo, EventMarket.Outcome outcome) = em.markets(id);
        assertEq(qId, keccak256(abi.encodePacked(QUESTION)));
        assertEq(tYes, 0);
        assertEq(tNo, 0);
        assertEq(uint256(outcome), uint256(EventMarket.Outcome.UNRESOLVED));
    }

    function test_createMarket_rejectsBadExpiry() public {
        vm.expectRevert("bad expiry");
        em.createMarket(QUESTION, block.timestamp - 1);
    }

    function test_createMarket_rejectsEmptyQuestion() public {
        vm.expectRevert("empty question");
        em.createMarket("", expiry);
    }

    // ── Positions ────────────────────────────────────────────────────

    function test_takePosition_yes() public {
        uint256 id = em.createMarket(QUESTION, expiry);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        em.takePosition{value: 1 ether}(id, EventMarket.Side.YES);
        (,,, uint256 tYes,,) = em.markets(id);
        assertEq(tYes, 1 ether);
    }

    function test_takePosition_rejectsAfterExpiry() public {
        uint256 id = em.createMarket(QUESTION, expiry);
        vm.warp(expiry + 1);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert("market expired");
        em.takePosition{value: 1 ether}(id, EventMarket.Side.YES);
    }

    // ── Settlement ───────────────────────────────────────────────────

    function test_settlement_yes() public {
        uint256 id = _setupMarketWithPositions();
        vm.prank(creWallet);
        ese.executeSettlement(id, 1); // 1 = YES
        (,,,,, EventMarket.Outcome outcome) = em.markets(id);
        assertEq(uint256(outcome), uint256(EventMarket.Outcome.YES));
    }

    function test_settlement_no() public {
        uint256 id = _setupMarketWithPositions();
        vm.prank(creWallet);
        ese.executeSettlement(id, 2); // 2 = NO
        (,,,,, EventMarket.Outcome outcome) = em.markets(id);
        assertEq(uint256(outcome), uint256(EventMarket.Outcome.NO));
    }

    function test_settlement_invalid() public {
        uint256 id = _setupMarketWithPositions();
        vm.prank(creWallet);
        ese.executeSettlement(id, 3); // 3 = INVALID
        (,,,,, EventMarket.Outcome outcome) = em.markets(id);
        assertEq(uint256(outcome), uint256(EventMarket.Outcome.INVALID));
    }

    function test_settlement_rejectsNonCRE() public {
        vm.expectRevert("only CRE forwarder");
        ese.executeSettlement(0, 1);
    }

    function test_settlement_rejectsReplay() public {
        uint256 id = _setupMarketWithPositions();
        vm.startPrank(creWallet);
        ese.executeSettlement(id, 1);
        vm.expectRevert("already settled");
        ese.executeSettlement(id, 1);
        vm.stopPrank();
    }

    // ── Claim ────────────────────────────────────────────────────────

    function test_claim_yesWinner() public {
        uint256 id = _setupMarketWithPositions();
        vm.prank(creWallet);
        ese.executeSettlement(id, 1); // YES wins
        uint256 before = alice.balance;
        vm.prank(alice);
        em.claim(id);
        assertEq(alice.balance - before, 2 ether); // gets full pool
    }

    function test_claim_rejectsLoser() public {
        uint256 id = _setupMarketWithPositions();
        vm.prank(creWallet);
        ese.executeSettlement(id, 1); // YES wins, bob loses
        vm.prank(bob);
        vm.expectRevert("nothing to claim");
        em.claim(id);
    }

    // ── Refund (INVALID) ─────────────────────────────────────────────

    function test_refund_onInvalid() public {
        uint256 id = _setupMarketWithPositions();
        vm.prank(creWallet);
        ese.executeSettlement(id, 3); // INVALID

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        em.claimRefund(id);
        vm.prank(bob);
        em.claimRefund(id);

        assertEq(alice.balance - aliceBefore, 1 ether);
        assertEq(bob.balance - bobBefore, 1 ether);
    }

    function test_refund_rejectsDoubleRefund() public {
        uint256 id = _setupMarketWithPositions();
        vm.prank(creWallet);
        ese.executeSettlement(id, 3);
        vm.startPrank(alice);
        em.claimRefund(id);
        vm.expectRevert("already refunded");
        em.claimRefund(id);
        vm.stopPrank();
    }
}
