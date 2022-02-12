// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";

import { IMapleLoan }        from "../../lib/loan/contracts/interfaces/IMapleLoan.sol";
import { IMapleLoanFactory } from "../../lib/loan/contracts/interfaces/IMapleLoanFactory.sol";

import { MapleLoan }  from "../../lib/loan/contracts/MapleLoan.sol";
import { Refinancer } from "../../lib/loan/contracts/Refinancer.sol";

import { IDebtLockerLike, IPoolLike, IUSDCLike } from "../interfaces/Interfaces.sol";

contract LoanV2_UpgradeSimulation is TestUtils {

    address constant internal MAPLE_LOAN_IMPLEMENTATION_V200 = address(0x97940C7aea99998da4c56922211ce012E7765395);
    address constant internal MAPLE_LOAN_INITIALIZER         = address(0xCba99a6648450a7bE7f20B1C3258F74Adb662020);

    address constant internal BORROWER   = address(0xa8c42bBb0648511cC9004fbDCf0FA365088F862B);
    address constant internal GOVERNOR   = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address constant internal LENDER     = address(0xCba99a6648450a7bE7f20B1C3258F74Adb662020);

    IMapleLoanFactory constant internal factory = IMapleLoanFactory(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);
    IMapleLoan        constant internal loan    = IMapleLoan(0x7dF5A2238C62e4b7E05238Da1FBe4b6FbbE22770);

    address internal loanImplementationV210;

    // Loan storage variables (tracking in storage to avoid "stack too deep" errors)
    address internal borrower;
    address internal lender;
    address internal pendingBorrower;
    address internal pendingLender;
    address internal collateralAsset;
    address internal fundsAsset;

    uint256 internal gracePeriod;
    uint256 internal paymentInterval;
    uint256 internal interestRate;
    uint256 internal earlyFeeRate;
    uint256 internal lateFeeRate;
    uint256 internal lateInterestPremium;
    uint256 internal collateralRequired;
    uint256 internal principalRequested;
    uint256 internal endingPrincipal;
    uint256 internal drawableFunds;
    uint256 internal claimableFunds;
    uint256 internal collateral;
    uint256 internal nextPaymentDueDate;
    uint256 internal paymentsRemaining;
    uint256 internal principal;

    function setUp() external {
        // Deploy Loan v2.1.0 implementation
        loanImplementationV210 = address(new MapleLoan());

        // Configure loan in factory
        vm.startPrank(GOVERNOR);
        factory.registerImplementation(210, loanImplementationV210, MAPLE_LOAN_INITIALIZER);
        factory.enableUpgradePath(200, 210, address(0));
        factory.setDefaultVersion(210);
        vm.stopPrank();
    }

    function test_loanUpgrade_storageAssertions() external {

        /********************/
        /*** Before state ***/
        /********************/

        borrower        = loan.borrower();
        lender          = loan.lender();
        pendingBorrower = loan.pendingBorrower();
        pendingLender   = loan.pendingLender();

        collateralAsset = loan.collateralAsset();
        fundsAsset      = loan.fundsAsset();

        gracePeriod     = loan.gracePeriod();
        paymentInterval = loan.paymentInterval();

        interestRate        = loan.interestRate();
        earlyFeeRate        = loan.earlyFeeRate();
        lateFeeRate         = loan.lateFeeRate();
        lateInterestPremium = loan.lateInterestPremium();

        collateralRequired = loan.collateralRequired();
        principalRequested = loan.principalRequested();
        endingPrincipal    = loan.endingPrincipal();

        drawableFunds      = loan.drawableFunds();
        claimableFunds     = loan.claimableFunds();
        collateral         = loan.collateral();
        nextPaymentDueDate = loan.nextPaymentDueDate();
        paymentsRemaining  = loan.paymentsRemaining();
        principal          = loan.principal();

        /***********************/
        /*** Perform upgrade ***/
        /***********************/

        vm.expectRevert("ML:U:NOT_BORROWER");
        loan.upgrade(210, "");

        assertEq(loan.implementation(), MAPLE_LOAN_IMPLEMENTATION_V200);

        vm.prank(BORROWER);
        loan.upgrade(210, "");

        assertEq(loan.implementation(), loanImplementationV210);

        /*******************/
        /*** After state ***/
        /*******************/

        assertEq(loan.borrower(),        borrower);
        assertEq(loan.lender(),          lender);
        assertEq(loan.pendingBorrower(), pendingBorrower);
        assertEq(loan.pendingLender(),   pendingLender);

        assertEq(loan.collateralAsset(), collateralAsset);
        assertEq(loan.fundsAsset(),      fundsAsset);

        assertEq(loan.gracePeriod(),     gracePeriod);
        assertEq(loan.paymentInterval(), paymentInterval);

        assertEq(loan.interestRate(),        interestRate);
        assertEq(loan.earlyFeeRate(),        earlyFeeRate);
        assertEq(loan.lateFeeRate(),         lateFeeRate);
        assertEq(loan.lateInterestPremium(), lateInterestPremium);

        assertEq(loan.collateralRequired(), collateralRequired);
        assertEq(loan.principalRequested(), principalRequested);
        assertEq(loan.endingPrincipal(),    endingPrincipal);

        assertEq(loan.drawableFunds(),      drawableFunds);
        assertEq(loan.claimableFunds(),     claimableFunds);
        assertEq(loan.collateral(),         collateral);
        assertEq(loan.nextPaymentDueDate(), nextPaymentDueDate);
        assertEq(loan.paymentsRemaining(),  paymentsRemaining);
        assertEq(loan.principal(),          principal);
    }

}

