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

    // this is a constant used in the manifest, to reference our only dependency: the multi owner plugin
    // since it is the first, and only, plugin the index 0 will reference the multi owner plugin
    // we can use this to tell the modular account that we should use the multi owner plugin to validate our user op
    // in other words, we'll say "make sure the person calling increment is an owner of the account using our multiowner plugin"
    uint256 internal constant _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION = 0;

    address[] subscribed;

    // subscribed to nft
    mapping(address => uint256) public subscribers;

    /**
     *
     * @notice Emitted when user subscribe to nft
     * @dev This event is emitted when a new subscriber of NFT is added
     */
    event AccountSubscribed(address account, uint256 subscriptionId);

    /**
     *
     * @notice Emitted when user unsubscribe to nft
     * @dev This event is emitted when a subscriber of NFT is removed
     */
    event AccountUnsubscribed(address account, uint256 subscriptionId);

    // error handlers

    error InsufficientBalance();
    error AlreadySubscribed(address account, uint256 subscriptionId);
    error CannotFindSubscriber(address account);

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Execution functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    // this can be called from a user op by the account owner
    function subscribe(address service) external {
        uint256 subscriptionId = subscribers[msg.sender];

        if (subscriptionId > 0) {
            revert AlreadySubscribed(msg.sender, subscriptionId);
        }

        SubscriptionToken subscriptionToken = SubscriptionToken(service);

        SubscriptionDetails memory subscriptionDetails = subscriptionToken.getSubscriptionDetails();

        uint256 accountBalance = IERC20(subscriptionDetails.token).balanceOf(msg.sender);

        if (accountBalance < subscriptionDetails.amount) {
            revert InsufficientBalance();
        }

        IERC20(subscriptionDetails.token).transferFrom(
            msg.sender, subscriptionToken.owner(), subscriptionDetails.amount
        );

        uint256 tokenId = subscriptionToken.safeMint(msg.sender, subscriptionDetails.metadataUri);

        subscribers[msg.sender] = tokenId;
        subscribed.push(msg.sender);

        emit AccountSubscribed(msg.sender, tokenId);
    }

    function unsubscribe() external {
        uint256 subscriptionId = subscribers[msg.sender];

        if (subscriptionId < 1) {
            revert CannotFindSubscriber(msg.sender);
        }

        delete subscribers[msg.sender];

        for (uint256 i = 0; i < subscribed.length - 1; i++) {
            if (subscribed[i] == msg.sender) {
                delete subscribed[i];
            }
        }

        emit AccountUnsubscribed(msg.sender, subscriptionId);
    }

    function paySubscription(address service, uint256 amount) external {}

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    View      functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    function isPaymentDue(address service) external view returns (bool) {}

    function isSubscribed(address service) external view returns (bool) {}

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Plugin interface functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @inheritdoc BasePlugin
    function onInstall(bytes calldata data) external override {}

    /// @inheritdoc BasePlugin
    function onUninstall(bytes calldata) external override {
        for (uint256 i = 0; i < subscribed.length - 1; i++) {
            delete subscribers[subscribed[i]];
        }

        delete subscribed;
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
}
