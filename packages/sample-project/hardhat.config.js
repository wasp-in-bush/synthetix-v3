require('@nomiclabs/hardhat-ethers');
require('@synthetixio/hardhat-router');
require('hardhat-cannon');

module.exports = {
  solidity: {
    version: '0.8.11',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    local: {
      url: 'http://localhost:8545',
    },
  },
  router: {},
};
