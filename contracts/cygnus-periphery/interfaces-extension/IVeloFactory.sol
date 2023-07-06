// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

interface IVeloFactory {
  function getFee(address, bool) external view returns (uint256);
}
