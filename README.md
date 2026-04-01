# Onchain Git -- Upgradeable Proxy with Version History

HW7: version control system for upgradeable smart contracts using proxy patterns.

## Overview

A custom proxy contract that maintains a full history of implementation addresses
and supports rollback to any previous version. Built on OpenZeppelin V5 and Foundry.

### Contracts

| Contract | Purpose |
|---|---|
| `VersionedProxy` | Transparent-style proxy with `versionHistory[]`, `currentVersionIndex`, `upgradeTo`, `rollbackTo` |
| `VersionedBeacon` | Beacon proxy variant with the same versioning and rollback (Extra) |
| `VaultV1` | Base ETH vault: deposit, withdraw, balanceOf |
| `VaultV2` | Adds withdrawal fee (basis points) |
| `VaultV3` | Adds maximum deposit cap |

### Storage safety

All implementation contracts use ERC-7201 namespaced storage to avoid
slot collisions across proxy upgrades. Each version uses a separate namespace:

- `onchain-git.vault` -- base vault fields (balances, totalDeposits, owner)
- `onchain-git.vault.v2` -- fee-related fields (feeBps, feeCollected)
- `onchain-git.vault.v3` -- cap field (maxDepositCap)

The proxy itself stores version data in namespace `onchain-git.proxy.version`.

## Setup

```
git clone https://github.com/SergeySolovyev/vega_blockchain_onchain-git.git
cd vega_blockchain_onchain-git
forge install
```

## Build and test

```
forge build
forge test -vv
```

## Deploy (local anvil example)

```
anvil &
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key <KEY>
```

## Upgrade

```
PROXY_ADDRESS=0x... forge script script/Upgrade.s.sol:UpgradeToV2Script \
  --rpc-url http://127.0.0.1:8545 --broadcast --private-key <KEY>
```

## Rollback

```
PROXY_ADDRESS=0x... VERSION_INDEX=0 forge script script/Upgrade.s.sol:RollbackScript \
  --rpc-url http://127.0.0.1:8545 --broadcast --private-key <KEY>
```

## Dependencies

- Solidity 0.8.26
- OpenZeppelin Contracts V5
- Foundry (forge, cast, anvil)
