// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IEscrow
 * @notice Interface for the main Escrow contract
 */
interface IEscrow {
    // Add struct definition before using it
    struct InstallmentDetail {
        uint256 dueDate;    // Timestamp de vencimento
        uint256 amount;     // Valor da parcela
        bool paid;          // Status de pagamento
    }

    // Add EscrowInfo struct definition
    struct EscrowInfo {
        // PARTES ENVOLVIDAS
        address depositor;              // 👤 Comprador
        address beneficiary;            // 👤 Vendedor
        address escrowOwner;            // 👤 Árbitro/Criador
        
        // STATUS E ESTADO
        EscrowState state;              // 📊 Estado atual
        bool requiresGuarantee;         // 🛡️ Exige garantia?
        bool isGuaranteeProvided;       // ✅ Garantia foi dada?
        
        // CONFIGURAÇÃO FINANCEIRA
        address paymentToken;           // 💰 Token de pagamento
        uint256 totalAmount;            // 💰 Valor total
        uint256 totalInstallments;      // 📊 Total de parcelas
        uint256 installmentsPaid;       // ✅ Parcelas pagas
        
        // CRONOGRAMA E JUROS
        uint256 paymentIntervalSeconds; // ⏰ Intervalo entre parcelas
        uint256 dailyInterestFeeBP;     // 📈 Taxa de juros diária
        InterestModel interestModel;    // 🧮 Modelo de juros
        
        // TIMESTAMPS
        uint256 startTimestamp;         // 🚀 Início da custódia
        uint256 lastPaymentTimestamp;   // 💳 Último pagamento
        uint256 autoExecuteDeadline;    // ⏰ Prazo para auto-execução
        uint256 settlementDeadline;     // 🤝 Prazo para acordo
        uint256 lastInteraction;        // 👋 Última interação
        
        // APROVAÇÕES
        bool depositorApproved;         // ✅ Comprador aprovou
        bool beneficiaryApproved;       // ✅ Vendedor aprovou
        bool escrowOwnerApproved;       // ✅ Árbitro aprovou
        bool allowBeneficiaryWithdrawPartial; // 💸 Permite saque parcial
        
        // DISPUTAS
        bool isDisputed;                // ⚔️ Em disputa?
        address disputedBy;             // 👤 Quem disputou
        
        // CONFIGURAÇÕES
        bool useCustomSchedule;         // ⚙️ Cronograma personalizado?
        
        // SETTLEMENT (ACORDOS)
        bool hasSettlementProposal;     // 🤝 Tem proposta de acordo?
        uint256 settlementAmountToSender;    // 💰 Quanto para comprador
        uint256 settlementAmountToReceiver;  // 💰 Quanto para vendedor
        address settlementProposedBy;        // 👤 Quem propôs
    }

    // Structs
    struct EscrowParams {
        address depositor;                    // 👤 Comprador
        address beneficiary;                  // 👤 Vendedor
        bool requiresGuarantee;              // 🛡️ Exige garantia?
        uint256 totalAmount;                 // 💰 Valor total
        uint256 totalInstallments;           // 📊 Número de parcelas
        uint256 paymentIntervalSeconds;      // ⏰ Intervalo entre parcelas
        uint256 dailyInterestFeeBP;          // 📈 Taxa de juros diária
        bool allowBeneficiaryWithdrawPartial; // 💸 Permite saque parcial?
        address paymentToken;                // 💰 Token de pagamento
        InterestModel interestModel;         // 🧮 Modelo de juros
        bool useCustomSchedule;              // ⚙️ Cronograma personalizado?
    }

    // Enums
    enum TokenType {
        ERC20,      // 🪙 Tokens fungíveis
        ERC721,     // 🖼️ NFTs únicos
        ERC1155,    // 📦 Tokens semi-fungíveis
        ETH         // ⚡ Ethereum nativo
    }
    enum EscrowState {
        INACTIVE,   // 😴 Criada, aguardando início
        ACTIVE,     // 🏃 Funcionando normalmente  
        DISPUTED,   // ⚔️ Em conflito
        COMPLETE    // ✅ Finalizada
    }
    enum InterestModel {
        SIMPLE,     // 📈 Juros simples
        COMPOUND    // 📈📈 Juros compostos
    }

    // Events
    event EscrowCreated(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed depositor,     // 👤 Comprador
        address indexed beneficiary,   // 👤 Vendedor
        bool requiresGuarantee,        // 🛡️ Exige garantia?
        uint256 totalAmount,           // 💰 Valor total
        uint256 totalInstallments,     // 📊 Parcelas
        address paymentToken           // 💰 Token de pagamento
    );

    event EscrowStarted(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed depositor,     // 👤 Comprador  
        address indexed beneficiary    // 👤 Vendedor
    );

