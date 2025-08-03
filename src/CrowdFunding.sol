// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CampaignToken} from "./CampaignToken.sol";
import {Campaign} from "./interfaces/ICrowdfunding.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * 🏗️ CONTRATO DE CROWDFUNDING CVM 88
 * 
 * 📚 O QUE É ESTE CONTRATO?
 * 
 * Imagine que este contrato é como uma "feira de investimentos digital" onde:
 * - 🏢 EMPRESAS (criadores) podem criar "barracas" (campanhas) para captar dinheiro
 * - 👥 INVESTIDORES podem "comprar" participações nas empresas
 * - 🎯 Há regras claras para proteger todos os envolvidos
 * - ⚖️ Tudo segue as regras da CVM (Comissão de Valores Mobiliários)
 * 
 * 🎪 ANALOGIA: FEIRA DE INVESTIMENTOS
 * 
 * 1. 🏢 EMPRESA (Criador): "Quero abrir uma barraca na feira para vender minha ideia"
 * 2. 🎯 CAMPANHA: "Minha barraca precisa de R$ 100.000 a R$ 150.000 para funcionar"
 * 3. 👥 INVESTIDORES: "Vou dar R$ 1.000 para participar dessa empresa"
 * 4. ⏰ PRAZO: "A feira dura 30 dias, depois fechamos as barracas"
 * 5. 🎁 RESULTADO: Se der certo, investidores ganham tokens da empresa
 * 
 * 🔒 SEGURANÇAS IMPLEMENTADAS:
 * 
 * 🛡️ DIREITO DE ARREPENDIMENTO: Como comprar algo online e ter 5 dias para devolver
 * 💰 LIMITE ANUAL: Cada pessoa só pode investir até R$ 20.000 por ano
 * ⏰ PRAZO MÁXIMO: Campanhas não podem durar mais de 180 dias
 * 🎯 METAS CLARAS: Empresa precisa atingir pelo menos 2/3 da meta máxima
 * 
 * 💡 SISTEMA DE LÍDERES:
 * 
 * Imagine que alguns investidores são "influenciadores" da feira:
 * - 👑 LÍDER: "Se eu investir R$ 5.000, outros vão seguir meu exemplo"
 * - 💰 COMISSÃO: "Se a campanha der certo, ganho 10% extra como agradecimento"
 * - 🎯 QUALIFICAÇÃO: "Só ganho se realmente investir o valor mínimo prometido"
 * 
 * 🔄 SISTEMA DE TOKENS:
 * 
 * 1. 🎫 TOKEN TEMPORÁRIO: Como um "vale" que você recebe ao investir
 * 2. 🏆 TOKEN OFICIAL: Como "ações" da empresa que você recebe no final
 * 3. ⏰ VESTING: Como receber suas ações aos poucos (ex: 20% por mês)
 * 
 * 📊 ORÁCULOS DE PREÇO:
 * 
 * Como "termômetros digitais" que nos dizem o valor real das moedas:
 * - 💵 USD/BRL: "Quantos reais vale 1 dólar?"
 * - 🪙 ETH/USD: "Quantos dólares vale 1 Ethereum?"
 * - 🏦 USDC/USD: "O USDC está realmente valendo 1 dólar?"
 * 
 * 🚨 PROTEÇÕES ESPECIAIS:
 * 
 * 🔄 REENTRANCY: Impede que alguém "entre duas vezes" na mesma função
 * ⏰ SEQUENCIADOR: Verifica se a rede está funcionando corretamente
 * 📅 PREÇOS ATUALIZADOS: Rejeita preços com mais de 24 horas
 * 
 * @dev Contrato de crowdfunding compatível com as regras da Resolução CVM 88
 *      Principais características:
 *      - Aceita ETH ou tokens ERC20 como forma de pagamento
 *      - Implementa alvos mínimo e máximo com prazo máximo de 180 dias
 *      - Possui período de desistência de 5 dias (direito de arrependimento)
 *      - Controla limite anual de investimento por investidor
 *      - Sistema de Líderes:
 *          - Suporta múltiplos investidores líderes com aporte mínimo
 *          - Cada líder pode receber uma taxa de desempenho (carry) extra
 *          - O carry é definido em basis points (1/100 de um percentual)
 *          - Limite total de carry é 20%
 *          - O carry é distribuído após o término da campanha
 */
