/** 
    This is a private, unpublished repository.
    All rights reserved to Arcadia Finance.
    Any modification, publication, reproduction, commercialization, incorporation, 
    sharing or any other kind of use of any part of this code or derivatives thereof is not allowed.
    
    SPDX-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.13;

import "../../lib/solmate/src/tokens/ERC20.sol";

interface ILiquidityPool {
    function asset() external returns (ERC20);

    function deposit(uint256 assets, address from) external;

    function withdraw(uint256 assets, address receiver, address owner) external;
}