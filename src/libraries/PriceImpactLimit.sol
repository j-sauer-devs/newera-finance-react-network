// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library PriceImpactLimit {
    uint160 internal constant MIN_SQRT_RATIO = 4295128739 + 1;          // Uniswap V3 + 1
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342 - 1;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;

    /// @notice Babylonian sqrt on wad-scaled values (returns wad)
    function sqrtWad(uint256 xWad) internal pure returns (uint256) {
        if (xWad == 0) return 0;
        // Babylonian method on integer
        uint256 z = (xWad + 1) / 2;
        uint256 y = xWad;
        while (z < y) { y = z; z = (xWad / z + z) / 2; }
        return y;
    }

    /// @notice Compute sqrtPriceLimitX96 that caps price impact to p_bps
    /// @param sqrtPriceX96 current sqrt price from slot0()
    /// @param p_bps maximum price impact in basis points (e.g. 100 = 1%)
    /// @param zeroForOne true for token0->token1 (price down), false for token1->token0 (price up)
    function limitFromImpactBps(
        uint160 sqrtPriceX96,
        uint256 p_bps,
        bool zeroForOne
    ) internal pure returns (uint160 limit) {
        require(p_bps < BPS, "impact too large");

        // ratio = (1 - p) or (1 + p) in wad
        uint256 num = zeroForOne ? (BPS - p_bps) : (BPS + p_bps);
        // sqrtMultiplier in wad
        uint256 sqrtMultWad = sqrtWad((num * WAD) / BPS);

        // limit = sqrtPriceX96 * sqrtMultWad / 1e18
        uint256 tmp = (uint256(sqrtPriceX96) * sqrtMultWad) / WAD;
        limit = uint160(tmp);

        // Direction-specific guards + clamp to Uniswap bounds
        if (zeroForOne) {
            // price must go DOWN but not below limit; limit < current
            if (limit >= sqrtPriceX96) {
                // tiny rounding can push equality; nudge by 1 if needed
                limit = sqrtPriceX96 - 1;
            }
            if (limit <= MIN_SQRT_RATIO) limit = MIN_SQRT_RATIO;
        } else {
            // price must go UP but not above limit; limit > current
            if (limit <= sqrtPriceX96) {
                limit = sqrtPriceX96 + 1;
            }
            if (limit >= MAX_SQRT_RATIO) limit = MAX_SQRT_RATIO;
        }
    }
}