// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultV2} from "./VaultV2.sol";

/// @title VaultV3 -- Adds a maximum deposit cap
/// @dev Extends the storage chain: VaultV1 (base) -> VaultV2 (fee) -> VaultV3 (cap).
contract VaultV3 is VaultV2 {
    // --- Extended ERC-7201 Storage --------------------------------------

    /// @custom:storage-location erc7201:onchain-git.vault.v3
    struct VaultV3Storage {
        uint256 maxDepositCap; // max ETH the vault can hold (0 = unlimited)
    }

    // keccak256(abi.encode(uint256(keccak256("onchain-git.vault.v3")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant V3_STORAGE_LOCATION =
        0x6dde7cb02db004d9ba50ff0729e10131b7b85ffc7c3c51e977f56ff1dceeff00;

    function _getV3Storage() internal pure returns (VaultV3Storage storage s) {
        bytes32 slot = V3_STORAGE_LOCATION;
        assembly {
            s.slot := slot
        }
    }

    // --- Errors ---------------------------------------------------------

    error DepositCapExceeded(uint256 totalAfter, uint256 cap);

    // --- Events ---------------------------------------------------------

    event DepositCapUpdated(uint256 newCap);

    // --- Initialization -------------------------------------------------

    /// @notice Call after upgrading to V3 to set the deposit cap.
    function initializeV3(uint256 maxDepositCap_) external reinitializer(3) {
        _getV3Storage().maxDepositCap = maxDepositCap_;
    }

    // --- Overridden Logic -----------------------------------------------

    /// @notice Deposit with a cap check.
    function deposit() external payable override {
        if (msg.value == 0) revert ZeroDeposit();

        VaultStorage storage vs = _getVaultStorage();
        VaultV3Storage storage v3s = _getV3Storage();

        uint256 newTotal = vs.totalDeposits + msg.value;
        if (v3s.maxDepositCap > 0 && newTotal > v3s.maxDepositCap) {
            revert DepositCapExceeded(newTotal, v3s.maxDepositCap);
        }

        vs.balances[msg.sender] += msg.value;
        vs.totalDeposits = newTotal;

        emit Deposited(msg.sender, msg.value);
    }

    // --- Cap Management -------------------------------------------------

    function setDepositCap(uint256 newCap) external onlyOwner {
        _getV3Storage().maxDepositCap = newCap;
        emit DepositCapUpdated(newCap);
    }

    // --- Views ----------------------------------------------------------

    function maxDepositCap() external view returns (uint256) {
        return _getV3Storage().maxDepositCap;
    }

    function version() external pure override returns (string memory) {
        return "V3";
    }
}
