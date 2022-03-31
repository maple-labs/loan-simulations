// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";

import { IMapleLoanFactory }  from "../../modules/loan-v3/contracts/interfaces/IMapleLoanFactory.sol";
import { IMapleLoan }         from "../../modules/loan-v3/contracts/interfaces/IMapleLoan.sol";

import { MapleLoan }             from "../../modules/loan-v3/contracts/MapleLoan.sol";
import { MapleLoanInitializer }  from "../../modules/loan-v3/contracts/MapleLoanInitializer.sol";

contract LoanV3UpgradeTests is TestUtils {

    address internal constant BORROWER = address(0xb079F40dd951d842f688275100524c09bEf9b4E2);
    address internal constant GOVERNOR = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);

    address internal constant LOAN_IMPLEMENTATION_V200 = address(0x97940C7aea99998da4c56922211ce012E7765395);

    address internal immutable LOAN_IMPLEMENTATION_V300 = address(new MapleLoan());
    address internal immutable LOAN_INITIALIZER_V300    = address(new MapleLoanInitializer());

    IMapleLoan        internal constant LOAN         = IMapleLoan(0x1597bc9C167bA318Da52EE94FDb0efAf84837BBF);
    IMapleLoanFactory internal constant LOAN_FACTORY = IMapleLoanFactory(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);

    // Existing Loan state variables.
    address internal _borrower;
    address internal _lender;
    address internal _pendingBorrower;
    address internal _pendingLender;

    address internal _collateralAsset;
    address internal _fundsAsset;

    uint256 internal _gracePeriod;
    uint256 internal _paymentInterval;

    uint256 internal _interestRate;
    uint256 internal _earlyFeeRate;
    uint256 internal _lateFeeRate;
    uint256 internal _lateInterestPremium;

    uint256 internal _collateralRequired;
    uint256 internal _principalRequested;
    uint256 internal _endingPrincipal;

    uint256 internal _drawableFunds;
    uint256 internal _claimableFunds;
    uint256 internal _collateral;
    uint256 internal _nextPaymentDueDate;
    uint256 internal _paymentsRemaining;
    uint256 internal _principal;

    bytes32 internal _refinanceCommitment;

    // Newly added state variables.
    uint256 internal _delegateFee;
    uint256 internal _treasuryFee;

    function setUp() external {
        vm.startPrank(GOVERNOR);
        LOAN_FACTORY.registerImplementation(300, LOAN_IMPLEMENTATION_V300, LOAN_INITIALIZER_V300);
        LOAN_FACTORY.setDefaultVersion(300);
        LOAN_FACTORY.enableUpgradePath(200, 300, address(0));
        vm.stopPrank();
    }

    function test_upgrade_errorChecks() external {
        vm.expectRevert("ML:U:NOT_BORROWER");
        LOAN.upgrade(300, "");

        vm.startPrank(BORROWER);

        vm.expectRevert("MPF:UI:NOT_ALLOWED");
        LOAN.upgrade(210, "");

        vm.expectRevert("MPF:UI:FAILED");
        LOAN.upgrade(300, "0");

        LOAN.upgrade(300, "");

        vm.stopPrank();
    }

    function test_upgrade_loan_storageAssertions() external {

        /********************/
        /*** Before state ***/
        /********************/

        _borrower        = LOAN.borrower();
        _lender          = LOAN.lender();
        _pendingBorrower = LOAN.pendingBorrower();
        _pendingLender   = LOAN.pendingLender();

        _collateralAsset = LOAN.collateralAsset();
        _fundsAsset      = LOAN.fundsAsset();

        _gracePeriod     = LOAN.gracePeriod();
        _paymentInterval = LOAN.paymentInterval();

        _interestRate        = LOAN.interestRate();
        _earlyFeeRate        = LOAN.earlyFeeRate();
        _lateFeeRate         = LOAN.lateFeeRate();
        _lateInterestPremium = LOAN.lateInterestPremium();

        _collateralRequired = LOAN.collateralRequired();
        _principalRequested = LOAN.principalRequested();
        _endingPrincipal    = LOAN.endingPrincipal();

        _drawableFunds      = LOAN.drawableFunds();
        _claimableFunds     = LOAN.claimableFunds();
        _collateral         = LOAN.collateral();
        _nextPaymentDueDate = LOAN.nextPaymentDueDate();
        _paymentsRemaining  = LOAN.paymentsRemaining();
        _principal          = LOAN.principal();

        /***************/
        /*** Upgrade ***/
        /***************/

        assertEq(LOAN.implementation(), LOAN_IMPLEMENTATION_V200);

        vm.prank(BORROWER);
        LOAN.upgrade(300, "");

        assertEq(LOAN.implementation(), LOAN_IMPLEMENTATION_V300);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(LOAN.borrower(),        _borrower);
        assertEq(LOAN.lender(),          _lender);
        assertEq(LOAN.pendingBorrower(), _pendingBorrower);
        assertEq(LOAN.pendingLender(),   _pendingLender);

        assertEq(LOAN.collateralAsset(), _collateralAsset);
        assertEq(LOAN.fundsAsset(),      _fundsAsset);

        assertEq(LOAN.gracePeriod(),     _gracePeriod);
        assertEq(LOAN.paymentInterval(), _paymentInterval);

        assertEq(LOAN.interestRate(),        _interestRate);
        assertEq(LOAN.earlyFeeRate(),        _earlyFeeRate);
        assertEq(LOAN.lateFeeRate(),         _lateFeeRate);
        assertEq(LOAN.lateInterestPremium(), _lateInterestPremium);

        assertEq(LOAN.collateralRequired(), _collateralRequired);
        assertEq(LOAN.principalRequested(), _principalRequested);
        assertEq(LOAN.endingPrincipal(),    _endingPrincipal);

        assertEq(LOAN.drawableFunds(),      _drawableFunds);
        assertEq(LOAN.claimableFunds(),     _claimableFunds);
        assertEq(LOAN.collateral(),         _collateral);
        assertEq(LOAN.nextPaymentDueDate(), _nextPaymentDueDate);
        assertEq(LOAN.paymentsRemaining(),  _paymentsRemaining);
        assertEq(LOAN.principal(),          _principal);

        assertEq(LOAN.refinanceCommitment(), 0);
        assertEq(LOAN.refinanceInterest(),   0);

        assertEq(LOAN.delegateFee(), 0);
        assertEq(LOAN.treasuryFee(), 0);
    }

}
