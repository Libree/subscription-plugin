// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {BasePlugin} from "modular-account/src/plugins/BasePlugin.sol";
import {IPluginExecutor} from "modular-account/src/interfaces/IPluginExecutor.sol";
import {
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    ManifestExternalCallPermission,
    PluginManifest,
    PluginMetadata
} from "modular-account/src/interfaces/IPlugin.sol";
import {IMultiOwnerPlugin} from "modular-account/src/plugins/owner/IMultiOwnerPlugin.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SubscriptionToken, SubscriptionDetails} from "./SubscriptionToken.sol";
import {ISubscriptionPlugin} from "./interfaces/ISubscriptionPlugin.sol";

/// @title SubscriptionPlugin
/// @author Libree
/// @notice This plugin lets us subscribe to services!
contract SubscriptionPlugin is BasePlugin, ISubscriptionPlugin {
    // metadata used by the pluginMetadata() method down below
    string public constant NAME = "Subscription Plugin";
    string public constant VERSION = "1.0.0";
    string public constant AUTHOR = "Libree";

    struct Subscriber {
        uint256 tokenId;
        uint256 lastPayment;
    }

    struct Subscription {
        mapping(address => Subscriber) subscribers;
    }

    // this is a constant used in the manifest, to reference our only dependency: the multi owner plugin
    // since it is the first, and only, plugin the index 0 will reference the multi owner plugin
    // we can use this to tell the modular account that we should use the multi owner plugin to validate our user op
    // in other words, we'll say "make sure the person calling increment is an owner of the account using our multiowner plugin"
    uint256 internal constant _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION = 0;

    // subscribed to nft
    mapping(address => Subscription) private subscriptions;
    mapping(address => address[])private userSubscriptions;

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

        if (isSubscribed(service, msg.sender)) {
            revert AlreadySubscribed(msg.sender, service, subscription.subscribers[msg.sender].tokenId);
        }

        uint256 accountBalance = IERC20(subscriptionDetails.token).balanceOf(msg.sender);

        if (accountBalance < subscriptionDetails.amount) {
            revert InsufficientBalance();
        }

        IPluginExecutor(msg.sender).executeFromPluginExternal(
            address(subscriptionDetails.token),
            0,
            abi.encodeCall(IERC20.transfer, (subscriptionToken.owner(), subscriptionDetails.amount))
        );

        uint256 tokenId = subscriptionToken.safeMint(msg.sender);

        subscription.subscribers[msg.sender] = Subscriber({
            tokenId: tokenId, 
            lastPayment: block.timestamp
        });

        userSubscriptions[msg.sender].push(service);

        emit AccountSubscribed(service, msg.sender, tokenId);
    }

    /**
     * @notice sender unsubscribe to a subcription
     * @param service subscription which sender will unsubscribe
     */
    function unsubscribe(address service) public {
        if (!isSubscribed(service, msg.sender)) {
            revert AccountNotSubscribed(msg.sender, service);
        }

        address[] storage currentSubscriptions = userSubscriptions[msg.sender];
        for (uint i = 0; i < currentSubscriptions.length; i++) {
            if (currentSubscriptions[i] == service) {
                currentSubscriptions[i] = currentSubscriptions[currentSubscriptions.length - 1];
                currentSubscriptions.pop();
                break;
            }
        }

        uint256 tokenId = subscriptions[service].subscribers[msg.sender].tokenId;
        delete subscriptions[service].subscribers[msg.sender];

        emit AccountUnsubscribed(msg.sender, service, tokenId);
    }

    /**
     * @notice sender update subcription payment
     * @param service subscription which sender will update payment
     */
    function paySubscription(address service) external {
        (SubscriptionToken subscriptionToken, SubscriptionDetails memory subscriptionDetails) =
            _getSubscriptionDetails(service);

        if (!isSubscribed(service, msg.sender)) {
            revert AccountNotSubscribed(msg.sender, service);
        }

        if (!isPaymentDue(service, msg.sender)) {
            revert SubscriptionIsActive(
                msg.sender, service, subscriptions[service].subscribers[msg.sender].lastPayment, block.timestamp
            );
        }

        IPluginExecutor(msg.sender).executeFromPluginExternal(
            address(subscriptionDetails.token),
            0,
            abi.encodeCall(IERC20.transfer, (subscriptionToken.owner(), subscriptionDetails.amount))
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

        return subscriptionDetails.period + subscriptions[service].subscribers[account].lastPayment < block.timestamp;
    }

    /**
     * @notice check if account is subscribed
     * @param service subscription address
     * @param account account to check
     */
    function isSubscribed(address service, address account) public view returns (bool) {
        return subscriptions[service].subscribers[account].lastPayment > 0;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Plugin interface functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @inheritdoc BasePlugin
    function onInstall(bytes calldata) external pure override {}

    /// @inheritdoc BasePlugin
    function onUninstall(bytes calldata) external override {
        while(userSubscriptions[msg.sender].length > 0){
            unsubscribe(userSubscriptions[msg.sender][0]);
        }
    }

    /// @inheritdoc BasePlugin
    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.dependencyInterfaceIds = new bytes4[](2);
        manifest.dependencyInterfaceIds[0] = type(IMultiOwnerPlugin).interfaceId;
        manifest.dependencyInterfaceIds[1] = type(IMultiOwnerPlugin).interfaceId;

        manifest.executionFunctions = new bytes4[](3);
        manifest.executionFunctions[0] = this.subscribe.selector;
        manifest.executionFunctions[1] = this.unsubscribe.selector;
        manifest.executionFunctions[2] = this.paySubscription.selector;

        ManifestFunction memory ownerUserOpValidationFunction = ManifestFunction({
            functionType: ManifestAssociatedFunctionType.DEPENDENCY,
            functionId: 0, // unused since it's a dependency
            dependencyIndex: _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION
        });

        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](3);
        manifest.userOpValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.subscribe.selector,
            associatedFunction: ownerUserOpValidationFunction
        });

        manifest.userOpValidationFunctions[1] = ManifestAssociatedFunction({
            executionSelector: this.unsubscribe.selector,
            associatedFunction: ownerUserOpValidationFunction
        });

        manifest.userOpValidationFunctions[2] = ManifestAssociatedFunction({
            executionSelector: this.paySubscription.selector,
            associatedFunction: ownerUserOpValidationFunction
        });

        manifest.preRuntimeValidationHooks = new ManifestAssociatedFunction[](3);
        manifest.preRuntimeValidationHooks[0] = ManifestAssociatedFunction({
            executionSelector: this.subscribe.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.preRuntimeValidationHooks[1] = ManifestAssociatedFunction({
            executionSelector: this.unsubscribe.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.preRuntimeValidationHooks[2] = ManifestAssociatedFunction({
            executionSelector: this.paySubscription.selector,
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
