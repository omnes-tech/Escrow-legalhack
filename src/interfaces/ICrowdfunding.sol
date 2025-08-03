// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

struct Campaign {
    address creator; // Endereço da empresa (emissora)
    address creatorVault; // Para onde enviar o saldo do criador
    uint256 minTarget; // Valor mínimo de captação
    uint256 maxTarget; // Valor máximo de captação
    uint256 pledged; // Valor total já investido
    uint32 startAt; // Timestamp de início
    uint32 endAt; // Timestamp de fim
    uint32 vestingStart; // Quando começa o vesting
    uint32 vestingDuration; // Quanto tempo dura o vesting
    bool claimed; // Indica se o criador já sacou os fundos
    address paymentToken; // address(0) para ETH, ou endereço ERC20
    uint256 platformFeeBP; // Fee da plataforma em basis points (ex.: 100 = 1%)
    address platformWallet; // Para onde enviar a taxa da plataforma
    address campaignToken; // ERC20 representando o investimento
    address officialToken; // Token final que os investidores receberão
    // Líderes
    address[] investorLeaders; // Endereços dos investidores líderes
    bool[] leaderQualified; // Se atingiu minLeaderContribution
    uint256[] leaderMinContribution; // Valor mínimo que ele deve aportar, ex.: 2000e6 = 2000 USDC
    uint256[] leaderCarryBP; // % de carry em basis points, ex.: 2000 => 20%
}
