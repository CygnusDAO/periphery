// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

import {IVault} from "./IVault.sol";

/**
 *  @notice Balacner V2 Weighted Pool
 */
interface IWeightedPool {
  function getNormalizedWeights() external view returns (uint256[] memory);
  function getPoolId() external view returns (bytes32);
  function getInvariant() external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function getLastInvariant() external view returns (uint256, uint256);
  function getVault() external view returns (IVault);
}
