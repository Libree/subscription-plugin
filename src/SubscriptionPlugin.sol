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
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SubscriptionToken, SubscriptionDetails} from "./SubscriptionToken.sol";
import {ISubscriptionPlugin} from "./interfaces/ISubscriptionPlugin.sol";

/// @title SubscriptionPlugin
/// @author Libree
/// @notice This plugin lets us subscribe to services!
contract SubscriptionPlugin is BasePlugin, ISubscriptionPlugin, Ownable2Step {
    // metadata used by the pluginMetadata() method down below
    string public constant NAME = "Subscription Plugin";
    string public constant VERSION = "1.0.0";
    string public constant AUTHOR = "Libree";
    uint16 public constant FEE = 100; // 1%

    // this is a constant used in the manifest, to reference our only dependency: the multi owner plugin
    // since it is the first, and only, plugin the index 0 will reference the multi owner plugin
    // we can use this to tell the modular account that we should use the multi owner plugin to validate our user op
    // in other words, we'll say "make sure the person calling increment is an owner of the account using our multiowner plugin"
    uint256 internal constant _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION = 0;
    
    mapping(address => mapping(address => bool)) public subscriptions;
    mapping(address => address[]) public userSubscriptions;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Execution functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛


    constructor() Ownable2Step() {}

    /**
     * @notice sender subscribe to a subcription
     * @param service subscription which sender will subscribe
     */
    function subscribe(address service) external {
        (SubscriptionToken subscriptionToken, SubscriptionDetails memory subscriptionDetails) =
            _getSubscriptionDetails(service);

        if (isSubscribed(service, msg.sender)) {
            revert AlreadySubscribed(msg.sender, service);
        }

        uint256 accountBalance = IERC20(subscriptionDetails.token).balanceOf(msg.sender);

        if (accountBalance < subscriptionDetails.amount) {
            revert InsufficientBalance();
        }

        _sendPayment(subscriptionDetails.token, subscriptionToken.owner(), subscriptionDetails.amount);

        SubscriptionToken(service).updatePayment(msg.sender, block.timestamp);

        userSubscriptions[msg.sender].push(service);
        subscriptions[service][msg.sender] = true;

        emit AccountSubscribed(service, msg.sender);
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

        delete subscriptions[service][msg.sender];

        emit AccountUnsubscribed(msg.sender, service);
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
                msg.sender, service, SubscriptionToken(service).getPayment(msg.sender), block.timestamp
            );
        }

        _sendPayment(subscriptionDetails.token, subscriptionToken.owner(), subscriptionDetails.amount);

        SubscriptionToken(service).updatePayment(msg.sender, block.timestamp);

        emit SubscriptionPayment(service, msg.sender);
    }

    function withdraw (address token, uint256 amount, address destination) external onlyOwner {
        IERC20(token).transfer(destination, amount);
    }


    /**
     * @dev Internal function to send payment to the subscription owner.
     * @param paymentToken The address of the payment token.
     * @param subscriptionOwner The address of the subscription owner.
     * @param paymentAmount The amount of payment to be sent.
     */
    function _sendPayment(address paymentToken, address subscriptionOwner, uint256 paymentAmount) internal {
        uint256 feeAmount;
        uint256 netPayment = paymentAmount; 

        if (FEE > 0) {
            feeAmount = (paymentAmount * FEE) / 1e4;
            netPayment = paymentAmount - feeAmount;

            // Transfer the fee amount to the plugin contract
            IPluginExecutor(msg.sender).executeFromPluginExternal(
                address(paymentToken),
                0,
                abi.encodeCall(IERC20.transfer, (address(this), feeAmount))
            );
        }

        // Transfer the net payment amount to the subscription owner
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            address(paymentToken),
            0,
            abi.encodeCall(IERC20.transfer, (subscriptionOwner, netPayment))
        );
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
        return SubscriptionToken(service).getPayment(account) < block.timestamp;
    }

    /**
     * @notice check if account is subscribed
     * @param service subscription address
     * @param account account to check
     */
    function isSubscribed(address service, address account) public view returns (bool) {
        return subscriptions[service][account];
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

    /**
     * @dev Retrieves the subscription details for a given subscription address.
     * @param subscription The address of the subscription.
     * @return subscriptionToken The subscription token associated with the subscription address.
     * @return subscriptionDetails The details of the subscription.
     * @dev Throws a `NotValidAddress` error if the subscription address is not valid.
     * @dev Throws a `NotValidSubscriptionNFT` error if the subscription token is not a valid subscription NFT.
     */
    function _getSubscriptionDetails(address subscription)
        internal
        view
        returns (SubscriptionToken subscriptionToken, SubscriptionDetails memory subscriptionDetails)
    {
        if (subscription.code.length == 0) {
            revert NotValidAddress(subscription);
        }

        subscriptionToken = SubscriptionToken(subscription);

        try subscriptionToken.getSubscriptionDetails() returns (SubscriptionDetails memory details) {
            return (subscriptionToken, details);
        } catch {
            revert NotValidSubscriptionNFT(subscription);
        }
    }
}
