// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PredictionMarket.sol";
import "../src/SettlementEngine.sol";

contract PredictionMarketTest is Test {
    PredictionMarket public pm;
    SettlementEngine public se;

    address public creWallet = makeAddr("cre");
    address public alice     = makeAddr("alice");
    address public bob       = makeAddr("bob");

    uint256 public constant STRIKE = 3000_00000000;
    uint256 public expiry;

    // ── helpers ──────────────────────────────────────────────────────

    function _deploy() internal {
        // Step 1: deploy PM with a temp settler so constructor doesn't revert
        pm = new PredictionMarket(address(this));
        // Step 2: deploy SE pointing to the real PM
        se = new SettlementEngine(address(pm), creWallet);
        // Step 3: update PM to point to the real SE
        pm.updateSettlementEngine(address(se));
        // Reset expiry relative to current block
        expiry = block.timestamp + 1 hours;
    }

    function _setupMarketWithPositions() internal {
        pm.createMarket(STRIKE, expiry);
        vm.deal(alice, 1 ether);
        vm.deal(bob,   1 ether);
        vm.prank(alice);
        pm.takePosition{value: 1 ether}(0, PredictionMarket.Side.ABOVE);
        vm.prank(bob);
        pm.takePosition{value: 1 ether}(0, PredictionMarket.Side.BELOW);
        vm.warp(expiry + 1);
    }

    function setUp() public {
        _deploy();
    }

    // ── Market creation ──────────────────────────────────────────────

    function test_createMarket() public {
        uint256 id = pm.createMarket(STRIKE, expiry);
        assertEq(id, 0);
        (uint256 strike, uint256 exp,,,, PredictionMarket.State state) = pm.markets(0);
        assertEq(strike, STRIKE);
        assertEq(exp, expiry);
        assertEq(uint(state), uint(PredictionMarket.State.OPEN));
    }

    function test_createMarket_rejectsExpiredExpiry() public {
        vm.expectRevert("bad expiry");
        pm.createMarket(STRIKE, block.timestamp - 1);
    }

    // ── Position taking ──────────────────────────────────────────────

    function test_takePosition_above() public {
        pm.createMarket(STRIKE, expiry);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        pm.takePosition{value: 1 ether}(0, PredictionMarket.Side.ABOVE);
        (,, uint256 totalAbove,,,) = pm.markets(0);
        assertEq(totalAbove, 1 ether);
    }

    function test_takePosition_below() public {
        pm.createMarket(STRIKE, expiry);
        vm.deal(bob, 0.5 ether);
        vm.prank(bob);
        pm.takePosition{value: 0.5 ether}(0, PredictionMarket.Side.BELOW);
        (,,, uint256 totalBelow,,) = pm.markets(0);
        assertEq(totalBelow, 0.5 ether);
    }

    function test_takePosition_rejectsAfterExpiry() public {
        pm.createMarket(STRIKE, expiry);
        vm.warp(expiry + 1);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert("market expired");
        pm.takePosition{value: 1 ether}(0, PredictionMarket.Side.ABOVE);
    }

    // ── Settlement ───────────────────────────────────────────────────

    function test_settlement_aboveWins() public {
        _setupMarketWithPositions();
        uint256 settledPrice = 3500_00000000;
        vm.prank(creWallet);
        se.executeSettlement(0, settledPrice);
        (,,,, uint256 sp, PredictionMarket.State state) = pm.markets(0);
        assertEq(sp, settledPrice);
        assertEq(uint(state), uint(PredictionMarket.State.SETTLED));
    }

    function test_settlement_rejectsNonCRE() public {
        vm.expectRevert("only CRE forwarder");
        se.executeSettlement(0, STRIKE);
    }

    function test_settlement_rejectsReplay() public {
        _setupMarketWithPositions();
        vm.startPrank(creWallet);
        se.executeSettlement(0, 3500_00000000);
        vm.expectRevert("already settled");
        se.executeSettlement(0, 3500_00000000);
        vm.stopPrank();
    }

    // ── Claim / Payout ───────────────────────────────────────────────

    function test_claim_winnerGetsFullPool() public {
        _setupMarketWithPositions();
        // Alice bet ABOVE 1 ETH, Bob bet BELOW 1 ETH
        // Price $3500 > $3000 strike → ABOVE wins → Alice gets 2 ETH
        vm.prank(creWallet);
        se.executeSettlement(0, 3500_00000000);
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        pm.claim(0);
        assertEq(alice.balance - aliceBefore, 2 ether);
    }

    function test_claim_rejectsLoser() public {
        _setupMarketWithPositions();
        vm.prank(creWallet);
        se.executeSettlement(0, 3500_00000000);
        vm.prank(bob);
        vm.expectRevert("nothing to claim");
        pm.claim(0);
    }
}
