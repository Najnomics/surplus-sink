// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

interface IMintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IOracle {
    function incrementFlashblock() external;
    function setBuilder(address builder, bool allowed) external;
}

interface ISink {
    function creditSurplus(PoolKey calldata key, bool amountOn0, uint256 amount) external;
    function setRelayer(address relayer, bool allowed) external;
}

/// @notice Relayer-shaped agent: TEE pulse, public tax path, creditSurplus donate.
contract SinkAgent {
    IUniswapV4Router04 public immutable router;
    IOracle public immutable oracle;
    ISink public immutable hook;
    PoolKey public key;

    constructor(IUniswapV4Router04 router_, IOracle oracle_, ISink hook_, PoolKey memory key_) {
        router = router_;
        oracle = oracle_;
        hook = hook_;
        key = key_;
    }

    function arm(IMintable t0, IMintable t1, uint256 mintAmt) external {
        t0.mint(address(this), mintAmt);
        t1.mint(address(this), mintAmt);
        t0.approve(address(router), type(uint256).max);
        t1.approve(address(router), type(uint256).max);
        t0.approve(address(hook), type(uint256).max);
        t1.approve(address(hook), type(uint256).max);
    }

    function burstPrivate(uint256 n, uint256 amountIn) external {
        oracle.incrementFlashblock();
        _burst(n, amountIn);
    }

    function burstPublic(uint256 n, uint256 amountIn) external {
        _burst(n, amountIn);
    }

    function credit(bool amountOn0, uint256 amount) external {
        hook.creditSurplus(key, amountOn0, amount);
    }

    function _burst(uint256 n, uint256 amountIn) internal {
        for (uint256 i; i < n; ++i) {
            router.swapExactTokensForTokens(
                amountIn, 0, i % 2 == 0, key, bytes(""), address(this), block.timestamp + 3600
            );
        }
    }
}

contract PopulateTrafficScript is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        string memory j = vm.readFile("frontend/src/deployed.json");
        address hook = vm.parseJsonAddress(j, ".hook");
        address oracle = vm.parseJsonAddress(j, ".oracle");
        address router = vm.parseJsonAddress(j, ".swapRouter");
        address token0 = vm.parseJsonAddress(j, ".token0");
        address token1 = vm.parseJsonAddress(j, ".token1");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        vm.startBroadcast(pk);
        SinkAgent agent = new SinkAgent(IUniswapV4Router04(payable(router)), IOracle(oracle), ISink(hook), key);
        IOracle(oracle).setBuilder(address(agent), true);
        ISink(hook).setRelayer(address(agent), true);
        agent.arm(IMintable(token0), IMintable(token1), 200_000 ether);
        agent.burstPrivate(6, 2 ether);
        agent.burstPublic(10, 3 ether);
        agent.credit(true, 20 ether);
        agent.burstPrivate(4, 1 ether);
        agent.burstPublic(8, 2 ether);
        agent.credit(false, 15 ether);
        vm.stopBroadcast();

        console2.log("SinkAgent", address(agent));
    }
}
