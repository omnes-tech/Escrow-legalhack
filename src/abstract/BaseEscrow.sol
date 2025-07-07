// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IEscrow.sol";
import "../interfaces/IEscrowErrors.sol";

/**
 * @title BaseEscrow - A Fundação Sólida do Escrow
 * @notice Contrato abstrato com funcionalidades base para o sistema de custódia
 * 
 * 🏛️ ANALOGIA: É como as fundações de um prédio - você não vê, mas tudo depende dela
 *              Define as regras básicas que todos os escrows devem seguir
 * 
 * RESPONSABILIDADES PRINCIPAIS:
 * 🔐 Controle de acesso (apenas o dono pode mudar regras importantes)
 * 🛡️ Proteção contra reentrancy (evita ataques de hackers)
 * 💰 Gestão de taxas da plataforma
 * 📋 Lista de tokens permitidos (whitelist de segurança)
 * 🧮 Cálculos matemáticos básicos
 * 
 * HERANÇAS IMPORTADAS:
 * 👑 Ownable: Sistema de proprietário (apenas o dono pode fazer certas coisas)
 * 🛡️ ReentrancyGuard: Proteção contra ataques de reentrada
 * 📜 IEscrow: Interface que define as funções obrigatórias
 * ❌ IEscrowErrors: Catálogo de erros personalizados
 */
