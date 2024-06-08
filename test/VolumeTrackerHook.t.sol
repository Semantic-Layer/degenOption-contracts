// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

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
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {VolumeTrackerHook} from "../src/VolumeTrackerHook.sol";
import {NarrativeController} from "../src/NarrativeController.sol";
import {Option} from "../src/Option.sol";
import "../src/libraries/TickPriceLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract TestVolumeTrackerHook is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    MockERC20 token;
    VolumeTrackerHook hook;
    NarrativeController narrativeController;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    uint256 internal devPrivatekey = 0xde111;
    uint256 internal okbPrivateKey = 0x1111;
    uint256 internal userPrivateKey = 0xad111;

    address internal user = vm.addr(userPrivateKey);
    address internal dev = vm.addr(devPrivatekey);
    address internal okb = vm.addr(okbPrivateKey);

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();

        // Deploy our OKB token contract
        token = new MockERC20("OKB Token", "OKB", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint a bunch of TOKEN to ourselves
        token.mint(address(this), 1000 ether);

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(VolumeTrackerHook).creationCode,
            abi.encode(address(manager), "", 1, address(token), dev)
        );
        hook = new VolumeTrackerHook{salt: salt}(IPoolManager(address(manager)), "", 1, address(token), dev);
        require(address(hook) == hookAddress, "VolumeTrackerHookTest: hook address mismatch");

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Create the pool
        key = PoolKey(ethCurrency, tokenCurrency, 3000, 60, IHooks(address(hook)));
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Deploy NarrativeController contract
        narrativeController = new NarrativeController(dev, IERC20(address(token)), Option(hook), key, swapRouter);

        // Mint a bunch of TOKEN to the narrative controller contract
        token.mint(address(narrativeController), 1000 ether);

        // Provide liquidity to the pool

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

        bytes memory hookData = abi.encode(address(user));

        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false}),
            hookData
        );
    }

    function test_mintOption() public {
        // Confirm that the option was issued
        assertEq(hook.isOptionTokenValid(1), true);

        // These values were calculated from logging the values directly from the hook
        uint256 strikePrice1 = 251693749733777908291279597518;
        uint256 expiryPrice1 = 24889615696832107675131794113;

        // Get the values of the option from the tokenId
        (bool void, uint256 tokenId, uint256 strikePrice, uint256 expiryPrice) = hook.tokenId2Option(1);

        assertEq(void, false);
        assertEq(strikePrice, strikePrice1);
        assertEq(expiryPrice, expiryPrice1);
        assertEq(tokenId, 1);

        // Confirm that the tokenId corresponds to the strike and expiry price
        assertEq(hook.getTokenId(strikePrice, expiryPrice), 1);

        // Confirm that there is one valid option with the expiry price
        assertEq(hook.getNumberOfValidToken(expiryPrice), 1);
    }

    function test_redeemInNarrativeControlerWithoutBuyBack() public {
        console.log(token.balanceOf(address(narrativeController)));
        console.log(hook.balanceOf(address(user), 1));
        assertEq(hook.isOptionTokenValid(1), true);

        (,, uint256 strikePrice,) = hook.tokenId2Option(1);

        //Let's consider that the user want to redeem the entire option
        uint256 amount = hook.balanceOf(address(user), 1);

        console.log(TickPriceLib.getQuoteAtSqrtPrice(uint160(strikePrice), uint128(amount), address(token), address(0)));

        uint256 ethToSend =
            TickPriceLib.getQuoteAtSqrtPrice(uint160(strikePrice), uint128(amount), address(token), address(0));

        // User wants to redeem the option
        vm.startPrank(user);
        vm.deal(user, 1 ether);

        // Get the balance of the user of ETH and ok
        assertEq(token.balanceOf(address(user)), 0);
        assertEq(user.balance, 1 ether);

        hook.setApprovalForAll(address(narrativeController), true);
        (bool success,) = address(narrativeController).call{value: ethToSend}(
            abi.encodeWithSignature("exerciseOptionByTokenId(uint256,uint256)", 1, amount)
        );
        require(success, "ETH transfer fail");

        // Check that the balances were updated accordingly
        assertEq(token.balanceOf(address(user)), amount);
        assertEq(user.balance, 1 ether - ethToSend);
        vm.stopPrank();
    }

    function test_redeemInNarrativeControlerWithBuyBack() public {
        assertEq(hook.isOptionTokenValid(1), true);

        (,, uint256 strikePrice,) = hook.tokenId2Option(1);

        // Enable buyback
        vm.startPrank(dev);
        assertEq(narrativeController.buyBackHookControl(), false);
        narrativeController.setBuyBack(true);
        assertEq(narrativeController.buyBackHookControl(), true);
        vm.stopPrank();

        //Let's consider that the user want to redeem the entire option
        uint256 amount = hook.balanceOf(address(user), 1);

        console.log(TickPriceLib.getQuoteAtSqrtPrice(uint160(strikePrice), uint128(amount), address(token), address(0)));

        uint256 ethToSend =
            TickPriceLib.getQuoteAtSqrtPrice(uint160(strikePrice), uint128(amount), address(token), address(0));

        // User wants to redeem the option
        vm.startPrank(user);
        vm.deal(user, 1 ether);

        // Get the balance of the user of ETH and ok
        assertEq(token.balanceOf(address(user)), 0);
        assertEq(user.balance, 1 ether);

        hook.setApprovalForAll(address(narrativeController), true);
        (bool success,) = address(narrativeController).call{value: ethToSend}(
            abi.encodeWithSignature("exerciseOptionByTokenId(uint256,uint256)", 1, amount)
        );
        require(success, "ETH transfer fail");

        // Check that the balances were updated accordingly
        assertEq(token.balanceOf(address(user)), amount);
        assertEq(user.balance, 1 ether - ethToSend);
        vm.stopPrank();
    }
}
