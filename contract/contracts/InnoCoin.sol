// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import { ERC20 } from "./ERC20.sol";

contract InnoCoin is ERC20 {
    string public name = "InnoCoin";
    string public symbol = "ICC";
    uint8 public decimals = 8;
    uint256 override public totalSupply = 1000000;

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowances;

    // TODO: remove before release
    function tap() public {
        uint256 amount = 100000;
        totalSupply -= amount;
        balances[msg.sender] += amount;
    }

    function balanceOf(address _owner) public override view returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value)
        public
        override
        returns (bool success)
    {
        require(
            balances[msg.sender] >= _value,
            "Must have enough funds to transfer"
        );

        balances[msg.sender] -= _value;
        balances[_to] += _value;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override returns (bool success) {
        require(
            _value < allowances[_from][msg.sender],
            "Must be authorized to spend that much lmao"
        );

        allowances[_from][msg.sender] -= 1;
        balances[_from] -= _value;
        balances[_to] += _value;

        return true;
    }

    function approve(address _spender, uint256 _value)
        public
        override
        returns (bool success)
    {
        allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender)
        public
        override
        view
        returns (uint256 remaining)
    {
        return allowances[_owner][_spender];
    }
}
