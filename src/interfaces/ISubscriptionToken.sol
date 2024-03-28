// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

interface ISubscriptionToken {
    struct SubscriptionDetails {
        uint256 period;
        uint256 amount;
        address token;
    }

    function getSubscriptionDetails()
        external
        view
        returns (SubscriptionDetails memory);

    function safeTransferFrom(address, address, uint256) external;

    function transferFrom(address, address, uint256) external;

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function ownerOf(uint256 tokenId) external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function tokenOf(address owner) external view returns (uint256);

    function updatePayment(address account, uint256 lastPayment) external;

    function getPayment(address account) external view returns (uint256);

}
