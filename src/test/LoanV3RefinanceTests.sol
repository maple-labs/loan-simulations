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

    // Accounts that interact with the contracts or are affected by them.
    address internal constant BORROWER      = address(0xb079F40dd951d842f688275100524c09bEf9b4E2);
    address internal constant GOVERNOR      = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address internal constant POOL_DELEGATE = address(0xA6cCb9483E3E7a737E3a4F5B72a1Ce51838ba122);
    address internal constant TREASURY      = address(0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19);

    // Contracts that are already deployed on the mainnet.
    address internal constant DEBT_LOCKER_IMPLEMENTATION_V200 = address(0xA134143D6bDEf75eD2FbbB4e7a8E70765c25a03C);
    address internal constant DEBT_LOCKER_INITIALIZER         = address(0x3D01aE38be6D81BD7c8De0D5Cd558eAb3F4cb79b);
    address internal constant LOAN_IMPLEMENTATION_V200        = address(0x97940C7aea99998da4c56922211ce012E7765395);
    address internal constant REFINANCER                      = address(0x2cF4C679bc9B6073A3f68f7584809E5F177cC59A);

    // Initial terms of the loan.
    uint256 internal constant PAYMENT_INTERVAL            = 30 days;
    uint256 internal constant STARTING_INTEREST_RATE      = 0.0975e18;
    uint256 internal constant STARTING_PAYMENTS_REMAINING = 6;
    uint256 internal constant STARTING_PRINCIPAL          = 10_000_000_000000;

    // New terms of the loan.
    uint256 internal constant DEADLINE               = type(uint256).max;
    uint256 internal constant NEW_INTEREST_RATE      = 0.1e18;
    uint256 internal constant NEW_PAYMENTS_REMAINING = 3;
    uint256 internal constant NEW_PRINCIPAL          = STARTING_PRINCIPAL + PRINCIPAL_INCREASE;
    uint256 internal constant PRINCIPAL_INCREASE     = 2_500_000_000000;

    // Starting balances of relevant contracts.
    uint256 internal immutable LOAN_STARTING_BALANCE          = USDC.balanceOf(address(LOAN));
    uint256 internal immutable POOL_DELEGATE_STARTING_BALANCE = USDC.balanceOf(POOL_DELEGATE);
    uint256 internal immutable TREASURY_STARTING_BALANCE      = USDC.balanceOf(TREASURY);

    // Expected establishment fees.
    uint256 internal immutable EXPECTED_POOL_DELEGATE_FEE = _calculateEstablishmentFee(NEW_PRINCIPAL, 33, PAYMENT_INTERVAL);
    uint256 internal immutable EXPECTED_TREASURY_FEE      = _calculateEstablishmentFee(NEW_PRINCIPAL, 66, PAYMENT_INTERVAL);

    // Newly deployed contracts.
    address internal immutable DEBT_LOCKER_IMPLEMENTATION_V300 = address(new DebtLocker());
    address internal immutable LOAN_IMPLEMENTATION_V300        = address(new MapleLoan());
    address internal immutable LOAN_INITIALIZER_V300           = address(new MapleLoanInitializer());

    // Contracts that are called directly in the test scenario.
    IDebtLocker        internal constant DEBT_LOCKER         = IDebtLocker(0x55689CCB4274502335DD26CB75c31A8F1fAcD9f1);
    IDebtLockerFactory internal constant DEBT_LOCKER_FACTORY = IDebtLockerFactory(0xA83404CAA79989FfF1d84bA883a1b8187397866C);
    IMapleLoan         internal constant LOAN                = IMapleLoan(0x1597bc9C167bA318Da52EE94FDb0efAf84837BBF);
    IMapleLoanFactory  internal constant LOAN_FACTORY        = IMapleLoanFactory(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);
    IPoolLike          internal constant POOL                = IPoolLike(0xFeBd6F15Df3B73DC4307B1d7E65D46413e710C27);
    IUSDCLike          internal constant USDC                = IUSDCLike(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

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
        // Assert the starting conditions of the loan.
        assertEq(LOAN.principal(),         STARTING_PRINCIPAL);
        assertEq(LOAN.endingPrincipal(),   STARTING_PRINCIPAL);
        assertEq(LOAN.interestRate(),      STARTING_INTEREST_RATE);
        assertEq(LOAN.paymentsRemaining(), STARTING_PAYMENTS_REMAINING);
        assertEq(LOAN.paymentInterval(),   PAYMENT_INTERVAL);
        
        // Make a payment before the refinance.
        uint256 payment = _calculatePayment(STARTING_PRINCIPAL, STARTING_INTEREST_RATE, PAYMENT_INTERVAL);
        ( uint256 principalPaid, uint256 interestPaid, uint256 delegateFeePaid, uint256 treasuryFeePaid ) = _makeNextPayment(payment);

        // Check only interest has been paid.
        assertEq(principalPaid,   0);
        assertEq(interestPaid,    payment);
        assertEq(delegateFeePaid, 0);
        assertEq(treasuryFeePaid, 0);

        // Check interest was received by the loan, and nothing was received by the pool delegate or treasury.
        assertEq(USDC.balanceOf(address(LOAN)), LOAN_STARTING_BALANCE + payment);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE);

        bytes[] memory calls = new bytes[](4);
        calls[2] = abi.encodeWithSelector(IRefinancer.increasePrincipal.selector,    PRINCIPAL_INCREASE);
        calls[3] = abi.encodeWithSelector(IRefinancer.setEndingPrincipal.selector,   NEW_PRINCIPAL);
        calls[0] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      NEW_INTEREST_RATE);
        calls[1] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, NEW_PAYMENTS_REMAINING);

        assertEq(LOAN.refinanceCommitment(), 0);

        // Propose new terms through the borrower.
        _proposeNewTerms(calls);

        assertEq(LOAN.refinanceCommitment(), keccak256(abi.encode(REFINANCER, DEADLINE, calls)));

        // Accept the new terms through the pool delegate.
        _acceptNewTerms(calls, PRINCIPAL_INCREASE);

        assertEq(LOAN.refinanceCommitment(), 0);

        // Check loan state has been updated correctly.
        assertEq(LOAN.principal(),         NEW_PRINCIPAL);
        assertEq(LOAN.endingPrincipal(),   NEW_PRINCIPAL);
        assertEq(LOAN.interestRate(),      NEW_INTEREST_RATE);
        assertEq(LOAN.paymentsRemaining(), NEW_PAYMENTS_REMAINING);
        assertEq(LOAN.paymentInterval(),   PAYMENT_INTERVAL);
        assertEq(LOAN.delegateFee(),       EXPECTED_POOL_DELEGATE_FEE);
        assertEq(LOAN.treasuryFee(),       EXPECTED_TREASURY_FEE);

        // Cache balances before the payment.
        uint256 loanBalanceBeforePayment         = USDC.balanceOf(address(LOAN));
        uint256 poolDelegateBalanceBeforePayment = USDC.balanceOf(POOL_DELEGATE);
        uint256 treasuryBalanceBeforePayment     = USDC.balanceOf(TREASURY);

        // Calculate the payment using the new terms of the loan, adding the establishment fees on top.
        payment = _calculatePayment(NEW_PRINCIPAL, NEW_INTEREST_RATE, PAYMENT_INTERVAL);
        ( principalPaid, interestPaid, delegateFeePaid, treasuryFeePaid ) = _makeNextPayment(payment);

        // Check establishment fees have been paid.
        assertEq(principalPaid,   0);
        assertEq(interestPaid,    payment);
        assertEq(delegateFeePaid, EXPECTED_POOL_DELEGATE_FEE);
        assertEq(treasuryFeePaid, EXPECTED_TREASURY_FEE);

        // Check loan, pool delegate, and treasury have received the fees.
        assertEq(USDC.balanceOf(address(LOAN)), loanBalanceBeforePayment + interestPaid - delegateFeePaid - treasuryFeePaid);
        assertEq(USDC.balanceOf(POOL_DELEGATE), poolDelegateBalanceBeforePayment + delegateFeePaid);
        assertEq(USDC.balanceOf(TREASURY),      treasuryBalanceBeforePayment + treasuryFeePaid);
    }

    /*************************/
    /*** Uitlity Functions ***/
    /*************************/

    function _calculatePayment(uint256 principal_, uint256 interestRate_, uint256 interval_) internal pure returns (uint256 payment_) {
        return principal_ * interestRate_ * interval_ / 365 days / 1e18;
    }

    function _calculateEstablishmentFee(uint256 principal_, uint256 feeRate_, uint256 interval_) internal pure returns (uint256 fee_) {
        return principal_ * feeRate_ * interval_ / 365 days / 100_00;
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
        LOAN.proposeNewTerms(REFINANCER, DEADLINE, calls_);
    }

    function _acceptNewTerms(bytes[] memory calls_, uint256 PRINCIPAL_INCREASE_) internal {
        vm.startPrank(POOL_DELEGATE);

        POOL.fundLoan(address(LOAN), address(DEBT_LOCKER_FACTORY), PRINCIPAL_INCREASE_);
        POOL.claim(address(LOAN), address(DEBT_LOCKER_FACTORY));

        DEBT_LOCKER.acceptNewTerms(REFINANCER, DEADLINE, calls_, PRINCIPAL_INCREASE_);

        vm.stopPrank();
    }

    function _mintAndApprove(address account_, uint256 amount_) internal {
        erc20_mint(address(USDC), 9, account_, amount_);
        USDC.approve(address(LOAN), amount_);
    }

}

// TODO: test refinance same principal
// TODO: test refinance reduced principal

// TODO: test refinance before upgrade (propose and accept before upgrade)
// TODO: test refinance during upgrade (propose before upgrade, accept after upgrade)
