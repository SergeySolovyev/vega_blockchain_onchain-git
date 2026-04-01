// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {VersionedProxy} from "../src/VersionedProxy.sol";
import {VaultV1} from "../src/VaultV1.sol";
import {VaultV2} from "../src/VaultV2.sol";
import {VaultV3} from "../src/VaultV3.sol";

contract VersionedProxyTest is Test {
    VersionedProxy public proxy;
    VaultV1 public implV1;
    VaultV2 public implV2;
    VaultV3 public implV3;

    address public admin = makeAddr("admin");
    address public user = makeAddr("user");

    function setUp() public {
        // Deploy implementations
        implV1 = new VaultV1();
        implV2 = new VaultV2();
        implV3 = new VaultV3();

        // Deploy proxy pointing to V1, with initialization
        bytes memory initData = abi.encodeCall(VaultV1.initialize, (admin));
        vm.prank(admin);
        proxy = new VersionedProxy(address(implV1), admin, initData);

        // Fund user for deposits
        vm.deal(user, 100 ether);
    }

    // --- Deployment -----------------------------------------------------

    function test_InitialState() public view {
        assertEq(proxy.admin(), admin);
        assertEq(proxy.implementation(), address(implV1));
        assertEq(proxy.getVersionCount(), 1);
        assertEq(proxy.getCurrentVersionIndex(), 0);
        assertEq(proxy.getImplementationAt(0), address(implV1));
    }

    function test_InitializedVault() public view {
        VaultV1 vault = VaultV1(address(proxy));
        assertEq(vault.owner(), admin);
        assertEq(vault.totalDeposits(), 0);
    }

    // --- Deposit / Withdraw via proxy (V1) ------------------------------

    function test_DepositAndWithdraw() public {
        VaultV1 vault = VaultV1(address(proxy));

        vm.startPrank(user);
        vault.deposit{value: 5 ether}();
        assertEq(vault.balanceOf(user), 5 ether);
        assertEq(vault.totalDeposits(), 5 ether);

        vault.withdraw(2 ether);
        assertEq(vault.balanceOf(user), 3 ether);
        vm.stopPrank();
    }

    function test_VersionString_V1() public view {
        VaultV1 vault = VaultV1(address(proxy));
        assertEq(vault.version(), "V1");
    }

    function test_RevertZeroDeposit() public {
        VaultV1 vault = VaultV1(address(proxy));
        vm.prank(user);
        vm.expectRevert(VaultV1.ZeroDeposit.selector);
        vault.deposit{value: 0}();
    }

    function test_RevertInsufficientBalance() public {
        VaultV1 vault = VaultV1(address(proxy));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultV1.InsufficientBalance.selector, 1 ether, 0));
        vault.withdraw(1 ether);
    }

    // --- Upgrade to V2 -------------------------------------------------

    function test_UpgradeToV2() public {
        // Deposit as V1
        vm.prank(user);
        VaultV1(address(proxy)).deposit{value: 10 ether}();

        // Upgrade to V2 with fee init
        bytes memory v2Init = abi.encodeCall(VaultV2.initializeV2, (200)); // 2% fee
        vm.prank(admin);
        proxy.upgradeToAndCall(address(implV2), v2Init);

        // Verify upgrade
        assertEq(proxy.implementation(), address(implV2));
        assertEq(proxy.getVersionCount(), 2);
        assertEq(proxy.getCurrentVersionIndex(), 1);

        // State preserved
        VaultV2 vault = VaultV2(address(proxy));
        assertEq(vault.balanceOf(user), 10 ether);
        assertEq(vault.version(), "V2");
        assertEq(vault.feeBps(), 200);
    }

    function test_V2_WithdrawFee() public {
        // Deposit, upgrade, then withdraw with fee
        vm.prank(user);
        VaultV1(address(proxy)).deposit{value: 10 ether}();

        bytes memory v2Init = abi.encodeCall(VaultV2.initializeV2, (200)); // 2%
        vm.prank(admin);
        proxy.upgradeToAndCall(address(implV2), v2Init);

        VaultV2 vault = VaultV2(address(proxy));
        uint256 balanceBefore = user.balance;

        vm.prank(user);
        vault.withdraw(1 ether);

        // User receives 0.98 ETH (1 - 2% fee)
        assertEq(user.balance - balanceBefore, 0.98 ether);
        // Fee collected
        assertEq(vault.feeCollected(), 0.02 ether);
        // Balance updated fully
        assertEq(vault.balanceOf(user), 9 ether);
    }

    // --- Upgrade to V3 -------------------------------------------------

    function test_UpgradeToV3() public {
        // V1 -> V2 -> V3
        vm.startPrank(admin);
        proxy.upgradeToAndCall(address(implV2), abi.encodeCall(VaultV2.initializeV2, (100)));
        proxy.upgradeToAndCall(address(implV3), abi.encodeCall(VaultV3.initializeV3, (50 ether)));
        vm.stopPrank();

        assertEq(proxy.getVersionCount(), 3);
        assertEq(proxy.getCurrentVersionIndex(), 2);

        VaultV3 vault = VaultV3(address(proxy));
        assertEq(vault.version(), "V3");
        assertEq(vault.maxDepositCap(), 50 ether);
    }

    function test_V3_DepositCap() public {
        vm.startPrank(admin);
        proxy.upgradeToAndCall(address(implV2), abi.encodeCall(VaultV2.initializeV2, (0)));
        proxy.upgradeToAndCall(address(implV3), abi.encodeCall(VaultV3.initializeV3, (5 ether)));
        vm.stopPrank();

        VaultV3 vault = VaultV3(address(proxy));

        // Deposit within cap
        vm.prank(user);
        vault.deposit{value: 3 ether}();
        assertEq(vault.balanceOf(user), 3 ether);

        // Deposit exceeding cap
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultV3.DepositCapExceeded.selector, 6 ether, 5 ether));
        vault.deposit{value: 3 ether}();
    }

    // --- Rollback -------------------------------------------------------

    function test_RollbackToV1() public {
        // Deposit as V1
        vm.prank(user);
        VaultV1(address(proxy)).deposit{value: 5 ether}();

        // Upgrade to V2
        vm.prank(admin);
        proxy.upgradeToAndCall(address(implV2), abi.encodeCall(VaultV2.initializeV2, (200)));

        // Rollback to V1
        vm.prank(admin);
        proxy.rollbackTo(0);

        assertEq(proxy.implementation(), address(implV1));
        assertEq(proxy.getCurrentVersionIndex(), 0);
        assertEq(proxy.getVersionCount(), 2); // history unchanged

        // State still intact
        VaultV1 vault = VaultV1(address(proxy));
        assertEq(vault.balanceOf(user), 5 ether);
        assertEq(vault.version(), "V1");

        // Can withdraw without fee (V1 logic)
        uint256 balanceBefore = user.balance;
        vm.prank(user);
        vault.withdraw(5 ether);
        assertEq(user.balance - balanceBefore, 5 ether); // full amount, no fee
    }

    function test_RollbackToV2_FromV3() public {
        // V1 -> V2 -> V3 -> rollback to V2
        vm.startPrank(admin);
        proxy.upgradeToAndCall(address(implV2), abi.encodeCall(VaultV2.initializeV2, (100)));
        proxy.upgradeToAndCall(address(implV3), abi.encodeCall(VaultV3.initializeV3, (50 ether)));
        proxy.rollbackTo(1); // back to V2
        vm.stopPrank();

        assertEq(proxy.implementation(), address(implV2));
        assertEq(proxy.getCurrentVersionIndex(), 1);
        assertEq(VaultV2(address(proxy)).version(), "V2");
    }

    function test_RollbackAndUpgradeAgain() public {
        // V1 -> V2 -> rollback to V1 -> upgrade to V3
        vm.startPrank(admin);
        proxy.upgradeToAndCall(address(implV2), abi.encodeCall(VaultV2.initializeV2, (100)));
        proxy.rollbackTo(0);
        proxy.upgradeToAndCall(address(implV3), abi.encodeCall(VaultV3.initializeV3, (100 ether)));
        vm.stopPrank();

        assertEq(proxy.getVersionCount(), 3); // V1, V2, V3
        assertEq(proxy.getCurrentVersionIndex(), 2);
        assertEq(proxy.implementation(), address(implV3));
    }

    // --- Version History ------------------------------------------------

    function test_VersionHistoryTracking() public {
        vm.startPrank(admin);
        proxy.upgradeTo(address(implV2));
        proxy.upgradeTo(address(implV3));
        vm.stopPrank();

        address[] memory history = proxy.getVersionHistory();
        assertEq(history.length, 3);
        assertEq(history[0], address(implV1));
        assertEq(history[1], address(implV2));
        assertEq(history[2], address(implV3));
    }

    // --- Access Control -------------------------------------------------

    function test_RevertUpgradeNotAdmin() public {
        vm.prank(user);
        vm.expectRevert(VersionedProxy.NotAdmin.selector);
        proxy.upgradeTo(address(implV2));
    }

    function test_RevertRollbackNotAdmin() public {
        vm.prank(user);
        vm.expectRevert(VersionedProxy.NotAdmin.selector);
        proxy.rollbackTo(0);
    }

    function test_RevertRollbackInvalidIndex() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VersionedProxy.InvalidVersionIndex.selector, 5));
        proxy.rollbackTo(5);
    }

    // --- Events ---------------------------------------------------------

    function test_EmitUpgradedEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(proxy));
        emit VersionedProxy.Upgraded(address(implV2), 1);
        proxy.upgradeTo(address(implV2));
    }

    function test_EmitRolledBackEvent() public {
        vm.prank(admin);
        proxy.upgradeTo(address(implV2));

        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(proxy));
        emit VersionedProxy.RolledBack(1, 0);
        proxy.rollbackTo(0);
    }

    // --- Edge Cases -----------------------------------------------------

    function test_RollbackToCurrentVersion() public {
        vm.prank(admin);
        proxy.rollbackTo(0); // rollback to same version -- should be a no-op
        assertEq(proxy.getCurrentVersionIndex(), 0);
    }

    function test_MultipleDepositsAcrossUpgrades() public {
        // Deposit as V1
        vm.prank(user);
        VaultV1(address(proxy)).deposit{value: 3 ether}();

        // Upgrade to V2
        vm.prank(admin);
        proxy.upgradeToAndCall(address(implV2), abi.encodeCall(VaultV2.initializeV2, (0)));

        // Deposit as V2
        vm.prank(user);
        VaultV2(address(proxy)).deposit{value: 2 ether}();

        // Total balance preserved
        assertEq(VaultV2(address(proxy)).balanceOf(user), 5 ether);
        assertEq(VaultV2(address(proxy)).totalDeposits(), 5 ether);
    }
}
