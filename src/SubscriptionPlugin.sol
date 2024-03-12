// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {BasePlugin} from "modular-account/src/plugins/BasePlugin.sol";
import {IPluginExecutor} from "modular-account/src/interfaces/IPluginExecutor.sol";
import {
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    PluginManifest,
    PluginMetadata
} from "modular-account/src/interfaces/IPlugin.sol";
import {IMultiOwnerPlugin} from "modular-account/src/plugins/owner/IMultiOwnerPlugin.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SubscriptionToken, SubscriptionDetails} from "./SubscriptionNFT.sol";

/// @title SubscriptionPlugin
/// @author Libree
/// @notice This plugin lets us subscribe to services!
contract SubscriptionPlugin is BasePlugin {
    // metadata used by the pluginMetadata() method down below
    string public constant NAME = "Subscription Plugin";
    string public constant VERSION = "1.0.0";
    string public constant AUTHOR = "Libree";

    struct Subscriber {
        uint256 tokenId;
        uint256 lastPayment;
    }

    struct SubscriberRegistered {
        uint256 tokenId;
        address account;
        address[] subscriptions;
    }

    struct Subscription {
        mapping(address => Subscriber) subscribers;
        bool isInitialized;
    }

    // this is a constant used in the manifest, to reference our only dependency: the multi owner plugin
    // since it is the first, and only, plugin the index 0 will reference the multi owner plugin
    // we can use this to tell the modular account that we should use the multi owner plugin to validate our user op
    // in other words, we'll say "make sure the person calling increment is an owner of the account using our multiowner plugin"
    uint256 internal constant _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION = 0;

    SubscriberRegistered[] subscribersRegistered;

    // subscribed to nft
    mapping(address => Subscription) private subscriptions;

    /**
     *
     * @notice Emitted when user subscribe to nft
     * @dev This event is emitted when a new subscriber of NFT is added
     * @param subscription subscription address
     * @param account account to subscribe to the subscription
     * @param subscriptionId the subscription id which is equal to tokenId
     */
    event AccountSubscribed(address subscription, address account, uint256 subscriptionId);

    /**
     *
     * @notice Emitted when user unsubscribe to nft
     * @dev This event is emitted when a subscriber of NFT is removed
     * @param subscription subscription address
     * @param account account to unsubscribe to the subscription
     * @param subscriptionId the subscription id which is equal to tokenId
     */
    event AccountUnsubscribed(address subscription, address account, uint256 subscriptionId);

    /**
     * @notice Emitted when user update subscription payment
     * @dev This event is emitted when payment is updated
     * @param subscription subscription address
     * @param account account to unsubscribe to the subscription
     * @param subscriptionId the subscription id which is equal to tokenId
     */
    event SubscriptionPayment(address subscription, address account, uint256 subscriptionId);

    // error handlers

    error NotValidAddress(address subscription);
    error NotValidSubscriptionNFT(address subscription);
    error InsufficientBalance();
    error AlreadySubscribed(address account, address subscription, uint256 tokenId);
    error AlreadyUnsubscribed(address account, address subscription);
    error AccountNotSubscribed(address account, address subscription);
    error SubscriptionNotFound(address subscription);
    error SubscriptionIsActive(address account, address subscription, uint256 lastPayment, uint256 currentDate);

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Execution functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice sender subscribe to a subcription
     * @param service subscription which sender will subscribe
     */
    function subscribe(address service) external {
        (SubscriptionToken subscriptionToken, SubscriptionDetails memory subscriptionDetails) =
            _getSubscriptionDetails(service);
        Subscription storage subscription = subscriptions[service];

        if (subscription.isInitialized && isSubscribed(service, msg.sender)) {
            revert AlreadySubscribed(msg.sender, service, subscription.subscribers[msg.sender].tokenId);
        }

        uint256 accountBalance = IERC20(subscriptionDetails.token).balanceOf(msg.sender);

        if (accountBalance < subscriptionDetails.amount) {
            revert InsufficientBalance();
        }

        IPluginExecutor(subscriptionDetails.token).executeFromPluginExternal(
            msg.sender, subscriptionDetails.amount, "0x"
        );

        uint256 tokenId = subscriptionToken.safeMint(msg.sender);

        if (!subscription.isInitialized) {
            subscription.isInitialized = true;
        }

        subscription.subscribers[msg.sender].tokenId = tokenId;
        subscription.subscribers[msg.sender].lastPayment = block.timestamp;

        (SubscriberRegistered memory subscriberRegistered, uint256 index) = _findSubscriberRegistered(msg.sender);

        if (subscriberRegistered.tokenId == 0) {
            subscriberRegistered.account = msg.sender;
            subscriberRegistered.tokenId = tokenId;
            subscribersRegistered.push(subscriberRegistered);
            subscribersRegistered[subscribersRegistered.length - 1].subscriptions.push(service);
        } else {
            subscribersRegistered[index].subscriptions.push(service);
        }

        emit AccountSubscribed(service, msg.sender, tokenId);
    }

    /**
     * @notice sender unsubscribe to a subcription
     * @param service subscription which sender will unsubscribe
     */
    function unsubscribe(address service) external {
        Subscription storage subscription = subscriptions[service];

        if (!subscription.isInitialized) {
            revert SubscriptionNotFound(service);
        }

        if (!isSubscribed(service, msg.sender)) {
            revert AccountNotSubscribed(msg.sender, service);
        }

        uint256 tokenId = subscription.subscribers[msg.sender].tokenId;

        delete subscription.subscribers[msg.sender];

        emit AccountUnsubscribed(msg.sender, service, tokenId);
    }

    /**
     * @notice sender update subcription payment
     * @param service subscription which sender will update payment
     */
    function paySubscription(address service) external {
        (, SubscriptionDetails memory subscriptionDetails) = _getSubscriptionDetails(service);

        if (!isPaymentDue(service, msg.sender)) {
            revert SubscriptionIsActive(
                msg.sender, service, subscriptions[service].subscribers[msg.sender].lastPayment, block.timestamp
            );
        }

        IPluginExecutor(subscriptionDetails.token).executeFromPluginExternal(
            msg.sender, subscriptionDetails.amount, "0x"
        );

        subscriptions[service].subscribers[msg.sender].lastPayment = block.timestamp;

        emit SubscriptionPayment(service, msg.sender, subscriptions[service].subscribers[msg.sender].tokenId);
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    View      functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /**
     * @notice check if payment is due
     * @param service subscription address
     * @param account account to check
     */
    function isPaymentDue(address service, address account) public view returns (bool) {
        (, SubscriptionDetails memory subscriptionDetails) = _getSubscriptionDetails(service);

        if (subscriptions[service].isInitialized) {
            revert SubscriptionNotFound(service);
        }

        if (!isSubscribed(service, account)) {
            revert AccountNotSubscribed(account, service);
        }

        return subscriptionDetails.period + subscriptions[service].subscribers[account].lastPayment < block.timestamp;
    }

    /**
     * @notice check if account is subscribed
     * @param service subscription address
     * @param account account to check
     */
    function isSubscribed(address service, address account) public view returns (bool) {
        return subscriptions[service].subscribers[account].tokenId > 0;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Plugin interface functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @inheritdoc BasePlugin
    function onInstall(bytes calldata) external pure override {}

    /// @inheritdoc BasePlugin
    function onUninstall(bytes calldata) external override {
        for (uint256 i = 0; i < subscribersRegistered.length - 1; i++) {
            SubscriberRegistered memory subscriberRegistered = subscribersRegistered[i];

            for (uint256 c = 0; c < subscriberRegistered.subscriptions.length - 1; c++) {
                delete subscriptions[subscriberRegistered.subscriptions[c]].subscribers[subscriberRegistered.account];

                subscriptions[subscriberRegistered.subscriptions[c]].isInitialized = false;
            }
        }

        delete subscribersRegistered;
    }

    /// @inheritdoc BasePlugin
    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.dependencyInterfaceIds = new bytes4[](1);
        manifest.dependencyInterfaceIds[0] = type(IMultiOwnerPlugin).interfaceId;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.subscribe.selector;

        ManifestFunction memory ownerUserOpValidationFunction = ManifestFunction({
            functionType: ManifestAssociatedFunctionType.DEPENDENCY,
            functionId: 0, // unused since it's a dependency
            dependencyIndex: _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION
        });

        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.userOpValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.subscribe.selector,
            associatedFunction: ownerUserOpValidationFunction
        });

        manifest.preRuntimeValidationHooks = new ManifestAssociatedFunction[](1);
        manifest.preRuntimeValidationHooks[0] = ManifestAssociatedFunction({
            executionSelector: this.subscribe.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.permitAnyExternalAddress = true;
        manifest.canSpendNativeToken = true;

        return manifest;
    }

    /// @inheritdoc BasePlugin
    function pluginMetadata() external pure virtual override returns (PluginMetadata memory) {
        PluginMetadata memory metadata;
        metadata.name = NAME;
        metadata.version = VERSION;
        metadata.author = AUTHOR;
        return metadata;
    }

    function _findSubscriberRegistered(address account)
        internal
        view
        returns (SubscriberRegistered memory, uint256 index)
    {
        SubscriberRegistered memory subscriberRegistered;
        uint256 i = 0;

        for (i; i < subscribersRegistered.length - 1; i++) {
            if (subscribersRegistered[i].account == account) {
                subscriberRegistered = subscribersRegistered[i];

                break;
            }
        }

        return (subscriberRegistered, i);
    }

    function _getSubscriptionDetails(address subscription)
        internal
        view
        returns (SubscriptionToken, SubscriptionDetails memory)
    {
        if (subscription.code.length == 0) {
            revert NotValidAddress(subscription);
        }

        SubscriptionToken subscriptionToken = SubscriptionToken(subscription);

        try subscriptionToken.getSubscriptionDetails() returns (SubscriptionDetails memory subscriptionDetails) {
            return (subscriptionToken, subscriptionDetails);
        } catch {
            revert NotValidSubscriptionNFT(subscription);
        }
    }
}
