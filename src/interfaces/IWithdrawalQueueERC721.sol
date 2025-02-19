// SPDX-License-Identifier: GNU
pragma solidity 0.8.28;

interface IWithdrawalQueueERC721 {
    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 _requestId) external;
}
