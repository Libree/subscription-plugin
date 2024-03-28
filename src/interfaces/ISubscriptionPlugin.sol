// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {UserOperation} from "@eth-infinitism/account-abstraction/interfaces/UserOperation.sol";

interface ISubscriptionPlugin {
    enum FunctionId {
        RUNTIME_VALIDATION_OWNER_OR_SELF,
        USER_OP_VALIDATION_OWNER
    }

    /**
     *
     * @notice Emitted when user subscribe to nft
     * @dev This event is emitted when a new subscriber of NFT is added
     * @param subscription subscription address
     * @param account account to subscribe to the subscription
     */
    event AccountSubscribed(address subscription, address account);

    /**
     *
     * @notice Emitted when user unsubscribe to nft
     * @dev This event is emitted when a subscriber of NFT is removed
     * @param subscription subscription address
     * @param account account to unsubscribe to the subscription
     */
    event AccountUnsubscribed(address subscription, address account);

    /**
     * @notice Emitted when user update subscription payment
     * @dev This event is emitted when payment is updated
     * @param subscription subscription address
     * @param account account to unsubscribe to the subscription
     */
    event SubscriptionPayment(address subscription, address account);

    // error handlers

    error NotValidAddress(address subscription);
    error NotValidSubscriptionNFT(address subscription);
    error InsufficientBalance();
    error AlreadySubscribed(address account, address subscription);
    error AlreadyUnsubscribed(address account, address subscription);
    error AccountNotSubscribed(address account, address subscription);
    error SubscriptionNotFound(address subscription);
    error SubscriptionIsActive(address account, address subscription, uint256 lastPayment, uint256 currentDate);

    /**
     * @notice sender subscribe to a subcription
     * @param service subscription which sender will subscribe
     */
    function subscribe(address service) external;

    /**
     * @notice sender unsubscribe to a subcription
     * @param service subscription which sender will unsubscribe
     */
    function unsubscribe(address service) external;

    /**
     * @notice sender update subcription payment
     * @param service subscription which sender will update payment
     */
    function paySubscription(address service) external;
}
