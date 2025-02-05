// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyVault is ERC4626 {
    // Initialize with an ERC20 asset (e.g., WETH)
    constructor(IERC20 asset) ERC4626(asset) ERC20("MyVault", "mVT") {}

    // Override deposit/mint/withdraw/redeem later
}