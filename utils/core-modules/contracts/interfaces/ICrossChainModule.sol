//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

/**
 * @title Module with assorted cross-chain functions.
 */
interface ICrossChainModule {
    /**
     * @notice Emitted when a new cross chain network becomes supported by the protocol
     */
    event NewSupportedCrossChainNetwork(uint64 newChainId);

    /**
     * @notice Configure CCIP addresses router.
     * @param ccipRouter The address on this chain to which CCIP messages will be sent or received.
     */
    function configureChainlinkCrossChain(address ccipRouter) external;

    /**
     * @notice Used to add new cross chain networks to the protocol
     * Ignores a network if it matches the current chain id
     * Ignores a network if it has already been added, but still updates target if changed
     * @param supportedNetworks array of all networks that are supported by the protocol
     * @param supportedNetworkTargets array of the target addresses for each network
     * @param ccipSelectors the ccip "selector" which maps to the chain id on the same index. must be same length as `supportedNetworks`
     * @return numRegistered the number of networks that were actually registered
     */
    function setSupportedCrossChainNetworksWithTargets(
        uint64[] memory supportedNetworks,
        address[] memory supportedNetworkTargets,
        uint64[] memory ccipSelectors
    ) external returns (uint256 numRegistered);

    /**
     * @notice Helper function for `setSupportedCrossChainNetworksWithTargets`, which allows you to not set
     * the target addresses for each network, in which case is going to point to address(this).
     * @param supportedNetworks array of all networks that are supported by the protocol
     * @param ccipSelectors the ccip "selector" which maps to the chain id on the same index. must be same length as `supportedNetworks`
     * @return numRegistered the number of networks that were actually registered
     */
    function setSupportedCrossChainNetworks(
        uint64[] memory supportedNetworks,
        uint64[] memory ccipSelectors
    ) external returns (uint256 numRegistered);
}
