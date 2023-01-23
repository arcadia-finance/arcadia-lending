/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */

pragma solidity ^0.8.0;

import "../../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import "../../lib/solmate/src/auth/Owned.sol";

/**
 * @dev This module provides a mechanism that allows authorized accounts to trigger an emergency stop
 *
 */
abstract contract Guardian is Context, Owned {
    address public guardian;

    event GuardianChanged(address indexed oldGuardian, address indexed newGuardian);
    event PauseUpdate(
        address account, bool repayPauseUpdate, bool withdrawPauseUpdate, bool borrowPauseUpdate, bool supplyPauseUpdate
    );

    bool public repayPaused;
    bool public withdrawPaused;
    bool public borrowPaused;
    bool public depositPaused;
    uint256 public pauseTimestamp;

    constructor() Owned(msg.sender) {
        repayPaused = false;
        withdrawPaused = false;
        borrowPaused = false;
        depositPaused = false;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Guardian: Only guardian can call this function");
        _;
    }

    modifier whenRepayNotPaused() {
        require(!repayPaused, "Guardian: repay paused");
        _;
    }

    modifier whenWithdrawNotPaused() {
        require(!withdrawPaused, "Guardian: withdraw paused");
        _;
    }

    modifier whenBorrowNotPaused() {
        require(!borrowPaused, "Guardian: borrow paused");
        _;
    }

    modifier whenDepositNotPaused() {
        require(!depositPaused, "Guardian: deposit paused");
        _;
    }

    //    function changeGuardian(address _newGuardian) external virtual {}

    function changeGuardian(address guardian_) external onlyOwner {
        guardian = guardian_;
        emit GuardianChanged(guardian, guardian_);
    }

    function pause() external onlyGuardian {
        require(block.timestamp > pauseTimestamp + 32 days, "Guardian: Cannot pause, Pause time not expired");
        repayPaused = true;
        withdrawPaused = true;
        borrowPaused = true;
        depositPaused = true;
        pauseTimestamp = block.timestamp;
        emit PauseUpdate(msg.sender, repayPaused, withdrawPaused, borrowPaused, depositPaused);
    }

    function unPause(bool repayPaused_, bool withdrawPaused_, bool borrowPaused_, bool depositPaused_)
        external
        onlyOwner
    {
        repayPaused = repayPaused && repayPaused_;
        withdrawPaused = withdrawPaused && withdrawPaused_;
        borrowPaused = borrowPaused && borrowPaused_;
        depositPaused = depositPaused && depositPaused_;
        emit PauseUpdate(msg.sender, repayPaused, withdrawPaused, borrowPaused, depositPaused);
    }

    function unPause() external {
        require(block.timestamp > pauseTimestamp + 30 days, "Guardian: Cannot unPause, unPause time not expired");
        if (repayPaused || withdrawPaused || borrowPaused || depositPaused) {
            repayPaused = false;
            withdrawPaused = false;
            borrowPaused = false;
            depositPaused = false;
            emit PauseUpdate(msg.sender, repayPaused, withdrawPaused, borrowPaused, depositPaused);
        }
    }
}