abstract contract BaseEscrow is Ownable, ReentrancyGuard, IEscrow, IEscrowErrors {
    
    // ========================================================================
    // VARIÁVEIS DE ESTADO (A Memória do Cartório)
    // ========================================================================
    
    /**
     * @notice Taxa da plataforma em pontos base (1 ponto base = 0.01%)
     * @dev Máximo permitido é 9999 (99.99%) para evitar taxas abusivas
     * 
     * 💰 ANALOGIA: É como a comissão que o cartório cobra pelos seus serviços
     *              Se platformFeeBP = 250, significa 2.5% de taxa
     * 
     * EXEMPLOS PRÁTICOS:
     * - 100 = 1% de taxa
     * - 250 = 2.5% de taxa  
     * - 500 = 5% de taxa
     * - 1000 = 10% de taxa
     */
    uint256 public platformFeeBP;
    
    /**
     * @notice Próximo ID único que será usado para criar uma custódia
     * @dev Incrementa automaticamente a cada nova custódia criada
     * 
     * 📊 ANALOGIA: É como o número sequencial dos protocolos no cartório
     *              Cada documento tem um número único crescente
     * 
     * SEGURANÇA: Começa em 1 (não 0) para evitar confusões
     */
    uint256 internal _nextEscrowId;

    /**
     * @notice Lista de tokens ERC20 permitidos no sistema
     * @dev Mapping: endereço_do_token => true/false
     * 
     * 🏛️ ANALOGIA: É como uma lista de bancos autorizados a operar no país
     *              Só aceita moedas que foram previamente aprovadas
     * 
     * SEGURANÇA: Evita que tokens maliciosos sejam usados
     * EXEMPLO: isAllowedToken[USDC_ADDRESS] = true
     */
    mapping(address => bool) public isAllowedToken;
    
    /**
     * @notice Lista de NFTs específicos permitidos no sistema
     * @dev Mapping: endereço_do_contrato => id_do_token => true/false
     * 
     * 🖼️ ANALOGIA: É como uma galeria de arte que só aceita obras certificadas
     *              Cada NFT precisa ser aprovado individualmente
     * 
     * USO: Para garantias com NFTs específicos de valor conhecido
     * EXEMPLO: isAllowedERC721AndERC1155[BORED_APES][123] = true
     */
    mapping(address => mapping(uint256 => bool)) public isAllowedERC721AndERC1155;

    // ========================================================================
    // CONSTRUCTOR (Nascimento do Cartório)
    // ========================================================================
    
    /**
     - Estabelecendo as Regras Fundamentais
     * @notice Inicializa o cartório com taxa definida e segurança ativada
     * @param _platformFeeBP Taxa da plataforma em pontos base (máximo 9999)
     * 
     * 🎯 ANALOGIA: É como o ato de fundação de um cartório - define as regras
     *              básicas que nunca mudam e estabelece quem é o proprietário
     * 
     * VALIDAÇÕES CRÍTICAS:
     * ✅ Taxa não pode ser 100% ou mais (seria confisco)
     * ✅ Proprietário é definido como quem deplorou o contrato
     * ✅ Contador de custódias começa em 1 (não 0)
     * 
     * SEGURANÇA APLICADA:
     * 🛡️ Ownable(msg.sender): Define deployer como owner
     * 🔒 Validação de taxa máxima
     * 📊 Inicialização segura do contador
     */
    constructor(uint256 _platformFeeBP) Ownable(msg.sender) {
        // VALIDAÇÃO: Taxa não pode ser 100% ou mais
        if (_platformFeeBP >= 10000) revert InvalidFee();
        
        // CONFIGURAÇÃO: Salvar taxa válida
        platformFeeBP = _platformFeeBP;
        
        // INICIALIZAÇÃO: Primeiro escrow terá ID 1
        _nextEscrowId = 1;
    }

    // ========================================================================
    // FUNÇÕES ADMINISTRATIVAS (Poderes do Proprietário)
    // ========================================================================
    
    /**
     setPlatformFeeBP - Ajustando as Taxas
     * @notice Permite ao proprietário alterar a taxa da plataforma
     * @param _feeBP Nova taxa em pontos base (máximo 9999)
     * 
     * 💼 ANALOGIA: É como o governo ajustar impostos - só quem tem autoridade
     *              pode fazer, e há limites para evitar abusos
     * 
     * RESTRIÇÕES:
     * 👑 Apenas o proprietário pode chamar
     * 📊 Taxa máxima é 99.99% (evita confisco)
     * 
     * CASOS DE USO:
     * - Ajustar taxa baseado na demanda do mercado
     * - Promoções temporárias (reduzir taxa)
     * - Adequação a regulamentações
     */
    function setPlatformFeeBP(uint256 _feeBP) external onlyOwner {
        // VALIDAÇÃO: Nova taxa deve estar dentro dos limites
        if (_feeBP >= 10000) revert InvalidFee();
        
        // ATUALIZAÇÃO: Aplicar nova taxa
        platformFeeBP = _feeBP;
    }

    /**
      setAllowedToken - Gerenciando Lista de Moedas
     * @notice Adiciona ou remove tokens ERC20 da lista de permitidos
     * @param _token Endereço do contrato do token
     * @param _allowed true para permitir, false para bloquear
     * 
     * 🏦 ANALOGIA: É como o Banco Central autorizar ou suspender uma moeda
     *              estrangeira para uso no país
     * 
     * EXEMPLOS DE USO:
     * - Adicionar USDC: setAllowedToken(USDC_ADDRESS, true)
     * - Remover token suspeito: setAllowedToken(SCAM_TOKEN, false)
     * - Atualizar após auditoria: setAllowedToken(NEW_TOKEN, true)
     * 
     * SEGURANÇA:
     * ✅ Apenas proprietário pode modificar
     * ✅ Pode revogar permissões se token se tornar malicioso
     */
    function setAllowedToken(address _token, bool _allowed) external onlyOwner {
        isAllowedToken[_token] = _allowed;
    }

    /**
     setAllowedERC721Or1155 - Curando NFTs Específicos
     * @notice Permite ou bloqueia NFTs específicos para uso como garantia
     * @param _token Endereço do contrato NFT
     * @param _tokenId ID específico do NFT
     * @param _allowed true para permitir, false para bloquear
     * 
     * 🎨 ANALOGIA: É como um leilão de arte que só aceita quadros específicos
     *              de artistas famosos - cada obra precisa ser aprovada
     * 
     * CASOS DE USO:
     * - Permitir Bored Ape #123: setAllowedERC721Or1155(BAYC, 123, true)
     * - Bloquear NFT roubado: setAllowedERC721Or1155(STOLEN_NFT, 456, false)
     * - Aprovar coleção verificada: aprovar IDs individuais de valor
     * 
     * ESTRATÉGIA DE CURADORIA:
     * 🔍 Análise individual de cada NFT
     * 💎 Foco em NFTs de valor comprovado
     * 🛡️ Proteção contra falsificações
     */
    function setAllowedERC721Or1155(address _token, uint256 _tokenId, bool _allowed) external onlyOwner {
        isAllowedERC721AndERC1155[_token][_tokenId] = _allowed;
    }

    // ========================================================================
    // FUNÇÕES AUXILIARES INTERNAS (Ferramentas do Sistema)
    // ========================================================================
    
    /**
      _calculateFee - Calculadora de Taxas
     * @notice Calcula a taxa da plataforma sobre um valor
     * @param amount Valor base sobre o qual calcular a taxa
     * @return Taxa em wei/unidades do token
     * 
     * 🧮 ANALOGIA: É como uma calculadora de imposto - você informa o valor
     *              e ela te diz exatamente quanto deve pagar de taxa
     * 
     * MATEMÁTICA APLICADA:
     * Formula: (amount × platformFeeBP) ÷ 10000
     * 
     * EXEMPLOS PRÁTICOS:
     * - Valor: 1000 USDC, Taxa: 250 (2.5%)
     *   Cálculo: (1000 × 250) ÷ 10000 = 25 USDC de taxa
     * 
     * - Valor: 1 ETH, Taxa: 200 (2%)
     *   Cálculo: (1 × 200) ÷ 10000 = 0.02 ETH de taxa
     * 
     * SEGURANÇA MATEMÁTICA:
     * ✅ Não há overflow (valores limitados)
     * ✅ Divisão por 10000 sempre exata
     * ✅ Resultado sempre ≤ valor original
     */
    function _calculateFee(uint256 amount) internal view returns (uint256) {
        return (amount * platformFeeBP) / 10000;
    }
}
