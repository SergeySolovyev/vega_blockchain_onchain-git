// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultV1} from "./VaultV1.sol";

/// @title VaultV2 -- Adds a withdrawal fee (basis points)
/// @dev Extends VaultStorage by appending new fields (safe for proxy upgrade).
contract VaultV2 is VaultV1 {
    // --- Extended ERC-7201 Storage (appended fields) --------------------

    /// @custom:storage-location erc7201:onchain-git.vault.v2
    struct VaultV2Storage {
        uint256 feeBps;       // fee in basis points (e.g. 100 = 1%)
        uint256 feeCollected; // accumulated fees
    }

    // keccak256(abi.encode(uint256(keccak256("onchain-git.vault.v2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant V2_STORAGE_LOCATION =
        0xe96fb02fb6108924ce97e586654059a5aeff25096d6a824c7f504fcf33a18600;

    function _getV2Storage() internal pure returns (VaultV2Storage storage s) {
        bytes32 slot = V2_STORAGE_LOCATION;
        assembly {
            s.slot := slot
        }
    }

    // --- Errors ---------------------------------------------------------

    error NotOwner();
    error FeeTooHigh(uint256 feeBps);

    // --- Events ---------------------------------------------------------

    event FeeUpdated(uint256 newFeeBps);
    event FeesCollected(address indexed to, uint256 amount);

    // --- Modifiers ------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != _getVaultStorage().owner) revert NotOwner();
        _;
    }

    // --- Initialization for V2-specific fields --------------------------

    /// @notice Call after upgrading to V2 to set the initial fee.
    function initializeV2(uint256 feeBps_) external reinitializer(2) {
        if (feeBps_ > 1000) revert FeeTooHigh(feeBps_); // max 10%
        _getV2Storage().feeBps = feeBps_;
    }

    // --- Overridden Logic -----------------------------------------------

    /// @notice Withdraw with a fee deducted. Fee stays in the contract.
    function withdraw(uint256 amount) external override {
        VaultStorage storage vs = _getVaultStorage();
        uint256 balance = vs.balances[msg.sender];
        if (amount > balance) revert InsufficientBalance(amount, balance);

        VaultV2Storage storage v2s = _getV2Storage();
        uint256 fee = (amount * v2s.feeBps) / 10_000;
        uint256 payout = amount - fee;

        vs.balances[msg.sender] -= amount;
        vs.totalDeposits -= amount;
        v2s.feeCollected += fee;

        (bool success,) = msg.sender.call{value: payout}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(msg.sender, payout);
    }

    // --- Fee Management -------------------------------------------------

    function setFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > 1000) revert FeeTooHigh(newFeeBps);
        _getV2Storage().feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }

    function collectFees(address to) external onlyOwner {
        VaultV2Storage storage v2s = _getV2Storage();
        uint256 amount = v2s.feeCollected;
        v2s.feeCollected = 0;

        (bool success,) = to.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit FeesCollected(to, amount);
    }

    // --- Views ----------------------------------------------------------

    function feeBps() external view returns (uint256) {
        return _getV2Storage().feeBps;
    }

    function feeCollected() external view returns (uint256) {
        return _getV2Storage().feeCollected;
    }

    function version() external pure virtual override returns (string memory) {
        return "V2";
    }
}
