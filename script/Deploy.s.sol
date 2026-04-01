// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VersionedProxy} from "../src/VersionedProxy.sol";
import {VaultV1} from "../src/VaultV1.sol";

/// @notice Deploys VaultV1 implementation + VersionedProxy pointing to it.
/// @dev Usage: forge script script/Deploy.s.sol --rpc-url $RPC --broadcast --private-key $PK
contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Deploy V1 implementation
        VaultV1 implV1 = new VaultV1();
        console.log("VaultV1 implementation:", address(implV1));

        // 2. Deploy proxy with V1 and initialize
        bytes memory initData = abi.encodeCall(VaultV1.initialize, (msg.sender));
        VersionedProxy proxy = new VersionedProxy(address(implV1), msg.sender, initData);
        console.log("VersionedProxy:", address(proxy));
        console.log("Admin:", msg.sender);

        // Verify
        console.log("Implementation:", proxy.implementation());
        console.log("Version count:", proxy.getVersionCount());

        vm.stopBroadcast();
    }
}
