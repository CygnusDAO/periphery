// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

interface IAugustusSwapper {
    // MultiSwap calldata
    struct SellData {
        address fromToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 expectedAmount;
        address payable beneficiary;
        Path[] path;
        address payable partner;
        uint256 feePercent;
        bytes permit;
        uint256 deadline;
        bytes16 uuid;
    }

    struct Path {
        address to;
        uint256 totalNetworkFee; //NOT USED - Network fee is associated with 0xv3 trades
        Adapter[] adapters;
    }

    struct Adapter {
        address payable adapter;
    }

    function getTokenTransferProxy() external view returns (address);
}
