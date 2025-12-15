// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {UniswapDemoStopOrderCallback} from "../src/Callback.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title DeployCallback
 * @notice Deployment script for UniswapDemoStopOrderCallback (Callback.sol)
 * @dev This script deploys the Callback contract which receives triggers from Reactive Network
 *      and executes automated trading orders on Uniswap v4
 *
 * Usage:
 * forge script script/DeployCallback.s.sol --rpc-url $RPC_URL --broadcast --verify
 *
 * Or with specific parameters:
 * forge script script/DeployCallback.s.sol:DeployCallback --sig "run(address,address)" \
 *   --rpc-url $RPC_URL --broadcast --verify -- \
 *   0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408 \
 *   0x6f52dFd822A5Fab638e8fF7e9e7B37f030193aC6
 */
contract DeployCallback is Script {
    // Default addresses (can be overridden via parameters)
    address internal constant DEFAULT_POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address internal constant DEFAULT_PRICE_ORACLE = 0x0bB8Dd51273aA4F59b4F4BD26Be153328a5ee89E;

    // Deployed contract address (will be set after deployment)
    address public callbackAddress;
    address public newEraHookAddress;

    /**
     * @notice Main deployment function with default addresses
     * @dev Uses the hardcoded addresses from the original contract
     */
    function run() public returns (address) {
        return run(DEFAULT_POOL_MANAGER, DEFAULT_PRICE_ORACLE);
    }

    /**
     * @notice Deployment function with custom addresses
     * @param poolManagerAddress The address of the Uniswap v4 PoolManager
     * @param priceOracleAddress The address of the PriceOracle contract
     * @return The deployed Callback contract address
     */
    function run(address poolManagerAddress, address priceOracleAddress) public returns (address) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0x151ee9c063332f97069f4f2833c32878a3e35a77070869fae3c0c6050c055528));
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== DEPLOYING CALLBACK CONTRACT ===");
        console2.log("Deployer address:", deployer);
        console2.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        console2.log("Chain ID:", block.chainid);
        console2.log("PoolManager address:", poolManagerAddress);
        console2.log("PriceOracle address:", priceOracleAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy UniswapDemoStopOrderCallback with 0.02 ETH
        console2.log("\nDeploying UniswapDemoStopOrderCallback with 0.02 ETH...");
        UniswapDemoStopOrderCallback callback = new UniswapDemoStopOrderCallback{value: 0.03 ether}(address(0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA));
        callbackAddress = address(callback);
        console2.log("Callback deployed at:", callbackAddress);
        console2.log("Contract balance:", callbackAddress.balance / 1e18, "ETH");

        // Note: The NewEraHook is deployed inside the Origin constructor
        // We can't directly access it from the deployment script, but we know it's created
        console2.log("Note: NewEraHook is deployed internally by the Callback constructor");

        vm.stopBroadcast();

        // Deployment summary
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("Network Chain ID:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("Callback (UniswapDemoStopOrderCallback):", callbackAddress);
        console2.log("Contract Balance:", callbackAddress.balance / 1e18, "ETH");
        console2.log("PoolManager:", poolManagerAddress);
        console2.log("PriceOracle:", priceOracleAddress);
        console2.log("========================\n");

        // Save deployment info
        saveDeploymentInfo(callbackAddress, poolManagerAddress, priceOracleAddress, deployer);

        return callbackAddress;
    }

    /**
     * @notice Save deployment information to a file for easy reference
     */
    function saveDeploymentInfo(
        address callbackAddress_,
        address poolManagerAddress,
        address priceOracleAddress,
        address deployer
    ) internal {
        string memory output = string(abi.encodePacked(
            "// Callback Contract Deployment Information\n",
            "// Generated on: ", vm.toString(block.timestamp), "\n",
            "// Network Chain ID: ", vm.toString(block.chainid), "\n\n",
            "Callback Address: ", vm.toString(callbackAddress_), "\n",
            "Contract Balance: 0.02 ETH\n",
            "PoolManager Address: ", vm.toString(poolManagerAddress), "\n",
            "PriceOracle Address: ", vm.toString(priceOracleAddress), "\n",
            "Deployer Address: ", vm.toString(deployer), "\n"
        ));

        // vm.writeFile("./callback_deployment_info.txt", output);
        // console2.log("Deployment information saved to callback_deployment_info.txt");
    }

    /**
     * @notice Verify the deployed contract by checking its state
     * @param callbackAddress_ The address of the deployed Callback contract
     */
    function verifyDeployment(address callbackAddress_) public view {
        console2.log("=== VERIFYING DEPLOYMENT ===");
        console2.log("Callback contract address:", callbackAddress_);
        console2.log("Callback contract balance:", callbackAddress_.balance / 1e18, "ETH");
        console2.log("Callback contract code size:", callbackAddress_.code.length, "bytes");

        // Check if contract has code deployed
        if (callbackAddress_.code.length > 0) {
            console2.log(" Contract code is deployed");
        } else {
            console2.log(" No contract code found at address");
        }

        console2.log("========================\n");
    }
}
