# 📋 Documentação do Contrato Escrow

## 📋 Índice
1. [Visão Geral](#visão-geral)
2. [Conceitos Fundamentais](#conceitos-fundamentais)
3. [Estrutura do Contrato](#estrutura-do-contrato)
4. [Funções Administrativas](#funções-administrativas)
5. [Sistema de Pagamentos](#sistema-de-pagamentos)
6. [Sistema de Disputas](#sistema-de-disputas)
7. [Sistema de Aprovações](#sistema-de-aprovações)
8. [Funções Automáticas](#funções-automáticas)
9. [Sistema de Acordos](#sistema-de-acordos)
10. [Funções de Consulta](#funções-de-consulta)
11. [Fluxo de Operação](#fluxo-de-operação)
12. [Segurança e Proteções](#segurança-e-proteções)
13. [Exemplos Práticos](#exemplos-práticos)
14. [Glossário](#glossário)

---

## 🎯 Visão Geral

O contrato Escrow é uma solução descentralizada para facilitar transações seguras entre partes que não confiam mutuamente. Funciona como um intermediário confiável que guarda fundos até que todas as condições do acordo sejam satisfeitas.

### Analogia Prática
Imagine que você quer comprar um carro de uma pessoa desconhecida pela internet:
- **Problema**: Você não confia em pagar primeiro, e ele não confia em entregar primeiro
- **Solução**: Um "intermediário confiável" (o escrow) guarda o dinheiro até tudo dar certo
- **Como funciona**: Você deposita o dinheiro → Ele entrega o carro → O intermediário libera o pagamento

---

## 🔧 Conceitos Fundamentais

### Escrow (Custódia)
Um mecanismo de segurança que retém fundos até que condições específicas sejam atendidas, garantindo que ambas as partes cumpram suas obrigações.

### Garantias
Depósitos feitos pelas partes para assegurar o cumprimento do contrato:
- **Comprador**: Garantia de pagamento
- **Vendedor**: Garantia de entrega

### Disputas
Mecanismo de resolução de conflitos quando uma das partes não cumpre suas obrigações.

---

## 🏗️ Estrutura do Contrato

O contrato Escrow é composto por três componentes principais:

1. **BaseEscrow**: Classe abstrata com funcionalidades básicas
2. **Escrow**: Implementação principal do sistema
3. **EscrowLib**: Biblioteca com funções auxiliares

---

## ⚙️ Funções Administrativas

### 🏁 startEscrow
**Função**: `startEscrow()`

**Descrição**: Oficialmente inicia a custódia após todas as garantias serem fornecidas.

**Analogia**: É como apertar o botão "INICIAR" em uma máquina de lavar:
- Tudo precisa estar no lugar (água, sabão, roupas)
- Só depois você pode apertar o botão
- Uma vez iniciado, o ciclo começa a rodar

**Quando usar**: Depois que comprador e vendedor depositaram suas garantias.

---

## 💰 Sistema de Pagamentos

### payInstallmentETH
**Função**: `payInstallmentETH(uint256 installmentAmount)`

**Descrição**: Permite ao comprador pagar uma parcela usando Ethereum (moeda digital).

**Analogia**: Como pagar um boleto no banco:
- Se pagar no prazo → só o valor normal
- Se atrasar → o sistema cobra juros automaticamente
- Pagou a mais? O troco volta automaticamente

**Exemplo prático**:
- Parcela de R$ 1.000 vence hoje
- Você atrasou 5 dias = R$ 50 de juros
- Total a pagar: R$ 1.050
- Enviou R$ 1.100? Recebe R$ 50 de troco

### payInstallmentERC20
**Função**: `payInstallmentERC20(address token, uint256 installmentAmount)`

**Descrição**: Igual ao anterior, mas usando tokens (outras moedas digitais).

**Analogia**: Como pagar com cartão de débito em vez de dinheiro vivo.

### payAllRemaining
**Função**: `payAllRemaining()`

**Descrição**: Permite pagar todas as parcelas restantes de uma vez.

**Analogia**: Como quitar um financiamento:
- Em vez de pagar 12x de R$ 500
- Você decide pagar R$ 6.000 de uma vez
- Acaba mais rápido e sem risco de juros futuros

### calculateInstallmentWithInterest
**Função**: `calculateInstallmentWithInterest(uint256 installmentNumber)`

**Descrição**: Calcula quanto você deve pagar agora, incluindo juros se estiver atrasado.

**Analogia**: Como o taxímetro do Uber:
- Dentro do tempo estimado → preço normal
- Trânsito parado (atraso) → o taxímetro continua rodando
- No final, você paga o valor base + o tempo extra

**Tipos de juros**:
- **Simples**: Cada dia soma 1% sobre o valor original
- **Compostos**: Juros sobre juros (como cartão de crédito)

---

## ⚖️ Sistema de Disputas

### openDispute
**Função**: `openDispute(string memory reason)`

**Descrição**: Quando algo dá errado, qualquer parte pode abrir uma disputa.

**Analogia**: Como abrir um processo no Procon:
- Comprador: "Ele não entregou o que prometeu!"
- Vendedor: "Ele não pagou direito!"
- Sistema: "Ok, vamos parar tudo até resolver isso"

**Efeito**: Congela todas as ações até alguém resolver.

### resolveDispute
**Função**: `resolveDispute(uint256 buyerPercentage, uint256 sellerPercentage)`

**Descrição**: Um mediador resolve a disputa e divide o dinheiro conforme sua decisão.

**Analogia**: Como um juiz no tribunal:
- Analisa as evidências
- Decide: "60% para o comprador, 40% para o vendedor"
- A decisão é final e automática

**Flexibilidade total**: Não é só "tudo ou nada" - pode dividir como achar justo.

---

## ✅ Sistema de Aprovações

### setReleaseApproval
**Função**: `setReleaseApproval(bool approved)`

**Descrição**: Cada participante (comprador, vendedor, mediador) dá sua aprovação.

**Analogia**: Como três chaves para abrir um cofre do banco:
- Cada pessoa tem uma chave
- Só abre quando as três chaves girarem juntas
- Qualquer um pode voltar atrás até a abertura final

### withdrawFunds
**Função**: `withdrawFunds()`

**Descrição**: O vendedor retira o dinheiro quando tudo estiver aprovado.

**Analogia**: Como sacar dinheiro no caixa eletrônico:
- Precisa da senha (aprovações)
- Precisa que a conta tenha saldo
- O banco cobra uma pequena taxa de serviço

**Condições**:
- ✅ Todos aprovaram OU contrato já finalizou
- ✅ Não tem disputa ativa
- ✅ Há dinheiro para sacar

### returnGuarantee
**Função**: `returnGuarantee()`

**Descrição**: Devolve a garantia (dinheiro/NFT/token) para o comprador.

**Analogia**: Como receber o depósito do aluguel de volta:
- Você pagou R$ 2.000 de caução
- Não fez bagunça na casa
- No final, recebe os R$ 2.000 de volta

**Tipos de garantia suportados**:
- 💰 Dinheiro (ETH)
- 🪙 Tokens (ERC-20)
- 🖼️ NFTs (ERC-721)
- 📦 Tokens colecionáveis (ERC-1155)

---

## 🤖 Funções Automáticas

### _checkAutoComplete
**Função**: `_checkAutoComplete()`

**Descrição**: Automaticamente finaliza o contrato quando detecta consenso total.

**Analogia**: Como um assistente que percebe quando todo mundo concordou:
- Pagamentos: ✅ Completos
- Aprovações: ✅ Todos deram OK
- Disputas: ✅ Nenhuma ativa
- **Resultado**: "Pronto! Vou finalizar automaticamente"

**Benefício**: Experiência mais fluida - não precisa apertar "finalizar" manualmente.

### autoExecuteTransaction
**Função**: `autoExecuteTransaction()`

**Descrição**: Após 90 dias, se ninguém se pronunciar, favorece automaticamente o vendedor.

**Analogia**: Como uma regra de futebol:
- Se o jogo não terminar em 90 minutos por decisão
- O juiz apita e define o resultado
- Padrão: vendedor recebe (ele já entregou, presume-se)

**Quando acontece**:
- ✅ Todos os pagamentos foram feitos
- ❌ Mas não houve consenso nas aprovações
- ⏰ Passaram-se 90 dias desde o prazo

### emergencyTimeout
**Função**: `emergencyTimeout()`

**Descrição**: Última proteção contra fundos ficarem presos para sempre.

**Analogia**: Como chamar o bombeiro:
- Só usa em emergências extremas
- Apenas o "dono do sistema" pode usar
- Depois de 6 meses sem solução
- Salva o dinheiro que ficaria perdido

**Situações extremas**:
- 💀 Participantes desapareceram
- 🐛 Bug no sistema que ninguém resolve
- 🔥 Disputas eternas que nunca terminam

---

## 🤝 Sistema de Acordos

### proposeSettlement
**Função**: `proposeSettlement(uint256 buyerPercentage, uint256 sellerPercentage)`

**Descrição**: Uma parte propõe dividir o dinheiro sem ir para arbitragem.

**Analogia**: Como vizinhos que brigaram e decidem conversar:
- "Que tal eu ficar com 70% e você com 30%?"
- "Assim evitamos o tribunal e resolvemos rápido"
- A outra parte tem 30 dias para decidir

**Vantagens**:
- ⚡ Mais rápido que disputa formal
- 💰 Economiza taxas de arbitragem
- 🎯 Controle total das partes

### acceptSettlement
**Função**: `acceptSettlement()`

**Descrição**: A outra parte aceita a proposta de divisão.

**Analogia**: "Aceito sua proposta, vamos dividir assim mesmo"
- Automaticamente executa a divisão
- Finaliza o contrato imediatamente
- Todo mundo sai satisfeito

---

## 📊 Funções de Consulta

### Funções de Visualização
**Descrição**: Permitem consultar informações sem alterar nada.

**Exemplos**:
- `getETHBalance`: "Quanto dinheiro tem no cofre?"
- `getRemainingInstallments`: "Quantas parcelas faltam?"
- `getEscrowInfo`: "Me mostra todos os detalhes desta custódia"

**Analogia**: Como consultar extrato bancário - você só olha, não mexe em nada.

---

## 🔄 Fluxo de Operação

### Fluxo Típico de Uso

```
1. 🏗️  Criar escrow (fora desta seleção)
2. 💎  Depositar garantias 
3. 🏁  startEscrow() - Iniciar oficialmente
4. 💰  payInstallmentETH() - Pagar parcelas
5. ✅  setReleaseApproval() - Todos aprovam
6. 🤖  _checkAutoComplete() - Sistema finaliza automaticamente
7. 🏆  withdrawFunds() - Vendedor saca
8. 🎁  returnGuarantee() - Comprador recebe garantia de volta
```

---

## 🛡️ Segurança e Proteções

### Padrão CEI (Checks-Effects-Interactions)
**O que é**: Uma metodologia de programação que evita bugs e ataques.

**Analogia**: Como seguir uma receita de bolo na ordem certa:
1. **Checks**: Conferir se tem todos os ingredientes
2. **Effects**: Misturar tudo na tigela 
3. **Interactions**: Só depois colocar no forno

**Por que é importante**: Se você colocar no forno antes de misturar, dá errado!

### Proteção contra Reentrância
**O que é**: Evita que alguém "fure a fila" e execute funções fora de ordem.

**Analogia**: Como uma porta giratória que só deixa uma pessoa passar por vez.

---

## 💡 Exemplos Práticos

### Exemplo 1: Compra de Carro Online
1. Comprador deposita R$ 50.000 como garantia
2. Vendedor deposita o carro como garantia
3. Sistema inicia automaticamente
4. Comprador paga em parcelas
5. Vendedor entrega o carro
6. Ambos aprovam a transação
7. Sistema libera os fundos

### Exemplo 2: Resolução de Disputa
1. Comprador alega que o produto não chegou
2. Abre disputa no sistema
3. Mediador analisa evidências
4. Decide: 80% para comprador, 20% para vendedor
5. Sistema executa automaticamente

---

## 📚 Glossário

### Termos Técnicos
- **Escrow**: Mecanismo de custódia que retém fundos até condições serem atendidas
- **Reentrância**: Ataque onde uma função é chamada recursivamente antes de completar
- **CEI**: Padrão Checks-Effects-Interactions para segurança
- **ERC-20**: Padrão para tokens fungíveis
- **ERC-721**: Padrão para NFTs únicos
- **ERC-1155**: Padrão para tokens colecionáveis

### Termos do Negócio
- **Garantia**: Depósito que assegura cumprimento de obrigações
- **Disputa**: Conflito entre partes que requer resolução
- **Mediador**: Terceiro que resolve disputas
- **Vesting**: Liberação gradual de tokens ao longo do tempo

---

## 🎯 Resumo para Leigos

Este contrato é como um **"cofre inteligente"** que:

1. ✅ **Guarda dinheiro** com segurança durante negócios
2. ✅ **Cobra juros** automaticamente se alguém atrasar
3. ✅ **Resolve conflitos** quando as partes brigam  
4. ✅ **Finaliza sozinho** quando todo mundo concorda
5. ✅ **Protege contra** dinheiro perdido para sempre
6. ✅ **Permite acordos** amigáveis para resolver rápido

**Benefício principal**: Permite que estranhos façam negócios com segurança, sem precisar confiar uns nos outros! 🤝

----

# 🚀 Smart Contract de Crowdfunding

## 📋 Índice
1. [Visão Geral](#visão-geral)
2. [Conceitos Fundamentais](#conceitos-fundamentais)
3. [Estrutura do Contrato](#estrutura-do-contrato)
4. [Funções Administrativas](#funções-administrativas)
5. [Criação de Campanhas](#criação-de-campanhas)
6. [Sistema de Investimento](#sistema-de-investimento)
7. [Direito de Desistência](#direito-de-desistência)
8. [Reembolso e Saques](#reembolso-e-saques)
9. [Sistema de Líderes](#sistema-de-líderes)
10. [Sistema de Tokens e Vesting](#sistema-de-tokens-e-vesting)
11. [Funções Auxiliares](#funções-auxiliares)
12. [Exemplos Práticos](#exemplos-práticos)
13. [Glossário](#glossário)

---

## 🎯 Visão Geral

Imagine que você está criando uma **"Plataforma de Investimento Digital"** que funciona como um **"Kickstarter Regulado"** para investimentos em empresas. Este smart contract implementa as regras da **Resolução CVM 88**, que é como um "manual de boas práticas" para crowdfunding no Brasil.

### 🏗️ Analogia: Uma Casa de Investimentos Digital

Pense no contrato como uma **casa de investimentos digital** onde:

- **🏢 A Casa**: O smart contract
- **📋 Os Projetos**: As campanhas de crowdfunding
- **💰 Os Investidores**: Pessoas que colocam dinheiro nos projetos
- **👑 Os Líderes**: Investidores especiais que recebem comissões
- **🏛️ A CVM**: O regulador que define as regras (como um "manual de construção")

---

## 🧠 Conceitos Fundamentais

### 1. **Campanha de Crowdfunding**
```solidity
struct Campaign {
    address creator;           // Quem criou a campanha
    uint256 minTarget;         // Meta mínima (ex: R$ 100.000)
    uint256 maxTarget;         // Meta máxima (ex: R$ 500.000)
    uint256 pledged;           // Quanto já foi investido
    uint32 startAt;           // Quando começa
    uint32 endAt;             // Quando termina
    // ... outros campos
}
```

**Analogia**: É como um **"projeto no Kickstarter"** com meta mínima e máxima.

### 2. **Investimento**
```solidity
struct Investment {
    uint256 amount;           // Quanto investiu
    bool claimed;             // Se já sacou
    uint256 investTime;       // Quando investiu
    // ... outros campos
}
```

**Analogia**: É como um **"recibo de investimento"** que guarda todas as informações.

### 3. **Tokens de Campanha**
```solidity
contract CampaignToken is ERC20 {
    // Representa o investimento como um token
}
```

**Analogia**: É como um **"certificado de investimento"** que você recebe ao investir.

---

## 🏗️ Estrutura do Contrato

### 🔐 Sistema de Permissões (AccessControl)

O contrato usa um sistema de **"cargos"** como uma empresa:

```solidity
bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");
bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
```

**Analogia**: 
- **INVESTOR_ROLE**: Como ter uma "carteirinha de investidor"
- **CREATOR_ROLE**: Como ser um "empreendedor autorizado"
- **DEFAULT_ADMIN_ROLE**: Como ser o "gerente da casa"

### 💰 Oráculos de Preço (Chainlink)

O contrato usa **"termômetros digitais"** para saber o valor das moedas:

```solidity
AggregatorV2V3Interface private immutable sequencerUptimeFeed;
AggregatorV2V3Interface private immutable usdcPriceFeed;
AggregatorV2V3Interface private immutable usdtPriceFeed;
AggregatorV2V3Interface private immutable brlPriceFeed;
AggregatorV2V3Interface private immutable ethPriceFeed;
```

**Analogia**: São como **"cotações em tempo real"** que você vê no Google Finance, mas automatizadas.

---

## ⚙️ Funções Administrativas

### 1. **setAllowedInvestor()** - Cadastrando Investidores

```solidity
function setAllowedInvestor(address[] memory investors, bool allowed) external
```

**O que faz**: Permite ou bloqueia investidores na plataforma.

**Analogia**: É como **"fazer uma lista VIP"** de quem pode investir.

**Exemplo Prático**:
```javascript
// Permitir que João e Maria possam investir
setAllowedInvestor(["0x123...", "0x456..."], true)
```

### 2. **setAllowedCreator()** - Cadastrando Criadores

```solidity
function setAllowedCreator(address[] memory creators) external
```

**O que faz**: Permite que pessoas criem campanhas.

**Analogia**: É como **"dar permissão para criar projetos"** na plataforma.

### 3. **setAnnualLimit()** - Definindo Limite Anual

```solidity
function setAnnualLimit(uint256 usdLimit) external
```

**O que faz**: Define quanto cada investidor pode investir por ano.

**Analogia**: É como **"definir um limite de cartão de crédito"** para investimentos.

**Exemplo**:
- Limite de $10.000 USD por ano
- Convertido automaticamente para BRL
- Protege investidores de investir demais

---

## 🚀 Criação de Campanhas

### **launchCampaign()** - Lançando uma Campanha

```solidity
function launchCampaign(
    uint256 _minTarget,        // Meta mínima
    uint256 _maxTarget,        // Meta máxima
    uint32 _startAt,          // Quando começa
    uint32 _endAt,            // Quando termina
    address _paymentToken,     // Qual moeda aceita
    address _officialToken,    // Token que será distribuído (use address(0) para token global)
    address[] memory _leaders, // Líderes da campanha
    // ... outros parâmetros
) external returns (uint256)
```

**Analogia**: É como **"criar uma página no Kickstarter"** com todas as regras.

#### 🎯 **Sistema de Tokens Flexível:**

O contrato suporta **dois modos** de token oficial:

1. **Token Específico da Campanha**: 
   ```solidity
   _officialToken = 0x123... // Token específico para esta campanha
   ```

2. **Token Global (Fallback)**:
   ```solidity
   _officialToken = address(0) // Usa o token definido no constructor
   ```

**Analogia**: É como **"escolher entre usar um produto específico ou o padrão da loja"**.

#### 🔍 Validações Importantes:

1. **Prazo Máximo**: Máximo 180 dias (regra CVM)
```solidity
require(_endAt <= _startAt + MAX_CAMPAIGN_DURATION, "Exceeds 180 days");
```

2. **Meta Mínima vs Máxima**: Mínima deve ser pelo menos 2/3 da máxima
```solidity
require(_minTarget * 3 >= _maxTarget * 2, "minTarget < 2/3 of maxTarget");
```

3. **Limite CVM**: Máximo 15 milhões de BRL
```solidity
require(_maxTarget <= MAX_CAMPAIGN_TARGET, "Exceeds 15M CVM limit");
```

#### 🎯 Exemplo Prático:

```javascript
// Exemplo 1: Campanha com token específico
launchCampaign(
    100_000e18,    // Meta mínima: R$ 100.000
    300_000e18,    // Meta máxima: R$ 300.000
    1640995200,    // Começa em 1º de janeiro
    1648771200,    // Termina em 1º de abril (90 dias)
    USDC_ADDRESS,  // Aceita USDC
    TOKEN_ESPECIFICO,  // Token específico da empresa
    [LEADER1, LEADER2], // 2 líderes
    [50_000e6, 30_000e6], // Mínimo de cada líder
    [500, 300]     // Carry de 5% e 3%
)

// Exemplo 2: Campanha usando token global (fallback)
launchCampaign(
    50_000e18,     // Meta mínima: R$ 50.000
    150_000e18,    // Meta máxima: R$ 150.000
    1640995200,    // Começa em 1º de janeiro
    1648771200,    // Termina em 1º de abril (90 dias)
    USDC_ADDRESS,  // Aceita USDC
    address(0),    // Usa token global definido no constructor
    [LEADER1],     // 1 líder
    [20_000e6],    // Mínimo do líder
    [300]          // Carry de 3%
)
```

### **extendDeadline()** - Estendendo o Prazo

```solidity
function extendDeadline(uint256 _id, uint32 _newEndAt) external
```

**O que faz**: Permite estender o prazo da campanha.

**Analogia**: É como **"estender o prazo de uma vaquinha"**.

**Restrições**:
- Só o criador pode estender
- Não pode passar de 180 dias
- Novo prazo deve ser maior que o atual

---

## 💰 Sistema de Investimento

### **invest()** - Fazendo um Investimento

```solidity
function invest(uint256 _campaignId, uint256 _amount) external payable
```

**Analogia**: É como **"comprar uma ação"** ou **"fazer uma doação no Kickstarter"**.

#### 🔄 Fluxo Completo:

1. **Verificação de Elegibilidade**:
   ```solidity
   require(block.timestamp >= c.startAt, "Not started"); // tempo de interação tem que ser maior ou igual ao do inicio da campanha
   require(block.timestamp <= c.endAt, "Campaign ended"); // tempo de interação tem que ser menor ou igual ao do final da campanha
   ```

2. **Cálculo de Limite Anual**:
   ```solidity
   uint256 usdValue = calculateUSDValue(acceptedAmount, c.paymentToken);
   uint256 brlValue = getBRLPrice(usdValue);
   require(investedBRLThisYear[msg.sender] + brlValue <= limit, "Exceeds limit"); // o valor já investido pelo endereço de interação + a quantidade que ele está investindo novamente tem que ser menor ou igual ao limite estipulado para os investidores.
   ```

3. **Registro do Investimento**:
   ```solidity
   inv.amount += acceptedAmount;
   // trava para evitar que o investidor invista mais que o target e devolve o valor restante até o target da campanha
   inv.investmentCount++;
   inv.investmentDates[inv.investmentCount] = block.timestamp;
   ```

4. **Mint de Tokens**:
   ```solidity
   CampaignToken(c.campaignToken).mint(msg.sender, acceptedAmount);
   ```

#### 🎯 Exemplo Prático:

```javascript
// João investe 1000 USDC na campanha #1
invest(1, 1000e6) // 1000 USDC com 6 decimais

// O que acontece:
// 1. Verifica se João pode investir
// 2. Calcula valor em BRL (ex: R$ 5.000)
// 3. Verifica limite anual
// 4. Registra investimento
// 5. Minta 1000 tokens de campanha
// 6. Emite evento Invested()
```

---

## 🔄 Direito de Desistência

### **desist()** - Desistindo de um Investimento

```solidity
function desist(uint256 _campaignId, uint256 _investmentId) external
```

**Analogia**: É como **"cancelar uma compra online"** dentro do prazo de arrependimento.

#### ⏰ Regra dos 5 Dias:

```solidity
require(
    block.timestamp <= investment.investmentDates[_investmentId] + DESIST_PERIOD,
    "Withdrawal period expired for this investment"
);
```

**Exemplo Prático**:
- João investe em 1º de janeiro às 10h
- Pode desistir até 6 de janeiro às 10h
- Após esse prazo, não pode mais desistir

#### 🔄 Processo de Desistência:

1. **Validação**: Verifica se está no prazo
2. **Cálculo**: Pega o valor específico do investimento
3. **Atualização**: Remove da campanha e do investidor
4. **Devolução**: Retorna o dinheiro/token
5. **Limpeza**: Remove o registro do investimento

---

## 💸 Reembolso e Saques

### **claimRefund()** - Reembolso em Campanha Mal-Sucedida

```solidity
function claimRefund(uint256 _id) external payable
```

**Analogia**: É como **"receber o dinheiro de volta"** quando um projeto no Kickstarter não atinge a meta.

#### 📋 Condições para Reembolso:

```solidity
require(block.timestamp > c.endAt, "Not ended yet");
require(c.pledged < c.minTarget, "Min target reached");
require(inv.amount > 0, "No investment");
require(!inv.claimed, "Already claimed");
```

**Exemplo**:
- Campanha quer R$ 100.000 (mínimo)
- Só conseguiu R$ 80.000
- Todos os investidores podem sacar o dinheiro de volta

### **claimCreator()** - Saque do Criador (Campanha Bem-Sucedida)

```solidity
function claimCreator(uint256 _id) external payable
```

**Analogia**: É como **"o criador do projeto receber o dinheiro"** quando atinge a meta.

#### 💰 Distribuição de Fundos:

1. **Taxa da Plataforma**:
   ```solidity
   uint256 feeAmount = (totalFunds * c.platformFeeBP) / DIVISOR_FACTOR;
   // já calcula a taxa do total captado.
   ```

2. **Carry dos Líderes**:
   ```solidity
   leaderCarryAmounts[i] = (remainingAfterFee * c.leaderCarryBP[i]) / DIVISOR_FACTOR;
   // calcula a taxa dos lideres sob o valor que restou já retirando taxa da plataforma.
   ```

3. **Valor para o Criador**:
   ```solidity
   uint256 netAmount = remainingAfterFee - totalCarryAmount;
   // valor para o criador depois do cálculo de todas as taxas.
   ```

#### 🎯 Exemplo Prático:

```javascript
// Campanha captou R$ 300.000
// Taxa da plataforma: 5% = R$ 15.000
// Carry do líder: 3% = R$ 8.550
// Criador recebe: R$ 276.450
```

### **claimTokens()** - Investidor Recebe Tokens

```solidity
function claimTokens(uint256 _id) external
```

**Analogia**: É como **"receber as ações da empresa"** após o investimento.

**Condições**:
- Campanha deve ter terminado
- Deve ter atingido a meta mínima
- Investidor não pode ter sacado antes

### **swapForOfficialToken()** - Troca de Tokens com Vesting

```solidity
function swapForOfficialToken(uint256 _id, uint256 amount) external nonReentrant
```

**Analogia**: É como **"trocar um voucher por ações da empresa"** com liberação gradual.

#### 🔄 Como Funciona o Swap:

1. **Queima Tokens de Campanha**: 
   ```solidity
   CampaignToken(c.campaignToken).burnFrom(msg.sender, amount);
   ```

2. **Calcula Vesting**:
   ```solidity
   uint256 vestedAmount = calculateVestedAmount(amount, c.vestingStart, c.vestingDuration, block.timestamp);
   ```

3. **Transfere Tokens Oficiais**:
   ```solidity
   if (vestedAmount > 0) {
       IERC20(c.officialToken).safeTransfer(msg.sender, vestedAmount);
   }
   ```

#### ⏰ Sistema de Vesting

**Analogia**: É como **"receber salário com liberação gradual"** ao invés de tudo de uma vez.

```solidity
function calculateVestedAmount(uint256 total, uint32 vestingStart, uint32 vestingDuration, uint256 timestamp)
    public pure returns (uint256)
{
    if (timestamp < vestingStart) return 0;           // Ainda não começou
    if (timestamp >= vestingStart + vestingDuration) return total; // Já liberou tudo
    
    return (total * (timestamp - vestingStart)) / vestingDuration; // Liberação proporcional
}
```

#### 📊 Exemplo de Vesting:

**Cenário**: 
- Total de tokens: 1000
- Vesting começa: 1º janeiro 2024
- Duração: 12 meses
- Hoje: 1º abril 2024 (3 meses depois)

**Cálculo**:
- Tempo decorrido: 3 meses
- Proporção: 3/12 = 25%
- Tokens liberados: 1000 × 25% = 250 tokens

#### 🎯 Vantagens do Sistema:

1. **🛡️ Proteção**: Evita que investidores vendam tudo de uma vez
2. **📈 Alinhamento**: Mantém investidores interessados no longo prazo
3. **⚖️ Equidade**: Todos recebem na mesma proporção do tempo
4. **🔒 Segurança**: Tokens são liberados gradualmente

#### 💡 Exemplo Prático:

```javascript
// João tem 1000 tokens de campanha
// Vesting: 12 meses começando em 1º janeiro
// Hoje: 6 meses depois

swapForOfficialToken(1, 1000) // Queima 1000 tokens de campanha
// Recebe: 500 tokens oficiais (50% do vesting)
// Restante: 500 tokens serão liberados nos próximos 6 meses
```

---

## 👑 Sistema de Líderes

### 🎯 Conceito de Líderes

**Analogia**: São como **"investidores âncora"** que recebem comissão por trazer outros investidores.

#### 📊 Estrutura de Líderes:

```solidity
address[] investorLeaders;     // Quem são os líderes
bool[] leaderQualified;        // Se qualificaram
uint256[] leaderMinContribution; // Quanto precisam investir
uint256[] leaderCarryBP;       // Qual carry recebem
```

#### 🔍 Qualificação de Líderes:

```solidity
if (msg.sender == c.investorLeaders[i] && !c.leaderQualified[i]) {
    if (inv.amount >= c.leaderMinContribution[i]) {
        c.leaderQualified[i] = true;
    }
}
```

**Exemplo**:
- Líder precisa investir mínimo R$ 50.000
- Recebe 5% de carry se qualificar
- Só recebe carry se qualificar

#### 💰 Cálculo do Carry:

```solidity
for (uint256 i = 0; i < c.investorLeaders.length; i++) {
    if (c.leaderQualified[i] && c.leaderCarryBP[i] > 0) {
        leaderCarryAmounts[i] = (remainingAfterFee * c.leaderCarryBP[i]) / DIVISOR_FACTOR;
        totalCarryAmount += leaderCarryAmounts[i];
    }
}
```

**Restrições**:
- Máximo 5 líderes por campanha
- Carry total não pode passar de 20%
- Só recebe se qualificar

---

## 🪙 Sistema de Tokens e Vesting

### 🎯 Visão Geral do Sistema de Tokens

O contrato usa **dois tipos de tokens**:

1. **CampaignToken**: Representa o investimento (como um "voucher")
2. **OfficialToken**: Token real da empresa (como "ações")

**Analogia**: É como ter um **"vale-presente"** que você pode trocar por **"produtos reais"** da loja.

### 🔄 Fluxo de Tokens

```
Investimento → CampaignToken → Swap → OfficialToken (com vesting)
```

#### 📊 Exemplo Completo:

```javascript
// 1. João investe 1000 USDC
invest(1, 1000e6)
// Recebe: 1000 CampaignTokens

// 2. Campanha é bem-sucedida
// 3. João pode trocar tokens
swapForOfficialToken(1, 1000)
// Queima: 1000 CampaignTokens
// Recebe: OfficialTokens (com vesting)
```

### ⏰ Sistema de Vesting

**Analogia**: É como **"receber salário com liberação gradual"** ao invés de tudo de uma vez.

#### 🔢 Cálculo do Vesting:

```solidity
function calculateVestedAmount(uint256 total, uint32 vestingStart, uint32 vestingDuration, uint256 timestamp)
    public pure returns (uint256)
{
    if (timestamp < vestingStart) return 0;           // Ainda não começou
    if (timestamp >= vestingStart + vestingDuration) return total; // Já liberou tudo
    
    return (total * (timestamp - vestingStart)) / vestingDuration; // Liberação proporcional
}
```

#### 📈 Exemplos de Vesting:

**Cenário 1 - Vesting de 12 meses**:
- Total: 1000 tokens
- Vesting: 1º janeiro a 31º dezembro
- Hoje: 1º abril (3 meses)
- Liberado: 1000 × (3/12) = 250 tokens

**Cenário 2 - Vesting de 6 meses**:
- Total: 1000 tokens  
- Vesting: 1º janeiro a 30º junho
- Hoje: 1º março (2 meses)
- Liberado: 1000 × (2/6) = 333 tokens

### 🎯 Vantagens do Sistema de Vesting:

1. **🛡️ Proteção**: Evita que investidores vendam tudo de uma vez
2. **📈 Alinhamento**: Mantém investidores interessados no longo prazo
3. **⚖️ Equidade**: Todos recebem na mesma proporção do tempo
4. **🔒 Segurança**: Tokens são liberados gradualmente
5. **📊 Transparência**: Cálculo matemático simples e previsível

### 💡 Casos de Uso Práticos:

#### 🏢 Startup de Tecnologia:
- Vesting: 24 meses
- Objetivo: Manter investidores alinhados com crescimento
- Resultado: Liberação gradual conforme empresa cresce

#### 🏥 Hospital:
- Vesting: 12 meses  
- Objetivo: Estabilidade financeira
- Resultado: Receita previsível ao longo do ano

#### 🏭 Fábrica:
- Vesting: 18 meses
- Objetivo: Alinhar com ciclo de produção
- Resultado: Tokens liberados conforme produção aumenta

---

## 🔧 Funções Auxiliares

### **calculateUSDValue()** - Convertendo para USD

```solidity
function calculateUSDValue(uint256 amount, address token) internal view returns (uint256)
```

**Analogia**: É como **"converter moedas"** usando cotações em tempo real.

**Exemplo**:
- 1000 USDC = $1000 USD
- 1 ETH = $3000 USD
- 1000 USDT = $1000 USD

### **getBRLPrice()** - Convertendo USD para BRL

```solidity
function getBRLPrice(uint256 usdAmount) public view returns (uint256)
```

**Analogia**: É como **"converter dólar para real"** usando cotação atual.

**Exemplo**:
- $1000 USD = R$ 5000 BRL (cotação 1 USD = 5 BRL)

### **validateCampaignAmount()** - Validando Valores

```solidity
function validateCampaignAmount(uint256 amount, address token) internal view
```

**O que faz**: Verifica se o valor não excede o limite da CVM.

**Analogia**: É como **"verificar se não está ultrapassando o limite de cartão"**.

### **checkSequencer()** - Verificando Oráculos

```solidity
function checkSequencer() internal view
```

**O que faz**: Verifica se os oráculos estão funcionando.

**Analogia**: É como **"verificar se o termômetro está funcionando"** antes de medir a temperatura.

### **hasExpiredInvestments()** - Verificando Investimentos Expirados

```solidity
function hasExpiredInvestments(uint256 _campaignId, address _investor) public view returns (bool)
```

**O que faz**: Verifica se algum investimento do investidor já passou do período de 5 dias.

**Analogia**: É como **"verificar se algum produto já passou da data de validade"**.

#### 🔍 Como Funciona:

```solidity
for (uint256 i = 1; i <= investment.investmentCount; i++) {
    if (block.timestamp > investment.investmentDates[i] + 5 days) {
        return true; // Tem investimento expirado
    }
}
return false; // Nenhum investimento expirado
```

#### 💡 Exemplo Prático:

```javascript
// João fez 3 investimentos:
// 1º: 1º janeiro (já passou de 5 dias)
// 2º: 5º janeiro (já passou de 5 dias)  
// 3º: 10º janeiro (ainda dentro de 5 dias)

hasExpiredInvestments(1, "0xJoão") // Retorna: true
// Porque tem investimentos que já passaram de 5 dias
```

---

## 📊 Exemplos Práticos

### 🏢 Exemplo 1: Startup de Tecnologia

**Cenário**: Uma startup quer captar R$ 200.000 a R$ 500.000

```javascript
// 1. Criar campanha
launchCampaign(
    200_000e18,    // Mínimo: R$ 200.000
    500_000e18,    // Máximo: R$ 500.000
    1640995200,    // Início: 1º jan 2022
    1648771200,    // Fim: 1º abr 2022 (90 dias)
    USDC_ADDRESS,  // Aceita USDC
    TOKEN_ADDRESS,  // Distribui tokens
    [LEADER1],     // 1 líder
    [50_000e6],    // Líder investe mínimo 50.000 USDC
    [500]          // Líder recebe 5% carry
)

// 2. Investidores fazem aportes
invest(1, 10_000e6)  // João investe 10.000 USDC
invest(1, 5_000e6)   // Maria investe 5.000 USDC
invest(1, 50_000e6)  // Líder investe 50.000 USDC (qualifica)

// 3. Campanha atinge meta
// 4. Criador saca fundos
claimCreator(1)
// 5. Investidores recebem tokens
claimTokens(1)
```

### 🏥 Exemplo 2: Hospital

**Cenário**: Hospital quer captar R$ 1.000.000 a R$ 2.000.000

```javascript
// Campanha com 3 líderes
launchCampaign(
    1_000_000e18,  // Mínimo: R$ 1M
    2_000_000e18,  // Máximo: R$ 2M
    1640995200,    // 90 dias
    1648771200,
    USDC_ADDRESS,
    TOKEN_ADDRESS,
    [LEADER1, LEADER2, LEADER3], // 3 líderes
    [100_000e6, 80_000e6, 60_000e6], // Mínimos
    [800, 600, 400] // Carry: 8%, 6%, 4%
)
```

---

## 📚 Glossário

### 🔤 Termos Técnicos

- **Basis Points (BP)**: 1/100 de 1%. Ex: 100 BP = 1%
- **Vesting**: Liberação gradual de tokens ao longo do tempo
- **Carry**: Comissão extra para líderes de investimento
- **Oráculo**: Fonte de dados externa (preços, etc.)
- **ReentrancyGuard**: Proteção contra ataques de reentrada
- **SafeERC20**: Biblioteca segura para transferências de tokens

### 🏛️ Termos Regulatórios (CVM 88)

- **Prazo Máximo**: 180 dias para campanhas
- **Limite Máximo**: 15 milhões de BRL por campanha
- **Período de Desistência**: 5 dias para arrependimento
- **Limite Anual**: Controle de quanto cada investidor pode investir por ano

### 💰 Termos Financeiros

- **Min Target**: Meta mínima para campanha ser bem-sucedida
- **Max Target**: Meta máxima que pode ser captada
- **Pledged**: Valor total já investido
- **Platform Fee**: Taxa cobrada pela plataforma
- **Carry**: Comissão para líderes de investimento

---

## 🎓 Conclusão

Este smart contract implementa um **sistema completo de crowdfunding regulado** que:

1. **✅ Segue as regras da CVM 88**
2. **💰 Aceita múltiplas moedas (ETH, USDC, USDT)**
3. **👑 Suporta sistema de líderes com carry**
4. **⏰ Implementa direito de desistência**
5. **🔒 Usa oráculos para preços seguros**
6. **📊 Controla limites anuais de investimento**

É como um **"Kickstarter profissional"** com todas as proteções regulatórias necessárias para o mercado brasileiro! 🚀

---

## 🚀 Deploy e Verificação

### 📋 Pré-requisitos

Antes de fazer o deploy, você precisa configurar as variáveis de ambiente:

```bash
# .env
PRIVATE_KEY=sua_chave_privada_aqui_sem_0x
BASE_RPC_URL=https://mainnet.base.org
AMOY_RPC_URL="https://amoy.g.alchemy.com/v2/"
ETHERSCAN_API_KEY=sua_api_key_do_etherscan
```

### 🔧 Comandos de Deploy

#### **1. Deploy na Base Mainnet com Verificação Automática**

```bash
forge script script/Token.s.sol:TokenScript \
    --rpc-url https://mainnet.base.org \
    --private-key ${PRIVATE_KEY} \
    --broadcast \
    --verify \
    --etherscan-api-key ${ETHERSCAN_API_KEY} \
    --verifier-url https://api.basescan.org/api
```

#### **2. Deploy na Base Sepolia (Testnet)**

```bash
forge script script/Token.s.sol:TokenScript \
    --rpc-url https://sepolia.base.org \
    --private-key ${PRIVATE_KEY} \
    --broadcast \
    --verify \
    --etherscan-api-key ${ETHERSCAN_API_KEY} \
    --verifier-url https://api-sepolia.basescan.org/api
```

#### **2.1 Deploy na Polygon Amoy (Testnet)**

```bash
forge script script/Token.s.sol:TokenScript \
    --rpc-url https://amoy.base.org \
    --private-key ${PRIVATE_KEY} \
    --broadcast \
    --verify \
    --etherscan-api-key ${POLYGONSCAN_API_KEY} \
    --verifier-url https://api-amoy.polygonscan.com/api
```

#### **3. Simulação Antes do Deploy**

```bash
# Simular deploy sem executar
forge script script/Token.s.sol:TokenScript \
    --rpc-url ${BASE_RPC_URL} \
    --private-key ${PRIVATE_KEY} \
    --dry-run

# Simular com logs detalhados
forge script script/Token.s.sol:TokenScript \
    --rpc-url ${BASE_RPC_URL} \
    --private-key ${PRIVATE_KEY} \
    --dry-run \
    -vvvv
```

### 🔍 Verificação Manual

Se precisar verificar manualmente após o deploy:

```bash
# Verificar na Base Mainnet
forge verify-contract \
    ENDERECO_DO_CONTRATO \
    src/Token.sol:Token \
    --chain-id 8453 \
    --etherscan-api-key ${ETHERSCAN_API_KEY} \
    --verifier-url https://api.basescan.org/api

# Verificar na Base Sepolia
forge verify-contract \
    ENDERECO_DO_CONTRATO \
    src/Token.sol:Token \
    --chain-id 84532 \
    --etherscan-api-key ${ETHERSCAN_API_KEY} \
    --verifier-url https://api-sepolia.basescan.org/api

## Verificar na Amoy
forge verify-contract \
    ENDERECO_DO_CONTRATO \
    src/Token.sol:Token \
    --chain-id 80002 \
    --etherscan-api-key ${POLYGONSCAN_API_KEY} \
    --verifier-url https://api-amoy.polygonscan.com/api
```

### 📊 Comandos Úteis

#### **Compilação e Testes**

```bash
# Compilar contratos
forge build

# Compilar com força (limpar cache)
forge build --force

# Verificar tamanho dos contratos
forge build --sizes

# Executar testes
forge test

# Executar testes com logs
forge test -vvv
```

#### **Monitoramento**

```bash
# Verificar status da transação
cast tx-status HASH_DA_TRANSACAO --rpc-url ${BASE_RPC_URL}

# Verificar logs do contrato
cast logs ENDERECO_DO_CONTRATO --rpc-url ${BASE_RPC_URL}

# Consultar saldo de ETH
cast balance ENDERECO --rpc-url ${BASE_RPC_URL}
```

### 📋 Checklist de Deploy

```bash
# ✅ 1. Verificar variáveis de ambiente
echo $PRIVATE_KEY
echo $BASE_RPC_URL
echo $ETHERSCAN_API_KEY

# ✅ 2. Compilar contratos
forge build

# ✅ 3. Testar localmente
forge test

# ✅ 4. Simular deploy
forge script script/Token.s.sol:TokenScript \
    --rpc-url ${BASE_RPC_URL} \
    --private-key ${PRIVATE_KEY} \
    --dry-run

# ✅ 5. Deploy real com verificação
forge script script/Token.s.sol:TokenScript \
    --rpc-url ${BASE_RPC_URL} \
    --private-key ${PRIVATE_KEY} \
    --broadcast \
    --verify \
    --etherscan-api-key ${ETHERSCAN_API_KEY} \
    --verifier-url https://api.basescan.org/api
```

### 🎯 Exemplo Completo

```bash
# Deploy completo com verificação
forge script script/Token.s.sol:TokenScript \
    --rpc-url https://mainnet.base.org \
    --private-key 0x1234567890abcdef... \
    --broadcast \
    --verify \
    --etherscan-api-key ABC123DEF456... \
    --verifier-url https://api.basescan.org/api \
    -vvvv
```

### 🔧 Configuração do foundry.toml

O projeto já está configurado com:

```toml
[rpc_endpoints]
base = "${BASE_RPC_URL}"
amoy = "${AMOY_RPC_URL}"

[etherscan]
base = { key = "${ETHERSCAN_API_KEY}" }
amoy = { key = "${POLYGONSCAN_API_KEY}" }
```

### 📊 Endereços Importantes

#### **Base Mainnet**
- **RPC URL**: `https://mainnet.base.org`
- **Chain ID**: `8453`
- **Explorer**: `https://basescan.org`
- **Verifier URL**: `https://api.basescan.org/api`

#### **Base Sepolia (Testnet)**
- **RPC URL**: `https://sepolia.base.org`
- **Chain ID**: `84532`
- **Explorer**: `https://sepolia.basescan.org`
- **Verifier URL**: `https://api-sepolia.basescan.org/api`

### 🚨 Troubleshooting

#### **Erro: "Invalid private key"**
```bash
# Verificar se a chave privada está correta
echo $PRIVATE_KEY | wc -c
# Deve retornar 65 (32 bytes + 1 para o '0x')
```

#### **Erro: "Insufficient funds"**
```bash
# Verificar saldo na Base
cast balance $(cast wallet address) --rpc-url ${BASE_RPC_URL}
```

#### **Erro: "Verification failed"**
```bash
# Tentar verificação manual
forge verify-contract ENDERECO src/Token.sol:Token \
    --chain-id 8453 \
    --etherscan-api-key ${ETHERSCAN_API_KEY}
```

### 💡 Dicas Importantes

1. **🔐 Segurança**: Nunca compartilhe sua chave privada
2. **💰 Gas**: Mantenha ETH suficiente para gas fees
3. **📝 Logs**: Use `-vvvv` para logs detalhados
4. **🧪 Testnet**: Sempre teste na Sepolia primeiro
5. **🔍 Verificação**: Sempre verifique o contrato após deploy

### 🎉 Deploy Concluído!

Após o deploy bem-sucedido, você terá:
- ✅ Contrato deployado na Base
- ✅ Código verificado no Basescan
- ✅ Contrato pronto para uso
- ✅ Documentação completa disponível 