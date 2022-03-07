// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";

import { IMapleLoan }            from "../../lib/loan/contracts/interfaces/IMapleLoan.sol";
import { IMapleLoanInitializer } from "../../lib/loan/contracts/interfaces/IMapleLoanInitializer.sol";
import { IMapleLoanFactory }     from "../../lib/loan/contracts/interfaces/IMapleLoanFactory.sol";

import { MapleLoan }            from "../../lib/loan/contracts/MapleLoan.sol";
import { MapleLoanInitializer } from "../../lib/loan/contracts/MapleLoanInitializer.sol";
import { Refinancer }           from "../../lib/loan/contracts/Refinancer.sol";

import { IDebtLockerLike, IPoolLike, IUSDCLike } from "../interfaces/Interfaces.sol";

contract LoanV3RefinanceTests is TestUtils {

    address internal constant BORROWER                 = address(0xb079F40dd951d842f688275100524c09bEf9b4E2);
    address internal constant DEBT_LOCKER              = address(0x55689CCB4274502335DD26CB75c31A8F1fAcD9f1);
    address internal constant DEBT_LOCKER_FACTORY      = address(0xA83404CAA79989FfF1d84bA883a1b8187397866C);
    address internal constant GOVERNOR                 = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address internal constant LOAN                     = address(0x1597bc9C167bA318Da52EE94FDb0efAf84837BBF);
    address internal constant LOAN_FACTORY             = address(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);
    address internal constant LOAN_IMPLEMENTATION_V200 = address(0x97940C7aea99998da4c56922211ce012E7765395);
    address internal constant POOL                     = address(0xFeBd6F15Df3B73DC4307B1d7E65D46413e710C27);
    address internal constant POOL_DELEGATE            = address(0xA6cCb9483E3E7a737E3a4F5B72a1Ce51838ba122);
    address internal constant TREASURY                 = address(0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19);
    address internal constant USDC                     = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint256 internal constant BASIS_POINTS      = 10000;
    uint256 internal constant USDC_STORAGE_SLOT = 9;
    uint256 internal constant YEAR              = 365 days;

    address internal immutable LOAN_IMPLEMENTATION_V300 = address(new MapleLoan());
    address internal immutable LOAN_INITIALIZER_V300    = address(new MapleLoanInitializer());
    address internal immutable REFINANCER               = address(new Refinancer());

    function setUp() external {
        // Register the new version of the loan.
        vm.startPrank(GOVERNOR);
        IMapleLoanFactory(LOAN_FACTORY).registerImplementation(300, LOAN_IMPLEMENTATION_V300, LOAN_INITIALIZER_V300);
        IMapleLoanFactory(LOAN_FACTORY).enableUpgradePath(200, 300, address(0));
        IMapleLoanFactory(LOAN_FACTORY).setDefaultVersion(300);
        vm.stopPrank();

        // Upgrade the loan to the new version.
        vm.prank(BORROWER);
        IMapleLoan(LOAN).upgrade(300, "");
    }

    function test_refinance_afterUpgrade_principalIncrease() external {
        // Define the current terms of the loan.
        uint256 initialPrincipal  = 10_000_000_000000;
        uint256 interestRate      = 9_75;
        uint256 loanDuration      = 180 days;
        uint256 numberOfPayments  = 6;

        // Make a payment before the refinance.
        uint256 payment = _calculatePayment(initialPrincipal, interestRate, loanDuration, numberOfPayments);
        ( uint256 principalPaid, uint256 interestPaid, uint256 delegateFeePaid, uint256 treasuryFeePaid ) = _makeNextPayment(payment);

        // Check only interest has been paid.
        assertEq(principalPaid,   0);
        assertEq(interestPaid,    payment);
        assertEq(delegateFeePaid, 0);
        assertEq(treasuryFeePaid, 0);

        // Define new terms of the loan.
        uint256 principalIncrease = 2_500_000_000000;
        interestRate              = 10_00;
        loanDuration              = 90 days;
        numberOfPayments          = 3;

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(Refinancer.increasePrincipal.selector,    principalIncrease);
        calls[1] = abi.encodeWithSelector(Refinancer.setInterestRate.selector,      interestRate);
        calls[2] = abi.encodeWithSelector(Refinancer.setPaymentsRemaining.selector, numberOfPayments);

        // Refinance the loan.
        _proposeNewTerms(calls);
        _acceptNewTerms(calls, principalIncrease);

        // Calculate the payment using the new terms of the loan.
        payment = _calculatePayment((initialPrincipal + principalIncrease), interestRate, loanDuration, numberOfPayments);
        ( principalPaid, interestPaid, delegateFeePaid, treasuryFeePaid ) = _makeNextPayment(payment);

        // Calculate the expected establishment fees.
        uint256 expectedDelegateFeePaid = IMapleLoan(LOAN).delegateFee();
        uint256 expectedTreasuryFeePaid = IMapleLoan(LOAN).treasuryFee();

        // Check establishment fees have been paid.
        assertEq(principalPaid,   0);
        assertEq(interestPaid,    payment - expectedDelegateFeePaid - expectedTreasuryFeePaid);
        assertEq(delegateFeePaid, expectedDelegateFeePaid);
        assertEq(treasuryFeePaid, expectedTreasuryFeePaid);
    }

    function test_refinance_beforeUpgrade() external {
        // TODO
    }

    function test_refinance_duringUpgrade() external {
        // TODO
    }

    /*************************/
    /*** Uitlity Functions ***/
    /*************************/

    function _calculatePayment(uint256 principal, uint256 interestRate, uint256 loanDuration, uint256 numberOfPayments) internal pure returns (uint256 payment) {
        return principal * interestRate * loanDuration / YEAR / numberOfPayments / BASIS_POINTS;
    }

    function _makeNextPayment(uint256 payment_) internal returns (uint256 principal_, uint256 interest_, uint256 delegateFee_, uint256 treasuryFee_) {
        vm.startPrank(BORROWER);
        _mintAndApprove(BORROWER, payment_);
        vm.warp(IMapleLoan(LOAN).nextPaymentDueDate());
        ( principal_, interest_, delegateFee_, treasuryFee_ ) = IMapleLoan(LOAN).makePayment(payment_);
        vm.stopPrank();
    }

    function _proposeNewTerms(bytes[] memory calls_) internal {
        vm.prank(BORROWER);
        IMapleLoan(LOAN).proposeNewTerms(REFINANCER, type(uint256).max, calls_);
    }

    // TODO: Update the DebtLocker to use the new `acceptNewTerms` signature?
    // TODO: Is this even the correct workflow for accepting new terms anymore?
    function _acceptNewTerms(bytes[] memory calls_, uint256 principalIncrease_) internal {
        vm.startPrank(POOL_DELEGATE);
        IPoolLike(POOL).fundLoan(LOAN, DEBT_LOCKER_FACTORY, principalIncrease_);
        IDebtLockerLike(DEBT_LOCKER).acceptNewTerms(REFINANCER, /* type(uint256).max, */ calls_, principalIncrease_);
        vm.stopPrank();
    }

    function _mintAndApprove(address account_, uint256 amount_) internal {
        erc20_mint(USDC, USDC_STORAGE_SLOT, account_, amount_);
        IUSDCLike(USDC).approve(LOAN, amount_);
    }

}
