#!/bin/bash
# =============================================================================
# CRE Settlement Simulation — Tenderly Virtual TestNet
# Demonstrates CRE workflow execution with full Tenderly debugger support
# =============================================================================
set -e
source .env

RPC=$TENDERLY_RPC
TENDERLY_EXPLORER="https://dashboard.tenderly.co/tx/base-sepolia"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     CRE Settlement — Tenderly Virtual TestNet            ║"
echo "║     Full execution traces available in dashboard         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Create fresh market ──────────────────────────────────────
echo "[1/6] Creating fresh market on Tenderly Virtual TestNet..."
EXPIRY=$(( $(date +%s) + 300 ))

CREATE_TX=$(cast send $PM_ADDRESS \
  "createMarket(uint256,uint256)" \
  300000000000 $EXPIRY \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC \
  --json | jq -r '.transactionHash')

NEW_MARKET_ID=$(cast call $PM_ADDRESS \
  "nextMarketId()(uint256)" \
  --rpc-url $RPC)
NEW_MARKET_ID=$(( NEW_MARKET_ID - 1 ))

echo "      Market ID: $NEW_MARKET_ID"
echo "      Expiry in: 5 minutes"
echo "      TX: $TENDERLY_EXPLORER/$CREATE_TX"
echo ""

# ── Step 2: Take position ────────────────────────────────────────────
echo "[2/6] Taking ABOVE position..."
POS_TX=$(cast send $PM_ADDRESS \
  "takePosition(uint256,uint8)" \
  $NEW_MARKET_ID 0 \
  --value 0.001ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC \
  --json | jq -r '.transactionHash')

echo "      TX: $TENDERLY_EXPLORER/$POS_TX"
echo ""

# ── Step 3: Verify market state ──────────────────────────────────────
echo "[3/6] Verifying market state on Tenderly..."
STATE=$(cast call $PM_ADDRESS \
  "markets(uint256)((uint256,uint256,uint256,uint256,uint256,uint8))" \
  $NEW_MARKET_ID \
  --rpc-url $RPC)
echo "      State: $STATE"
echo ""

# ── Step 4: Wait for expiry ──────────────────────────────────────────
echo "[4/6] Waiting 5 minutes for market expiry..."
for i in $(seq 300 -15 15); do
  echo -ne "      ⏳ $i seconds remaining...\r"
  sleep 15
done
echo "      ✅ Market expired                    "
echo ""

# ── Step 5: Fetch prices + settle ────────────────────────────────────
echo "[5/6] CRE Workflow — Fetching prices + settling..."

BINANCE=$(curl -s "https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT" \
  | jq -r '.price' | cut -d. -f1)
COINGECKO=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd" \
  | jq -r '.ethereum.usd' | cut -d. -f1)
GATEIO=$(curl -s "https://api.gateio.ws/api/v4/spot/tickers?currency_pair=ETH_USDT" \
  | jq -r '.[0].last' | cut -d. -f1)

echo "      Binance:   \$$BINANCE"
echo "      CoinGecko: \$$COINGECKO"
echo "      Gate.io:   \$$GATEIO"

MEDIAN=$(echo -e "$BINANCE\n$COINGECKO\n$GATEIO" | sort -n | sed -n '2p')
MEDIAN_8DEC=$(echo "$MEDIAN * 100000000" | bc)
echo "      Median:    \$$MEDIAN → $MEDIAN_8DEC (8 dec)"
echo ""

SETTLE_TX=$(cast send $SE_ADDRESS \
  "executeSettlement(uint256,uint256)" \
  $NEW_MARKET_ID $MEDIAN_8DEC \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC \
  --json | jq -r '.transactionHash')

echo "      Settlement TX: $TENDERLY_EXPLORER/$SETTLE_TX"
echo ""

# ── Step 6: Verify final state ───────────────────────────────────────
echo "[6/6] Final state on Tenderly..."
sleep 3

FINAL=$(cast call $PM_ADDRESS \
  "markets(uint256)((uint256,uint256,uint256,uint256,uint256,uint8))" \
  $NEW_MARKET_ID \
  --rpc-url $RPC)

if [ "$MEDIAN_8DEC" -ge "300000000000" ]; then
  WINNER="ABOVE ▲"
else
  WINNER="BELOW ▼"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  TENDERLY SETTLEMENT COMPLETE                            ║"
printf "║  ETH Price:  \$%-44s║\n" "$MEDIAN"
printf "║  Strike:     \$%-44s║\n" "3000"
printf "║  Winner:     %-45s║\n" "$WINNER"
echo "║                                                          ║"
echo "║  View full execution traces in Tenderly dashboard:       ║"
printf "║  %-57s║\n" "$TENDERLY_EXPLORER/$SETTLE_TX"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Tenderly Dashboard: https://dashboard.tenderly.co"
echo ""
