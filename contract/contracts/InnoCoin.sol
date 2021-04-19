pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

contract InnoCoin {
    // The coin instrumentation part

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed _owner, address indexed _spender, uint256 value);

    string public name = "InnoCoin";
    string public symbol = "ICC";
    uint8 public decimals = 8;
    uint256 public totalSupply = 1000000;

    mapping (address => uint256) balances;
    mapping (address => mapping(address => uint256)) allowances;

    // TODO: remove befoere rearwfa
    function tap() public {
        balances[msg.sender] += 100000;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value) public returns (bool success) {
        require(balances[msg.sender] >= _value, "Must have enough funds to transfer");

        balances[msg.sender] -= _value;
        balances[_to] += _value;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value < allowances[_from][msg.sender], "Must be authorized to spend that much lmao");

        allowances[_from][msg.sender] -= 1;
        balances[_from] -= _value;
        balances[_to] += _value;

        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowances[_owner][_spender];
    }

    // The DEX part

    enum OrderSide { Bid, Ask }
    enum OrderFlags { ImmediateOrCancel, TimeInForce, GoodTillCancel }

    struct Order {
        uint256 uid;

        uint256 created_at;
        uint256 price;
        uint256 quantity;

        OrderFlags flags;
        uint256 good_till; // only if flags == TimeInForce, 0 otherwise

        address payable owner;
    }

    uint256 next_order = 1;
    Order[] public asks;
    Order[] public bids;
    Order[] public closed_asks;
    Order[] public closed_bids;

    event OrderClosed(uint256 indexed uid);

    function limitOrder(OrderSide _side, uint256 _price, uint256 _quantity, OrderFlags _flags, uint256 _good_till) external payable returns (uint256 order_uid) {
        if (_side == OrderSide.Ask) {
            require(_quantity >= balances[msg.sender], "Must have enough tokens for this ask");
            balances[msg.sender] -= _quantity;
            balances[address(this)] += _quantity;
        } else if (_side == OrderSide.Bid) {
            require(_price * _quantity == msg.value, "Must pay for the bid");
        }

        Order memory order = Order({
            uid: next_order++,
            created_at: now,
            price: _price,
            quantity: _quantity,
            flags: _flags,
            // TODO: implement good till shit
            good_till: _good_till,
            owner: msg.sender
        });

        if (_side == OrderSide.Ask) {
            asks.push(order);
        } else if (_side == OrderSide.Bid) {
            bids.push(order);
        }
        
        (uint256[] memory remove_bids, uint256[] memory remove_asks, bool covered) = this.tryCover(_side, order);

        this.filterAsksAndBids(remove_asks, remove_bids);

        return next_order - 1;
    }

    function tryCover(OrderSide _side, Order memory order) public returns (uint256[] memory, uint256[] memory, bool) {
        bool covered = false;
        uint256 next_remove_bid = 0;
        uint256[] memory remove_bids;
        uint256 next_remove_ask = 0;
        uint256[] memory remove_asks;

        Order memory ask;
        Order memory bid;
        Order[] memory others;

        if (_side == OrderSide.Ask) {
            others = bids;
        } else if (_side == OrderSide.Bid) {
            others = asks;
        }

        for (uint256 i = 0; i < others.length; i++) {
            if (_side == OrderSide.Ask) {
                ask = order;
                bid = others[i];
            } else if (_side == OrderSide.Bid) {
                bid = order;
                ask = others[i];
            }
            if (ask.price >= bid.price) {
                if (ask.quantity == bid.quantity) {
                    balances[address(this)] -= bid.quantity;
                    balances[bid.owner] += bid.quantity;
                    ask.owner.transfer(bid.price * bid.quantity);

                    closed_asks.push(ask);
                    closed_bids.push(bid);

                    emit OrderClosed(ask.uid);
                    emit OrderClosed(bid.uid);

                    covered = true;

                    remove_asks[next_remove_ask++] = ask.uid;
                    remove_bids[next_remove_bid++] = bid.uid;
                    break;
                } else if (ask.quantity > bid.quantity) {
                    balances[address(this)] -= bid.quantity;
                    balances[bid.owner] += bid.quantity;
                    ask.owner.transfer(bid.price * bid.quantity);

                    closed_bids.push(bid);

                    ask.quantity -= bid.quantity;

                    emit OrderClosed(bid.uid);

                    remove_bids[next_remove_bid++] = bid.uid;

                    if (_side == OrderSide.Bid) {
                        covered = true;
                        break;
                    }
                } else if (ask.quantity < bid.quantity) {
                    balances[address(this)] -= ask.quantity;
                    balances[bid.owner] += ask.quantity;
                    ask.owner.transfer(bid.price * ask.quantity);

                    closed_asks.push(ask);

                    bid.quantity -= ask.quantity;

                    emit OrderClosed(ask.uid);

                    remove_asks[next_remove_ask++] = ask.uid;

                    if (_side == OrderSide.Ask) {
                        covered = true;
                        break;
                    }
                }
            }
        }

        return (remove_asks, remove_bids, covered);
    }

    function filterAsksAndBids(uint256[] memory remove_asks, uint256[] memory remove_bids) public {
        for (uint256 i = 0; i < remove_asks.length; i++) {
            uint256 uid_to_remove = remove_asks[i];
            bool shit = false;
            for (uint256 j = 0; j < asks.length; j++) {
                if (asks[j].uid == uid_to_remove) {
                    shit = true;
                } else if (shit) {
                    asks[j - 1] = asks[j];
                }
            }
            asks.length--;
        }
        for (uint256 i = 0; i < remove_bids.length; i++) {
            uint256 uid_to_remove = remove_bids[i];
            bool shit = false;
            for (uint256 j = 0; j < bids.length; j++) {
                if (bids[j].uid == uid_to_remove) {
                    shit = true;
                } else if (shit) {
                    bids[j - 1] = bids[j];
                }
            }
            bids.length--;
        }
    }
}
