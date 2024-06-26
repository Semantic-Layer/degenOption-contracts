// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import "./Access.sol";
import "./Option.sol";

contract VolumeTrackerHook is BaseHook, Access, Option {
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------
    uint256 public constant DIVIDE_FACTOR = 1000;
    uint256 public factor;
    address public developer;
    uint256 public min = 12; // the minimum is 1.2
    uint256 public max = 32; // the maximim is 3.2
    // if the liquidity is greater than the threshold, the strike price corresponds to the min
    uint256 public threshold = 100 ether;
    address public immutable OK;

    PoolId public immutable id;

    mapping(address user => uint256 swapAmount) public afterSwapCount;

    constructor(IPoolManager _poolManager, string memory _uri, uint256 _ratio, address _okb, address _admin)
        BaseHook(_poolManager)
        Access(_admin)
        Option(_uri)
    {
        factor = _ratio;
        OK = _okb;
        id = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(_okb)), 3000, 60, IHooks(address(this))).toId();
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookdata
    ) external override poolManagerOnly returns (bytes4, int128) {
        // The address which should receive the option should be set as an input in hookdata
        address user = abi.decode(hookdata, (address));

        if (Currency.wrap(address(0)) < Currency.wrap(OK)) {
            // If this is not an ETH-OKB pool with this hook attached, ignore
            if (!key.currency0.isNative() && Currency.unwrap(key.currency1) != OK) return (this.afterSwap.selector, 0);

            // We only consider swaps in one direction (in our case when user buys OKB)
            if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);
        } else {
            // If this is not an OKB-ETH pool with this hook attached, ignore
            if (!key.currency1.isNative() && Currency.unwrap(key.currency0) != OK) return (this.afterSwap.selector, 0);

            // We only consider swaps in one direction (in our case when user buys OKB)
            if (swapParams.zeroForOne) return (this.afterSwap.selector, 0);
        }

        // if amountSpecified < 0:
        //      this is an "exact input for output" swap
        //      amount of tokens they spent is equal to |amountSpecified|
        // if amountSpecified > 0:
        //      this is an "exact output for input" swap
        //      amount of tokens they spent is equal to BalanceDelta.amount0()

        uint256 swapAmount =
            swapParams.amountSpecified < 0 ? uint256(-swapParams.amountSpecified) : uint256(int256(-delta.amount0()));

        // get the current tick
        (, int24 tick,,) = poolManager.getSlot0(key.toId());

        // get the spot price as sqrt price
        uint256 spotPrice = TickMath.getSqrtPriceAtTick(tick);

        // get current liquidity
        uint256 liquidity = poolManager.getLiquidity(key.toId());

        uint256 strikePrice;

        // Considering the two-point form equation of the straight line  y - y1 = (y2 - y1)/(x2 - x1)(x - x1)
        // x is the liquidity and y is the strike price
        // The two points that are known are (x2, y2) = (0, max * price) and (x1, y1) = (threshold, min * price)
        // Substituting in the formula, we have y = min * price + (max * price) / threshold * (threshold - x)
        if (liquidity > threshold) {
            // This is the constant line of the piecewise function
            strikePrice = (spotPrice * min) / 10;
        } else {
            // This is the the decreasing straight line of the piecewise function that is obtained from the
            // formula described above
            strikePrice =
                (spotPrice * min) / 10 + ((max - min) * spotPrice / (10 * threshold)) * (threshold - liquidity);
        }

        // Considering that expiryPrice = spotPrice/ y
        // -> expiryPrice = spotPrice/ (strikePrice/spotPrice) = spotPrice*spotPrice/strikePrice
        uint256 expiryPrice = (spotPrice * spotPrice) / strikePrice;

        _mintOption(user, swapAmount * factor / DIVIDE_FACTOR, strikePrice, expiryPrice);

        return (this.afterSwap.selector, 0);
    }

    function updateFactor(uint256 newFactor) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFactor != 0);

        factor = newFactor;
    }

    function updateThreshold(uint256 newThreshold) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newThreshold > 0, "newThreshold value not valid");

        threshold = newThreshold;
    }

    function updateMin(uint256 newMin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMin >= 12 && newMin < max, "newMin value not valid");

        min = newMin;
    }

    function updateMax(uint256 newMax) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMax <= 32 && newMax > min, "newMax value not valid");

        max = newMax;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, Option) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @param tokenId option token to void
     */
    function _voidOptionByTokenId(uint256 tokenId) internal override {
        // get the current tick
        (, int24 tick,,) = poolManager.getSlot0(id);

        // get the spot price as sqrt price
        uint256 spotPrice = TickMath.getSqrtPriceAtTick(tick);
        uint256 expiryPrice = tokenId2Option[tokenId].expiryPrice;
        if (tokenId2Option[tokenId].void) return; // do nothing if it's already voided.
        if (spotPrice <= expiryPrice) {
            EnumerableSet.UintSet storage tokenIds = expiryPrice2TokenIds[expiryPrice];
            tokenIds.remove(tokenId);
            tokenId2Option[tokenId].void = true;
        }
    }

    /**
     * @param expiryPrice_ we void options with this expiry price
     */
    function _voidOptionByExpiryPrice(uint256 expiryPrice_) internal override {
        // get the current tick
        (, int24 tick,,) = poolManager.getSlot0(id);

        // get the spot price as sqrt price
        uint256 spotPrice = TickMath.getSqrtPriceAtTick(tick);
        if (spotPrice <= expiryPrice_) {
            // Get the set of token IDs associated with the expiry price
            EnumerableSet.UintSet storage tokenIds = expiryPrice2TokenIds[expiryPrice_];

            // Iterate over the set and remove each token ID
            while (tokenIds.length() > 0) {
                uint256 tokenId = tokenIds.at(0);
                tokenIds.remove(tokenId);
                tokenId2Option[tokenId].void = true;
            }

            // Optionally, delete the entry from the mapping if the set is empty
            // This is optional since the set will be empty and won't consume much gas, but
            // it might be useful to remove the mapping entry entirely
            delete expiryPrice2TokenIds[expiryPrice_];
        }
    }
}
