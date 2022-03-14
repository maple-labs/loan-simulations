// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";

import { IDebtLocker }        from "../../modules/debt-locker/contracts/interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "../../modules/debt-locker/contracts/interfaces/IDebtLockerFactory.sol";

import { DebtLocker } from "../../modules/debt-locker/contracts/DebtLocker.sol";

contract DebtLockerV3UpgradeTests is TestUtils {

    address internal constant GOVERNOR      = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address internal constant POOL_DELEGATE = address(0xA6cCb9483E3E7a737E3a4F5B72a1Ce51838ba122);

    address internal constant DEBT_LOCKER_IMPLEMENTATION_V200 = address(0xA134143D6bDEf75eD2FbbB4e7a8E70765c25a03C);
    address internal constant DEBT_LOCKER_INITIALIZER         = address(0x3D01aE38be6D81BD7c8De0D5Cd558eAb3F4cb79b);

    address internal immutable DEBT_LOCKER_IMPLEMENTATION_V300 = address(new DebtLocker());

    IDebtLocker        internal constant DEBT_LOCKER         = IDebtLocker(0x55689CCB4274502335DD26CB75c31A8F1fAcD9f1);
    IDebtLockerFactory internal constant DEBT_LOCKER_FACTORY = IDebtLockerFactory(0xA83404CAA79989FfF1d84bA883a1b8187397866C);

    /**********************************/
    /*** DebtLocker state variables ***/
    /**********************************/

    address internal _liquidator;
    address internal _loan;
    address internal _pool;

    bool internal _repossessed;

    uint256 internal _allowedSlippage;
    uint256 internal _amountRecovered;
    uint256 internal _fundsToCapture;
    uint256 internal _minRatio;
    uint256 internal _principalRemainingAtLastClaim;

    function setUp() external {
        vm.startPrank(GOVERNOR);
        DEBT_LOCKER_FACTORY.registerImplementation(300, DEBT_LOCKER_IMPLEMENTATION_V300, DEBT_LOCKER_INITIALIZER);
        DEBT_LOCKER_FACTORY.enableUpgradePath(200, 300, address(0));
        DEBT_LOCKER_FACTORY.setDefaultVersion(300);
        vm.stopPrank();
    }

    function test_upgrade_errorChecks_dl() external {
        vm.expectRevert("DL:U:NOT_POOL_DELEGATE");
        DEBT_LOCKER.upgrade(300, "");

        vm.startPrank(POOL_DELEGATE);

        vm.expectRevert("MPF:UI:NOT_ALLOWED");
        DEBT_LOCKER.upgrade(210, "");

        vm.expectRevert("MPF:UI:FAILED");
        DEBT_LOCKER.upgrade(300, "0");

        DEBT_LOCKER.upgrade(300, "");

        vm.stopPrank();
    }

    function test_upgrade_storageAssertions() external {

        /********************/
        /*** Before state ***/
        /********************/

        _liquidator = DEBT_LOCKER.liquidator();
        _loan       = DEBT_LOCKER.loan();
        _pool       = DEBT_LOCKER.pool();

        _repossessed = DEBT_LOCKER.repossessed();

        _allowedSlippage               = DEBT_LOCKER.allowedSlippage();
        _amountRecovered               = DEBT_LOCKER.amountRecovered();
        _fundsToCapture                = DEBT_LOCKER.fundsToCapture();
        _minRatio                      = DEBT_LOCKER.minRatio();
        _principalRemainingAtLastClaim = DEBT_LOCKER.principalRemainingAtLastClaim();

        /***************/
        /*** Upgrade ***/
        /***************/

        assertEq(DEBT_LOCKER.implementation(), DEBT_LOCKER_IMPLEMENTATION_V200);

        vm.prank(POOL_DELEGATE);
        DEBT_LOCKER.upgrade(300, "");

        assertEq(DEBT_LOCKER.implementation(), DEBT_LOCKER_IMPLEMENTATION_V300);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(DEBT_LOCKER.liquidator(), _liquidator);
        assertEq(DEBT_LOCKER.loan(),       _loan);
        assertEq(DEBT_LOCKER.pool(),       _pool);

        assertTrue(DEBT_LOCKER.repossessed() == _repossessed);

        assertEq(DEBT_LOCKER.allowedSlippage(),               _allowedSlippage);
        assertEq(DEBT_LOCKER.amountRecovered(),               _amountRecovered);
        assertEq(DEBT_LOCKER.fundsToCapture(),                _fundsToCapture);
        assertEq(DEBT_LOCKER.minRatio(),                      _minRatio);
        assertEq(DEBT_LOCKER.principalRemainingAtLastClaim(), _principalRemainingAtLastClaim);
    }

}
