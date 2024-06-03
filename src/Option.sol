// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./Access.sol";

/**
 * @title ERC1155 Option Contract
 * @author @semanticlayer
 * @dev the prices used in the contract refer to `sqrt(1.0001^tick) * 2^96` (tick.getSqrtPriceAtTick())
 */
abstract contract Option is ERC1155, ERC1155Supply, Access {
    using EnumerableSet for EnumerableSet.UintSet;

    ///@dev struct to store the Option info of an option token
    /// option with the same strike price and expiry price will be minted under the same token id
    // a new tokenId will be used for the option if the previous option token has been voided
    /// call `isOptionTokenValid()` function to check if the current option token is valid
    struct OptionToken {
        uint256 tokenId;
        uint256 strikePrice;
        uint256 expiryPrice;
    }

    ///@dev struct for twap price update related information
    struct TwapPrice {
        uint256 price; // twap price
        uint256 intervalCount; // `block.timestamp/TWAP_INTERVAL`. the time when the twap price is updated. it's xth `TWAP_INTERVAL` interval time. not timestamp. it allows keeper to void options as long as it's within the same 30min gap
        uint256 timestamp; // block.timestamp when the twap price is updated
    }

    ///@notice interval for updating twap price
    uint256 public constant TWAP_INTERVAL = 30 minutes;

    ///@notice next tokenId to mint a new type of option token
    ///@dev a valid tokenId starting from 1
    uint256 public nextTokenId = 1; //

    ///@notice latest twap price related information
    TwapPrice public latestTwapPrice;

    ///@notice store the option info of a option token
    mapping(uint256 tokenId => OptionToken option) public tokenId2Option;

    ///@notice return the valid option token ids of the expiry price
    ///@dev use EnumerableSet instead of array as we need to check if the token id is valid upton minting new option tokens
    mapping(uint256 expiryPrice => EnumerableSet.UintSet tokenIds) private expiryPrice2TokenIds;

    ///@notice get the current valid token Id with option strike price and expiry price
    ///@dev key is keccake256(abi.encode(strikePrice, expiryPrice))
    mapping(bytes32 option => uint256 tokenId) public option2TokenId;

    /// ======== errors and events =======
    error NotHook();
    error InvalidInterval();

    event TWAPPriceUpdated(uint256 newPrice, uint256 updateTime);

    constructor(string memory uri_, uint256 initialPrice_) ERC1155(uri_) {
        _updateTWAPPrice(initialPrice_);
    }

    /**
     * @notice hook call this function to mint option tokens for user
     * @dev the option token id is determined by the option strike price and expiry price.
     * @param user the address to receive the minted option token
     * @param amount the amount of option token to mint
     * @param strikePrice the option strike price
     * @param expiryPrice the option expiry price
     */
    function _mintOption(address user, uint256 amount, uint256 strikePrice, uint256 expiryPrice) internal {
        bytes32 optionKey = getOptionKey(strikePrice, expiryPrice);
        uint256 id = option2TokenId[optionKey];
        bool isValid = isOptionTokenValid(id);

        if (isValid) {
            // a valid option token already exists

            _mint(user, id, amount, "");
        } else {
            // use a new token id the option with the same strike price and expiry price

            // increment the nextTokenId after using its value for the new token id
            uint256 newTokenId = nextTokenId++;
            _mint(user, newTokenId, amount, "");

            // update option info for this new option token
            tokenId2Option[newTokenId] =
                OptionToken({tokenId: newTokenId, strikePrice: strikePrice, expiryPrice: expiryPrice});

            // add this new tokenId into expiryPrice2TokenIds
            expiryPrice2TokenIds[expiryPrice].add(nextTokenId);

            // update option2TokenId
            option2TokenId[optionKey] = nextTokenId;
        }
    }

    // =========== keeper functions ==============

    /**
     * @notice keeper call this function to update twap price every interval time
     * @dev only be called once every `TWAP_INTERVAL` time.
     * @param price twap price to update
     */
    function updateTWAPPrice(uint256 price) public onlyRole(KEEPER_ROLE) {
        if (block.timestamp <= latestTwapPrice.timestamp + TWAP_INTERVAL) {
            revert InvalidInterval();
        }
        _updateTWAPPrice(price);
    }

    /**
     * @notice keeper call this function to void options that met the expiry price condition
     * @dev It can be called between updates of the twap price. As long as the twap price is not update. keeper can call this function
     *      There options to void might exceed the limits we can call in one tx. So we design this with the time flexibity.
     * @param twapPrice_ twap price
     * @param expiryPrices_  we void options with these expiry prices
     */
    function voidOptions(uint256 twapPrice_, uint256[] calldata expiryPrices_) public onlyRole(KEEPER_ROLE) {
        uint256 length = expiryPrices_.length;
        for (uint256 i = 0; i < length; i++) {
            _voidOption(twapPrice_, expiryPrices_[i]);
        }
    }

    // ==================== utils ============================
    /**
     * @notice get the key value for mapping `option2TokenId`
     * @param strikePrice_ strike price
     * @param expiryPrice_ expiry price
     */
    function getOptionKey(uint256 strikePrice_, uint256 expiryPrice_) public pure returns (bytes32 key) {
        key = keccak256(abi.encode(strikePrice_, expiryPrice_));
    }

    /**
     * @notice it returns the corresponding option token id with option strike price and expiry price.
     * if the id is zero, it means the option token does not exists.
     * @dev it only returns id. use `isOptionTokenValid` to check if the option token is valid or not.
     * @param strikePrice_ option strike price
     * @param expiryPrice_ option expiry price
     */
    function getTokenId(uint256 strikePrice_, uint256 expiryPrice_) public view returns (uint256 id) {
        id = option2TokenId[getOptionKey(strikePrice_, expiryPrice_)];
    }

    /**
     * @notice check if an option token is valid
     *  true: valid. can be exercised
     *  false: option token does not exist or has been voided
     * @param tokenId_ token id
     */
    function isOptionTokenValid(uint256 tokenId_) public view returns (bool) {
        if (tokenId_ == 0) {
            return false;
        }
        uint256 expiryPrice = tokenId2Option[tokenId_].expiryPrice;
        if (expiryPrice == 0) {
            return false;
        }
        return expiryPrice2TokenIds[expiryPrice].contains(tokenId_);
    }

    /**
     * @notice given an expiry price, return the total number of valid option tokens.
     * @param expiryPrice_  expiry price
     */
    function getNumberOfValidToken(uint256 expiryPrice_) public view returns (uint256) {
        return expiryPrice2TokenIds[expiryPrice_].length();
    }

    /**
     * @notice given the expiry price, return an array of valid token ids from index start to end
     * @dev
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     * @param expiryPrice_ option expiry price
     * @param start_ start index. it must <= end_
     * @param end_  end index. it must be strictly less than the enumerate set length (fetch length by function `getNumberOfValidToken()`)
     */
    function getValidTokenIdByExpiryPrice(uint256 expiryPrice_, uint256 start_, uint256 end_)
        public
        view
        returns (uint256[] memory validTokenIds)
    {
        for (uint256 i = start_; i <= end_; i++) {
            validTokenIds[i - start_] = (expiryPrice2TokenIds[expiryPrice_].at(i));
        }
    }

    // ==================== private functions ====================
    /**
     * @dev it deletes all the tokens under expiryPrice2TokenIds[expiryPrice_] if the expiryPrice_ <= twapPrice_
     * @param twapPrice_ twap price
     * @param expiryPrice_ we void options with this expiry price
     */
    function _voidOption(uint256 twapPrice_, uint256 expiryPrice_) private {
        if (twapPrice_ <= expiryPrice_) {
            // Get the set of token IDs associated with the expiry price
            EnumerableSet.UintSet storage tokenIds = expiryPrice2TokenIds[expiryPrice_];

            // Iterate over the set and remove each token ID
            while (tokenIds.length() > 0) {
                uint256 tokenId = tokenIds.at(0);
                tokenIds.remove(tokenId);
            }

            // Optionally, delete the entry from the mapping if the set is empty
            // This is optional since the set will be empty and won't consume much gas, but
            // it might be useful to remove the mapping entry entirely
            delete expiryPrice2TokenIds[expiryPrice_];
        }
    }

    /**
     * @dev it updates `twapPrice` and emit event
     * @param price twap price to update
     */
    function _updateTWAPPrice(uint256 price) private {
        uint256 time = block.timestamp / TWAP_INTERVAL;
        latestTwapPrice = TwapPrice({
            price: price,
            intervalCount: time, // the Xth interval times
            timestamp: block.timestamp
        });
        emit TWAPPriceUpdated(price, time);
    }

    // =========== funcitons required to override ======================
    function _update(address from_, address to_, uint256[] memory ids_, uint256[] memory values_)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from_, to_, ids_, values_);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
