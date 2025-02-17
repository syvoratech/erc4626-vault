// SPDX-License-Identifier: GNU
pragma solidity 0.8.28;

interface ILido {
    function submit(address _referral) external payable returns (uint256);
}