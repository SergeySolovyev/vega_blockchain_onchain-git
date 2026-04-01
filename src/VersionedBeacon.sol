// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title VersionedBeacon -- Beacon with on-chain version history and rollback
/// @notice Extends OpenZeppelin's UpgradeableBeacon to track every implementation address
///         and allow the owner to roll back to any previous version.
/// @dev Multiple BeaconProxy instances can share this beacon; upgrading the beacon
///      upgrades all proxies simultaneously.
contract VersionedBeacon is UpgradeableBeacon {
    // --- State ----------------------------------------------------------

    address[] public versionHistory;
    uint256 public currentVersionIndex;

    // --- Errors ---------------------------------------------------------

    error InvalidVersionIndex(uint256 index);

    // --- Events ---------------------------------------------------------

    event VersionAdded(address indexed implementation, uint256 indexed versionIndex);
    event RolledBack(uint256 indexed fromIndex, uint256 indexed toIndex);

    // --- Constructor ----------------------------------------------------

    constructor(
        address implementation_,
        address owner_
    ) UpgradeableBeacon(implementation_, owner_) {
        versionHistory.push(implementation_);
        currentVersionIndex = 0;
        emit VersionAdded(implementation_, 0);
    }

    // --- Upgrade (overrides OZ) -----------------------------------------

    /// @notice Upgrade the beacon to a new implementation and record it in version history.
    function upgradeTo(address newImplementation) public override onlyOwner {
        super.upgradeTo(newImplementation);
        versionHistory.push(newImplementation);
        currentVersionIndex = versionHistory.length - 1;
        emit VersionAdded(newImplementation, currentVersionIndex);
    }

    // --- Rollback -------------------------------------------------------

    /// @notice Roll back the beacon to a previously stored implementation.
    /// @param versionIndex Index in the versionHistory array.
    function rollbackTo(uint256 versionIndex) external onlyOwner {
        if (versionIndex >= versionHistory.length) {
            revert InvalidVersionIndex(versionIndex);
        }

        uint256 oldIndex = currentVersionIndex;
        currentVersionIndex = versionIndex;

        // Use the parent's upgradeTo but skip our override to avoid adding a duplicate entry.
        // We call the OZ base directly.
        super.upgradeTo(versionHistory[versionIndex]);

        emit RolledBack(oldIndex, versionIndex);
    }

    // --- Views ----------------------------------------------------------

    function getVersionHistory() external view returns (address[] memory) {
        return versionHistory;
    }

    function getVersionCount() external view returns (uint256) {
        return versionHistory.length;
    }

    function getImplementationAt(uint256 index) external view returns (address) {
        if (index >= versionHistory.length) {
            revert InvalidVersionIndex(index);
        }
        return versionHistory[index];
    }
}
