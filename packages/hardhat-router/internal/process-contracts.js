const { parseFullyQualifiedName } = require('hardhat/utils/contract-names');
const { getBytecodeHash } = require('@synthetixio/core-utils/utils/ethers/contracts');

const path = require('path');
const fs = require('fs');
const mkdirp = require('mkdirp');
const { dirname } = require('path');

/**
 * Initialize contract metadata on hre.router.deployment.*
 * This will in turn save all the necessary data to deployments file.
 * @param {string} contractFullyQualifiedName
 */
async function initContractData(contractFullyQualifiedName, extraData = {}) {
  const { deployment, previousDeployment } = hre.router;

  const { sourceName, contractName } = parseFullyQualifiedName(contractFullyQualifiedName);
  const { deployedBytecode } = await hre.artifacts.readArtifact(contractFullyQualifiedName);

  const previousData = previousDeployment?.general.contracts[contractFullyQualifiedName] || {};
  const deployedBytecodeHash = getBytecodeHash(deployedBytecode);

  deployment.general.contracts[contractFullyQualifiedName] = {
    deployedAddress: '',
    deployTransaction: '',
    ...previousData,
    ...extraData,
    deployedBytecodeHash,
    contractFullyQualifiedName,
    contractName,
    sourceName,
  };

  const cachedSourceInfo = path.join(
    hre.router.paths.cache,
    'source-abis',
    deployedBytecodeHash + '.json'
  );
  if (fs.existsSync(cachedSourceInfo)) {
    const data = JSON.parse(fs.readFileSync(cachedSourceInfo));
    deployment.sources[sourceName] = data.sourceInfo;
    deployment.abis[`${sourceName}:${contractName}`] = data.abiInfo;
  } else {
    await _initContractSource(contractFullyQualifiedName);

    // save the resulting artifacts
    await mkdirp(dirname(cachedSourceInfo));

    fs.writeFileSync(
      cachedSourceInfo,
      JSON.stringify({
        sourceInfo: deployment.sources[sourceName],
        abiInfo: deployment.abis[`${sourceName}:${contractName}`],
      })
    );
  }
}

/**
 * Save contract sources, AST and bytcode to deployment files. Kept for maintaining
 * historic data.
 * @param {string} contractFullyQualifiedName
 */
async function _initContractSource(contractFullyQualifiedName) {
  const { deployment } = hre.router;

  const buildInfo = await hre.artifacts.getBuildInfo(contractFullyQualifiedName);

  // Save the source code for the entire dependency tree
  for (const [sourceName, attributes] of Object.entries(buildInfo.input.sources)) {
    if (!deployment.sources[sourceName]) {
      deployment.sources[sourceName] = {};
    }

    deployment.sources[sourceName].sourceCode = attributes.content;
  }

  // Save the asts for the entire dependency tree
  for (const [sourceName, attributes] of Object.entries(buildInfo.output.sources)) {
    deployment.sources[sourceName].ast = attributes.ast;
  }

  // Save the ABIs of all the contracts
  for (const [sourceName, contracts] of Object.entries(buildInfo.output.contracts)) {
    for (const [contractName, attributes] of Object.entries(contracts)) {
      deployment.abis[`${sourceName}:${contractName}`] = attributes.abi;
    }
  }
}

module.exports = {
  initContractData,
};
