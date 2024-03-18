// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {Test, StdUtils} from "forge-std/Test.sol";
import {SubscriptionToken} from "../src/SubscriptionToken.sol";
import {SubscriptionPlugin} from "../src/SubscriptionPlugin.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MultiOwnerModularAccountFactory} from "modular-account/src/factory/MultiOwnerModularAccountFactory.sol";
import {IEntryPoint} from "modular-account/src/interfaces/erc4337/IEntryPoint.sol";
import {UpgradeableModularAccount} from "modular-account/src/account/UpgradeableModularAccount.sol";
import {EntryPoint} from "@eth-infinitism/account-abstraction/core/EntryPoint.sol";

contract SubscriptionPluginTest is Test {
    address subscriptionTokenProxy;
    SubscriptionToken subscriptionToken;
    SubscriptionPlugin subscriptionPlugin;

    address owner = vm.addr(1);
    address usdc = 0x52D800ca262522580CeBAD275395ca6e7598C014;
    IEntryPoint entryPoint = IEntryPoint(address(new EntryPoint()));
    MultiOwnerModularAccountFactory smartAccountFactory;

    function setUp() public {
        vm.startPrank(owner);
        deal(owner, 1 ether);

        bytes memory data = abi.encode(30 days, 100, usdc);

        subscriptionPlugin = new SubscriptionPlugin();

        address impl = address(new UpgradeableModularAccount(entryPoint));

        smartAccountFactory = new MultiOwnerModularAccountFactory(
            address(owner),
            address(subscriptionPlugin),
            impl,
            keccak256(abi.encode(subscriptionPlugin.pluginManifest())),
            entryPoint
        );

        subscriptionToken = new SubscriptionToken();

        subscriptionTokenProxy = address(
            new ERC1967Proxy(address(subscriptionToken),
            abi.encodeCall(
                SubscriptionToken.initialize,
                ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
            )    
            )
        );

        subscriptionToken = SubscriptionToken(subscriptionTokenProxy);

        vm.stopPrank();
    }

    function testInstallPlugin() public {
        vm.startPrank(owner);
        bytes memory data = abi.encode();

        subscriptionPlugin.pluginManifest();
        subscriptionPlugin.pluginMetadata();
        subscriptionPlugin.onInstall(data);

        vm.stopPrank();
    }

    function testSubscribe() public {
        bytes memory data = abi.encode();

        address subscriber = vm.addr(2);
        address[] storage owners;

        owners.push(subscriber);

        UpgradeableModularAccount account =
            UpgradeableModularAccount(payable(smartAccountFactory.createAccount(0, owners)));

        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.pluginManifest();
        subscriptionPlugin.onInstall(data);
        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, subscriber));
    }

    function testSecondSubscriberSameSubscription() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        address subscriber2 = vm.addr(3);

        vm.startPrank(subscriber2);

        deal(subscriber2, 1 ether);
        deal(usdc, subscriber2, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, subscriber));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, subscriber2));
    }

    function testSecondSubscriberDifferentSubscription() public {
        bytes memory data = abi.encode(180 days, 500, usdc);

        vm.startPrank(owner);
        address subscriptionTokenProxy2 = address(
            new ERC1967Proxy(address(subscriptionToken),
            abi.encodeCall(
                SubscriptionToken.initialize,
                ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
            )    
            )
        );

        vm.stopPrank();

        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        address subscriber2 = vm.addr(3);

        vm.startPrank(subscriber2);

        deal(subscriber2, 1 ether);
        deal(usdc, subscriber2, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy2);

        vm.stopPrank();

        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, subscriber));
        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy2, subscriber));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy2, subscriber2));
        assertFalse(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, subscriber2));
    }

    function testSubscriberSameSubscription() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        bytes4 selector = bytes4(keccak256("AlreadySubscribed(address,address,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(selector, subscriber, subscriptionTokenProxy, 0));

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();
    }

    function testSubscriberDifferentSubscriptions() public {
        vm.startPrank(owner);
        bytes memory data = abi.encode(180 days, 500, usdc);
        address subscriptionTokenProxy2 = address(
            new ERC1967Proxy(address(subscriptionToken),
            abi.encodeCall(
                SubscriptionToken.initialize,
                ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
            )    
            )
        );

        bytes memory data2 = abi.encode(180 days, 300, usdc);
        address subscriptionTokenProxy3 = address(
            new ERC1967Proxy(address(subscriptionToken),
            abi.encodeCall(
                SubscriptionToken.initialize,
                ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
            )    
            )
        );

        vm.stopPrank();

        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        subscriptionPlugin.subscribe(subscriptionTokenProxy2);

        subscriptionPlugin.subscribe(subscriptionTokenProxy3);

        vm.stopPrank();

        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy, subscriber));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy2, subscriber));
        assertTrue(subscriptionPlugin.isSubscribed(subscriptionTokenProxy3, subscriber));
    }

    function testIsPaymentDue() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();
        vm.warp(block.timestamp + 40 days);

        assertTrue(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, subscriber));
    }

    function testIsNotPaymentDue() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        assertFalse(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, subscriber));
    }

    function testServiceNotFound() public {
        address subscriber = vm.addr(2);

        bytes4 selector = bytes4(keccak256("SubscriptionNotFound(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(subscriptionTokenProxy)));
        subscriptionPlugin.isPaymentDue(address(subscriptionTokenProxy), subscriber);
    }

    function testAccountIsNotSubscribed() public {
        address subscriber = vm.addr(2);
        address subscriber2 = vm.addr(3);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.stopPrank();

        bytes4 selector = bytes4(keccak256("AccountNotSubscribed(address,address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, subscriber2, address(subscriptionTokenProxy)));
        assertFalse(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, subscriber2));
    }

    function testPaySubscription() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        vm.warp(block.timestamp + 40 days);

        subscriptionPlugin.paySubscription(subscriptionTokenProxy);

        vm.stopPrank();

        assertFalse(subscriptionPlugin.isPaymentDue(subscriptionTokenProxy, subscriber));
    }

    function testNotNeedPaySubscriptionYet() public {
        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        bytes4 selector = bytes4(keccak256("SubscriptionIsActive(address,address,uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(
                selector, subscriber, address(subscriptionTokenProxy), block.timestamp, block.timestamp
            )
        );
        subscriptionPlugin.paySubscription(subscriptionTokenProxy);

        vm.stopPrank();
    }

    function testUninstallEmptyPlugin() public {
        vm.startPrank(owner);
        bytes memory data = abi.encode();

        subscriptionPlugin.onUninstall(data);

        vm.stopPrank();
    }

    function testUninstallPluginWithData() public {
        vm.startPrank(owner);
        bytes memory data = abi.encode(180 days, 500, usdc);
        address subscriptionTokenProxy2 = address(
            new ERC1967Proxy(address(subscriptionToken),
            abi.encodeCall(
                SubscriptionToken.initialize,
                ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
            )    
            )
        );

        bytes memory data2 = abi.encode(180 days, 300, usdc);
        address subscriptionTokenProxy3 = address(
            new ERC1967Proxy(address(subscriptionToken),
            abi.encodeCall(
                SubscriptionToken.initialize,
                ("TestNFT", "TEST", "https://example.com", address(subscriptionPlugin), data)
            )    
            )
        );

        vm.stopPrank();

        address subscriber = vm.addr(2);
        vm.startPrank(subscriber);
        deal(subscriber, 1 ether);
        deal(usdc, subscriber, 1000 ether);

        IERC20(usdc).approve(address(subscriptionPlugin), 1000 ether);

        subscriptionPlugin.subscribe(subscriptionTokenProxy);

        subscriptionPlugin.subscribe(subscriptionTokenProxy2);

        subscriptionPlugin.subscribe(subscriptionTokenProxy3);

        vm.stopPrank();

        vm.startPrank(owner);
        bytes memory dataEmpty = abi.encode();

        subscriptionPlugin.onUninstall(dataEmpty);

        vm.stopPrank();
    }
}
