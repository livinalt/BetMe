// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PredictionMarket.sol";
import "../src/SettlementEngine.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address creForwarder = vm.envAddress("CRE_FORWARDER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy PredictionMarket with deployer as temp settler
        address deployer = vm.addr(deployerPrivateKey);
        PredictionMarket pm = new PredictionMarket(deployer);
        console.log("PredictionMarket deployed at:", address(pm));

        // Step 2: Deploy SettlementEngine pointing to PredictionMarket
        SettlementEngine se = new SettlementEngine(address(pm), creForwarder);
        console.log("SettlementEngine deployed at:", address(se));

        // Step 3: Update PredictionMarket to use SettlementEngine
        pm.updateSettlementEngine(address(se));
        console.log("PredictionMarket wired to SettlementEngine");

        // Step 4: Create the first market — ETH/USD, strike $3000, expiry 24h from now
        uint256 strike = 3000_00000000; // $3000 in 8 decimals
        uint256 expiry = block.timestamp + 24 hours;
        uint256 marketId = pm.createMarket(strike, expiry);
        console.log("Market created with ID:", marketId);
        console.log("Strike price: $3000.00 (8 decimals)");
        console.log("Expiry timestamp:", expiry);

        vm.stopBroadcast();

        // Print summary for easy copy-paste into .env
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("PM_ADDRESS=", address(pm));
        console.log("SE_ADDRESS=", address(se));
        console.log("MARKET_ID=0");
        console.log("EXPIRY=", expiry);
    }
}
