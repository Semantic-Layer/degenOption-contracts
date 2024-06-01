// SPDX-License-Identifier: GPL-2.0-or-later

// based on https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol
pragma solidity ^0.8.20;

import "@uniswap/v4-core/src/libraries/FullMath.sol";
import "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @title Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
library TickPriceLib {
    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function getQuoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        internal
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param tokenZeroAmount Amount of token to be converted
    /// @return tokenOneAmount Amount of quoteToken received for baseAmount of baseToken
    function getTokenOneQuoteAtTick(int24 tick, uint128 tokenZeroAmount)
        internal
        pure
        returns (uint256 tokenOneAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            tokenOneAmount = FullMath.mulDiv(ratioX192, tokenZeroAmount, 1 << 192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            tokenOneAmount = FullMath.mulDiv(ratioX128, tokenZeroAmount, 1 << 128);
        }
    }
}
