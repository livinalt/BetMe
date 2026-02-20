# CRE-Powered Prediction Market Settlement Engine

> Automated, verifiable ETH/USD prediction market settlement using Chainlink CRE on Base Sepolia.

## Overview

This project demonstrates a minimal but production-aware prediction market where settlement is fully automated by Chainlink CRE — no admin keys, no manual intervention, no centralized oracle owner.

**The core flow:**
1. A prediction market is created on-chain with a strike price and expiry
2. Users take ABOVE or BELOW positions by depositing ETH
3. At expiry, CRE automatically fetches ETH/USD from 3 independent sources, computes a tamper-resistant median, and submits a signed settlement transaction
4. Winners claim their proportional share of the pool permissionlessly

## Architecture
```
┌─────────────────────────────────────────────────────┐
│                 CRE WORKFLOW                         │
│                                                      │
│  Trigger: cron every 5 min                          │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ Binance  │  │CoinGecko │  │ Gate.io  │  HTTP     │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       └─────────────┴──────────────┘                 │
│                 Median Compute                        │
│                 Sign + Submit TX                      │
└─────────────────────┬───────────────────────────────┘
                      │ executeSettlement()
                      ▼
┌─────────────────────────────────────────────────────┐
│              Base Sepolia                            │
│  PredictionMarket.sol ←── SettlementEngine.sol      │
│  (positions, payouts)      (CRE forwarder, replay)  │
└─────────────────────────────────────────────────────┘
```

## Why Median Aggregation?

With 3 price sources, the median is the middle value after sorting. A single compromised or spiking source cannot shift the result — an attacker must corrupt at least 2 of 3 sources simultaneously.
```
Example:
  Binance:   $1963
  CoinGecko: $1963  ← median (correct)
  Gate.io:   $9999  ← spike/attack ignored

  Median: $1963  ✅
  Mean:   $4641  ❌
```

## Deployed Contracts (Base Sepolia)

| Contract | Address |
|---|---|
| PredictionMarket | `0xD8846806e200604428E6c40f6c3ed6B80c3a70DF` |
| SettlementEngine | `0xA32d2AD94b9C1795d44385F16Bf5366131e0F362` |

- [PredictionMarket on Basescan](https://sepolia.basescan.org/address/0xD8846806e200604428E6c40f6c3ed6B80c3a70DF)
- [SettlementEngine on Basescan](https://sepolia.basescan.org/address/0xA32d2AD94b9C1795d44385F16Bf5366131e0F362)

## Smart Contract Design

### PredictionMarket.sol
- Creates markets with a strike price and expiry timestamp
- Accepts ETH positions on ABOVE or BELOW
- Settles only when called by the authorized SettlementEngine
- Pays winners proportionally from the total pool
- Replay-safe: settled markets cannot be re-settled

### SettlementEngine.sol
- Accepts settlement calls only from the CRE forwarder address
- Payload replay protection via `keccak256(marketId, price)` mapping
- Single entry point between CRE and the market contract
- Owner can rotate the CRE forwarder address if needed

## CRE Integration

The CRE job spec is in `cre/job-spec.toml`. It defines:

1. **Trigger** — cron every 5 minutes
2. **check_expiry** — blockchain_read task reads on-chain market state; exits if not ready
3. **fetch_binance / fetch_coingecko / fetch_gateio** — parallel HTTP tasks
4. **compute_median** — built-in CRE median task, multiplies by 1e8 for on-chain decimals
5. **submit_settlement** — eth_tx task calls `SettlementEngine.executeSettlement()`

## Known Simplifications vs Production

| Simplification | Production Equivalent |
|---|---|
| CRE forwarder is a single EOA | DON threshold signature verification (EIP-712) |
| Single market type (ETH/USD) | Generic market factory with any price feed |
| Manual forwarder address allowlist | On-chain DON public key registry |
| 3 HTTP sources | Chainlink Data Streams or additional DON sources |

These are intentional scoping decisions, not oversights. The architecture is designed to make upgrading each layer straightforward.

## Repository Structure
```
cre-prediction-market/
├── src/
│   ├── PredictionMarket.sol    # Core market logic
│   └── SettlementEngine.sol    # CRE entry point + replay protection
├── test/
│   └── PredictionMarket.t.sol  # 10 tests, full coverage
├── script/
│   ├── Deploy.s.sol            # Foundry deploy script
│   └── demo.sh                 # End-to-end live demo
├── cre/
│   ├── job-spec.toml           # CRE workflow definition
│   └── simulate.sh             # Local CRE simulation
└── README.md
```

## Quick Start
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone and install
git clone https://github.com/YOUR_USERNAME/cre-prediction-market
cd cre-prediction-market

# Copy and fill environment
cp .env.example .env
# Edit .env with your PRIVATE_KEY, BASE_SEPOLIA_RPC, etc.

# Run tests
forge test -vv

# Deploy
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast -vv

# Run full demo
bash script/demo.sh

# Run CRE simulation only
bash cre/simulate.sh
```

## Demo Flow
```
bash script/demo.sh

  STEP 1: Create market (strike $3000, expiry 2min)
  STEP 2: Take ABOVE + BELOW positions on-chain
  STEP 3: Wait for expiry
  STEP 4: CRE fetches 3 prices → median → settles on-chain
  STEP 5: Final state verified, winner determined
```

## Test Suite
```bash
forge test -vv

  [PASS] test_createMarket()
  [PASS] test_createMarket_rejectsExpiredExpiry()
  [PASS] test_takePosition_above()
  [PASS] test_takePosition_below()
  [PASS] test_takePosition_rejectsAfterExpiry()
  [PASS] test_settlement_aboveWins()
  [PASS] test_settlement_rejectsNonCRE()
  [PASS] test_settlement_rejectsReplay()
  [PASS] test_claim_winnerGetsFullPool()
  [PASS] test_claim_rejectsLoser()
```

## Judging Checklist

- [x] Blockchain integration — Base Sepolia, live contracts
- [x] External API via CRE — 3 independent price sources
- [x] Automated settlement — CRE job spec triggers on expiry
- [x] Simulation/deployment via CLI — `bash cre/simulate.sh`
- [x] Clean README + demo flow — this document
- [x] Verifiable on-chain — all TXs on Basescan
