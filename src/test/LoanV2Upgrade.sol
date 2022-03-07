// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";

import { IMapleLoan }            from "../../lib/loan/contracts/interfaces/IMapleLoan.sol";
import { IMapleLoanFactory }     from "../../lib/loan/contracts/interfaces/IMapleLoanFactory.sol";

import { MapleLoan }            from "../../lib/loan/contracts/MapleLoan.sol";
import { MapleLoanInitializer } from "../../lib/loan/contracts/MapleLoanInitializer.sol";

contract LoanV2UpgradeTests is TestUtils {

    address internal constant BORROWER                 = address(0xa8c42bBb0648511cC9004fbDCf0FA365088F862B);
    address internal constant FACTORY                  = address(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);
    address internal constant GOVERNOR                 = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address internal constant LENDER                   = address(0xCba99a6648450a7bE7f20B1C3258F74Adb662020);
    address internal constant LOAN                     = address(0x7dF5A2238C62e4b7E05238Da1FBe4b6FbbE22770);
    address internal constant LOAN_IMPLEMENTATION_V200 = address(0x97940C7aea99998da4c56922211ce012E7765395);

    address internal immutable LOAN_IMPLEMENTATION_V300 = address(new MapleLoan());
    address internal immutable LOAN_INITIALIZER_V300    = address(new MapleLoanInitializer());

    /******************************/
    /*** LoanV2 state variables ***/
    /******************************/

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

    /**********************************/
    /*** New LoanV3 state variables ***/
    /**********************************/

    uint256 internal _delegateFee;
    uint256 internal _treasuryFee;

    function setUp() external {
        vm.startPrank(GOVERNOR);
        IMapleLoanFactory(FACTORY).registerImplementation(300, LOAN_IMPLEMENTATION_V300, LOAN_INITIALIZER_V300);
        IMapleLoanFactory(FACTORY).setDefaultVersion(300);
        IMapleLoanFactory(FACTORY).enableUpgradePath(200, 300, address(0));
        vm.stopPrank();
    }

    function test_upgrade_errorChecks() external {
        vm.expectRevert("ML:U:NOT_BORROWER");
        IMapleLoan(LOAN).upgrade(300, "");

        vm.startPrank(BORROWER);

        vm.expectRevert("MPF:UI:NOT_ALLOWED");
        IMapleLoan(LOAN).upgrade(210, "");

        vm.expectRevert("MPF:UI:FAILED");
        IMapleLoan(LOAN).upgrade(300, "0");

        IMapleLoan(LOAN).upgrade(300, "");

        vm.stopPrank();
    }

    function test_upgrade_storageAssertions() external {

        /********************/
        /*** Before state ***/
        /********************/

        _borrower        = IMapleLoan(LOAN).borrower();
        _lender          = IMapleLoan(LOAN).lender();
        _pendingBorrower = IMapleLoan(LOAN).pendingBorrower();
        _pendingLender   = IMapleLoan(LOAN).pendingLender();

        _collateralAsset = IMapleLoan(LOAN).collateralAsset();
        _fundsAsset      = IMapleLoan(LOAN).fundsAsset();

        _gracePeriod     = IMapleLoan(LOAN).gracePeriod();
        _paymentInterval = IMapleLoan(LOAN).paymentInterval();

        _interestRate        = IMapleLoan(LOAN).interestRate();
        _earlyFeeRate        = IMapleLoan(LOAN).earlyFeeRate();
        _lateFeeRate         = IMapleLoan(LOAN).lateFeeRate();
        _lateInterestPremium = IMapleLoan(LOAN).lateInterestPremium();

        _collateralRequired = IMapleLoan(LOAN).collateralRequired();
        _principalRequested = IMapleLoan(LOAN).principalRequested();
        _endingPrincipal    = IMapleLoan(LOAN).endingPrincipal();

        _drawableFunds      = IMapleLoan(LOAN).drawableFunds();
        _claimableFunds     = IMapleLoan(LOAN).claimableFunds();
        _collateral         = IMapleLoan(LOAN).collateral();
        _nextPaymentDueDate = IMapleLoan(LOAN).nextPaymentDueDate();
        _paymentsRemaining  = IMapleLoan(LOAN).paymentsRemaining();
        _principal          = IMapleLoan(LOAN).principal();

        /***************/
        /*** Upgrade ***/
        /***************/

        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V200);

        vm.prank(BORROWER);
        IMapleLoan(LOAN).upgrade(300, "");

        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V300);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(IMapleLoan(LOAN).borrower(),        _borrower);
        assertEq(IMapleLoan(LOAN).lender(),          _lender);
        assertEq(IMapleLoan(LOAN).pendingBorrower(), _pendingBorrower);
        assertEq(IMapleLoan(LOAN).pendingLender(),   _pendingLender);

        assertEq(IMapleLoan(LOAN).collateralAsset(), _collateralAsset);
        assertEq(IMapleLoan(LOAN).fundsAsset(),      _fundsAsset);

        assertEq(IMapleLoan(LOAN).gracePeriod(),     _gracePeriod);
        assertEq(IMapleLoan(LOAN).paymentInterval(), _paymentInterval);

        assertEq(IMapleLoan(LOAN).interestRate(),        _interestRate);
        assertEq(IMapleLoan(LOAN).earlyFeeRate(),        _earlyFeeRate);
        assertEq(IMapleLoan(LOAN).lateFeeRate(),         _lateFeeRate);
        assertEq(IMapleLoan(LOAN).lateInterestPremium(), _lateInterestPremium);

        assertEq(IMapleLoan(LOAN).collateralRequired(), _collateralRequired);
        assertEq(IMapleLoan(LOAN).principalRequested(), _principalRequested);
        assertEq(IMapleLoan(LOAN).endingPrincipal(),    _endingPrincipal);

        assertEq(IMapleLoan(LOAN).drawableFunds(),      _drawableFunds);
        assertEq(IMapleLoan(LOAN).claimableFunds(),     _claimableFunds);
        assertEq(IMapleLoan(LOAN).collateral(),         _collateral);
        assertEq(IMapleLoan(LOAN).nextPaymentDueDate(), _nextPaymentDueDate);
        assertEq(IMapleLoan(LOAN).paymentsRemaining(),  _paymentsRemaining);
        assertEq(IMapleLoan(LOAN).principal(),          _principal);

        assertEq(IMapleLoan(LOAN).refinanceCommitment(), 0);

        assertEq(IMapleLoan(LOAN).delegateFee(), 0);
        assertEq(IMapleLoan(LOAN).treasuryFee(), 0);
    }

    function test_upgrade_ongoingPayments() external {
        // TODO
    }

}
