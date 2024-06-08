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

    address create2depoyProxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    PoolManager poolManager = PoolManager(0x75E7c1Fd26DeFf28C7d1e82564ad5c24ca10dB14);
    PoolSwapTest poolSwapTest = PoolSwapTest(0xB8b53649b87F0e1eb3923305490a5cB288083f82);

    // hookAddress = 0x26309e1Ac538e0731242ac060923800a57B28040;

    MockERC20 OK = MockERC20(0x9fE71A8fb340E1cC13F61691bCaDDB83aE6c00ac);

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency = Currency.wrap(address(OK));
    VolumeTrackerHook hook;
    NarrativeController NC;

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // OK.mint(address(this), 1000 ether);
        // OK.mint(address(deployer), 1000 ether);

        // console2.log("deploy NC");

        vm.stopBroadcast();
    }
}

contract MineAddress is Script, Deployers {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address internal deployer = vm.addr(deployerPrivateKey);
    address creat2deployerProxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    Create2Deployer create2deployer = Create2Deployer(0x98B2920D53612483F91F12Ed7754E51b4A77919e);
    // Create3Deployer create3deployer = Create3Deployer(0x6513Aedb4D1593BA12e50644401D976aebDc90d8);
    PoolKey poolKey;

    MockERC20 OK = MockERC20(0x9fE71A8fb340E1cC13F61691bCaDDB83aE6c00ac);
    PoolManager poolManager = PoolManager(0x75E7c1Fd26DeFf28C7d1e82564ad5c24ca10dB14);
    PoolSwapTest poolSwapTest = PoolSwapTest(0xB8b53649b87F0e1eb3923305490a5cB288083f82);
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency = Currency.wrap(address(OK));

    DeployFactory deployFactory = DeployFactory(0x617346FACCe2491B840877e99A638902af54DE0B);
    VolumeTrackerHook hook;

    PoolModifyLiquidityTest poolModifyLiquidityRouter =
        PoolModifyLiquidityTest(0x2b925D1036E2E17F79CF9bB44ef91B95a3f9a084);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // (address hookAddress, bytes32 salt) = findAddress(address(creat2deployerProxy));
        // bytes memory deployBytecode = type(VolumeTrackerHook).creationCode;

        // console2.log("deployHook");
        // require(deployBytecode.length != 0, "byte zero");
        // bytes memory creationCodeWithArgs = abi.encodePacked(
        //     type(VolumeTrackerHook).creationCode, abi.encode(address(poolManager), "", 1, address(OK), deployer)
        // );

        // // address hookAddr = deployFactory.deploy(salt, creationCodeWithArgs);
        // // address hookAddr = create2deployer.deploy(creationCodeWithArgs, salt);
        // hook = new VolumeTrackerHook{salt: salt}(poolManager, "", 1, address(OK), deployer);

        // console2.log("hook deployed at", address(hook));
        // require(hookAddress == address(hook), "wrong deploy");

        console2.log("init pool");
        poolKey = PoolKey(ethCurrency, tokenCurrency, 3000, 60, IHooks(0xCd3EB6f3F81b62a4E544Ff513727dE1978078040));
        // poolManager.initialize(poolKey, SQRT_PRICE_1_1, ZERO_BYTES);

        OK.mint(deployer, 1000 ether);
        OK.approve(address(poolModifyLiquidityRouter), type(uint256).max);
        OK.approve(address(poolSwapTest), type(uint256).max);

        console2.log("add liquidity");
        poolModifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
            poolKey,
            IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: 0}),
            ZERO_BYTES
        );

        vm.stopBroadcast();

        // console2.logBytes(bytecode);
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

contract AddLiquidity is Script, Deployers {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address internal deployer = vm.addr(deployerPrivateKey);
    address creat2deployerProxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    MockERC20 OK = MockERC20(0x9fE71A8fb340E1cC13F61691bCaDDB83aE6c00ac);
    PoolManager poolManager = PoolManager(0x75E7c1Fd26DeFf28C7d1e82564ad5c24ca10dB14);
    PoolSwapTest poolSwapTest = PoolSwapTest(0xB8b53649b87F0e1eb3923305490a5cB288083f82);
    PoolModifyLiquidityTest poolModifyLiquidityRouter =
        PoolModifyLiquidityTest(0x2b925D1036E2E17F79CF9bB44ef91B95a3f9a084);
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency = Currency.wrap(address(OK));

    DeployFactory deployFactory = DeployFactory(0x617346FACCe2491B840877e99A638902af54DE0B);
    VolumeTrackerHook hook = VolumeTrackerHook(0xCd3EB6f3F81b62a4E544Ff513727dE1978078040);

    PoolKey poolKey = PoolKey(ethCurrency, tokenCurrency, 3000, 60, IHooks(address(hook)));

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        poolModifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: 0}),
            ZERO_BYTES
        );
        vm.stopBroadcast();
    }
}

contract DeployFactory {
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address) {
        // Deploy the contract using Create2
        address addr = Create2.deploy(0, salt, bytecode);
        return addr;
    }
}

//docs.axelar.dev/dev/solidity-utilities#create2-deployer
interface Create2Deployer {
    function deploy(bytes memory bytecode, bytes32 salt) external returns (address);
}

interface Create3Deployer {
    function deploy(bytes memory bytecode, bytes32 salt) external returns (address);
}