contract LoanV2_UpgradeRefinanceSimulation is TestUtils {

    address constant internal DL_FACTORY                     = address(0xA83404CAA79989FfF1d84bA883a1b8187397866C);
    address constant internal MAPLE_LOAN_IMPLEMENTATION_V200 = address(0x97940C7aea99998da4c56922211ce012E7765395);
    address constant internal MAPLE_GLOBALS                  = address(0xC234c62c8C09687DFf0d9047e40042cd166F3600);
    address constant internal MAPLE_LOAN_INITIALIZER         = address(0xCba99a6648450a7bE7f20B1C3258F74Adb662020);
    address constant internal MAPLE_TREASURY                 = address(0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19);

    address constant internal BORROWER      = address(0xa8c42bBb0648511cC9004fbDCf0FA365088F862B);
    address constant internal GOVERNOR      = address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    address constant internal POOL_DELEGATE = address(0xA6cCb9483E3E7a737E3a4F5B72a1Ce51838ba122);

    IDebtLockerLike   constant internal debtLocker = IDebtLockerLike(0xb61374f64Bb4805e1e815799F3aa6e149C8141E5);
    IMapleLoanFactory constant internal factory    = IMapleLoanFactory(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);
    IMapleLoan        constant internal loan       = IMapleLoan(0x7dF5A2238C62e4b7E05238Da1FBe4b6FbbE22770);
    IPoolLike         constant internal pool       = IPoolLike(0xFeBd6F15Df3B73DC4307B1d7E65D46413e710C27);
    IUSDCLike         constant internal usdc       = IUSDCLike(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address internal loanImplementationV210;
    address internal refinancer;

    function setUp() external {
        // Deploy Loan v2.1.0 implementation and refinancer
        loanImplementationV210 = address(new MapleLoan());
        refinancer             = address(new Refinancer());

        // Configure loan in factory
        vm.startPrank(GOVERNOR);
        factory.registerImplementation(210, loanImplementationV210, MAPLE_LOAN_INITIALIZER);
        factory.enableUpgradePath(200, 210, address(0));
        factory.setDefaultVersion(210);
        vm.stopPrank();
    }

    function test_loanRefinance_samePrincipal() external {
        assertEq(loan.implementation(), MAPLE_LOAN_IMPLEMENTATION_V200);

        vm.startPrank(BORROWER);
        loan.upgrade(210, "");

        assertEq(loan.implementation(), loanImplementationV210);

        uint256 treasuryStartingBalance     = usdc.balanceOf(MAPLE_TREASURY);
        uint256 poolDelegateStartingBalance = usdc.balanceOf(POOL_DELEGATE);
        uint256 poolDelegateEstabFee        = 12_205_479452;
        uint256 treasuryEstabFee            = 24_410_958904;

        assertEq(poolDelegateEstabFee, uint256(7_500_000_000000) * 180 days * 33 / 365 days / 10_000);
        assertEq(treasuryEstabFee,     uint256(7_500_000_000000) * 180 days * 66 / 365 days / 10_000);

        // Return enough USDC to the loan to satisfy investor fee (33) and treasury fee (66) on 7500000.000000 principal refinance,
        // with 2592000 payment interval and 6 payments remaining, which is 12205.479452 and 24410.958904 respectively.
        erc20_mint(address(usdc), 9, BORROWER, poolDelegateEstabFee + treasuryEstabFee);
        usdc.approve(address(loan), poolDelegateEstabFee + treasuryEstabFee);
        loan.returnFunds(poolDelegateEstabFee + treasuryEstabFee);

        assertEq(loan.drawableFunds(), poolDelegateEstabFee + treasuryEstabFee);

        // Propose refinance to set interest rate.
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(Refinancer.setInterestRate.selector, 0.15e18);

        loan.proposeNewTerms(refinancer, calls);

        // Accept refinance as the pool delegate
        vm.stopPrank();
        vm.startPrank(POOL_DELEGATE);
        debtLocker.acceptNewTerms(refinancer, calls, 0);

        // Check that the interest rate wa updated and that fees in USDC were paid.
        assertEq(loan.interestRate(),  0.15e18);
        assertEq(loan.drawableFunds(), 0);

        assertEq(usdc.balanceOf(POOL_DELEGATE),  poolDelegateStartingBalance + poolDelegateEstabFee);
        assertEq(usdc.balanceOf(MAPLE_TREASURY), treasuryStartingBalance + treasuryEstabFee);
    }


    function test_loanRefinance_increasedPrincipal() external {
        assertEq(loan.implementation(), MAPLE_LOAN_IMPLEMENTATION_V200);

        vm.startPrank(BORROWER);
        loan.upgrade(210, "");

        assertEq(loan.implementation(), loanImplementationV210);

        uint256 principalIncreaseAmount = 2_500_000_000000;

        // Propose refinance to set interest rate.
        // NOTE: Establishment fees do not have to be paid upfront since they will be taken out of increased principal
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(Refinancer.increasePrincipal.selector, principalIncreaseAmount);

        loan.proposeNewTerms(refinancer, calls);

        uint256 treasuryStartingBalance     = usdc.balanceOf(MAPLE_TREASURY);
        uint256 poolDelegateStartingBalance = usdc.balanceOf(POOL_DELEGATE);
        uint256 poolDelegateEstabFee        = 16_273_972602;
        uint256 treasuryEstabFee            = 32_547_945205;

        assertEq(poolDelegateEstabFee, uint256(10_000_000_000000) * 180 days * 33 / 365 days / 10_000);
        assertEq(treasuryEstabFee,     uint256(10_000_000_000000) * 180 days * 66 / 365 days / 10_000);

        // Change to Pool Delegate address.
        vm.stopPrank();
        vm.startPrank(POOL_DELEGATE);

        uint256 poolCash = usdc.balanceOf(pool.liquidityLocker());

        // Fund the loan for the increase amount.
        pool.fundLoan(address(loan), DL_FACTORY, principalIncreaseAmount);

        assertEq(usdc.balanceOf(pool.liquidityLocker()), poolCash - principalIncreaseAmount);
        assertEq(usdc.balanceOf(address(debtLocker)),    principalIncreaseAmount);
        assertEq(usdc.balanceOf(address(loan)),          0);

        // Accept terms of the refinance, using re-routed funds from refinance.
        debtLocker.acceptNewTerms(refinancer, calls, principalIncreaseAmount);

        assertEq(usdc.balanceOf(address(debtLocker)),    0);
        assertEq(usdc.balanceOf(address(loan)),          principalIncreaseAmount - (poolDelegateEstabFee + treasuryEstabFee));

        // Check that the interest rate wa updated and that fees in USDC were paid.
        assertEq(loan.principal(),          10_000_000_000000);
        assertEq(loan.principalRequested(), 10_000_000_000000);
        assertEq(loan.drawableFunds(),      principalIncreaseAmount - (poolDelegateEstabFee + treasuryEstabFee));
        assertEq(loan.drawableFunds(),      2_451_178_082193);

        assertEq(usdc.balanceOf(POOL_DELEGATE),  poolDelegateStartingBalance + poolDelegateEstabFee);
        assertEq(usdc.balanceOf(POOL_DELEGATE),  43_707_374596);
        assertEq(usdc.balanceOf(MAPLE_TREASURY), treasuryStartingBalance + treasuryEstabFee);
        assertEq(usdc.balanceOf(MAPLE_TREASURY), 600_431_496595);
    }

    function test_loanRefinance_increasedPrincipal_reducedTerm() external {
        assertEq(loan.implementation(), MAPLE_LOAN_IMPLEMENTATION_V200);

        vm.startPrank(BORROWER);
        loan.upgrade(210, "");

        assertEq(loan.implementation(), loanImplementationV210);

        uint256 principalIncreaseAmount = 2_500_000_000000;

        // Propose refinance to set interest rate.
        // NOTE: Establishment fees do not have to be paid upfront since they will be taken out of increased principal
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(Refinancer.increasePrincipal.selector, principalIncreaseAmount);
        calls[1] = abi.encodeWithSelector(Refinancer.setPaymentsRemaining.selector, 3);

        loan.proposeNewTerms(refinancer, calls);

        uint256 treasuryStartingBalance     = usdc.balanceOf(MAPLE_TREASURY);
        uint256 poolDelegateStartingBalance = usdc.balanceOf(POOL_DELEGATE);
        uint256 poolDelegateEstabFee        = 8_136_986301;
        uint256 treasuryEstabFee            = 16_273_972602;

        assertEq(poolDelegateEstabFee, uint256(10_000_000_000000) * 90 days * 33 / 365 days / 10_000);
        assertEq(treasuryEstabFee,     uint256(10_000_000_000000) * 90 days * 66 / 365 days / 10_000);

        // Change to Pool Delegate address.
        vm.stopPrank();
        vm.startPrank(POOL_DELEGATE);

        uint256 poolCash = usdc.balanceOf(pool.liquidityLocker());

        // Fund the loan for the increase amount.
        pool.fundLoan(address(loan), DL_FACTORY, principalIncreaseAmount);

        assertEq(usdc.balanceOf(pool.liquidityLocker()), poolCash - principalIncreaseAmount);
        assertEq(usdc.balanceOf(address(debtLocker)),    principalIncreaseAmount);
        assertEq(usdc.balanceOf(address(loan)),          0);

        // Accept terms of the refinance, using re-routed funds from refinance.
        debtLocker.acceptNewTerms(refinancer, calls, principalIncreaseAmount);

        assertEq(usdc.balanceOf(address(debtLocker)),    0);
        assertEq(usdc.balanceOf(address(loan)),          principalIncreaseAmount - (poolDelegateEstabFee + treasuryEstabFee));

        // Check that the interest rate wa updated and that fees in USDC were paid.
        assertEq(loan.principal(),          10_000_000_000000);
        assertEq(loan.principalRequested(), 10_000_000_000000);
        assertEq(loan.drawableFunds(),      principalIncreaseAmount - (poolDelegateEstabFee + treasuryEstabFee));
        assertEq(loan.drawableFunds(),      2_475_589_041097);

        assertEq(usdc.balanceOf(POOL_DELEGATE),  poolDelegateStartingBalance + poolDelegateEstabFee);
        assertEq(usdc.balanceOf(POOL_DELEGATE),  35_570_388295);
        assertEq(usdc.balanceOf(MAPLE_TREASURY), treasuryStartingBalance + treasuryEstabFee);
        assertEq(usdc.balanceOf(MAPLE_TREASURY), 584_157_523992);
    }

}
