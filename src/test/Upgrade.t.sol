// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { StateManipulations, TestUtils } from "../../lib/contract-test-utils/contracts/test.sol";
import { IMapleLoan }                    from "../../lib/loan/contracts/interfaces/IMapleLoan.sol";
import { IMapleLoanFactory }             from "../../lib/loan/contracts/interfaces/IMapleLoanFactory.sol";

import { MapleLoan }  from "../../lib/loan/contracts/MapleLoan.sol";
import { Refinancer } from "../../lib/loan/contracts/Refinancer.sol";

interface IUSDCLike {

    function balanceOf(address account_) external view returns (uint256 balance_);

    function mint(address to_, uint256 amount_) external returns (bool success_);

    function transfer(address to_, uint256 amount_) external returns (bool success_);

    function configureMinter(address minter_, uint256 minterAllowedAmount_) external returns (bool success_);

    function updateMasterMinter(address _newMasterMinter) external;

}

contract LoanV2_Simulation is StateManipulations, TestUtils {

    address constant internal MAPLE_LOAN_IMPLEMENTATION_V200 = address(0x97940C7aea99998da4c56922211ce012E7765395);
    address constant internal MAPLE_GLOBALS                  = address(0xC234c62c8C09687DFf0d9047e40042cd166F3600);
    address constant internal MAPLE_LOAN_INITIALIZER         = address(0xCba99a6648450a7bE7f20B1C3258F74Adb662020);

    address constant internal MAPLE_TREASURY = address(0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19);

    uint256 constant internal MAPLE_GLOBALS_GOVERNOR_STORAGE_SLOT = 1;
    uint256 constant internal MAPLE_LOAN_BORROWER_STORAGE_SLOT = 0;
    uint256 constant internal MAPLE_LOAN_LENDER_STORAGE_SLOT = 1;
    uint256 constant internal USDC_OWNER_STORAGE_SLOT = 0;

    IMapleLoanFactory constant internal _factory = IMapleLoanFactory(0x36a7350309B2Eb30F3B908aB0154851B5ED81db0);
    IMapleLoan        constant internal _loan    = IMapleLoan(0x7dF5A2238C62e4b7E05238Da1FBe4b6FbbE22770);
    IUSDCLike         constant internal _usdc    = IUSDCLike(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address internal _loanImplementationV210;
    address internal _refinancer;

    function setUp() external {
        // Set owner of USDC to this.
        hevm.store(address(_usdc), bytes32(USDC_OWNER_STORAGE_SLOT), bytes32(uint256(uint160(address(this)))));

        // Set master minter of USDC to this, and make this a minter.
        _usdc.updateMasterMinter(address(this));
        _usdc.configureMinter(address(this), type(uint256).max);

        // Set borrower and lender of loan to this.
        hevm.store(address(_loan), bytes32(MAPLE_LOAN_BORROWER_STORAGE_SLOT), bytes32(uint256(uint160(address(this)))));
        hevm.store(address(_loan), bytes32(MAPLE_LOAN_LENDER_STORAGE_SLOT), bytes32(uint256(uint160(address(this)))));

        // Set governor of globals to this.
        hevm.store(MAPLE_GLOBALS, bytes32(MAPLE_GLOBALS_GOVERNOR_STORAGE_SLOT), bytes32(uint256(uint160(address(this)))));

        // Deploy and Register new implementation.
        _loanImplementationV210 = address(new MapleLoan());
        _factory.registerImplementation(210, _loanImplementationV210, MAPLE_LOAN_INITIALIZER);
        _factory.enableUpgradePath(200, 210, address(0));
        _factory.setDefaultVersion(210);

        // Deploy refinancer.
        _refinancer = address(new Refinancer());
    }

    function poolDelegate() external view returns (address poolDelegate_) {
        poolDelegate_ = address(this);
    }

    function test_loanUpgrade() external {
        assertEq(_loan.implementation(), MAPLE_LOAN_IMPLEMENTATION_V200);

        _loan.upgrade(210, "");

        assertEq(_loan.implementation(), _loanImplementationV210);

        // Return enough USDC to the loan to satisfy investor fee (33) and treasury fee (66) on 7500000.000000 principal refinance,
        // with 2592000 payment interval and 6 payments remaining, which is 12205.479452 and 24410.958904 respectively.
        _usdc.mint(address(_loan), 12205479452 + 24410958904);
        _loan.returnFunds(0);

        assertEq(_loan.drawableFunds(), 12205479452 + 24410958904);

        // Propose refinance to set interest rate.
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(Refinancer.setInterestRate.selector, 100000000000000000);

        _loan.proposeNewTerms(_refinancer, calls);

        uint256 treasuryStartingBalance = _usdc.balanceOf(MAPLE_TREASURY);

        // Accept refinance.
        _loan.acceptNewTerms(_refinancer, calls, 0);

        // Check that the interest rate wa updated and that fees in USDC were paid.
        assertEq(_loan.interestRate(), 100000000000000000);
        assertEq(_loan.drawableFunds(), 0);
        assertEq(_usdc.balanceOf(address(this)), 12205479452);
        assertEq(_usdc.balanceOf(MAPLE_TREASURY), treasuryStartingBalance + 24410958904);
    }

}
