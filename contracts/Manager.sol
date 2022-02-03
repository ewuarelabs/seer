//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.2/contracts/access/Ownable.sol";
import "./ILendingPool.sol";
import "./Witch.sol";

contract Manager is Ownable {

    function removeStake(address asset, address to) public onlyOwner returns(uint256) {
        ILendingPool pool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        Witch wc;
        address _owner = Ownable.owner();
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(_owner);

        uint256 available = totalCollateralETH - totalDebtETH;
        uint256 removeAmount = wc.expiredStake() * available/100;

        return pool.withdraw(asset, removeAmount, to);
    }
}