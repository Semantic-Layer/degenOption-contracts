// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import "../src/VolumeTrackerHook.sol";
import "../src/NarrativeController.sol";
import "../test/utils/HookMiner.sol";

contract Deploy is Script, Deployers {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address internal deployer = vm.addr(deployerPrivateKey);
    PoolKey poolKey;
    address creat2deployerProxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    MockERC20 OK = MockERC20(0x9fE71A8fb340E1cC13F61691bCaDDB83aE6c00ac);
    PoolManager poolManager = PoolManager(0x75E7c1Fd26DeFf28C7d1e82564ad5c24ca10dB14);
    PoolSwapTest poolSwapTest = PoolSwapTest(0xB8b53649b87F0e1eb3923305490a5cB288083f82);
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency = Currency.wrap(address(OK));
    VolumeTrackerHook hook;

    PoolModifyLiquidityTest poolModifyLiquidityRouter =
        PoolModifyLiquidityTest(0x2b925D1036E2E17F79CF9bB44ef91B95a3f9a084);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // (address hookAddress, bytes32 salt) = findAddress(address(creat2deployerProxy));
        // bytes memory deployBytecode = type(VolumeTrackerHook).creationCode;
        // console2.log("deployHook");
        // require(deployBytecode.length != 0, "byte zero");

        // hook = new VolumeTrackerHook{salt: salt}(poolManager, "", 1, address(OK), deployer);
        // console2.log("hook deployed at", address(hook));
        // require(hookAddress == address(hook), "wrong deploy");

        // console2.log("init pool");
        // poolKey = PoolKey(ethCurrency, tokenCurrency, 3000, 60, IHooks(address(hook)));
        // poolManager.initialize(poolKey, SQRT_PRICE_1_1, ZERO_BYTES);

        // console2.log("mint ok tokens for adding liquidity");
        // OK.mint(deployer, 1000 ether);
        // OK.approve(address(poolModifyLiquidityRouter), type(uint256).max);
        // OK.approve(address(poolSwapTest), type(uint256).max);

        // console2.log("add liquidity");
        // poolModifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
        //     poolKey,
        //     IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: 0}),
        //     ZERO_BYTES
        // );

        console2.log("swap");
        poolKey = PoolKey(ethCurrency, tokenCurrency, 3000, 60, IHooks(address(0x8Db2126407C061e04092b0e1FA0e941E94BE0040)));
        poolSwapTest.swap{value: 0.001 ether}(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false}),
            ""
        );

        vm.stopBroadcast();
    }

    function findAddress(address deployer_) public view returns (address, bytes32) {
        console2.log("finding address");
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer_,
            flags,
            type(VolumeTrackerHook).creationCode,
            abi.encode(address(poolManager), "", 1, address(OK), deployer)
        );

        console2.log("found address", hookAddress);
        console2.logBytes32(salt);

        return (hookAddress, salt);
    }
}
