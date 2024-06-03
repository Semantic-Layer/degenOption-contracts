// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

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
    address public guh;

    mapping(address user => uint256 swapAmount) public afterSwapCount;

    constructor(
        IPoolManager _poolManager,
        string memory _uri,
        uint256 _ratio,
        uint256 _initialTwapPrice,
        address _guh,
        address _admin,
        address _keeper
    ) BaseHook(_poolManager) Access(_admin, _keeper) Option(_uri, _initialTwapPrice) {
        ratio = _ratio;
        guh = _guh;
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
        if(Currency.wrap(address(0)) < Currency.wrap(guh)){
            // If this is not an ETH-GUH pool with this hook attached, ignore
            if (!key.currency0.isNative()) return (this.afterSwap.selector, 0);

            // If this is not an ETH-GUH pool with this hook attached, ignore
            if (Currency.unwrap(key.currency1) != guh) return (this.afterSwap.selector, 0);

            // We only consider swaps in one direction (in our case when user buys GUH)
            if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);
        } else {
            // If this is not an GUH-ETH pool with this hook attached, ignore
            if (!key.currency1.isNative()) return (this.afterSwap.selector, 0);

            // If this is not an GUH-ETH pool with this hook attached, ignore
            if (Currency.unwrap(key.currency0) != guh) return (this.afterSwap.selector, 0);

            // We only consider swaps in one direction (in our case when user buys GUH)
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

        afterSwapCount[user] += swapAmount;
        _mint(user, positionId, swapAmount / ratio, "");

        return (this.afterSwap.selector, 0);
    }

    function updateRatio(uint256 newRatio) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRatio != 0);

        ratio = newRatio;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, Option) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
