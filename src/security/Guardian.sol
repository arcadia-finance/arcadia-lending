/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../../lib/openzeppelin-contracts/contracts/security/Pausable.sol";

abstract contract Guardian is Pausable {
    address public guardian;

    event GuardianChanged(address indexed oldGuardian, address indexed newGuardian);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Guardian: Only guardian can call this function");
        _;
    }

    function changeGuardian(address _newGuardian) external virtual {}

    function pause() external onlyGuardian {
        _pause();
    }

    function unpause() external onlyGuardian {
        _unpause();
    }
}
