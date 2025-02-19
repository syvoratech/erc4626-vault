// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MyVault} from "../src/MyVault.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployVault is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address weth = vm.envAddress("WETH_ADDRESS");
        address lido = vm.envAddress("LIDO_STETH_ADDRESS");
        address withdrawalQueue = vm.envAddress("WITHDRAWAL_QUEUE_ADDRESS");
        uint256 feeBps = vm.envUint("FEE_BASIS_POINTS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation contract
        MyVault vaultImplementation = new MyVault(weth);
        
        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            MyVault.initialize.selector,
            deployer,   // admin
            lido,       // Lido address
            withdrawalQueue, // Withdrawal queue
            feeBps       // Fee basis points
        );

        // 3. Deploy ERC1967 proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(vaultImplementation),
            initData
        );

        vm.stopBroadcast();

        console.log("Successfully deployed contracts:");
        console.log("Implementation address:", address(vaultImplementation));
        console.log("Proxy address:", address(proxy));

        bytes memory implementationArgs = abi.encode(weth);
        bytes memory proxyArgs = abi.encode(address(vaultImplementation), initData);

        console.log("\nVerification commands:");
        console.log("forge verify-contract %s src/MyVault.sol:MyVault --constructor-args %s --rpc-url %s",
            address(vaultImplementation),
            vm.toString(implementationArgs),
            vm.envString("RPC_URL")
        );
        
        console.log("forge verify-contract %s lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --constructor-args %s --rpc-url %s",
            address(proxy),
            vm.toString(proxyArgs),
            vm.envString("RPC_URL")
        );
    }
}