    // EVENTOS DE GARANTIAS
    event GuaranteeProvided(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed depositor,     // 👤 Quem forneceu
        TokenType tokenType,           // 🏷️ Tipo de token
        address tokenAddress,          // 📍 Endereço do token
        uint256 tokenId,               // 🆔 ID do token (NFTs)
        uint256 amount                 // 💰 Quantidade
    );

    event MultipleGuaranteesProvided(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed buyer,         // 👤 Comprador
        TokenType[] tokenTypes,        // 🏷️ Tipos de tokens
        address[] tokenAddresses,      // 📍 Endereços dos tokens
        uint256[] tokenIds,            // 🆔 IDs dos tokens
        uint256[] amounts              // 💰 Quantidades
    );

    event GuaranteeReturned(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed buyer,         // 👤 Comprador
        uint256 netAmount             // 💰 Valor devolvido
    );

    // EVENTOS DE PAGAMENTOS
    event InstallmentPaid(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        uint256 installmentNumber,     // 📊 Número da parcela
        uint256 amountPaid,           // 💰 Valor pago
        uint256 interest              // 📈 Juros cobrados
    );

    // EVENTOS DE APROVAÇÕES E SAQUES
    event ApprovalUpdated(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed approver,      // 👤 Quem aprovou
        bool isApproved               // ✅ Aprovado ou não
    );

    event FundsWithdrawn(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed seller,        // 👤 Vendedor
        address token,                // 💰 Token sacado
        uint256 netAmount             // 💰 Valor líquido
    );

    event PartialWithdrawal(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed seller,        // 👤 Vendedor
        address token,                // 💰 Token sacado
        uint256 netAmount             // 💰 Valor sacado
    );

    // EVENTOS DE DISPUTAS
    event DisputeOpened(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed raisedBy       // 👤 Quem abriu a disputa
    );

    event DisputeResolved(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed resolver,      // 👤 Quem resolveu
        string resolution,            // 📝 Justificativa
        uint256 timestamp,            // ⏰ Quando foi resolvido
        address arbitrator,           // 👤 Árbitro
        string rationale             // 📝 Fundamentação
    );

    // EVENTOS DE SETTLEMENT (ACORDOS)
    event SettlementProposed(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed proposer,      // 👤 Quem propôs
        uint256 amountToSender,       // 💰 Para o comprador
        uint256 amountToReceiver      // 💰 Para o vendedor
    );

    event SettlementAccepted(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        address indexed acceptor       // 👤 Quem aceitou
    );

    // EVENTOS DE AUTOMAÇÃO
    event EscrowAutoCompleted(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        string reason                 // 📝 Motivo da finalização
    );

    event AutoExecuted(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        uint256 timestamp             // ⏰ Quando foi executado
    );

    // EVENTOS DE EMERGÊNCIA
    event EmergencyTimeout(
        uint256 indexed escrowId,      // 🆔 ID da custódia
        string reason,               // 📝 Motivo da intervenção
        uint256 timestamp            // ⏰ Quando ocorreu
    );

    // EVENTOS ADMINISTRATIVOS
    event FeesWithdrawn(
        address indexed owner,        // 👤 Proprietário
        uint256 amount               // 💰 Valor sacado
    );

  

    // FUNÇÕES DE CRIAÇÃO E ATIVAÇÃO
    function createEscrow(EscrowParams calldata params, InstallmentDetail[] calldata customInstallments) external returns (uint256);
    function startEscrow(uint256 escrowId) external;

    
    function provideGuarantee(uint256 escrowId, TokenType tokenType, address tokenAddress, uint256 tokenId, uint256 amount) external payable;
    function provideMultipleGuarantees(uint256 escrowId, TokenType[] calldata tokenTypes, address[] calldata tokenAddresses, uint256[] calldata tokenIds, uint256[] calldata amounts) external payable;
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
    function resolveDispute(uint256 _escrowId, uint256 amountToBuyer, uint256 amountToSeller, string calldata resolution) external;

    // FUNÇÕES ADMINISTRATIVAS
    function setEscrowOwnersApproval(address[] memory _escrowOwners, bool _approval) external;
    function withdrawFees() external;

    // FUNÇÕES DE CONSULTA
    function escrows(uint256 _escrowId) external view returns (EscrowInfo memory);
    function escrowInstallments(uint256 _escrowId, uint256 _installmentNumber) external view returns (InstallmentDetail memory);
    function getEscrowBalance(uint256 _escrowId, address _token) external view returns (uint256);
    function getRemainingInstallments(uint256 _escrowId) external view returns (uint256);
    function calculateInstallmentWithInterest(uint256 _escrowId) external view returns (uint256 amountDue, uint256 interest);
    function getEscrowInfo(uint256 _escrowId) external view returns (EscrowInfo memory);
}
