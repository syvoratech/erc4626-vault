// SPDX-License-Identifier: GNU
pragma solidity 0.8.28;

interface ILido {
    function submit(address _referral) external payable returns (uint256);

    function balanceOf(address account) external view returns (uint);

    function approve(address user, uint256 amount) external returns (bool);

    function getPooledEthByShares(
        uint256 _sharesAmount
    ) external view returns (uint256);
}
