// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFairFlowPolicy} from "./interfaces/IFairFlowPolicy.sol";

/// @title SurplusSinkHook
/// @notice Two private ingresses, one LP sink:
///         1. TEE / Flashtestation heartbeat (`policy.isFair`) — attested sequencing.
///         2. EIP-712 receipt from an owner-set Protect / MEV-Share relayer, bound
///            to this pool. Relayer `creditSurplus` donates real tokens to LPs.
///         Public mempool flow pays PUBLIC_FEE + recapture tax. No mock verifier.
contract SurplusSinkHook is BaseHook, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    error NotDynamicFee();
    error NotRelayer();
    error Expired();
    error BadReceipt();
    error ZeroAmount();

    uint24 public constant PRIVATE_FEE = 500;
    uint24 public constant PUBLIC_FEE = 10_000;
    uint256 public constant PUBLIC_TAX_BIPS = 50;

    bytes32 public constant RECEIPT_TYPEHASH = keccak256("PrivateReceipt(uint256 deadline,uint256 nonce,bytes32 poolId)");

    IFairFlowPolicy public immutable policy;
    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(address => bool) public isRelayer;
    mapping(bytes32 => bool) public usedReceipt;
    mapping(PoolId => uint256) public totalPublicTaxDonated;
    mapping(PoolId => uint256) public totalSurplusDonated;

    event RelayerSet(address indexed relayer, bool allowed);
    event SwapClassified(PoolId indexed poolId, bool privatePath, uint24 fee, uint256 taxAmount);
    event SurplusCredited(PoolId indexed poolId, uint256 amount, address currency);

    constructor(IPoolManager _poolManager, address initialOwner, address relayer, IFairFlowPolicy _policy)
        BaseHook(_poolManager)
        Ownable(initialOwner)
    {
        policy = _policy;
        if (relayer != address(0)) isRelayer[relayer] = true;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("SurplusSink")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function setRelayer(address relayer, bool allowed) external onlyOwner {
        isRelayer[relayer] = allowed;
        emit RelayerSet(relayer, allowed);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24) internal pure override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert NotDynamicFee();
        return this.afterInitialize.selector;
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata hookData)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bool priv = _isPrivate(hookData, key.toId());
        if (hookData.length != 0 && !priv) {
            (uint256 deadline,,,,) = abi.decode(hookData, (uint256, uint256, uint8, bytes32, bytes32));
            if (block.timestamp > deadline) revert Expired();
            revert BadReceipt();
        }
        uint24 fee = priv ? PRIVATE_FEE : PUBLIC_FEE;
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128 hookDeltaUnspecified) {
        PoolId poolId = key.toId();
        bool priv = _consumePrivate(hookData, poolId);
        uint24 fee = priv ? PRIVATE_FEE : PUBLIC_FEE;
        uint256 taxAmount;
        if (!priv) {
            (taxAmount, hookDeltaUnspecified) = _recapture(poolId, key, params, delta);
            totalPublicTaxDonated[poolId] += taxAmount;
        }
        emit SwapClassified(poolId, priv, fee, taxAmount);
        return (this.afterSwap.selector, hookDeltaUnspecified);
    }

    /// @notice Authorized Protect / MEV-Share relayer donates surplus already
    ///         pulled from the relayer into this hook.
    function creditSurplus(PoolKey calldata key, bool amountOn0, uint256 amount) external nonReentrant {
        if (!isRelayer[msg.sender]) revert NotRelayer();
        if (amount == 0) revert ZeroAmount();
        Currency c = amountOn0 ? key.currency0 : key.currency1;
        IERC20(Currency.unwrap(c)).safeTransferFrom(msg.sender, address(this), amount);
        poolManager.unlock(abi.encode(key, amountOn0, amount));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert BaseHook.NotPoolManager();
        (PoolKey memory key, bool amountOn0, uint256 amount) = abi.decode(data, (PoolKey, bool, uint256));
        Currency c = amountOn0 ? key.currency0 : key.currency1;
        poolManager.donate(key, amountOn0 ? amount : 0, amountOn0 ? 0 : amount, "");
        c.settle(poolManager, address(this), amount, false);
        PoolId poolId = key.toId();
        totalSurplusDonated[poolId] += amount;
        emit SurplusCredited(poolId, amount, Currency.unwrap(c));
        return "";
    }

    function _isPrivate(bytes calldata hookData, PoolId poolId) internal view returns (bool) {
        if (hookData.length == 0) {
            return address(policy) != address(0) && policy.isFair(block.number);
        }
        return _receiptValid(hookData, poolId);
    }

    function _consumePrivate(bytes calldata hookData, PoolId poolId) internal returns (bool) {
        if (hookData.length == 0) {
            return address(policy) != address(0) && policy.isFair(block.number);
        }
        _burnReceipt(hookData, poolId);
        return true;
    }

    function _receiptValid(bytes calldata hookData, PoolId poolId) internal view returns (bool) {
        if (hookData.length == 0) return false;
        (uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(hookData, (uint256, uint256, uint8, bytes32, bytes32));
        if (block.timestamp > deadline) return false;
        bytes32 digest = _digest(deadline, nonce, poolId);
        if (usedReceipt[digest]) return false;
        address signer = ecrecover(digest, v, r, s);
        return signer != address(0) && isRelayer[signer];
    }

    function _burnReceipt(bytes calldata hookData, PoolId poolId) internal {
        if (!_receiptValid(hookData, poolId)) revert BadReceipt();
        (uint256 deadline, uint256 nonce,,,) =
            abi.decode(hookData, (uint256, uint256, uint8, bytes32, bytes32));
        usedReceipt[_digest(deadline, nonce, poolId)] = true;
    }

    function _digest(uint256 deadline, uint256 nonce, PoolId poolId) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(RECEIPT_TYPEHASH, deadline, nonce, PoolId.unwrap(poolId)));
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _recapture(PoolId, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        internal
        returns (uint256 taxAmount, int128 hookDelta)
    {
        bool specifiedTokenIs0 = (params.amountSpecified < 0) == params.zeroForOne;
        Currency feeCurrency = specifiedTokenIs0 ? key.currency1 : key.currency0;
        int128 swapAmount = specifiedTokenIs0 ? delta.amount1() : delta.amount0();
        if (swapAmount < 0) swapAmount = -swapAmount;
        taxAmount = uint256(uint128(swapAmount)) * PUBLIC_TAX_BIPS / 10_000;
        if (taxAmount == 0) return (0, 0);
        feeCurrency.take(poolManager, address(this), taxAmount, false);
        poolManager.donate(key, specifiedTokenIs0 ? 0 : taxAmount, specifiedTokenIs0 ? taxAmount : 0, "");
        feeCurrency.settle(poolManager, address(this), taxAmount, false);
        hookDelta = taxAmount.toInt128();
    }
}
