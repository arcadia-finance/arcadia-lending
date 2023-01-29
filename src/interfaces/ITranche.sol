/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.13;

interface ITranche {
    /**
     * @notice Locks the tranche in case all liquidity of the tranche is written of due to bad debt
     */
    function lock() external;

    /**
     * @notice Locks the tranche while an auction is in progress
     */
    function setAuctionInProgress(bool _auctionInProgress) external;
}
