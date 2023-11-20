//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DecimalMath} from "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import {ITokenModule} from "@synthetixio/core-modules/contracts/interfaces/ITokenModule.sol";
import {PerpMarketConfiguration, SYNTHETIX_USD_MARKET_ID} from "./PerpMarketConfiguration.sol";
import {SafeCastI256, SafeCastU256} from "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import {INodeModule} from "@synthetixio/oracle-manager/contracts/interfaces/INodeModule.sol";
import {PerpMarket} from "./PerpMarket.sol";
import {Position} from "./Position.sol";
import {MathUtil} from "../utils/MathUtil.sol";
import {ErrorUtil} from "../utils/ErrorUtil.sol";

library Margin {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using SafeCastI256 for int256;
    using SafeCastU256 for uint256;
    using PerpMarket for PerpMarket.Data;
    using Position for Position.Data;

    // --- Constants --- //

    bytes32 private constant SLOT_NAME = keccak256(abi.encode("io.synthetix.bfp-market.Margin"));

    // --- Structs --- //

    struct CollateralType {
        // Underlying sell oracle used by this spot collateral bytes32(0) if sUSD.
        bytes32 oracleNodeId;
        // Maximum allowable deposited amount for this collateral type.
        uint128 maxAllowable;
        // Address of the associated reward distributor.
        address rewardDistributor;
        // Adding exists so we can differentiate maxAllowable from 0 and unset in the supported mapping below.
        bool exists;
    }

    // --- Storage --- //

    struct GlobalData {
        // {synthMarketId: CollateralType}.
        mapping(uint128 => CollateralType) supported;
        // Array of supported synth spot market ids useable as collateral for margin.
        uint128[] supportedSynthMarketIds;
    }

    struct Data {
        // {synthMarketId: collateralAmount} (amount of collateral deposited into this account).
        mapping(uint128 => uint256) collaterals;
    }

    function load(uint128 accountId, uint128 marketId) internal pure returns (Margin.Data storage d) {
        bytes32 s = keccak256(abi.encode("io.synthetix.bfp-market.Margin", accountId, marketId));

        assembly {
            d.slot := s
        }
    }

    function load() internal pure returns (Margin.GlobalData storage d) {
        bytes32 s = SLOT_NAME;

        assembly {
            d.slot := s
        }
    }

    /**
     * @dev Withdraw `amount` synths from deposits to sell for sUSD and burn for LPs.
     */
    function sellNonSusdCollateral(
        uint128 marketId,
        uint128 synthMarketId,
        uint256 amount,
        uint256 price,
        PerpMarketConfiguration.GlobalData storage globalConfig
    ) internal {
        globalConfig.synthetix.withdrawMarketCollateral(
            marketId,
            globalConfig.spotMarket.getSynth(synthMarketId),
            amount
        );
        (uint256 amountUsd, ) = globalConfig.spotMarket.sellExactIn(
            synthMarketId,
            amount,
            amount.mulDecimal(price).mulDecimal(DecimalMath.UNIT - globalConfig.sellExactInMaxSlippagePercent),
            address(0)
        );
        globalConfig.synthetix.depositMarketUsd(marketId, address(this), amountUsd);
    }

    // --- Mutative --- //

    /**
     * @dev Reevaluates the collateral in `market` for `accountId` with `amountDeltaUsd`. When amount is negative,
     * portion of their collateral is deducted. If positive, an equivalent amount of sUSD is credited to the
     * account.
     */
    function updateAccountCollateral(
        uint128 accountId,
        PerpMarket.Data storage market,
        int256 amountDeltaUsd
    ) internal {
        // Nothing to update, this is a no-op.
        if (amountDeltaUsd == 0) {
            return;
        }

        // This is invoked when an order is settled and a modification of an existing position needs to be
        // performed. There are a few scenarios we are trying to capture:
        //
        // 1. Increasing size for a profitable position
        // 2. Increasing size for a unprofitable position
        // 3. Decreasing size for an profitable position (partial close)
        // 4. Decreasing size for an unprofitable position (partial close)
        // 5. Closing a profitable position (full close)
        // 6. Closing an unprofitable position (full close)
        //
        // The commonalities:
        // - There is an existing position
        // - All position modifications involve 'touching' a position which realizes the profit/loss
        // - All profitable positions are given more sUSD as collateral
        // - All accounting can be performed within the market (i.e. no need to move tokens around)

        PerpMarketConfiguration.GlobalData storage globalConfig = PerpMarketConfiguration.load();
        Margin.Data storage accountMargin = Margin.load(accountId, market.id);

        // >0 means to add sUSD to this account's margin (realized profit).
        if (amountDeltaUsd > 0) {
            accountMargin.collaterals[SYNTHETIX_USD_MARKET_ID] += amountDeltaUsd.toUint();
            market.depositedCollateral[SYNTHETIX_USD_MARKET_ID] += amountDeltaUsd.toUint();
        } else {
            // <0 means a realized loss and we need to partially deduct from their collateral.
            Margin.GlobalData storage globalMarginConfig = Margin.load();
            uint256 length = globalMarginConfig.supportedSynthMarketIds.length;
            uint256 amountToDeductUsd = MathUtil.abs(amountDeltaUsd);

            // Variable declaration outside of loop to be more gas efficient.
            uint128 synthMarketId;
            uint256 available;
            uint256 price;
            uint256 deductionAmount;
            uint256 deductionAmountUsd;

            for (uint256 i = 0; i < length; ) {
                synthMarketId = globalMarginConfig.supportedSynthMarketIds[i];
                available = accountMargin.collaterals[synthMarketId];

                // Account has _any_ amount to deduct collateral from (or has realized profits if sUSD).
                if (available > 0) {
                    price = getCollateralPrice(globalMarginConfig, synthMarketId, available, globalConfig);
                    deductionAmountUsd = MathUtil.min(amountToDeductUsd, available.mulDecimal(price));
                    deductionAmount = deductionAmountUsd.divDecimal(price);

                    // If collateral isn't sUSD, withdraw, sell, deposit as USD then continue update accounting.
                    if (synthMarketId != SYNTHETIX_USD_MARKET_ID) {
                        sellNonSusdCollateral(market.id, synthMarketId, deductionAmount, price, globalConfig);
                    }

                    // At this point we can just update the accounting.
                    //
                    // Non-sUSD collateral has been sold for sUSD and deposited to core system. The
                    // `amountDeltaUsd` will take order fees, keeper fees and funding into account.
                    //
                    // If sUSD is used we can just update the accounting directly.
                    accountMargin.collaterals[synthMarketId] -= deductionAmount;
                    market.depositedCollateral[synthMarketId] -= deductionAmount;
                    amountToDeductUsd -= deductionAmountUsd;
                }

                // Exit early in the event the first deducted collateral is enough to cover the loss.
                if (amountToDeductUsd == 0) {
                    break;
                }

                unchecked {
                    ++i;
                }
            }

            // Not enough remaining margin to deduct from `-amount`.
            //
            // NOTE: This is _only_ used within settlement and should revert settlement if the margin is
            // not enough to cover fees incurred to modify position. However, IM/MM should be configured
            // well enough to prevent this from ever happening. Additionally, instant liquidation checks
            // should also prevent this from happening too.
            if (amountToDeductUsd > 0) {
                revert ErrorUtil.InsufficientMargin();
            }
        }
    }

    // --- Views --- //

    /**
     * @dev Returns the "raw" margin in USD before fees, `sum(p.collaterals.map(c => c.amount * c.price))`.
     */
    function getCollateralUsd(uint128 accountId, uint128 marketId) internal view returns (uint256) {
        PerpMarketConfiguration.GlobalData storage globalConfig = PerpMarketConfiguration.load();
        Margin.GlobalData storage globalMarginConfig = Margin.load();
        Margin.Data storage accountMargin = Margin.load(accountId, marketId);

        // Variable declaration outside of loop to be more gas efficient.
        uint256 length = globalMarginConfig.supportedSynthMarketIds.length;
        uint128 synthMarketId;
        uint256 available;
        uint256 collateralUsd;

        for (uint256 i = 0; i < length; ) {
            synthMarketId = globalMarginConfig.supportedSynthMarketIds[i];
            available = accountMargin.collaterals[synthMarketId];

            // `getCollateralPrice()` is an expensive op, skip if we can.
            if (available > 0) {
                collateralUsd += available.mulDecimal(
                    getCollateralPrice(globalMarginConfig, synthMarketId, available, globalConfig)
                );
            }

            unchecked {
                ++i;
            }
        }

        return collateralUsd;
    }

    /**
     * @dev Returns the margin value in usd given the account, market, and market price.
     *
     * Margin is effectively the discounted value of the deposited collateral, accounting for the funding accrued,
     * fees paid and any unrealized profit/loss on the position.
     *
     * In short, `collateralUsd  + position.funding + position.pnl - position.feesPaid`.
     */
    function getMarginUsd(
        uint128 accountId,
        PerpMarket.Data storage market,
        uint256 price
    ) internal view returns (uint256) {
        uint256 collateralUsd = getCollateralUsd(accountId, market.id);
        Position.Data storage position = market.positions[accountId];

        // Zero position means that marginUsd eq collateralUsd.
        if (position.size == 0) {
            return collateralUsd;
        }
        return
            MathUtil
                .max(
                    collateralUsd.toInt() +
                        position.getPnl(price) +
                        position.getAccruedFunding(market, price) -
                        position.accruedFeesUsd.toInt(),
                    0
                )
                .toUint();
    }

    // --- Member (views) --- //

    /**
     * @dev Returns haircut adjusted collateral price. Discount proportional to `available`, scaled by a spot skew scale.
     */
    function getCollateralPrice(
        Margin.GlobalData storage self,
        uint128 synthMarketId,
        uint256 available,
        PerpMarketConfiguration.GlobalData storage globalConfig
    ) internal view returns (uint256) {
        if (synthMarketId == SYNTHETIX_USD_MARKET_ID) {
            return DecimalMath.UNIT;
        }

        // Fetch the raw oracle price.
        uint256 oraclePrice = globalConfig
            .oracleManager
            .process(self.supported[synthMarketId].oracleNodeId)
            .price
            .toUint();

        // Calculate haircut on collateral price if this collateral were to be instantly sold on spot.
        uint256 skewScale = globalConfig.spotMarket.getMarketSkewScale(synthMarketId);
        uint256 haircut = MathUtil.min(
            MathUtil.max(available.divDecimal(skewScale), globalConfig.minCollateralHaircut),
            globalConfig.maxCollateralHaircut
        );

        // Apply discount on price by the haircut.
        return oraclePrice.mulDecimal(DecimalMath.UNIT - haircut);
    }
}
