// base-sepolia has exactly same deployments as mainnet (in theory lol), so we reuse all the handlers
// If some handlers need to be different - we copy-paste them into base-sepolia folder and make adjustments. Later when aligned with mainnet -- revert import
export * from '../mainnet/getISOWeekNumber';
export * from '../mainnet/handleAccountCreated';
export * from './handleCollateralConfigured';
export * from '../mainnet/handleCollateralDeposited';
export * from '../mainnet/handleCollateralWithdrawn';
export * from '../mainnet/handleDelegationUpdated';
export * from '../mainnet/handleLiquidation';
export * from '../mainnet/handleMarketCreated';
export * from '../mainnet/handlePermissionGranted';
export * from '../mainnet/handlePermissionRevoked';
export * from '../mainnet/handlePoolConfigurationSet';
export * from '../mainnet/handlePoolCreated';
export * from '../mainnet/handlePoolNameUpdated';
export * from '../mainnet/handlePoolNominationRenounced';
export * from '../mainnet/handlePoolNominationRevoked';
export * from '../mainnet/handlePoolOwnerNominated';
export * from '../mainnet/handlePoolOwnershipAccepted';
export * from '../mainnet/handleRewardsClaimed';
export * from '../mainnet/handleRewardsDistributed';
export * from '../mainnet/handleRewardsDistributorRegistered';
export * from '../mainnet/handleUSDBurned';
export * from '../mainnet/handleUSDMinted';
export * from '../mainnet/handleVaultLiquidation';
export * from '../mainnet/marketSnapshotByDay';
export * from '../mainnet/marketSnapshotByWeek';
