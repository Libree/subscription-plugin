// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

struct SubscriptionDetails {
    uint256 period;
    uint256 amount;
    address token;
    string metadataUri;
}

contract SubscriptionToken is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    uint256 private _nextTokenId;

    address private _minter;

    SubscriptionDetails public _subscriptionDetails;

    modifier onlyMinter() {
        require(_msgSender() == _minter, "SubscriptionToken: caller is not the minter");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        string memory name,
        string memory symbol,
        address minter,
        bytes calldata data
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        _minter = minter;

        (uint256 period, uint256 amount, address token, string memory metadataUri) =
            abi.decode(data, (uint256, uint256, address, string));

        _subscriptionDetails = SubscriptionDetails(period, amount, token, metadataUri);
    }

    function safeMint(address to, string memory uri) public onlyMinter returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        return tokenId;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function getSubscriptionDetails() public view returns (SubscriptionDetails memory) {
        return _subscriptionDetails;
    }
}
