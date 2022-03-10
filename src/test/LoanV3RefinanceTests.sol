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
    uint256 internal constant NEW_INTEREST_RATE      = 0.1e18;
    uint256 internal constant NEW_PAYMENTS_REMAINING = 3;
    uint256 internal constant PRINCIPAL_DECREASE     = 1_500_000_000000;
    uint256 internal constant PRINCIPAL_INCREASE     = 2_500_000_000000;
    uint256 internal constant PROPOSAL_DURATION      = 10 days;

    // Starting balances of relevant contracts.
    uint256 internal immutable LOAN_STARTING_BALANCE          = USDC.balanceOf(address(LOAN));
    uint256 internal immutable POOL_DELEGATE_STARTING_BALANCE = USDC.balanceOf(POOL_DELEGATE);
    uint256 internal immutable TREASURY_STARTING_BALANCE      = USDC.balanceOf(TREASURY);

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

        // Calculate expected payment before refinance.
        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check only interest will be paid.
        assertEq(principal,   0);
        assertEq(interest,    _calculateInterestPayment(STARTING_PRINCIPAL, STARTING_INTEREST_RATE, PAYMENT_INTERVAL));
        assertEq(delegateFee, 0);
        assertEq(treasuryFee, 0);

        _makeNextPayment(interest);

        // Check interest was received by the loan, and nothing was received by the pool delegate or treasury.
        assertEq(USDC.balanceOf(address(LOAN)), LOAN_STARTING_BALANCE + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE);

        uint256 deadline = block.timestamp + PROPOSAL_DURATION;
        uint256 newPrincipal = STARTING_PRINCIPAL + PRINCIPAL_INCREASE;

        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSelector(IRefinancer.increasePrincipal.selector,    PRINCIPAL_INCREASE);
        calls[1] = abi.encodeWithSelector(IRefinancer.setEndingPrincipal.selector,   newPrincipal);
        calls[2] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      NEW_INTEREST_RATE);
        calls[3] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, NEW_PAYMENTS_REMAINING);

        assertEq(LOAN.refinanceCommitment(), 0);

        _proposeNewTerms(deadline, calls);

        assertEq(LOAN.refinanceCommitment(), keccak256(abi.encode(REFINANCER, deadline, calls)));

        // Accept the new terms before the deadline expires.
        vm.warp(block.timestamp + PROPOSAL_DURATION / 2);
        _acceptNewTerms(deadline, calls, PRINCIPAL_INCREASE);

        assertEq(LOAN.refinanceCommitment(), 0);

        // Cache pool delegate balance after the refinance.
        uint256 poolDelegateBalanceAfterRefinance = USDC.balanceOf(POOL_DELEGATE);

        // Drawdown all of the funds.
        _drawdownFunds();

        // Calculate expected establishment fees.
        uint256 expectedPoolDelegateFee = _calculateEstablishmentFee(newPrincipal, 33, PAYMENT_INTERVAL);
        uint256 expectedTreasuryFee     = _calculateEstablishmentFee(newPrincipal, 66, PAYMENT_INTERVAL);

        // Check loan state has been updated correctly.
        assertEq(LOAN.principal(),         newPrincipal);
        assertEq(LOAN.endingPrincipal(),   newPrincipal);
        assertEq(LOAN.interestRate(),      NEW_INTEREST_RATE);
        assertEq(LOAN.paymentsRemaining(), NEW_PAYMENTS_REMAINING);
        assertEq(LOAN.paymentInterval(),   PAYMENT_INTERVAL);
        assertEq(LOAN.delegateFee(),       expectedPoolDelegateFee);
        assertEq(LOAN.treasuryFee(),       expectedTreasuryFee);

        // Calculate the interest payment using the new terms of the loan, adding the establishment fees on top.
        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check interest and establishment fees have been defined correctly.
        assertEq(principal,   0);
        assertEq(interest,    _calculateInterestPayment(newPrincipal, NEW_INTEREST_RATE, PAYMENT_INTERVAL));
        assertEq(delegateFee, expectedPoolDelegateFee);
        assertEq(treasuryFee, expectedTreasuryFee);

        uint256 payment = interest + delegateFee + treasuryFee;
        _makeNextPayment(payment);

        // Check loan, pool delegate, and treasury have received the fees.
        assertEq(USDC.balanceOf(address(LOAN)), interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), poolDelegateBalanceAfterRefinance + delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE + treasuryFee);

        // Make the remaining payments.
        _makeNextPayment(payment);
        _closeLoan(newPrincipal + payment);

        // Check loan is cleaned up.
        assertEq(LOAN.principal(),         0);
        assertEq(LOAN.endingPrincipal(),   0);
        assertEq(LOAN.interestRate(),      0);
        assertEq(LOAN.paymentsRemaining(), 0);
        assertEq(LOAN.paymentInterval(),   0);
        assertEq(LOAN.delegateFee(),       0);
        assertEq(LOAN.treasuryFee(),       0);

        // Check loan, pool delegate, and treasury have received all of the funds.
        assertEq(USDC.balanceOf(address(LOAN)), newPrincipal + 3 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), poolDelegateBalanceAfterRefinance + 3 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE + 3 * treasuryFee);
    }

    function test_refinance_afterUpgrade_samePrincipal() external {
        // Assert the starting conditions of the loan.
        assertEq(LOAN.principal(),         STARTING_PRINCIPAL);
        assertEq(LOAN.endingPrincipal(),   STARTING_PRINCIPAL);
        assertEq(LOAN.interestRate(),      STARTING_INTEREST_RATE);
        assertEq(LOAN.paymentsRemaining(), STARTING_PAYMENTS_REMAINING);
        assertEq(LOAN.paymentInterval(),   PAYMENT_INTERVAL);

        // Calculate expected payment before refinance.
        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check only interest will be paid.
        assertEq(principal,   0);
        assertEq(interest,    _calculateInterestPayment(STARTING_PRINCIPAL, STARTING_INTEREST_RATE, PAYMENT_INTERVAL));
        assertEq(delegateFee, 0);
        assertEq(treasuryFee, 0);

        _makeNextPayment(interest);

        // Check interest was received by the loan, and nothing was received by the pool delegate or treasury.
        assertEq(USDC.balanceOf(address(LOAN)), LOAN_STARTING_BALANCE + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE);

        uint256 deadline = block.timestamp + PROPOSAL_DURATION;
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      NEW_INTEREST_RATE);
        calls[1] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, NEW_PAYMENTS_REMAINING);

        assertEq(LOAN.refinanceCommitment(), 0);

        _proposeNewTerms(deadline, calls);

        assertEq(LOAN.refinanceCommitment(), keccak256(abi.encode(REFINANCER, deadline, calls)));

        // Accept the new terms before the deadline expires.
        vm.warp(block.timestamp + PROPOSAL_DURATION / 2);
        _acceptNewTerms(deadline, calls, 0);

        assertEq(LOAN.refinanceCommitment(), 0);

        // Cache pool delegate balance after the refinance.
        uint256 poolDelegateBalanceAfterRefinance = USDC.balanceOf(POOL_DELEGATE);

        // Calculate expected establishment fees.
        uint256 expectedPoolDelegateFee = _calculateEstablishmentFee(STARTING_PRINCIPAL, 33, PAYMENT_INTERVAL);
        uint256 expectedTreasuryFee     = _calculateEstablishmentFee(STARTING_PRINCIPAL, 66, PAYMENT_INTERVAL);

        // Check loan state has been updated correctly.
        assertEq(LOAN.principal(),         STARTING_PRINCIPAL);
        assertEq(LOAN.endingPrincipal(),   STARTING_PRINCIPAL);
        assertEq(LOAN.interestRate(),      NEW_INTEREST_RATE);
        assertEq(LOAN.paymentsRemaining(), NEW_PAYMENTS_REMAINING);
        assertEq(LOAN.paymentInterval(),   PAYMENT_INTERVAL);
        assertEq(LOAN.delegateFee(),       expectedPoolDelegateFee);
        assertEq(LOAN.treasuryFee(),       expectedTreasuryFee);

        // Calculate the interest payment using the new terms of the loan, adding the establishment fees on top.
        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check interest and establishment fees have been defined correctly.
        assertEq(principal,   0);
        assertEq(interest,    _calculateInterestPayment(STARTING_PRINCIPAL, NEW_INTEREST_RATE, PAYMENT_INTERVAL));
        assertEq(delegateFee, expectedPoolDelegateFee);
        assertEq(treasuryFee, expectedTreasuryFee);

        uint256 payment = interest + delegateFee + treasuryFee;
        _makeNextPayment(payment);

        // Check loan, pool delegate, and treasury have received the fees.
        assertEq(USDC.balanceOf(address(LOAN)), interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), poolDelegateBalanceAfterRefinance + delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE + treasuryFee);

        // Make the remaining payments.
        _makeNextPayment(payment);
        _closeLoan(STARTING_PRINCIPAL + payment);

        // Check loan is cleaned up.
        assertEq(LOAN.principal(),         0);
        assertEq(LOAN.endingPrincipal(),   0);
        assertEq(LOAN.interestRate(),      0);
        assertEq(LOAN.paymentsRemaining(), 0);
        assertEq(LOAN.paymentInterval(),   0);
        assertEq(LOAN.delegateFee(),       0);
        assertEq(LOAN.treasuryFee(),       0);

        // Check loan, pool delegate, and treasury have received all of the funds.
        assertEq(USDC.balanceOf(address(LOAN)), STARTING_PRINCIPAL + 3 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), poolDelegateBalanceAfterRefinance + 3 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE + 3 * treasuryFee);
    }

    function test_refinance_afterUpgrade_principalDecrease() external {
        // Assert the starting conditions of the loan.
        assertEq(LOAN.principal(),         STARTING_PRINCIPAL);
        assertEq(LOAN.endingPrincipal(),   STARTING_PRINCIPAL);
        assertEq(LOAN.interestRate(),      STARTING_INTEREST_RATE);
        assertEq(LOAN.paymentsRemaining(), STARTING_PAYMENTS_REMAINING);
        assertEq(LOAN.paymentInterval(),   PAYMENT_INTERVAL);

        // Calculate expected payment before refinance.
        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check only interest will be paid.
        assertEq(principal,   0);
        assertEq(interest,    _calculateInterestPayment(STARTING_PRINCIPAL, STARTING_INTEREST_RATE, PAYMENT_INTERVAL));
        assertEq(delegateFee, 0);
        assertEq(treasuryFee, 0);

        _makeNextPayment(interest);

        // Check interest was received by the loan, and nothing was received by the pool delegate or treasury.
        assertEq(USDC.balanceOf(address(LOAN)), LOAN_STARTING_BALANCE + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE);

        uint256 deadline = block.timestamp + PROPOSAL_DURATION;
        uint256 newPrincipal = STARTING_PRINCIPAL - PRINCIPAL_DECREASE;

        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSelector(IRefinancer.setEndingPrincipal.selector,   newPrincipal);
        calls[1] = abi.encodeWithSelector(IRefinancer.decreasePrincipal.selector,    PRINCIPAL_DECREASE);
        calls[2] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      NEW_INTEREST_RATE);
        calls[3] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, NEW_PAYMENTS_REMAINING);

        assertEq(LOAN.refinanceCommitment(), 0);

        // Propose the new terms and return the decresed principal.
        _proposeNewTerms(deadline, calls);
        _returnFunds(PRINCIPAL_DECREASE);

        assertEq(LOAN.refinanceCommitment(), keccak256(abi.encode(REFINANCER, deadline, calls)));

        // Accept the new terms before the deadline expires.
        vm.warp(block.timestamp + PROPOSAL_DURATION / 2);
        _acceptNewTerms(deadline, calls, 0);

        assertEq(LOAN.refinanceCommitment(), 0);

        // Cache pool delegate balance after the refinance.
        uint256 poolDelegateBalanceAfterRefinance = USDC.balanceOf(POOL_DELEGATE);

        // Calculate expected establishment fees.
        uint256 expectedPoolDelegateFee = _calculateEstablishmentFee(newPrincipal, 33, PAYMENT_INTERVAL);
        uint256 expectedTreasuryFee     = _calculateEstablishmentFee(newPrincipal, 66, PAYMENT_INTERVAL);

        // Check loan state has been updated correctly.
        assertEq(LOAN.principal(),         newPrincipal);
        assertEq(LOAN.endingPrincipal(),   newPrincipal);
        assertEq(LOAN.interestRate(),      NEW_INTEREST_RATE);
        assertEq(LOAN.paymentsRemaining(), NEW_PAYMENTS_REMAINING);
        assertEq(LOAN.paymentInterval(),   PAYMENT_INTERVAL);
        assertEq(LOAN.delegateFee(),       expectedPoolDelegateFee);
        assertEq(LOAN.treasuryFee(),       expectedTreasuryFee);

        // Calculate the interest payment using the new terms of the loan, adding the establishment fees on top.
        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check interest and establishment fees have been defined correctly.
        assertEq(principal,   0);
        assertEq(interest,    _calculateInterestPayment(newPrincipal, NEW_INTEREST_RATE, PAYMENT_INTERVAL));
        assertEq(delegateFee, expectedPoolDelegateFee);
        assertEq(treasuryFee, expectedTreasuryFee);

        uint256 payment = interest + delegateFee + treasuryFee;
        _makeNextPayment(payment);

        // Check loan, pool delegate, and treasury have received the fees.
        assertEq(USDC.balanceOf(address(LOAN)), interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), poolDelegateBalanceAfterRefinance + delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE + treasuryFee);

        // Make the remaining payments.
        _makeNextPayment(payment);
        _closeLoan(newPrincipal + payment);

        // Check loan is cleaned up.
        assertEq(LOAN.principal(),         0);
        assertEq(LOAN.endingPrincipal(),   0);
        assertEq(LOAN.interestRate(),      0);
        assertEq(LOAN.paymentsRemaining(), 0);
        assertEq(LOAN.paymentInterval(),   0);
        assertEq(LOAN.delegateFee(),       0);
        assertEq(LOAN.treasuryFee(),       0);

        // Check loan, pool delegate, and treasury have received all of the funds.
        assertEq(USDC.balanceOf(address(LOAN)), newPrincipal + 3 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), poolDelegateBalanceAfterRefinance + 3 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE + 3 * treasuryFee);
    }

    /*************************/
    /*** Uitlity Functions ***/
    /*************************/

    function _calculateInterestPayment(uint256 principal_, uint256 interestRate_, uint256 interval_) internal pure returns (uint256 payment_) {
        return principal_ * interestRate_ * interval_ / 365 days / 1e18;
    }

    function _calculateEstablishmentFee(uint256 principal_, uint256 feeRate_, uint256 interval_) internal pure returns (uint256 fee_) {
        return principal_ * feeRate_ * interval_ / 365 days / 100_00;
    }

    function _drawdownFunds() internal {
        vm.startPrank(BORROWER);
        LOAN.drawdownFunds(LOAN.drawableFunds(), BORROWER);
        vm.stopPrank();
    }

    function _returnFunds(uint256 amount_) internal {
        vm.startPrank(BORROWER);

        _mintAndApprove(BORROWER, amount_);
        LOAN.returnFunds(amount_);

        vm.stopPrank();
    }

    function _makeNextPayment(uint256 payment_) internal {
        vm.startPrank(BORROWER);

        _mintAndApprove(BORROWER, payment_);
        vm.warp(LOAN.nextPaymentDueDate());
        LOAN.makePayment(payment_);

        vm.stopPrank();
    }

    function _closeLoan(uint256 payment_) internal {
        vm.startPrank(BORROWER);

        _mintAndApprove(BORROWER, payment_);
        vm.warp(LOAN.nextPaymentDueDate());
        LOAN.closeLoan(payment_);

        vm.stopPrank();
    }

    function _proposeNewTerms(uint256 deadline_, bytes[] memory calls_) internal {
        vm.prank(BORROWER);
        LOAN.proposeNewTerms(REFINANCER, deadline_, calls_);
    }

    function _acceptNewTerms(uint256 deadline_, bytes[] memory calls_, uint256 principalIncrease_) internal {
        vm.startPrank(POOL_DELEGATE);

        POOL.fundLoan(address(LOAN), address(DEBT_LOCKER_FACTORY), principalIncrease_);
        POOL.claim(address(LOAN), address(DEBT_LOCKER_FACTORY));
        DEBT_LOCKER.acceptNewTerms(REFINANCER, deadline_, calls_, principalIncrease_);

        vm.stopPrank();
    }

    function _mintAndApprove(address account_, uint256 amount_) internal {
        erc20_mint(address(USDC), 9, account_, amount_);
        USDC.approve(address(LOAN), amount_);
    }

}

// TODO: test refinance before upgrade (propose and accept before upgrade)
// TODO: test refinance during upgrade (propose before upgrade, accept after upgrade)
