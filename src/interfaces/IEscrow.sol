// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IEscrow
 * @notice Interface for the main Escrow contract
 */
interface IEscrow {
    // Add struct definition before using it
    struct InstallmentDetail {
        uint256 dueDate; // Timestamp de vencimento
        uint256 amount; // Valor da parcela
        bool paid; // Status de pagamento
    }

    // Add EscrowInfo struct definition
    struct EscrowInfo {
        // PARTES ENVOLVIDAS
        address depositor; // 👤 Comprador
        address beneficiary; // 👤 Vendedor
        address escrowOwner; // 👤 Árbitro/Criador
        // STATUS E ESTADO
        EscrowState state; // 📊 Estado atual
        bool requiresGuarantee; // 🛡️ Exige garantia?
        bool isGuaranteeProvided; // ✅ Garantia foi dada?
        // CONFIGURAÇÃO FINANCEIRA
        address paymentToken; // 💰 Token de pagamento
        uint256 totalAmount; // 💰 Valor total
        uint256 totalInstallments; // 📊 Total de parcelas
        uint256 installmentsPaid; // ✅ Parcelas pagas
        // CRONOGRAMA E JUROS
        uint256 paymentIntervalSeconds; // ⏰ Intervalo entre parcelas
        uint256 dailyInterestFeeBP; // 📈 Taxa de juros diária
        InterestModel interestModel; // 🧮 Modelo de juros
        // TIMESTAMPS
        uint256 startTimestamp; // 🚀 Início da custódia
        uint256 lastPaymentTimestamp; // 💳 Último pagamento
        uint256 autoExecuteDeadline; // ⏰ Prazo para auto-execução
        uint256 settlementDeadline; // 🤝 Prazo para acordo
        uint256 lastInteraction; // 👋 Última interação
        // APROVAÇÕES
        bool depositorApproved; // ✅ Comprador aprovou
        bool beneficiaryApproved; // ✅ Vendedor aprovou
        bool escrowOwnerApproved; // ✅ Árbitro aprovou
        bool allowBeneficiaryWithdrawPartial; // 💸 Permite saque parcial
        // DISPUTAS
        bool isDisputed; // ⚔️ Em disputa?
        address disputedBy; // 👤 Quem disputou
        // CONFIGURAÇÕES
        bool useCustomSchedule; // ⚙️ Cronograma personalizado?
        // SETTLEMENT (ACORDOS)
        bool hasSettlementProposal; // 🤝 Tem proposta de acordo?
        uint256 settlementAmountToSender; // 💰 Quanto para comprador
        uint256 settlementAmountToReceiver; // 💰 Quanto para vendedor
        address settlementProposedBy; // 👤 Quem propôs
    }

    // Structs
    struct EscrowParams {
        address depositor; // 👤 Comprador
        address beneficiary; // 👤 Vendedor
        bool requiresGuarantee; // 🛡️ Exige garantia?
        uint256 totalAmount; // 💰 Valor total
        uint256 totalInstallments; // 📊 Número de parcelas
        uint256 paymentIntervalSeconds; // ⏰ Intervalo entre parcelas
        uint256 dailyInterestFeeBP; // 📈 Taxa de juros diária
        bool allowBeneficiaryWithdrawPartial; // 💸 Permite saque parcial?
        address paymentToken; // 💰 Token de pagamento
        InterestModel interestModel; // 🧮 Modelo de juros
        bool useCustomSchedule; // ⚙️ Cronograma personalizado?
    }

    // Enums
    enum TokenType {
        ERC20, // 🪙 Tokens fungíveis
        ERC721, // 🖼️ NFTs únicos
        ERC1155, // 📦 Tokens semi-fungíveis
        ETH // ⚡ Ethereum nativo

    }
    enum EscrowState {
        INACTIVE, // 😴 Criada, aguardando início
        ACTIVE, // 🏃 Funcionando normalmente
        DISPUTED, // ⚔️ Em conflito
        COMPLETE // ✅ Finalizada

    }
    enum InterestModel {
        SIMPLE, // 📈 Juros simples
        COMPOUND // 📈📈 Juros compostos

    }

    // Events
    // 👤 Comprador
    // 👤 Vendedor
    // 🛡️ Exige garantia?
    // 💰 Valor total
    // 📊 Parcelas
    // 💰 Token de pagamento
    event EscrowCreated( // 🆔 ID da custódia
        uint256 indexed escrowId,
        address indexed depositor,
        address indexed beneficiary,
        bool requiresGuarantee,
        uint256 totalAmount,
        uint256 totalInstallments,
        address paymentToken
    );

    event EscrowStarted( // 🆔 ID da custódia
        // 👤 Comprador
        // 👤 Vendedor
    uint256 indexed escrowId, address indexed depositor, address indexed beneficiary);

    // EVENTOS DE GARANTIAS
    // 👤 Quem forneceu
    // 🏷️ Tipo de token
    // 📍 Endereço do token
    // 🆔 ID do token (NFTs)
    // 💰 Quantidade
    event GuaranteeProvided( // 🆔 ID da custódia
        uint256 indexed escrowId,
        address indexed depositor,
        TokenType tokenType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    );

    // 👤 Comprador
    // 🏷️ Tipos de tokens
    // 📍 Endereços dos tokens
    // 🆔 IDs dos tokens
    // 💰 Quantidades
    event MultipleGuaranteesProvided( // 🆔 ID da custódia
        uint256 indexed escrowId,
        address indexed buyer,
        TokenType[] tokenTypes,
        address[] tokenAddresses,
        uint256[] tokenIds,
        uint256[] amounts
    );

