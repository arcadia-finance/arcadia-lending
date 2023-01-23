/**
 * Created by Arcadia Finance
 * https://www.arcadia.finance
 *
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import {Guardian} from "../src/security/Guardian.sol";

contract LendingPoolMockup is Guardian {
    uint256 public totalSupply;
    uint256 public totalBorrow;

    //    constructor()
    //    {}

    function depositGuarded(uint256 supply) external whenDepositNotPaused {
        totalSupply += supply;
    }

    function borrowUnguarded(uint256 borrow) external {
        totalBorrow += borrow;
    }

    function borrowGuarded(uint256 borrow) external whenBorrowNotPaused {
        totalBorrow += borrow;
    }

    function reset() external onlyOwner {
        totalSupply = 0;
        totalBorrow = 0;
    }
}

contract GuardianUnitTest is Test {
    using stdStorage for StdStorage;

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
        // Reset the lending pool variables
        vm.startPrank(owner);
        lendingPool.reset();
        vm.stopPrank();
        // Reset: the lending pool pauseTimestamp
        stdstore.target(address(lendingPool)).sig(lendingPool.pauseTimestamp.selector).checked_write(uint256(0));
        // Warp the block timestamp to 60days for smooth testing
        vm.warp(60 days);
    }

    function testSuccess_changeGuardian() public {
        // Given: the lending pool owner is owner§
        vm.startPrank(owner);
        // When: the owner changes the guardian
        lendingPool.changeGuardian(newGuardian);
        vm.stopPrank();
        // Then: the guardian is changed
        assertEq(lendingPool.guardian(), newGuardian);

        // When: The owner changes the guardian back to the original guardian
        vm.startPrank(owner);
        lendingPool.changeGuardian(guardian);
        vm.stopPrank();

        // Then: the guardian is changed
        assertEq(lendingPool.guardian(), guardian);
    }

    function testRevert_changeGuardian_onlyOwner() public {
        // Given: the lending pool owner is owner
        vm.startPrank(nonOwner);
        // When: a non-owner tries to change the guardian, it is reverted
        vm.expectRevert("UNAUTHORIZED");
        lendingPool.changeGuardian(guardian);
        vm.stopPrank();
        // Then: the guardian is not changed
        assertEq(lendingPool.guardian(), guardian);
    }

    function testRevert_pause_onlyGuard() public {
        // Given When Then: the lending pool is paused
        vm.expectRevert("Guardian: Only guardian can call this function");
        vm.startPrank(owner);
        lendingPool.pause();
        vm.stopPrank();
    }

    function testSuccess_depositGuarded_notPause() public {
        // Given: the lending pool is not paused
        vm.startPrank(user);
        // When: a user supplies
        lendingPool.depositGuarded(100);
        vm.stopPrank();
        // Then: the total supply is updated
        assertEq(lendingPool.totalSupply(), 100);
    }

    function testRevert_depositGuarded_paused() public {
        // Given: the lending pool supply is paused, only supply paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // When Then: a user tries to supply, it is reverted as paused
        vm.expectRevert("Guardian: deposit paused");
        vm.startPrank(user);
        lendingPool.depositGuarded(100);
        vm.stopPrank();

        // Then: the total supply is not updated
        assertEq(lendingPool.totalSupply(), 0);

        // When: owner can unPauses the borrow
        vm.startPrank(owner);
        lendingPool.unPause(true, true, false, true, true);
        vm.stopPrank();

        // Then: user tries to borrow, which is not paused
        vm.startPrank(user);
        lendingPool.borrowGuarded(100);
        vm.stopPrank();

        // Then: the total borrow is updated
        assertEq(lendingPool.totalBorrow(), 100);

        // Revert: the lending pool is unpaused
        vm.startPrank(owner);
        lendingPool.unPause(false, false, false, false, false);
        vm.stopPrank();
    }

    function testSuccess_borrowUnguarded_notPaused() public {
        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // When: a user borrows from unguarded function
        vm.startPrank(user);
        lendingPool.borrowUnguarded(100);
        vm.stopPrank();

        // Then: the total borrow is updated
        assertEq(lendingPool.totalBorrow(), 100);
    }

    function testRevert_borrowGuarded_paused() public {
        emit log_named_uint("pauset", lendingPool.pauseTimestamp());
        emit log_named_uint("times", block.timestamp);
        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // Given: only borrow left paused
        vm.startPrank(owner);
        lendingPool.unPause(false, false, true, false, false);
        vm.stopPrank();

        // When: a user tries to supply
        vm.startPrank(user);
        lendingPool.depositGuarded(100);
        vm.stopPrank();

        // Then: the total supply is updated
        assertEq(lendingPool.totalSupply(), 100);

        // When: user tries to borrow, which is paused
        vm.expectRevert("Guardian: borrow paused");
        vm.startPrank(user);
        lendingPool.borrowGuarded(100);
        vm.stopPrank();

        // Then: the total borrow is not updated
        assertEq(lendingPool.totalBorrow(), 0);

        // Revert: the lending pool is unpaused
        vm.startPrank(owner);
        lendingPool.unPause(false, false, false, false, false);
        vm.stopPrank();
    }

    function testSuccess_unPause_ownerCanUnPauseDuring30Days(uint256 timePassedAfterPause) public {
        vm.assume(timePassedAfterPause <= 30 days);

        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // Given: Sometime passed after the pause
        vm.warp(block.timestamp + timePassedAfterPause);

        // When: the owner unPauses the supply
        vm.startPrank(owner);
        lendingPool.unPause(true, true, true, false, true);
        vm.stopPrank();

        // Then: the user can supply
        vm.startPrank(user);
        lendingPool.depositGuarded(100);
        vm.stopPrank();

        // Then: the total supply is updated
        assertEq(lendingPool.totalSupply(), 100);
    }

    function testSuccess_unPause_onlyUnpausePossible(uint256 timePassedAfterPause) public {
        vm.assume(timePassedAfterPause <= 30 days);

        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // Given: Sometime passed after the pause
        vm.warp(block.timestamp + timePassedAfterPause);

        // When: the owner unPauses the supply
        vm.startPrank(owner);
        lendingPool.unPause(true, true, true, false, true);
        vm.stopPrank();

        // When: the owner attempts the pause the supply from the unPause
        vm.startPrank(owner);
        lendingPool.unPause(true, true, true, true, true);
        vm.stopPrank();

        // Then: the user can still supply because the once the supply is unPaused, it cannot be paused
        vm.startPrank(user);
        lendingPool.depositGuarded(100);
        vm.stopPrank();

        // Then: the total supply is updated
        assertEq(lendingPool.totalSupply(), 100);
    }

    function testRevert_pause_timeNotExpired(uint256 timePassedAfterPause) public {
        vm.assume(timePassedAfterPause < 32 days);

        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // Given: 1 day passed
        uint256 startTimestamp = block.timestamp;
        vm.warp(startTimestamp + 1 days);

        // When: the owner unPauses
        vm.startPrank(owner);
        lendingPool.unPause(false, false, false, false, false);
        vm.stopPrank();

        // Then: the guardian cannot pause again until 32 days passed from the first pause
        vm.warp(startTimestamp + timePassedAfterPause);
        vm.expectRevert("Guardian: Cannot pause, Pause time not expired");
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();
    }

    function testRevert_unPause_userCannotUnPauseBefore30Days(uint256 timePassedAfterPause) public {
        vm.assume(timePassedAfterPause < 30 days);

        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // Given: Sometime passed after the pause
        vm.warp(block.timestamp + timePassedAfterPause);

        // When: the user tries to unPause
        vm.expectRevert("Guardian: Cannot unPause, unPause time not expired");
        vm.startPrank(user);
        lendingPool.unPause();
        vm.stopPrank();
    }

    function testSuccess_unPause_userCanUnPauseAfter30Days(uint256 deltaTimePassedAfterPause) public {
        // Preprocess: the delta time passed after pause is at least 30 days
        vm.assume(deltaTimePassedAfterPause <= 120 days);
        vm.assume(deltaTimePassedAfterPause > 0);
        uint256 timePassedAfterPause = 30 days + deltaTimePassedAfterPause;

        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // Given: Sometime passed after the pause
        vm.warp(block.timestamp + timePassedAfterPause);

        // When: the user unPause
        vm.startPrank(user);
        lendingPool.unPause();
        vm.stopPrank();

        // Then: the user can supply
        vm.startPrank(user);
        lendingPool.depositGuarded(100);
        vm.stopPrank();
        assertEq(lendingPool.totalSupply(), 100);
    }

    function testRevert_pause_guardianCannotPauseAgainBetween30and32Days(uint8 deltaTimePassedAfterPause) public {
        // Preprocess: the delta time passed after pause is between 30 and 32 days
        vm.assume(deltaTimePassedAfterPause <= 2 days);
        uint256 timePassedAfterPause = 30 days + deltaTimePassedAfterPause;

        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        // Given: Sometime passed after the pause
        vm.warp(block.timestamp + timePassedAfterPause);

        // When: the guardian tries pause
        vm.startPrank(guardian);
        // Then: the guardian cannot pause again until 32 days passed from the first pause
        vm.expectRevert("Guardian: Cannot pause, Pause time not expired");
        lendingPool.pause();
        vm.stopPrank();
    }

    function testSuccess_pause_guardianCanPauseAgainAfter32days(uint32 timePassedAfterPause) public {
        // Preprocess: the delta time passed after pause is between 30 and 32 days
        vm.assume(timePassedAfterPause > 32 days);

        // Given: the lending pool is paused
        vm.startPrank(guardian);
        lendingPool.pause();
        vm.stopPrank();

        uint256 startTimestamp = block.timestamp;
        // Given: 30 days passed after the pause and user unpauses
        vm.warp(startTimestamp + 30 days + 1);
        vm.startPrank(user);
        lendingPool.unPause();
        vm.stopPrank();

        // Given: Sometime passed after the initial pause
        vm.warp(startTimestamp + timePassedAfterPause);

        // When: the guardian unPause
        vm.startPrank(guardian);
        // Then: the guardian can pause again because time passed
        lendingPool.pause();
        vm.stopPrank();
    }
}
