// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {VolumeTrackerHook} from "../src/VolumeTrackerHook.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract TestVolumeTrackerHook is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolId poolId;
    VolumeTrackerHook hook;

    uint256 internal devPrivatekey = 0xde111;
    uint256 internal keeperPrivateKey = 0x3333;
    uint256 internal okbPrivateKey = 0x1111;

    address internal dev = vm.addr(devPrivatekey);
    address internal keeper = vm.addr(keeperPrivateKey);
    address internal okb = vm.addr(okbPrivateKey);

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this), flags, type(VolumeTrackerHook).creationCode, abi.encode(address(manager), "", 1, 0, okb, dev, keeper)
        );
        hook = new VolumeTrackerHook{salt: salt}(IPoolManager(address(manager)), "", 1, 0, okb, dev, keeper);
        require(address(hook) == hookAddress, "VolumeTrackerHookTest: hook address mismatch");

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide liquidity to the pool
        /*
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether, 0), ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-120, 120, 10 ether, 0), ZERO_BYTES
        );
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether, 0),
            ZERO_BYTES
        );
        */
    }

    function test_addLiquidityAndSwap() public {
        // How we landed on 0.003 ether here is based on computing value of x and y given
        // total value of delta L (liquidity delta) = 1 ether
        // This is done by computing x and y from the equation shown in Ticks and Q64.96 Numbers lesson
        // View the full code for this lesson on GitHub which has additional comments
        // showing the exact computation and a Python script to do that calculation for you
        modifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: 0}),
            ZERO_BYTES
        );
        /*
        uint256 pointsBalanceAfterAddLiquidity = hook.balanceOf(address(this));

        // The exact amount of ETH we're adding (x)
        // is roughly 0.299535... ETH
        // Our original POINTS balance was 0
                // so after adding liquidity we should have roughly 0.299535... POINTS tokens
        assertApproxEqAbs(
            pointsBalanceAfterAddLiquidity - pointsBalanceOriginal,
            2995354955910434,
            0.0001 ether // error margin for precision loss
        );
        */
        //Check the mapping before the swap
        //hook.afterSwapCount(address(this));
        //console2.log(hook.afterSwapCount(address(this)));

        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false}),
            ZERO_BYTES
        );
        /*
        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));
        assertEq(
            pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity,
            2 * 10 ** 14
        );
        */
        // Check the mapping after the swap
        //hook.afterSwapCount(address(this));
        //console2.log(hook.afterSwapCount(address(this)));
    }
}
