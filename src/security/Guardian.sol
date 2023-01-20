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

    bool private _repayPaused;
    bool private _withdrawPaused;
    bool private _borrowPaused;
    bool private _supplyPaused;
    uint256 public pauseTimestamp;

    constructor() Owned(msg.sender) {
        _repayPaused = false;
        _withdrawPaused = false;
        _borrowPaused = false;
        _supplyPaused = false;
        //        pauseTimestamp = 0;
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

    //    function changeGuardian(address _newGuardian) external virtual {}

    function changeGuardian(address guardian_) external onlyOwner {
        emit GuardianChanged(guardian, guardian_);
        guardian = guardian_;
    }

    function pause() external onlyGuardian {
        require(block.timestamp > pauseTimestamp + 32 days, "Guardian: Cannot pause, Pause time not expired");
        _repayPaused = true;
        _withdrawPaused = true;
        _borrowPaused = true;
        _supplyPaused = true;
        pauseTimestamp = block.timestamp;
        emit PauseUpdate(msg.sender, _repayPaused, _withdrawPaused, _borrowPaused, _supplyPaused);
    }

    function unPause(bool repayPaused, bool withdrawPaused, bool borrowPaused, bool supplyPaused) external onlyOwner {
        _repayPaused = repayPaused && _repayPaused;
        _withdrawPaused = withdrawPaused && _withdrawPaused;
        _borrowPaused = borrowPaused && _borrowPaused;
        _supplyPaused = supplyPaused && _supplyPaused;
        emit PauseUpdate(msg.sender, repayPaused, withdrawPaused, borrowPaused, supplyPaused);
    }

    function unPause() external {
        require(block.timestamp > pauseTimestamp + 30 days, "Guardian: Cannot unPause, unPause time not expired");
        if (_repayPaused || _withdrawPaused || _borrowPaused || _supplyPaused) {
            _repayPaused = false;
            _withdrawPaused = false;
            _borrowPaused = false;
            _supplyPaused = false;
            emit PauseUpdate(msg.sender, _repayPaused, _withdrawPaused, _borrowPaused, _supplyPaused);
        }
    }
}
