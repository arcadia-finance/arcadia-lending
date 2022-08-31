/** 
    This is a private, unpublished repository.
    All rights reserved to Arcadia Finance.
    Any modification, publication, reproduction, commercialization, incorporation, 
    sharing or any other kind of use of any part of this code or derivatives thereof is not allowed.
    
    SPDX-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.13;

interface IVault {
    function owner() external view returns (address);

    function increaseMarginPosition(uint256 baseCurrency, uint256 amount) external returns (bool);

    function decreaseMarginPosition(uint256 baseCurrency, uint256 amount) external returns (bool);
}