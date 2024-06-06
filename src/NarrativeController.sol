// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol"; // not for production

import "./libraries/TickPriceLib.sol";
import "./Option.sol";

contract NarrativeController is IERC1155Receiver, Ownable2Step {
    using SafeERC20 for IERC20;

    address public constant ETH = address(0);

    ///@notice the token user can buy with option tokens. e.g. protocol governance token
    IERC20 public immutable TOKEN;

    ///@notice option token contract (ERC1155)
    Option public immutable OPTION;

    ///@notice uniswapV4 pool key
    PoolKey public POOL_KEY;

    ///@notice uniswapV4 swap router
    PoolSwapTest public SWAP_ROUTER;

    ///@notice true: buy back hook is on. false: buy back hook is off
    bool public buyBackHookControl;

    // ============ errors & events =============
    error InValidOptionTokenId();
    error InsufficientOptionTokenBalance();
    error InsufficientETHBalance();

    event BuyBackHookControllSet(bool indexed val);
    event OptionExercised(address indexed user, uint256 indexed id, uint256 indexed amount);

    constructor(address owner, IERC20 token, Option option, PoolKey memory poolKey, PoolSwapTest swapRouter)
        Ownable(owner)
    {
        TOKEN = token;
        OPTION = option;
        POOL_KEY = poolKey;
        SWAP_ROUTER = swapRouter;
    }

    /**
     * @notice exercise option by providng the option token id
     * @param tokenId option token id
     * @param amount the amount of options user wants to exercise
     */
    function exerciseOptionByTokenId(uint256 tokenId, uint256 amount) public payable {
        // check pool token balance. if balance <= amount. we only redeem partially
        uint256 poolBalance = TOKEN.balanceOf(address(this));
        if (poolBalance == 0) return;
        if (poolBalance < amount) {
            // partial redeem
            amount = poolBalance;
        }

        // check if the option tokenId is valid
        if (!OPTION.isOptionTokenValid(tokenId)) {
            revert InValidOptionTokenId();
        }

        // check user's option token balance
        if (OPTION.balanceOf(msg.sender, tokenId) < amount) {
            revert InsufficientOptionTokenBalance();
        }

        // calculate how much user should pay
        (,, uint256 strikePrice,) = OPTION.tokenId2Option(tokenId);
        uint256 ethAmountToPay =
            TickPriceLib.getQuoteAtSqrtPrice(uint160(strikePrice), uint128(amount), address(TOKEN), ETH);
        if (msg.value < ethAmountToPay) {
            revert InsufficientETHBalance();
        }

        // burn user's option token
        OPTION.burn(msg.sender, tokenId, amount);

        // transfer token bought to user
        TOKEN.safeTransfer(msg.sender, amount);
        _buyBackHook(ethAmountToPay);

        emit OptionExercised(msg.sender, tokenId, amount);
    }

    // ================= internal function ==============

    /**
     * @dev it swap exact amount of ETH into $TOKEN
     * @param amount the amount of tokens to swap. Negative is an exact-input swap
     */
    function _buyBackHook(uint256 amount) internal {
        if (buyBackHookControl) {
            uint160 MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
            uint160 MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;
            bool zeroForOne = ETH < address(TOKEN) ? true : false;
            IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amount),
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT // unlimited impact
            });
            PoolSwapTest.TestSettings memory testSettings =
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

            SWAP_ROUTER.swap(POOL_KEY, swapParams, testSettings, "");
        }
    }

    // ===== required override =======
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
