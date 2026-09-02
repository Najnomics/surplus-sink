// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {SurplusSinkHook} from "../src/SurplusSinkHook.sol";
import {UnichainFairOracle} from "../src/UnichainFairOracle.sol";

contract SurplusSinkHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;

    uint256 relayerPk = 0xA11CE;
    address relayer;
    PoolKey poolKey;
    PoolId poolId;
    SurplusSinkHook hook;
    UnichainFairOracle oracle;
    Currency currency0;
    Currency currency1;

    function setUp() public {
        relayer = vm.addr(relayerPk);
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        oracle = new UnichainFairOracle(address(this), address(0), address(0));
        oracle.setBuilder(address(this), true);

        address flags = address(
            uint160(
                Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                    | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144)
        );
        deployCodeTo(
            "SurplusSinkHook.sol:SurplusSinkHook", abi.encode(poolManager, address(this), relayer, oracle), flags
        );
        hook = SurplusSinkHook(flags);

        poolKey = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        int24 lo = TickMath.minUsableTick(60);
        int24 hi = TickMath.maxUsableTick(60);
        uint128 liq = 100e18;
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(lo), TickMath.getSqrtPriceAtTick(hi), liq
        );
        positionManager.mint(poolKey, lo, hi, liq, a0 + 1, a1 + 1, address(this), block.timestamp, Constants.ZERO_BYTES);
    }

    function _privateData(uint256 nonce) internal view returns (bytes memory) {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(abi.encode(hook.RECEIPT_TYPEHASH(), deadline, nonce, PoolId.unwrap(poolId)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPk, digest);
        return abi.encode(deadline, nonce, v, r, s);
    }

    function test_publicSwapPaysTax() public {
        swapRouter.swapExactTokensForTokens({
            amountIn: 10e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "",
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertGt(hook.totalPublicTaxDonated(poolId), 0);
    }

    function test_privateReceiptNoTax() public {
        swapRouter.swapExactTokensForTokens({
            amountIn: 10e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: _privateData(1),
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertEq(hook.totalPublicTaxDonated(poolId), 0);
    }

    function test_receiptReplayReverts() public {
        bytes memory data = _privateData(7);
        swapRouter.swapExactTokensForTokens({
            amountIn: 5e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: data,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: 5e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: data,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_attestedHeartbeatIsPrivate() public {
        oracle.incrementFlashblock();
        swapRouter.swapExactTokensForTokens({
            amountIn: 10e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: "",
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertEq(hook.totalPublicTaxDonated(poolId), 0);
    }

    function test_creditSurplusFromRelayer() public {
        uint256 amount = 10e18;
        MockERC20 token = MockERC20(Currency.unwrap(currency0));
        token.mint(relayer, amount);
        vm.startPrank(relayer);
        IERC20(address(token)).approve(address(hook), amount);
        hook.creditSurplus(poolKey, true, amount);
        vm.stopPrank();
        assertEq(hook.totalSurplusDonated(poolId), amount);
    }

    function test_unauthorizedCreditReverts() public {
        vm.expectRevert(SurplusSinkHook.NotRelayer.selector);
        hook.creditSurplus(poolKey, true, 1e18);
    }

    function test_badReceiptReverts() public {
        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: bytes("not-a-receipt"),
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_expiredReceiptReverts() public {
        uint256 deadline = block.timestamp - 1;
        bytes32 structHash = keccak256(abi.encode(hook.RECEIPT_TYPEHASH(), deadline, uint256(1), PoolId.unwrap(poolId)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(relayerPk, digest);
        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: abi.encode(deadline, uint256(1), v, r, s),
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_creditSurplusToken1() public {
        uint256 amount = 4e18;
        MockERC20 token = MockERC20(Currency.unwrap(currency1));
        token.mint(relayer, amount);
        vm.startPrank(relayer);
        IERC20(address(token)).approve(address(hook), amount);
        hook.creditSurplus(poolKey, false, amount);
        vm.stopPrank();
        assertEq(hook.totalSurplusDonated(poolId), amount);
    }

    function test_creditZeroReverts() public {
        vm.prank(relayer);
        vm.expectRevert(SurplusSinkHook.ZeroAmount.selector);
        hook.creditSurplus(poolKey, true, 0);
    }

    function test_setRelayerRevoke() public {
        hook.setRelayer(relayer, false);
        vm.prank(relayer);
        vm.expectRevert(SurplusSinkHook.NotRelayer.selector);
        hook.creditSurplus(poolKey, true, 1e18);
    }

    function test_wrongSignerReceipt() public {
        uint256 pk2 = 0xB0B;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(abi.encode(hook.RECEIPT_TYPEHASH(), deadline, uint256(3), PoolId.unwrap(poolId)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk2, digest);
        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: abi.encode(deadline, uint256(3), v, r, s),
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function test_permissions() public {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.beforeSwap && p.afterSwap && p.afterSwapReturnDelta);
        assertFalse(p.beforeSwapReturnDelta);
    }

    function test_staticFeeInitReverts() public {
        PoolKey memory staticKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        vm.expectRevert();
        poolManager.initialize(staticKey, Constants.SQRT_PRICE_1_1);
    }
}
