// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
import {Script, console} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "../src/VolumeTrackerHook.sol";
import "../src/NarrativeController.sol";
import "../test/HookMiner.sol";
contract Deploy is Script, Deployers {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address internal deployer = vm.addr(deployerPrivateKey);

    PoolManager poolManager = PoolManager("0xf7a031A182aFB3061881156df520FE7912A51617");

    MockERC20 OK;

    NarrativeController NC;


    function run() public {
        vm.startBroadcast(deployerPrivateKey);

         (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(VolumeTrackerHook).creationCode,
            abi.encode(address(manager), "", 1, address(token), dev, keeper)
        );

        console.log("deploy hook");
        // console.log("deploy $OK");
        // OK = new MockERC20("OK Token", "OK", 18);
        // console.log("$OK deployed at", address(OK));

        // OK.mint(address(this), 1000 ether);
        // OK.mint(address(deployer), 1000 ether);

        // console.log("deploy NC");
        




        vm.stopBroadcast();
    }
    
}