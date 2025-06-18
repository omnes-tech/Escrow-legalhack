// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IEscrowErrors
 * @notice Custom errors for the Escrow system
 */
interface IEscrowErrors {
    error InvalidDepositor();
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidInstallments();
    error InvalidInterestRate();
    error InvalidFee();
    error UnauthorizedCaller();
    error EscrowNotActive();
    error EscrowAlreadyActive();
    error EscrowDisputed();
    error EscrowNotInDispute();
    error GuaranteeRequired();
    error GuaranteeAlreadyProvided();
    error TokenNotAllowed();
    error InsufficientPayment();
    error TransferFailed();
    error AllInstallmentsPaid();
    error NoBalanceToWithdraw();
    error NotAllPartiesApproved();
    error InvalidEscrowState();
    error PartialWithdrawalNotAllowed();
    error AmountNotDivisible();
    error InvalidPartialAmount();
    error UnsupportedTokenType();
    error InvalidDistribution();
    error InvalidCaller();
    error InvalidInstallment();
    error ArrayLengthMismatch();
    error InvalidEthAmount(uint256 provided, uint256 required);
}