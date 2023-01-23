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

    /*
    //////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////
    */

    event GuardianChanged(address indexed oldGuardian, address indexed newGuardian);
    event PauseUpdate(
        address account, bool repayPauseUpdate, bool withdrawPauseUpdate, bool borrowPauseUpdate, bool supplyPauseUpdate
    );

    /*
    //////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////
    */
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

    /*
    //////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////
    */

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyGuardian() {
        require(msg.sender == guardian, "Guardian: Only guardian can call this function");
        _;
    }

    /**
     * @dev Throws if repay is paused.
     */
    modifier whenRepayNotPaused() {
        require(!repayPaused, "Guardian: repay paused");
        _;
    }

    /**
     * @dev Throws if withdraw is paused.
     */
    modifier whenWithdrawNotPaused() {
        require(!withdrawPaused, "Guardian: withdraw paused");
        _;
    }

    /**
     * @dev Throws if borrow is paused.
     */
    modifier whenBorrowNotPaused() {
        require(!borrowPaused, "Guardian: borrow paused");
        _;
    }

    /**
     * @dev Throws if deposit is paused.
     */
    modifier whenDepositNotPaused() {
        require(!depositPaused, "Guardian: deposit paused");
        _;
    }

    /**
     * @param guardian_ The address of the new guardian.
     * @dev Allows onlyOwner to change the guardian address.
     */
    function changeGuardian(address guardian_) external onlyOwner {
        guardian = guardian_;
        emit GuardianChanged(guardian, guardian_);
    }

    /**
     * @dev Pauses repay, withdraw, borrow, and deposit functionality.
     * @dev Only guardian can call this function.
     * @dev This function can only be called once every 32 days. This is to prevent the guardian from
     *      accidentally or maliciously locking the protocol.
     * @dev This function can be called again after 32 days.
     */
    function pause() external onlyGuardian {
        require(block.timestamp > pauseTimestamp + 32 days, "Guardian: Cannot pause, Pause time not expired");
        repayPaused = true;
        withdrawPaused = true;
        borrowPaused = true;
        depositPaused = true;
        pauseTimestamp = block.timestamp;
        emit PauseUpdate(msg.sender, repayPaused, withdrawPaused, borrowPaused, depositPaused);
    }

    /**
     * @param repayPaused_ Whether repay functionality should be paused.
     * @param withdrawPaused_ Whether withdraw functionality should be paused.
     * @param borrowPaused_ Whether borrow functionality should be paused.
     * @param depositPaused_ Whether deposit functionality should be paused.
     * @dev Unpauses repay, withdraw, borrow, and deposit functionality.
     * @dev Only owner can call this function.
     * @dev updates the variables if incoming variable is false. If variable is false and incoming variable is true, then it does not update the variable.
     */
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

    /**
     * @dev Unpauses repay, withdraw, borrow, and deposit functionality.
     * @dev Users can call this function after 30 days that the protocol is paused.
     * @dev unpauses all the variables
     */
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
