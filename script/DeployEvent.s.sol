// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/EventMarket.sol";
import "../src/EventSettlementEngine.sol";

contract DeployEvent is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address creForwarder = vm.envAddress("CRE_FORWARDER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        EventMarket em = new EventMarket(deployer);
        console.log("EventMarket deployed at:", address(em));

        EventSettlementEngine ese = new EventSettlementEngine(address(em), creForwarder);
        console.log("EventSettlementEngine deployed at:", address(ese));

        em.updateSettlementEngine(address(ese));
        console.log("EventMarket wired to EventSettlementEngine");

        // Create first event market — Binance ETH volume threshold
        string memory question = "Will ETH 24h Binance volume exceed $1B USD at expiry?";
        uint256 expiry = block.timestamp + 24 hours;
        uint256 id = em.createMarket(question, expiry);
        console.log("Event market created, ID:", id);
        console.log("Question: Will ETH 24h Binance volume exceed $1B USD at expiry?");
        console.log("Expiry:", expiry);

        vm.stopBroadcast();

        console.log("=== EVENT DEPLOYMENT SUMMARY ===");
        console.log("EM_ADDRESS=", address(em));
        console.log("ESE_ADDRESS=", address(ese));
        console.log("EVENT_MARKET_ID=0");
    }
}
