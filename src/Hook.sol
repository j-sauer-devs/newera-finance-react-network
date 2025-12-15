// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// Imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IExtsload} from "v4-core/src/interfaces/IExtsload.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {TWAMMHelper} from "./libraries/TWAMMHelper.sol";
import {ITWAMM} from "../src/interfaces/ITWAMM.sol";
import {TwammMath} from "../src/libraries/TWAMM/TwammMath.sol";
import {OrderPool} from "../src/libraries/TWAMM/OrderPool.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {SwapMath} from "v4-core/src/libraries/SwapMath.sol";
import {LiquidityMath} from "v4-core/src/libraries/LiquidityMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LimitHelper} from "./libraries/LimitHelper.sol";
import {console} from "forge-std/console.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PriceImpactLimit} from "./libraries/PriceImpactLimit.sol";
import { FullMath } from "v4-core/src/libraries/FullMath.sol";
// Contract Definition
contract NewEraHook is BaseHook, ITWAMM, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using OrderPool for OrderPool.State;
    using LimitHelper for *;

    enum UnlockType {
        Execute   
    }

    bytes internal constant ZERO_BYTES = bytes("");

    // Events
    event LimitOrderExecuted(
        PoolId poolId,
        address user,
        uint256 orderId,
        uint256 amount,
        uint256 executionPrice
    );
    event LimitOrderCancelled(PoolId poolId, address user, uint256 orderId, uint256 amount);
    // Structs
    struct LimitOrder {
        address user;
        uint256 amount;
        uint256 totalAmount;
        uint256 oraclePrice;
        uint256 oraclePrice2;
        uint256 tolerance;
        bool zeroForOne;
        bool isActive;
        bool tokensTransferred;
        uint256 creationTimestamp;
        bool shouldExecute;
        uint256 amountFilled;
        uint256 expireMinutes;
        uint256 lastTradeTimestamp;
        PoolKey key;
    }
    
    // Storage & State Variables
    mapping(PoolId => mapping(address => mapping(uint256 => LimitOrder))) public limitOrders;
    mapping(PoolId => mapping(address => uint256)) public userOrderCount;
    mapping(PoolId => address) public poolAddresses;
    mapping(Currency => mapping(address => uint256)) public tokensOwed;
    PoolId[] public allPoolIds; // Track all pools
    address public immutable admin;
    IPriceOracle public immutable priceOracle;
    mapping(address => bytes32[]) private userTWAMMOrderIds;
    // Add user tracking for limit orders
    mapping(PoolId => address[]) public poolUsers;
    mapping(PoolId => mapping(address => bool)) public isPoolUser;
    // Constants
    int256 internal constant MIN_DELTA = -1;
    bool internal constant ZERO_FOR_ONE = true;
    bool internal constant ONE_FOR_ZERO = false;
    uint256 internal constant MAX_DURATION = 360;
    // Errors
    error NoActiveLimitOrder();
    error UnauthorizedCaller();
    error PriceAboveLimit();
    error LimitOrderConditionsNotMet();
    error OnlyAdmin();
    error InsufficientFunds();
    error WrongMaxDuration();
    // Constructor
    constructor(
        IPoolManager _poolManager,
        address _priceOracle
    ) BaseHook(_poolManager) {
        priceOracle = IPriceOracle(_priceOracle);
        admin = msg.sender;
    }
    // Core Hook Functions
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal virtual override returns (bytes4) {
        PoolId poolId = key.toId();
        poolAddresses[poolId] = address(
            uint160(uint256(keccak256(abi.encode(poolId))))
        );
        // Add to allPoolIds if not already present
        bool exists = false;
        for (uint256 i = 0; i < allPoolIds.length; i++) {
            if (PoolId.unwrap(allPoolIds[i]) == PoolId.unwrap(poolId)) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            allPoolIds.push(poolId);
        }
        return BaseHook.beforeInitialize.selector;
    }

    function checkLimitOrders(PoolKey calldata key) internal {
        PoolId poolId = key.toId();
        address[] storage users = poolUsers[poolId];
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
        uint256 currentPrice = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
        currentPrice = currentPrice * 1e18;
        uint256 latestOraclePrice = LimitHelper.getOraclePrice(key, priceOracle);
        uint256 scaledOraclePrice = (latestOraclePrice * 1e18) / 100;
        for (uint256 u = 0; u < users.length; u++) {
            address orderOwner = users[u];
            uint256 orderCount = userOrderCount[poolId][orderOwner];
            uint256 i = 0;
            while (i < orderCount) {
                LimitOrder storage order = limitOrders[poolId][orderOwner][i];
                if (!order.isActive) {
                    i++;
                    continue;
                }
                if(order.expireMinutes > 0){
                    if(block.timestamp >= (order.lastTradeTimestamp + 60)){
                        order.shouldExecute = true;
                    }
                    i++;
                    continue;
                }
                bool shouldExecute = true;
                if (order.tolerance > 0) {
                    uint256 scaledTolerance = (order.tolerance * 1e18) / 10000;
                    uint256 priceLimit = order.zeroForOne
                        ? scaledOraclePrice - scaledTolerance
                        : scaledOraclePrice + scaledTolerance;

                    shouldExecute = (order.zeroForOne && currentPrice <= priceLimit) ||
                        (!order.zeroForOne && currentPrice >= priceLimit);
                }
                if (shouldExecute) {
                    order.shouldExecute = true;
                }
                i++;
            }
        }
    }

    function unlockCallback(bytes calldata rawData) external virtual returns (bytes memory) {
        (UnlockType initialOpType) = abi.decode(rawData[:32], (UnlockType));
        if (initialOpType == UnlockType.Execute) {
            (UnlockType opType, PoolKey memory key, IPoolManager.SwapParams memory swapParams, address orderOwner) = abi.decode(rawData, (UnlockType, PoolKey, IPoolManager.SwapParams, address));
            PoolId poolId = key.toId();
            uint128 liquidity = StateLibrary.getLiquidity(poolManager, poolId);
            BalanceDelta delta = poolManager.swap(key, swapParams, ZERO_BYTES);
            if (swapParams.zeroForOne) {
                if (delta.amount0() < 0) {
                    _settle(key.currency0, uint128(-delta.amount0()));
                }
                if (delta.amount1() > 0) {
                    _take(key.currency1, uint128(delta.amount1()));
                    key.currency1.transfer(address(orderOwner), uint128(delta.amount1()));
                }
            } else {
                if (delta.amount1() < 0) {
                    _settle(key.currency1, uint128(-delta.amount1()));
                }
                if (delta.amount0() > 0) {
                    _take(key.currency0, uint128(delta.amount0()));
                    key.currency0.transfer(address(orderOwner), uint128(delta.amount0()));
                }
            }
            return bytes("");
        }
    }

    function getPriceLimit(
        uint160 sqrtPriceX96,
        uint256 impactBps,   // e.g. 1000 = 10%
        bool zeroForOne      // true = token0->token1, false = token1->token0
    ) internal pure returns (uint160) {
        // factor in 1e18 precision
        uint256 factor = zeroForOne
            ? (1e18 * (10_000 - impactBps)) / 10_000 // 0.9 for 1000 bps
            : (1e18 * (10_000 + impactBps)) / 10_000; // 1.1 for 1000 bps

        // sqrt(factor) in 1e18 precision
        uint256 sqrtFactor = sqrt(factor);

        // scale sqrtFactor back to Q96 domain
        uint160 limit = uint160(
            FullMath.mulDiv(uint256(sqrtPriceX96), sqrtFactor, 1e9) // because sqrt gave us 1e9 scaling
        );

        return limit;
    }

    // sqrt for fixed-point 1e18 numbers, returns result scaled by 1e9
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y; // still in 1e18
    }

    function executeLimitOrders(PoolKey calldata key) external {
        checkLimitOrders(key);
        PoolId poolId = key.toId();
        address[] storage users = poolUsers[poolId];
        for (uint256 u = 0; u < users.length; u++) {
            address orderOwner = users[u];
            uint256 orderCount = userOrderCount[poolId][orderOwner];
            uint256 i = 0;
            while (i < orderCount) {
                LimitOrder storage order = limitOrders[poolId][orderOwner][i];
                if (!order.isActive) {
                    i++;
                    continue;
                }
                if (order.shouldExecute) {
                    if(order.expireMinutes > 0){
                        uint256 eachAmount = order.amount / order.expireMinutes;
                        poolManager.unlock(abi.encode(UnlockType.Execute, key, IPoolManager.SwapParams(order.zeroForOne, -1*int256(eachAmount) , TickMath.MAX_SQRT_PRICE_MINUS_MIN_SQRT_PRICE_MINUS_ONE), orderOwner));
                        checkLimitOrders(key);
                        order.lastTradeTimestamp = block.timestamp;
                        order.amountFilled = order.amountFilled + eachAmount;
                        order.shouldExecute = false;
                        if(order.amountFilled >= order.amount){
                            order.isActive = false;
                            (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
                            uint256 currentPrice = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
                            emit LimitOrderExecuted(poolId, orderOwner, i, order.amount, currentPrice);
                        }
                        continue;
                    }
                    uint256 swapAmount = order.amount - order.amountFilled;
                    (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
                    uint160 priceLimit = getPriceLimit(sqrtPriceX96, 1, order.zeroForOne);
                    uint128 liquidity = StateLibrary.getLiquidity(poolManager, poolId);
                    (, uint256 amountIn,,) = SwapMath.computeSwapStep(
                        sqrtPriceX96,
                        priceLimit,
                        liquidity,
                        type(int256).max, 
                        key.fee                 
                    );
                    uint256 maxAmount = amountIn < swapAmount ? amountIn : swapAmount;
                    poolManager.unlock(abi.encode(UnlockType.Execute, key, IPoolManager.SwapParams(order.zeroForOne, -1*int256(maxAmount) , priceLimit), orderOwner));
                    checkLimitOrders(key);
                    order.amountFilled = order.amountFilled + maxAmount;
                    order.shouldExecute = false;
                    if(amountIn >= swapAmount){
                        order.isActive = false;
                        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
                        uint256 currentPrice = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
                        emit LimitOrderExecuted(poolId, orderOwner, i, order.amount, currentPrice);
                    }
                }
                i++;
            }
        }
    }

    // Limit Order Functions
    function placeLimitOrder(
        PoolKey calldata key,
        uint256 baseAmount,
        uint256 totalAmount,
        uint256 tolerance,
        bool zeroForOne,
        uint256 expireMinutes
    ) external {
        if(expireMinutes > MAX_DURATION){
            revert WrongMaxDuration();
        }
        PoolId poolId = key.toId();
        LimitHelper.validateLimitOrder(
            baseAmount,
            tolerance,
            userOrderCount[poolId][msg.sender]
        );
        uint256 oraclePrice = LimitHelper.getOraclePrice(key, priceOracle);
        uint256 oraclePrice2 = LimitHelper.getOraclePrice2(key, priceOracle);
        LimitHelper.transferTokens(key, totalAmount, zeroForOne, msg.sender);
        uint256 orderId = userOrderCount[poolId][msg.sender];
        limitOrders[poolId][msg.sender][orderId] = LimitOrder({
            user: msg.sender,
            amount: baseAmount, 
            totalAmount: totalAmount,
            oraclePrice: oraclePrice,
            oraclePrice2: oraclePrice2,
            tolerance: tolerance,
            zeroForOne: zeroForOne,
            isActive: true,
            tokensTransferred: true,
            creationTimestamp: block.timestamp,
            shouldExecute: false,
            amountFilled: 0,
            expireMinutes: expireMinutes,
            lastTradeTimestamp: block.timestamp,
            key: key
        });
        userOrderCount[poolId][msg.sender]++;
        // Track user for this pool if not already tracked
        if (!isPoolUser[poolId][msg.sender]) {
            poolUsers[poolId].push(msg.sender);
            isPoolUser[poolId][msg.sender] = true;
        }
        LimitHelper.emitLimitOrderPlaced(
            poolId,
            msg.sender,
            orderId,
            baseAmount,
            oraclePrice,
            tolerance
        );
    }
    function cancelLimitOrder(
        PoolKey calldata key,
        address orderOwner,
        uint256 orderId
    ) external {
        PoolId poolId = key.toId();
        LimitOrder storage order = limitOrders[poolId][orderOwner][orderId];
        if (order.user == address(0)) revert NoActiveLimitOrder();
        if (order.user != msg.sender) revert UnauthorizedCaller();
        if (!order.isActive) revert NoActiveLimitOrder();
        if (order.tokensTransferred) {
            Currency token = order.zeroForOne ? key.currency0 : key.currency1;
            uint256 transferrable = order.amount - order.amountFilled;
            if(transferrable <= 0) revert NoActiveLimitOrder();
            token.transfer(msg.sender, transferrable);
        }
        delete limitOrders[poolId][orderOwner][orderId];
        emit LimitOrderCancelled(poolId, msg.sender, orderId, order.amount);
    }
    function _settle(Currency currency, uint128 amount) internal {
        poolManager.sync(currency);
        currency.transfer(address(poolManager), amount);
        poolManager.settle();
    }
    function _take(Currency currency, uint128 amount) internal {
        poolManager.take(currency, address(this), amount);
    }
    function calculateOrderAmounts(uint256 amount, PoolKey calldata key) external pure returns (uint256 baseAmount, uint256 totalAmount) {
        return TWAMMHelper.calculateOrderAmounts(amount, key);
    }
    function getUserLimitOrders() external view returns (LimitOrder[] memory orders) {
        uint256 totalOrders = 0;
        // First, count total orders for allocation
        for (uint256 p = 0; p < allPoolIds.length; p++) {
            PoolId poolId = allPoolIds[p];
            totalOrders += userOrderCount[poolId][msg.sender];
        }
        orders = new LimitOrder[](totalOrders);
        uint256 idx = 0;
        for (uint256 p = 0; p < allPoolIds.length; p++) {
            PoolId poolId = allPoolIds[p];
            uint256 orderCount = userOrderCount[poolId][msg.sender];
            for (uint256 i = 0; i < orderCount; i++) {
                orders[idx] = limitOrders[poolId][msg.sender][i];
                idx++;
            }
        }
    }
}

