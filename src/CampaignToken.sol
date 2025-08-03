// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CampaignToken is ERC20 {
    address public immutable crowdfunding;
    uint256 public immutable campaignId;

    constructor(string memory _name, string memory _symbol, address _crowdfunding, uint256 _campaignId)
        ERC20(_name, _symbol)
    {
        crowdfunding = _crowdfunding;
        campaignId = _campaignId;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == crowdfunding, "Only crowdfunding can mint");
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) public {
        require(msg.sender == crowdfunding, "Only crowdfunding can burn");
        _burn(from, amount);
    }

    function mintUser(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
