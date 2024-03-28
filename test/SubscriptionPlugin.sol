// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {Test, StdUtils} from "forge-std/Test.sol";
import {SubscriptionToken} from "../src/SubscriptionToken.sol";
import {SubscriptionPlugin} from "../src/SubscriptionPlugin.sol";
import {ISubscriptionPlugin} from "../src/interfaces/ISubscriptionPlugin.sol";
import {ISubscriptionToken} from "../src/interfaces/ISubscriptionToken.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MultiOwnerModularAccountFactory} from "modular-account/src/factory/MultiOwnerModularAccountFactory.sol";
import {IEntryPoint} from "modular-account/src/interfaces/erc4337/IEntryPoint.sol";
import {UpgradeableModularAccount} from "modular-account/src/account/UpgradeableModularAccount.sol";
import {FunctionReferenceLib} from "modular-account/src/helpers/FunctionReferenceLib.sol";
import {FunctionReference} from "modular-account/src/interfaces/IPluginManager.sol";
import {EntryPoint} from "@eth-infinitism/account-abstraction/core/EntryPoint.sol";
import {IMultiOwnerPlugin} from "modular-account/src/plugins/owner/IMultiOwnerPlugin.sol";
import {MultiOwnerPlugin} from "modular-account/src/plugins/owner/MultiOwnerPlugin.sol";
import {TestUSDC} from "./MockUSDC.sol";

