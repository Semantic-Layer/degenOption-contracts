// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "@uniswap/v4-core/src/libraries/TickMath.sol";

import "./libraries/TickPriceLib.sol";
import "./Option.sol";

contract NarrativeController is IERC1155Receiver, Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ///@notice the token user can buy with option tokens
    IERC20 public immutable TOKEN;

    ///@notice option token contract (ERC1155)
    Option public immutable OPTION;

    ///@notice true: buy back hook is on. false: buy back hook is off
    bool public buyBackHookControl;

    // ============ errors & events =============
    error InValidOptionTokenId();
    error InsufficientOptionTokenBalance();
    error InsufficientETHBalance();

    event BuyBackHookControllSet(bool indexed val);

    constructor(address owner, address token, address option) Ownable(owner) {
        TOKEN = IERC20(token);
        OPTION = Option(option);
    }

    function exerciseOptionByTokenId(uint256 tokenId, uint256 amount) public payable {
        // check pool token balance. if balance <= amount. we only redeem partially
        uint256 poolBalance = TOKEN.balanceOf(address(this));
        if (poolBalance == 0) return;
        if (poolBalance < amount) {
            // partial redeem
            amount = poolBalance;
        }
        // check if the tokenId is valid
        if (!OPTION.isOptionTokenValid(tokenId)) {
            revert InValidOptionTokenId();
        }

        // check option token balance
        if (OPTION.balanceOf(msg.sender, tokenId) < amount) {
            revert InsufficientOptionTokenBalance();
        }

        (, uint256 strikePrice,) = OPTION.tokenId2Option(tokenId);

        uint256 ethAmountToPay =
            TickPriceLib.getQuoteAtSqrtPrice(uint160(strikePrice), uint128(amount), address(WETH), address(TOKEN));

        if (msg.value < ethAmountToPay) {
            revert InsufficientETHBalance();
        }

        // maybe we should just burn those option tokens?
        OPTION.safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        TOKEN.safeTransfer(msg.sender, amount);

        _buyBackHook();
    }

    function exerciseOptionByPrices(address strikePrice, address expiryPrice, uint256 amount) public payable {
        // get the option token id
        uint256 tokenId = OPTION.option2TokenId(keccak256(abi.encode(strikePrice, expiryPrice)));
        exerciseOptionByTokenId(tokenId, amount);
    }

    function setBuyBackHook(bool val) public onlyOwner {
        buyBackHookControl = val;
        emit BuyBackHookControllSet(val);
    }

    // ================= internal function ==============
    function _buyBackHook() internal {
        if (buyBackHookControl) {
            // zap and seed liquidity
        }
    }

    // ===== required override =======
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
