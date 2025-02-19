## MyVault (ERC4626 + Lido Staking)

MyVault is an ERC4626‐compliant, UUPS‐upgradeable vault that stakes WETH on Lido, automatically managing deposits, redemptions, and fees. It combines the following components:

    ERC4626Upgradeable: Standard interface for tokenized vaults.
    AccessControlUpgradeable: Role-based access for admins and fee managers.
    UUPSUpgradeable: Allows upgradeability via a proxy contract.
    ReentrancyGuardUpgradeable: Prevents reentrant calls to critical functions.

### Key Features

    Deposit Flow
        User calls deposit(assets, receiver) or mint(shares, receiver).
        Vault pulls WETH from the user.
        Vault unwraps WETH to ETH (using IWETH.withdraw).
        Vault stakes ETH into Lido via lido.submit{value: netAmount}.
        Vault mints ERC4626 shares to the user.

    Redeem Flow
        User calls redeem(shares, receiver, owner) or withdraw(assets, receiver, owner).
        Vault calculates the user’s proportion of stETH/ETH.
        Vault requests and claims ETH from Lido via the withdrawalQueue contract.
        Vault deducts fees (based on feeBasisPoints).
        Vault transfers net WETH to the user.

    Fees
        A feeBasisPoints parameter determines the fee taken on redemption or withdrawal.
        For example, if feeBasisPoints = 100, the fee is 1% of the redeemed amount.

    Gas Buffer
        On deposit, the contract reserves a small amount of ETH (gasBuffer) to cover potential gas usage for the Lido submit call (e.g., 0.02 ETH).
        This buffer ensures the contract call doesn’t fail due to insufficient gas.

    Access Control
        DEFAULT_ADMIN_ROLE / VAULT_ADMIN: Can upgrade the contract and manage roles.
        FEE_MANAGER: Can change the feeBasisPoints.

    Upgradeability
        The contract is deployed via a UUPS proxy.
        The _authorizeUpgrade function ensures only addresses with the VAULT_ADMIN role can upgrade the implementation.

### Contract Roles & Permissions

    Admin (VAULT_ADMIN):
        Has DEFAULT_ADMIN_ROLE.
        Can upgrade the contract.
        Can grant/revoke roles.

    Fee Manager (FEE_MANAGER):
        Can set the feeBasisPoints.

### Contract Flow Overview

    Initialization (initialize):
        Takes _admin, _lido, _withdrawalQueue, _feeBasisPoints.
        Sets up roles and configures references to Lido, the withdrawal queue, and WETH.

    Deposit / Mint:
        Pull WETH from user.
        Unwrap to ETH.
        Stake in Lido.
        Mint vault shares.

    Withdraw / Redeem:
        Burn vault shares.
        Request and claim ETH from Lido.
        Convert to WETH if needed.
        Deduct fees, transfer net to user.

    Fee Calculation:
        Fees are taken as a percentage of the redeemed assets (in basis points).

    Upgrade:
        Only an admin with VAULT_ADMIN role can call _authorizeUpgrade.

### Deployment & Usage

    Deploy Contracts
    `forge script script/DeployVault.s.sol:DeployVault --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast`

    Initialize:
        Call initialize(_admin, _lido, _withdrawalQueue, _feeBasisPoints) so the vault is fully set up.

    Interact:
        Deposit: vault.deposit(wethAmount, user)
        Redeem: vault.redeem(shares, receiver, owner)
        Withdraw: vault.withdraw(assets, receiver, owner)
        Mint: vault.mint(shares, receiver)

### Security Considerations

    Reentrancy:
    The vault uses nonReentrant to guard external entry points.

    Approvals:
        Ensure the user has approved the vault to transfer WETH.
        The vault must approve the withdrawal queue for stETH redemptions.

    Upgrade Risks:
        Because this contract is upgradeable, keep the upgrade admin role in a secure address or a multisig.

    Gas Buffer:
        The fixed 0.02 ETH buffer is an estimate. Large changes in gas price or call complexity could break assumptions.

### Testing & Verification

    Test with Foundry:
        Unit tests should cover deposit, redeem, fee calculations, upgrade, etc.
    Verify Onchain:
        Use forge verify-contract (or another tool) to verify both the implementation and the proxy (if necessary) on Etherscan or your preferred explorer.