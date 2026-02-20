#!/bin/bash
# =============================================================================
# CRE Football Event Market Settlement Simulation
# Question: "Will Adelaide United beat Perth Glory?"
# Fixture ID: 1469658
# Source: API-Football (primary) + score cross-check logic
# Mirrors cre/event-job-spec.toml majority vote pattern exactly
# =============================================================================
set -e
source .env

FIXTURE_ID=1469658
HOME_TEAM="Adelaide United"
AWAY_TEAM="Perth Glory"
QUESTION="Will Adelaide United beat Perth Glory? (Fixture $FIXTURE_ID)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     CRE Football Event Market Settlement Simulation          ║"
echo "║     $QUESTION"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Create fresh football market on-chain ────────────────────
echo "[1/6] Creating football event market on-chain..."

EXPIRY_NOW=$(( $(date +%s) + 10 ))

CREATE_OUTPUT=$(cast send $EM_ADDRESS \
  "createMarket(string,uint256)" \
  "$QUESTION" $EXPIRY_NOW \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json)

TX_CREATE=$(echo $CREATE_OUTPUT | jq -r '.transactionHash')

# Get the new market ID
FOOTBALL_MARKET_ID=$(cast call $EM_ADDRESS \
  "nextMarketId()(uint256)" \
  --rpc-url $BASE_SEPOLIA_RPC)
FOOTBALL_MARKET_ID=$(( FOOTBALL_MARKET_ID - 1 ))

echo "      Market ID: $FOOTBALL_MARKET_ID"
echo "      Question:  $QUESTION"
echo "      TX: https://sepolia.basescan.org/tx/$TX_CREATE"
echo ""

# ── Step 2: Take positions ───────────────────────────────────────────
echo "[2/6] Taking positions on-chain..."

cast send $EM_ADDRESS \
  "takePosition(uint256,uint8)" \
  $FOOTBALL_MARKET_ID 0 \
  --value 0.001ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC > /dev/null

echo "      YES position: 0.001 ETH (Adelaide United wins)"
echo "      NO  position: skipped (single wallet demo)"
echo ""

# ── Step 3: Wait for expiry ──────────────────────────────────────────
echo "[3/6] Waiting for market expiry..."
sleep 12
echo "      ✅ Market expired"
echo ""

# ── Step 4: Fetch match result from API-Football (3 independent checks) ──
echo "[4/6] Fetching match result from API-Football..."
echo "      Fixture: $FIXTURE_ID ($HOME_TEAM vs $AWAY_TEAM)"
echo ""

FIXTURE_DATA=$(curl -s \
  -H "x-apisports-key: $FOOTBALL_API_KEY" \
  "https://v3.football.api-sports.io/fixtures?id=$FIXTURE_ID")

STATUS=$(echo $FIXTURE_DATA | jq -r '.response[0].fixture.status.short')
HOME_SCORE=$(echo $FIXTURE_DATA | jq -r '.response[0].goals.home')
AWAY_SCORE=$(echo $FIXTURE_DATA | jq -r '.response[0].goals.away')
HOME_NAME=$(echo $FIXTURE_DATA | jq -r '.response[0].teams.home.name')
AWAY_NAME=$(echo $FIXTURE_DATA | jq -r '.response[0].teams.away.name')

echo "      Match:  $HOME_NAME vs $AWAY_NAME"
echo "      Score:  $HOME_SCORE - $AWAY_SCORE"
echo "      Status: $STATUS"
echo ""

# ── Step 5: Majority vote (3 independent evaluations of same data) ───
# CRE pattern: each evaluation is an independent task
# Source 1: final status check
# Source 2: home score > away score check  
# Source 3: home team winner flag from API

echo "[5/6] Majority vote across 3 independent evaluations..."

YES_VOTES=0

# Evaluation 1: match status is FT (full time)
if [ "$STATUS" = "FT" ] || [ "$STATUS" = "AET" ] || [ "$STATUS" = "PEN" ]; then
  FINISHED=true
else
  FINISHED=false
fi

# Evaluation 2: home score > away score
if [ "$FINISHED" = true ] && [ "$HOME_SCORE" -gt "$AWAY_SCORE" ] 2>/dev/null; then
  echo "      Check 1 (score comparison):  YES ✅ ($HOME_SCORE > $AWAY_SCORE)"
  YES_VOTES=$(( YES_VOTES + 1 ))
else
  echo "      Check 1 (score comparison):  NO  ❌"
fi

# Evaluation 2: API winner flag for home team
HOME_WINNER=$(echo $FIXTURE_DATA | jq -r '.response[0].teams.home.winner')
if [ "$HOME_WINNER" = "true" ]; then
  echo "      Check 2 (API winner flag):   YES ✅"
  YES_VOTES=$(( YES_VOTES + 1 ))
else
  echo "      Check 2 (API winner flag):   NO  ❌ ($HOME_WINNER)"
fi

# Evaluation 3: score difference > 0
SCORE_DIFF=$(( HOME_SCORE - AWAY_SCORE ))
if [ "$FINISHED" = true ] && [ "$SCORE_DIFF" -gt 0 ] 2>/dev/null; then
  echo "      Check 3 (score difference):  YES ✅ (diff: +$SCORE_DIFF)"
  YES_VOTES=$(( YES_VOTES + 1 ))
else
  echo "      Check 3 (score difference):  NO  ❌"
fi

echo ""
echo "      YES votes: $YES_VOTES / 3"

# Map to outcome
if [ "$FINISHED" = false ]; then
  OUTCOME_VAL=3
  OUTCOME_LABEL="INVALID (match not finished yet)"
elif [ "$YES_VOTES" -ge 2 ]; then
  OUTCOME_VAL=1
  OUTCOME_LABEL="YES ✅ ($HOME_TEAM won $HOME_SCORE-$AWAY_SCORE)"
else
  OUTCOME_VAL=2
  OUTCOME_LABEL="NO ❌ ($HOME_TEAM did not win)"
fi

echo "      Outcome: $OUTCOME_LABEL"
echo ""

# ── Step 6: Submit settlement ─────────────────────────────────────────
echo "[6/6] Submitting to EventSettlementEngine..."
echo "      Call: executeSettlement($FOOTBALL_MARKET_ID, $OUTCOME_VAL)"

TX=$(cast send $ESE_ADDRESS \
  "executeSettlement(uint256,uint8)" \
  $FOOTBALL_MARKET_ID $OUTCOME_VAL \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json | jq -r '.transactionHash')

echo "      TX:   $TX"
echo "      Link: https://sepolia.basescan.org/tx/$TX"

sleep 3

FINAL=$(cast call $EM_ADDRESS \
  "markets(uint256)(bytes32,string,uint256,uint256,uint256,uint8)" \
  $FOOTBALL_MARKET_ID \
  --rpc-url $BASE_SEPOLIA_RPC)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  FOOTBALL SETTLEMENT COMPLETE                                ║"
printf "║  Match:   %-50s║\n" "$HOME_TEAM vs $AWAY_TEAM"
printf "║  Score:   %-50s║\n" "$HOME_SCORE - $AWAY_SCORE ($STATUS)"
printf "║  Outcome: %-50s║\n" "$OUTCOME_LABEL"
printf "║  TX: %-56s║\n" "$TX"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Verify on Basescan:"
echo "  Contract: https://sepolia.basescan.org/address/$EM_ADDRESS"
echo "  TX:       https://sepolia.basescan.org/tx/$TX"
echo ""
