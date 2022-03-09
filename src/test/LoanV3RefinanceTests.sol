// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";

import { IDebtLocker }        from "../../lib/debt-locker/contracts/interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "../../lib/debt-locker/contracts/interfaces/IDebtLockerFactory.sol";
import { IMapleLoan }         from "../../lib/loan/contracts/interfaces/IMapleLoan.sol";
import { IMapleLoanFactory }  from "../../lib/loan/contracts/interfaces/IMapleLoanFactory.sol";
import { IRefinancer }        from "../../lib/loan/contracts/interfaces/IRefinancer.sol";

import { DebtLocker }           from "../../lib/debt-locker/contracts/DebtLocker.sol";
import { MapleLoan }            from "../../lib/loan/contracts/MapleLoan.sol";
import { MapleLoanInitializer } from "../../lib/loan/contracts/MapleLoanInitializer.sol";

import { IPoolLike, IUSDCLike } from "../interfaces/Interfaces.sol";

contract LoanV3RefinanceTests is TestUtils {

    address internal constant BORROWER      = address(0xb079F40dd951d842f688275100524c09bEf9b4E2);
    address internal constant GOVERNOR      = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address internal constant POOL_DELEGATE = address(0xA6cCb9483E3E7a737E3a4F5B72a1Ce51838ba122);
    address internal constant TREASURY      = address(0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19);

    address internal constant DEBT_LOCKER_IMPLEMENTATION_V200 = address(0xA134143D6bDEf75eD2FbbB4e7a8E70765c25a03C);
    address internal constant DEBT_LOCKER_INITIALIZER         = address(0x3D01aE38be6D81BD7c8De0D5Cd558eAb3F4cb79b);
    address internal constant LOAN_IMPLEMENTATION_V200        = address(0x97940C7aea99998da4c56922211ce012E7765395);
    address internal constant POOL                            = address(0xFeBd6F15Df3B73DC4307B1d7E65D46413e710C27);
    address internal constant REFINANCER                      = address(0x2cF4C679bc9B6073A3f68f7584809E5F177cC59A);
    address internal constant USDC                            = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint256 internal constant BASIS_POINTS      = 10000;
    uint256 internal constant USDC_STORAGE_SLOT = 9;
    uint256 internal constant YEAR              = 365 days;

    address internal immutable DEBT_LOCKER_IMPLEMENTATION_V300 = address(new DebtLocker());
    address internal immutable LOAN_IMPLEMENTATION_V300        = address(new MapleLoan());
    address internal immutable LOAN_INITIALIZER_V300           = address(new MapleLoanInitializer());

    IDebtLockerFactory internal constant DEBT_LOCKER_FACTORY = IDebtLockerFactory(0xA83404CAA79989FfF1d84bA883a1b8187397866C);
    IMapleLoanFactory  internal constant LOAN_FACTORY        = IMapleLoanFactory(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);

    IDebtLocker internal constant DEBT_LOCKER = IDebtLocker(0x55689CCB4274502335DD26CB75c31A8F1fAcD9f1);
    IMapleLoan  internal constant LOAN        = IMapleLoan(0x1597bc9C167bA318Da52EE94FDb0efAf84837BBF);

    function setUp() external {
        vm.startPrank(GOVERNOR);

        // Register the new version of the DebtLocker.
        DEBT_LOCKER_FACTORY.registerImplementation(300, DEBT_LOCKER_IMPLEMENTATION_V300, DEBT_LOCKER_INITIALIZER);
        DEBT_LOCKER_FACTORY.enableUpgradePath(200, 300, address(0));
        DEBT_LOCKER_FACTORY.setDefaultVersion(300);

        // Register the new version of the Loan.
        LOAN_FACTORY.registerImplementation(300, LOAN_IMPLEMENTATION_V300, LOAN_INITIALIZER_V300);
        LOAN_FACTORY.enableUpgradePath(200, 300, address(0));
        LOAN_FACTORY.setDefaultVersion(300);

        vm.stopPrank();

        // Upgrade the DebtLocker to the new version.
        vm.prank(POOL_DELEGATE);
        DEBT_LOCKER.upgrade(300, "");

        // Upgrade the Loan to the new version.
        vm.prank(BORROWER);
        LOAN.upgrade(300, "");
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
        calls[0] = abi.encodeWithSelector(IRefinancer.increasePrincipal.selector,    principalIncrease);
        calls[1] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      interestRate);
        calls[2] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, numberOfPayments);

        // Refinance the loan.
        _proposeNewTerms(calls);
        _acceptNewTerms(calls, principalIncrease);

        // Calculate the payment using the new terms of the loan.
        payment = _calculatePayment((initialPrincipal + principalIncrease), interestRate, loanDuration, numberOfPayments);
        ( principalPaid, interestPaid, delegateFeePaid, treasuryFeePaid ) = _makeNextPayment(payment);

        // Check establishment fees have been paid.
        assertEq(principalPaid,   0);
        assertEq(interestPaid,    payment - LOAN.delegateFee() -  LOAN.treasuryFee());
        assertEq(delegateFeePaid, LOAN.delegateFee());
        assertEq(treasuryFeePaid, LOAN.treasuryFee());
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
        vm.warp(LOAN.nextPaymentDueDate());
        ( principal_, interest_, delegateFee_, treasuryFee_ ) = LOAN.makePayment(payment_);

        vm.stopPrank();
    }

    function _proposeNewTerms(bytes[] memory calls_) internal {
        vm.prank(BORROWER);
        LOAN.proposeNewTerms(REFINANCER, type(uint256).max, calls_);
    }

    function _acceptNewTerms(bytes[] memory calls_, uint256 principalIncrease_) internal {
        vm.startPrank(POOL_DELEGATE);

        IPoolLike(POOL).claim(address(LOAN), address(DEBT_LOCKER_FACTORY));
        IPoolLike(POOL).fundLoan(address(LOAN), address(DEBT_LOCKER_FACTORY), principalIncrease_);

        DEBT_LOCKER.acceptNewTerms(REFINANCER, type(uint256).max, calls_, principalIncrease_);

        vm.stopPrank();
    }

    function _mintAndApprove(address account_, uint256 amount_) internal {
        erc20_mint(USDC, USDC_STORAGE_SLOT, account_, amount_);
        IUSDCLike(USDC).approve(address(LOAN), amount_);
    }

}
