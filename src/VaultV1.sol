// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title VaultV1 -- Basic ETH vault (deposit / withdraw)
/// @dev Uses ERC-7201 namespaced storage for proxy-safe layout.
contract VaultV1 is Initializable {
    // --- ERC-7201 Namespaced Storage ------------------------------------

    /// @custom:storage-location erc7201:onchain-git.vault
    struct VaultStorage {
        mapping(address => uint256) balances;
        uint256 totalDeposits;
        address owner;
    }

    // keccak256(abi.encode(uint256(keccak256("onchain-git.vault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULT_STORAGE_LOCATION =
        0x80fa312a691c54be25b7a48f1516e999838a05bd7d366f6bf24f0a6128f1cc00;

    function _getVaultStorage() internal pure returns (VaultStorage storage vs) {
        bytes32 slot = VAULT_STORAGE_LOCATION;
        assembly {
            vs.slot := slot
        }
    }

    // --- Errors ---------------------------------------------------------

    error InsufficientBalance(uint256 requested, uint256 available);
    error TransferFailed();
    error ZeroDeposit();

    // --- Events ---------------------------------------------------------

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    // --- Initializer (replaces constructor for proxied contracts) -------

    function initialize(address owner_) external initializer {
        _getVaultStorage().owner = owner_;
    }

    // --- Core Logic -----------------------------------------------------

    /// @notice Deposit ETH into the vault.
    function deposit() external payable virtual {
        if (msg.value == 0) revert ZeroDeposit();

        VaultStorage storage vs = _getVaultStorage();
        vs.balances[msg.sender] += msg.value;
        vs.totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the vault.
    /// @param amount Amount of ETH (in wei) to withdraw.
    function withdraw(uint256 amount) external virtual {
        VaultStorage storage vs = _getVaultStorage();
        uint256 balance = vs.balances[msg.sender];
        if (amount > balance) revert InsufficientBalance(amount, balance);

        vs.balances[msg.sender] -= amount;
        vs.totalDeposits -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    // --- Views ----------------------------------------------------------

    function balanceOf(address account) external view returns (uint256) {
        return _getVaultStorage().balances[account];
    }

    function totalDeposits() external view returns (uint256) {
        return _getVaultStorage().totalDeposits;
    }

    function owner() external view returns (address) {
        return _getVaultStorage().owner;
    }

    function version() external pure virtual returns (string memory) {
        return "V1";
    }
}