    event GuaranteeReturned( // 🆔 ID da custódia
        // 👤 Comprador
        // 💰 Valor devolvido
    uint256 indexed escrowId, address indexed buyer, uint256 netAmount);

    // EVENTOS DE PAGAMENTOS
    event InstallmentPaid( // 🆔 ID da custódia
        // 📊 Número da parcela
        // 💰 Valor pago
        // 📈 Juros cobrados
    uint256 indexed escrowId, uint256 installmentNumber, uint256 amountPaid, uint256 interest);

    // EVENTOS DE APROVAÇÕES E SAQUES
    event ApprovalUpdated( // 🆔 ID da custódia
        // 👤 Quem aprovou
        // ✅ Aprovado ou não
    uint256 indexed escrowId, address indexed approver, bool isApproved);

    event FundsWithdrawn( // 🆔 ID da custódia
        // 👤 Vendedor
        // 💰 Token sacado
        // 💰 Valor líquido
    uint256 indexed escrowId, address indexed seller, address token, uint256 netAmount);

    event PartialWithdrawal( // 🆔 ID da custódia
        // 👤 Vendedor
        // 💰 Token sacado
        // 💰 Valor sacado
    uint256 indexed escrowId, address indexed seller, address token, uint256 netAmount);

    // EVENTOS DE DISPUTAS
    event DisputeOpened( // 🆔 ID da custódia
        // 👤 Quem abriu a disputa
    uint256 indexed escrowId, address indexed raisedBy);

    // 👤 Quem resolveu
    // 📝 Justificativa
    // ⏰ Quando foi resolvido
    // 👤 Árbitro
    // 📝 Fundamentação
    event DisputeResolved( // 🆔 ID da custódia
        uint256 indexed escrowId,
        address indexed resolver,
        string resolution,
        uint256 timestamp,
        address arbitrator,
        string rationale
    );

    // EVENTOS DE SETTLEMENT (ACORDOS)
    event SettlementProposed( // 🆔 ID da custódia
        // 👤 Quem propôs
        // 💰 Para o comprador
        // 💰 Para o vendedor
    uint256 indexed escrowId, address indexed proposer, uint256 amountToSender, uint256 amountToReceiver);

    event SettlementAccepted( // 🆔 ID da custódia
        // 👤 Quem aceitou
    uint256 indexed escrowId, address indexed acceptor);

    // EVENTOS DE AUTOMAÇÃO
    event EscrowAutoCompleted( // 🆔 ID da custódia
        // 📝 Motivo da finalização
    uint256 indexed escrowId, string reason);

    event AutoExecuted( // 🆔 ID da custódia
        // ⏰ Quando foi executado
    uint256 indexed escrowId, uint256 timestamp);

    // EVENTOS DE EMERGÊNCIA
    event EmergencyTimeout( // 🆔 ID da custódia
        // 📝 Motivo da intervenção
        // ⏰ Quando ocorreu
    uint256 indexed escrowId, string reason, uint256 timestamp);

    // EVENTOS ADMINISTRATIVOS
    event FeesWithdrawn( // 👤 Proprietário
        // 💰 Valor sacado
    address indexed owner, uint256 amount);

    // FUNÇÕES DE CRIAÇÃO E ATIVAÇÃO
    function createEscrow(EscrowParams calldata params, InstallmentDetail[] calldata customInstallments)
        external
        returns (uint256);
    function startEscrow(uint256 escrowId) external;

    function provideGuarantee(
        uint256 escrowId,
        TokenType tokenType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    ) external payable;
    function provideMultipleGuarantees(
        uint256 escrowId,
        TokenType[] calldata tokenTypes,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external payable;
    function returnGuarantee(uint256 _escrowId, TokenType _type, address _tokenAddress, uint256 _tokenId) external;

    // FUNÇÕES DE PAGAMENTOS
    function payInstallmentETH(uint256 escrowId) external payable;
    function payInstallmentERC20(uint256 escrowId, uint256 amount) external;
    function payAllRemaining(uint256 _escrowId) external payable;

    // FUNÇÕES DE APROVAÇÕES E SAQUES
    function setReleaseApproval(uint256 _escrowId, bool _approval) external;
    function withdrawFunds(uint256 _escrowId) external;
    function partialWithdraw(uint256 _escrowId, uint256 _amount) external;

    // FUNÇÕES DE DISPUTAS
    function openDispute(uint256 _escrowId) external;
    function resolveDispute(
        uint256 _escrowId,
        uint256 amountToBuyer,
        uint256 amountToSeller,
        string calldata resolution
    ) external;

    // FUNÇÕES ADMINISTRATIVAS
    function setEscrowOwnersApproval(address[] memory _escrowOwners, bool _approval) external;
    function withdrawFees() external;

    // FUNÇÕES DE CONSULTA
    function escrows(uint256 _escrowId) external view returns (EscrowInfo memory);
    function escrowInstallments(uint256 _escrowId, uint256 _installmentNumber)
        external
        view
        returns (InstallmentDetail memory);
    function getEscrowBalance(uint256 _escrowId, address _token) external view returns (uint256);
    function getRemainingInstallments(uint256 _escrowId) external view returns (uint256);
    function calculateInstallmentWithInterest(uint256 _escrowId)
        external
        view
        returns (uint256 amountDue, uint256 interest);
    function getEscrowInfo(uint256 _escrowId) external view returns (EscrowInfo memory);
}
