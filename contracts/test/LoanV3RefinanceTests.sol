// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../modules/contract-test-utils/contracts/test.sol";

import { IDebtLocker }        from "../../modules/debt-locker/contracts/interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "../../modules/debt-locker/contracts/interfaces/IDebtLockerFactory.sol";
import { IMapleLoan }         from "../../modules/loan/contracts/interfaces/IMapleLoan.sol";
import { IMapleLoanFactory }  from "../../modules/loan/contracts/interfaces/IMapleLoanFactory.sol";
import { IRefinancer }        from "../../modules/loan/contracts/interfaces/IRefinancer.sol";

import { DebtLocker }           from "../../modules/debt-locker/contracts/DebtLocker.sol";
import { MapleLoan }            from "../../modules/loan/contracts/MapleLoan.sol";
import { MapleLoanInitializer } from "../../modules/loan/contracts/MapleLoanInitializer.sol";

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

    // Starting balances of relevant contracts.
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

    uint256 internal _start;

    function setUp() external {
        // Warp to the time the loan was funded.
        _start = LOAN.nextPaymentDueDate() - 30 days;

        vm.warp(_start);

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

        // // Upgrade the DebtLocker to the new version.
        // vm.prank(POOL_DELEGATE);
        // DEBT_LOCKER.upgrade(300, "");

        // // Upgrade the Loan to the new version.
        // vm.prank(BORROWER);
        // LOAN.upgrade(300, "");
    }

    // Based on the following spreadheet: https://docs.google.com/spreadsheets/d/1v3ALXotiJNXpqfxENjeoocguFFeuDyd_jfUs3khihPc/edit#gid=945746867
    function test_refinance_afterUpgrade_principalIncrease() external {
        // Assert the starting conditions of the loan.
        assertEq(LOAN.principal(),         10_000_000_000000);
        assertEq(LOAN.endingPrincipal(),   10_000_000_000000);
        assertEq(LOAN.interestRate(),      0.0975e18);
        assertEq(LOAN.paymentsRemaining(), 6);
        assertEq(LOAN.paymentInterval(),   30 days);

        // Borrowers draws down all funds from the loan.
        _drawdownAllFunds();

        ( uint256 principal, uint256 interest ) = LOAN.getNextPaymentBreakdown();

        // Check only interest will be paid.
        assertEq(principal,   0);
        assertEq(interest,    80_136_986301);  // 10,000,000 * 9.75% * (30 / 365)
        assertEq(delegateFee, 0);
        assertEq(treasuryFee, 0);

        vm.warp(_start + 30 days);

        // Borrower makes the first payment.
        _makePayment(interest);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE + 0);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 0);

        vm.warp(_start + 60 days);

        // TODO: Another getNextPaymentBreakdown?

        // Borrower makes another payment.
        _makePayment(interest);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 2 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE + 0);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 0);

        vm.warp(_start + 75 days);

        // Define the new terms of the loan.
        uint256 deadline = block.timestamp + 10 days;
        bytes[] memory calls = new bytes[](4);

        calls[0] = abi.encodeWithSelector(IRefinancer.increasePrincipal.selector,    2_500_000_000000);   // Increase the principal by 2.5 million.
        calls[1] = abi.encodeWithSelector(IRefinancer.setEndingPrincipal.selector,   12_500_000_000000);  // Adjust the ending principal to be equal to the principal.
        calls[2] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      0.1e18);             // Set the interest rate to 10%.
        calls[3] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, 3);                  // Set duration of loan to 90 days (3 payments).

        assertEq(LOAN.refinanceCommitment(), 0);

        // Borrowr upgrades the Loan to V3 through the UI before proposeNewTerms
        vm.prank(BORROWER);
        LOAN.upgrade(300, "");

        // Borrower proposes new terms.
        _proposeNewTerms(deadline, calls);

        assertEq(LOAN.refinanceCommitment(), keccak256(abi.encode(REFINANCER, deadline, calls)));

        vm.warp(_start + 80 days);

        // Pool Delegate upgrades the DebtLocker to V3 through the UI before acceptNewTerms
        vm.prank(POOL_DELEGATE);
        DEBT_LOCKER.upgrade(300, "");

        // Pool delegate funds the loan and accepts the proposal after a time delay.
        _fundLoan(2_500_000_000000);
        _acceptNewTerms(deadline, calls, 2_500_000_000000);

        uint256 newPoolDelegateStartingBalance = USDC.balanceOf(POOL_DELEGATE);

        // Check loan state was updated correctly after the refinance.
        assertEq(LOAN.principal(),           12_500_000_000000);
        assertEq(LOAN.endingPrincipal(),     12_500_000_000000);
        assertEq(LOAN.interestRate(),        0.1e18);
        assertEq(LOAN.paymentsRemaining(),   3);
        assertEq(LOAN.paymentInterval(),     30 days);
        assertEq(LOAN.refinanceInterest(),   1);
        assertEq(LOAN.delegateFee(),         3_390_410958);  // 12,500,000 * 0.33% * (30 / 365)
        assertEq(LOAN.treasuryFee(),         6_780_821917);  // 12,500,000 * 0.66% * (30 / 365)
        assertEq(LOAN.refinanceCommitment(), 0);

        // Borrowers draws down all funds from the loan.
        _drawdownAllFunds();

        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        assertEq(principal,   0);
        assertEq(interest,    102_739_726027);  // 12,500,000 * 10% * (30 / 365)
        assertEq(delegateFee, 3_390_410958);
        assertEq(treasuryFee, 6_780_821917);

        vm.warp(_start + 90 days); // TODO: The due date should be recalculated here.

        // Make the first payment on the new loan.
        _makePayment(interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + treasuryFee);

        vm.warp(_start + 120 days);

        // Make the second payment on the new loan.
        _makePayment(interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 2 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + 2 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 2 * treasuryFee);

        vm.warp(_start + 150 days);

        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        assertEq(principal,   12_500_000_000000);
        assertEq(interest,    102_739_726027);
        assertEq(delegateFee, 3_390_410958);
        assertEq(treasuryFee, 6_780_821917);

        // Make the last payment on the new loan, including the principal this time.
        _makePayment(principal + interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 3 * interest + principal);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + 3 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 3 * treasuryFee);

        // Check loan is cleaned up.
        assertEq(LOAN.principal(),         0);
        assertEq(LOAN.endingPrincipal(),   0);
        assertEq(LOAN.interestRate(),      0);
        assertEq(LOAN.paymentsRemaining(), 0);
        assertEq(LOAN.paymentInterval(),   0);
        assertEq(LOAN.delegateFee(),       0);
        assertEq(LOAN.treasuryFee(),       0);
    }

    function test_refinance_afterUpgrade_samePrincipal() external {
       // Assert the starting conditions of the loan.
        assertEq(LOAN.principal(),         10_000_000_000000);
        assertEq(LOAN.endingPrincipal(),   10_000_000_000000);
        assertEq(LOAN.interestRate(),      0.0975e18);
        assertEq(LOAN.paymentsRemaining(), 6);
        assertEq(LOAN.paymentInterval(),   30 days);

        // Borrowers draws down all funds from the loan.
        _drawdownAllFunds();

        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check only interest will be paid.
        assertEq(principal,   0);
        assertEq(interest,    80_136_986301);  // 10,000,000 * 9.75% * (30 / 365)
        assertEq(delegateFee, 0);
        assertEq(treasuryFee, 0);

        vm.warp(_start + 30 days);

        // Borrower makes the first payment.
        _makePayment(interest);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE + 0);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 0);

        vm.warp(_start + 60 days);

        // Borrower makes another payment.
        _makePayment(interest);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 2 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE + 0);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 0);

        vm.warp(_start + 80 days);

        // Define the new terms of the loan.
        uint256 deadline = block.timestamp + 10 days;
        bytes[] memory calls = new bytes[](2);

        calls[0] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      0.1e18);  // Set the interest rate to 10%.
        calls[1] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, 3);       // Set duration of loan to 90 days (3 payments).

        assertEq(LOAN.refinanceCommitment(), 0);

        // Borrower proposes new terms.
        _proposeNewTerms(deadline, calls);

        assertEq(LOAN.refinanceCommitment(), keccak256(abi.encode(REFINANCER, deadline, calls)));

        vm.warp(_start + 85 days);

        // Pool delegate accepts the proposal after a time delay.
        _acceptNewTerms(deadline, calls, 0);

        uint256 newPoolDelegateStartingBalance = USDC.balanceOf(POOL_DELEGATE);

        // Check loan state was updated correctly after the refinance.
        assertEq(LOAN.principal(),           10_000_000_000000);
        assertEq(LOAN.endingPrincipal(),     10_000_000_000000);
        assertEq(LOAN.interestRate(),        0.1e18);
        assertEq(LOAN.paymentsRemaining(),   3);
        assertEq(LOAN.paymentInterval(),     30 days);
        assertEq(LOAN.delegateFee(),         2_712_328767);  // 10,000,000 * 0.33% * (30 / 365)
        assertEq(LOAN.treasuryFee(),         5_424_657534);  // 10,000,000 * 0.66% * (30 / 365)
        assertEq(LOAN.refinanceCommitment(), 0);

        // Borrowers draws down all funds from the loan.
        _drawdownAllFunds();

        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        assertEq(principal,   0);
        assertEq(interest,    82_191_780821);  // 10,000,000 * 10% * (30 / 365)
        assertEq(delegateFee, 2_712_328767);
        assertEq(treasuryFee, 5_424_657534);

        vm.warp(_start + 90 days); // TODO: The due date should be recalculated here.

        // Make the first payment on the new loan.
        _makePayment(interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + treasuryFee);

        vm.warp(_start + 120 days);

        // Make the second payment on the new loan.
        _makePayment(interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 2 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + 2 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 2 * treasuryFee);

        vm.warp(_start + 150 days);

        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        assertEq(principal,   10_000_000_000000);
        assertEq(interest,    82_191_780821);
        assertEq(delegateFee, 2_712_328767);
        assertEq(treasuryFee, 5_424_657534);

        // Make the last payment on the new loan, including the principal this time.
        _makePayment(principal + interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 3 * interest + principal);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + 3 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 3 * treasuryFee);

        // Check loan is cleaned up.
        assertEq(LOAN.principal(),         0);
        assertEq(LOAN.endingPrincipal(),   0);
        assertEq(LOAN.interestRate(),      0);
        assertEq(LOAN.paymentsRemaining(), 0);
        assertEq(LOAN.paymentInterval(),   0);
        assertEq(LOAN.delegateFee(),       0);
        assertEq(LOAN.treasuryFee(),       0);
    }

    function test_refinance_afterUpgrade_principalDecrease() external {
        // Assert the starting conditions of the loan.
        assertEq(LOAN.principal(),         10_000_000_000000);
        assertEq(LOAN.endingPrincipal(),   10_000_000_000000);
        assertEq(LOAN.interestRate(),      0.0975e18);
        assertEq(LOAN.paymentsRemaining(), 6);
        assertEq(LOAN.paymentInterval(),   30 days);

        // Borrowers draws down all funds from the loan.
        _drawdownAllFunds();

        ( uint256 principal, uint256 interest, uint256 delegateFee, uint256 treasuryFee ) = LOAN.getNextPaymentBreakdown();

        // Check only interest will be paid.
        assertEq(principal,   0);
        assertEq(interest,    80_136_986301);  // 10,000,000 * 9.75% * (30 / 365)
        assertEq(delegateFee, 0);
        assertEq(treasuryFee, 0);

        vm.warp(_start + 30 days);

        // Borrower makes the first payment.
        _makePayment(interest);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE + 0);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 0);

        vm.warp(_start + 60 days);

        // Borrower makes another payment.
        _makePayment(interest);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 2 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), POOL_DELEGATE_STARTING_BALANCE + 0);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 0);

        vm.warp(_start + 80 days);

        // Define the new terms of the loan.
        uint256 deadline = block.timestamp + 10 days;
        bytes[] memory calls = new bytes[](4);

        calls[0] = abi.encodeWithSelector(IRefinancer.setEndingPrincipal.selector,   7_500_000_000000);  // Adjust the ending principal to be equal to the principal.
        calls[1] = abi.encodeWithSelector(IRefinancer.decreasePrincipal.selector,    2_500_000_000000);  // Increase the principal by 2.5 million.
        calls[2] = abi.encodeWithSelector(IRefinancer.setInterestRate.selector,      0.1e18);            // Set the interest rate to 10%.
        calls[3] = abi.encodeWithSelector(IRefinancer.setPaymentsRemaining.selector, 3);                 // Set duration of loan to 90 days (3 payments).

        assertEq(LOAN.refinanceCommitment(), 0);

        // Borrower proposes new terms.
        _proposeNewTerms(deadline, calls);
        _returnFunds(2_500_000_000000);

        assertEq(LOAN.refinanceCommitment(), keccak256(abi.encode(REFINANCER, deadline, calls)));

        vm.warp(_start + 85 days);

        // Pool delegate funds the loan and accepts the proposal after a time delay.
        _acceptNewTerms(deadline, calls, 0);

        uint256 newPoolDelegateStartingBalance = USDC.balanceOf(POOL_DELEGATE);

        // Check loan state was updated correctly after the refinance.
        assertEq(LOAN.principal(),           7_500_000_000000);
        assertEq(LOAN.endingPrincipal(),     7_500_000_000000);
        assertEq(LOAN.interestRate(),        0.1e18);
        assertEq(LOAN.paymentsRemaining(),   3);
        assertEq(LOAN.paymentInterval(),     30 days);
        assertEq(LOAN.delegateFee(),         2_034_246575);  // 7,500,000 * 0.33% * (30 / 365)
        assertEq(LOAN.treasuryFee(),         4_068_493150);  // 7,500,000 * 0.66% * (30 / 365)
        assertEq(LOAN.refinanceCommitment(), 0);

        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        assertEq(principal,   0);
        assertEq(interest,    61_643_835616);  // 7,500,000 * 10% * (30 / 365)
        assertEq(delegateFee, 2_034_246575);
        assertEq(treasuryFee, 4_068_493150);

        vm.warp(_start + 90 days); // TODO: The due date should be recalculated here.

        // Make the first payment on the new loan.
        _makePayment(interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + treasuryFee);

        vm.warp(_start + 120 days);

        // Make the second payment on the new loan.
        _makePayment(interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 2 * interest);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + 2 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 2 * treasuryFee);

        vm.warp(_start + 150 days);

        ( principal, interest, delegateFee, treasuryFee ) = LOAN.getNextPaymentBreakdown();

        assertEq(principal,   7_500_000_000000);
        assertEq(interest,    61_643_835616);
        assertEq(delegateFee, 2_034_246575);
        assertEq(treasuryFee, 4_068_493150);

        // Make the last payment on the new loan, including the principal this time.
        _makePayment(principal + interest + delegateFee + treasuryFee);

        assertEq(USDC.balanceOf(address(LOAN)), 0                              + 3 * interest + principal);
        assertEq(USDC.balanceOf(POOL_DELEGATE), newPoolDelegateStartingBalance + 3 * delegateFee);
        assertEq(USDC.balanceOf(TREASURY),      TREASURY_STARTING_BALANCE      + 3 * treasuryFee);

        // Check loan is cleaned up.
        assertEq(LOAN.principal(),         0);
        assertEq(LOAN.endingPrincipal(),   0);
        assertEq(LOAN.interestRate(),      0);
        assertEq(LOAN.paymentsRemaining(), 0);
        assertEq(LOAN.paymentInterval(),   0);
        assertEq(LOAN.delegateFee(),       0);
        assertEq(LOAN.treasuryFee(),       0);
    }

    /*************************/
    /*** Uitlity Functions ***/
    /*************************/

    function _acceptNewTerms(uint256 deadline_, bytes[] memory calls_, uint256 principalIncrease_) internal {
        vm.startPrank(POOL_DELEGATE);

        // Claim first in order to prevent `acceptNewTerms` from reverting.
        POOL.claim(address(LOAN), address(DEBT_LOCKER_FACTORY));
        DEBT_LOCKER.acceptNewTerms(REFINANCER, deadline_, calls_, principalIncrease_);

        vm.stopPrank();
    }

    function _drawdownAllFunds() internal {
        uint256 amount = LOAN.drawableFunds();

        vm.prank(BORROWER);
        LOAN.drawdownFunds(amount, BORROWER);
    }

    function _fundLoan(uint256 principalIncrease_) internal {
        vm.prank(POOL_DELEGATE);
        POOL.fundLoan(address(LOAN), address(DEBT_LOCKER_FACTORY), principalIncrease_);
    }

    function _makePayment(uint256 payment_) internal {
        vm.startPrank(BORROWER);

        _mintAndApprove(BORROWER, payment_);
        LOAN.makePayment(payment_);

        vm.stopPrank();
    }

    function _mintAndApprove(address account_, uint256 amount_) internal {
        erc20_mint(address(USDC), 9, account_, amount_);
        USDC.approve(address(LOAN), amount_);
    }

    function _proposeNewTerms(uint256 deadline_, bytes[] memory calls_) internal {
        vm.prank(BORROWER);
        LOAN.proposeNewTerms(REFINANCER, deadline_, calls_);
    }

    function _returnFunds(uint256 amount_) internal {
        vm.startPrank(BORROWER);

        _mintAndApprove(BORROWER, amount_);
        LOAN.returnFunds(amount_);

        vm.stopPrank();
    }

}

// TODO: test refinance before upgrade (propose and accept before upgrade)
// TODO: test refinance during upgrade (propose before upgrade, accept after upgrade)