contract SubscriptionPluginTest is Test {
    address subscriptionTokenProxy;
    SubscriptionToken subscriptionToken;
    SubscriptionPlugin subscriptionPlugin;

    address owner = vm.addr(1);
    address usdc;
    IEntryPoint entryPoint = IEntryPoint(address(new EntryPoint()));
    MultiOwnerModularAccountFactory smartAccountFactory;
    MultiOwnerPlugin multiOwnerPlugin;

    function setUp() public {
        vm.startPrank(owner);
        deal(owner, 1 ether);

        subscriptionPlugin = new SubscriptionPlugin();

        multiOwnerPlugin = new MultiOwnerPlugin();

        address impl = address(new UpgradeableModularAccount(entryPoint));

        smartAccountFactory = new MultiOwnerModularAccountFactory(
            address(owner),
            address(multiOwnerPlugin),
            impl,
            keccak256(abi.encode(multiOwnerPlugin.pluginManifest())),
            entryPoint
        );

        subscriptionToken = new SubscriptionToken();

        TestUSDC testUSDC = new TestUSDC();

        usdc = address(testUSDC);

        bytes memory data = abi.encode(30 days, 100000000, usdc);

        subscriptionTokenProxy = address(
            new ERC1967Proxy(
                address(subscriptionToken),
                abi.encodeCall(
                    SubscriptionToken.initialize,
                    ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
                )
            )
        );

        subscriptionToken = SubscriptionToken(subscriptionTokenProxy);

        vm.stopPrank();
    }

    function _getSmartAccount(address account) internal returns (address) {
        bytes memory data = abi.encode();

        address[] memory owners = new address[](1);

        owners[0] = account;

        UpgradeableModularAccount smartAccount =
            UpgradeableModularAccount(payable(smartAccountFactory.createAccount(12, owners)));

        bytes32 manifestHash = keccak256(abi.encode(subscriptionPlugin.pluginManifest()));
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] = FunctionReferenceLib.pack(
            address(multiOwnerPlugin), uint8(ISubscriptionPlugin.FunctionId.RUNTIME_VALIDATION_OWNER_OR_SELF)
        );
        dependencies[1] = FunctionReferenceLib.pack(
            address(multiOwnerPlugin), uint8(ISubscriptionPlugin.FunctionId.USER_OP_VALIDATION_OWNER)
        );

        smartAccount.installPlugin({
            plugin: address(subscriptionPlugin),
            manifestHash: manifestHash,
            pluginInstallData: data,
            dependencies: dependencies
        });

        return address(smartAccount);
    }

    function testSubscribeWithSmartWallet() public {
        address subscriber = vm.addr(2);

        vm.startPrank(subscriber);

        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount));
    }

    function testSecondSubscriberSameSubscription() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount1 = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount1);

        deal(smartAccount1, 1 ether);
        deal(usdc, smartAccount1, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        address subscriber2 = vm.addr(3);

        vm.startPrank(subscriber2);

        deal(subscriber2, 1 ether);

        address smartAccount2 = _getSmartAccount(subscriber2);

        vm.stopPrank();

        vm.startPrank(smartAccount2);

        deal(smartAccount2, 1 ether);
        deal(usdc, smartAccount2, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount1));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount2));
    }

    function testSecondSubscriberDifferentSubscription() public {
        bytes memory data = abi.encode(180 days, 500, usdc);

        SubscriptionToken subscriptionToken2 = new SubscriptionToken();

        vm.startPrank(owner);
        address subscriptionTokenProxy2 = address(
            new ERC1967Proxy(
                address(subscriptionToken2),
                abi.encodeCall(
                    SubscriptionToken.initialize,
                    ("TestNFT", "TEST", "https://test.com", address(subscriptionPlugin), data)
                )
            )
        );

        vm.stopPrank();

        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount1 = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount1);

        deal(smartAccount1, 1 ether);
        deal(usdc, smartAccount1, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        address subscriber2 = vm.addr(3);

        vm.startPrank(subscriber2);

        deal(subscriber2, 1 ether);

        address smartAccount2 = _getSmartAccount(subscriber2);

        vm.stopPrank();

        vm.startPrank(smartAccount2);

        deal(smartAccount2, 1 ether);
        deal(usdc, smartAccount2, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy2);

        vm.stopPrank();

        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount1));
        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy2, smartAccount1));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy2, smartAccount2));
        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount2));
    }

    function testSubscriberSameSubscription() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        bytes4 selector = bytes4(keccak256("AlreadySubscribed(address,address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, smartAccount, subscriptionTokenProxy));

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();
    }

    function testSubscriberDifferentSubscriptions() public {
        vm.startPrank(owner);
        bytes memory data = abi.encode(180 days, 500, usdc);

        SubscriptionToken subscriptionToken2 = new SubscriptionToken();

        address subscriptionTokenProxy2 = address(
            new ERC1967Proxy(
                address(subscriptionToken2),
                abi.encodeCall(
                    SubscriptionToken.initialize,
                    ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
                )
            )
        );

        SubscriptionToken subscriptionToken3 = new SubscriptionToken();

        bytes memory data2 = abi.encode(180 days, 300, usdc);
        address subscriptionTokenProxy3 = address(
            new ERC1967Proxy(
                address(subscriptionToken3),
                abi.encodeCall(
                    SubscriptionToken.initialize,
                    ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data2)
                )
            )
        );

        vm.stopPrank();

        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        subscriptionPlugin.subscribe(subscriptionTokenProxy2);

        subscriptionPlugin.subscribe(subscriptionTokenProxy3);

        vm.stopPrank();

        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy2, smartAccount));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy3, smartAccount));
    }

    function testIsPaymentDue() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();
        vm.warp(block.timestamp + 40 days);

        assertTrue(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, smartAccount));
    }

    function testIsNotPaymentDue() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        assertFalse(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, smartAccount));
    }

    function testAccountIsNotSubscribed() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        address subscriber2 = vm.addr(3);

        vm.startPrank(subscriber2);

        address smartAccount2 = _getSmartAccount(subscriber2);

        vm.stopPrank();

        assertTrue(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, smartAccount2));
        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount2));
    }

    function testPaySubscription() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.warp(block.timestamp + 40 days);

        uint256 FEE = 100;

        ISubscriptionToken.SubscriptionDetails memory details = ISubscriptionToken(subscriptionTokenProxy).getSubscriptionDetails();

        uint256 feeAmount = (details.amount * FEE) / 1e4;
        uint256 netPayment = details.amount - feeAmount;

        uint256 balanceOwnerBefore = IERC20(usdc).balanceOf(SubscriptionToken(subscriptionTokenProxy).owner());
        uint256 pluginBalanceBefore = IERC20(usdc).balanceOf(address(subscriptionPlugin));
        subscriptionPlugin.paySubscription(subscriptionTokenProxy);

        uint256 balanceOwnerAfter = IERC20(usdc).balanceOf(SubscriptionToken(subscriptionTokenProxy).owner());
        uint256 pluginBalanceAfter = IERC20(usdc).balanceOf(address(subscriptionPlugin));

        vm.stopPrank();

        assertTrue(balanceOwnerBefore + netPayment == balanceOwnerAfter);
        assertTrue(pluginBalanceAfter == pluginBalanceBefore + feeAmount);
        assertFalse(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, smartAccount));
    }

    function testNotNeedPaySubscriptionYet() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        bytes4 selector = bytes4(keccak256("SubscriptionIsActive(address,address,uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(
                selector, smartAccount, address(subscriptionTokenProxy), block.timestamp, block.timestamp
            )
        );
        subscriptionPlugin.paySubscription(subscriptionTokenProxy);

        vm.stopPrank();
    }

    function testUnsubscribeSubscription() public {
        address subscriber = vm.addr(2);

        vm.startPrank(subscriber);

        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        subscriptionPlugin.unsubscribe(subscriptionTokenProxy);

        vm.stopPrank();

        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount));
    }

    function testWithdrawNotAllowed() public {
        address newOwner = vm.addr(4);
        address noOwner = vm.addr(5);
        vm.startPrank(owner);

        subscriptionPlugin.transferOwnership(newOwner);
        vm.stopPrank();

        vm.startPrank(newOwner);

        subscriptionPlugin.acceptOwnership();

        vm.stopPrank();

        vm.startPrank(noOwner);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));

        subscriptionPlugin.withdraw(usdc, 10, address(this));

        vm.stopPrank();
    }

    function testWithdraw() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.warp(block.timestamp + 40 days);

        uint256 FEE = 100;

        ISubscriptionToken.SubscriptionDetails memory details = ISubscriptionToken(subscriptionTokenProxy).getSubscriptionDetails();

        uint256 feeAmount = (details.amount * FEE) / 1e4;
        uint256 netPayment = details.amount - feeAmount;

        uint256 balanceOwnerBefore = IERC20(usdc).balanceOf(SubscriptionToken(subscriptionTokenProxy).owner());
        uint256 pluginBalanceBefore = IERC20(usdc).balanceOf(address(subscriptionPlugin));
        subscriptionPlugin.paySubscription(subscriptionTokenProxy);

        uint256 balanceOwnerAfter = IERC20(usdc).balanceOf(SubscriptionToken(subscriptionTokenProxy).owner());
        uint256 pluginBalanceAfter = IERC20(usdc).balanceOf(address(subscriptionPlugin));

        vm.stopPrank();

        assertTrue(balanceOwnerBefore + netPayment == balanceOwnerAfter);
        assertTrue(pluginBalanceAfter == pluginBalanceBefore + feeAmount);
        assertFalse(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, smartAccount));
        address newOwner = vm.addr(4);

        vm.startPrank(owner);

        subscriptionPlugin.transferOwnership(newOwner);

        vm.stopPrank();

        vm.startPrank(newOwner);
        subscriptionPlugin.acceptOwnership();

        uint256 balanceBefore = IERC20(usdc).balanceOf(newOwner);

        subscriptionPlugin.withdraw(usdc, 1000, newOwner);

        uint256 balanceAfter = IERC20(usdc).balanceOf(newOwner);

        assertTrue(balanceAfter == balanceBefore + 1000);

        vm.stopPrank();
    }

    function testUninstallEmptyPlugin() public {
        bytes memory data = abi.encode();
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        UpgradeableModularAccount smartAccount = UpgradeableModularAccount(payable(_getSmartAccount(subscriber)));

        smartAccount.uninstallPlugin(address(subscriptionPlugin), data, data);

        vm.stopPrank();
    }

    function testUninstallPluginWithData() public {
        vm.startPrank(owner);
        bytes memory data = abi.encode(180 days, 500, usdc);

        SubscriptionToken subscriptionToken2 = new SubscriptionToken();

        address subscriptionTokenProxy2 = address(
            new ERC1967Proxy(
                address(subscriptionToken2),
                abi.encodeCall(
                    SubscriptionToken.initialize,
                    ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
                )
            )
        );

        bytes memory data2 = abi.encode(180 days, 300, usdc);

        SubscriptionToken subscriptionToken3 = new SubscriptionToken();

        address subscriptionTokenProxy3 = address(
            new ERC1967Proxy(
                address(subscriptionToken3),
                abi.encodeCall(
                    SubscriptionToken.initialize,
                    ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data2)
                )
            )
        );

        vm.stopPrank();

        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);

        address smartAccount = _getSmartAccount(subscriber);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        deal(smartAccount, 1 ether);
        deal(usdc, smartAccount, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        subscriptionPlugin.subscribe(subscriptionTokenProxy2);

        subscriptionPlugin.subscribe(subscriptionTokenProxy3);

        vm.stopPrank();

        address subscriber2 = vm.addr(3);
        vm.startPrank(subscriber2);
        deal(subscriber2, 1 ether);

        address smartAccount2 = _getSmartAccount(subscriber2);

        vm.stopPrank();

        vm.startPrank(smartAccount2);

        deal(smartAccount2, 1 ether);
        deal(usdc, smartAccount2, 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        vm.startPrank(smartAccount);

        bytes memory dataEmpty = abi.encode();

        UpgradeableModularAccount smartAccountModular = UpgradeableModularAccount(payable(smartAccount));

        smartAccountModular.uninstallPlugin(address(subscriptionPlugin), dataEmpty, dataEmpty);

        vm.stopPrank();

        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount));
        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy2, smartAccount));
        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy3, smartAccount));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, smartAccount2));
    }
}
