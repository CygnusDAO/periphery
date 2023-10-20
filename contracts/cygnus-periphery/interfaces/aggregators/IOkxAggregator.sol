// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

interface IOkxAggregator {
  function approveProxy() external view returns (address);
}

interface IOkxProxy { 
  function tokenApprove() external view returns (address);
}
