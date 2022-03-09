// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

interface IPoolLike {
    function claim(address loan_, address debtLockerFactory_) external returns (uint256[7] memory claimInfo_);
    function fundLoan(address loan_, address debtLockerFactory_, uint256 amount_) external;
    function liquidityLocker() external view returns (address liquidityLocker_);
}

interface IUSDCLike {
    function approve(address account_, uint256 amount_) external;
    function balanceOf(address account_) external view returns (uint256 balance_);
    function transfer(address to_, uint256 amount_) external returns (bool success_);
}
