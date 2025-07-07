// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Escrow} from "../src/Escrow.sol";
import {IEscrow} from "../src/interfaces/IEscrow.sol";
import {IEscrowErrors} from "../src/interfaces/IEscrowErrors.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {console} from "forge-std/console.sol";

contract EscrowTest is Test {
    Escrow public escrow;
    MockERC20 public token;
    MockERC721 public nft;
    MockERC1155 public nft1155;

    address public owner;
    address[] public escrowOwners;

    address public depositor;
    address public beneficiary;

    uint256 public constant PLATFORM_FEE = 200; // 2%
    uint256 public constant TOTAL_AMOUNT = 100 ether;
    uint256 public constant INSTALLMENTS = 4;
    uint256 public constant PAYMENT_INTERVAL = 30 seconds;
    uint256 public constant DAILY_INTEREST = 100; // 1%

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed depositor,
        address indexed beneficiary,
        bool requiresGuarantee,
        uint256 totalAmount,
        uint256 totalInstallments,
        address paymentToken
    );

    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        depositor = makeAddr("depositor");
        beneficiary = makeAddr("beneficiary");

        // Create escrow owners
        escrowOwners = new address[](2);
        escrowOwners[0] = makeAddr("escrowOwner1");
        escrowOwners[1] = makeAddr("escrowOwner2");

        vm.startPrank(owner);

        // Deploy contracts
        escrow = new Escrow(PLATFORM_FEE);
        token = new MockERC20("Test Token", "TEST");
        nft = new MockERC721("Test NFT", "TNFT");
        nft1155 = new MockERC1155("uri/");

        // Allow tokens
        escrow.setAllowedToken(address(token), true);
        escrow.setAllowedToken(address(nft1155), true);
        escrow.setAllowedERC721Or1155(address(nft), 1, true);

        // Approve escrow owners
        escrow.setEscrowOwnersApproval(escrowOwners, true);

        vm.stopPrank();

        // Fund accounts - ✅ CORREÇÃO: Aumentar saldo do depositor
        vm.deal(depositor, 10000 ether); // Era 1000, agora 10000 ether
        token.mint(depositor, 1000 ether);
        nft.mint(depositor, 1);
        nft1155.mint(depositor, 1, 10);
    }

    function test_CreateEscrow() public {
        vm.startPrank(depositor);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        vm.expectEmit(true, true, true, true);
        emit EscrowCreated(1, depositor, beneficiary, true, TOTAL_AMOUNT, INSTALLMENTS, address(0));

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));
        assertEq(escrowId, 1, "Wrong escrow ID");

        vm.stopPrank();
    }

    function test_ProvideGuaranteeAndStart() public {
        // First create escrow
        uint256 escrowId = _createBasicEscrow();

        vm.startPrank(depositor);

        // Provide ETH guarantee
        uint256 guaranteeAmount = 10 ether;
        escrow.provideGuarantee{value: guaranteeAmount}(escrowId, IEscrow.TokenType.ETH, address(0), 0, guaranteeAmount);

        // Start escrow
        escrow.startEscrow(escrowId);

        vm.stopPrank();
    }

    function test_PayInstallments() public {
        // Setup escrow and start it
        uint256 escrowId = _createAndStartEscrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        vm.startPrank(depositor);

        // Pay first installment
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);

        // Try to pay second installment early (should work)
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);

        // Try to pay third installment late (should include interest)
        vm.warp(block.timestamp + 45 seconds); // 15 seconds late
        (uint256 amountDue,) = escrow.calculateInstallmentWithInterest(escrowId);
        escrow.payInstallmentETH{value: amountDue}(escrowId);

        vm.stopPrank();
    }

    function test_CreateERC20Escrow() public {
        vm.startPrank(depositor);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(token),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        vm.expectEmit(true, true, true, true);
        emit EscrowCreated(1, depositor, beneficiary, true, TOTAL_AMOUNT, INSTALLMENTS, address(token));

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));
        assertEq(escrowId, 1, "Wrong escrow ID");

        vm.stopPrank();
    }

    function test_ProvideERC20GuaranteeAndStart() public {
        // First create escrow with ERC20
        uint256 escrowId = _createBasicERC20Escrow();

        vm.startPrank(depositor);

        // Approve token for guarantee
        uint256 guaranteeAmount = 10 ether;
        token.approve(address(escrow), guaranteeAmount);

        // Provide ERC20 guarantee
        escrow.provideGuarantee(escrowId, IEscrow.TokenType.ERC20, address(token), 0, guaranteeAmount);

        // Start escrow
        escrow.startEscrow(escrowId);

        vm.stopPrank();
    }

    function test_PayERC20Installments() public {
        // Setup escrow and start it
        uint256 escrowId = _createAndStartERC20Escrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        vm.startPrank(depositor);

        // Approve tokens for payments
        token.approve(address(escrow), TOTAL_AMOUNT);

        // Pay first installment
        escrow.payInstallmentERC20(escrowId, installmentAmount);

        // Verify balance
        assertEq(
            escrow.getEscrowBalance(escrowId, address(token)),
            installmentAmount,
            "Wrong escrow balance after first payment"
        );

        // Pay second installment early (should work)
        escrow.payInstallmentERC20(escrowId, installmentAmount);

        // Pay third installment late (should include interest)
        vm.warp(block.timestamp + 45 seconds); // 15 seconds late
        (uint256 amountDue,) = escrow.calculateInstallmentWithInterest(escrowId);
        escrow.payInstallmentERC20(escrowId, amountDue);

        vm.stopPrank();
    }

    function test_WithdrawERC20() public {
        uint256 escrowId = _createAndStartERC20Escrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Depositor makes a payment
        vm.startPrank(depositor);
        token.approve(address(escrow), installmentAmount);
        escrow.payInstallmentERC20(escrowId, installmentAmount);
        vm.stopPrank();

        // Get initial balances
        uint256 initialBeneficiaryBalance = token.balanceOf(beneficiary);
        uint256 initialOwnerBalance = token.balanceOf(owner);

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]); // Use escrow owner
        escrow.setReleaseApproval(escrowId, true);

        // Beneficiary withdraws
        vm.prank(beneficiary);
        escrow.withdrawFunds(escrowId);

        // Calculate expected amounts
        uint256 platformFee = (installmentAmount * PLATFORM_FEE) / 10000;
        uint256 expectedBeneficiaryAmount = installmentAmount - platformFee;

        // Verify balances
        assertEq(
            token.balanceOf(beneficiary),
            initialBeneficiaryBalance + expectedBeneficiaryAmount,
            "Wrong beneficiary balance after withdrawal"
        );
        assertEq(token.balanceOf(owner), initialOwnerBalance + platformFee, "Wrong owner balance after withdrawal");
        assertEq(escrow.getEscrowBalance(escrowId, address(token)), 0, "Escrow balance should be 0 after withdrawal");
    }

    // Helper function to create basic escrow
    function _createBasicEscrow() internal returns (uint256) {
        // Use escrowOwner to create escrow
        vm.prank(escrowOwners[0]);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        return escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));
    }

    // Helper to create and start escrow
    function _createAndStartEscrow() internal returns (uint256) {
        uint256 escrowId = _createBasicEscrow();

        vm.startPrank(depositor);
        escrow.provideGuarantee{value: 10 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);
        escrow.startEscrow(escrowId); // Now depositor can start
        vm.stopPrank();

        return escrowId;
    }

    // Helper function to create basic ERC20 escrow
    function _createBasicERC20Escrow() internal returns (uint256) {
        // Use escrow owner to create
        vm.prank(escrowOwners[0]);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(token),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        return escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));
    }

    // Helper to create and start ERC20 escrow
    function _createAndStartERC20Escrow() internal returns (uint256) {
        uint256 escrowId = _createBasicERC20Escrow();

        vm.startPrank(depositor);
        token.approve(address(escrow), 10 ether);
        escrow.provideGuarantee(escrowId, IEscrow.TokenType.ERC20, address(token), 0, 10 ether);
        escrow.startEscrow(escrowId); // Now depositor can start
        vm.stopPrank();

        return escrowId;
    }

    // Add new test for custom installment schedule
    function test_CreateEscrowWithCustomSchedule() public {
        vm.startPrank(depositor);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: 3,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: true
        });

        // Create custom installment schedule
        IEscrow.InstallmentDetail[] memory schedule = new IEscrow.InstallmentDetail[](3);
        schedule[0] = IEscrow.InstallmentDetail({dueDate: block.timestamp + 30 seconds, amount: 20 ether, paid: false});
        schedule[1] = IEscrow.InstallmentDetail({dueDate: block.timestamp + 60 seconds, amount: 30 ether, paid: false});
        schedule[2] = IEscrow.InstallmentDetail({dueDate: block.timestamp + 90 seconds, amount: 50 ether, paid: false});

        uint256 escrowId = escrow.createEscrow(params, schedule);
        assertEq(escrowId, 1, "Wrong escrow ID");

        vm.stopPrank();
    }

    // Add these new test functions

    function test_DisputeResolution() public {
        uint256 escrowId = _createAndStartEscrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Make first payment and ensure escrow is active
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);

        // Verify escrow is active
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        require(info.state == IEscrow.EscrowState.ACTIVE, "Escrow not active");

        // Open dispute
        escrow.openDispute(escrowId);
        vm.stopPrank();

        // Store initial balances
        uint256 initialDepositorBalance = address(depositor).balance;
        uint256 initialBeneficiaryBalance = address(beneficiary).balance;
        uint256 initialPendingFees = escrow.pendingFees(owner);
        uint256 initialOwnerBalance = address(owner).balance;

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // Calculate proper distribution considering platform fee
        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 availableForDistribution = balance - platformFee;
        uint256 halfAvailable = availableForDistribution / 2;

        vm.prank(escrowOwners[0]);
        escrow.resolveDispute(escrowId, halfAvailable, halfAvailable, "Split funds equally");

        // Verify balances - parties get their allocated amounts
        assertEq(
            address(depositor).balance - initialDepositorBalance, halfAvailable, "Wrong depositor balance after dispute"
        );
        assertEq(
            address(beneficiary).balance - initialBeneficiaryBalance,
            halfAvailable,
            "Wrong beneficiary balance after dispute"
        );

        // Verify platform fee was added to pending fees (not transferred directly)
        assertEq(escrow.pendingFees(owner) - initialPendingFees, platformFee, "Wrong pending fees amount");

        // Owner balance should not change yet
        assertEq(address(owner).balance, initialOwnerBalance, "Owner balance should not change before withdrawFees");

        // Owner can withdraw fees using pull payment
        vm.prank(owner);
        escrow.withdrawFees();

        assertEq(address(owner).balance - initialOwnerBalance, platformFee, "Wrong owner balance after fee withdrawal");
    }

    function test_GuaranteeReturn() public {
        uint256 escrowId = _createAndStartEscrow();

        // Complete all payments
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId);
        vm.stopPrank();

        // ✅ CORREÇÃO: Finalizar o escrow via auto-execute
        vm.warp(block.timestamp + 91 days);
        escrow.autoExecuteTransaction(escrowId);

        // ✅ Agora o escrow está COMPLETE
        uint256 initialBalance = address(depositor).balance;
        vm.prank(depositor);
        escrow.returnGuarantee(escrowId, IEscrow.TokenType.ETH, address(0), 0);

        assertEq(
            address(depositor).balance - initialBalance, 10 ether, "Wrong depositor balance after guarantee return"
        );
    }

    function test_PartialWithdrawal() public {
        // Create escrow with partial withdrawal enabled
        vm.prank(escrowOwners[0]); // Use escrow owner to create

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: true,
            paymentToken: address(token),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Provide guarantee and start
        vm.startPrank(depositor);
        token.approve(address(escrow), 10 ether);
        escrow.provideGuarantee(escrowId, IEscrow.TokenType.ERC20, address(token), 0, 10 ether);
        escrow.startEscrow(escrowId);

        // Make payment
        token.approve(address(escrow), TOTAL_AMOUNT);
        escrow.payInstallmentERC20(escrowId, 25 ether);
        vm.stopPrank();

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // Partial withdraw
        uint256 withdrawAmount = 10 ether;
        uint256 initialBalance = token.balanceOf(beneficiary);

        vm.prank(beneficiary);
        escrow.partialWithdraw(escrowId, withdrawAmount);

        uint256 expectedNet = withdrawAmount - ((withdrawAmount * PLATFORM_FEE) / 10000);
        assertEq(
            token.balanceOf(beneficiary),
            initialBalance + expectedNet,
            "Wrong beneficiary balance after partial withdrawal"
        );
    }

    function test_MultiTokenGuarantees() public {
        uint256 escrowId = _createBasicEscrow();

        vm.startPrank(depositor);

        // Approve tokens
        token.approve(address(escrow), type(uint256).max);
        nft.approve(address(escrow), 1);
        nft1155.setApprovalForAll(address(escrow), true);

        // Provide ETH guarantee first
        escrow.provideGuarantee{value: 5 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 5 ether);

        // Start escrow after first guarantee
        escrow.startEscrow(escrowId);

        // Cannot provide more guarantees after escrow starts
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidEscrowState.selector));
        escrow.provideGuarantee(escrowId, IEscrow.TokenType.ERC20, address(token), 0, 5 ether);

        vm.stopPrank();
    }

    function test_EscrowOwnerApproval() public {
        address newEscrowOwner = makeAddr("newEscrowOwner");

        // Only owner can approve escrow owners
        vm.prank(owner);
        address[] memory newOwners = new address[](1);
        newOwners[0] = newEscrowOwner;
        escrow.setEscrowOwnersApproval(newOwners, true);

        // New escrow owner should be able to create escrow
        vm.prank(newEscrowOwner);
        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));
        assertEq(escrowId, 1, "Wrong escrow ID");
    }

    function test_CompoundInterest() public {
        vm.prank(escrowOwners[0]);
        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: 1 days, // Change to 1 day interval
            dailyInterestFeeBP: 5000, // 50% daily interest
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.COMPOUND,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        vm.startPrank(depositor);
        escrow.provideGuarantee{value: 10 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);
        escrow.startEscrow(escrowId);

        // Warp 2 days ahead to ensure we have at least 1 full day of interest
        vm.warp(block.timestamp + 2 days);

        // Add debug logs
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        console.log("Current timestamp:", block.timestamp);
        console.log("Last payment timestamp:", info.lastPaymentTimestamp);
        console.log("Time difference (days):", (block.timestamp - info.lastPaymentTimestamp) / 1 days);
        console.log("Payment interval (days):", info.paymentIntervalSeconds / 1 days);
        console.log("Daily interest rate (BP):", info.dailyInterestFeeBP);

        (uint256 amountDue, uint256 interest) = escrow.calculateInstallmentWithInterest(escrowId);
        console.log("Interest:", interest);
        console.log("Amount Due:", amountDue);
        console.log("Base Amount:", TOTAL_AMOUNT / INSTALLMENTS);

        assertGt(interest, 0, "No interest charged");
        assertGt(amountDue, TOTAL_AMOUNT / INSTALLMENTS, "No interest added to payment");

        vm.stopPrank();
    }

    function test_RevertConditions() public {
        uint256 escrowId = _createBasicEscrow();

        // Try to start without guarantee
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.GuaranteeRequired.selector));
        escrow.startEscrow(escrowId);

        // Try to provide guarantee with wrong amount
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidAmount.selector));
        escrow.provideGuarantee{value: 1 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);

        // Try to pay installment before escrow is active
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.EscrowNotActive.selector));
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
    }

    function test_InvalidEscrowCreation() public {
        vm.startPrank(escrowOwners[0]);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: address(0),
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidDepositor.selector));
        escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Test invalid beneficiary
        params.depositor = depositor;
        params.beneficiary = address(0);
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidBeneficiary.selector));
        escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Test invalid amount
        params.beneficiary = beneficiary;
        params.totalAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidAmount.selector));
        escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Test invalid interest rate
        params.totalAmount = TOTAL_AMOUNT;
        params.dailyInterestFeeBP = 10000;
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidInterestRate.selector));
        escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        vm.stopPrank();
    }

    function test_InvalidGuaranteeProvision() public {
        uint256 escrowId = _createBasicEscrow();

        // Test unauthorized caller
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.UnauthorizedCaller.selector));
        escrow.provideGuarantee{value: 10 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);

        // Test invalid token
        vm.prank(depositor);
        address randomToken = makeAddr("randomToken");
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.TokenNotAllowed.selector));
        escrow.provideGuarantee(escrowId, IEscrow.TokenType.ERC20, randomToken, 0, 10 ether);
    }

    function test_DisputeEdgeCases() public {
        uint256 escrowId = _createAndStartEscrow();

        // Try to open dispute from non-participant
        vm.prank(makeAddr("random"));
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidCaller.selector));
        escrow.openDispute(escrowId);

        // Open dispute properly
        vm.prank(depositor);
        escrow.openDispute(escrowId);

        // Try invalid distribution with approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        vm.prank(escrowOwners[0]);
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidDistribution.selector));
        escrow.resolveDispute(escrowId, 1000 ether, 1000 ether, "Invalid amounts");
    }

    function test_UnsupportedTokenType() public {
        uint256 escrowId = _createBasicEscrow();

        // Create a bytes array for the function call
        bytes memory data = abi.encodeWithSelector(
            Escrow.provideGuarantee.selector,
            escrowId,
            uint8(99), // Invalid token type
            address(0),
            0,
            10 ether
        );

        vm.prank(depositor);
        // Use expectRevert with raw bytes
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.UnsupportedTokenType.selector));
        (bool success,) = address(escrow).call{value: 10 ether}(data);
        require(!success, "Call should fail");
    }

    function test_PartialWithdrawEdgeCases() public {
        // Create escrow with partial withdrawals disabled
        vm.prank(escrowOwners[0]);
        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Setup escrow
        vm.startPrank(depositor);
        escrow.provideGuarantee{value: 10 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);
        escrow.startEscrow(escrowId);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        vm.stopPrank();

        // Try partial withdraw when disabled
        vm.prank(beneficiary);
        vm.expectRevert("Partial withdrawal not allowed");
        escrow.partialWithdraw(escrowId, 1 ether);
    }

    function test_CustomScheduleValidation() public {
        vm.startPrank(escrowOwners[0]);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: 2, // Changed to match our test schedule
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: true
        });

        vm.expectRevert("No installments provided for custom schedule");
        escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Test invalid schedule total amount (should sum to TOTAL_AMOUNT)
        IEscrow.InstallmentDetail[] memory invalidSchedule = new IEscrow.InstallmentDetail[](2);
        invalidSchedule[0] = IEscrow.InstallmentDetail({
            dueDate: block.timestamp + 30 seconds,
            amount: 120 ether, // Total will be more than TOTAL_AMOUNT
            paid: false
        });
        invalidSchedule[1] =
            IEscrow.InstallmentDetail({dueDate: block.timestamp + 60 seconds, amount: 120 ether, paid: false});

        vm.expectRevert("Sum of custom installments != totalAmount");
        escrow.createEscrow(params, invalidSchedule);

        vm.stopPrank();
    }

    function test_InterestCalculationEdgeCases() public {
        vm.prank(escrowOwners[0]);
        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: 1000, // 10% daily interest
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(0),
            interestModel: IEscrow.InterestModel.COMPOUND,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        vm.startPrank(depositor);
        escrow.provideGuarantee{value: 10 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);
        escrow.startEscrow(escrowId);
        vm.stopPrank();

        // Test zero days late
        (uint256 amountDue, uint256 interest) = escrow.calculateInstallmentWithInterest(escrowId);
        assertEq(interest, 0, "Should have no interest when not late");
        assertEq(amountDue, TOTAL_AMOUNT / INSTALLMENTS, "Wrong base amount");

        // Test one day late
        vm.warp(block.timestamp + PAYMENT_INTERVAL + 1 days);

        // Update debug logs to use seconds
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        console.log("Current timestamp:", block.timestamp);
        console.log("Last payment timestamp:", info.lastPaymentTimestamp);
        console.log("Payment interval (seconds):", info.paymentIntervalSeconds);
        console.log("Daily interest rate (BP):", info.dailyInterestFeeBP);

        (amountDue, interest) = escrow.calculateInstallmentWithInterest(escrowId);
        console.log("Amount due:", amountDue);
        console.log("Interest:", interest);

        assertGt(interest, 0, "Should have interest when late");
    }

    function test_DisputeResolutionScenarios() public {
        uint256 escrowId = _createAndStartEscrow();

        // Make some payments
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);

        // Open dispute
        escrow.openDispute(escrowId);
        vm.stopPrank();

        // Store initial balances
        uint256 initialDepositorBalance = address(depositor).balance;
        uint256 initialPendingFees = escrow.pendingFees(owner);
        uint256 initialOwnerBalance = address(owner).balance;

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // Calculate proper amounts considering platform fee
        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 availableForRefund = balance - platformFee; // 49 ether available for refund

        vm.startPrank(escrowOwners[0]);

        // Full refund to buyer (minus platform fee)
        escrow.resolveDispute(escrowId, availableForRefund, 0, "Full refund to buyer");
        vm.stopPrank();

        // Verify depositor received the refund amount (49 ether)
        assertEq(
            address(depositor).balance - initialDepositorBalance,
            availableForRefund,
            "Wrong depositor balance after full refund"
        );

        // Verify platform fee was added to pending fees
        assertEq(escrow.pendingFees(owner) - initialPendingFees, platformFee, "Wrong pending fees amount");

        // Owner withdraws fees
        vm.prank(owner);
        escrow.withdrawFees();

        assertEq(address(owner).balance - initialOwnerBalance, platformFee, "Wrong owner balance after fee withdrawal");
    }

    function test_ERC1155GuaranteeHandling() public {
        uint256 escrowId = _createBasicEscrow();

        // Allow the specific token ID
        vm.prank(owner);
        escrow.setAllowedERC721Or1155(address(nft1155), 1, true);

        vm.startPrank(depositor);
        nft1155.setApprovalForAll(address(escrow), true);

        // Provide ERC1155 guarantee
        uint256 guaranteeAmount = 5;
        nft1155.mint(depositor, 1, guaranteeAmount);
        escrow.provideGuarantee(escrowId, IEscrow.TokenType.ERC1155, address(nft1155), 1, guaranteeAmount);

        // Complete escrow flow
        escrow.startEscrow(escrowId);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId);
        vm.stopPrank();

        // ✅ CORREÇÃO: Finalizar o escrow
        vm.warp(block.timestamp + 91 days);
        escrow.autoExecuteTransaction(escrowId);

        // Store initial balance
        uint256 initialBalance = nft1155.balanceOf(depositor, 1);

        // Return guarantee (agora funciona porque escrow está COMPLETE)
        vm.prank(depositor);
        escrow.returnGuarantee(escrowId, IEscrow.TokenType.ERC1155, address(nft1155), 1);

        // Verify guarantee returned
        assertEq(nft1155.balanceOf(depositor, 1), initialBalance + guaranteeAmount, "ERC1155 not returned correctly");
    }

    // Novo teste para validar casos extremos
    function test_DisputeResolutionInvalidDistribution() public {
        uint256 escrowId = _createAndStartEscrow();

        // Make payment
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        escrow.openDispute(escrowId);
        vm.stopPrank();

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));

        // Try to distribute more than available (ignoring platform fee)
        vm.prank(escrowOwners[0]);
        vm.expectRevert(abi.encodeWithSelector(IEscrowErrors.InvalidDistribution.selector));
        escrow.resolveDispute(escrowId, balance, 1, "Invalid distribution");
    }

    // Novo teste para ERC20 dispute resolution
    function test_DisputeResolutionERC20() public {
        // Create ERC20 escrow
        vm.prank(escrowOwners[0]);
        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: false,
            paymentToken: address(token),
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Setup escrow
        vm.startPrank(depositor);
        token.approve(address(escrow), type(uint256).max);
        escrow.provideGuarantee(escrowId, IEscrow.TokenType.ERC20, address(token), 0, 10 ether);
        escrow.startEscrow(escrowId);
        escrow.payInstallmentERC20(escrowId, 25 ether);
        escrow.openDispute(escrowId);
        vm.stopPrank();

        // Store initial balances
        uint256 initialDepositorBalance = token.balanceOf(depositor);
        uint256 initialBeneficiaryBalance = token.balanceOf(beneficiary);
        uint256 initialOwnerBalance = token.balanceOf(owner);

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // Calculate proper distribution
        uint256 balance = escrow.getEscrowBalance(escrowId, address(token));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 availableForDistribution = balance - platformFee;
        uint256 halfAvailable = availableForDistribution / 2;

        vm.prank(escrowOwners[0]);
        escrow.resolveDispute(escrowId, halfAvailable, halfAvailable, "Split ERC20 funds equally");

        // Verify balances
        assertEq(
            token.balanceOf(depositor) - initialDepositorBalance,
            halfAvailable,
            "Wrong depositor ERC20 balance after dispute"
        );
        assertEq(
            token.balanceOf(beneficiary) - initialBeneficiaryBalance,
            halfAvailable,
            "Wrong beneficiary ERC20 balance after dispute"
        );
        assertEq(
            token.balanceOf(owner) - initialOwnerBalance,
            platformFee,
            "Wrong owner ERC20 balance - platform fee not transferred"
        );
    }

    function test_WithdrawETH() public {
        uint256 escrowId = _createAndStartEscrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Depositor makes a payment
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        vm.stopPrank();

        // Get initial balances
        uint256 initialBeneficiaryBalance = address(beneficiary).balance;
        uint256 initialOwnerBalance = address(owner).balance;
        uint256 initialPendingFees = escrow.pendingFees(owner);

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // Beneficiary withdraws
        vm.prank(beneficiary);
        escrow.withdrawFunds(escrowId);

        // Calculate expected amounts
        uint256 platformFee = (installmentAmount * PLATFORM_FEE) / 10000;
        uint256 expectedBeneficiaryAmount = installmentAmount - platformFee;

        // Verify balances
        assertEq(
            address(beneficiary).balance - initialBeneficiaryBalance,
            expectedBeneficiaryAmount,
            "Wrong beneficiary balance after withdrawal"
        );

        // Verify platform fee was added to pending fees (not transferred directly)
        assertEq(escrow.pendingFees(owner) - initialPendingFees, platformFee, "Wrong pending fees amount");

        // Owner balance should not change yet
        assertEq(address(owner).balance, initialOwnerBalance, "Owner balance should not change before withdrawFees");

        // Owner withdraws fees using pull payment
        vm.prank(owner);
        escrow.withdrawFees();

        assertEq(address(owner).balance - initialOwnerBalance, platformFee, "Wrong owner balance after fee withdrawal");

        // Pending fees should be zero after withdrawal
        assertEq(escrow.pendingFees(owner), 0, "Pending fees should be zero after withdrawal");

        assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Escrow balance should be 0 after withdrawal");
    }

    function test_PartialWithdrawalETH() public {
        // Create escrow with partial withdrawal enabled
        vm.prank(escrowOwners[0]);

        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: true,
            paymentToken: address(0), // ETH
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Provide guarantee and start
        vm.startPrank(depositor);
        escrow.provideGuarantee{value: 10 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);
        escrow.startEscrow(escrowId);

        // Make payment
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        vm.stopPrank();

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // Store initial state
        uint256 withdrawAmount = 10 ether;
        uint256 initialBeneficiaryBalance = address(beneficiary).balance;
        uint256 initialPendingFees = escrow.pendingFees(owner);
        uint256 initialOwnerBalance = address(owner).balance;

        // Partial withdraw
        vm.prank(beneficiary);
        escrow.partialWithdraw(escrowId, withdrawAmount);

        // Calculate expected amounts
        uint256 platformFee = (withdrawAmount * PLATFORM_FEE) / 10000;
        uint256 expectedNet = withdrawAmount - platformFee;

        // Verify beneficiary received net amount
        assertEq(
            address(beneficiary).balance - initialBeneficiaryBalance,
            expectedNet,
            "Wrong beneficiary balance after partial withdrawal"
        );

        // Verify platform fee was added to pending fees
        assertEq(
            escrow.pendingFees(owner) - initialPendingFees,
            platformFee,
            "Wrong pending fees amount after partial withdrawal"
        );

        // Owner balance should not change yet
        assertEq(address(owner).balance, initialOwnerBalance, "Owner balance should not change before withdrawFees");

        // Owner withdraws fees
        vm.prank(owner);
        escrow.withdrawFees();

        assertEq(address(owner).balance - initialOwnerBalance, platformFee, "Wrong owner balance after fee withdrawal");
    }

    function test_AccumulatedPendingFees() public {
        // Create one escrow with partial withdrawal enabled
        vm.prank(escrowOwners[0]);
        IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
            depositor: depositor,
            beneficiary: beneficiary,
            requiresGuarantee: true,
            totalAmount: TOTAL_AMOUNT,
            totalInstallments: INSTALLMENTS,
            paymentIntervalSeconds: PAYMENT_INTERVAL,
            dailyInterestFeeBP: DAILY_INTEREST,
            allowBeneficiaryWithdrawPartial: true,
            paymentToken: address(0), // ETH
            interestModel: IEscrow.InterestModel.SIMPLE,
            useCustomSchedule: false
        });

        uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

        // Setup escrow
        vm.startPrank(depositor);
        escrow.provideGuarantee{value: 10 ether}(escrowId, IEscrow.TokenType.ETH, address(0), 0, 10 ether);
        escrow.startEscrow(escrowId);

        // Make payments
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        vm.stopPrank();

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        uint256 initialPendingFees = escrow.pendingFees(owner);
        uint256 initialOwnerBalance = address(owner).balance;

        // Make two partial withdrawals to accumulate fees
        uint256 withdrawAmount = 10 ether;

        vm.prank(beneficiary);
        escrow.partialWithdraw(escrowId, withdrawAmount);

        vm.prank(beneficiary);
        escrow.partialWithdraw(escrowId, withdrawAmount);

        // Verify accumulated pending fees
        uint256 expectedTotalFees = 2 * ((withdrawAmount * PLATFORM_FEE) / 10000);
        assertEq(escrow.pendingFees(owner) - initialPendingFees, expectedTotalFees, "Wrong accumulated pending fees");

        // Owner withdraws all accumulated fees
        vm.prank(owner);
        escrow.withdrawFees();

        assertEq(address(owner).balance - initialOwnerBalance, expectedTotalFees, "Wrong total fees withdrawn");

        assertEq(escrow.pendingFees(owner), 0, "Pending fees should be zero after withdrawal");
    }

    function test_WithdrawFeesWhenNoPending() public {
        vm.prank(owner);
        vm.expectRevert("No fees to withdraw");
        escrow.withdrawFees();
    }

    // ========================================================================
    // 🤝 SETTLEMENT SYSTEM TESTS
    // ========================================================================

    function test_ProposeSettlement_ETH() public {
        uint256 escrowId = _createAndStartEscrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Make some payments
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        vm.stopPrank();

        uint256 balance = escrow.getEscrowBalance(escrowId, address(0)); // 50 ether
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000; // 1 ether
        uint256 availableForDistribution = balance - platformFee; // 49 ether

        uint256 amountToSender = 30 ether;
        uint256 amountToReceiver = 19 ether; // Total: 49 ether

        // Buyer proposes settlement
        vm.prank(depositor);
        vm.expectEmit(true, true, false, true);
        emit SettlementProposed(escrowId, depositor, amountToSender, amountToReceiver);
        escrow.proposeSettlement(escrowId, amountToSender, amountToReceiver);

        // Verify settlement proposal saved
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertTrue(info.hasSettlementProposal, "Settlement proposal should exist");
        assertEq(info.settlementAmountToSender, amountToSender, "Wrong amount to sender");
        assertEq(info.settlementAmountToReceiver, amountToReceiver, "Wrong amount to receiver");
        assertEq(info.settlementProposedBy, depositor, "Wrong proposer");
        assertEq(info.settlementDeadline, block.timestamp + 30 days, "Wrong settlement deadline");
    }

    function test_ProposeSettlement_ERC20() public {
        uint256 escrowId = _createAndStartERC20Escrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Make some payments
        vm.startPrank(depositor);
        token.approve(address(escrow), TOTAL_AMOUNT);
        escrow.payInstallmentERC20(escrowId, installmentAmount);
        escrow.payInstallmentERC20(escrowId, installmentAmount);
        vm.stopPrank();

        uint256 balance = escrow.getEscrowBalance(escrowId, address(token));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 availableForDistribution = balance - platformFee;

        uint256 amountToSender = availableForDistribution / 2;
        uint256 amountToReceiver = availableForDistribution / 2;

        // Seller proposes settlement
        vm.prank(beneficiary);
        escrow.proposeSettlement(escrowId, amountToSender, amountToReceiver);

        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertTrue(info.hasSettlementProposal, "Settlement proposal should exist");
        assertEq(info.settlementProposedBy, beneficiary, "Wrong proposer");
    }

    function test_AcceptSettlement_ETH() public {
        uint256 escrowId = _createAndStartEscrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Make payments
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        vm.stopPrank();

        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 availableForDistribution = balance - platformFee;

        uint256 amountToSender = 30 ether;
        uint256 amountToReceiver = availableForDistribution - amountToSender;

        // Buyer proposes settlement
        vm.prank(depositor);
        escrow.proposeSettlement(escrowId, amountToSender, amountToReceiver);

        // Store initial balances
        uint256 initialSenderBalance = address(depositor).balance;
        uint256 initialReceiverBalance = address(beneficiary).balance;
        uint256 initialPendingFees = escrow.pendingFees(owner);

        // Seller accepts settlement
        vm.prank(beneficiary);
        vm.expectEmit(true, true, false, true);
        emit SettlementAccepted(escrowId, beneficiary);
        escrow.acceptSettlement(escrowId);

        // Verify final state
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete");
        assertFalse(info.hasSettlementProposal, "Settlement proposal should be cleared");
        assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Escrow balance should be zero");

        // Verify balance transfers
        assertEq(address(depositor).balance - initialSenderBalance, amountToSender, "Wrong sender balance");
        assertEq(address(beneficiary).balance - initialReceiverBalance, amountToReceiver, "Wrong receiver balance");
        assertEq(escrow.pendingFees(owner) - initialPendingFees, platformFee, "Wrong pending fees");
    }

    function test_AcceptSettlement_ERC20() public {
        uint256 escrowId = _createAndStartERC20Escrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Make payments
        vm.startPrank(depositor);
        token.approve(address(escrow), TOTAL_AMOUNT);
        escrow.payInstallmentERC20(escrowId, installmentAmount);
        escrow.payInstallmentERC20(escrowId, installmentAmount);
        vm.stopPrank();

        uint256 balance = escrow.getEscrowBalance(escrowId, address(token));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 availableForDistribution = balance - platformFee;

        uint256 amountToSender = availableForDistribution / 3;
        uint256 amountToReceiver = availableForDistribution - amountToSender;

        // Seller proposes settlement
        vm.prank(beneficiary);
        escrow.proposeSettlement(escrowId, amountToSender, amountToReceiver);

        // Store initial balances
        uint256 initialSenderBalance = token.balanceOf(depositor);
        uint256 initialReceiverBalance = token.balanceOf(beneficiary);
        uint256 initialOwnerBalance = token.balanceOf(owner);

        // Buyer accepts settlement
        vm.prank(depositor);
        escrow.acceptSettlement(escrowId);

        // Verify balance transfers (ERC20 transfers fees directly)
        assertEq(token.balanceOf(depositor) - initialSenderBalance, amountToSender, "Wrong sender ERC20 balance");
        assertEq(
            token.balanceOf(beneficiary) - initialReceiverBalance, amountToReceiver, "Wrong receiver ERC20 balance"
        );
        assertEq(token.balanceOf(owner) - initialOwnerBalance, platformFee, "Wrong owner ERC20 balance");
    }

    function test_SettlementRevertConditions() public {
        uint256 escrowId = _createAndStartEscrow();

        // Test: Non-participant cannot propose
        vm.prank(makeAddr("random"));
        vm.expectRevert("Only buyer or seller can propose");
        escrow.proposeSettlement(escrowId, 10 ether, 10 ether);

        // Make payment
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        vm.stopPrank();

        // Test: Invalid distribution (exceeds balance + fee)
        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        vm.prank(depositor);
        vm.expectRevert("Settlement exceeds available balance");
        escrow.proposeSettlement(escrowId, balance, 1); // This will exceed balance after platform fee

        // Make valid proposal
        vm.prank(depositor);
        escrow.proposeSettlement(escrowId, 10 ether, 10 ether);

        // Test: Non-other-party cannot accept
        vm.prank(depositor); // Same person who proposed
        vm.expectRevert("Only the other party can accept");
        escrow.acceptSettlement(escrowId);

        // Test: Random person cannot accept
        vm.prank(makeAddr("random"));
        vm.expectRevert("Only the other party can accept");
        escrow.acceptSettlement(escrowId);

        // Test: Expired settlement
        vm.warp(block.timestamp + 31 days); // After 30 day timeout
        vm.prank(beneficiary);
        vm.expectRevert("Settlement proposal expired");
        escrow.acceptSettlement(escrowId);
    }

    function test_SettlementWhenEscrowNotActive() public {
        uint256 escrowId = _createBasicEscrow();

        // Test proposing when escrow is INACTIVE
        vm.prank(depositor);
        vm.expectRevert("Escrow not active");
        escrow.proposeSettlement(escrowId, 10 ether, 10 ether);
    }

    // ========================================================================
    // ⏰ AUTO EXECUTE TESTS
    // ========================================================================

    function test_AutoExecuteTransaction_ETH() public {
        uint256 escrowId = _createAndStartEscrow();

        // Complete all payments (mas mantém ACTIVE)
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId);
        vm.stopPrank();

        // ✅ Verificar que escrow ainda está ACTIVE após payAllRemaining
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(
            uint256(info.state), uint256(IEscrow.EscrowState.ACTIVE), "Escrow should still be ACTIVE after payments"
        );

        // Try to auto-execute before deadline
        vm.expectRevert("Auto-execute deadline not reached");
        escrow.autoExecuteTransaction(escrowId);

        // Warp to after auto-execute deadline (90 days)
        vm.warp(block.timestamp + 91 days);

        // Store initial state
        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 expectedBeneficiaryAmount = balance - platformFee;

        uint256 initialBeneficiaryBalance = address(beneficiary).balance;
        uint256 initialPendingFees = escrow.pendingFees(owner);

        // Auto-execute (anyone can call)
        vm.expectEmit(true, false, false, true);
        emit AutoExecuted(escrowId, block.timestamp);
        escrow.autoExecuteTransaction(escrowId);

        // Verify final state
        info = escrow.escrows(escrowId);
        assertEq(
            uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete after auto-execute"
        );
        assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Escrow balance should be zero");

        // Verify transfers (funds go to beneficiary by default)
        assertEq(
            address(beneficiary).balance - initialBeneficiaryBalance,
            expectedBeneficiaryAmount,
            "Wrong beneficiary balance after auto-execute"
        );
        assertEq(escrow.pendingFees(owner) - initialPendingFees, platformFee, "Wrong pending fees after auto-execute");
    }

    function test_AutoExecuteTransaction_ERC20() public {
        uint256 escrowId = _createAndStartERC20Escrow();

        // Complete all payments (mas mantém ACTIVE)
        vm.startPrank(depositor);
        token.approve(address(escrow), TOTAL_AMOUNT);
        escrow.payAllRemaining(escrowId);
        vm.stopPrank();

        // ✅ Verificar que escrow ainda está ACTIVE
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(
            uint256(info.state), uint256(IEscrow.EscrowState.ACTIVE), "Escrow should still be ACTIVE after payments"
        );

        // Warp to after auto-execute deadline
        vm.warp(block.timestamp + 91 days);

        // Store initial state
        uint256 balance = escrow.getEscrowBalance(escrowId, address(token));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 expectedBeneficiaryAmount = balance - platformFee;

        uint256 initialBeneficiaryBalance = token.balanceOf(beneficiary);
        uint256 initialOwnerBalance = token.balanceOf(owner);

        // Auto-execute
        escrow.autoExecuteTransaction(escrowId);

        // Verify final state
        info = escrow.escrows(escrowId);
        assertEq(
            uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete after auto-execute"
        );

        // Verify transfers (ERC20 transfers fees directly)
        assertEq(
            token.balanceOf(beneficiary) - initialBeneficiaryBalance,
            expectedBeneficiaryAmount,
            "Wrong beneficiary ERC20 balance after auto-execute"
        );
        assertEq(
            token.balanceOf(owner) - initialOwnerBalance, platformFee, "Wrong owner ERC20 balance after auto-execute"
        );
    }

    function test_AutoExecuteRevertConditions() public {
        // ========================================================================
        // TESTE 1: Escrow em disputa não pode ser auto-executado
        // ========================================================================
        uint256 escrowId1 = _createAndStartEscrow();

        // Test: Escrow disputed
        vm.prank(depositor);
        escrow.openDispute(escrowId1);

        vm.warp(block.timestamp + 91 days);
        // ✅ CORREÇÃO: Agora deve dar o erro correto
        vm.expectRevert("Cannot auto-execute: escrow is disputed");
        escrow.autoExecuteTransaction(escrowId1);

        // ========================================================================
        // TESTE 2: Escrow com pagamentos incompletos
        // ========================================================================
        uint256 escrowId2 = _createAndStartEscrow();

        // Make partial payment only
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: 25 ether}(escrowId2);
        vm.stopPrank();

        vm.warp(block.timestamp + 91 days);
        vm.expectRevert("Cannot auto-execute: payments not complete");
        escrow.autoExecuteTransaction(escrowId2);

        // ========================================================================
        // TESTE 3: Auto-execute antes do prazo
        // ========================================================================
        uint256 escrowId3 = _createAndStartEscrow();

        // Complete all payments
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId3);
        vm.stopPrank();

        // Try auto-execute before deadline (should fail)
        vm.expectRevert("Auto-execute deadline not reached");
        escrow.autoExecuteTransaction(escrowId3);
    }

    // ========================================================================
    // 🚨 EMERGENCY TIMEOUT TESTS
    // ========================================================================

    function test_EmergencyTimeout_RefundToSender() public {
        uint256 escrowId = _createAndStartEscrow();

        // Make some payments
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        vm.stopPrank();

        // Try emergency timeout too early
        vm.warp(block.timestamp + 180 days); // Still too early (need 90 + 180 = 270 days)
        vm.prank(owner);
        vm.expectRevert("Emergency timeout: not enough time passed");
        escrow.emergencyTimeout(escrowId, true, "Test emergency");

        // Warp to valid emergency timeout period (90 + 180 = 270 days)
        vm.warp(block.timestamp + 91 days); // Now 271 days total

        // Store initial state
        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 expectedRefund = balance - platformFee;

        uint256 initialDepositorBalance = address(depositor).balance;
        uint256 initialPendingFees = escrow.pendingFees(owner);

        // Emergency timeout - refund to sender
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit EmergencyTimeout(escrowId, "Emergency refund to buyer", block.timestamp);
        escrow.emergencyTimeout(escrowId, true, "Emergency refund to buyer");

        // Verify final state
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete");
        assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Escrow balance should be zero");

        // Verify refund to depositor
        assertEq(
            address(depositor).balance - initialDepositorBalance,
            expectedRefund,
            "Wrong depositor balance after emergency timeout"
        );
        assertEq(
            escrow.pendingFees(owner) - initialPendingFees, platformFee, "Wrong pending fees after emergency timeout"
        );
    }

    function test_EmergencyTimeout_PayToReceiver() public {
        uint256 escrowId = _createAndStartERC20Escrow();

        // Make payments
        vm.startPrank(depositor);
        token.approve(address(escrow), TOTAL_AMOUNT);
        escrow.payInstallmentERC20(escrowId, 50 ether);
        vm.stopPrank();

        // Warp to emergency timeout period
        vm.warp(block.timestamp + 271 days);

        // Store initial state
        uint256 balance = escrow.getEscrowBalance(escrowId, address(token));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 expectedPayment = balance - platformFee;

        uint256 initialBeneficiaryBalance = token.balanceOf(beneficiary);
        uint256 initialOwnerBalance = token.balanceOf(owner);

        // Emergency timeout - pay to receiver
        vm.prank(owner);
        escrow.emergencyTimeout(escrowId, false, "Emergency payment to seller");

        // Verify payment to beneficiary (ERC20 transfers fees directly)
        assertEq(
            token.balanceOf(beneficiary) - initialBeneficiaryBalance,
            expectedPayment,
            "Wrong beneficiary ERC20 balance after emergency timeout"
        );
        assertEq(
            token.balanceOf(owner) - initialOwnerBalance,
            platformFee,
            "Wrong owner ERC20 balance after emergency timeout"
        );
    }

    function test_EmergencyTimeoutRevertConditions() public {
        // ========================================================================
        // TESTE 1: Apenas owner pode chamar
        // ========================================================================
        uint256 escrowId1 = _createAndStartEscrow();

        vm.prank(depositor);
        vm.expectRevert();
        escrow.emergencyTimeout(escrowId1, true, "Unauthorized call");

        // ========================================================================
        // TESTE 2: Muito cedo para emergency timeout
        // ========================================================================
        uint256 escrowId2 = _createAndStartEscrow();

        vm.warp(block.timestamp + 89 days);
        vm.prank(owner);
        vm.expectRevert("Emergency timeout: not enough time passed");
        escrow.emergencyTimeout(escrowId2, true, "Too early");

        // ========================================================================
        // TESTE 3: Escrow já completo não pode ter emergency timeout
        // ========================================================================
        uint256 escrowId3 = _createAndStartEscrow();

        // Complete escrow normally via auto-execute
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId3);
        vm.stopPrank();

        // Auto-execute to make it COMPLETE
        vm.warp(block.timestamp + 91 days);
        escrow.autoExecuteTransaction(escrowId3);

        // Try emergency timeout on completed escrow
        vm.warp(block.timestamp + 182 days); // Total: 273 days
        vm.prank(owner);
        vm.expectRevert("Escrow already complete");
        escrow.emergencyTimeout(escrowId3, true, "Already complete");
    }

    // ========================================================================
    // 🔍 TIMEOUT VALIDATION TESTS
    // ========================================================================

    function test_TimeoutInitialization() public {
        uint256 escrowId = _createBasicEscrow();

        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);

        // Verify timeout initialization
        assertEq(info.autoExecuteDeadline, block.timestamp + 90 days, "Wrong auto-execute deadline");
        assertEq(info.settlementDeadline, 0, "Settlement deadline should be zero initially");
        assertEq(info.lastInteraction, block.timestamp, "Wrong last interaction timestamp");
        assertFalse(info.hasSettlementProposal, "Should not have settlement proposal initially");
    }

    function test_LastInteractionUpdate() public {
        uint256 escrowId = _createAndStartEscrow();

        // Make payment and check last interaction update
        vm.startPrank(depositor);
        uint256 beforePayment = block.timestamp;
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        vm.stopPrank();

        // Warp time and make settlement proposal
        vm.warp(block.timestamp + 1 days);
        vm.prank(depositor);
        escrow.proposeSettlement(escrowId, 10 ether, 10 ether);

        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(info.lastInteraction, block.timestamp, "Last interaction should be updated after settlement proposal");
    }

    function test_CompleteWorkflow_WithSettlement() public {
        // Test complete workflow: Create -> Start -> Payments -> Settlement -> Complete
        uint256 escrowId = _createAndStartEscrow();

        // Make partial payments
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        vm.stopPrank();

        // Propose settlement
        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        uint256 platformFee = (balance * PLATFORM_FEE) / 10000;
        uint256 available = balance - platformFee;

        vm.prank(depositor);
        escrow.proposeSettlement(escrowId, available / 2, available / 2);

        // Accept settlement
        vm.prank(beneficiary);
        escrow.acceptSettlement(escrowId);

        // Verify final state
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete");
        assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Balance should be zero");

        // Should be able to return guarantee now
        vm.prank(depositor);
        escrow.returnGuarantee(escrowId, IEscrow.TokenType.ETH, address(0), 0);
    }

    function test_CompleteWorkflow_WithAutoExecute() public {
        // Test complete workflow: Create -> Start -> Payments -> AutoExecute -> Complete
        uint256 escrowId = _createAndStartEscrow();

        // Complete all payments (mantém ACTIVE)
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId);
        vm.stopPrank();

        // ✅ Verificar que ainda está ACTIVE
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.ACTIVE), "Escrow should be ACTIVE after payments");

        // Warp past auto-execute deadline
        vm.warp(block.timestamp + 91 days);

        // Auto-execute
        escrow.autoExecuteTransaction(escrowId);

        // Verify final state
        info = escrow.escrows(escrowId);
        assertEq(
            uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete after auto-execute"
        );

        // Should be able to return guarantee
        vm.prank(depositor);
        escrow.returnGuarantee(escrowId, IEscrow.TokenType.ETH, address(0), 0);
    }

    function test_CompleteWorkflow_WithEmergencyTimeout() public {
        // Test emergency scenario: Create -> Start -> Partial Payments -> Emergency Timeout
        uint256 escrowId = _createAndStartEscrow();

        // Make only partial payments
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: 25 ether}(escrowId);
        vm.stopPrank();

        // Open dispute but don't resolve
        vm.prank(depositor);
        escrow.openDispute(escrowId);

        // Warp to emergency timeout period
        vm.warp(block.timestamp + 271 days);

        // Emergency timeout (owner decision)
        vm.prank(owner);
        escrow.emergencyTimeout(escrowId, true, "Long-standing dispute, refunding buyer");

        // Verify final state
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete");
    }

    // Add events for new functionality
    event SettlementProposed(
        uint256 indexed escrowId, address indexed proposer, uint256 amountToSender, uint256 amountToReceiver
    );
    event SettlementAccepted(uint256 indexed escrowId, address indexed acceptor);
    event AutoExecuted(uint256 indexed escrowId, uint256 timestamp);
    event EmergencyTimeout(uint256 indexed escrowId, string reason, uint256 timestamp);

    // Adicionar teste específico para verificar estado após pagamentos
    function test_PayAllRemaining_KeepsActiveState() public {
        uint256 escrowId = _createAndStartEscrow();

        // Complete all payments
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId);
        vm.stopPrank();

        // ✅ Estado deve permanecer ACTIVE
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(
            uint256(info.state),
            uint256(IEscrow.EscrowState.ACTIVE),
            "Escrow should remain ACTIVE after payAllRemaining"
        );
        assertEq(info.installmentsPaid, info.totalInstallments, "All installments should be paid");

        // Balance deve estar presente
        uint256 balance = escrow.getEscrowBalance(escrowId, address(0));
        assertGt(balance, 0, "Escrow should have balance after payments");
    }

    function test_WithdrawFunds_SetsCompleteState() public {
        uint256 escrowId = _createAndStartEscrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // Depositor makes a payment
        vm.startPrank(depositor);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        vm.stopPrank();

        // Get approvals
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // ✅ Verificar que está ACTIVE antes do withdraw
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.ACTIVE), "Escrow should be ACTIVE before withdraw");

        // Beneficiary withdraws
        vm.prank(beneficiary);
        escrow.withdrawFunds(escrowId);

        // ✅ Verificar que mudou para COMPLETE após withdraw
        info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be COMPLETE after withdraw");
        assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Escrow balance should be 0 after withdrawal");
    }

    function test_GuaranteeReturn_WithConsensus() public {
        uint256 escrowId = _createAndStartEscrow();

        // Complete all payments
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId);
        vm.stopPrank();

        // ✅ NOVO: Dar aprovações para finalizar automaticamente
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        // ✅ Agora o escrow deve estar COMPLETE automaticamente
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(
            uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow should be complete after consensus"
        );

        // ✅ Garantia pode ser resgatada imediatamente
        uint256 initialBalance = address(depositor).balance;
        vm.prank(depositor);
        escrow.returnGuarantee(escrowId, IEscrow.TokenType.ETH, address(0), 0);

        assertEq(address(depositor).balance - initialBalance, 10 ether, "Garantia deve ser liberada imediatamente");
    }

    function test_PayInstallments_AutoComplete() public {
        uint256 escrowId = _createAndStartEscrow();
        uint256 installmentAmount = TOTAL_AMOUNT / INSTALLMENTS;

        // ✅ NOVO: Dar aprovações ANTES dos pagamentos
        vm.prank(depositor);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(beneficiary);
        escrow.setReleaseApproval(escrowId, true);
        vm.prank(escrowOwners[0]);
        escrow.setReleaseApproval(escrowId, true);

        vm.startPrank(depositor);

        // Pay first 3 installments - escrow should remain ACTIVE
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);

        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.ACTIVE), "Should still be ACTIVE");

        // Pay last installment - should auto-complete!
        vm.expectEmit(true, false, false, true);
        emit EscrowAutoCompleted(escrowId, "All payments made and approved");
        escrow.payInstallmentETH{value: installmentAmount}(escrowId);

        info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Should auto-complete after final payment");

        vm.stopPrank();
    }

    function test_AutoExecute_WhenNoConsensus() public {
        uint256 escrowId = _createAndStartEscrow();

        // Complete payments WITHOUT giving approvals
        vm.startPrank(depositor);
        escrow.payAllRemaining{value: TOTAL_AMOUNT}(escrowId);
        vm.stopPrank();

        // ✅ Verificar que permanece ACTIVE (sem aprovações)
        IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.ACTIVE), "Should remain ACTIVE without approvals");

        // Try to auto-execute before deadline
        vm.expectRevert("Auto-execute deadline not reached");
        escrow.autoExecuteTransaction(escrowId);

        // Warp to after deadline
        vm.warp(block.timestamp + 91 days);

        // Auto-execute should work as backup mechanism
        escrow.autoExecuteTransaction(escrowId);

        info = escrow.escrows(escrowId);
        assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Should be complete after auto-execute");
    }

    // Evento para os testes
    event EscrowAutoCompleted(uint256 indexed escrowId, string reason);

