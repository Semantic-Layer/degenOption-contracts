// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "./Access.sol";

abstract contract Option is ERC1155, ERC1155Supply, Access {
    struct OptionToken {
        uint256 tokenId;
        uint256 strikePrice;
        uint256 expiryPrice;
    }

    struct TwapPrice {
        uint256 price; // twap price
        uint256 intervalCount; // the time when the twap price is updated. it's xth 30min. not timestamp. it allows keeper to void options as long as it's within the same 30min gap
        uint256 timestamp;
    }

    uint256 public constant TWAP_INTERVAL = 30 minutes;

    uint256 public nextTokenId; // tokenId starting from 1

    TwapPrice public twapPrice;

    mapping(uint256 expiryPrice => uint256[] tokenIds) public expiryPrice2TokenIds;
    mapping(uint256 tokenId => OptionToken option) public tokenId2Option;

    // key is keccake256(abi.encode(strikePrice, expiryPrice))
    mapping(bytes32 option => uint256 tokenId) public option2TokenId;

    error NotHook();
    error InvalidInterval();
    // Event to emit when the price is updated

    event TWAPPriceUpdated(uint256 newPrice, uint256 updateTime);

    constructor(string memory uri_, uint256 initialPrice_) ERC1155(uri_) {
        _updateTWAPPrice(initialPrice_);
    }

    function _mintOption(address user, uint256 amount, uint256 strikePrice, uint256 expiryPrice) internal {
        bytes32 optionKey = getOptionKey(strikePrice, expiryPrice);
        uint256 id = option2TokenId[optionKey];

        if (id != 0) {
            // a valid option token already exists
            _mint(user, id, amount, "");
        } else {
            // the option does not have a valid token yet. we need to mint a new token
            nextTokenId++; // a valid token id starts from 1.
            _mint(user, nextTokenId, amount, "");

            // add this new tokenId into expiryPrice2TokenIds
            expiryPrice2TokenIds[expiryPrice].push(nextTokenId);

            // update option2TokenId
            option2TokenId[optionKey] = nextTokenId;
        }
    }

    function _updateTWAPPrice(uint256 price) internal {
        uint256 time = block.timestamp / TWAP_INTERVAL;
        twapPrice = TwapPrice({
            price: price,
            intervalCount: time, // the Xth interval times
            timestamp: block.timestamp
        });
        emit TWAPPriceUpdated(price, time);
    }

    /**
     * @notice keeper call this function to update twap price every interval time
     * @dev only be called once every `TWAP_INTERVAL` time.
     * @param price twap price to update
     */
    function updateTWAPPrice(uint256 price) public onlyRole(KEEPER_ROLE) {
        if (block.timestamp <= twapPrice.timestamp + TWAP_INTERVAL) {
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

    function getOptionKey(uint256 strikePrice_, uint256 expiryPrice_) public pure returns (bytes32 key) {
        key = keccak256(abi.encode(strikePrice_, expiryPrice_));
    }

    function _voidOption(uint256 twapPrice_, uint256 expiryPrice_) internal {
        if (twapPrice_ <= expiryPrice_) {
            delete expiryPrice2TokenIds[expiryPrice_];
        }
    }

    // it returns the corresponding option token id with option strike price and expiry price.
    function getTokenId(uint256 strikePrice_, uint256 expiryPrice_) public view returns (uint256 id) {
        id = option2TokenId[getOptionKey(strikePrice_, expiryPrice_)];
    }

    /**
     * @notice check if an option token is valid
     *  true: valid. can be exercised
     *  false: option token does not exist or has been voided
     * @param option_ option token to check
     */
    function isOptionTokenValid(OptionToken memory option_) public view returns (bool) {
        return arrayContains(expiryPrice2TokenIds[option_.expiryPrice], option_.tokenId);
    }

    function arrayContains(uint256[] memory array_, uint256 item_) public pure returns (bool) {
        for (uint256 i = 0; i < array_.length; i++) {
            if (array_[i] == item_) {
                return true;
            }
        }
        return false;
    }

    // The following functions are overrides required by Solidity.
    function _update(address from_, address to_, uint256[] memory ids_, uint256[] memory values_)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from_, to_, ids_, values_);
    }

    // Override supportsInterface
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
