// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

interface IGyroECLPPool { 
      function getRate() external view returns (uint256);
      function getPoolId() external view returns (bytes32);
      function getPriceRateCache(address token) external view returns (uint256, uint256, uint256);
      function totalSupply() external view returns (uint256);
      function getTokenRates() external view returns (uint256 rate0, uint256 rate1);
}
