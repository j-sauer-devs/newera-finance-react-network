// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BasicCronContract} from "../src/Cron.sol";

/**
 * @title DeployReactive
 * @notice Deployment script for BasicCronContract (Cron.sol) on Reactive Network
 * @dev This script deploys the reactive contract that monitors cron events and triggers callbacks
 *
 * Usage:
 * forge script script/DeployReactive.s.sol --rpc-url $REACTIVE_RPC_URL --broadcast --verify
 *
 * Or with specific parameters:
 * forge script script/DeployReactive.s.sol:DeployReactive --sig "run(uint256,address,uint256,uint256)" \
 *   --rpc-url $REACTIVE_RPC_URL --broadcast --verify -- \
 *   0xcron_topic_here \
 *   0xcallback_address_here \
 *   0xorigin_chain_id \
 *   0xdestination_chain_id
 */
contract DeployReactive is Script {
    // Reactive Network system contract address
    address internal constant REACTIVE_SYSTEM_CONTRACT = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    // Default parameters (can be overridden via parameters)
    uint256 internal constant DEFAULT_CRON_TOPIC = 0x9d4ac5c34a3b7c24c57b7f2e3a9c3d9a8c7b5e4f2a1d8c6e9b4a7f3e2c5d8a9f6e; // Example cron topic
    address internal constant DEFAULT_CALLBACK_ADDRESS = 0x020dD0882F9132824bc3e5d539136D9BaacdFEd3; // Will be updated after callback deployment
    uint256 internal constant DEFAULT_ORIGIN_CHAIN_ID = 0; // Reactive Network
    uint256 internal constant DEFAULT_DESTINATION_CHAIN_ID = 1; // Ethereum Mainnet

    // Deployed contract address (will be set after deployment)
    address public reactiveContractAddress;

    /**
     * @notice Main deployment function with default addresses
     * @dev Uses the default parameters for deployment
     */
    function run() public returns (address) {
        return run(
            DEFAULT_CRON_TOPIC,
            DEFAULT_CALLBACK_ADDRESS,
            DEFAULT_ORIGIN_CHAIN_ID,
            DEFAULT_DESTINATION_CHAIN_ID
        );
    }

    /**
     * @notice Deployment function with custom parameters
     * @param cronTopic The topic to subscribe to for cron events
     * @param callbackAddress The callback contract address on destination chain
     * @param originChainId The chain ID where the reactive contract is deployed
     * @param destinationChainId The chain ID where callback contract is deployed
     * @return The deployed reactive contract address
     */
    function run(
        uint256 cronTopic,
        address callbackAddress,
        uint256 originChainId,
        uint256 destinationChainId
    ) public returns (address) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0x151ee9c063332f97069f4f2833c32878a3e35a77070869fae3c0c6050c055528));
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== DEPLOYING REACTIVE CONTRACT ===");
        console2.log("Deployer address:", deployer);
        console2.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        console2.log("Chain ID:", block.chainid);
        console2.log("Cron Topic:", vm.toString(cronTopic));
        console2.log("Callback Address:", callbackAddress);
        console2.log("Origin Chain ID:", originChainId);
        console2.log("Destination Chain ID:", destinationChainId);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy BasicCronContract with 0.1 ETH for gas
        console2.log("\nDeploying BasicCronContract with 0.1 ETH...");
        BasicCronContract reactiveContract = new BasicCronContract{value: 0.1 ether}(
            REACTIVE_SYSTEM_CONTRACT,
            cronTopic,
            callbackAddress,
            originChainId,
            destinationChainId
        );
        reactiveContractAddress = address(reactiveContract);
        console2.log("Reactive contract deployed at:", reactiveContractAddress);
        console2.log("Contract balance:", reactiveContractAddress.balance / 1e18, "ETH");

        vm.stopBroadcast();

        // Deployment summary
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("Network Chain ID:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("Reactive Contract (BasicCronContract):", reactiveContractAddress);
        console2.log("Contract Balance:", reactiveContractAddress.balance / 1e18, "ETH");
        console2.log("Cron Topic:", vm.toString(cronTopic));
        console2.log("Callback Address:", callbackAddress);
        console2.log("Origin Chain ID:", originChainId);
        console2.log("Destination Chain ID:", destinationChainId);
        console2.log("========================\n");

        // Save deployment info
        saveDeploymentInfo(
            reactiveContractAddress,
            cronTopic,
            callbackAddress,
            originChainId,
            destinationChainId,
            deployer
        );

        return reactiveContractAddress;
    }

    /**
     * @notice Save deployment information to a file for easy reference
     */
    function saveDeploymentInfo(
        address reactiveAddress,
        uint256 cronTopic,
        address callbackAddress,
        uint256 originChainId,
        uint256 destinationChainId,
        address deployer
    ) internal {
        string memory output = string(abi.encodePacked(
            "// Reactive Contract Deployment Information\n",
            "// Generated on: ", vm.toString(block.timestamp), "\n",
            "// Network Chain ID: ", vm.toString(block.chainid), "\n\n",
            "Reactive Contract Address: ", vm.toString(reactiveAddress), "\n",
            "Contract Balance: 0.1 ETH\n",
            "Cron Topic: ", vm.toString(cronTopic), "\n",
            "Callback Address: ", vm.toString(callbackAddress), "\n",
            "Origin Chain ID: ", vm.toString(originChainId), "\n",
            "Destination Chain ID: ", vm.toString(destinationChainId), "\n",
            "Deployer Address: ", vm.toString(deployer), "\n"
        ));

        // vm.writeFile("./reactive_deployment_info.txt", output);
        // console2.log("Deployment information saved to reactive_deployment_info.txt");
    }

    /**
     * @notice Verify the deployed contract by checking its state
     * @param reactiveAddress The address of the deployed reactive contract
     */
    function verifyDeployment(address reactiveAddress) public view {
        console2.log("=== VERIFYING REACTIVE DEPLOYMENT ===");
        console2.log("Reactive contract address:", reactiveAddress);
        console2.log("Reactive contract balance:", reactiveAddress.balance / 1e18, "ETH");
        console2.log("Reactive contract code size:", reactiveAddress.code.length, "bytes");

        // Check if contract has code deployed
        if (reactiveAddress.code.length > 0) {
            console2.log(" Contract code is deployed");
        } else {
            console2.log(" No contract code found at address");
        }

        console2.log("========================\n");
    }
}
