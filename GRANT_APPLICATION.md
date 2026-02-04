# Reactive Network Grant Application: Automated Limit & DCA Orders for Uniswap v4

## Project Overview

**Project Name:** New Era Finance - Automated Trading Orders for Uniswap v4

**Team:** NewEra Finance LTDA

**Contact:** julian@newera.finance

**Project Type:** DeFi Infrastructure, Automated Trading Protocol

---

## Problem Statement

### Why Reactive Smart Contracts are Needed

Traditional decentralized exchanges like Uniswap require manual intervention for complex trading strategies such as limit orders and dollar-cost averaging (DCA). This creates several critical limitations:

1. **Manual Execution Overhead**: Users must constantly monitor markets and manually execute trades when conditions are met, leading to missed opportunities and inefficient capital utilization.

2. **Cross-Chain Synchronization Issues**: When trading across multiple chains, users face challenges in coordinating executions and maintaining consistent positions.

3. **Time-Based Automation Gaps**: DCA strategies require periodic execution (e.g., daily purchases), but current DEX infrastructure lacks native time-based automation without external services.

4. **Real-Time Price Monitoring**: Limit orders need continuous price monitoring to execute at target prices, which is resource-intensive and unreliable with manual processes.

### Solution: Reactive Smart Contracts for Automated Trading

Our project implements automated limit orders and DCA orders on Uniswap v4 using Reactive Network technology to address these pain points:

- **Onchain Automation**: Reactive Smart Contracts enable fully automated order execution without manual intervention
- **Cross-Chain Functionality**: Seamless execution across multiple blockchain networks
- **Modular Architecture**: Clean separation between order logic and execution triggers
- **Streamlined Workflows**: Multiple manual steps are consolidated into automated processes

---

## Technical Implementation

### Reactive Smart Contract Architecture

#### Origin Chain: Reactive Network
- **Reactive Contract**: `Cron.sol` - Monitors time-based triggers every minute
- **Trigger Event**: Cron service emits timestamp-based events
- **Subscription**: Subscribes to system contract events on Reactive Network

#### Destination Chain: Ethereum (and compatible EVM chains)
- **Callback Contract**: `Callback.sol` - Receives cross-chain triggers from Reactive Network
- **Execution Logic**: Calls `executeLimitOrders()` function on the Uniswap v4 Hook contract

### Onchain Events & Function Calls

#### Events That Trigger RSC Execution
1. **Cron Events**: Reactive Network system contract emits periodic timestamp events
2. **Price Threshold Events**: Oracle price updates that meet order conditions
3. **Time-Based Events**: Scheduled execution for DCA orders

#### Functions Called as Result of RSC Execution
1. **`executeLimitOrders(PoolKey calldata key)`** - Main execution function on Hook contract
2. **`callback(address sender, address token0, address token1)`** - Callback handler function
3. **Internal Uniswap Functions**:
   - `poolManager.swap()` - Executes actual token swaps
   - `poolManager.unlock()` - Manages pool state during execution

#### Conditions Checked Within RSC & Callback Contracts

**Reactive Contract (Cron.sol)**:
```solidity
function react(LogRecord calldata log) external vmOnly {
    if (log.topic_0 == CRON_TOPIC) {
        // Emit callback to destination chain
        emit Callback(destinationChainId, callback, GAS_LIMIT, payload);
    }
}
```

## Mainnet example

**Scenario**: User places a dca order for 0.01 cusdo to usdc on arbitrum

#### Step 1: Order Placement
**Transaction**: User calls `placeLimitOrder()` on Hook contract
https://arbiscan.io/tx/0x0e0c8292160d2631fdd2fb465872e57a88f127af497e5675bf03c7541745a09f

#### Step 2: Reactive Network Trigger
**Time**: Every minute, Reactive Network emits cron event

**Reactscan**: [Reactscan Link](https://reactscan.net/address/0x9f7d6c65188bbaad3d76ff0de53ff600a6bdf569/4)