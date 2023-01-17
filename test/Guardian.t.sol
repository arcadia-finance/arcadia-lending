/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../src/security/Guardian.sol";

contract LendingPoolMockup is Guardian {
    uint256 public totalSupply;
    uint256 public totalBorrow;
    address owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function changeGuardian(address guardian_) external override onlyOwner {
        emit GuardianChanged(guardian, guardian_);
        guardian = guardian_;
    }

    function supplyGuarded(uint256 supply) external whenNotPaused {
        totalSupply += supply;
    }

    function borrowUnguarded(uint256 borrow) external {
        totalBorrow += borrow;
    }

    function reset() external onlyOwner {
        totalSupply = 0;
        totalBorrow = 0;
    }
}

contract GuardianTest is Test {
    LendingPoolMockup lendingPool;
    address newGuardian = address(1);
    address guardian = address(2);
    address owner = address(3);
    address nonOwner = address(4);
    address user = address(5);

    constructor() {
        vm.startPrank(owner);
        lendingPool = new LendingPoolMockup();
        lendingPool.changeGuardian(guardian);
        vm.stopPrank();
    }

    function setUp() public virtual {
        vm.startPrank(owner);
        lendingPool.reset();
        vm.stopPrank();
    }

    function testSuccess_changeGuardian() public {
        vm.startPrank(owner);
        lendingPool.changeGuardian(newGuardian);
        vm.stopPrank();
        assertEq(lendingPool.guardian(), newGuardian);

        // Revert: Get
        vm.startPrank(owner);
        lendingPool.changeGuardian(guardian);
        vm.stopPrank();
    }

    function testRevert_changeGuardian_onlyOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        lendingPool.changeGuardian(guardian);
        vm.stopPrank();
    }

    function testSuccess_supplyGuarded_notPause() public {
        vm.startPrank(user);
        lendingPool.supplyGuarded(100);
        vm.stopPrank();
        assertEq(lendingPool.totalSupply(), 100);
    }

    function testRevert_supplyGuarded_paused() public {
        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // When Then: a user tries to supply, it is reverted as paused
        vm.expectRevert("Pausable: paused");
        vm.startPrank(user);
        lendingPool.supplyGuarded(100);
        vm.stopPrank();

        // Then: the total supply is not updated
        assertEq(lendingPool.totalSupply(), 0);

        // Revert: the lending pool is unpaused
        vm.startPrank(guardian);
        lendingPool.unpause();
        vm.stopPrank();
    }

    function testSuccess_borrowUnguarded_notPaused() public {
        vm.startPrank(user);
        lendingPool.borrowUnguarded(100);
        vm.stopPrank();
        assertEq(lendingPool.totalBorrow(), 100);
    }

    function testRevert_borrowUnguarded_paused() public {
        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // When Then: a user tries to supply, it is reverted as paused
        vm.expectRevert("Pausable: paused");
        vm.startPrank(user);
        lendingPool.supplyGuarded(100);
        vm.stopPrank();

        // Then: the total supply is not updated
        assertEq(lendingPool.totalSupply(), 0);

        // Revert: the lending pool is unpaused
        vm.startPrank(guardian);
        lendingPool.unpause();
        vm.stopPrank();
    }
}
