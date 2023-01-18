/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */

pragma solidity ^0.8.0;

import "../../lib/openzeppelin-contracts/contracts/utils/Context.sol";

/**
 * @dev This module provides a mechanism that allows authorized accounts to trigger an emergency stop
 *
 */
abstract contract MultiGuardian is Context {
    address public guardian;

    event GuardianChanged(address indexed oldGuardian, address indexed newGuardian);
    event PauseUpdate(
        address account, bool repayPauseUpdate, bool withdrawPauseUpdate, bool borrowPauseUpdate, bool supplyPauseUpdate
    );

    bool private _repayPaused;
    bool private _withdrawPaused;
    bool private _borrowPaused;
    bool private _supplyPaused;

    constructor() {
        _repayPaused = false;
        _withdrawPaused = false;
        _borrowPaused = false;
        _supplyPaused = false;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Guardian: Only guardian can call this function");
        _;
    }

    modifier whenRepayNotPaused() {
        require(!_repayPaused, "Guardian: repay paused");
        _;
    }

    modifier whenWithdrawNotPaused() {
        require(!_withdrawPaused, "Guardian: withdraw paused");
        _;
    }

    modifier whenBorrowNotPaused() {
        require(!_borrowPaused, "Guardian: borrow paused");
        _;
    }

    modifier whenSupplyNotPaused() {
        require(!_supplyPaused, "Guardian: supply paused");
        _;
    }

    function changeGuardian(address _newGuardian) external virtual {}

    function pause(bool repayPaused, bool withdrawPaused, bool borrowPaused, bool supplyPaused) external onlyGuardian {
        _repayPaused = repayPaused;
        _withdrawPaused = withdrawPaused;
        _borrowPaused = borrowPaused;
        _supplyPaused = supplyPaused;
        emit PauseUpdate(msg.sender, repayPaused, withdrawPaused, borrowPaused, supplyPaused);
    }
}
