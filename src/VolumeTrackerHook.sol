// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import "./Access.sol";
import "./Option.sol";

contract VolumeTrackerHook is BaseHook, Access, Option {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------
    uint256 public ratio;
    uint256 public min = 12; // the minimum is 1.2
    uint256 public max = 32; // the maximim is 3.2
    // if the liquidity is greater than the threshold, the strike price corresponds to the min
    uint256 public threshold = 1000000; 
    address public okb;

    mapping(address user => uint256 swapAmount) public afterSwapCount;

    constructor(
        IPoolManager _poolManager,
        string memory _uri,
        uint256 _ratio,
        uint256 _initialTwapPrice,
        address _okb,
        address _admin,
        address _keeper
    ) BaseHook(_poolManager) Access(_admin, _keeper) Option(_uri, _initialTwapPrice) {
        ratio = _ratio;
        okb = _okb;
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
        address user,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        if(Currency.wrap(address(0)) < Currency.wrap(okb)){
            // If this is not an ETH-OKB pool with this hook attached, ignore
            if (!key.currency0.isNative() && Currency.unwrap(key.currency1) != okb) return (this.afterSwap.selector, 0);

            // We only consider swaps in one direction (in our case when user buys OKB)
            if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);
        } else {
            // If this is not an OKB-ETH pool with this hook attached, ignore
            if (!key.currency1.isNative() && Currency.unwrap(key.currency0) != okb) return (this.afterSwap.selector, 0);

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

        uint256 positionId = uint256(keccak256(abi.encode(key.toId())));

        // I'm not really sure if this is the way that we would like to measure the liquidity
        uint256 liquidity = address(this).balance + IERC20(okb).balanceOf(address(this));
        uint256 strikePrice;

        // Considering the two-point form equation of the straight line  y - y1 = (y2 - y1)/(x2 - x1)(x - x1)
        // x is the liquidity and y is the strike price
        // The two points that are known are (x2, y2) = (0, max * price) and (x1, y1) = (threshold, min * price)
        // Substituting in the formula, we have y = min * price + (max * price) / threshold * (threshold - x)
        if(liquidity > threshold){
            // This is the constant line of the piecewise function 
            strikePrice = (twapPrice.price * min) / 10;
        } else {
            // This is the the decreasing straight line of the piecewise function that is obtained from the
            // formula described above
            strikePrice = (twapPrice.price * min) / 10 + 
            ((max - min) * twapPrice.price / (10 * threshold)) * (threshold - liquidity);
        }

        // Considering that expiryPrice = spotPrice/ y 
        // -> expiryPrice = spotPrice/ (strikePrice/spotPrice) = spotPrice*spotPrice/strikePrice
        uint256 expiryPrice = (twapPrice.price / strikePrice) * twapPrice.price;

        _mintOption(user, swapAmount / ratio, strikePrice, expiryPrice);

        return (this.afterSwap.selector, 0);
    }

    function updateRatio(uint256 newRatio) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRatio > 0, "newRatio ratio not valid");

        ratio = newRatio;
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
}