// ========================================================================
// 🎓 TESTES DIDÁTICOS E VISUAIS - CENÁRIOS REAIS
// ========================================================================

/**
 * CENARIO: E-COMMERCE COM GARANTIA
 * 
 * ANALOGIA: Ana compra um iPhone de Bruno por R$ 3.000
 * - Pagamento: 3x R$ 1.000 (mensal)  
 * - Garantia: R$ 500 (protecao contra defeitos)
 * - Plataforma: TechEscrow (cobra 2% de taxa)
 * 
 * FLUXO ESPERADO:
 * 1. Bruno cria o escrow (vendedor/árbitro)
 * 2. Ana deposita R$ 500 de garantia 
 * 3. Ana inicia o escrow
 * 4. Ana paga 3 parcelas de R$ 1.000
 * 5. Todos aprovam (produto ok)
 * 6. Bruno saca R$ 2.940 (R$ 3.000 - 2% taxa)
 * 7. Ana recupera R$ 500 de garantia
 */
function test_EcommerceWithGuarantee_HappyPath() public {
    console.log("INICIANDO: Cenario de E-commerce - iPhone R$ 3.000");
    console.log("Ana (Compradora):", depositor);
    console.log("Bruno (Vendedor):", beneficiary);
    console.log("TechEscrow (Plataforma):", escrowOwners[0]);
    console.log("");

    // ETAPA 1: BRUNO CRIA O ESCROW
    console.log("ETAPA 1: Bruno cria escrow para venda do iPhone");
    
    vm.prank(escrowOwners[0]); // Bruno (vendedor) usando plataforma
    IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
        depositor: depositor,           // Ana (compradora)
        beneficiary: beneficiary,       // Bruno (vendedor)
        requiresGuarantee: true,        // Exige garantia para proteger Bruno
        totalAmount: 3000 ether,        // R$ 3.000 (simulando stablecoin)
        totalInstallments: 3,           // 3 parcelas mensais
        paymentIntervalSeconds: 30 days, // Parcelas mensais
        dailyInterestFeeBP: 100,        // 1% ao dia se atrasar
        allowBeneficiaryWithdrawPartial: false, // Bruno nao pode sacar antes do fim
        paymentToken: address(0),       // Pagamento em ETH
        interestModel: IEscrow.InterestModel.SIMPLE, // Juros simples
        useCustomSchedule: false        // Parcelas iguais
    });

    uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));
    console.log("Escrow criado com ID:", escrowId);
    
    IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
    console.log("Estado inicial:", uint256(info.state)); // 0 = INACTIVE
    console.log("Exige garantia:", info.requiresGuarantee);
    console.log("Valor total:", info.totalAmount / 1 ether, "ETH");
    console.log("");

    // ETAPA 2: ANA DEPOSITA GARANTIA
    console.log("ETAPA 2: Ana deposita R$ 500 de garantia");
    console.log("Ana pensa: 'Se o iPhone vier com defeito, eles ja tem como me compensar'");
    
    vm.startPrank(depositor); // Ana
    uint256 guaranteeAmount = 500 ether; // R$ 500 de garantia
    uint256 anaBalanceBefore = address(depositor).balance;
    
    escrow.provideGuarantee{value: guaranteeAmount}(
        escrowId, 
        IEscrow.TokenType.ETH, 
        address(0), 
        0, 
        guaranteeAmount
    );
    
    console.log("Ana gastou:", (anaBalanceBefore - address(depositor).balance) / 1 ether, "ETH");
    //console.log("Garantia depositada:", escrow.escrowGuarantees(escrowId, address(0), uint256(IEscrow.TokenType.ETH), 0) / 1 ether, "ETH");
    
    info = escrow.escrows(escrowId);
    console.log("Garantia foi aceita:", info.isGuaranteeProvided);
    console.log("");

    // ETAPA 3: ANA INICIA O ESCROW
    console.log("ETAPA 3: Ana inicia o escrow (negocio comecou oficialmente!)");
    
    escrow.startEscrow(escrowId);
    
    info = escrow.escrows(escrowId);
    console.log("Estado atual:", uint256(info.state)); // 1 = ACTIVE
    console.log("Iniciado em:", info.startTimestamp);
    console.log("Bruno pensa: 'Otimo! Posso mandar o iPhone pelo correio'");
    console.log("");

    vm.stopPrank(); // Para o prank da Ana

    // ETAPA 4: ANA PAGA AS 3 PARCELAS
    console.log("ETAPA 4: Ana paga as 3 parcelas mensais");
    
    uint256 installmentAmount = 3000 ether / 3; // R$ 1.000 por parcela
    
    vm.startPrank(depositor); // Ana volta a fazer transacoes
    
    // PARCELA 1 - No prazo
    console.log("Parcela 1/3: R$ 1.000 (no prazo)");
    uint256 anaBalanceBeforeP1 = address(depositor).balance;
    escrow.payInstallmentETH{value: installmentAmount}(escrowId);
    console.log("Ana pagou:", (anaBalanceBeforeP1 - address(depositor).balance) / 1 ether, "ETH");
    console.log("Saldo do escrow:", escrow.getEscrowBalance(escrowId, address(0)) / 1 ether, "ETH");
    
    // PARCELA 2 - No prazo (30 dias depois)
    vm.warp(block.timestamp + 30 days);
    console.log("Parcela 2/3: R$ 1.000 (no prazo - 30 dias depois)");
    uint256 anaBalanceBeforeP2 = address(depositor).balance;
    escrow.payInstallmentETH{value: installmentAmount}(escrowId);
    console.log("Ana pagou:", (anaBalanceBeforeP2 - address(depositor).balance) / 1 ether, "ETH");
    console.log("Saldo do escrow:", escrow.getEscrowBalance(escrowId, address(0)) / 1 ether, "ETH");
    
    // PARCELA 3 - Atrasada (vamos simular 5 dias de atraso)
    vm.warp(block.timestamp + 35 days); // 30 + 5 dias = atrasou 5 dias
    console.log("Parcela 3/3: ATRASADA por 5 dias (vai ter juros!)");
    
    (uint256 amountDue, uint256 interest) = escrow.calculateInstallmentWithInterest(escrowId);
    console.log("Valor original da parcela:", installmentAmount / 1 ether, "ETH");
    console.log("Juros por atraso (5 dias x 1%):", interest / 1 ether, "ETH");
    console.log("Total a pagar:", amountDue / 1 ether, "ETH");
    console.log("Ana pensa: 'Eita, esqueci de pagar no prazo! Agora tem juros...'");
    
    uint256 anaBalanceBeforeP3 = address(depositor).balance;
    escrow.payInstallmentETH{value: amountDue}(escrowId);
    console.log("Ana pagou (com juros):", (anaBalanceBeforeP3 - address(depositor).balance) / 1 ether, "ETH");
    console.log("Saldo FINAL do escrow:", escrow.getEscrowBalance(escrowId, address(0)) / 1 ether, "ETH");
    
    info = escrow.escrows(escrowId);
    console.log("Parcelas pagas:", info.installmentsPaid, "/", info.totalInstallments);
    console.log("");

    vm.stopPrank(); // Para o prank da Ana

    // ETAPA 5: TODOS APROVAM (iPhone chegou perfeito!)
    console.log("ETAPA 5: Todos aprovam - iPhone chegou perfeito!");
    console.log("Ana: 'iPhone chegou novo, sem defeitos!'");
    console.log("Bruno: 'Recebi todos os pagamentos, cliente satisfeita!'");
    console.log("TechEscrow: 'Transacao ocorreu sem problemas!'");
    
    // Ana aprova
    vm.prank(depositor);
    escrow.setReleaseApproval(escrowId, true);
    console.log("Ana aprovou o recebimento");
    
    // Bruno aprova  
    vm.prank(beneficiary);
    escrow.setReleaseApproval(escrowId, true);
    console.log("Bruno aprovou a entrega");
    
    // TechEscrow aprova
    vm.prank(escrowOwners[0]);
    escrow.setReleaseApproval(escrowId, true);
    console.log("TechEscrow aprovou a transacao");
    
    // VERIFICAR SE AUTO-COMPLETOU
    info = escrow.escrows(escrowId);
    if (info.state == IEscrow.EscrowState.COMPLETE) {
        console.log("ESCROW AUTO-COMPLETOU! (Consenso total atingido)");
    }
    console.log("");

    // ETAPA 6: BRUNO SACA O DINHEIRO
    console.log("ETAPA 6: Bruno saca seus R$ 3.000 (menos 2% de taxa)");
    
    uint256 escrowBalance = escrow.getEscrowBalance(escrowId, address(0));
    uint256 expectedFee = (escrowBalance * PLATFORM_FEE) / 10000; // 2%
    uint256 expectedNetForBruno = escrowBalance - expectedFee;
    
    console.log("Saldo total do escrow:", escrowBalance / 1 ether, "ETH");
    console.log("Taxa da plataforma (2%):", expectedFee / 1 ether, "ETH");
    console.log("Bruno vai receber:", expectedNetForBruno / 1 ether, "ETH");
    
    uint256 brunoBalanceBefore = address(beneficiary).balance;
    uint256 platformFeesBefore = escrow.pendingFees(owner);
    
    vm.prank(beneficiary);
    escrow.withdrawFunds(escrowId);
    
    uint256 brunoReceived = address(beneficiary).balance - brunoBalanceBefore;
    uint256 platformFeesAfter = escrow.pendingFees(owner);
    
    console.log("Bruno recebeu:", brunoReceived / 1 ether, "ETH");
    console.log("Taxa pendente para plataforma:", (platformFeesAfter - platformFeesBefore) / 1 ether, "ETH");
    console.log("Bruno pensa: 'Perfeito! Recebi R$ 2.940 limpos'");
    
    // Verificar que estado mudou para COMPLETE
    info = escrow.escrows(escrowId);
    assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow deve estar COMPLETE apos withdraw");
    console.log("Estado final:", uint256(info.state)); // 3 = COMPLETE
    console.log("");

    // ETAPA 7: ANA RECUPERA A GARANTIA
    console.log("ETAPA 7: Ana recupera sua garantia de R$ 500");
    console.log("Ana pensa: 'Agora posso pegar minha garantia de volta!'");
    
    uint256 anaBalanceBeforeGuarantee = address(depositor).balance;
    
    vm.prank(depositor);
    escrow.returnGuarantee(escrowId, IEscrow.TokenType.ETH, address(0), 0);
    
    uint256 guaranteeReturned = address(depositor).balance - anaBalanceBeforeGuarantee;
    
    console.log("Ana recuperou:", guaranteeReturned / 1 ether, "ETH de garantia");
    console.log("Transacao finalizada com sucesso!");
    console.log("");

    // RESUMO FINAL
    console.log("RESUMO FINAL DA TRANSACAO:");
    console.log("Bruno recebeu:", brunoReceived / 1 ether, "ETH (R$ 2.940)");
    console.log("Ana recuperou:", guaranteeReturned / 1 ether, "ETH de garantia");
    console.log("Plataforma recebeu:", (platformFeesAfter - platformFeesBefore) / 1 ether, "ETH de taxa");
    console.log("Todos sairam satisfeitos!");
    
    // VALIDACOES FINAIS
    assertEq(brunoReceived, expectedNetForBruno, "Bruno deve receber valor correto");
    assertEq(guaranteeReturned, guaranteeAmount, "Ana deve recuperar garantia completa");
    assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Saldo do escrow deve ser zero");
}

