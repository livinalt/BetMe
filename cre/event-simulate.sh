#!/bin/bash
# =============================================================================
# CRE Event Market Settlement Simulation
# Event: Will ETH 24h Binance volume exceed $1B USD?
# Mirrors cre/event-job-spec.toml exactly
# =============================================================================
set -e
source .env

THRESHOLD=1000000000  # $1 billion

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     CRE Event Market Settlement Simulation                   ║"
echo "║     Event: ETH 24h Volume > \$1B?                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Read on-chain market state ──────────────────────────────
echo "[1/5] Reading on-chain event market state..."
STATE=$(cast call $EM_ADDRESS \
  "markets(uint256)(bytes32,string,uint256,uint256,uint256,uint8)" \
  $EVENT_MARKET_ID \
  --rpc-url $BASE_SEPOLIA_RPC)
echo "      $STATE"

OUTCOME=$(echo $STATE | grep -oP '\d+$')
if [ "$OUTCOME" != "0" ]; then
  echo "✗  Market already resolved. Exiting."
  exit 0
fi
echo "      Status: UNRESOLVED — proceeding"
echo ""

# ── Step 2: Fetch volumes from 3 sources ────────────────────────────
echo "[2/5] Fetching 24h ETH volume from 3 sources..."

BINANCE_VOL=$(curl -s "https://api.binance.com/api/v3/ticker/24hr?symbol=ETHUSDT" \
  | jq -r '.quoteVolume' | cut -d. -f1)

COINGECKO_VOL=$(curl -s "https://api.coingecko.com/api/v3/coins/ethereum/market_chart?vs_currency=usd&days=1" \
  | jq -r '.total_volumes[-1][1]' | cut -d. -f1)

GATEIO_VOL=$(curl -s "https://api.gateio.ws/api/v4/spot/tickers?currency_pair=ETH_USDT" \
  | jq -r '.[0].quote_volume' | cut -d. -f1)

echo "      Binance:   \$$BINANCE_VOL"
echo "      CoinGecko: \$$COINGECKO_VOL"
echo "      Gate.io:   \$$GATEIO_VOL"
echo "      Threshold: \$$THRESHOLD (1 billion)"
echo ""

# ── Step 3: Evaluate each source (majority vote) ─────────────────────
echo "[3/5] Evaluating against threshold (majority vote)..."

YES_VOTES=0

if [ "$BINANCE_VOL" -ge "$THRESHOLD" ] 2>/dev/null; then
  echo "      Binance:   YES ✅"
  YES_VOTES=$(( YES_VOTES + 1 ))
else
  echo "      Binance:   NO  ❌"
fi

if [ "$COINGECKO_VOL" -ge "$THRESHOLD" ] 2>/dev/null; then
  echo "      CoinGecko: YES ✅"
  YES_VOTES=$(( YES_VOTES + 1 ))
else
  echo "      CoinGecko: NO  ❌"
fi

if [ "$GATEIO_VOL" -ge "$THRESHOLD" ] 2>/dev/null; then
  echo "      Gate.io:   YES ✅"
  YES_VOTES=$(( YES_VOTES + 1 ))
else
  echo "      Gate.io:   NO  ❌"
fi

echo ""
echo "      YES votes: $YES_VOTES / 3"

# Map to outcome: >=2 YES=1, <2 NO=2, fetch failure=INVALID=3
if [ -z "$BINANCE_VOL" ] || [ -z "$COINGECKO_VOL" ] || [ -z "$GATEIO_VOL" ]; then
  OUTCOME_VAL=3
  OUTCOME_LABEL="INVALID (fetch failure)"
elif [ "$YES_VOTES" -ge 2 ]; then
  OUTCOME_VAL=1
  OUTCOME_LABEL="YES ✅ (volume exceeded \$1B)"
else
  OUTCOME_VAL=2
  OUTCOME_LABEL="NO ❌ (volume below \$1B)"
fi

echo "      Outcome:   $OUTCOME_LABEL"
echo ""

# ── Step 4: Submit settlement ─────────────────────────────────────────
echo "[4/5] Submitting to EventSettlementEngine..."
echo "      Call: executeSettlement($EVENT_MARKET_ID, $OUTCOME_VAL)"

TX=$(cast send $ESE_ADDRESS \
  "executeSettlement(uint256,uint8)" \
  $EVENT_MARKET_ID $OUTCOME_VAL \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json | jq -r '.transactionHash')

echo "      TX:   $TX"
echo "      Link: https://sepolia.basescan.org/tx/$TX"
echo ""

# ── Step 5: Verify ────────────────────────────────────────────────────
echo "[5/5] Verifying on-chain..."
sleep 3

FINAL=$(cast call $EM_ADDRESS \
  "markets(uint256)(bytes32,string,uint256,uint256,uint256,uint8)" \
  $EVENT_MARKET_ID \
  --rpc-url $BASE_SEPOLIA_RPC)
echo "      Final state: $FINAL"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  EVENT SETTLEMENT COMPLETE                                   ║"
printf "║  Outcome: %-51s║\n" "$OUTCOME_LABEL"
printf "║  TX: %-56s║\n" "$TX"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
