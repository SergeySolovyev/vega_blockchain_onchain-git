// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VersionedProxy} from "../src/VersionedProxy.sol";
import {VaultV2} from "../src/VaultV2.sol";
import {VaultV3} from "../src/VaultV3.sol";

/// @notice Upgrades the proxy from V1 -> V2, then V2 -> V3.
/// @dev Set PROXY_ADDRESS env var to the deployed proxy.
///      Usage: forge script script/Upgrade.s.sol --rpc-url $RPC --broadcast --private-key $PK
contract UpgradeToV2Script is Script {
    function run() external {
        address proxyAddr = vm.envAddress("PROXY_ADDRESS");
        VersionedProxy proxy = VersionedProxy(payable(proxyAddr));

        vm.startBroadcast();

        // Deploy V2 implementation
        VaultV2 implV2 = new VaultV2();
        console.log("VaultV2 implementation:", address(implV2));

        // Upgrade proxy to V2 with 1% fee
        bytes memory initData = abi.encodeCall(VaultV2.initializeV2, (100));
        proxy.upgradeToAndCall(address(implV2), initData);

        console.log("Upgraded to V2. Version count:", proxy.getVersionCount());
        console.log("Current implementation:", proxy.implementation());

        vm.stopBroadcast();
    }
}

contract UpgradeToV3Script is Script {
    function run() external {
        address proxyAddr = vm.envAddress("PROXY_ADDRESS");
        VersionedProxy proxy = VersionedProxy(payable(proxyAddr));

        vm.startBroadcast();

        // Deploy V3 implementation
        VaultV3 implV3 = new VaultV3();
        console.log("VaultV3 implementation:", address(implV3));

        // Upgrade proxy to V3 with 100 ETH cap
        bytes memory initData = abi.encodeCall(VaultV3.initializeV3, (100 ether));
        proxy.upgradeToAndCall(address(implV3), initData);

        console.log("Upgraded to V3. Version count:", proxy.getVersionCount());
        console.log("Current implementation:", proxy.implementation());

        vm.stopBroadcast();
    }
}

/// @notice Rolls back to a specific version index.
/// @dev Set PROXY_ADDRESS and VERSION_INDEX env vars.
contract RollbackScript is Script {
    function run() external {
        address proxyAddr = vm.envAddress("PROXY_ADDRESS");
        uint256 versionIndex = vm.envUint("VERSION_INDEX");
        VersionedProxy proxy = VersionedProxy(payable(proxyAddr));

        vm.startBroadcast();

        console.log("Rolling back from version", proxy.getCurrentVersionIndex());
        console.log("Rolling back to version", versionIndex);

        proxy.rollbackTo(versionIndex);

        console.log("Rollback complete. Implementation:", proxy.implementation());

        vm.stopBroadcast();
    }
}