contract Crowdfunding is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    // ========================================
    // 🎭 ROLES (PAPÉIS) DOS PARTICIPANTES
    // ========================================
    
    /**
     * 👥 SISTEMA DE ROLES - COMO UMA EMPRESA REAL
     * 
     * 🏢 INVESTOR_ROLE: Como ser um "cliente cadastrado" da empresa
     *    - Precisa ser aprovado pelo administrador
     *    - Pode investir em campanhas
     *    - Tem limite anual de investimento
     * 
     * 👑 CREATOR_ROLE: Como ser um "fornecedor autorizado"
     *    - Pode criar campanhas
     *    - Pode estender prazos
     *    - Pode sacar fundos quando campanha der certo
     * 
     * 🛡️ DEFAULT_ADMIN_ROLE: Como ser o "gerente geral"
     *    - Pode aprovar novos investidores
     *    - Pode aprovar novos criadores
     *    - Pode ajustar limites anuais
     */
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

   // ========================================
    // 📊 ORÁCULOS DE PREÇO (TERMÔMETROS DIGITAIS)
    // ========================================
    
    /**
     * 🌡️ ORÁCULOS - COMO TERMÔMETROS QUE NUNCA MENTEM
     * 
     * Imagine que cada oráculo é um "termômetro especializado":
     * 
     * 🔍 SEQUENCER: "A rede está funcionando bem?"
     *    - Como verificar se o "sistema elétrico" da feira está ok
     * 
     * 💵 USDC/USD: "1 USDC = 1 USD mesmo?"
     *    - Como verificar se a "moeda estável" não perdeu valor
     * 
     * 🏦 USDT/USD: "1 USDT = 1 USD mesmo?"
     *    - Outra verificação de moeda estável
     * 
     * 🇧🇷 BRL/USD: "Quantos reais vale 1 dólar?"
     *    - Para calcular limites em reais (CVM 88)
     * 
     * 🪙 ETH/USD: "Quantos dólares vale 1 Ethereum?"
     *    - Para investimentos em Ethereum
     */
    AggregatorV2V3Interface private immutable sequencerUptimeFeed;
    AggregatorV2V3Interface private immutable usdcPriceFeed;
    AggregatorV2V3Interface private immutable usdtPriceFeed;
    AggregatorV2V3Interface private immutable brlPriceFeed;
    AggregatorV2V3Interface private immutable ethPriceFeed;

     /**
     * ⏰ GRACE PERIOD - PERÍODO DE GRAÇA
     * 
     * Como um "período de aquecimento" após a rede voltar:
     * - Se a rede ficou instável, esperamos 1 hora antes de aceitar transações
     * - Evita problemas com preços desatualizados
     */
    uint256 private constant GRACE_PERIOD_TIME = 3600;

     // ========================================
    // 🚨 ERROS PERSONALIZADOS (MENSAGENS DE ERRO)
    // ========================================
    
    /**
     * ❌ ERROS PERSONALIZADOS - COMO AVISOS ESPECÍFICOS
     * 
     * 🚫 SequencerDown: "A rede está instável, tente novamente em 1 hora"
     * ⏰ GracePeriodNotOver: "Ainda estamos no período de aquecimento"
     * 📅 StalePrice: "Este preço está muito antigo, não podemos confiar"
     */
    error SequencerDown();
    error GracePeriodNotOver();
    error StalePrice();

    // ========================================
    // 📊 TIPOS DE DADOS
    // ========================================

    
    // ========================================
    // 📋 ESTRUTURAS DE DADOS (COMO FORMULÁRIOS)
    // ========================================
    
    /**
     * 💼 INVESTMENT - COMO UM "EXTRATO BANCÁRIO" DO INVESTIDOR
     * 
     * Imagine que cada investimento é como uma "conta bancária" para cada pessoa:
     * 
     * 💰 amount: "Quanto dinheiro esta pessoa investiu no total?"
     *    - Como o saldo da conta bancária
     * 
     * ✅ claimed: "Esta pessoa já sacou o dinheiro/tokens?"
     *    - Como verificar se já foi ao banco sacar
     * 
     * ⏰ investTime: "Quando foi o último investimento?"
     *    - Para calcular os 5 dias de direito de arrependimento
     * 
     * 📅 investmentDates: "Quando foi cada investimento específico?"
     *    - Como um histórico detalhado de cada depósito
     * 
     * 💵 investmentAmounts: "Quanto foi cada investimento específico?"
     *    - Como saber exatamente quanto foi cada depósito
     * 
     * 🔢 investmentCount: "Quantos investimentos esta pessoa fez?"
     *    - Como contar quantas vezes foi ao banco depositar
     */
    struct Investment {
        uint256 amount; // Total amount invested
        bool claimed; // Se já sacou reembolso ou tokens
        uint256 investTime; // Momento do último aporte (para o período de 5 dias)
        mapping(uint256 => uint256) investmentDates; // ID => timestamp of each investment
        mapping(uint256 => uint256) investmentAmounts; // ID => amount of each investment
        uint256 investmentCount; // Number of investments made
    }

    // ========================================
    // 📝 EVENTOS (COMO NOTAS DE LANÇAMENTO)
    // ========================================
    
    /**
     * 📢 EVENTOS - COMO "NOTIFICAÇÕES" DO SISTEMA
     * 
     * Imagine que cada evento é como um "WhatsApp" que avisa quando algo importante acontece:
     * 
     * 🚀 CampaignLaunched: "Nova barraca abriu na feira!"
     *    - id: "Qual é o número da barraca?"
     *    - creator: "Quem é o dono da barraca?"
     *    - minTarget/maxTarget: "Quanto dinheiro precisa?"
     *    - startAt/endAt: "Quando abre e fecha?"
     *    - paymentToken: "Que moeda aceita?"
     *    - officialToken: "Que token vai dar em troca?"
     *    - investorLeaders: "Quem são os influenciadores?"
     *    - leaderMinContrib: "Quanto cada líder precisa investir?"
     *    - leaderCarryBP: "Quanto de comissão cada líder ganha?"
     * 
     * ⏰ DeadlineExtended: "A barraca vai ficar aberta por mais tempo!"
     * 
     * 💰 Invested: "Alguém investiu na barraca!"
     *    - amount: "Quanto investiu?"
     *    - investmentCount: "Quantas vezes já investiu?"
     *    - investmentDate: "Quando investiu?"
     *    - investmentAmount: "Quanto foi este investimento específico?"
     * 
     * 🔄 Desisted: "Alguém desistiu do investimento (dentro dos 5 dias)!"
     * 
     * 💸 RefundClaimed: "Alguém sacou o reembolso (campanha falhou)!"
     * 
     * 🎉 CreatorClaimed: "O dono da barraca sacou o dinheiro (deu certo)!"
     *    - netAmount: "Quanto o criador recebeu?"
     *    - feeAmount: "Quanto a plataforma ganhou?"
     * 
     * 🎫 TokensClaimed: "Alguém sacou os tokens da empresa!"
     * 
     * 🔄 TokensSwapped: "Alguém trocou tokens temporários por oficiais!"
     *    - amount: "Quantos tokens temporários trocou?"
     *    - vestedAmount: "Quantos tokens oficiais recebeu?"
     */
    event CampaignLaunched(
        uint256 indexed id,
        address indexed creator,
        uint256 minTarget,
        uint256 maxTarget,
        uint32 startAt,
        uint32 endAt,
        address paymentToken,
        address officialToken,
        address[] investorLeaders,
        uint256[] leaderMinContrib,
        uint256[] leaderCarryBP
    );

    event DeadlineExtended(uint256 indexed id, uint32 newEndAt);
    event Invested(
        uint256 indexed id,
        address indexed investor,
        uint256 amount,
        uint256 investmentCount,
        uint256 investmentDate,
        uint256 investmentAmount
    );
    event Desisted(uint256 indexed id, address indexed investor, uint256 refunded);
    event RefundClaimed(uint256 indexed id, address indexed investor, uint256 amount);
    event CreatorClaimed(uint256 indexed id, uint256 netAmount, uint256 feeAmount);
    event TokensClaimed(uint256 indexed id, address indexed investor, uint256 amount);
    event TokensSwapped(uint256 indexed id, address indexed investor, uint256 amount, uint256 vestedAmount);
    
    /**
     * 💾 VARIÁVEIS DE ESTADO - COMO "ARQUIVOS" DO SISTEMA
     * 
     * Imagine que estas variáveis são como "pastas" no computador que guardam informações:
     * 
     * 🔢 campaignCount: "Quantas barracas já foram criadas na feira?"
     *    - Como um contador que aumenta a cada nova campanha
     * 
     * 📁 campaigns: "Informações de todas as barracas"
     *    - Como uma pasta com fichas de cada barraca
     *    - campaignId => "Ficha da barraca número X"
     * 
     * 💼 investments: "Quem investiu em cada barraca"
     *    - Como um registro de "quem deu dinheiro para qual barraca"
     *    - campaignId => investor => "Extrato bancário da pessoa"
     * 
     * ⏰ lastCampaignTimestamp: "Quando foi a última barraca de cada criador?"
     *    - Para controlar o período de "descanso" entre campanhas
     *    - Como um "calendário" que mostra quando cada pessoa pode criar nova barraca
     * 
     * 💰 investedThisYear: "Quanto cada pessoa investiu este ano?"
     *    - Para controlar o limite anual de R$ 20.000
     *    - Como um "extrato anual" de cada investidor
     * 
     * 🕐 investorStartTime: "Quando começou o ano para cada investidor?"
     *    - Para resetar o limite anual após 365 dias
     *    - Como um "aniversário" de cada investidor no sistema
     * 
     * 🇧🇷 investedBRLThisYear: "Quanto cada pessoa investiu em reais este ano?"
     *    - Para calcular o limite em reais (CVM 88)
     *    - Como um "extrato em reais" de cada investidor
     * 
     * 🎯 MAX_ANNUAL_LIMIT: "Qual é o limite anual de investimento?"
     *    - Configurável pelo administrador
     *    - Padrão: R$ 20.000 por ano por pessoa
     * 
     * 🏆 officialToken: "Qual é o token oficial que todos recebem?"
     *    - Token que representa participação nas empresas
     *    - Como "ações" que todos os investidores recebem
     */
    uint256 public campaignCount;
    mapping(uint256 => Campaign) internal campaigns;
    // campaignId => (investor => Investment)
    mapping(uint256 => mapping(address => Investment)) internal investments;

    // Track creator's last campaign timestamp
    mapping(address => uint256) public lastCampaignTimestamp;

    // Controle de quem pode investir e quanto no ano
    mapping(address => uint256) public investedThisYear;
    mapping(address => uint256) public investorStartTime;

    // Para rastrear o valor investido em USD
    mapping(address => uint256) public investedBRLThisYear;

    uint256 public MAX_ANNUAL_LIMIT;

    // Token oficial "global" (pode ser substituído pela campaign.officialToken)
    IERC20 public immutable officialToken;

     /**
     * 🪙 ENDEREÇOS DOS TOKENS - COMO "CÓDIGOS DE BARRAS" DAS MOEDAS
     * 
     * 💵 USDC: "Dólar digital estável" (1 USDC = 1 USD)
     *    - Como ter dólares no banco, mas digitais
     * 
     * 🏦 USDT: "Outro dólar digital estável" (1 USDT = 1 USD)
     *    - Como ter dólares em outro banco
     * 
     * 🪙 ETH: "Ethereum" (valor varia conforme mercado)
     *    - Como ter ouro digital
     */
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; 
    address public constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address public constant ETH = 0x4200000000000000000000000000000000000006;
    // Limites fixos da CVM 88
    uint256 public constant MAX_CAMPAIGN_TARGET = 15_000_000 ether; // 15M BRL c/ 18 dec.
    uint32 public constant MAX_CAMPAIGN_DURATION = 180 days;
    uint32 public constant DESIST_PERIOD = 5 days;
    uint256 public constant MAX_CAMPAIGN_FEE = 1000; // 10%
    uint32 public constant MAX_PERIOD_INVESTOR = 365 days;
    uint256 public constant DIVISOR_FACTOR = 10000; // 10%

    uint32 public constant CREATOR_COOLDOWN = 120 days;

     // ========================================
    // 🏗️ CONSTRUTOR (COMO "INAUGURAÇÃO" DA FEIRA)
    // ========================================
    
    /**
     * 🏗️ CONSTRUTOR - COMO "INAUGURAR" A FEIRA DE INVESTIMENTOS
     * 
     * Imagine que este construtor é como "abrir" a feira pela primeira vez:
     * 
     * 🎯 _officialToken: "Qual token vamos dar para os investidores?"
     *    - Como definir qual "moeda" da feira todos vão receber
     * 
     * 👑 _owner: "Quem é o dono da feira?"
     *    - Como definir quem é o "gerente geral" que pode aprovar pessoas
     * 
     * 🔍 _sequencerUptimeFeed: "Qual termômetro verifica se a rede está ok?"
     *    - Como instalar o "sistema de alarme" que avisa se algo está errado
     * 
     * 💵 _usdcPriceFeed: "Qual termômetro verifica o preço do USDC?"
     *    - Como instalar o "termômetro do dólar digital"
     * 
     * 🏦 _usdtPriceFeed: "Qual termômetro verifica o preço do USDT?"
     *    - Como instalar outro "termômetro do dólar digital"
     * 
     * 🇧🇷 _brlPriceFeed: "Qual termômetro verifica o preço do real?"
     *    - Como instalar o "termômetro do real" para calcular limites
     * 
     * 🪙 _ethPriceFeed: "Qual termômetro verifica o preço do Ethereum?"
     *    - Como instalar o "termômetro do ouro digital"
     * 
     * 🚀 O QUE ACONTECE NA INAUGURAÇÃO:
     * 1. ✅ Define quem é o gerente geral (DEFAULT_ADMIN_ROLE)
     * 2. ✅ Instala todos os "termômetros" de preço
     * 3. ✅ Define qual token oficial será usado
     * 4. ✅ A feira está pronta para receber barracas!
     */
    constructor(
        address _officialToken,
        address _owner,
        address _sequencerUptimeFeed,
        address _usdcPriceFeed,
        address _usdtPriceFeed,
        address _brlPriceFeed,
        address _ethPriceFeed
    ) {
         // 👑 Definir o gerente geral da feira
        (bool success) = _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        require(success, "Failed to grant DEFAULT_ADMIN_ROLE");

        // 🏆 Definir qual token oficial será usado
        officialToken = IERC20(_officialToken);

        // 🌡️ Instalar todos os "termômetros" de preço
        sequencerUptimeFeed = AggregatorV2V3Interface(_sequencerUptimeFeed);
        usdcPriceFeed = AggregatorV2V3Interface(_usdcPriceFeed);
        usdtPriceFeed = AggregatorV2V3Interface(_usdtPriceFeed);
        brlPriceFeed = AggregatorV2V3Interface(_brlPriceFeed);
        ethPriceFeed = AggregatorV2V3Interface(_ethPriceFeed);
    }

    // ========================================
    // 🔐 MODIFIERS (COMO "CARTÕES DE ACESSO")
    // ========================================
    
    /**
     * 🔐 MODIFIERS - COMO "CARTÕES DE ACESSO" ESPECIAIS
     * 
     * Imagine que modifiers são como "cartões de acesso" que verificam se você pode entrar:
     * 
     * 🎫 onlyAllowedCreator: "Só o dono da barraca pode fazer isso"
     *    - Como verificar se você é realmente o dono da barraca
     *    - Impede que outras pessoas mexam na sua barraca
     */
    modifier onlyAllowedCreator(uint256 _id) {
        require(campaigns[_id].creator == msg.sender, "Creator not allowed");
        _;
    }

      /**
     * 👥 setAllowedInvestor - COMO "CADASTRAR CLIENTES" NA FEIRA
     * 
     * Imagine que esta função é como "cadastrar" pessoas para poderem investir:
     * 
     * 📝 investors: "Lista de pessoas que querem ser clientes"
     * ✅ allowed: "Se queremos aprovar ou não essas pessoas"
     * 
     * 🚀 O QUE ACONTECE:
     * 1. ✅ Para cada pessoa na lista, dá o "cartão de cliente"
     * 2. ✅ Se está aprovando, marca quando começou o "ano" para essa pessoa
     * 3. ✅ Agora essas pessoas podem investir na feira!
     * 
     * 💡 ANALOGIA: Como um gerente de banco aprovando novos clientes
     */
    function setAllowedInvestor(address[] memory investors, bool allowed) external {
        for (uint256 i = 0; i < investors.length; i++) {
            // 🎫 Dar o "cartão de cliente" para a pessoa
            grantRole(INVESTOR_ROLE, investors[i]); //ja checa se eh o Admin aqui
            if (allowed) {
                // ⏰ Se está aprovando, marcar quando começou o "ano" para essa pessoa
                investorStartTime[investors[i]] = block.timestamp;
            }
        }
    }

    
    /**
     * 👑 setAllowedCreator - COMO "AUTORIZAR FORNECEDORES" NA FEIRA
     * 
     * Imagine que esta função é como "autorizar" pessoas para criarem barracas:
     * 
     * 🏢 creators: "Lista de pessoas que querem criar barracas"
     * 
     * 🚀 O QUE ACONTECE:
     * 1. ✅ Para cada pessoa na lista, dá o "cartão de fornecedor"
     * 2. ✅ Agora essas pessoas podem criar campanhas na feira!
     * 
     * 💡 ANALOGIA: Como um gerente de shopping autorizando lojas para abrirem
     */
    function setAllowedCreator(address[] memory creators) external {
        for (uint256 i = 0; i < creators.length; i++) {
            // 🎫 Dar o "cartão de fornecedor" para a pessoa
            grantRole(CREATOR_ROLE, creators[i]); //ja checa se eh o Admin aqui
        }
    }

     /**
     * 💰 setAnnualLimit - COMO "DEFINIR LIMITE DE CRÉDITO" ANUAL
     * 
     * Imagine que esta função é como "definir" quanto cada pessoa pode gastar por ano:
     * 
     * 💵 usdLimit: "Qual é o limite em dólares?" (ex: $3.400 USD)
     * 
     * 🚀 O QUE ACONTECE:
     * 1. 🔄 Converte o limite de dólares para reais (usando termômetro de preço)
     * 2. 💾 Guarda o limite em reais no sistema
     * 3. ✅ Agora todos sabem qual é o limite anual!
     * 
     * 💡 ANALOGIA: Como um gerente de banco definindo limite de cartão de crédito
     * 
     * 📊 EXEMPLO:
     * - Entrada: $3.400 USD
     * - Conversão: $3.400 × 5 BRL/USD = R$ 17.000
     * - Resultado: Cada pessoa pode investir até R$ 17.000 por ano
     */
    function setAnnualLimit(uint256 usdLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // 🔄 Converter limite de dólares para reais
        uint256 brlLimit = getBRLPrice(usdLimit);
        //require(brlLimit <= 20000e18, "Exceeds 20,000 BRL limit"); // 20_000 BRL with 18 decimals

        // 💾 Guardar o limite em reais no sistema
        MAX_ANNUAL_LIMIT = brlLimit;
    }

    // ========================================
    // 🚀 CRIAÇÃO DE CAMPANHA (COMO "ABRIR UMA BARRACA" NA FEIRA)
    // ========================================
    
    /**
     * 🚀 launchCampaign - COMO "ABRIR UMA BARRACA" NA FEIRA DE INVESTIMENTOS
     * 
     * Imagine que esta função é como "abrir" uma nova barraca na feira:
     * 
     * 🎯 PARÂMETROS PRINCIPAIS:
     * 
     * 💰 _minTarget: "Qual é o mínimo que preciso para funcionar?"
     *    - Como definir o "mínimo necessário" para a barraca funcionar
     *    - Exemplo: "Preciso de pelo menos R$ 100.000"
     * 
     * 🎯 _maxTarget: "Qual é o máximo que posso receber?"
     *    - Como definir o "limite máximo" que a barraca pode receber
     *    - Exemplo: "Posso receber até R$ 150.000"
     * 
     * ⏰ _startAt: "Quando a barraca abre?"
     *    - Data e hora de início da campanha
     * 
     * ⏰ _endAt: "Quando a barraca fecha?"
     *    - Data e hora de fim da campanha
     * 
     * 🔄 _vestingStart: "Quando começo a dar as ações aos poucos?"
     *    - Quando começa o "pagamento parcelado" de tokens
     * 
     * ⏱️ _vestingDuration: "Por quanto tempo dou as ações?"
     *    - Duração do "pagamento parcelado" (ex: 180 dias)
     * 
     * 💵 _paymentToken: "Que moeda aceito?"
     *    - USDC, USDT ou ETH
     * 
     * 🏆 _officialToken: "Que token vou dar em troca?"
     *    - Token que representa participação na empresa
     * 
     * 💸 _platformFeeBP: "Quanto a feira cobra de comissão?"
     *    - Taxa da plataforma em basis points (ex: 500 = 5%)
     * 
     * 🏦 _platformWallet: "Para onde vai a comissão da feira?"
     *    - Carteira que recebe as taxas da plataforma
     * 
     * 👑 _creatorWallet: "Quem é o dono da barraca?"
     *    - Endereço do criador da campanha
     * 
     * 🏛️ _creatorVault: "Para onde vai o dinheiro da barraca?"
     *    - Carteira que recebe os fundos da campanha
     * 
     * 👑 _leaders: "Quem são os influenciadores?"
     *    - Lista de endereços dos líderes
     * 
     * 💰 _leaderMinContribs: "Quanto cada líder precisa investir?"
     *    - Valor mínimo que cada líder deve aportar
     * 
     * 💸 _leaderCarryBP: "Quanto de comissão cada líder ganha?"
     *    - Taxa de desempenho de cada líder (ex: 1000 = 10%)
     * 
     * 🚀 O QUE ACONTECE QUANDO ABRE A BARRACA:
     * 1. ✅ Verifica se o criador não está em "período de descanso"
     * 2. ✅ Valida todas as regras da CVM 88
     * 3. ✅ Cria o token temporário da campanha
     * 4. ✅ Configura os líderes e suas comissões
     * 5. ✅ Emite evento "Nova barraca abriu!"
     * 
     * 💡 ANALOGIA: Como abrir uma loja no shopping com todas as autorizações
     */
    /**
     * @dev Incluímos parâmetros para lidar com investidor líder:
     *      `_leaders`, `_leaderMinContribs`, `_leaderCarryBP`.
     *
     * @param _minTarget Valor mínimo alvo da campanha
     * @param _maxTarget Valor máximo alvo da campanha
     * @param _startAt Data de início
     * @param _endAt Data de término
     * @param _vestingStart Início do vesting
     * @param _vestingDuration Duração do vesting
     * @param _paymentToken Token aceito para pagamento
     * @param _officialToken Token oficial da campanha (use address(0) para usar o token global)
     * @param _platformFeeBP Taxa da plataforma em basis points
     * @param _platformWallet Carteira da plataforma
     * @param _creatorWallet Carteira do criador
     * @param _creatorVault Vault do criador
     * @param _leaders Array de endereços dos líderes
     * @param _leaderMinContribs Array com valor mínimo que cada líder deve aportar
     * @param _leaderCarryBP Array com taxa de desempenho de cada líder
     */
    function launchCampaign(
        uint256 _minTarget,
        uint256 _maxTarget,
        uint32 _startAt,
        uint32 _endAt,
        uint32 _vestingStart,
        uint32 _vestingDuration,
        address _paymentToken,
        address _officialToken,
        uint256 _platformFeeBP,
        address _platformWallet,
        address _creatorWallet,
        address _creatorVault,
        address[] memory _leaders,
        uint256[] memory _leaderMinContribs,
        uint256[] memory _leaderCarryBP
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        require(
            _leaderMinContribs.length == _leaderCarryBP.length && _leaderMinContribs.length == _leaders.length,
            "leaderMinContribs and leaderCarryBP must have the same length"
        );
        require(_leaders.length <= 5, "Max 5 leaders");
        // Check creator cooldown period
        require(
            block.timestamp >= lastCampaignTimestamp[_creatorWallet] + CREATOR_COOLDOWN, "Creator in cooldown period"
        );

        require(isUSDC(_paymentToken) || isUSDT(_paymentToken) || isETH(_paymentToken), "Only USDC/USDT/ETH  accepted");
        require(_startAt >= block.timestamp, "Invalid start time");
        require(_endAt > _startAt, "endAt must be > startAt");
        require(_endAt <= _startAt + MAX_CAMPAIGN_DURATION, "Exceeds 180 days");
        require(_minTarget > 0 && _maxTarget >= _minTarget, "Invalid targets");
        require(_minTarget * 3 >= _maxTarget * 2, "minTarget < 2/3 of maxTarget");
        require(_maxTarget <= MAX_CAMPAIGN_TARGET, "Exceeds 15M CVM limit");
        require(_platformFeeBP <= MAX_CAMPAIGN_FEE, "Fee too high (max 10%)");
        require(_creatorWallet != address(0), "Invalid fee wallet");
        
        // Determine which official token to use
        address tokenToUse = _officialToken == address(0) ? address(officialToken) : _officialToken;
        
        // Check if contract has enough official tokens to cover max target
        uint256 contractBalance = IERC20(tokenToUse).balanceOf(address(this));
        require(contractBalance >= _maxTarget, "Insufficient official tokens");

        campaignCount++;
        Campaign storage c = campaigns[campaignCount];
        c.creator = _creatorWallet;
        grantRole(CREATOR_ROLE, _creatorWallet);
        c.creatorVault = _creatorVault;
        c.minTarget = _minTarget;
        c.maxTarget = _maxTarget;
        c.startAt = _startAt;
        c.endAt = _endAt;
        c.vestingStart = _vestingStart;
        c.vestingDuration = _vestingDuration;
        c.paymentToken = _paymentToken;
        c.platformFeeBP = _platformFeeBP;
        c.platformWallet = _platformWallet;
        
        // Use global officialToken as fallback if _officialToken is zero
        c.officialToken = _officialToken == address(0) ? address(officialToken) : _officialToken;

        // -- Investidores Líderes --
        uint256 totalCarryBP = 0;
        for (uint256 i = 0; i < _leaders.length; i++) {
            c.investorLeaders.push(_leaders[i]);
            c.leaderQualified.push(false);
            c.leaderMinContribution.push(_leaderMinContribs[i]);
            totalCarryBP += _leaderCarryBP[i];
            require(totalCarryBP <= 2000, "Total carry exceeds 20%"); // Check cumulative carry
            c.leaderCarryBP.push(_leaderCarryBP[i]);
        }

        // Create campaign token
        string memory name = string(abi.encodePacked("Campaign ", campaignCount.toString(), " Token"));
        string memory symbol = string(abi.encodePacked("CAMP", campaignCount.toString()));
        address campaignToken = address(new CampaignToken(name, symbol, address(this), campaignCount));
        c.campaignToken = campaignToken;

        // Update creator's last campaign timestamp
        lastCampaignTimestamp[_creatorWallet] = block.timestamp;

        emit CampaignLaunched(
            campaignCount,
            msg.sender,
            _minTarget,
            _maxTarget,
            _startAt,
            _endAt,
            _paymentToken,
            c.officialToken, // Use the actual token that will be used
            _leaders,
            _leaderMinContribs,
            _leaderCarryBP
        );
        return campaignCount;
    }

    /**
     * 📅 EXTEND DEADLINE - COMO "ESTENDER O TEMPO" DA BARRACA
     * 
     * Imagine que esta função é como "estender" o prazo de uma barraca:
     * 
     * 🔄 PARÂMETROS PRINCIPAIS:
     * 
     * 📅 _id: "Qual é o número da barraca?"
     *    - Como identificar a barraca
     * 
     * ⏰ _newEndAt: "Quando a barraca fecha?"
     *    - Nova data e hora de término
     * 
     * 💡 ANALOGIA: Como estender o prazo de uma loja no shopping
     */
    function extendDeadline(uint256 _id, uint32 _newEndAt) external {
        Campaign storage c = campaigns[_id];
        require(msg.sender == c.creator, "Not campaign creator");
        require(_newEndAt > c.endAt, "newEndAt <= old endAt");
        require(_newEndAt <= c.startAt + MAX_CAMPAIGN_DURATION, "Exceeds 180 days");

        c.endAt = _newEndAt;
        emit DeadlineExtended(_id, _newEndAt);
    }

    // ========================================
    // 💰 INVESTIMENTO (COMO "COMPRAR" PARTICIPAÇÃO NA BARRACA)
    // ========================================
    
    /**
     * 💰 invest - COMO "COMPRAR" PARTICIPAÇÃO EM UMA BARRACA
     * 
     * Imagine que esta função é como "comprar" uma participação em uma barraca da feira:
     * 
     * 🎯 PARÂMETROS:
     * 
     * 🔢 _campaignId: "Qual barraca quero comprar?"
     *    - ID da campanha (barraca) onde quer investir
     * 
     * 💵 _amount: "Quanto quero investir?"
     *    - Quantidade de dinheiro que quer investir
     * 
     * 🚀 O QUE ACONTECE QUANDO INVESTE:
     * 
     * 1. ✅ VERIFICAÇÕES DE SEGURANÇA:
     *    - "A barraca está aberta?" (dentro do prazo)
     *    - "A barraca ainda não fechou?" (não atingiu limite)
     *    - "Tenho cartão de cliente?" (INVESTOR_ROLE)
     * 
     * 2. 💰 CÁLCULOS DE LIMITE:
     *    - "Quanto posso investir sem ultrapassar o limite da barraca?"
     *    - "Não ultrapassei meu limite anual?"
     *    - "Quanto isso vale em reais?" (para CVM 88)
     * 
     * 3. 🎫 RECEBIMENTO DE TOKENS:
     *    - "Recebo tokens temporários da barraca"
     *    - "Como um 'vale' que posso trocar depois"
     * 
     * 4. 👑 VERIFICAÇÃO DE LÍDERES:
     *    - "Sou um líder desta barraca?"
     *    - "Atingi o valor mínimo para ganhar comissão?"
     * 
     * 5. ⏰ FECHAMENTO AUTOMÁTICO:
     *    - "Se a barraca atingiu o limite, fecha automaticamente"
     * 
     * 💡 ANALOGIA: Como comprar ações de uma empresa em uma bolsa de valores
     * 
     * 🔄 DIREITO DE ARREPENDIMENTO:
     * - "Tenho 5 dias para desistir do investimento"
     * - "Como devolver algo comprado online"
     * 
     * 📊 EXEMPLO:
     * - Investimento: R$ 1.000 em uma barraca
     * - Recebo: 1.000 tokens temporários da barraca
     * - Posso: Trocar por tokens oficiais da empresa depois
     */
    /**
     * @dev Incluímos parâmetros para lidar com investidor líder:
     *      `_leaders`, `_leaderMinContribs`, `_leaderCarryBP`.
     *
     * @param _campaignId ID da campanha
     * @param _amount Quantidade de dinheiro que o investidor quer investir
     */
    function invest(uint256 _campaignId, uint256 _amount) external payable nonReentrant onlyRole(INVESTOR_ROLE) {
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp >= c.startAt, "Not started");
        require(block.timestamp <= c.endAt, "Campaign ended");
        require(!c.claimed, "Creator already claimed");
        require(_amount > 0, "No amount");

        // Calculate how much more we can accept
        uint256 remainingToMax = c.maxTarget - c.pledged;
        require(remainingToMax > 0, "Campaign is full");

        // If amount would exceed maxTarget, adjust it
        // se o valor que ele está investindo for maior que o valor restante para atingir o maxTarget, ajusta o valor para o valor restante
        uint256 acceptedAmount = _amount;
        uint256 excessAmount = 0;
        if (_amount > remainingToMax) {
            acceptedAmount = remainingToMax;
            excessAmount = _amount - remainingToMax;
        }

        // valida se o valor aceito é maior que 0
        validateCampaignAmount(acceptedAmount, c.paymentToken);

        // Reseta limite anual se passou 1 ano
        if (block.timestamp >= investorStartTime[msg.sender] + MAX_PERIOD_INVESTOR) {
            investedBRLThisYear[msg.sender] = 0;
            investorStartTime[msg.sender] = block.timestamp;
        }

        // Calculate BRL value of this investment
        uint256 usdValue = calculateUSDValue(acceptedAmount, c.paymentToken);
        uint256 brlValue = getBRLPrice(usdValue);

        uint256 limit = MAX_ANNUAL_LIMIT;
        if (limit > 0) {
            require(investedBRLThisYear[msg.sender] + brlValue <= limit, "Exceeds your annual BRL limit");
            investedBRLThisYear[msg.sender] += brlValue;
        }

        // Effects: Update state variables
        c.pledged += acceptedAmount;
        Investment storage inv = investments[_campaignId][msg.sender];
        inv.amount += acceptedAmount;
        inv.investTime = block.timestamp;
        inv.investmentCount++;
        inv.investmentDates[inv.investmentCount] = block.timestamp;
        inv.investmentAmounts[inv.investmentCount] = acceptedAmount; // Store individual investment amount

        // Check leader qualification
        for (uint256 i = 0; i < c.investorLeaders.length; i++) {
            if (msg.sender == c.investorLeaders[i] && !c.leaderQualified[i]) {
                if (inv.amount >= c.leaderMinContribution[i]) {
                    c.leaderQualified[i] = true;
                }
            }
        }

        // If we've reached maxTarget, end the campaign early
        // se o valor total investido for igual ao maxTarget, termina a campanha
        if (c.pledged == c.maxTarget) {
            c.endAt = uint32(block.timestamp);
            emit DeadlineExtended(_campaignId, uint32(block.timestamp));
        }

        // Interactions: Handle token transfers
        // se o token for ETH, verifica se o valor enviado é maior ou igual ao valor aceito
        if (c.paymentToken == address(0)) {
            // ETH
            require(msg.value >= _amount, "Insufficient ETH");

            // Return excess ETH if any
            // se houver excesso, retorna o excesso para o endereço de interação
            if (excessAmount > 0) {
                (bool refundSuccess,) = payable(msg.sender).call{value: excessAmount}("");
                require(refundSuccess, "ETH refund failed");
            }
        } else {
            // ERC20
            // transfere o valor aceito para o contrato
            IERC20(c.paymentToken).safeTransferFrom(msg.sender, address(this), acceptedAmount);
            // se houver excesso, transfere o excesso para o endereço de interação
            // Return excess tokens if any
            if (excessAmount > 0) {
                IERC20(c.paymentToken).safeTransfer(msg.sender, excessAmount);
            }
        }

        // Mint campaign tokens for the accepted amount
        // criação de tokens para o investidor
        CampaignToken(c.campaignToken).mint(msg.sender, acceptedAmount);

        // emite o evento de investimento
        emit Invested(
            _campaignId,
            msg.sender,
            acceptedAmount,
            inv.investmentCount,
            inv.investmentDates[inv.investmentCount],
            inv.investmentAmounts[inv.investmentCount]
        );
    }

    /**
     * 🔄 desist - COMO "DEVOLVER" UM INVESTIMENTO (DIREITO DE ARREPENDIMENTO)
     * 
     * Imagine que esta função é como "devolver" algo que você comprou online:
     * 
     * 🎯 PARÂMETROS:
     * 
     * 🔢 _campaignId: "De qual barraca quero desistir?"
     *    - ID da campanha onde fez o investimento
     * 
     * 🔢 _investmentId: "Qual investimento específico quero desistir?"
     *    - ID do investimento específico (pode ter feito vários)
     * 
     * 🚀 O QUE ACONTECE QUANDO DESISTE:
     * 
     * 1. ✅ VERIFICAÇÕES:
     *    - "Fiz algum investimento nesta barraca?"
     *    - "A barraca ainda não fechou?" (não posso desistir depois)
     *    - "Estou dentro dos 5 dias de direito de arrependimento?"
     *    - "Este investimento específico existe?"
     * 
     * 2. 💰 CÁLCULO DO REEMBOLSO:
     *    - "Quanto foi este investimento específico?"
     *    - "Vou receber exatamente o que investi de volta"
     * 
     * 3. 🔄 ATUALIZAÇÃO DO ESTADO:
     *    - "Diminuo o total investido na barraca"
     *    - "Marco este investimento como desistido"
     *    - "Se foi o último investimento, marco como 'sacado'"
     * 
     * 4. 💸 REEMBOLSO AUTOMÁTICO:
     *    - "Recebo o dinheiro de volta automaticamente"
     *    - "ETH volta para minha carteira"
     *    - "USDC/USDT volta para minha carteira"
     * 
     * 💡 ANALOGIA: Como devolver um produto comprado online dentro do prazo
     * 
     * ⏰ PRAZO DE 5 DIAS:
     * - "Como o direito de arrependimento do Código de Defesa do Consumidor"
     * - "Posso desistir de qualquer investimento dentro de 5 dias"
     * 
     * 📊 EXEMPLO:
     * - Investimento 1: R$ 500 (feito há 3 dias) ✅ Pode desistir
     * - Investimento 2: R$ 300 (feito há 6 dias) ❌ Não pode desistir
     * - Resultado: Desiste do investimento 1, recebe R$ 500 de volta
     * 
     * @dev Direito de desistência em até 5 dias.
     * @param _campaignId ID da campanha
     * @param _investmentId ID do investimento específico a ser desistido
     */
    function desist(uint256 _campaignId, uint256 _investmentId) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];
        Investment storage investment = investments[_campaignId][msg.sender];

        require(investment.amount > 0, "No investment found");
        require(!investment.claimed, "Already claimed");
        require(block.timestamp < campaign.endAt, "Campaign ended");
        require(_investmentId > 0 && _investmentId <= investment.investmentCount, "Invalid investment ID");

        // Check 5-day period for specific investment
        require(
            block.timestamp <= investment.investmentDates[_investmentId] + DESIST_PERIOD,
            "Withdrawal period expired for this investment"
        );

        // Get the specific investment amount
        uint256 refundAmount = investment.investmentAmounts[_investmentId];
        require(refundAmount > 0, "Investment already desisted");

        // Update state
        investment.amount -= refundAmount;
        campaign.pledged -= refundAmount;

        // Clear the investment record
        investment.investmentAmounts[_investmentId] = 0;
        investment.investmentDates[_investmentId] = 0;

        // If this was the last investment, mark as claimed
        if (investment.amount == 0) {
            investment.claimed = true;
        }

        // Return funds
        if (campaign.paymentToken == address(0)) {
            // ETH
            (bool success,) = payable(msg.sender).call{value: refundAmount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20
            IERC20(campaign.paymentToken).safeTransfer(msg.sender, refundAmount);
        }

        emit Desisted(_campaignId, msg.sender, refundAmount);
    }

    /**
     * 💰 CLAIM REFUND - COMO "REEMBOLSAR" UM INVESTIMENTO (SE FALHAR)
     * 
     * Imagine que esta função é como "reembolsar" um investimento:
     * 
     * 🔄 PARÂMETROS PRINCIPAIS:
     * 
     * 🔢 _id: "Qual é o número da barraca?"
     *    - Como identificar a barraca
     * 
     * 💡 ANALOGIA: Como reembolsar um produto comprado online
     */
    function claimRefund(uint256 _id) external payable nonReentrant onlyRole(INVESTOR_ROLE) {
        Campaign storage c = campaigns[_id];
        Investment storage inv = investments[_id][msg.sender];

        require(block.timestamp > c.endAt, "Not ended yet");
        require(c.pledged < c.minTarget, "Min target reached");
        require(inv.amount > 0, "No invest or already refunded/claimed");
        require(!inv.claimed, "Already claimed/refunded");

        uint256 refundAmount = inv.amount;
        inv.amount = 0;
        inv.claimed = true;

        if (c.paymentToken == address(0)) {
            // ETH
            (bool success,) = payable(msg.sender).call{value: refundAmount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20
            IERC20(c.paymentToken).safeTransfer(msg.sender, refundAmount);
        }

        emit RefundClaimed(_id, msg.sender, refundAmount);
    }

    // ========================================
    // 🎉 SAQUE DO CRIADOR (COMO "SACAR" DINHEIRO DA BARRACA BEM-SUCEDIDA)
    // ========================================
    
    /**
     * 🎉 claimCreator - COMO "SACAR" DINHEIRO DE UMA BARRACA BEM-SUCEDIDA
     * 
     * Imagine que esta função é como "sacar" o dinheiro de uma barraca que deu certo:
     * 
     * 🎯 PARÂMETROS:
     * 
     * 🔢 _id: "Qual barraca quero sacar o dinheiro?"
     *    - ID da campanha bem-sucedida
     * 
     * 🚀 O QUE ACONTECE QUANDO SACO O DINHEIRO:
     * 
     * 1. ✅ VERIFICAÇÕES:
     *    - "Sou realmente o dono desta barraca?"
     *    - "A barraca já não foi sacada antes?"
     *    - "A barraca atingiu a meta mínima ou já fechou?"
     * 
     * 2. 💰 CÁLCULO DAS DISTRIBUIÇÕES:
     *    - "Quanto dinheiro tem na barraca no total?"
     *    - "Quanto a feira cobra de comissão?"
     *    - "Quanto sobra após a comissão da feira?"
     * 
     * 3. 👑 CÁLCULO DAS COMISSÕES DOS LÍDERES:
     *    - "Quais líderes atingiram o valor mínimo?"
     *    - "Quanto cada líder qualificado deve receber?"
     *    - "Quanto sobra para o criador?"
     * 
     * 4. 💸 DISTRIBUIÇÃO AUTOMÁTICA:
     *    - "Envio comissão para a feira (plataforma)"
     *    - "Envio comissões para os líderes qualificados"
     *    - "Envio o restante para o criador"
     * 
     * 💡 ANALOGIA: Como distribuir o lucro de uma empresa entre sócios
     * 
     * 📊 EXEMPLO DE DISTRIBUIÇÃO:
     * - Total arrecadado: R$ 100.000
     * - Comissão da feira (2%): R$ 2.000
     * - Sobra para distribuir: R$ 98.000
     * - Comissão líder 1 (10%): R$ 9.800
     * - Comissão líder 2 (10%): R$ 9.800
     * - Total comissões líderes: R$ 19.600
     * - Para o criador: R$ 78.400
     * 
     * 🎯 RESULTADO:
     * - Feira recebe: R$ 2.000
     * - Líder 1 recebe: R$ 9.800
     * - Líder 2 recebe: R$ 9.800
     * - Criador recebe: R$ 78.400
     * 
     * 🔒 SEGURANÇA:
     * - "Só posso sacar uma vez"
     * - "Só o dono da barraca pode sacar"
     * - "Distribuição automática e transparente"
     */
    function claimCreator(uint256 _id) external payable nonReentrant onlyAllowedCreator(_id) {
        Campaign storage c = campaigns[_id];
        require(!c.claimed, "Already claimed");
        require(
            block.timestamp > c.endAt || c.pledged >= c.minTarget, "Campaign not ended yet or minTarget not reached"
        );

        c.claimed = true;

        uint256 totalFunds = c.pledged;
        // Calculate platform fee
        uint256 feeAmount = (totalFunds * c.platformFeeBP) / DIVISOR_FACTOR;

        // Calculate remaining after platform fee
        uint256 remainingAfterFee = totalFunds - feeAmount;

        // Calculate individual carry amounts for qualified leaders
        uint256[] memory leaderCarryAmounts = new uint256[](c.investorLeaders.length);
        uint256 totalCarryAmount = 0;

        for (uint256 i = 0; i < c.investorLeaders.length; i++) {
            if (c.leaderQualified[i] && c.leaderCarryBP[i] > 0 && c.investorLeaders[i] != address(0)) {
                leaderCarryAmounts[i] = (remainingAfterFee * c.leaderCarryBP[i]) / DIVISOR_FACTOR;
                totalCarryAmount += leaderCarryAmounts[i];
            }
        }

        // Remaining for creator
        uint256 netAmount = remainingAfterFee - totalCarryAmount;

        // Effects before interactions
        // Transfer fee to platform
        if (c.paymentToken == address(0)) {
            (bool success,) = payable(c.platformWallet).call{value: feeAmount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(c.paymentToken).safeTransfer(c.platformWallet, feeAmount);
        }

        // Transfer carry to qualified leaders
        for (uint256 i = 0; i < c.investorLeaders.length; i++) {
            if (leaderCarryAmounts[i] > 0) {
                if (c.paymentToken == address(0)) {
                    (bool success,) = payable(c.investorLeaders[i]).call{value: leaderCarryAmounts[i]}("");
                    require(success, "ETH transfer failed");
                } else {
                    IERC20(c.paymentToken).safeTransfer(c.investorLeaders[i], leaderCarryAmounts[i]);
                }
            }
        }

        // Transfer remaining amount to creator
        if (c.paymentToken == address(0)) {
            (bool success,) = payable(c.creatorVault).call{value: netAmount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(c.paymentToken).safeTransfer(c.creatorVault, netAmount);
        }

        emit CreatorClaimed(_id, netAmount, feeAmount);
    }

    // ========================================
    // 🎁 REIVINDICAÇÃO DE TOKENS PELOS INVESTIDORES
    // ========================================
    
    /**
     * 🎁 CLAIM TOKENS - COMO "REIVINDICAR" TOKENS DE UMA BARRACA BEM-SUCEDIDA
     * 
     * Imagine que esta função é como "reivindicar" os tokens de uma barraca que deu certo:
     * 
     * 🔄 PARÂMETROS PRINCIPAIS:
     * 
     * 🔢 _id: "Qual barraca quero reivindicar os tokens?"
     *    - ID da campanha bem-sucedida
     * 
     * 💡 ANALOGIA: Como receber os produtos comprados online
     */
    function claimTokens(uint256 _id) external nonReentrant onlyRole(INVESTOR_ROLE) {
        Campaign storage c = campaigns[_id];
        Investment storage inv = investments[_id][msg.sender];

        require(block.timestamp > c.endAt, "Campaign not ended");
        require(c.pledged >= c.minTarget, "Campaign not successful");
        require(inv.amount > 0, "No investment or already claimed");
        require(!inv.claimed, "Already claimed/refunded");

        uint256 base = inv.amount;
        inv.claimed = true;
        uint256 tokenAmount = base;

        IERC20(c.officialToken).safeTransfer(msg.sender, tokenAmount);
        emit TokensClaimed(_id, msg.sender, tokenAmount);
    }

    // ========================================
    // 🛠️ FUNÇÕES AUXILIARES (COMO "FERRAMENTAS" DO SISTEMA)
    // ========================================
    
    /**
     * 🧮 calculateUSDValue - COMO "CONVERTER" MOEDAS PARA DÓLARES
     * 
     * Imagine que esta função é como um "conversor de moedas" automático:
     * 
     * 🎯 PARÂMETROS:
     * 
     * 💰 amount: "Quanto dinheiro quero converter?"
     *    - Quantidade da moeda que quer converter
     * 
     * 🪙 token: "De qual moeda quero converter?"
     *    - Endereço da moeda (USDC, USDT, ETH)
     * 
     * 🚀 O QUE ACONTECE:
     * 
     * 1. 📊 CONSULTA O PREÇO:
     *    - "Pergunta ao termômetro quanto vale esta moeda em dólares"
     *    - "Usa o oráculo de preço mais recente"
     * 
     * 2. 🔄 CONVERTE PARA DÓLARES:
     *    - "Multiplica a quantidade pela cotação"
     *    - "Ajusta as casas decimais corretamente"
     * 
     * 3. 💵 RETORNA EM DÓLARES:
     *    - "Resultado sempre em dólares com 18 casas decimais"
     * 
     * 💡 ANALOGIA: Como usar um conversor de moedas no aeroporto
     * 
     * 📊 EXEMPLOS PRÁTICOS DOS CÁLCULOS:
     * 
     * 🎯 OBJETIVO: Converter qualquer token para USD com 18 casas decimais
     * 
     * 💡 POR QUE 18 CASAS DECIMAIS?
     * 
     * 1. 🏗️ PADRÃO ETHEREUM: Todos os tokens ERC-20 usam 18 decimais por padrão
     * 2. 🔄 INTEROPERABILIDADE: Facilita cálculos entre diferentes tokens
     * 3. 📊 PRECISÃO: Evita perda de precisão em cálculos financeiros
     * 4. 🏛️ REGULAÇÃO CVM: Permite comparar valores em BRL para limites regulatórios
     * 5. 💰 CONVERSÃO BRL: Todos os valores em USD podem ser convertidos para BRL
     * 
     * 🔄 FLUXO COMPLETO:
     * Token → USD (18 decimais) → BRL (18 decimais) → Comparação com limites CVM
     * 
     * 🪙 EXEMPLO 1 - USDC (6 decimais):
     * - Input: 1000 USDC (1000000000 = 1000 * 10^6)
     * - Preço USDC: $1.00 (100000000 = 1 * 10^8)
     * - Multiplicação: 1000000000 * 100000000 = 100000000000000000 (14 decimais)
     * - Ajuste para 18 decimais: 100000000000000000 * 10^(18-14) = 100000000000000000 * 10^4
     * - Resultado: 1000000000000000000000 (1000 USD com 18 decimais)
     * 
     * 🪙 EXEMPLO 2 - ETH (18 decimais):
     * - Input: 1 ETH (1000000000000000000 = 1 * 10^18)
     * - Preço ETH: $2000.00 (200000000000 = 2000 * 10^8)
     * - Multiplicação: 1000000000000000000 * 200000000000 = 200000000000000000000000000000 (26 decimais)
     * - Ajuste para 18 decimais: 200000000000000000000000000000 / 10^(26-18) = 200000000000000000000000000000 / 10^8
     * - Resultado: 2000000000000000000000 (2000 USD com 18 decimais)
     * 
     * 🪙 EXEMPLO 3 - USDT (6 decimais):
     * - Input: 500 USDT (500000000 = 500 * 10^6)
     * - Preço USDT: $1.00 (100000000 = 1 * 10^8)
     * - Multiplicação: 500000000 * 100000000 = 50000000000000000 (14 decimais)
     * - Ajuste para 18 decimais: 50000000000000000 * 10^(18-14) = 50000000000000000 * 10^4
     * - Resultado: 500000000000000000000 (500 USD com 18 decimais)
     * 
     * 🔒 SEGURANÇA:
     * - "Usa preços atualizados (máximo 24h)"
     * - "Verifica se a rede está funcionando"
     * - "Rejeita moedas não suportadas"
     */
    function calculateUSDValue(uint256 amount, address token) internal view returns (uint256) {
        uint256 price = getUSDPrice(token);
        // Convert to 18 decimals
        // Price comes with 8 decimals, amount depends on token decimals
        uint256 decimals = token == address(0) ? 18 : ERC20(token).decimals();
        // First multiply by price (8 decimals)
        uint256 usdValue = amount * price;
        // Then adjust decimals to get final amount in 18 decimals
        // We need to add (18 - (decimals + 8)) decimals to get to 18
        if (decimals + 8 < 18) {
            usdValue = usdValue * (10 ** (18 - (decimals + 8)));
        } else if (decimals + 8 > 18) {
            usdValue = usdValue / (10 ** ((decimals + 8) - 18));
        }
        return usdValue;
    }

    /**
     * 💰 receive() - COMO "CAIXA DE ENTRADA" PARA ETH
     * 
     * Esta função permite que o contrato receba ETH diretamente
     * Como uma "caixa de entrada" que aceita depósitos
     */
    receive() external payable {}

    /**
     * 🔍 checkSequencer - COMO "VERIFICAR SE A REDE ESTÁ FUNCIONANDO"
     * 
     * Imagine que esta função é como verificar se o "sistema elétrico" da feira está ok:
     * 
     * 🚀 O QUE VERIFICA:
     * 
     * 1. 🔌 STATUS DO SEQUENCIADOR:
     *    - "O sequenciador está funcionando?"
     *    - "Se answer = 1, significa que está 'down'"
     * 
     * 2. ⏰ PERÍODO DE GRAÇA:
     *    - "A rede acabou de voltar?"
     *    - "Esperamos 1 hora antes de aceitar transações"
     * 
     * 💡 ANALOGIA: Como verificar se o sistema elétrico está estável antes de ligar equipamentos
     * 
     * 🚨 ERROS:
     * - SequencerDown: "A rede está instável, tente novamente"
     * - GracePeriodNotOver: "Ainda estamos no período de aquecimento"
     */
    function checkSequencer() internal view {
        (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();
        if (answer == 1) revert SequencerDown();
        if (block.timestamp - startedAt <= GRACE_PERIOD_TIME) revert GracePeriodNotOver();
    }

    /**
     * 💵 getUSDPrice - COMO "CONSULTAR PREÇO" DE UMA MOEDA
     * 
     * Imagine que esta função é como consultar o "termômetro" de preço de uma moeda:
     * 
     * 🎯 PARÂMETROS:
     * 
     * 🪙 token: "De qual moeda quero saber o preço?"
     *    - address(0) = ETH
     *    - USDC = endereço do USDC
     *    - USDT = endereço do USDT
     * 
     * 🚀 O QUE ACONTECE:
     * 
     * 1. 🔍 VERIFICAÇÃO DE SEGURANÇA:
     *    - "A rede está funcionando?" (checkSequencer)
     * 
     * 2. 📊 SELEÇÃO DO ORÁCULO:
     *    - "Qual termômetro usar para esta moeda?"
     *    - ETH → ethPriceFeed
     *    - USDC → usdcPriceFeed
     *    - USDT → usdtPriceFeed
     * 
     * 3. ⏰ VERIFICAÇÃO DE ATUALIDADE:
     *    - "O preço é recente?" (máximo 24h)
     *    - "Se não for, rejeita a transação"
     * 
     * 4. 💵 RETORNO DO PREÇO:
     *    - "Preço em dólares com 8 casas decimais"
     * 
     * 💡 ANALOGIA: Como consultar a cotação de uma moeda no jornal
     * 
     * 📊 EXEMPLOS:
     * - ETH: $2000.00 → 200000000000 (8 decimais)
     * - USDC: $1.00 → 100000000 (8 decimais)
     * - USDT: $1.00 → 100000000 (8 decimais)
     * 
     * 🚨 ERROS:
     * - "Unsupported token": Moeda não suportada
     * - StalePrice: Preço muito antigo
     * - SequencerDown: Rede instável
     */
    function getUSDPrice(address token) public view returns (uint256) {
        checkSequencer();

        AggregatorV2V3Interface priceFeed;
        if (token == address(0)) {
            priceFeed = ethPriceFeed;
        } else if (isUSDC(token)) {
            priceFeed = usdcPriceFeed;
        } else if (isUSDT(token)) {
            priceFeed = usdtPriceFeed;
        } else {
            revert("Unsupported token");
        }

        (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();
        if (block.timestamp - updatedAt > 24 hours) revert StalePrice();

        return uint256(price);
    }

    /**
     * 💰 getBRLPrice - COMO "CONVERTER" DÓLARES PARA REAIS
     * 
     * Imagine que esta função é como um "conversor de moedas" que transforma dólares em reais:
     * 
     * 🔄 PARÂMETROS:
     * 
     * 💰 usdAmount: "Quantos dólares quero converter?"
     *    - Quantidade de dólares que quer converter
     * 
     * 💵 O QUE ACONTECE:
     * 
     * 1. 🔍 VERIFICAÇÃO DE SEGURANÇA:      
     *    - "A rede está funcionando?" (checkSequencer)
     * 
     * 2. 📊 SELEÇÃO DO ORÁCULO:
     *    - "Qual termômetro usar para esta moeda?"
     *    - ETH → ethPriceFeed
     *    - USDC → usdcPriceFeed
     *    - USDT → usdtPriceFeed
     * 
     * 3. 💵 RETORNO EM REAIS:
     *    - "Resultado em reais com 2 decimais"
     * 
     * 💡 ANALOGIA: Como converter dólares para reais no banco
     */
    function getBRLPrice(uint256 usdAmount) public view returns (uint256) {
        checkSequencer();
        (, int256 brlRate,, uint256 updatedAt,) = brlPriceFeed.latestRoundData();
        if (block.timestamp - updatedAt > 24 hours) revert StalePrice();

        // 📊 EXEMPLO PRÁTICO - Conversão USD para BRL:
        // - usdAmount: $1000 USD (1000000000000000000000 = 1000 * 10^18)
        // - brlRate: 0.1667 USD/BRL (16670000 = 0.1667 * 10^8)
        // - Multiplicação: 1000000000000000000000 * 10^8 = 100000000000000000000000000000
        // - Divisão: 100000000000000000000000000000 / 16670000 = 6000000000000000000000
        // - Resultado: R$ 6000 BRL com 18 decimais (cotação 1 USD = 6 BRL)
        return (usdAmount * 1e8) / uint256(brlRate);
    }

    /**
     * 📊 getCampaign - COMO "CONSULTAR" UMA BARRACA
     * 
     * Imagine que esta função é como verificar o "status" de uma barraca:
     * 
     * 🔄 PARÂMETROS:   
     * 
     * 📅 _id: "Qual é o número da barraca?"
     *    - Como identificar a barraca
     * 
     * 💡 ANALOGIA: Como verificar o status de uma loja no shopping
     */
    function getCampaign(uint256 _id) external view returns (Campaign memory) {
        return campaigns[_id];
    }

    /**
     * 📊 getInvestment - COMO "CONSULTAR" UM INVESTIMENTO
     * 
     * Imagine que esta função é como verificar o "extrato" de um investimento:
     * 
     * 🔄 PARÂMETROS:
     * 
     * 📅 _id: "Qual é o número da barraca?"
     *    - Como identificar a barraca
     * 
     * 💡 ANALOGIA: Como verificar o extrato de uma conta bancária
     */
    function getInvestment(uint256 _id, address _investor)
        external
        view
        returns (uint256 amount, bool claimed, uint256 investTime, uint256 investmentCount)
    {
        Investment storage inv = investments[_id][_investor];
        return (inv.amount, inv.claimed, inv.investTime, inv.investmentCount);
    }

    /**
     * 📅 getInvestmentDate - COMO "CONSULTAR" A DATA DE UM INVESTIMENTO
     * 
     * Imagine que esta função é como verificar a "data" de um investimento:
     * 
     * 🔄 PARÂMETROS:
     *  
     * 🔢 investmentId: "Qual é o número do investimento?"
     *    - Como identificar o investimento
     * 
     * 💡 ANALOGIA: Como verificar a data de um depósito em uma conta bancária
     */
    function getInvestmentDate(uint256 _id, address _investor, uint256 investmentId) external view returns (uint256) {
        Investment storage inv = investments[_id][_investor];
        require(investmentId > 0 && investmentId <= inv.investmentCount, "Invalid investment ID");
        return inv.investmentDates[investmentId];
    }

    /**
     * 💰 convertBRLtoUSD - COMO "CONVERTER" REAIS PARA DÓLARES
     * 
     * Imagine que esta função é como um "conversor de moedas" que transforma reais em dólares:
     * 
     * 🔄 PARÂMETROS:       
     * 
     * 💰 brlAmount: "Quantos reais quero converter?"
     *    - Quantidade de reais que quer converter
     * 
     * 💡 ANALOGIA: Como converter reais para dólares no banco
     */
    function convertBRLtoUSD(uint256 brlAmount) public view returns (uint256) {
        checkSequencer();
        (, int256 brlRate,, uint256 updatedAt,) = brlPriceFeed.latestRoundData();
        if (block.timestamp - updatedAt > 24 hours) revert StalePrice();

        // 📊 EXEMPLO PRÁTICO - Conversão USD para BRL:
        // - brlAmount: $1000 USD (1000000000000000000000 = 1000 * 10^18)
        // - brlRate: 0.1667 (16670000 = 0.1667 * 10^8)
        // - Cálculo: (1000000000000000000000 * 16670000) / 10^8
        // - Resultado: 166700000000000000000000000 / 10^8 = 1667000000000000000000
        // - Significado: $1000 USD = R$ 6000 BRL (cotação 1 USD = 6 BRL)
        return (brlAmount * uint256(brlRate)) / 1e8;
    }

    /**
     * 📊 validateCampaignAmount - COMO "VALIDAR" O VALOR DE UMA BARRACA
     * 
     * Imagine que esta função é como verificar se o valor de uma barraca está dentro do limite:
     * 
     * 🔄 PARÂMETROS:
     * 
     * 💰 amount: "Quanto dinheiro quero investir?"
     *    - Quantidade de dinheiro que quer investir
     * 
     * 🪙 token: "De qual moeda quero investir?"
     *    - Endereço da moeda (USDC, USDT, ETH)
     * 
     * 💡 ANALOGIA: Como verificar se o valor de uma barraca está dentro do limite
     */
    function validateCampaignAmount(uint256 amount, address token) internal view {
        uint256 usdValue;
        if (isUSDC(token)) {
            (, int256 usdcPrice,, uint256 updatedAt,) = usdcPriceFeed.latestRoundData();
            if (block.timestamp - updatedAt > 24 hours) revert StalePrice();
            // 📊 EXEMPLO PRÁTICO - USDC:
            // - amount: 1000 USDC (1000000000 = 1000 * 10^6)
            // - usdcPrice: $1.00 (100000000 = 1 * 10^8)
            // - Multiplicação: 1000000000 * 100000000 = 100000000000000000 (14 decimais)
            // - Multiplicação por 1e12: 100000000000000000 * 10^12 = 100000000000000000000000000000
            // - Divisão por 1e8: 100000000000000000000000000000 / 10^8 = 1000000000000000000000
            // - Resultado: 1000 USD com 18 decimais
            usdValue = (amount * uint256(usdcPrice) * 1e12) / 1e8;
        } else if (isUSDT(token)) {
            (, int256 usdtPrice,, uint256 updatedAt,) = usdtPriceFeed.latestRoundData();
            if (block.timestamp - updatedAt > 24 hours) revert StalePrice();
            // 📊 EXEMPLO PRÁTICO - USDT:
            // - amount: 500 USDT (500000000 = 500 * 10^6)
            // - usdtPrice: $1.00 (100000000 = 1 * 10^8)
            // - Multiplicação: 500000000 * 100000000 = 50000000000000000 (14 decimais)
            // - Multiplicação por 1e12: 50000000000000000 * 10^12 = 50000000000000000000000000000
            // - Divisão por 1e8: 50000000000000000000000000000 / 10^8 = 500000000000000000000
            // - Resultado: 500 USD com 18 decimais
            usdValue = (amount * uint256(usdtPrice) * 1e12) / 1e8;
        } else if (isETH(token)) {
            (, int256 ethPrice,, uint256 updatedAt,) = ethPriceFeed.latestRoundData();
            if (block.timestamp - updatedAt > 24 hours) revert StalePrice();
            // 📊 EXEMPLO PRÁTICO - ETH:
            // - amount: 1 ETH (1000000000000000000 = 1 * 10^18)
            // - ethPrice: $2000.00 (200000000000 = 2000 * 10^8)
            // - Multiplicação: 1000000000000000000 * 200000000000 = 200000000000000000000000000000 (26 decimais)
            // - Divisão por 1e8: 200000000000000000000000000000 / 10^8 = 2000000000000000000000
            // - Resultado: 2000 USD com 18 decimais
            usdValue = (amount * uint256(ethPrice)) / 1e8;
        } else {
            revert("Unsupported token");
        }

        uint256 brlValue = getBRLPrice(usdValue);
        require(brlValue <= MAX_CAMPAIGN_TARGET, "Exceeds maximum campaign target in BRL");
    }

    /**
     * 📊 isUSDC - COMO "VERIFICAR" SE É USDC
     * 
     * Imagine que esta função é como verificar se uma moeda é USDC:
     * 
     * 🔄 PARÂMETROS:   
     * 
     * 🪙 token: "De qual moeda quero verificar?"
     *    - Endereço da moeda (USDC, USDT, ETH)
     * 
     * 💡 ANALOGIA: Como verificar se uma moeda é USDC
     */
    function isUSDC(address token) internal pure returns (bool) {
        return token == USDC;
    }

    /**
     * 📊 isUSDT - COMO "VERIFICAR" SE É USDT
     * 
     * Imagine que esta função é como verificar se uma moeda é USDT:
     * 
     * 🔄 PARÂMETROS:               
     * 
     * 🪙 token: "De qual moeda quero verificar?"
     *    - Endereço da moeda (USDC, USDT, ETH)
     * 
     * 💡 ANALOGIA: Como verificar se uma moeda é USDT
     */
    function isUSDT(address token) internal pure returns (bool) {
        return token == USDT;
    }

    /**
     * 📊 isETH - COMO "VERIFICAR" SE É ETH
     * 
     * Imagine que esta função é como verificar se uma moeda é ETH:
     * 
     * 🔄 PARÂMETROS:
     * 
     * 🪙 token: "De qual moeda quero verificar?"
     *    - Endereço da moeda (USDC, USDT, ETH)
     * 
     * 💡 ANALOGIA: Como verificar se uma moeda é ETH
     */
    function isETH(address token) internal pure returns (bool) {
        return token == address(0) || token == ETH;
    }

    /**
     * 📊 getMaxTargetInToken - COMO "CONSULTAR" O VALOR MÁXIMO DE UMA BARRACA
     * 
     * Imagine que esta função é como verificar o "valor máximo" de uma barraca:
     * 
     * 🔄 PARÂMETROS:
     * 
     * 🪙 token: "De qual moeda quero verificar?"
     *    - Endereço da moeda (USDC, USDT, ETH)
     * 
     * 💡 ANALOGIA: Como verificar o valor máximo de uma barraca
     */
    function getMaxTargetInToken(address token) public view returns (uint256) {
        uint256 usdNeeded = convertBRLtoUSD(MAX_CAMPAIGN_TARGET);
        if (isUSDC(token) || isUSDT(token)) {
            (, int256 tokenPrice,, uint256 updatedAt,) =
                isUSDC(token) ? usdcPriceFeed.latestRoundData() : usdtPriceFeed.latestRoundData();
            if (block.timestamp - updatedAt > 24 hours) revert StalePrice();

            // 📊 EXEMPLO PRÁTICO - Cálculo do valor máximo em tokens:
            // - usdNeeded: $3.000.000 USD (3000000000000000000000000 = 3M * 10^18)
            // - tokenPrice: $1.00 USDC/USDT (100000000 = 1 * 10^8)
            // - Multiplicação: 3000000000000000000000000 * 10^6 = 3000000000000000000000000000000
            // - Denominador: 100000000 * 10^10 = 1000000000000000000
            // - Divisão: 3000000000000000000000000000000 / 1000000000000000000 = 3000000000
            // - Resultado: 3.000.000.000 tokens (3 milhões de USDC/USDT)
            return (usdNeeded * 1e6) / (uint256(tokenPrice) * 1e10);
        } else {
            revert("Unsupported token");
        }
    }

    /**
     * 📊 swapForOfficialToken - COMO "TROCAR" PARA O TOKEN OFICIAL
     * 
     * Imagine que esta função é como trocar uma moeda por outra:
     * 
     * 🔄 PARÂMETROS:
     * 
     * 💰 amount: "Quanto dinheiro quero investir?"
     *    - Quantidade de dinheiro que quer investir
     * 
     * 💡 ANALOGIA: Como trocar uma moeda por outra
     */
    function swapForOfficialToken(uint256 _id, uint256 amount) external nonReentrant {
        Campaign storage c = campaigns[_id];
        require(c.pledged >= c.minTarget, "Campaign not successful");

        CampaignToken(c.campaignToken).burnFrom(msg.sender, amount);
        uint256 vestedAmount = calculateVestedAmount(amount, c.vestingStart, c.vestingDuration, block.timestamp);
        if (vestedAmount > 0) {
            IERC20(c.officialToken).safeTransfer(msg.sender, vestedAmount);
        }
    }

    /**
     * 📊 calculateVestedAmount - COMO "CALCULAR" O VALOR VESTIDO
     * 
     * Imagine que esta função é como calcular o "valor" de um investimento que se pode sacar:
     * 
     * 🔄 PARÂMETROS:
     * 
     * 💰 total: "Quanto dinheiro quero investir?"
     *    - Quantidade de dinheiro que quer investir
     * 
     * 📅 vestingStart: "Quando o investimento começa?"
     *    - Data de início da vesting
     * 
     * 📅 vestingDuration: "Quanto tempo de vesting?"
     *    - Duração da vesting
     * 
     * 📅 timestamp: "Qual é a data atual?"
     *    - Data atual
     * 
     * 💡 ANALOGIA: Como calcular o tempo que se pode vestir o investimento e a quantidade de tokens que se pode sacar
     */
    function calculateVestedAmount(uint256 total, uint32 vestingStart, uint32 vestingDuration, uint256 timestamp)
        public
        pure
        returns (uint256)
    {
        if (timestamp < vestingStart) return 0;
        if (timestamp >= vestingStart + vestingDuration) return total;

        return (total * (timestamp - vestingStart)) / vestingDuration;
    }

    /**
     * 📊 hasExpiredInvestments - COMO "VERIFICAR" SE UM INVESTIMENTO EXPIROU 5 DIAS de direito de arrependimento
     * 
     * Imagine que esta função é como verificar se um investimento expirou 5 dias de direito de arrependimento:
     * 
     * 🔄 PARÂMETROS:
     *  
     * 📅 _campaignId: "Qual é o número da barraca?"
     *    - Como identificar a barraca
     * 
     * 💡 ANALOGIA: Como verificar se um investimento expirou
     */
    function hasExpiredInvestments(uint256 _campaignId, address _investor) public view returns (bool) {
        Investment storage investment = investments[_campaignId][_investor];

        for (uint256 i = 1; i <= investment.investmentCount; i++) {
            if (block.timestamp > investment.investmentDates[i] + 5 days) {
                return true;
            }
        }
        return false;
    }
}
