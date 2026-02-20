#!/bin/bash
# =============================================================================
# CRE Prediction Market — Full End-to-End Demo
# Shows: market creation → position taking → CRE settlement → claim
# Usage: bash script/demo.sh
# =============================================================================
set -e
source .env

STRIKE=300000000000        # $3000 in 8 decimals
EXPIRY=$(( $(date +%s) + 120 ))  # 2 minutes from now

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        CRE-Powered Prediction Market — Live Demo             ║"
echo "║        Network: Base Sepolia | Chain ID: 84532               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Contracts:"
echo "  PredictionMarket: https://sepolia.basescan.org/address/$PM_ADDRESS"
echo "  SettlementEngine: https://sepolia.basescan.org/address/$SE_ADDRESS"
echo ""

# ── Step 1: Create a fresh market ───────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Create prediction market"
echo "  Strike: \$3000 | Expiry: 2 minutes from now"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CREATE_TX=$(cast send $PM_ADDRESS \
  "createMarket(uint256,uint256)" \
  $STRIKE $EXPIRY \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json | jq -r '.transactionHash')

# Get new market ID (nextMarketId - 1)
DEMO_MARKET_ID=$(cast call $PM_ADDRESS "nextMarketId()(uint256)" --rpc-url $BASE_SEPOLIA_RPC)
DEMO_MARKET_ID=$(( DEMO_MARKET_ID - 1 ))

echo "  ✅ Market $DEMO_MARKET_ID created"
echo "  TX: https://sepolia.basescan.org/tx/$CREATE_TX"
echo ""

# ── Step 2: Take positions ───────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Take positions (ABOVE and BELOW)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ABOVE_TX=$(cast send $PM_ADDRESS \
  "takePosition(uint256,uint8)" \
  $DEMO_MARKET_ID 0 \
  --value 0.002ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json | jq -r '.transactionHash')

echo "  ✅ ABOVE position: 0.002 ETH"
echo "  TX: https://sepolia.basescan.org/tx/$ABOVE_TX"

BELOW_TX=$(cast send $PM_ADDRESS \
  "takePosition(uint256,uint8)" \
  $DEMO_MARKET_ID 1 \
  --value 0.001ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json | jq -r '.transactionHash')

echo "  ✅ BELOW position: 0.001 ETH"
echo "  TX: https://sepolia.basescan.org/tx/$BELOW_TX"

# Show pool state
STATE=$(cast call $PM_ADDRESS \
  "markets(uint256)((uint256,uint256,uint256,uint256,uint256,uint8))" \
  $DEMO_MARKET_ID \
  --rpc-url $BASE_SEPOLIA_RPC)
echo ""
echo "  Pool state: $STATE"
echo ""

# ── Step 3: Wait for expiry ──────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Waiting for market expiry (2 minutes)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for i in $(seq 120 -10 10); do
  echo -ne "  ⏳ $i seconds remaining...\r"
  sleep 10
done
echo "  ✅ Market expired                    "
echo ""

# ── Step 4: CRE settlement (simulate) ───────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: CRE Workflow — Fetch prices + Settle"
echo "  (Mirrors cre/job-spec.toml tasks exactly)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "  Fetching from 3 independent sources..."
BINANCE=$(curl -s "https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT" \
  | jq -r '.price' | cut -d. -f1)
COINGECKO=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd" \
  | jq -r '.ethereum.usd' | cut -d. -f1)
GATEIO=$(curl -s "https://api.gateio.ws/api/v4/spot/tickers?currency_pair=ETH_USDT" \
  | jq -r '.[0].last' | cut -d. -f1)

echo "  Binance:   \$$BINANCE"
echo "  CoinGecko: \$$COINGECKO"
echo "  Gate.io:   \$$GATEIO"

MEDIAN=$(echo -e "$BINANCE\n$COINGECKO\n$GATEIO" | sort -n | sed -n '2p')
MEDIAN_8DEC=$(echo "$MEDIAN * 100000000" | bc)

echo "  Median:    \$$MEDIAN → $MEDIAN_8DEC (8 dec)"
echo ""

SETTLE_TX=$(cast send $SE_ADDRESS \
  "executeSettlement(uint256,uint256)" \
  $DEMO_MARKET_ID $MEDIAN_8DEC \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC \
  --json | jq -r '.transactionHash')

echo "  ✅ Settlement submitted"
echo "  TX: https://sepolia.basescan.org/tx/$SETTLE_TX"
echo ""

# ── Step 5: Verify and show winner ──────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Final state + Winner"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sleep 3
FINAL=$(cast call $PM_ADDRESS \
  "markets(uint256)((uint256,uint256,uint256,uint256,uint256,uint8))" \
  $DEMO_MARKET_ID \
  --rpc-url $BASE_SEPOLIA_RPC)

echo "  Final state: $FINAL"

if [ "$MEDIAN_8DEC" -ge "$STRIKE" ]; then
  WINNER="ABOVE ▲ — ETH stayed above \$3000"
else
  WINNER="BELOW ▼ — ETH settled below \$3000"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  DEMO COMPLETE — MARKET SETTLED ON-CHAIN                     ║"
printf "║  ETH Price:    \$%-46s║\n" "$MEDIAN"
printf "║  Strike:       \$%-46s║\n" "3000"
printf "║  Result:       %-47s║\n" "$WINNER"
printf "║  Settlement TX: %-44s║\n" "$SETTLE_TX"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Basescan links:"
echo "  Market contract: https://sepolia.basescan.org/address/$PM_ADDRESS"
echo "  Settlement TX:   https://sepolia.basescan.org/tx/$SETTLE_TX"
echo ""
