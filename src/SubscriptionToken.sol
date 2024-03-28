// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

struct SubscriptionDetails {
    uint256 period;
    uint256 amount;
    address token;
}

error TransferIsNotAllowed();

contract SubscriptionToken is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /**
    * @dev The next token ID to be assigned.
     */
    uint256 private _nextTokenId;

    /**
    * @dev The address of the minter.
     */
    address private _minter;

    /**
    * @dev The metadata URL of the token.
     */
    string public metadataUrl;

    /**
    * @dev The subscription details of the token.
     */
    SubscriptionDetails public _subscriptionDetails;

    /**
    * @dev The payment information of the users.
     */
    mapping(address => uint256) public _userPayment;

    modifier onlyMinter() {
        require(_msgSender() == _minter, "SubscriptionToken: caller is not the minter");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        string memory metadataUri,
        address minter,
        bytes calldata data
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        _minter = minter;

        metadataUri = metadataUri;

        (uint256 period, uint256 amount, address token) = abi.decode(data, (uint256, uint256, address));

        _subscriptionDetails = SubscriptionDetails(period, amount, token);
    }

    /**
     * @dev Safely transfers the ownership of a token from one address to another address.
     * Reverts with a custom error message if the transfer is not allowed.
     * 
     * Requirements:
     * - The caller must have the minter role.
     * 
     */
    function safeTransferFrom(address, address, uint256) 
        public 
        override(ERC721Upgradeable, IERC721Upgradeable)
        onlyMinter 
    {
        revert TransferIsNotAllowed();
    }

    /**
     * @dev Transfers a subscription token from one address to another.
     * Overrides the transferFrom function from ERC721Upgradeable and ERC721Upgradeable interfaces.
     * Only the minter is allowed to perform this action.
     */
    function transferFrom(address, address, uint256) 
        public  
        override(ERC721Upgradeable, IERC721Upgradeable) onlyMinter 
    {
        revert TransferIsNotAllowed();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Returns the URI for a given token ID.
     * 
     * This function overrides the `tokenURI` function from the ERC721Upgradeable and ERC721URIStorageUpgradeable contracts.
     * It retrieves the token URI from the parent contract using the `super` keyword.
     * 
     * @param tokenId The ID of the token.
     * @return The URI string for the token.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }


    /**
     * @dev Returns the owner of a given token ID.
     * 
     * This function is an override of the `ownerOf` function.
     * It returns the address of the owner of the specified token ID.
     * If the token ID does not exist or is owned by multiple addresses, it returns address(0).
     * 
     * @param tokenId The ID of the token to query the owner for.
     * @return The address of the owner of the specified token ID, or address(0) if the token ID does not exist or is owned by multiple addresses.
     */
    function ownerOf(uint256 tokenId) 
        public 
        view 
        override(ERC721Upgradeable, IERC721Upgradeable) 
        returns (address) 
    {
        address owner = address(uint160(tokenId));

        return balanceOf(owner) == 1 ? owner : address(0);
    }

    /**
     * @dev Returns the balance of the specified account.
     * @param account The address for which to check the balance.
     * @return The balance of the account. Returns 0 if the subscription period has expired, otherwise returns 1.
     */
    function balanceOf(address account) 
        public 
        view 
        override(ERC721Upgradeable, IERC721Upgradeable) 
        returns (uint256) 
    {
        return  _userPayment[account] + _subscriptionDetails.period < block.timestamp ? 0 : 1;
    }


    /**
     * @dev Returns the token ID owned by the specified address.
     * @param owner The address to query the token ID for.
     * @return The token ID owned by the specified address, or 0 if the address does not own any tokens.
     */
    function tokenOf(address owner) public view returns (uint256) {
        return balanceOf(owner) == 1 ? uint256(uint160(owner)) : 0;
    }

    /**
     * @dev Internal function to burn a specific token.
     * Overrides the `_burn` function from both `ERC721Upgradeable` and `ERC721URIStorageUpgradeable`.
     * Calls the `_burn` function from the parent contract `ERC721Upgradeable` to burn the token.
     * @param tokenId The ID of the token to be burned.
     */
    function _burn(uint256 tokenId) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
    }

    /**
     * @dev Checks if a contract supports a given interface.
     * It overrides the supportsInterface function from ERC721Upgradeable and ERC721URIStorageUpgradeable contracts.
     * @param interfaceId The interface identifier.
     * @return A boolean value indicating whether the contract supports the given interface.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Updates the payment information for a given account.
     * @param account The address of the account to update the payment for.
     * @param lastPayment The timestamp of the last payment made by the account.
     * @notice This function can only be called by the contract owner (minter).
     */
    function updatePayment (address account, uint256 lastPayment) public onlyMinter {
        _userPayment[account] = lastPayment;
    }

    /**
     * @dev Returns the payment amount for a given account.
     * @param account The address of the account.
     * @return The payment amount for the account.
     */
    function getPayment(address account) public view returns (uint256) {
        return _userPayment[account];
    }

    /**
     * @dev Retrieves the subscription details of the token.
     * @return subscriptionDetails The subscription details of the token.
     */
    function getSubscriptionDetails() public view returns (SubscriptionDetails memory) {
        return _subscriptionDetails;
    }
}
