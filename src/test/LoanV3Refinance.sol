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
    address internal constant GLOBALS                  = address(0xC234c62c8C09687DFf0d9047e40042cd166F3600);
    address internal constant GOVERNOR                 = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address internal constant LOAN                     = address(0x1597bc9C167bA318Da52EE94FDb0efAf84837BBF);
    address internal constant LOAN_FACTORY             = address(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);
    address internal constant LOAN_IMPLEMENTATION_V200 = address(0x97940C7aea99998da4c56922211ce012E7765395);
    address internal constant POOL                     = address(0xFeBd6F15Df3B73DC4307B1d7E65D46413e710C27);
    address internal constant POOL_DELEGATE            = address(0xA6cCb9483E3E7a737E3a4F5B72a1Ce51838ba122);
    address internal constant TREASURY                 = address(0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19);
    address internal constant USDC                     = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address internal immutable LOAN_IMPLEMENTATION_V300 = address(new MapleLoan());
    address internal immutable LOAN_INITIALIZER_V300    = address(new MapleLoanInitializer());
    address internal immutable REFINANCER               = address(new Refinancer());

    function setUp() external {
        vm.startPrank(GOVERNOR);
        IMapleLoanFactory(LOAN_FACTORY).registerImplementation(300, LOAN_IMPLEMENTATION_V300, LOAN_INITIALIZER_V300);
        IMapleLoanFactory(LOAN_FACTORY).enableUpgradePath(200, 300, address(0));
        IMapleLoanFactory(LOAN_FACTORY).setDefaultVersion(300);
        vm.stopPrank();
    }

    function test_refinance_afterUpgrade() external {
        vm.startPrank(BORROWER);
        IMapleLoan(LOAN).upgrade(300, "");
    }

    function test_refinance_beforeUpgrade() external {
        // TODO
    }

    function test_refinance_duringUpgrade() external {
        // TODO
    }

    /*
    function test_refinance_afterUpgrade_samePrincipal() external {
        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V200);

        vm.startPrank(BORROWER);
        IMapleLoan(LOAN).upgrade(300, "");

        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V300);

        uint256 treasuryStartingBalance     = IUSDCLike(USDC).balanceOf(TREASURY);
        uint256 poolDelegateStartingBalance = IUSDCLike(USDC).balanceOf(POOL_DELEGATE);
        uint256 poolDelegateFee             = 12_205_479452;
        uint256 treasuryFee                 = 24_410_958904;

        assertEq(poolDelegateFee, uint256(7_500_000_000000) * 180 days * 33 / 365 days / 10_000);
        assertEq(treasuryFee,     uint256(7_500_000_000000) * 180 days * 66 / 365 days / 10_000);

        // Return enough USDC to the LOAN to satisfy investor fee (33) and treasury fee (66) on 7500000.000000 principal refinance,
        // with 2592000 payment interval and 6 payments remaining, which is 12205.479452 and 24410.958904 respectively.
        erc20_mint(USDC, 9, BORROWER, poolDelegateFee + treasuryFee);
        IUSDCLike(USDC).approve(LOAN, poolDelegateFee + treasuryFee);
        IMapleLoan(LOAN).returnFunds(poolDelegateFee + treasuryFee);

        assertEq(IMapleLoan(LOAN).drawableFunds(), poolDelegateFee + treasuryFee);

        // Propose refinance to set interest rate.
        uint256 deadline = block.timestamp + 10 days;
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(Refinancer.setInterestRate.selector, 0.15e18);

        IMapleLoan(LOAN).proposeNewTerms(REFINANCER, deadline, calls);

        // Accept refinance as the POOL delegate
        vm.stopPrank();
        vm.startPrank(POOL_DELEGATE);
        IDebtLockerLike(DEBT_LOCKER).acceptNewTerms(REFINANCER, calls, 0);

        // Check that the interest rate wa updated and that fees in USDC were paid.
        assertEq(IMapleLoan(LOAN).interestRate(),  0.15e18);
        assertEq(IMapleLoan(LOAN).drawableFunds(), 0);

        assertEq(IUSDCLike(USDC).balanceOf(POOL_DELEGATE), poolDelegateStartingBalance + poolDelegateFee);
        assertEq(IUSDCLike(USDC).balanceOf(TREASURY),      treasuryStartingBalance + treasuryFee);
    }

    function test_refinance_afterUpgrade_increasedPrincipal() external {
        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V200);

        vm.startPrank(BORROWER);
        IMapleLoan(LOAN).upgrade(300, "");

        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V300);

        uint256 principalIncreaseAmount = 2_500_000_000000;

        // Propose refinance to set interest rate.
        // NOTE: Establishment fees do not have to be paid upfront since they will be taken out of increased principal
        uint256 deadline = block.timestamp + 10 days;
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(Refinancer.increasePrincipal.selector, principalIncreaseAmount);

        IMapleLoan(LOAN).proposeNewTerms(REFINANCER, deadline, calls);

        uint256 treasuryStartingBalance     = IUSDCLike(USDC).balanceOf(TREASURY);
        uint256 poolDelegateStartingBalance = IUSDCLike(USDC).balanceOf(POOL_DELEGATE);
        uint256 poolDelegateFee             = 16_273_972602;
        uint256 treasuryFee                 = 32_547_945205;

        assertEq(poolDelegateFee, uint256(10_000_000_000000) * 180 days * 33 / 365 days / 10_000);
        assertEq(treasuryFee,     uint256(10_000_000_000000) * 180 days * 66 / 365 days / 10_000);

        // Change to Pool Delegate address.
        vm.stopPrank();
        vm.startPrank(POOL_DELEGATE);

        uint256 poolCash = IUSDCLike(USDC).balanceOf(IPoolLike(POOL).liquidityLocker());

        // Fund the LOAN for the increase amount.
        IPoolLike(POOL).fundLoan(LOAN, DEBT_LOCKER_FACTORY, principalIncreaseAmount);

        assertEq(IUSDCLike(USDC).balanceOf(IPoolLike(POOL).liquidityLocker()), poolCash - principalIncreaseAmount);
        assertEq(IUSDCLike(USDC).balanceOf(DEBT_LOCKER),                       principalIncreaseAmount);
        assertEq(IUSDCLike(USDC).balanceOf(LOAN),                              0);

        // Accept terms of the refinance, using re-routed funds from refinance.
        IDebtLockerLike(DEBT_LOCKER).acceptNewTerms(REFINANCER, calls, principalIncreaseAmount);

        assertEq(IUSDCLike(USDC).balanceOf(DEBT_LOCKER), 0);
        assertEq(IUSDCLike(USDC).balanceOf(LOAN),        principalIncreaseAmount - (poolDelegateFee + treasuryFee));

        // Check that the interest rate was updated and that fees in USDC were paid.
        assertEq(IMapleLoan(LOAN).principal(),          10_000_000_000000);
        assertEq(IMapleLoan(LOAN).principalRequested(), 10_000_000_000000);
        assertEq(IMapleLoan(LOAN).drawableFunds(),      principalIncreaseAmount - (poolDelegateFee + treasuryFee));
        assertEq(IMapleLoan(LOAN).drawableFunds(),      2_451_178_082193);

        assertEq(IUSDCLike(USDC).balanceOf(POOL_DELEGATE), poolDelegateStartingBalance + poolDelegateFee);
        assertEq(IUSDCLike(USDC).balanceOf(POOL_DELEGATE), 43_707_374596);
        assertEq(IUSDCLike(USDC).balanceOf(TREASURY),      treasuryStartingBalance + treasuryFee);
        assertEq(IUSDCLike(USDC).balanceOf(TREASURY),      600_431_496595);
    }

    function test_refinance_afterUpgrade_increasedPrincipal_reducedTerm() external {
        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V200);

        vm.startPrank(BORROWER);
        IMapleLoan(LOAN).upgrade(300, "");

        assertEq(IMapleLoan(LOAN).implementation(), LOAN_IMPLEMENTATION_V300);

        uint256 principalIncreaseAmount = 2_500_000_000000;

        // Propose refinance to set interest rate.
        // NOTE: Establishment fees do not have to be paid upfront since they will be taken out of increased principal.
        uint256 deadline = block.timestamp + 10 days;
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(Refinancer.increasePrincipal.selector, principalIncreaseAmount);
        calls[1] = abi.encodeWithSelector(Refinancer.setPaymentsRemaining.selector, 3);

        IMapleLoan(LOAN).proposeNewTerms(REFINANCER, deadline, calls);

        uint256 treasuryStartingBalance     = IUSDCLike(USDC).balanceOf(TREASURY);
        uint256 poolDelegateStartingBalance = IUSDCLike(USDC).balanceOf(POOL_DELEGATE);
        uint256 poolDelegateFee             = 8_136_986301;
        uint256 treasuryFee                 = 16_273_972602;

        assertEq(poolDelegateFee, uint256(10_000_000_000000) * 90 days * 33 / 365 days / 10_000);
        assertEq(treasuryFee,     uint256(10_000_000_000000) * 90 days * 66 / 365 days / 10_000);

        // Change to Pool Delegate address.
        vm.stopPrank();
        vm.startPrank(POOL_DELEGATE);

        uint256 poolCash = IUSDCLike(USDC).balanceOf(IPoolLike(POOL).liquidityLocker());

        // Fund the LOAN for the increase amount.
        IPoolLike(POOL).fundLoan(LOAN, DEBT_LOCKER_FACTORY, principalIncreaseAmount);

        assertEq(IUSDCLike(USDC).balanceOf(IPoolLike(POOL).liquidityLocker()), poolCash - principalIncreaseAmount);
        assertEq(IUSDCLike(USDC).balanceOf(DEBT_LOCKER),                       principalIncreaseAmount);
        assertEq(IUSDCLike(USDC).balanceOf(LOAN),                              0);

        // Accept terms of the refinance, using re-routed funds from refinance.
        IDebtLockerLike(DEBT_LOCKER).acceptNewTerms(REFINANCER, calls, principalIncreaseAmount);

        assertEq(IUSDCLike(USDC).balanceOf(DEBT_LOCKER), 0);
        assertEq(IUSDCLike(USDC).balanceOf(LOAN),        principalIncreaseAmount - (poolDelegateFee + treasuryFee));

        // Check that the interest rate wa updated and that fees in USDC were paid.
        assertEq(IMapleLoan(LOAN).principal(),          10_000_000_000000);
        assertEq(IMapleLoan(LOAN).principalRequested(), 10_000_000_000000);
        assertEq(IMapleLoan(LOAN).drawableFunds(),      principalIncreaseAmount - (poolDelegateFee + treasuryFee));
        assertEq(IMapleLoan(LOAN).drawableFunds(),      2_475_589_041097);

        assertEq(IUSDCLike(USDC).balanceOf(POOL_DELEGATE), poolDelegateStartingBalance + poolDelegateFee);
        assertEq(IUSDCLike(USDC).balanceOf(POOL_DELEGATE), 35_570_388295);
        assertEq(IUSDCLike(USDC).balanceOf(TREASURY),      treasuryStartingBalance + treasuryFee);
        assertEq(IUSDCLike(USDC).balanceOf(TREASURY),      584_157_523992);
    }
    */

}