/**
 * CENARIO: FREELANCE COM DISPUTA
 * 
 * ANALOGIA: Carlos contrata Diana para criar um site por R$ 5.000
 * - Pagamento: 5x R$ 1.000 (quinzenal)
 * - Garantia: R$ 1.000 (protecao)
 * - PROBLEMA: Diana entrega site com bugs, Carlos reclama
 * 
 * FLUXO ESPERADO:
 * 1. Escrow criado e iniciado
 * 2. Carlos paga 3 parcelas (R$ 3.000) 
 * 3. Diana entrega site com problemas
 * 4. Carlos abre disputa
 * 5. Arbitro decide: 60% para Carlos, 40% para Diana
 * 6. Garantia volta para Carlos
 */
function test_FreelanceWithDispute_RealisticScenario() public {
    console.log("INICIANDO: Cenario Freelance - Site R$ 5.000 COM DISPUTA");
    console.log("Carlos (Cliente):", depositor);
    console.log("Diana (Freelancer):", beneficiary);
    console.log("FreelanceEscrow (Plataforma):", escrowOwners[0]);
    console.log("");

    // CRIACAO DO ESCROW
    vm.prank(escrowOwners[0]);
    IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
        depositor: depositor,           // Carlos (cliente)
        beneficiary: beneficiary,       // Diana (freelancer)
        requiresGuarantee: true,        // Garantia obrigatoria
        totalAmount: 5000 ether,        // R$ 5.000 pelo site
        totalInstallments: 5,           // 5 parcelas
        paymentIntervalSeconds: 15 days, // Parcelas quinzenais
        dailyInterestFeeBP: 200,        // 2% ao dia (mais rigoroso)
        allowBeneficiaryWithdrawPartial: false,
        paymentToken: address(0),
        interestModel: IEscrow.InterestModel.SIMPLE,
        useCustomSchedule: false
    });

    uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));
    console.log("Escrow criado para desenvolvimento do site");
    console.log("");

    // GARANTIA E INICIO
    vm.startPrank(depositor);
    uint256 guaranteeAmount = 1000 ether; // R$ 1.000 de garantia
    escrow.provideGuarantee{value: guaranteeAmount}(escrowId, IEscrow.TokenType.ETH, address(0), 0, guaranteeAmount);
    escrow.startEscrow(escrowId);
    console.log("Carlos depositou R$ 1.000 de garantia");
    console.log("Projeto iniciado - Diana pode comecar o desenvolvimento");
    console.log("");

    // PAGAMENTOS PARCIAIS (3 de 5 parcelas)
    uint256 installmentAmount = 1000 ether; // R$ 1.000 por parcela
    
    console.log("Carlos paga as primeiras 3 parcelas...");
    
    // Parcela 1
    escrow.payInstallmentETH{value: installmentAmount}(escrowId);
    console.log("Parcela 1/5 paga: R$ 1.000");
    
    // Parcela 2 (15 dias depois)
    vm.warp(block.timestamp + 15 days);
    escrow.payInstallmentETH{value: installmentAmount}(escrowId);
    console.log("Parcela 2/5 paga: R$ 1.000");
    
    // Parcela 3 (mais 15 dias)
    vm.warp(block.timestamp + 15 days);
    escrow.payInstallmentETH{value: installmentAmount}(escrowId);
    console.log("Parcela 3/5 paga: R$ 1.000");
    
    console.log("Total pago ate agora:", escrow.getEscrowBalance(escrowId, address(0)) / 1 ether, "ETH");
    console.log("Diana pensa: 'Ja recebi R$ 3.000, vou entregar a primeira versao'");
    console.log("");

    // PROBLEMA: DIANA ENTREGA SITE COM BUGS
    console.log("PROBLEMA: Diana entrega site mas esta cheio de bugs!");
    console.log("Carlos: 'Esse site nao funciona! Tem bugs em toda parte!'");
    console.log("Diana: 'Sao so alguns bugs menores, vou corrigir'");
    console.log("Carlos: 'Nao, isso esta muito ruim. Vou abrir uma disputa!'");
    console.log("");

    // CARLOS ABRE DISPUTA
    console.log("Carlos abre disputa no escrow");
    escrow.openDispute(escrowId);
    
    IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
    console.log("Estado mudou para DISPUTED:", uint256(info.state)); // 2 = DISPUTED
    console.log("Disputa aberta por:", info.disputedBy);
    console.log("");

    vm.stopPrank();

    // ARBITRO ANALISA E TODOS APROVAM A RESOLUCAO
    console.log("Arbitro analisa o caso...");
    console.log("Evidencias:");
    console.log("- Site foi entregue (Diana trabalhou)");
    console.log("- Mas tem muitos bugs (Carlos tem razao)");
    console.log("- Diana cooperou durante o processo");
    console.log("Decisao: 60% para Carlos (reembolso), 40% para Diana (trabalho parcial)");
    console.log("");

    // Todos aprovam a resolucao proposta
    vm.prank(depositor);
    escrow.setReleaseApproval(escrowId, true);
    console.log("Carlos aprovou a resolucao");
    
    vm.prank(beneficiary);
    escrow.setReleaseApproval(escrowId, true);
    console.log("Diana aprovou a resolucao");
    
    vm.prank(escrowOwners[0]);
    escrow.setReleaseApproval(escrowId, true);
    console.log("Arbitro aprovou a resolucao");
    console.log("");

    // RESOLUCAO DA DISPUTA
    uint256 totalBalance = escrow.getEscrowBalance(escrowId, address(0));
    uint256 platformFee = (totalBalance * PLATFORM_FEE) / 10000;
    uint256 availableForDistribution = totalBalance - platformFee;
    
    uint256 amountToCarlos = (availableForDistribution * 60) / 100; // 60%
    uint256 amountToDiana = availableForDistribution - amountToCarlos; // 40%
    
    console.log("DISTRIBUICAO DOS FUNDOS:");
    console.log("Total no escrow:", totalBalance / 1 ether, "ETH");
    console.log("Taxa da plataforma:", platformFee / 1 ether, "ETH");
    console.log("Disponivel para distribuir:", availableForDistribution / 1 ether, "ETH");
    console.log("Carlos recebera (60%):", amountToCarlos / 1 ether, "ETH");
    console.log("Diana recebera (40%):", amountToDiana / 1 ether, "ETH");
    console.log("");

    uint256 carlosBalanceBefore = address(depositor).balance;
    uint256 dianaBalanceBefore = address(beneficiary).balance;
    uint256 platformFeesBefore = escrow.pendingFees(owner);

    vm.prank(escrowOwners[0]);
    escrow.resolveDispute(escrowId, amountToCarlos, amountToDiana, "Carlos recebe 60% - site com muitos bugs. Diana recebe 40% - trabalho parcial realizado.");

    uint256 carlosReceived = address(depositor).balance - carlosBalanceBefore;
    uint256 dianaReceived = address(beneficiary).balance - dianaBalanceBefore;
    uint256 platformFeesReceived = escrow.pendingFees(owner) - platformFeesBefore;

    console.log("RESULTADO DA DISPUTA:");
    console.log("Carlos recebeu:", carlosReceived / 1 ether, "ETH (reembolso parcial)");
    console.log("Diana recebeu:", dianaReceived / 1 ether, "ETH (pagamento parcial)");
    console.log("Plataforma recebeu:", platformFeesReceived / 1 ether, "ETH (taxa)");
    console.log("");

    // CARLOS RECUPERA A GARANTIA
    console.log("Carlos recupera sua garantia...");
    
    info = escrow.escrows(escrowId);
    assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow deve estar COMPLETE");
    
    uint256 carlosBalanceBeforeGuarantee = address(depositor).balance;
    
    vm.prank(depositor);
    escrow.returnGuarantee(escrowId, IEscrow.TokenType.ETH, address(0), 0);
    
    uint256 guaranteeReturned = address(depositor).balance - carlosBalanceBeforeGuarantee;
    
    console.log("Carlos recuperou garantia:", guaranteeReturned / 1 ether, "ETH");
    console.log("");

    // RESUMO FINAL DETALHADO
    console.log("RESUMO FINAL - DISPUTA RESOLVIDA:");
    console.log("Carlos pagou:", 3000 ether / 1 ether, "ETH");
    console.log("Carlos recuperou:", (carlosReceived + guaranteeReturned) / 1 ether, "ETH");
    console.log("Perda liquida de Carlos:", (3000 ether - carlosReceived - guaranteeReturned) / 1 ether, "ETH");
    console.log("Diana trabalhou e recebeu:", dianaReceived / 1 ether, "ETH");
    console.log("Plataforma mediou e recebeu:", platformFeesReceived / 1 ether, "ETH");
    console.log("Justica: Ambas as partes sairam com algo justo");
    console.log("Disputa resolvida de forma equilibrada!");

    // VALIDACOES
    assertEq(carlosReceived, amountToCarlos, "Carlos deve receber 60%");
    assertEq(dianaReceived, amountToDiana, "Diana deve receber 40%");
    assertEq(guaranteeReturned, guaranteeAmount, "Garantia deve ser devolvida integralmente");
}

