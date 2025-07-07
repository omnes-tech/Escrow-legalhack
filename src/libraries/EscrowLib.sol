// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IEscrow} from "../interfaces/IEscrow.sol";

library EscrowLib {
    /**
     * @notice Calcula juros simples
     * @param _amount Valor principal
     * @param _dailyInterestBP Taxa de juros diária em basis points
     * @param _days Número de dias
     * @return Juros calculados
     */
    function calculateSimpleInterest(uint256 _amount, uint256 _dailyInterestBP, uint256 _days)
        internal
        pure
        returns (uint256)
    {
        // 🧮 MATEMÁTICA: Principal × Taxa × Tempo
        // 📊 BASIS POINTS: Dividimos por 10000 (100 BP = 1%)
        // 🔼 ARREDONDAMENTO: +9999 garante arredondamento para cima
        return (_amount * _dailyInterestBP * _days + 9999) / 10000;
    }

    /**
     * @notice Calcula juros compostos
     * @param _amount Valor principal
     * @param _dailyInterestBP Taxa de juros diária em basis points
     * @param _days Número de dias
     * @return Juros calculados
     */
    function calculateCompoundInterest(uint256 _amount, uint256 _dailyInterestBP, uint256 _days)
        internal
        pure
        returns (uint256)
    {
        // 🎯 CONFIGURAÇÃO: Base para cálculos (10000 = 100%)
        uint256 base = 10000;
        uint256 compoundedAmount = _amount;

        // 🔄 LOOP DIÁRIO: Aplica juros dia por dia para precisão máxima
        for (uint256 i = 0; i < _days; i++) {
            // 📊 CÁLCULO: Juros do dia sobre o montante atual
            // 🔼 TRUQUE: + (base - 1) = arredondamento para cima
            uint256 interest = (compoundedAmount * _dailyInterestBP + (base - 1)) / base;

            // 📈 ACUMULAR: Adiciona juros do dia ao montante
            compoundedAmount += interest;
        }

        // 🎯 RETORNO: Apenas os juros (montante final - principal)
        return compoundedAmount - _amount;
    }
}
