// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title VersionedProxy -- Transparent-style proxy with on-chain version history and rollback
/// @notice Maintains an array of all implementation addresses and allows the admin to upgrade
///         or roll back to any previously deployed version (like "git checkout").
/// @dev Uses ERC-7201 namespaced storage for version data to avoid collisions with implementation storage.
///      Admin calls are routed to proxy functions; all other calls are delegated to the current implementation.
contract VersionedProxy is Proxy {
    // --- ERC-7201 Namespaced Storage ------------------------------------

    /// @custom:storage-location erc7201:onchain-git.proxy.version
    struct VersionStorage {
        address[] versionHistory;
        uint256 currentVersionIndex;
    }

    // keccak256(abi.encode(uint256(keccak256("onchain-git.proxy.version")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VERSION_STORAGE_LOCATION =
        0x05a33aac1e40ed84d97f97a60374e32d3a12481deb06be3da25dc299224eab00;

    function _getVersionStorage() private pure returns (VersionStorage storage vs) {
        bytes32 slot = VERSION_STORAGE_LOCATION;
        assembly {
            vs.slot := slot
        }
    }

    // --- State ----------------------------------------------------------

    /// @notice The admin address (set once at deployment, cannot be changed).
    address public immutable admin;

    // --- Errors ---------------------------------------------------------

    error NotAdmin();
    error InvalidVersionIndex(uint256 index);

    // --- Events ---------------------------------------------------------

    event Upgraded(address indexed implementation, uint256 indexed versionIndex);
    event RolledBack(uint256 indexed fromIndex, uint256 indexed toIndex);

    // --- Modifiers ------------------------------------------------------

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // --- Constructor ----------------------------------------------------

    /// @param implementation_ Address of the first implementation contract.
    /// @param admin_          Address that will manage upgrades and rollbacks.
    /// @param data            Optional calldata for initializing the implementation via delegatecall.
    constructor(address implementation_, address admin_, bytes memory data) {
        admin = admin_;
        _upgradeToVersion(implementation_);

        if (data.length > 0) {
            Address.functionDelegateCall(implementation_, data);
        }
    }

    // --- Admin: Upgrade -------------------------------------------------

    /// @notice Deploy a new version. Appends to versionHistory and switches to it.
    /// @param newImplementation Address of the new implementation contract.
    function upgradeTo(address newImplementation) external onlyAdmin {
        _upgradeToVersion(newImplementation);
    }

    /// @notice Deploy a new version and call an initialization function on it.
    /// @param newImplementation Address of the new implementation contract.
    /// @param data              Calldata for the initialization delegatecall.
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable onlyAdmin {
        _upgradeToVersion(newImplementation);
        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        }
    }

    // --- Admin: Rollback ------------------------------------------------

    /// @notice Switch the active implementation to a previously stored version.
    /// @param versionIndex Index in the versionHistory array.
    function rollbackTo(uint256 versionIndex) external onlyAdmin {
        VersionStorage storage vs = _getVersionStorage();
        if (versionIndex >= vs.versionHistory.length) {
            revert InvalidVersionIndex(versionIndex);
        }

        uint256 oldIndex = vs.currentVersionIndex;
        vs.currentVersionIndex = versionIndex;

        // Update the ERC-1967 implementation slot
        ERC1967Utils.upgradeToAndCall(vs.versionHistory[versionIndex], "");

        emit RolledBack(oldIndex, versionIndex);
    }

    // --- View: Version Info ---------------------------------------------

    /// @notice Returns all stored implementation addresses.
    function getVersionHistory() external view returns (address[] memory) {
        return _getVersionStorage().versionHistory;
    }

    /// @notice Returns the index of the currently active implementation.
    function getCurrentVersionIndex() external view returns (uint256) {
        return _getVersionStorage().currentVersionIndex;
    }

    /// @notice Returns the total number of versions ever deployed.
    function getVersionCount() external view returns (uint256) {
        return _getVersionStorage().versionHistory.length;
    }

    /// @notice Returns the implementation address at a given version index.
    function getImplementationAt(uint256 index) external view returns (address) {
        VersionStorage storage vs = _getVersionStorage();
        if (index >= vs.versionHistory.length) {
            revert InvalidVersionIndex(index);
        }
        return vs.versionHistory[index];
    }

    /// @notice Returns the currently active implementation address (ERC-1967 slot).
    function implementation() external view returns (address) {
        return _implementation();
    }

    // --- Proxy Internals ------------------------------------------------

    /// @dev Returns the current implementation from the ERC-1967 storage slot.
    function _implementation() internal view override returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @dev Appends a new implementation to versionHistory and sets it as current.
    function _upgradeToVersion(address newImpl) internal {
        VersionStorage storage vs = _getVersionStorage();
        vs.versionHistory.push(newImpl);
        vs.currentVersionIndex = vs.versionHistory.length - 1;

        // Write to the ERC-1967 slot and emit the standard Upgraded event
        ERC1967Utils.upgradeToAndCall(newImpl, "");

        emit Upgraded(newImpl, vs.currentVersionIndex);
    }

    /// @dev Accept plain ETH transfers (delegated to implementation via fallback).
    receive() external payable {}
}
