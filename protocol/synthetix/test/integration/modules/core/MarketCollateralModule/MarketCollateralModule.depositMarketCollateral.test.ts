import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
import assertEvent from '@synthetixio/core-utils/utils/assertions/assert-event';
import { ContractTransaction, ethers, Signer } from 'ethers';
import { bootstrapWithMockMarketAndPool } from '../../../bootstrap';
import { verifyUsesFeatureFlag } from '../../../verifications';

describe('MarketCollateralModule.depositMarketCollateral()', function () {
  const { signers, systems, MockMarket, marketId, collateralAddress, collateralContract, restore } =
    bootstrapWithMockMarketAndPool();

  let owner: Signer, user1: Signer;

  before('identify signers', async () => {
    [owner, user1] = signers();

    // The owner assigns a maximum of 1,000
    await systems()
      .Core.connect(owner)
      .configureMaximumMarketCollateral(marketId(), collateralAddress(), 1000);
  });

  const configuredMaxAmount = ethers.utils.parseEther('1234');

  before(restore);

  before('configure max', async () => {
    await systems()
      .Core.connect(owner)
      .configureMaximumMarketCollateral(marketId(), collateralAddress(), configuredMaxAmount);
  });

  before('user approves', async () => {
    await collateralContract()
      .connect(user1)
      .approve(MockMarket().address, ethers.constants.MaxUint256);
  });

  let beforeCollateralBalance: ethers.BigNumber;
  before('record user collateral balance', async () => {
    beforeCollateralBalance = await collateralContract().balanceOf(await user1.getAddress());
  });

  it('only works for the market matching marketId', async () => {
    await assertRevert(
      systems().Core.connect(user1).depositMarketCollateral(marketId(), collateralAddress(), 1),
      `Unauthorized("${await user1.getAddress()}")`,
      systems().Core
    );
  });

  it('does not work when depositing over max amount', async () => {
    await assertRevert(
      MockMarket()
        .connect(user1)
        .depositCollateral(collateralAddress(), configuredMaxAmount.add(1)),
      `InsufficientMarketCollateralDepositable("${marketId()}", "${collateralAddress()}", "${configuredMaxAmount.add(
        1
      )}")`,
      systems().Core
    );
  });

  verifyUsesFeatureFlag(
    () => systems().Core,
    'depositMarketCollateral',
    () => MockMarket().connect(user1).depositCollateral(collateralAddress(), configuredMaxAmount)
  );

  describe('invoked successfully', () => {
    let tx: ContractTransaction;
    before('deposit', async () => {
      tx = await MockMarket()
        .connect(user1)
        .depositCollateral(collateralAddress(), configuredMaxAmount);
    });

    it('pulls in collateral', async () => {
      assertBn.equal(await collateralContract().balanceOf(MockMarket().address), 0);
      assertBn.equal(
        await collateralContract().balanceOf(await user1.getAddress()),
        beforeCollateralBalance.sub(configuredMaxAmount)
      );
    });

    it('returns collateral added', async () => {
      assertBn.equal(
        await systems()
          .Core.connect(user1)
          .getMarketCollateralAmount(marketId(), collateralAddress()),
        configuredMaxAmount
      );
    });

    it('reduces total balance', async () => {
      assertBn.equal(
        await systems().Core.connect(user1).getMarketTotalDebt(marketId()),
        configuredMaxAmount.sub(configuredMaxAmount.mul(2))
      );
    });

    it('emits event', async () => {
      const tokenAmount = configuredMaxAmount.toString();
      const sender = MockMarket().address;
      const creditCapacity = ethers.utils.parseEther('1000');
      const netIssuance = 0;
      const depositedCollateralValue = (
        await systems()
          .Core.connect(user1)
          .getMarketCollateralAmount(marketId(), collateralAddress())
      ).toString();
      const reportedDebt = 0;
      await assertEvent(
        tx,
        `MarketCollateralDeposited(${[
          marketId(),
          `"${collateralAddress()}"`,
          tokenAmount,
          `"${sender}"`,
          creditCapacity,
          netIssuance,
          depositedCollateralValue,
          reportedDebt,
        ].join(', ')})`,
        systems().Core
      );
    });

    describe('when withdrawing all usd', async () => {
      let withdrawable: ethers.BigNumber;
      before('do it', async () => {
        withdrawable = await systems().Core.getWithdrawableMarketUsd(marketId());
        // because of the way the mock market works we must first increase reported debt
        await MockMarket().connect(user1).setReportedDebt(withdrawable);
      });

      it('should be able to withdrawn', async () => {
        // now actually withdraw
        await (await MockMarket().connect(user1).sellSynth(withdrawable)).wait();
      });
    });
  });
});
