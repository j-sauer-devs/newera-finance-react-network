// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "lib/reactive-lib/src/interfaces/ISystemContract.sol";
import "lib/reactive-lib/src/abstract-base/AbstractPausableReactive.sol";

contract BasicCronContract is AbstractPausableReactive {
    uint256 public CRON_TOPIC;
    uint256 public originChainId;
    uint256 public destinationChainId;
    uint64 private constant GAS_LIMIT = 10000000;
    
    address private constant CALLBACK_ADDRESS_1 = 0x020dD0882F9132824bc3e5d539136D9BaacdFEd3;
    address private constant CALLBACK_ADDRESS_2 = 0x7ceCA9113e235c5795a1EbbE14137ba307d97861;
    address private callback;

    constructor(
        address _service,
        uint256 _cronTopic,
        address _callback,
        uint256 _originChainId,
        uint256 _destinationChainId
    ) payable {
        service = ISystemContract(payable(_service));
        CRON_TOPIC = _cronTopic;
        originChainId = _originChainId;
        destinationChainId = _destinationChainId;
        callback = _callback;

        if (!vm) {
            service.subscribe(
                originChainId,
                address(service),
                _cronTopic,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function getPausableSubscriptions() internal view override returns (Subscription[] memory) {
        Subscription[] memory result = new Subscription[](1);
        result[0] = Subscription(
            originChainId,
            address(service),
            CRON_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        return result;
    }

    function react(LogRecord calldata log) external vmOnly {
        if (log.topic_0 == CRON_TOPIC) {
            bytes memory payload = abi.encodeWithSignature(
                "callback(address,address,address)",
                address(0),
                address(CALLBACK_ADDRESS_1),
                address(CALLBACK_ADDRESS_2)
            );
            emit Callback(destinationChainId, callback, GAS_LIMIT, payload);
        }
    }
}