/**
 * CENARIO: ACORDO AMIGAVEL (SETTLEMENT)
 * 
 * ANALOGIA: Eduardo compra equipamento de Fernanda por R$ 2.000
 * - Pagamento: 4x R$ 500 (semanal)
 * - Eduardo paga 2 parcelas (R$ 1.000)
 * - Equipamento chega mas com pequeno defeito
 * - Ao inves de disputa, fazem acordo: 50% desconto para Eduardo
 * 
 * FLUXO:
 * 1. Escrow normal ate 2 pagamentos
 * 2. Problema surge, mas resolvem amigavelmente  
 * 3. Eduardo propoe settlement: R$ 700 para ele, R$ 300 para Fernanda
 * 4. Fernanda aceita o acordo
 * 5. Fundos distribuidos automaticamente
 */
function test_AmicableSettlement_RealisticScenario() public {
    console.log("INICIANDO: Cenario Acordo Amigavel - Equipamento R$ 2.000");
    console.log("Eduardo (Comprador):", depositor);
    console.log("Fernanda (Vendedora):", beneficiary);
    console.log("EquipEscrow (Plataforma):", escrowOwners[0]);
    console.log("");

    // CRIACAO E INICIO
    vm.prank(escrowOwners[0]);
    IEscrow.EscrowParams memory params = IEscrow.EscrowParams({
        depositor: depositor,
        beneficiary: beneficiary,
        requiresGuarantee: false,       // Sem garantia neste caso
        totalAmount: 2000 ether,        // R$ 2.000
        totalInstallments: 4,           // 4 parcelas semanais
        paymentIntervalSeconds: 7 days, // Semanal
        dailyInterestFeeBP: 150,        // 1.5% ao dia
        allowBeneficiaryWithdrawPartial: false,
        paymentToken: address(0),
        interestModel: IEscrow.InterestModel.SIMPLE,
        useCustomSchedule: false
    });

    uint256 escrowId = escrow.createEscrow(params, new IEscrow.InstallmentDetail[](0));

    vm.prank(escrowOwners[0]);
    IEscrow.EscrowParams memory params2 = IEscrow.EscrowParams({
        depositor: depositor,
        beneficiary: beneficiary,
        requiresGuarantee: false,       // Sem garantia neste caso
        totalAmount: 2000 ether,        // R$ 2.000
        totalInstallments: 4,           // 4 parcelas semanais
        paymentIntervalSeconds: 7 days, // Semanal
        dailyInterestFeeBP: 150,        // 1.5% ao dia
        allowBeneficiaryWithdrawPartial: false,
        paymentToken: address(0),
        interestModel: IEscrow.InterestModel.SIMPLE,
        useCustomSchedule: false
    });

    uint256 escrowId2 = escrow.createEscrow(params2, new IEscrow.InstallmentDetail[](0));
    assertEq(escrowId2, 2, "Escrow ID deve ser 2");
    
    vm.startPrank(depositor);
    escrow.startEscrow(escrowId); // Sem garantia, pode iniciar direto
    console.log("Compra de equipamento iniciada (sem garantia)");
    console.log("");

    // PAGAMENTOS PARCIAIS
    uint256 installmentAmount = 500 ether; // R$ 500 por parcela
    
    console.log("Eduardo paga as primeiras 2 parcelas...");
    
    // Parcela 1
    escrow.payInstallmentETH{value: installmentAmount}(escrowId);
    console.log("Semana 1: R$ 500 pagos");
    
    // Parcela 2
    vm.warp(block.timestamp + 7 days);
    escrow.payInstallmentETH{value: installmentAmount}(escrowId);
    console.log("Semana 2: R$ 500 pagos");
    
    console.log("Total pago:", escrow.getEscrowBalance(escrowId, address(0)) / 1 ether, "ETH");
    console.log("");

    // PROBLEMA SURGE
    console.log("Fernanda envia o equipamento...");
    console.log("Eduardo recebe e testa:");
    console.log("Eduardo: 'O equipamento funciona, mas tem um risco pequeno na carcaca'");
    console.log("Eduardo: 'Nao e grave, mas nao estava na descricao'");
    console.log("Eduardo liga para Fernanda...");
    console.log("Fernanda: 'Desculpa! Nem tinha visto esse risco. Que tal um desconto?'");
    console.log("Eduardo: 'Legal! Vamos fazer um acordo justo para os dois'");
    console.log("");

    // EDUARDO PROPOE SETTLEMENT
    console.log("Eduardo propoe um acordo amigavel...");
    
    uint256 currentBalance = escrow.getEscrowBalance(escrowId, address(0)); // 1000 ETH
    uint256 platformFee = (currentBalance * PLATFORM_FEE) / 10000; // 2%
    uint256 availableForDistribution = currentBalance - platformFee; // 980 ETH
    
    // Eduardo propoe ficar com 70% (devido ao defeito), Fernanda 30%
    uint256 proposedToEduardo = (availableForDistribution * 70) / 100; // 686 ETH
    uint256 proposedToFernanda = availableForDistribution - proposedToEduardo; // 294 ETH
    
    console.log("Eduardo propoe divisao:");
    console.log("Total disponivel:", availableForDistribution / 1 ether, "ETH");
    console.log("Eduardo ficaria com (70%):", proposedToEduardo / 1 ether, "ETH");
    console.log("Fernanda ficaria com (30%):", proposedToFernanda / 1 ether, "ETH");
    console.log("Eduardo: 'Assim eu pago so 300 pelo equipamento com defeito'");
    
    escrow.proposeSettlement(escrowId, proposedToEduardo, proposedToFernanda);
    
    IEscrow.EscrowInfo memory info = escrow.escrows(escrowId);
    console.log("Proposta de acordo enviada");
    console.log("Fernanda tem 30 dias para aceitar");
    console.log("Prazo ate:", info.settlementDeadline);
    console.log("");

    vm.stopPrank();

    // FERNANDA PONDERA E ACEITA
    console.log("Fernanda pondera a proposta...");
    console.log("Fernanda: 'R$ 294 por um equipamento com defeito e justo'");
    console.log("Fernanda: 'Melhor que uma disputa demorada'");
    console.log("Fernanda: 'E mantenho a reputacao boa na plataforma'");
    console.log("");

    uint256 eduardoBalanceBefore = address(depositor).balance;
    uint256 fernandaBalanceBefore = address(beneficiary).balance;
    uint256 platformFeesBefore = escrow.pendingFees(owner);

    vm.prank(beneficiary);
    escrow.acceptSettlement(escrowId);

    uint256 eduardoReceived = address(depositor).balance - eduardoBalanceBefore;
    uint256 fernandaReceived = address(beneficiary).balance - fernandaBalanceBefore;
    uint256 platformFeesReceived = escrow.pendingFees(owner) - platformFeesBefore;

    console.log("ACORDO ACEITO E EXECUTADO AUTOMATICAMENTE!");
    console.log("");

    // RESULTADO DO SETTLEMENT
    console.log("RESULTADO DO ACORDO:");
    console.log("Eduardo recebeu:", eduardoReceived / 1 ether, "ETH (reembolso por defeito)");
    console.log("Fernanda recebeu:", fernandaReceived / 1 ether, "ETH (pagamento pelo equipamento)");
    console.log("Plataforma recebeu:", platformFeesReceived / 1 ether, "ETH (taxa de servico)");
    console.log("");

    // ANALISE FINANCEIRA
    console.log("ANALISE FINANCEIRA FINAL:");
    console.log("Eduardo pagou:", 1000 ether / 1 ether, "ETH");
    console.log("Eduardo recebeu de volta:", eduardoReceived / 1 ether, "ETH");
    console.log("Custo real do equipamento:", (1000 ether - eduardoReceived) / 1 ether, "ETH");
    console.log("Fernanda vendeu por:", fernandaReceived / 1 ether, "ETH (com desconto por defeito)");
    console.log("Ambos evitaram disputa longa e custosa");
    console.log("Resolucao rapida e amigavel!");
    console.log("");

    // VERIFICACAO DO ESTADO FINAL
    info = escrow.escrows(escrowId);
    assertEq(uint256(info.state), uint256(IEscrow.EscrowState.COMPLETE), "Escrow deve estar COMPLETE");
    assertFalse(info.hasSettlementProposal, "Proposta deve ser limpa apos execucao");
    assertEq(escrow.getEscrowBalance(escrowId, address(0)), 0, "Saldo deve ser zero");
    
    console.log("Estado do escrow: COMPLETE");
    console.log("Acordo executado com sucesso!");
    console.log("Moral: Nem sempre e preciso disputar - acordos podem ser melhores!");

    // VALIDACOES FINAIS
    assertEq(eduardoReceived, proposedToEduardo, "Eduardo deve receber valor acordado");
    assertEq(fernandaReceived, proposedToFernanda, "Fernanda deve receber valor acordado");
}
}


