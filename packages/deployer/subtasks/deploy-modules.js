const rimraf = require('rimraf');
const { subtask } = require('hardhat/config');

const logger = require('../utils/logger');
const { SUBTASK_DEPLOY_CONTRACTS, SUBTASK_DEPLOY_MODULES } = require('../task-names');

subtask(SUBTASK_DEPLOY_MODULES).setAction(async (_, hre) => {
  logger.subtitle('Deploying modules');

  const deployedSomething = await hre.run(SUBTASK_DEPLOY_CONTRACTS, {
    contracts: hre.deployer.data.contracts.modules,
  });

  if (!deployedSomething) {
    logger.info('No modules need to be deployed, clearing generated files and exiting...');
    logger.info(`Deleting ${hre.deployer.file}`);
    rimraf.sync(hre.deployer.file);
    process.exit(0);
  }
});
