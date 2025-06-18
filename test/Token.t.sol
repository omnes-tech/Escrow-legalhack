// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

contract TokenTest is Test {
    Token public token;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        
        token = new Token();
    }

    function testInitialValues() public view {
        assertEq(token.name(), "Omnes");
        assertEq(token.symbol(), "OMN");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1000000 * 10 ** 18);
        assertEq(token.balanceOf(owner), 1000000 * 10 ** 18);
        assertEq(token.owner(), owner);
    }

    function testMintAsOwner() public {
        uint256 mintAmount = 100 * 10 ** 18;
        uint256 initialBalance = token.balanceOf(user1);
        uint256 initialTotalSupply = token.totalSupply();

        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), initialBalance + mintAmount);
        assertEq(token.totalSupply(), initialTotalSupply + mintAmount);
    }

    function testMintAsNonOwner() public {
        uint256 mintAmount = 100 * 10 ** 18;
        
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user2, mintAmount);
    }

    function testTransfer() public {
        uint256 transferAmount = 1000 * 10 ** 18;
        
        token.transfer(user1, transferAmount);
        
        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(owner), 1000000 * 10 ** 18 - transferAmount);
    }

    function testTransferFrom() public {
        uint256 transferAmount = 1000 * 10 ** 18;
        
        // Owner aprova user1 para gastar tokens
        token.approve(user1, transferAmount);
        
        // user1 transfere tokens do owner para user2
        vm.prank(user1);
        token.transferFrom(owner, user2, transferAmount);
        
        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.balanceOf(owner), 1000000 * 10 ** 18 - transferAmount);
        assertEq(token.allowance(owner, user1), 0);
    }

    function testTransferInsufficientBalance() public {
        uint256 transferAmount = 2000000 * 10 ** 18; // Mais que o supply inicial
        
        vm.expectRevert();
        token.transfer(user1, transferAmount);
    }

    function testApproveAndAllowance() public {
        uint256 approveAmount = 500 * 10 ** 18;
        
        token.approve(user1, approveAmount);
        
        assertEq(token.allowance(owner, user1), approveAmount);
    }

    function testMultipleMints() public {
        uint256 mintAmount1 = 100 * 10 ** 18;
        uint256 mintAmount2 = 200 * 10 ** 18;
        
        token.mint(user1, mintAmount1);
        token.mint(user2, mintAmount2);
        
        assertEq(token.balanceOf(user1), mintAmount1);
        assertEq(token.balanceOf(user2), mintAmount2);
        assertEq(token.totalSupply(), 1000000 * 10 ** 18 + mintAmount1 + mintAmount2);
    }

    function testOwnershipTransfer() public {
        // Transfere ownership para user1
        token.transferOwnership(user1);
        
        // user1 aceita a ownership
        // vm.prank(user1);
        // token.acceptOwnership();
        
        assertEq(token.owner(), user1);
        
        // Agora user1 pode fazer mint
        vm.prank(user1);
        token.mint(user2, 100 * 10 ** 18);
        
        assertEq(token.balanceOf(user2), 100 * 10 ** 18);
    }

    function testRenounceOwnership() public {
        token.renounceOwnership();
        
        assertEq(token.owner(), address(0));
        
        // Ninguém pode mais fazer mint
        vm.expectRevert();
        token.mint(user1, 100 * 10 ** 18);
    }

    // Teste fuzz para mint
    function testFuzzMint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount <= type(uint256).max - token.totalSupply());
        
        uint256 initialBalance = token.balanceOf(to);
        uint256 initialTotalSupply = token.totalSupply();
        
        token.mint(to, amount);
        
        assertEq(token.balanceOf(to), initialBalance + amount);
        assertEq(token.totalSupply(), initialTotalSupply + amount);
    }

    // Teste fuzz para transfer
    function testFuzzTransfer(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount <= token.balanceOf(owner));
        
        uint256 initialBalanceOwner = token.balanceOf(owner);
        uint256 initialBalanceTo = token.balanceOf(to);
        
        token.transfer(to, amount);
        
        if (to != owner) {
            assertEq(token.balanceOf(owner), initialBalanceOwner - amount);
            assertEq(token.balanceOf(to), initialBalanceTo + amount);
        }
    }
}
