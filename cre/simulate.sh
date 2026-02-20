#!/bin/bash
# =============================================================================
# CRE Settlement Simulation Script
# Sources: Binance, CoinGecko, Gate.io
# Mirrors cre/job-spec.toml logic exactly.
# Usage: bash cre/simulate.sh
# =============================================================================
set -e

source .env

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     CRE Prediction Market Settlement Simulation          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Read on-chain market state ──────────────────────────────────────
echo "[1/5] Reading on-chain market state..."
MARKET_STATE=$(cast call $PM_ADDRESS \
  "markets(uint256)((uint256,uint256,uint256,uint256,uint256,uint8))" \
  $MARKET_ID \
  --rpc-url $BASE_SEPOLIA_RPC)

echo "      Raw state: $MARKET_STATE"

NOW=$(date +%s)
STATE=$(echo $MARKET_STATE | grep -oP '\d+' | tail -1)
EXPIRY=$(echo $MARKET_STATE | grep -oP '\d{10}' | head -1)

echo "      Now:       $NOW"
echo "      Expiry:    $EXPIRY"
echo "      State:     $STATE (0=OPEN 1=SETTLED)"

if [ "$STATE" = "1" ]; then
  echo ""
  echo "✗  Market already settled. Exiting."
  exit 0
fi

if [ "$NOW" -lt "$EXPIRY" ]; then
  echo ""
  echo "⏳  Market not expired yet ($(( EXPIRY - NOW ))s remaining)."
  echo "    Continuing for demo purposes..."
fi

# ── Step 2: Fetch prices from 3 sources ─────────────────────────────────────
echo ""
echo "[2/5] Fetching ETH/USD from 3 independent sources..."

BINANCE=$(curl -s "https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT" \
  | jq -r '.price' | cut -d. -f1)

COINGECKO=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd" \
  | jq -r '.ethereum.usd' | cut -d. -f1)

GATEIO=$(curl -s "https://api.gateio.ws/api/v4/spot/tickers?currency_pair=ETH_USDT" \
  | jq -r '.[0].last' | cut -d. -f1)

echo "      Binance:   \$$BINANCE"
echo "      CoinGecko: \$$COINGECKO"
echo "      Gate.io:   \$$GATEIO"

# ── Step 3: Compute median ───────────────────────────────────────────────────
echo ""
echo "[3/5] Computing median..."

SORTED=$(echo -e "$BINANCE\n$COINGECKO\n$GATEIO" | sort -n)
MEDIAN=$(echo "$SORTED" | sed -n '2p')
MEDIAN_8DEC=$(echo "$MEDIAN * 100000000" | bc)

echo "      Sorted:    [$(echo $SORTED | tr ' ' ',')]"
echo "      Median:    \$$MEDIAN"
echo "      On-chain:  $MEDIAN_8DEC (8 decimals)"

# ── Step 4: Submit settlement ────────────────────────────────────────────────
echo ""
echo "[4/5] Submitting settlement via SettlementEngine..."
echo "      Contract:  $SE_ADDRESS"
echo "      Call:      executeSettlement($MARKET_ID, $MEDIAN_8DEC)"

TX=$(cast send $SE_ADDRESS \
  "executeSettlement(uint256,uint256)" \
  $MARKET_ID $MEDIAN_8DEC \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json | jq -r '.transactionHash')

echo "      TX Hash:   $TX"
echo "      Explorer:  https://sepolia.basescan.org/tx/$TX"

# ── Step 5: Verify on-chain ──────────────────────────────────────────────────
echo ""
echo "[5/5] Verifying final market state..."
sleep 3

FINAL=$(cast call $PM_ADDRESS \
  "markets(uint256)((uint256,uint256,uint256,uint256,uint256,uint8))" \
  $MARKET_ID \
  --rpc-url $BASE_SEPOLIA_RPC)

echo "      Final state: $FINAL"

STRIKE=300000000000
if [ "$MEDIAN_8DEC" -ge "$STRIKE" ]; then
  WINNER="ABOVE ▲  (ETH finished above \$3000)"
else
  WINNER="BELOW ▼  (ETH finished below \$3000)"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  SETTLEMENT COMPLETE                                     ║"
printf "║  Settled Price: \$%-40s║\n" "$MEDIAN"
printf "║  Strike Price:  \$%-40s║\n" "3000"
printf "║  Winner:        %-41s║\n" "$WINNER"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Verify on Basescan:"
echo "  Market:  https://sepolia.basescan.org/address/$PM_ADDRESS"
echo "  TX:      https://sepolia.basescan.org/tx/$TX"
echo ""
