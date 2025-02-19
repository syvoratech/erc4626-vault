// SPDX-License-Identifier: GNU
pragma solidity 0.8.28;

interface IWETH {
    // --- Core WETH Functions ---
    function deposit() external payable;

    function withdraw(uint wad) external;

    // --- ERC-20 Functions ---
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address dst, uint wad) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint);

    function approve(address guy, uint wad) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint wad
    ) external returns (bool);

    // --- ERC-20 Metadata ---
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    // --- Events ---
    event Transfer(address indexed src, address indexed dst, uint wad);
    event Approval(address indexed src, address indexed guy, uint wad);
    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);
}
