// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import 'lib/reactive-lib/src/abstract-base/AbstractCallback.sol';
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {NewEraHook} from './Hook.sol';


contract UniswapDemoStopOrderCallback is AbstractCallback {
    NewEraHook private hook;
    PoolKey poolKey;

    constructor(address _callback_sender) AbstractCallback(_callback_sender) payable {
        address hookAddress = address(0xAd33Fff75D8B3C75EdD6D63e9D537400784e2000);
        hook = NewEraHook(hookAddress);
    }

    function callback(address sender, address token0, address token1) external {
        poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 0, 100, IHooks(address(0xAd33Fff75D8B3C75EdD6D63e9D537400784e2000)));
        hook.executeLimitOrders(poolKey);
    }
}
