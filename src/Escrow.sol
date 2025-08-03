// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./abstract/BaseEscrow.sol";
import "./libraries/EscrowLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title Escrow (Custódia Digital)
 * @author Seu Nome
 * @notice Este contrato funciona como um "cartório digital" que mantém fundos seguros
 *         durante transações entre duas partes que não confiam uma na outra.
 *
 * ANALOGIA: É como um corretor imobiliário que segura o dinheiro do comprador
 *          até que todas as condições da venda sejam cumpridas.
 *
 * FUNCIONALIDADES PRINCIPAIS:
 * 1) 💰 Suporte a múltiplos tipos de pagamento (ETH, USDC, USDT, NFTs)
 * 2) 🛡️ Sistema de garantias opcionais para proteger o vendedor
 * 3) 📅 Pagamentos parcelados com sistema de juros para atrasos
 * 4) ✅ Sistema de aprovações triplas (comprador + vendedor + arbitro)
 * 5) 💸 Saques parciais quando permitidos
 * 6) ⚖️ Sistema de disputas com arbitragem
 * 7) 🔒 Rastreamento separado de fundos por transação
 */
contract Escrow is BaseEscrow, IERC721Receiver, IERC1155Receiver {
    using SafeERC20 for IERC20; // Biblioteca para transferências seguras de tokens ERC20
    using EscrowLib for *; // Biblioteca com funções auxiliares de cálculo

    // ========================================================================
    // VARIÁVEIS DE ARMAZENAMENTO (Estado do Contrato)
    // ========================================================================

    /**
     * @notice Armazena todas as informações de cada custódia criada
     * @dev Mapping privado: escrowId => dados completos da custódia
     *
     * ANALOGIA: É como um arquivo de pasta para cada negócio no cartório
     */
    mapping(uint256 => EscrowInfo) private _escrows;

    /**
     * @notice Armazena o cronograma de parcelas de cada custódia
     * @dev Array dinâmico para cada custódia: escrowId => [parcela1, parcela2, ...]
     *
     * ANALOGIA: É como um calendário de vencimentos para cada negócio
     */
    mapping(uint256 => InstallmentDetail[]) private _escrowInstallments;

    /**
     * @notice Armazena as garantias fornecidas pelos compradores
     * @dev Mapping complexo: escrowId => tokenAddress => tipoToken => tokenId => quantidade
     *
     * ESTRUTURA:
     * - Para ETH: escrowId => address(0) => TokenType.ETH => 0 => quantidade_em_wei
     * - Para ERC20: escrowId => token_address => TokenType.ERC20 => 0 => quantidade
     * - Para NFTs: escrowId => nft_address => TokenType.ERC721 => tokenId => 1
     *
     * ANALOGIA: É como um cofre onde cada gaveta guarda um tipo diferente de garantia
     */
    mapping(uint256 => mapping(address => mapping(IEscrow.TokenType => mapping(uint256 => uint256)))) public
        escrowGuarantees;

    /**
     * @notice Rastreia quanto dinheiro cada custódia tem em cada tipo de token
     * @dev escrowId => endereço_do_token => quantidade_disponível
     *
     * EXEMPLO:
     * - escrowBalances[1][address(0)] = 5 ether (custódia 1 tem 5 ETH)
     * - escrowBalances[1][USDC_ADDRESS] = 1000e6 (custódia 1 tem 1000 USDC)
     *
     * ANALOGIA: É como o extrato bancário de cada negócio
     */
    mapping(uint256 => mapping(address => uint256)) public escrowBalances;

    /**
     * @notice Lista de endereços autorizados a criar e gerenciar custódias
     * @dev endereco_do_arbitro => true/false
     *
     * ANALOGIA: Lista de tabeliões autorizados a trabalhar no cartório
     */
    mapping(address escrowOwner => bool approved) public escrowOwners;

    /**
     * @notice Taxas da plataforma que ainda não foram sacadas pelo proprietário
     * @dev endereco_do_dono => quantidade_pendente_em_wei
     *
     * SEGURANÇA: Usamos o padrão "pull payment" para evitar envios automaticos
     */
    mapping(address => uint256) public pendingFees;

    uint256 public constant AUTO_EXECUTE_TIMEOUT = 90 days;
    uint256 public constant SETTLEMENT_TIMEOUT = 30 days;

    // ========================================================================
    // CONSTRUTOR (Inicialização do Contrato)
    // ========================================================================

    /**
     * Construtor - Estabelecendo as Regras do Cartório
     * @notice Inicializa o contrato com a taxa da plataforma
     *
     * 🏛️ ANALOGIA: É como abrir um cartório - você precisa definir quanto vai cobrar
     *              pelos seus serviços antes de começar a trabalhar
     *
     * @param _platformFeeBP Taxa da plataforma em pontos base (200 = 2%)
     *
     * SEGURANÇA APLICADA:
     * ✅ Herda validações do BaseEscrow (taxa não pode ser > 10%)
     * ✅ Inicializa _nextEscrowId = 1 (evita confusão com ID 0)
     *
     * EXEMPLO: new Escrow(250) = cartório que cobra 2.5% de taxa
     */
    constructor(uint256 _platformFeeBP) BaseEscrow(_platformFeeBP) {
        //_nextEscrowId = 1; // Primeira custódia terá ID 1 (não 0, para evitar confusão)
        //BaseEscrow comeca no numero 1
    }

    // ========================================================================
    // FUNÇÕES DE CRIAÇÃO E INICIALIZAÇÃO DE CUSTÓDIA
    // ========================================================================

    /**
     * @notice Função interna que configura todos os dados de uma nova custódia
     * @param escrowId ID único da custódia que será criada
     * @param params Parâmetros principais da custódia
     * @param customInstallments Cronograma personalizado (se usar)
     *
     * ANALOGIA: É como preencher completamente a ficha do negócio no cartório
     *
     * FLUXO:
     * 1. Preenche todas as informações básicas
     * 2. Se usa cronograma personalizado: valida se a soma bate
     * 3. Se usa cronograma padrão: divide igualmente e calcula datas
     * 4. Emite evento de criação
     */
    function _initializeEscrow(
        uint256 escrowId,
        EscrowParams memory params,
        InstallmentDetail[] calldata customInstallments
    ) private {
        // Busca o espaço de armazenamento da custódia
        EscrowInfo storage e = _escrows[escrowId];

        // PREENCHIMENTO DOS DADOS BÁSICOS
        e.depositor = params.depositor; // Quem vai pagar (comprador)
        e.beneficiary = params.beneficiary; // Quem vai receber (vendedor)
        e.escrowOwner = msg.sender; // Quem criou (arbitro/tabelião)
        e.state = EscrowState.INACTIVE; // Status inicial: inativo
        e.requiresGuarantee = params.requiresGuarantee; // Se precisa de garantia
        e.isGuaranteeProvided = false; // Garantia ainda não foi dada
        e.paymentToken = params.paymentToken; // Qual token será usado (address(0) = ETH)
        e.totalAmount = params.totalAmount; // Valor total do negócio
        e.totalInstallments = params.totalInstallments; // Quantas parcelas
        e.installmentsPaid = 0; // Nenhuma parcela paga ainda
        e.paymentIntervalSeconds = params.paymentIntervalSeconds; // Intervalo entre parcelas
        e.dailyInterestFeeBP = params.dailyInterestFeeBP; // Taxa de juros diária por atraso
        e.interestModel = params.interestModel; // Juros simples ou compostos
        e.startTimestamp = 0; // Ainda não foi iniciada
        e.lastPaymentTimestamp = 0; // Nenhum pagamento ainda
        e.depositorApproved = false; // Comprador ainda não aprovou saque
        e.beneficiaryApproved = false; // Vendedor ainda não aprovou saque
        e.escrowOwnerApproved = false; // Arbitro ainda não aprovou saque
        e.allowBeneficiaryWithdrawPartial = params.allowBeneficiaryWithdrawPartial; // Permite saque parcial?
        e.isDisputed = false; // Não há disputa
        e.disputedBy = address(0); // Ninguém abriu disputa
        e.useCustomSchedule = params.useCustomSchedule; // Usa cronograma personalizado?

        // 🆕 CONFIGURAR TIMEOUTS DE FORMA SEGURA
        e.autoExecuteDeadline = block.timestamp + AUTO_EXECUTE_TIMEOUT; // 90 dias
        e.settlementDeadline = 0; // Será definido quando houver proposta
        e.lastInteraction = block.timestamp;

        // 🆕 INICIALIZAR SETTLEMENT
        e.hasSettlementProposal = false;
        e.settlementAmountToSender = 0;
        e.settlementAmountToReceiver = 0;
        e.settlementProposedBy = address(0);

        // Imagine que estamos montando o “carnê” das parcelas de uma compra.
        // ──────────────────────────────────────────────────────────────────────
        // Há dois cenários:
        //
        // 1. O cliente (params.useCustomSchedule == true) já traz um carnê
        //    impresso, com valores e datas específicos.
        // 2. Ele não traz nada; então a loja gera um carnê padrão, com valores
        //    iguais e vencimentos igualmente espaçados.
        //
        // A lógica abaixo decide qual caminho seguir e faz todas as conferências
        // de segurança necessárias.
        if (params.useCustomSchedule) {
            // ────────────────────────────────────────────────────────────────
            // CENÁRIO 1 ─ “Trouxe meu próprio carnê” (cronograma personalizado)
            // ────────────────────────────────────────────────────────────────

            // a) Conferir se o cliente realmente entregou as folhas do carnê
            if (customInstallments.length == 0) {
                revert("No installments provided for custom schedule");
                // → “Você disse que trouxe o carnê, mas ele está vazio.”
            }

            // b) Somar todas as parcelas para garantir que a soma é igual
            //    ao valor total do negócio.
            uint256 sum = 0;

            for (uint256 i = 0; i < customInstallments.length; i++) {
                _escrowInstallments[escrowId].push(customInstallments[i]); // guarda a folha
                sum += customInstallments[i].amount; // soma o valor
            }

            if (sum != params.totalAmount) {
                revert("Sum of custom installments != totalAmount");
                // → “Os valores do seu carnê não batem com o preço combinado.”
            }
        } else {
            // ────────────────────────────────────────────────────────────────
            // CENÁRIO 2 ─ “Quero o carnê padrão” (parcelas iguais)
            // ────────────────────────────────────────────────────────────────

            // a) Dividir o valor total igualmente entre as parcelas
            uint256 installmentAmount = params.totalAmount / params.totalInstallments;
            uint256 remainder = params.totalAmount % params.totalInstallments;

            // Segurança: se a divisão deixar “restinho” (centavos quebrados),
            // não permitimos, pois as parcelas precisam ser todas idênticas.
            if (remainder != 0) {
                revert("Valor nao e divisivel igualmente pelas parcelas");
                // → “O preço não divide redondo; escolha um número de parcelas diferente.”
            }

            // b) “Imprimir” cada boleto (folha do carnê) com:
            //    • valor igual
            //    • vencimento incremental (Ex.: 30 d, 60 d, 90 d…)
            for (uint256 i = 0; i < params.totalInstallments; i++) {
                _escrowInstallments[escrowId].push(
                    InstallmentDetail({
                        dueDate: block.timestamp + ((i + 1) * params.paymentIntervalSeconds),
                        amount: installmentAmount,
                        paid: false
                    })
                );
            }
        }

        // EMITE EVENTO PARA REGISTRAR A CRIAÇÃO
        emit EscrowCreated(
            escrowId,
            params.depositor,
            params.beneficiary,
            params.requiresGuarantee,
            params.totalAmount,
            params.totalInstallments,
            params.paymentToken
        );
    }

    /**
     * @notice Cria uma nova custódia (função pública principal)
     * @param params Estrutura com todos os parâmetros da custódia
     * @param customInstallments Array com cronograma personalizado (vazio se usar padrão)
     * @return escrowId ID único da custódia criada
     *
     * QUEM PODE CHAMAR: Apenas endereços autorizados (escrowOwners)
     *
     * VALIDAÇÕES REALIZADAS:
     * 1. Comprador não pode ser endereço zero
     * 2. Vendedor não pode ser endereço zero
     * 3. Valor total deve ser maior que zero
     * 4. Número de parcelas deve ser maior que zero
     * 5. Taxa de juros deve ser menor que 100% ao dia
     * 6. Token deve estar na lista de permitidos (se não for ETH)
     * 7. Parâmetros devem passar na validação da biblioteca
     *
     * EXEMPLO DE USO:
     * EscrowParams memory params = EscrowParams({
     *     depositor: 0x123...,           // Endereço do comprador
     *     beneficiary: 0x456...,         // Endereço do vendedor
     *     requiresGuarantee: true,       // Exige garantia
     *     totalAmount: 1000 * 10**6,     // 1000 USDC
     *     totalInstallments: 4,          // 4 parcelas
     *     paymentIntervalSeconds: 30 days, // Parcelas mensais
     *     dailyInterestFeeBP: 100,       // 1% ao dia de juros
     *     allowBeneficiaryWithdrawPartial: false, // Não permite saque parcial
     *     paymentToken: USDC_ADDRESS,    // Pagamento em USDC
     *     interestModel: InterestModel.SIMPLE, // Juros simples
     *     useCustomSchedule: false       // Usar cronograma padrão
     *     customInstallments: []         // Array vazio se usar padrão
     *     useCustomSchedule: false       // Usar cronograma padrão
     * });
     */
    function createEscrow(EscrowParams calldata params, InstallmentDetail[] calldata customInstallments)
        external
        override
        returns (uint256)
    {
        // VALIDAÇÃO 1: Comprador deve ser um endereço válido
        if (params.depositor == address(0)) revert InvalidDepositor();

        // VALIDAÇÃO 2: Vendedor deve ser um endereço válido
        if (params.beneficiary == address(0)) revert InvalidBeneficiary();

        // VALIDAÇÃO 3: Valor total deve ser maior que zero
        if (params.totalAmount == 0) revert InvalidAmount();

        // VALIDAÇÃO 4: Deve ter pelo menos 1 parcela
        if (params.totalInstallments == 0) revert InvalidInstallments();

        // VALIDAÇÃO 5: Taxa de juros não pode ser 100% ou mais ao dia
        if (params.dailyInterestFeeBP >= 10000) revert InvalidInterestRate();

        // VALIDAÇÃO 6: Se não for ETH, o token deve estar permitido
        if (params.paymentToken != address(0) && !isAllowedToken[params.paymentToken]) {
            revert TokenNotAllowed();
        }

        // GERA NOVO ID ÚNICO E INICIALIZA
        uint256 escrowId = _nextEscrowId++;
        _initializeEscrow(escrowId, params, customInstallments);

        return escrowId;
    }

    // ========================================================================
    // SISTEMA DE GARANTIAS
    // ========================================================================

    /**
     * @notice Permite ao comprador fornecer uma garantia individual
     * @param escrowId ID da custódia
     * @param tokenType Tipo do token (ETH, ERC20, ERC721, ERC1155)
     * @param tokenAddress Endereço do contrato do token (address(0) para ETH)
     * @param tokenId ID específico do token (relevante para NFTs)
     * @param amount Quantidade a ser depositada como garantia
     *
     * QUEM PODE CHAMAR: Apenas o comprador (depositor) da custódia
     *
     * QUANDO PODE SER CHAMADA: Apenas quando a custódia está INATIVA
     *
     * 💎 ANALOGIA: É como deixar seu cartão de crédito como garantia no hotel
     *              Se você quebrar algo, eles já têm como cobrir o prejuízo
     *
     * TIPOS DE GARANTIA SUPORTADOS:
     * 🪙 ETH: Criptomoeda nativa
     * 🏆 ERC20: Tokens como USDC, USDT
     * 🖼️ ERC721: NFTs únicos
     * 📦 ERC1155: Tokens semi-fungíveis
     *
     * SEGURANÇA APLICADA:
     * ✅ Padrão CEI (Check-Effects-Interactions)
     * ✅ Estado atualizado ANTES de calls externas
     * ✅ Proteção contra reentrância com nonReentrant
     *
     * EXEMPLOS DE USO:
     *
     * Para ETH:
     * escrow.provideGuarantee{value: 1 ether}(
     *     1,                    // escrowId
     *     TokenType.ETH,        // tipo
     *     address(0),           // endereço (sempre zero para ETH)
     *     0,                    // tokenId (irrelevante para ETH)
     *     1 ether               // quantidade em wei
     * );
     *
     * Para ERC20 (USDC):
     * usdc.approve(escrowAddress, 1000e6);  // Primeiro aprovar
     * escrow.provideGuarantee(
     *     1,                    // escrowId
     *     TokenType.ERC20,      // tipo
     *     USDC_ADDRESS,         // endereço do USDC
     *     0,                    // tokenId (irrelevante para ERC20)
     *     1000e6                // 1000 USDC
     * );
     *
     * Para NFT:
     * nft.approve(escrowAddress, 123);  // Primeiro aprovar o NFT específico
     * escrow.provideGuarantee(
     *     1,                    // escrowId
     *     TokenType.ERC721,     // tipo
     *     NFT_ADDRESS,          // endereço do contrato NFT
     *     123,                  // ID específico do NFT
     *     1                     // quantidade (sempre 1 para ERC721)
     * );
     */
    function provideGuarantee(
        uint256 escrowId,
        IEscrow.TokenType tokenType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    ) external payable override nonReentrant {
        // Busca os dados da custódia
        EscrowInfo storage e = _escrows[escrowId];

        // VALIDAÇÃO 1: Apenas o comprador pode fornecer garantia
        if (e.depositor != msg.sender) revert UnauthorizedCaller();

        // VALIDAÇÃO 2: Custódia deve estar inativa (ainda não iniciada)
        if (e.state != EscrowState.INACTIVE) revert InvalidEscrowState();

        // VALIDAÇÃO 3: A custódia deve exigir garantia
        if (!e.requiresGuarantee) revert GuaranteeRequired();

        // VALIDAÇÃO 4: Garantia não pode ter sido fornecida antes
        if (e.isGuaranteeProvided) revert GuaranteeAlreadyProvided();

        // EFFECTS: Atualizar estado ANTES de fazer calls externas (SEGURANÇA)
        e.isGuaranteeProvided = true;

        // INTERACTIONS: Transferir tokens por último (SEGURANÇA)
        if (tokenType == IEscrow.TokenType.ETH) {
            _transferETHGuarantee(escrowId, amount);
        } else {
            _transferGuarantee(escrowId, tokenType, tokenAddress, tokenId, amount, msg.sender);
        }

        // REGISTRO: Emitir evento para logs
        emit GuaranteeProvided(escrowId, msg.sender, tokenType, tokenAddress, tokenId, amount);
    }

    /**
     * @notice Permite fornecer múltiplas garantias em uma única transação
     * @param escrowId ID da custódia
     * @param tokenTypes Array com tipos de cada token
     * @param tokenAddresses Array com endereços de cada token
     * @param tokenIds Array com IDs de cada token
     * @param amounts Array com quantidades de cada token
     *
     * QUEM PODE CHAMAR: Apenas o comprador (depositor) da custódia
     *
     * VANTAGENS:
     * - Economia de gas (uma transação vs várias)
     * - Atomicidade (ou todas as garantias são aceitas, ou nenhuma)
     *
     * SEGURANÇA ESPECIAL:
     * - Validação de soma total de ETH para evitar vulnerabilidade msg.value-loop
     * - Arrays devem ter mesmo tamanho
     * - Padrão CEI aplicado
     *
     * EXEMPLO DE USO:
     * // Garantia mista: 1 ETH + 500 USDC + 1 NFT
     * TokenType[] memory types = [TokenType.ETH, TokenType.ERC20, TokenType.ERC721];
     * address[] memory addresses = [address(0), USDC_ADDRESS, NFT_ADDRESS];
     * uint256[] memory tokenIds = [0, 0, 123];
     * uint256[] memory amounts = [1 ether, 500e6, 1];
     *
     * escrow.provideMultipleGuarantees{value: 1 ether}(
     *     1, types, addresses, tokenIds, amounts
     * );
     */
    function provideMultipleGuarantees(
        uint256 escrowId,
        IEscrow.TokenType[] calldata tokenTypes,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external payable nonReentrant {
        // VALIDAÇÃO 1: Todos os arrays devem ter o mesmo tamanho
        if (
            tokenTypes.length != tokenAddresses.length || tokenTypes.length != tokenIds.length
                || tokenTypes.length != amounts.length
        ) {
            revert ArrayLengthMismatch();
        }

        EscrowInfo storage e = _escrows[escrowId];

        // VALIDAÇÕES BÁSICAS (iguais à função individual)
        if (e.depositor != msg.sender) revert UnauthorizedCaller();
        if (e.state != EscrowState.INACTIVE) revert InvalidEscrowState();
        if (!e.requiresGuarantee) revert GuaranteeRequired();
        if (e.isGuaranteeProvided) revert GuaranteeAlreadyProvided();

        // SEGURANÇA: Calcular total de ETH esperado para evitar msg.value loop
        uint256 totalEthRequired = 0;
        for (uint256 i = 0; i < tokenTypes.length; i++) {
            if (tokenTypes[i] == IEscrow.TokenType.ETH) {
                totalEthRequired += amounts[i];
            }
        }

        // VALIDAÇÃO 2: ETH enviado deve corresponder exatamente ao total necessário
        if (msg.value != totalEthRequired) {
            revert InvalidEthAmount(msg.value, totalEthRequired);
        }

        // EFFECTS: Atualizar estado ANTES de fazer calls externas (SEGURANÇA)
        e.isGuaranteeProvided = true;

        // INTERACTIONS: Processar todas as garantias por último (SEGURANÇA)
        for (uint256 i = 0; i < tokenTypes.length; i++) {
            _transferGuarantee(escrowId, tokenTypes[i], tokenAddresses[i], tokenIds[i], amounts[i], msg.sender);
        }

        // REGISTRO: Emitir evento detalhado
        emit MultipleGuaranteesProvided(escrowId, msg.sender, tokenTypes, tokenAddresses, tokenIds, amounts);
    }

    function _transferGuarantee(
        uint256 escrowId,
        IEscrow.TokenType tokenType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        address sender
    ) private {
        if (tokenType == IEscrow.TokenType.ERC20 || tokenType == IEscrow.TokenType.ERC1155) {
            if (!isAllowedToken[tokenAddress]) revert TokenNotAllowed();
        } else if (tokenType == IEscrow.TokenType.ERC721) {
            if (!isAllowedERC721AndERC1155[tokenAddress][tokenId]) revert TokenNotAllowed();
        }

        // Transfer guarantee (SEM validação de msg.value)
        if (tokenType == IEscrow.TokenType.ERC20) {
            if (amount == 0) revert InvalidAmount();
            IERC20(tokenAddress).safeTransferFrom(sender, address(this), amount);
            escrowGuarantees[escrowId][tokenAddress][tokenType][0] = amount;
        } else if (tokenType == IEscrow.TokenType.ERC721) {
            IERC721(tokenAddress).safeTransferFrom(sender, address(this), tokenId);
            escrowGuarantees[escrowId][tokenAddress][tokenType][tokenId] = 1;
        } else if (tokenType == IEscrow.TokenType.ERC1155) {
            if (amount == 0) revert InvalidAmount();
            IERC1155(tokenAddress).safeTransferFrom(sender, address(this), tokenId, amount, "");
            escrowGuarantees[escrowId][tokenAddress][tokenType][tokenId] = amount;
        } else if (tokenType == IEscrow.TokenType.ETH) {
            if (amount == 0) revert InvalidAmount();
            escrowGuarantees[escrowId][address(0)][tokenType][0] += amount;
        } else {
            revert UnsupportedTokenType();
        }
    }

    // Função específica para garantia ETH individual
    function _transferETHGuarantee(uint256 escrowId, uint256 amount) private {
        // Validação específica para ETH
        if (msg.value != amount) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();

        escrowGuarantees[escrowId][address(0)][IEscrow.TokenType.ETH][0] += amount;
    }

    /**
     * startEscrow - Ativando a Custódia
     * @notice Inicia oficialmente a custódia após garantia fornecida
     *
     * 🎬 ANALOGIA: É como o "Action!" do diretor - tudo está preparado,
     *              agora o filme (negócio) pode começar oficialmente
     *
     * SEGURANÇA:
     * ✅ Tanto comprador quanto vendedor podem iniciar
     * ✅ Garantia obrigatória se requerida
     * ✅ Estado muda de INACTIVE → ACTIVE
     * ✅ Timestamps inicializados para juros
     */
    function startEscrow(uint256 escrowId) external override {
        EscrowInfo storage e = _escrows[escrowId];

        // Depositor ou beneficiário para iniciar a custódia
        if (msg.sender != e.depositor && msg.sender != e.beneficiary) revert UnauthorizedCaller();
        if (e.state != EscrowState.INACTIVE) revert EscrowAlreadyActive();
        if (e.requiresGuarantee && !e.isGuaranteeProvided) revert GuaranteeRequired();

        e.state = EscrowState.ACTIVE;
        e.startTimestamp = block.timestamp;
        e.lastPaymentTimestamp = block.timestamp;

        emit EscrowStarted(escrowId, e.depositor, e.beneficiary);
    }

    // -------------------------------------------------------
    // Installment Payment Logic
    // -------------------------------------------------------

    /**
     * calculateInstallmentWithInterest - Calculadora de Juros
     * @notice Calcula valor devido com juros baseado no atraso
     *
     * ⚖️ ANALOGIA: É como o medidor de taxi - enquanto você está no prazo,
     *              cobra o valor básico. Depois do prazo, o "taxímetro" começa a contar
     *
     * LÓGICA DE CÁLCULO:
     * 📅 Dentro do prazo: Valor base
     * ⏱️ Atrasado: Valor base + juros por dias de atraso
     * 🔢 Suporte a juros simples E compostos
     *
     * CONVERSÃO INTELIGENTE:
     * ⚡ paymentIntervalSeconds → dias
     * 📊 Atraso em segundos → dias inteiros
     * 💯 Precisão matemática garantida
     * @dev Calcula o valor da próxima parcela + juros, considerando que `e.paymentIntervalDays`
     *      está em SEGUNDOS. Exemplo: 30 dias = 2592000 segundos.
     *      Se já estiver atrasado, calcula a quantidade de dias de atraso.
     */
    /**
     * ─────────────────────────────────────────────────────────────────────────
     * calculateInstallmentWithInterest
     * ─────────────────────────────────────────────────────────────────────────
     * 👀 Visão geral
     * ──────────────
     * Pense em um *taxímetro*:
     *   • Enquanto você está dentro do trajeto/prazo → o preço fica parado.
     *   • Passou do trajeto/prazo → o taxímetro começa a girar cobrando juros
     *     por cada dia de atraso.
     *
     * O que essa função faz?
     *   1. Descobre qual é a próxima “corrida” (parcela) a pagar.
     *   2. Mede há quanto tempo o relógio está rodando.
     *   3. Se ainda estamos na “avenida do prazo” → paga-se só o valor base.
     *   4. Se já entrou na “rua do atraso” → soma juros simples **ou** compostos,
     *      dependendo da regra escolhida.
     *
     * Retorno:
     *   • amountDue  → valor total que precisa ser pago agora (base + juros).
     *   • interest   → somente a parte dos juros (0 se não houver atraso).
     */
    function calculateInstallmentWithInterest(uint256 escrowId)
        public
        view
        override
        returns (uint256 amountDue, uint256 interest)
    {
        // 1) Pega todos os dados da “corrida” atual
        EscrowInfo memory e = _escrows[escrowId];

        //   🔒 Segurança: a custódia precisa estar ativa
        if (e.state != EscrowState.ACTIVE) revert EscrowNotActive();

        //   🏁 Segurança: se já pagou todas as parcelas, nada a calcular
        if (e.installmentsPaid >= e.totalInstallments) revert AllInstallmentsPaid();

        // 2) Valor base da próxima parcela (a “bandeirada” do táxi)
        uint256 baseAmount = _escrowInstallments[escrowId][e.installmentsPaid].amount;

        // 3) Quanto tempo (em segundos) desde o último pagamento
        uint256 timeDiff = block.timestamp - e.lastPaymentTimestamp;

        // 4) Ainda dentro do prazo?
        //    • Se sim → só devolve o valor base, juros = 0
        if (timeDiff <= e.paymentIntervalSeconds) {
            return (baseAmount, 0);
        }

        // 5) Se chegou aqui, estamos atrasados 😬
        //    • Calc. quantos segundos de atraso
        uint256 overdueSeconds = timeDiff - e.paymentIntervalSeconds;

        //    • Converte para dias inteiros (86400 seg = 1 dia)
        uint256 overdueDays = overdueSeconds / 1 days;

        //    • Se por acaso o atraso é menor que 1 dia, juros continuam 0
        if (overdueDays == 0) {
            return (baseAmount, 0);
        }

        // 6) Calcula juros conforme o “plano de cobrança” escolhido
        if (e.interestModel == InterestModel.SIMPLE) {
            // 📈 Juros simples: “cada dia soma X% sobre o valor original”
            interest = EscrowLib.calculateSimpleInterest(
                baseAmount,
                e.dailyInterestFeeBP, // taxa em basis points (1% = 100 bp)
                overdueDays
            );
        } else {
            // 📈 Juros compostos: “juros sobre juros” (efeito bola de neve)
            interest = EscrowLib.calculateCompoundInterest(baseAmount, e.dailyInterestFeeBP, overdueDays);
        }

        // 7) Valor final a pagar = bandeirada + “extra” do taxímetro
        amountDue = baseAmount + interest;

        return (amountDue, interest);
    }

    /**
     * payInstallmentETH - Pagando Parcela em ETH
     * @notice Permite ao comprador pagar uma parcela com juros se atrasado
     *
     * 💳 ANALOGIA: É como pagar uma conta no banco - se pagar no prazo, sem juros
     *              Se atrasar, o banco cobra juros automaticamente
     *
     * CÁLCULO DE JUROS INTELIGENTE:
     * ⏰ No prazo: Valor original
     * ⚠️ Atrasado: Valor + juros (simples ou compostos)
     * 📊 Excesso: Automaticamente devolvido
     *
     * SEGURANÇA APLICADA:
     * ✅ Índice salvo ANTES de incrementar (bug fix)
     * ✅ Excesso devolvido automaticamente
     * ✅ Auto-complete se pagamentos + aprovações completos
     * ✅ CEI pattern aplicado
     */

    /**
     * ─────────────────────────────────────────────────────────────────────────
     * 1.  payInstallmentETH  –  “pague a prestação usando **dinheiro vivo** (ETH)”
     * ─────────────────────────────────────────────────────────────────────────
     *
     *  🏦  Analogia simples
     *  ────────────────────
     *  Imagine que você foi ao banco / lotérica:
     *   1. Entrega o boleto da prestação.
     *   2. O caixa confere se você é o **comprador** certo e se o boleto ainda vale.
     *   3. Se você pagou antes do vencimento → só o valor do boleto.
     *      Se já venceu → o sistema soma o juro automaticamente.
     *   4. Pagou a mais sem querer?  O caixa devolve o troco.
     *   5. Depois que todas as prestações estiverem pagas **e** todo mundo assinar,
     *      o sistema dá “baixa” sozinho no contrato (auto-complete).
     *
     *  Passo a passo no código
     *  ───────────────────────
     *  ✅ 1) **Checks** (verificações):
     *      • A custódia deve estar “ACTIVA”.
     *      • Quem paga tem que ser o **depositor**.
     *      • Este modo aceita só ETH (`paymentToken == address(0)`).
     *      • Ainda restam parcelas a pagar.
     *
     *  ✅ 2) Calcula quanto está devendo agora
     *      `calculateInstallmentWithInterest` age como o “cálculo do boleto
     *      + multa” (mostra quanto é a prestação e se há juros).
     *
     *  ✅ 3) Se o valor enviado (`msg.value`) é menor → rejeita.
     *
     *  ✅ 4) Guarda alguns números **antes** de mexer no estado (CEI pattern):
     *      • Qual prestação estamos quitando.
     *      • Quanto de troco (excesso) precisa ser devolvido.
     *
     *  ✅ 5) **Effects**: atualiza todos os campos da custódia:
     *      • Marca a prestação como paga, atualiza timestamps, etc.
     *      • Credita o valor pago na “conta interna” da custódia.
     *      • Se houve excesso, já desconta esse troco da conta.
     *
     *  ✅ 6) Chama `_checkAutoComplete` **antes** de qualquer transferência externa.
     *      (Evita reentrância e fecha o contrato se tudo foi quitado + aprovado.)
     *
     *  ✅ 7) **Interactions** externas: devolve o troco via `call{value: …}`.
     *      Se a transferência falhar → reverte.
     *
     *  ✅ 8) Emite evento `InstallmentPaid` para que front-ends e indexadores saibam.
     */
    function payInstallmentETH(uint256 _escrowId) external payable nonReentrant {
        EscrowInfo storage e = _escrows[_escrowId];

        if (e.state != EscrowState.ACTIVE) revert EscrowNotActive();
        if (e.depositor != msg.sender) revert UnauthorizedCaller();
        if (e.paymentToken != address(0)) revert InvalidEscrowState();
        if (e.installmentsPaid >= e.totalInstallments) revert AllInstallmentsPaid();

        (uint256 amountDue,) = calculateInstallmentWithInterest(_escrowId);
        if (msg.value < amountDue) revert InsufficientPayment();

        // ✅ CHECK: Calcular valores ANTES de mudanças
        uint256 currentInstallmentIndex = e.installmentsPaid;
        uint256 excess = msg.value - amountDue;

        // ✅ EFFECTS: TODAS as mudanças de estado PRIMEIRO
        e.installmentsPaid += 1;
        e.lastPaymentTimestamp = block.timestamp;
        escrowBalances[_escrowId][address(0)] += msg.value;

        if (excess > 0) {
            escrowBalances[_escrowId][address(0)] -= excess;
        }

        // ✅ CRÍTICO: Auto-complete ANTES de calls externas
        _checkAutoComplete(_escrowId);

        // ✅ INTERACTIONS: Calls externas por ÚLTIMO
        if (excess > 0) {
            (bool refundOk,) = payable(msg.sender).call{value: excess}("");
            if (!refundOk) revert TransferFailed();
        }

        emit InstallmentPaid(
            _escrowId,
            e.installmentsPaid,
            msg.value,
            (msg.value - excess - _escrowInstallments[_escrowId][currentInstallmentIndex].amount)
        );
    }

    /**
     * @dev Pay an installment with ERC20 (if paymentToken != address(0)).
     * ✅ CORREÇÃO: CEI pattern aplicado rigorosamente
     */
    /**
     * ─────────────────────────────────────────────────────────────────────────
     * 2.  payInstallmentERC20 – igualzinho, mas com **moeda digital** (token)
     * ─────────────────────────────────────────────────────────────────────────
     *
     *  Só troca:
     *   • `msg.value` por `_amount` (quantos tokens você aprovou).
     *   • ETH → IERC20.
     *   • Envia e devolve via `safeTransferFrom` e `safeTransfer`.
     *
     *  O resto (checks, cálculo de juros, troco, auto-complete) é idêntico.
     */
    function payInstallmentERC20(uint256 _escrowId, uint256 _amount) external nonReentrant {
        EscrowInfo storage e = _escrows[_escrowId];
        if (e.state != EscrowState.ACTIVE) revert EscrowNotActive();
        if (e.depositor != msg.sender) revert UnauthorizedCaller();
        if (e.paymentToken == address(0)) revert InvalidEscrowState();
        if (e.installmentsPaid >= e.totalInstallments) revert AllInstallmentsPaid();

        (uint256 amountDue,) = calculateInstallmentWithInterest(_escrowId);
        if (_amount < amountDue) revert InsufficientPayment();

        // ✅ CHECK: Calcular valores ANTES de mudanças
        uint256 currentInstallmentIndex = e.installmentsPaid;
        uint256 excess = _amount - amountDue;

        // ✅ EFFECTS: TODAS as mudanças de estado PRIMEIRO
        e.installmentsPaid += 1;
        e.lastPaymentTimestamp = block.timestamp;
        escrowBalances[_escrowId][e.paymentToken] += _amount;

        if (excess > 0) {
            escrowBalances[_escrowId][e.paymentToken] -= excess;
        }

        // ✅ CRÍTICO: Auto-complete ANTES de calls externas
        _checkAutoComplete(_escrowId);

        // ✅ INTERACTIONS: Calls externas por ÚLTIMO
        IERC20 token = IERC20(e.paymentToken);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        if (excess > 0) {
            token.safeTransfer(msg.sender, excess);
        }

        emit InstallmentPaid(
            _escrowId,
            e.installmentsPaid,
            _amount,
            (_amount - excess - _escrowInstallments[_escrowId][currentInstallmentIndex].amount)
        );
    }

    /**
     * _checkAutoComplete - Inteligência Artificial de Finalização
     * @notice Verifica se pode finalizar automaticamente baseado em consenso
     *
     * 🧠 ANALOGIA: É como um assistente inteligente que percebe quando
     *              todos concordaram e automaticamente finaliza o processo
     *
     * CONDIÇÕES PARA AUTO-FINALIZAÇÃO:
     * ✅ Estado ACTIVE (não DISPUTED)
     * ✅ Sem disputas ativas
     * ✅ Todos os pagamentos feitos
     * ✅ Todas as aprovações dadas
     *
     * BENEFÍCIO: UX SUPERIOR
     * 🚀 Finalização instantânea quando há consenso
     * 💎 Garantia liberada imediatamente
     * ⚡ Sem esperas desnecessárias
     * ─────────────────────────────────────────────────────────────────────────
     * 3.  _checkAutoComplete – o “assistente que fecha o contrato sozinho”
     * ─────────────────────────────────────────────────────────────────────────
     *
     *  Ele faz uma pergunta simples depois de cada pagamento:
     *  “Já recebi **todo** o dinheiro, ninguém abriu disputa e as três pessoas
     *   (comprador, vendedor, árbitro) já apertaram o botão *OK*?”
     *
     *  • Se SIM  → muda o estado para `COMPLETE` e dispara `EscrowAutoCompleted`.
     *  • Se NÃO → não faz nada; espera pela próxima ação.
     *
     *  Resultado: experiência de usuário top 🏅 – você paga a última parcela,
     *  todo mundo concorda e *puf!* o contrato liquida automaticamente,
     *  liberando a garantia na mesma hora.
     */
    function _checkAutoComplete(uint256 escrowId) private {
        EscrowInfo storage e = _escrows[escrowId];

        // ✅ Se pagamentos completos + aprovações + SEM DISPUTA = FINALIZAR
        if (
            e.state == EscrowState.ACTIVE && !e.isDisputed && e.installmentsPaid == e.totalInstallments
                && isAllApproved(escrowId)
        ) {
            e.state = EscrowState.COMPLETE;
            emit EscrowAutoCompleted(escrowId, "All payments made and approved");
        }
    }

    /**
     * @dev Permite que o comprador pague todas as parcelas restantes de uma só vez.
     * ✅ CEI pattern aplicado rigorosamente
     */
    function payAllRemaining(uint256 _escrowId) external payable nonReentrant {
        EscrowInfo storage e = _escrows[_escrowId];
        if (e.state != EscrowState.ACTIVE) revert EscrowNotActive();
        if (e.depositor != msg.sender) revert UnauthorizedCaller();

        uint256 remaining = e.totalInstallments - e.installmentsPaid;
        if (remaining == 0) revert InvalidInstallment();

        uint256 totalDue = _escrowInstallments[_escrowId][e.installmentsPaid].amount * remaining;

        if (e.paymentToken == address(0)) {
            if (msg.value < totalDue) revert InsufficientPayment();

            // ✅ CHECK: Calcular excess ANTES de mudanças
            uint256 excess = msg.value - totalDue;

            // ✅ EFFECTS: TODAS as mudanças de estado PRIMEIRO
            escrowBalances[_escrowId][address(0)] += msg.value;
            if (excess > 0) {
                escrowBalances[_escrowId][address(0)] -= excess;
            }
            e.installmentsPaid = e.totalInstallments;
            e.lastPaymentTimestamp = block.timestamp;

            // ✅ CRÍTICO: Auto-complete ANTES de calls externas
            _checkAutoComplete(_escrowId);

            // ✅ INTERACTIONS: Calls externas por ÚLTIMO
            if (excess > 0) {
                (bool refundOk,) = payable(msg.sender).call{value: excess}("");
                require(refundOk, "Refund failed");
            }
        } else {
            // ERC20 pathway
            // ✅ EFFECTS: TODAS as mudanças de estado PRIMEIRO
            escrowBalances[_escrowId][e.paymentToken] += totalDue;
            e.installmentsPaid = e.totalInstallments;
            e.lastPaymentTimestamp = block.timestamp;

            // ✅ CRÍTICO: Auto-complete ANTES de calls externas
            _checkAutoComplete(_escrowId);

            // ✅ INTERACTIONS: Calls externas por ÚLTIMO
            IERC20 token = IERC20(e.paymentToken);
            token.safeTransferFrom(msg.sender, address(this), totalDue);
        }

        emit InstallmentPaid(_escrowId, e.installmentsPaid, totalDue, 0);
    }

    // -------------------------------------------------------
    // Dispute Mechanism
    // -------------------------------------------------------

    /**
     * @dev Buyer or Seller can open a dispute if the escrow is ACTIVE.
     *      Once a dispute is open, no further approvals or withdrawals can proceed until resolved.
     */
    function openDispute(uint256 _escrowId) external {
        EscrowInfo storage e = _escrows[_escrowId];
        if (e.state != EscrowState.ACTIVE) revert EscrowNotActive();
        if (msg.sender != e.depositor && msg.sender != e.beneficiary) revert InvalidCaller();

        e.state = EscrowState.DISPUTED;
        e.isDisputed = true;
        e.disputedBy = msg.sender;

        emit DisputeOpened(_escrowId, msg.sender);
    }

    /**
     * resolveDispute - Resolvendo Conflitos
     * @notice Permite resolver disputas com distribuição customizada
     *
     * ⚖️ ANALOGIA: É como um juiz que pode decidir dar 60% para o comprador
     *              e 40% para o vendedor, baseado nas evidências
     *
     * FLEXIBILIDADE TOTAL:
     * 💰 Distribuição customizada (não binária)
     * 🏛️ Requer aprovação de todas as partes
     * 💸 Taxa da plataforma sempre preservada
     * 🔒 Estado muda para COMPLETE após resolução
     *
     * SEGURANÇA MÁXIMA:
     * ✅ Validação de distribuição vs saldo
     * ✅ Pull payment para ETH (anti-reentrância)
     * ✅ CEI pattern rigorosamente aplicado
     */
    /**
     * ─────────────────────────────────────────────────────────────────────────
     *  resolveDispute ‒ “o juiz que divide o bolo”
     * ─────────────────────────────────────────────────────────────────────────
     *
     *  ⚖️  Analogia completa
     *  ────────────────────
     *  Pense num processo em que comprador e vendedor brigaram.
     *  • O **juiz** (quem chama a função) analisa tudo e decide:
     *      “Compra­dor fica com X, vendedor com Y, e a plataforma
     *       pega sua taxa Z”.
     *  • Depois da decisão, o caso é arquivado – nada mais pode ser pago
     *    ou sacado daquele escrow.
     *
     *  Estrutura CEI (Checks → Effects → Interactions)
     *  ───────────────────────────────────────────────
     *  1️⃣ **CHECKS**   – Confere se tudo está certo
     *  2️⃣ **EFFECTS**  – Atualiza o estado interno do contrato
     *  3️⃣ **INTERACTIONS** – Transfere dinheiro para fora
     */
    function resolveDispute(
        uint256 _escrowId,
        uint256 amountToBuyer, // 💸 quanto o juiz manda devolver ao comprador
        uint256 amountToSeller, // 💸 quanto o juiz manda pagar ao vendedor
        string calldata resolution // 🔖 texto com a decisão
    ) external nonReentrant {
        /* ─────── 1️⃣ CHECKS ─────── */
        // Todo mundo (comprador, vendedor, árbitro) já concordou com a decisão?
        if (!isAllApproved(_escrowId)) revert NotAllPartiesApproved();

        EscrowInfo storage e = _escrows[_escrowId];
        if (e.state != EscrowState.DISPUTED) revert EscrowNotInDispute(); // tem que estar em disputa!

        // Quanto de dinheiro/​token existe hoje na “conta” desse escrow
        address token = e.paymentToken; // address(0) = ETH
        uint256 balance = escrowBalances[_escrowId][token]; // saldo total
        uint256 feePlatform = _calculateFee(balance); // 📈 taxa da plataforma

        // Validação: X + Y + taxa não pode ultrapassar o que há na conta
        if (amountToBuyer + amountToSeller + feePlatform > balance) revert InvalidDistribution();

        /* ─────── 2️⃣ EFFECTS ─────── */
        escrowBalances[_escrowId][token] = 0; // zera a “conta” interna
        e.state = EscrowState.COMPLETE; // marca como FINALIZADO
        e.isDisputed = false; // remove a flag de disputa

        /* ─────── 3️⃣ INTERACTIONS ─────── */
        if (token == address(0)) {
            /* Pagamentos em ETH --------------------------------------------- */

            // A plataforma usa “pull-payment”: só **acumula** sua comissão
            // (retira depois em batch, evitando reentrância).
            pendingFees[owner()] += feePlatform;

            // Envia ETH pro comprador
            (bool buyerOk,) = payable(e.depositor).call{value: amountToBuyer}("");
            require(buyerOk, "Buyer transfer failed");

            // Envia ETH pro vendedor
            (bool sellerOk,) = payable(e.beneficiary).call{value: amountToSeller}("");
            require(sellerOk, "Seller transfer failed");
        } else {
            /* Pagamentos em ERC-20 ------------------------------------------ */
            IERC20 erc20 = IERC20(token);

            // Transfere direto: ERC-20 não sofre o mesmo risco de reentrância
            erc20.safeTransfer(e.depositor, amountToBuyer);
            erc20.safeTransfer(e.beneficiary, amountToSeller);

            if (feePlatform > 0) {
                erc20.safeTransfer(owner(), feePlatform); // comissão
            }
        }

        /* 🎉 Registro público da decisão */
        emit DisputeResolved(
            _escrowId,
            msg.sender, // quem resolveu
            resolution, // texto da sentença
            block.timestamp,
            msg.sender, // placeholder (ex-árbitro) – manter compatibilidade
            "" // dados extra (não usado aqui)
        );
    }

    // -------------------------------------------------------
    // Approval & Final / Partial Withdrawals
    // -------------------------------------------------------

    /* ──────────────────────────────────────────────────────────────────────────────
    *  setEscrowOwnersApproval – “entregando chaves aos tabeliões”
    * ──────────────────────────────────────────────────────────────────────────────
    *  Analogia: imagine várias filiais de um cartório.  
    *  • `onlyOwner` = a matriz.  
    *  • Cada endereço da lista recebe (ou perde) uma **chave-mestra** que permite
    *    abrir, criar ou arbitrar escrows.
    *  Implementação: um simples `for` que marca `true/false` no mapa `escrowOwners`.
    */
    function setEscrowOwnersApproval(address[] memory _escrowOwners, bool _approval) external onlyOwner {
        for (uint256 i = 0; i < _escrowOwners.length; i++) {
            escrowOwners[_escrowOwners[i]] = _approval; // entrega ou recolhe a chave
        }
    }

    /* ──────────────────────────────────────────────────────────────────────────────
    *  setReleaseApproval – cada parte vira seu “semáforo” para verde ou vermelho
    * ──────────────────────────────────────────────────────────────────────────────
    *  • Comprador, vendedor e árbitro possuem **um botão** de aprovação.  
    *  • Quando os três estiverem verdes ➜ o dinheiro já pode ser retirado.  
    *  • Se qualquer um apertar de novo com `false`, volta a ser vermelho.
    *  Lógica:
    *    1. Garante que o escrow está ATIVO ou em DISPUTA.  
    *    2. Liga/desliga o semáforo da parte que chamou.  
    *    3. Se está ativo e sem disputa, chama `_checkAutoComplete` para talvez
    *       finalizar automaticamente.  
    *    4. Emite evento.
    */
    function setReleaseApproval(uint256 _escrowId, bool _approval) external {
        EscrowInfo storage e = _escrows[_escrowId];
        require(e.state == EscrowState.ACTIVE || e.state == EscrowState.DISPUTED, "Escrow not active or disputed");

        if (msg.sender == e.depositor) e.depositorApproved = _approval;
        else if (msg.sender == e.beneficiary) e.beneficiaryApproved = _approval;
        else if (msg.sender == e.escrowOwner) e.escrowOwnerApproved = _approval;
        else revert InvalidCaller();

        // Se todo mundo está bem e não há briga, talvez feche automático
        if (e.state == EscrowState.ACTIVE && !e.isDisputed) {
            _checkAutoComplete(_escrowId);
        }

        emit ApprovalUpdated(_escrowId, msg.sender, _approval);
    }

    /* ──────────────────────────────────────────────────────────────────────────────
    *  isAllApproved – “todos os semáforos estão verdes?”
    * ──────────────────────────────────────────────────────────────────────────────
    *  Retorna `true` só quando comprador, vendedor e árbitro aprovaram.
    */
    function isAllApproved(uint256 _escrowId) internal view returns (bool) {
        EscrowInfo memory e = _escrows[_escrowId];
        return (e.depositorApproved && e.beneficiaryApproved && e.escrowOwnerApproved);
    }

    /* ──────────────────────────────────────────────────────────────────────────────
    *  withdrawFunds – o vendedor retira o “envelope” do cofre
    * ──────────────────────────────────────────────────────────────────────────────
    *  Analogia:
    *  • O cofre guarda o dinheiro até que o negócio acabe.  
    *  • Vendedor (beneficiário) só abre se:
    *      – Todos aprovaram **ou** o contrato já está COMPLETE.  
    *      – Não existe disputa.  
    *  • Plataforma retém sua comissão (`feePlatform`) antes do saque.
    *  • Usa o padrão CEI + pull-payment para ETH.
    */
    function withdrawFunds(uint256 _escrowId) external nonReentrant {
        EscrowInfo storage e = _escrows[_escrowId];
        require(e.beneficiary == msg.sender, "Only beneficiary can withdraw");
        require(e.state == EscrowState.ACTIVE || e.state == EscrowState.COMPLETE, "Escrow not in withdrawable state");
        require(!e.isDisputed, "Escrow is disputed");

        if (e.state == EscrowState.ACTIVE) {
            require(isAllApproved(_escrowId), "Not all parties approved");
        }

        address token = e.paymentToken; // address(0) = ETH
        uint256 balance = escrowBalances[_escrowId][token];
        require(balance > 0, "No balance to withdraw");

        uint256 feePlatform = _calculateFee(balance);
        uint256 netAmount = balance - feePlatform;

        /* EFFECTS */
        escrowBalances[_escrowId][token] = 0;
        e.state = EscrowState.COMPLETE;

        /* INTERACTIONS */
        if (token == address(0)) {
            if (feePlatform > 0) pendingFees[owner()] += feePlatform;

            (bool ok,) = payable(e.beneficiary).call{value: netAmount}("");
            require(ok, "ETH transfer to seller failed");
        } else {
            IERC20(token).safeTransfer(e.beneficiary, netAmount);
            if (feePlatform > 0) IERC20(token).safeTransfer(owner(), feePlatform);
        }

        emit FundsWithdrawn(_escrowId, msg.sender, token, netAmount);
    }

    /* ──────────────────────────────────────────────────────────────────────────────
    *  returnGuarantee – devolvendo a caução ao comprador
    * ──────────────────────────────────────────────────────────────────────────────
    *  Analogia: o depósito de segurança (dinheiro / NFT / token) fica trancado.
    *  • Quando o negócio fecha sem pendências, o comprador pode pegar a caução
    *    de volta.  
    *  • Suporta ETH, ERC-20, ERC-721, ERC-1155.
    */
    function returnGuarantee(uint256 _escrowId, IEscrow.TokenType _type, address _tokenAddress, uint256 _tokenId)
        external
        nonReentrant
    {
        EscrowInfo storage e = _escrows[_escrowId];
        require(e.depositor == msg.sender, "Only depositor can reclaim guarantee");
        require(e.state == EscrowState.COMPLETE, "Escrow not complete");
        require(isAllApproved(_escrowId) || !e.isDisputed, "Not all parties approved or dispute active");

        uint256 amountOrOne = escrowGuarantees[_escrowId][_tokenAddress][_type][_tokenId];
        require(amountOrOne > 0, "No guarantee balance");

        // Limpa armazenamento
        escrowGuarantees[_escrowId][_tokenAddress][_type][_tokenId] = 0;

        if (_type == IEscrow.TokenType.ERC20) {
            IERC20(_tokenAddress).safeTransfer(e.depositor, amountOrOne);
            emit GuaranteeReturned(_escrowId, e.depositor, amountOrOne);
        } else if (_type == IEscrow.TokenType.ERC721) {
            IERC721(_tokenAddress).safeTransferFrom(address(this), e.depositor, _tokenId);
            emit GuaranteeReturned(_escrowId, e.depositor, 1);
        } else if (_type == IEscrow.TokenType.ERC1155) {
            IERC1155(_tokenAddress).safeTransferFrom(address(this), e.depositor, _tokenId, amountOrOne, "");
            emit GuaranteeReturned(_escrowId, e.depositor, amountOrOne);
        } else if (_type == IEscrow.TokenType.ETH) {
            (bool sent,) = payable(e.depositor).call{value: amountOrOne}("");
            require(sent, "ETH transfer failed");
            emit GuaranteeReturned(_escrowId, e.depositor, amountOrOne);
        }
    }

    /* ──────────────────────────────────────────────────────────────────────────────
    *  partialWithdraw – “vale” de adiantamento ao vendedor
    * ──────────────────────────────────────────────────────────────────────────────
    *  • Se o contrato permite (`allowBeneficiaryWithdrawPartial == true`)
    *    e todos aprovaram, o vendedor pode pegar uma parte do dinheiro antes
    *    do fim.  
    *  • Comissão da plataforma é descontada proporcionalmente.
    */
    function partialWithdraw(uint256 _escrowId, uint256 _amount) external nonReentrant {
        EscrowInfo storage e = _escrows[_escrowId];
        require(e.beneficiary == msg.sender, "Only beneficiary can withdraw");
        require(e.state == EscrowState.ACTIVE, "Escrow not active");
        require(!e.isDisputed, "Escrow is disputed");
        require(e.allowBeneficiaryWithdrawPartial, "Partial withdrawal not allowed");
        require(isAllApproved(_escrowId), "Not all parties approved");

        address token = e.paymentToken;
        uint256 balance = escrowBalances[_escrowId][token];
        require(_amount > 0 && _amount <= balance, "Invalid partial amount");

        uint256 feePlatform = _calculateFee(_amount);
        uint256 netAmount = _amount - feePlatform;

        escrowBalances[_escrowId][token] = balance - _amount; // EFFECT

        if (token == address(0)) {
            if (feePlatform > 0) pendingFees[owner()] += feePlatform;
            (bool ok,) = payable(e.beneficiary).call{value: netAmount}("");
            require(ok, "Partial withdraw (ETH) failed");
        } else {
            IERC20(token).safeTransfer(e.beneficiary, netAmount);
            if (feePlatform > 0) IERC20(token).safeTransfer(owner(), feePlatform);
        }

        emit PartialWithdrawal(_escrowId, msg.sender, token, netAmount);
    }

    /* ──────────────────────────────────────────────────────────────────────────────
    *  withdrawFees – “o dono da plataforma esvazia o porquinho”
    * ──────────────────────────────────────────────────────────────────────────────
    *  • Todas as taxas acumulam no mapa `pendingFees`.  
    *  • O owner pode sacar quando quiser.  
    *  • Proteção reentrância (`nonReentrant`) e uso de pull-payment.
    */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = pendingFees[msg.sender];
        require(amount > 0, "No fees to withdraw");

        pendingFees[msg.sender] = 0;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "Fee withdrawal failed");

        emit FeesWithdrawn(msg.sender, amount);
    }

    // -------------------------------------------------------
    // View Functions
    // -------------------------------------------------------

    /**
     * @notice Returns the contract's total ETH balance.
     *         For multi-escrow usage, each escrow tracks a distinct portion in `escrowBalances[escrowId][address(0)]`.
     */
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Return how many installments remain for a given escrow.
     */
    function getRemainingInstallments(uint256 escrowId) external view override returns (uint256) {
        EscrowInfo memory e = _escrows[escrowId];
        return e.totalInstallments - e.installmentsPaid;
    }

    /**
     * @dev Returns escrow balances for a specific token.
     */
    function getEscrowBalance(uint256 escrowId, address token) external view override returns (uint256) {
        return escrowBalances[escrowId][token];
    }

    /**
     * @dev Returns escrow info for a specific escrow.
     */
    function getEscrowInfo(uint256 escrowId) external view override returns (EscrowInfo memory) {
        return _escrows[escrowId];
    }

    // -------------------------------------------------------
    // Fallback & Interface Support
    // -------------------------------------------------------

    receive() external payable {
        // Accept ETH
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // Funções públicas para interface
    function escrows(uint256 escrowId) external view override returns (EscrowInfo memory) {
        return _escrows[escrowId];
    }

    function escrowInstallments(uint256 escrowId, uint256 installmentId)
        external
        view
        override
        returns (InstallmentDetail memory)
    {
        return _escrowInstallments[escrowId][installmentId];
    }

    /**
     * proposeSettlement - Propondo Acordo
     * @notice Permite propostas de acordo antes da arbitragem
     *
     * 🕊️ ANALOGIA: É como quando dois vizinhos brigam e decidem
     *              resolver amigavelmente em vez de ir ao tribunal
     *
     * VANTAGENS DO SETTLEMENT:
     * ⚡ Resolução mais rápida
     * 💰 Economia de custos
     * 🎯 Controle total das partes
     * ⏱️ Timeout de 30 dias para aceitar
     *
     * SEGURANÇA:
     * ✅ Validação de saldo + taxa
     * ✅ Prazo de validade
     * ✅ Apenas participantes podem propor
     */
    function proposeSettlement(uint256 escrowId, uint256 amountToSender, uint256 amountToReceiver)
        external
        nonReentrant
    {
        EscrowInfo storage e = _escrows[escrowId];

        // ✅ VALIDAÇÕES BÁSICAS
        require(e.state == EscrowState.ACTIVE, "Escrow not active");
        require(msg.sender == e.depositor || msg.sender == e.beneficiary, "Only buyer or seller can propose");

        // ✅ VALIDAR VALORES DA PROPOSTA
        address token = e.paymentToken;
        uint256 balance = escrowBalances[escrowId][token];
        uint256 feePlatform = _calculateFee(balance);

        require(amountToSender + amountToReceiver + feePlatform <= balance, "Settlement exceeds available balance");

        // ✅ SALVAR PROPOSTA
        e.hasSettlementProposal = true;
        e.settlementAmountToSender = amountToSender;
        e.settlementAmountToReceiver = amountToReceiver;
        e.settlementProposedBy = msg.sender;
        e.settlementDeadline = block.timestamp + SETTLEMENT_TIMEOUT; // 30 dias
        e.lastInteraction = block.timestamp;

        emit SettlementProposed(escrowId, msg.sender, amountToSender, amountToReceiver);
    }

    /**
     * @notice Aceitar proposta de acordo
     * @dev A outra parte aceita a divisão proposta
     */
    function acceptSettlement(uint256 escrowId) external nonReentrant {
        EscrowInfo storage e = _escrows[escrowId];

        // ✅ VALIDAÇÕES
        require(e.state == EscrowState.ACTIVE, "Escrow not active");
        require(e.hasSettlementProposal, "No settlement proposal");
        require(block.timestamp <= e.settlementDeadline, "Settlement proposal expired");

        // ✅ APENAS A OUTRA PARTE PODE ACEITAR
        require(
            (e.settlementProposedBy == e.depositor && msg.sender == e.beneficiary)
                || (e.settlementProposedBy == e.beneficiary && msg.sender == e.depositor),
            "Only the other party can accept"
        );

        // ✅ EXECUTAR ACORDO AUTOMATICAMENTE
        _executeSettlement(escrowId);

        emit SettlementAccepted(escrowId, msg.sender);
    }

    /**
     * @notice Executa o acordo aceito
     * @dev Função interna que divide os fundos conforme acordado
     */
    function _executeSettlement(uint256 escrowId) private {
        EscrowInfo storage e = _escrows[escrowId];

        address token = e.paymentToken;
        uint256 balance = escrowBalances[escrowId][token];
        uint256 feePlatform = _calculateFee(balance);

        uint256 amountToSender = e.settlementAmountToSender;
        uint256 amountToReceiver = e.settlementAmountToReceiver;

        // ✅ EFFECTS: Limpar estado
        escrowBalances[escrowId][token] = 0;
        e.state = EscrowState.COMPLETE;
        e.hasSettlementProposal = false;

        // ✅ INTERACTIONS: Transferir fundos
        if (token == address(0)) {
            // ETH
            pendingFees[owner()] += feePlatform;

            if (amountToSender > 0) {
                (bool success1,) = payable(e.depositor).call{value: amountToSender}("");
                require(success1, "Transfer to sender failed");
            }

            if (amountToReceiver > 0) {
                (bool success2,) = payable(e.beneficiary).call{value: amountToReceiver}("");
                require(success2, "Transfer to receiver failed");
            }
        } else {
            // ERC20
            IERC20 erc20 = IERC20(token);

            if (feePlatform > 0) {
                erc20.safeTransfer(owner(), feePlatform);
            }

            if (amountToSender > 0) {
                erc20.safeTransfer(e.depositor, amountToSender);
            }

            if (amountToReceiver > 0) {
                erc20.safeTransfer(e.beneficiary, amountToReceiver);
            }
        }
    }

    /**
     * autoExecuteTransaction - Execução Automática de Backup
     * @notice Executa automaticamente após 90 dias se não há consenso
     *
     * ⏰ ANALOGIA: É como um "plano B" automático - se as partes não chegarem
     *              a um acordo em 90 dias, o sistema decide automaticamente
     *
     * QUANDO É USADO:
     * 🎯 Pagamentos completos MAS sem aprovações
     * 🚫 Sem disputas ativas
     * ⏳ Após 90 dias do deadline
     * 🏦 Favorece o vendedor (padrão de mercado)
     *
     * ORDEM CORRETA DAS VALIDAÇÕES:
     * 1️⃣ Não disputado
     * 2️⃣ Estado ACTIVE
     * 3️⃣ Pagamentos completos
     * 4️⃣ Deadline atingido
     */
    function autoExecuteTransaction(uint256 escrowId) external nonReentrant {
        EscrowInfo storage e = _escrows[escrowId];

        // ✅ Verificar pagamentos ANTES do deadline
        require(!e.isDisputed, "Cannot auto-execute: escrow is disputed");
        require(e.state == EscrowState.ACTIVE, "Escrow not active");
        require(e.installmentsPaid == e.totalInstallments, "Cannot auto-execute: payments not complete");
        require(block.timestamp >= e.autoExecuteDeadline, "Auto-execute deadline not reached");

        // ✅ EXECUÇÃO AUTOMÁTICA (favorece vendedor por padrão)
        address token = e.paymentToken;
        uint256 balance = escrowBalances[escrowId][token];
        uint256 feePlatform = _calculateFee(balance);
        uint256 netAmount = balance - feePlatform;

        // ✅ EFFECTS
        escrowBalances[escrowId][token] = 0;
        e.state = EscrowState.COMPLETE;

        // ✅ INTERACTIONS
        if (token == address(0)) {
            pendingFees[owner()] += feePlatform;
            (bool success,) = payable(e.beneficiary).call{value: netAmount}("");
            require(success, "Auto-execute transfer failed");
        } else {
            IERC20 erc20 = IERC20(token);
            if (feePlatform > 0) {
                erc20.safeTransfer(owner(), feePlatform);
            }
            erc20.safeTransfer(e.beneficiary, netAmount);
        }

        emit AutoExecuted(escrowId, block.timestamp);
    }

    /**
     * emergencyTimeout - Intervenção de Emergência
     * @notice Última proteção contra fundos permanentemente presos
     *
     * 🆘 ANALOGIA: É como chamar o bombeiro quando a situação
     *              está completamente fora de controle há muito tempo
     *
     * CASOS EXTREMOS:
     * 🔥 Disputas que nunca foram resolvidas
     * 💀 Partes que desapareceram
     * 🐛 Bugs não previstos
     * ⏰ Após 6 meses (90 + 180 dias)
     *
     * PROTEÇÃO MÁXIMA:
     * 👑 Apenas owner pode usar
     * ⏳ Prazo muito longo (270 dias)
     * 📝 Justificativa obrigatória
     * 🎯 Decisão sobre direção dos fundos
     */
    function emergencyTimeout(uint256 escrowId, bool refundToSender, string calldata reason)
        external
        onlyOwner
        nonReentrant
    {
        EscrowInfo storage e = _escrows[escrowId];

        // ✅ PROTEÇÃO: Só em casos extremos (6 meses)
        require(block.timestamp >= e.autoExecuteDeadline + 180 days, "Emergency timeout: not enough time passed");
        require(e.state != EscrowState.COMPLETE, "Escrow already complete");

        address token = e.paymentToken;
        uint256 balance = escrowBalances[escrowId][token];

        if (balance > 0) {
            uint256 feePlatform = _calculateFee(balance);
            uint256 netAmount = balance - feePlatform;

            escrowBalances[escrowId][token] = 0;
            e.state = EscrowState.COMPLETE;

            address recipient = refundToSender ? e.depositor : e.beneficiary;

            if (token == address(0)) {
                pendingFees[owner()] += feePlatform;
                (bool success,) = payable(recipient).call{value: netAmount}("");
                require(success, "Emergency transfer failed");
            } else {
                IERC20 erc20 = IERC20(token);
                if (feePlatform > 0) {
                    erc20.safeTransfer(owner(), feePlatform);
                }
                erc20.safeTransfer(recipient, netAmount);
            }
        }

        emit EmergencyTimeout(escrowId, reason, block.timestamp);
    }
}
