// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {console} from "forge-std/console.sol";
import {LimitHelper} from "../src/libraries/LimitHelper.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TestERC20} from "v4-core/src/test/TestERC20.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {NewEraHook} from "../src/Hook.sol";

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

contract test_CounterTest is Test, Deployers {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    TestERC20 token0; // First token in the pair
    TestERC20 token1; // Second token in the pair

    PriceOracle priceOracle;
    PoolSwapTest router;

    NewEraHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    address user = address(0x123);

    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, recipient);
        params[3] = abi.encode(poolKey.currency1, recipient);

        return (actions, params);
    }

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();

        router = new PoolSwapTest(poolManager);
        priceOracle = new PriceOracle();
        string[] memory assets = new string[](1);
        assets[0] = "TEST";
        uint256[] memory prices = new uint256[](1);
        prices[0] = 100;
        priceOracle.updatePrices(assets, prices);

        token0 = TestERC20(Currency.unwrap(currency0));
        token1 = TestERC20(Currency.unwrap(currency1));


        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG
        );

        // Deploy hook contract
        bytes memory constructorArgs = abi.encode(
            address(poolManager),
            address(priceOracle)
        );
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(NewEraHook).creationCode,
            constructorArgs
        );
        hook = new NewEraHook{salt: salt}(
            IPoolManager(address(poolManager)),
            address(priceOracle)
        );
        require(address(hook) == hookAddress, "Hook address mismatch");

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        uint128 liquidityAmount = 100e18;

        uint160 startingPrice = 4552702936290292383660862550846;
        int24 currentTick = TickMath.getTickAtSqrtPrice(startingPrice);

        tickLower = ((currentTick - 750 * 60) / 60) * 60;
        tickUpper = ((currentTick + 750 * 60) / 60) * 60;

        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount,
            liquidityAmount
        );

        // slippage limits
        uint256 amount0Max = liquidityAmount + 1;
        uint256 amount1Max = liquidityAmount + 1;

        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, address(this), Constants.ZERO_BYTES
        );

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // Initialize Pool
        params[0] = abi.encodeWithSelector(positionManager.initializePool.selector, poolKey, startingPrice, Constants.ZERO_BYTES);

        // Mint Liquidity
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 3600
        );

        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

        positionManager.multicall{value: valueToPass}(params);

    }

    function test_limitOrderExecution() public {
        vm.startPrank(user);
        // Set up order parameters
        uint256 amount = 1e18;
        uint256 tolerance = 1000; // 1% tolerance in basis points
        bool zeroForOne = false; // Buy order (token1 for token0)
        uint256 expireMinutesDef = 0;
        
        // Prepare tokens for the order
        token0.mint(user, amount * 2);
        token1.mint(user, amount * 2);

        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        // Calculate order amounts including fees
        (uint256 baseAmount, uint256 totalAmount) = hook.calculateOrderAmounts(
            amount,
            poolKey
        );

        // Prepare tokens for the buy order
        token1.approve(address(hook), totalAmount * 2);
        token1.approve(address(poolManager), totalAmount * 2);

        // Place the limit order
        hook.placeLimitOrder(
            poolKey,
            baseAmount,
            totalAmount,
            tolerance,
            zeroForOne,
            expireMinutesDef
        );

        hook.cancelLimitOrder(poolKey, user, 0);
        console.log("placing");
        hook.placeLimitOrder(
            poolKey,
            baseAmount,
            totalAmount,
            tolerance,
            zeroForOne,
            expireMinutesDef
        );
        console.log("placed");
        (
            address orderUser,
            uint256 orderAmount,
            uint256 orderTotalAmount,
            uint256 oraclePrice,
            uint256 oraclePrice2,
            uint256 orderTolerance,
            bool orderZeroForOne,
            bool isActive,
            bool tokensTransferred,
            uint256 creationTimestamp,
            bool shouldExecute,
            uint256 amountFilled,
            uint256 expireMinutes,
            uint256 lastTradeTimestamp,
            PoolKey memory key
        ) = hook.limitOrders(poolKey.toId(), user, 1);
        console2.log(key.tickSpacing);
        assertTrue(isActive, "Limit order should be created and active");
        assertFalse(orderZeroForOne, "Should be a buy order");
        assertEq(orderTotalAmount, totalAmount, "Total amount should match");
        assertEq(orderTolerance, tolerance, "Tolerance should match");
        assertEq(oraclePrice2, LimitHelper.getOraclePrice2(poolKey, priceOracle), "Incorrect oraclePrice2");
        assertTrue(creationTimestamp > 0, "creationTimestamp should be set");

        // Calculate price levels for the test
        uint160 initialSqrtPrice = TickMath.getSqrtPriceAtTick(0);
        uint256 initialPrice = (uint256(initialSqrtPrice) *
            uint256(initialSqrtPrice) *
            1e18) >> 192;
        uint160 targetSqrtPrice = TickMath.getSqrtPriceAtTick(1000);
        uint256 targetPrice = (uint256(targetSqrtPrice) *
            uint256(targetSqrtPrice) *
            1e18) >> 192;

        // Create swap parameters to move price up
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false, // Swap direction to increase price
            amountSpecified: 1e18, // Large amount to ensure price movement
            sqrtPriceLimitX96: targetSqrtPrice // Target price 1000 ticks higher
        });

        // Execute swap to trigger order execution
        vm.stopPrank();
        swapRouter.swapExactTokensForTokens({
            amountIn: 1e18,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: false,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        vm.startPrank(user);

        // Verify order was executed
        (, , , , , , , bool finalIsActive, , , bool finalShouldExecute , , , , ) = hook.limitOrders(
            poolKey.toId(),
            user,
            1
        );

        hook.executeLimitOrders(poolKey);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 finalAmountFilled,
            ,
            ,
        ) = hook.limitOrders(poolKey.toId(), user, 1);

        assertTrue(finalAmountFilled > 0, "Part of the limit order should be filled.");

        vm.stopPrank();
    }

    function test_dcaOrderExecution() public {
        vm.startPrank(user);
        // Set up order parameters
        uint256 amount = 1e18;
        uint256 tolerance = 1000; // 1% tolerance in basis points
        bool zeroForOne = false; // Buy order (token1 for token0)
        uint256 expireMinutesDef = 5;
        
        // Prepare tokens for the order
        token0.mint(user, amount * 2);
        token1.mint(user, amount * 2);

        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        // Calculate order amounts including fees
        (uint256 baseAmount, uint256 totalAmount) = hook.calculateOrderAmounts(
            amount,
            poolKey
        );

        // Prepare tokens for the buy order
        token1.approve(address(hook), totalAmount);
        token1.approve(address(poolManager), totalAmount);

        // Place the limit order
        hook.placeLimitOrder(
            poolKey,
            baseAmount,
            totalAmount,
            tolerance,
            zeroForOne,
            expireMinutesDef
        );

        (
            address orderUser,
            uint256 orderAmount,
            uint256 orderTotalAmount,
            uint256 oraclePrice,
            uint256 oraclePrice2,
            uint256 orderTolerance,
            bool orderZeroForOne,
            bool isActive,
            bool tokensTransferred,
            uint256 creationTimestamp,
            bool shouldExecute,
            uint256 amountFilled,
            uint256 expireMinutes,
            uint256 lastTradeTimestamp,
            PoolKey memory key
        ) = hook.limitOrders(poolKey.toId(), user, 0);
        assertTrue(isActive, "Limit order should be created and active");
        assertFalse(orderZeroForOne, "Should be a buy order");
        assertEq(orderTotalAmount, totalAmount, "Total amount should match");
        assertEq(orderTolerance, tolerance, "Tolerance should match");
        assertEq(oraclePrice2, LimitHelper.getOraclePrice2(poolKey, priceOracle), "Incorrect oraclePrice2");
        assertTrue(creationTimestamp > 0, "creationTimestamp should be set");

        uint256 start = block.timestamp;

        vm.warp(block.timestamp + 60);

        hook.executeLimitOrders(poolKey);

        vm.warp(block.timestamp + 60);

        hook.executeLimitOrders(poolKey);
        
        vm.warp(block.timestamp + 60);

        hook.executeLimitOrders(poolKey);

        vm.warp(block.timestamp + 60);

        hook.executeLimitOrders(poolKey);

        vm.warp(block.timestamp + 60);

        hook.executeLimitOrders(poolKey);

        vm.warp(block.timestamp + 60);

        hook.executeLimitOrders(poolKey);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool finalIsActive,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = hook.limitOrders(poolKey.toId(), user, 0);

        assertTrue(!finalIsActive, "Order should be executed");

        // hook.cancelLimitOrder(poolKey, user, 0);

        vm.stopPrank();

    }

    function test_cancelOrder() public {
        vm.startPrank(user);
        // Set up order parameters
        uint256 amount = 1e18;
        uint256 tolerance = 1000; // 1% tolerance in basis points
        bool zeroForOne = false; // Buy order (token1 for token0)
        uint256 expireMinutesDef = 5;
        
        // Prepare tokens for the order
        token0.mint(user, amount * 2);
        token1.mint(user, amount * 2);

        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);

        // Calculate order amounts including fees
        (uint256 baseAmount, uint256 totalAmount) = hook.calculateOrderAmounts(
            amount,
            poolKey
        );

        // Prepare tokens for the buy order
        token1.approve(address(hook), totalAmount);
        token1.approve(address(poolManager), totalAmount);

        // Place the limit order
        hook.placeLimitOrder(
            poolKey,
            baseAmount,
            totalAmount,
            tolerance,
            zeroForOne,
            expireMinutesDef
        );

        hook.cancelLimitOrder(poolKey, user, 0);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool finalIsActive,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = hook.limitOrders(poolKey.toId(), user, 0);

        assertTrue(!finalIsActive, "Order should be canceled");

        vm.stopPrank();
    }
}
