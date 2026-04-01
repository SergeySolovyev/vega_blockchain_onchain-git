// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VersionedBeacon} from "../src/VersionedBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {VaultV1} from "../src/VaultV1.sol";
import {VaultV2} from "../src/VaultV2.sol";
import {VaultV3} from "../src/VaultV3.sol";

contract VersionedBeaconTest is Test {
    VersionedBeacon public beacon;
    BeaconProxy public proxyA;
    BeaconProxy public proxyB;
    VaultV1 public implV1;
    VaultV2 public implV2;
    VaultV3 public implV3;

    address public owner = makeAddr("owner");
    address public userA = makeAddr("userA");
    address public userB = makeAddr("userB");

    function setUp() public {
        implV1 = new VaultV1();
        implV2 = new VaultV2();
        implV3 = new VaultV3();

        // Deploy beacon
        vm.prank(owner);
        beacon = new VersionedBeacon(address(implV1), owner);

        // Deploy two BeaconProxy instances sharing the same beacon
        bytes memory initA = abi.encodeCall(VaultV1.initialize, (owner));
        proxyA = new BeaconProxy(address(beacon), initA);

        bytes memory initB = abi.encodeCall(VaultV1.initialize, (owner));
        proxyB = new BeaconProxy(address(beacon), initB);

        vm.deal(userA, 50 ether);
        vm.deal(userB, 50 ether);
    }

    // --- Deployment -----------------------------------------------------

    function test_BeaconInitialState() public view {
        assertEq(beacon.implementation(), address(implV1));
        assertEq(beacon.getVersionCount(), 1);
        assertEq(beacon.currentVersionIndex(), 0);
        assertEq(beacon.getImplementationAt(0), address(implV1));
    }

    // --- Both proxies share the same beacon -----------------------------

    function test_BothProxiesWork() public {
        vm.prank(userA);
        VaultV1(address(proxyA)).deposit{value: 1 ether}();

        vm.prank(userB);
        VaultV1(address(proxyB)).deposit{value: 2 ether}();

        // Each proxy has independent storage
        assertEq(VaultV1(address(proxyA)).balanceOf(userA), 1 ether);
        assertEq(VaultV1(address(proxyB)).balanceOf(userB), 2 ether);

        // Same version
        assertEq(VaultV1(address(proxyA)).version(), "V1");
        assertEq(VaultV1(address(proxyB)).version(), "V1");
    }

    // --- Upgrade beacon -> both proxies upgraded -------------------------

    function test_BeaconUpgradeAffectsBothProxies() public {
        vm.prank(owner);
        beacon.upgradeTo(address(implV2));

        // Both proxies now use V2
        assertEq(VaultV2(address(proxyA)).version(), "V2");
        assertEq(VaultV2(address(proxyB)).version(), "V2");
        assertEq(beacon.getVersionCount(), 2);
    }

    // --- Version history ------------------------------------------------

    function test_BeaconVersionHistory() public {
        vm.startPrank(owner);
        beacon.upgradeTo(address(implV2));
        beacon.upgradeTo(address(implV3));
        vm.stopPrank();

        address[] memory history = beacon.getVersionHistory();
        assertEq(history.length, 3);
        assertEq(history[0], address(implV1));
        assertEq(history[1], address(implV2));
        assertEq(history[2], address(implV3));
        assertEq(beacon.currentVersionIndex(), 2);
    }

    // --- Rollback -------------------------------------------------------

    function test_BeaconRollback() public {
        // Deposit as V1
        vm.prank(userA);
        VaultV1(address(proxyA)).deposit{value: 5 ether}();

        // Upgrade to V2
        vm.prank(owner);
        beacon.upgradeTo(address(implV2));

        // Rollback to V1
        vm.prank(owner);
        beacon.rollbackTo(0);

        assertEq(beacon.implementation(), address(implV1));
        assertEq(beacon.currentVersionIndex(), 0);
        assertEq(beacon.getVersionCount(), 2); // history unchanged

        // Both proxies rolled back
        assertEq(VaultV1(address(proxyA)).version(), "V1");
        assertEq(VaultV1(address(proxyB)).version(), "V1");

        // State preserved
        assertEq(VaultV1(address(proxyA)).balanceOf(userA), 5 ether);
    }

    // --- Access control -------------------------------------------------

    function test_RevertBeaconUpgradeNotOwner() public {
        vm.prank(userA);
        vm.expectRevert();
        beacon.upgradeTo(address(implV2));
    }

    function test_RevertBeaconRollbackNotOwner() public {
        vm.prank(userA);
        vm.expectRevert();
        beacon.rollbackTo(0);
    }

    function test_RevertBeaconRollbackInvalidIndex() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(VersionedBeacon.InvalidVersionIndex.selector, 10));
        beacon.rollbackTo(10);
    }
}
