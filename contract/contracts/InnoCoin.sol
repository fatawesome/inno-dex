// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";

contract InnoCoin {
    // The coin instrumentation part

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 value
    );

    string public name = "InnoCoin";
    string public symbol = "ICC";
    uint8 public decimals = 8;
    uint256 public totalSupply = 1000000;

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowances;

    // TODO: remove befoere release
    function tap() public {
        balances[msg.sender] += 100000;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value)
        public
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
    ) public returns (bool success) {
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
        returns (bool success)
    {
        allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender)
        public
        view
        returns (uint256 remaining)
    {
        return allowances[_owner][_spender];
    }

    // The DEX part

    enum OrderSide {Bid, Ask}
    enum OrderFlags {ImmediateOrCancel, TimeInForce, GoodTillCancel}

    struct Order {
        uint256 uid;
        OrderSide side;
        uint256 created_at;
        uint256 price;
        uint256 quantity;
        uint256 original_quantity;
        OrderFlags flags;
        uint256 good_till; // only if flags == TimeInForce, 0 otherwise
        address payable owner;
    }

    uint256 public next_order = 1;
    Order[] public asks;
    Order[] public bids;
    Order[] public closed_asks;
    Order[] public closed_bids;
    Order[] public canceled_asks;
    Order[] public canceled_bids;

    event OrderClosed(uint256 indexed uid);
    event OrderCanceled(uint256 indexed uid);

    function orderExists(uint256 uid) external view returns (bool exists) {
        for (uint256 i = 0; i < asks.length; i++) {
            if (asks[i].uid == uid) {
                return true;
            }
        }
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].uid == uid) {
                return true;
            }
        }
        for (uint256 i = 0; i < closed_asks.length; i++) {
            if (closed_asks[i].uid == uid) {
                return true;
            }
        }
        for (uint256 i = 0; i < closed_bids.length; i++) {
            if (closed_bids[i].uid == uid) {
                return true;
            }
        }
        for (uint256 i = 0; i < canceled_asks.length; i++) {
            if (canceled_asks[i].uid == uid) {
                return true;
            }
        }
        for (uint256 i = 0; i < canceled_bids.length; i++) {
            if (canceled_bids[i].uid == uid) {
                return true;
            }
        }
        return false;
    }

    function amountOfOpenAsks() external view returns (uint256) {
        return asks.length;
    }

    function amountOfOpenBids() external view returns (uint256) {
        return bids.length;
    }

    function amountOfClosedAsks() external view returns (uint256) {
        return closed_asks.length;
    }

    function amountOfClosedBids() external view returns (uint256) {
        return closed_bids.length;
    }

    function amountOfCanceledAsks() external view returns (uint256) {
        return canceled_asks.length;
    }

    function amountOfCanceledBids() external view returns (uint256) {
        return canceled_bids.length;
    }

    function orderByUid(uint256 uid) external view returns (Order memory) {
        for (uint256 i = 0; i < asks.length; i++) {
            if (asks[i].uid == uid) {
                return asks[i];
            }
        }

        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].uid == uid) {
                return bids[i];
            }
        }

        for (uint256 i = 0; i < closed_asks.length; i++) {
            if (closed_asks[i].uid == uid) {
                return closed_asks[i];
            }
        }

        for (uint256 i = 0; i < closed_bids.length; i++) {
            if (closed_bids[i].uid == uid) {
                return closed_bids[i];
            }
        }

        for (uint256 i = 0; i < canceled_asks.length; i++) {
            if (canceled_asks[i].uid == uid) {
                return canceled_asks[i];
            }
        }

        for (uint256 i = 0; i < canceled_bids.length; i++) {
            if (canceled_bids[i].uid == uid) {
                return canceled_bids[i];
            }
        }

        revert("No such order found");
    }

    function limitOrder(
        uint256 _uid,
        OrderSide _side,
        uint256 _price,
        uint256 _quantity,
        OrderFlags _flags,
        uint256 _good_till
    ) external payable returns (bool success) {
        console.log(block.timestamp);

        require(!this.orderExists(_uid), "uid must be unused");
        next_order++;

        this.removeStaleOrders();

        if (_side == OrderSide.Ask) {
            require(
                _quantity <= balances[msg.sender],
                "Must have enough tokens for this ask"
            );
            balances[msg.sender] -= _quantity;
            balances[address(this)] += _quantity;
        } else if (_side == OrderSide.Bid) {
            require(_price * _quantity == msg.value, "Must pay for the bid");
        }

        Order memory order =
            Order({
                side: _side,
                uid: _uid,
                created_at: block.timestamp,
                price: _price,
                quantity: _quantity,
                original_quantity: _quantity,
                flags: _flags, // TODO: implement good till
                good_till: _good_till,
                owner: msg.sender
            });

        (
            uint256[] memory remove_asks,
            uint256[] memory remove_bids,
            Order memory new_order,
            bool covered
        ) = this.tryCover(_side, order);

        if (_flags == OrderFlags.ImmediateOrCancel) {
            if (!covered) {
                if (_side == OrderSide.Ask) {
                    canceled_asks.push(new_order);
                    emit OrderCanceled(new_order.uid);
                } else if (_side == OrderSide.Bid) {
                    canceled_bids.push(new_order);
                    emit OrderCanceled(new_order.uid);
                }
            }
        } else {
            if (_side == OrderSide.Ask) {
                console.log(new_order.quantity);
                asks.push(new_order);
            } else if (_side == OrderSide.Bid) {
                bids.push(new_order);
            }
        }

        this.filterAsksAndBids(remove_asks, remove_bids);

        return true;
    }

    function tryCover(OrderSide _side, Order memory order)
        public
        returns (
            uint256[] memory,
            uint256[] memory,
            Order memory,
            bool
        )
    {
        bool covered = false;
        uint256 next_remove_bid = 0;
        uint256[] memory remove_bids = new uint256[](bids.length + 1);
        uint256 next_remove_ask = 0;
        uint256[] memory remove_asks = new uint256[](asks.length + 1);

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
            if (ask.price <= bid.price) {
                if (ask.quantity == bid.quantity) {
                    balances[address(this)] -= bid.quantity;
                    balances[bid.owner] += bid.quantity;
                    ask.owner.transfer(bid.price * bid.quantity);

                    closed_asks.push(ask);
                    closed_bids.push(bid);

                    emit OrderClosed(ask.uid);
                    emit OrderClosed(bid.uid);

                    covered = true;

                    remove_asks[next_remove_ask] = ask.uid;
                    remove_bids[next_remove_bid] = bid.uid;
                    next_remove_ask++;
                    next_remove_bid++;
                    break;
                } else if (ask.quantity > bid.quantity) {
                    balances[address(this)] -= bid.quantity;
                    balances[bid.owner] += bid.quantity;
                    ask.owner.transfer(bid.price * bid.quantity);

                    closed_bids.push(bid);

                    console.log(" ");
                    console.log("Reducing ask quantity (%d) by %d", ask.quantity, bid.quantity);
                    ask.quantity -= bid.quantity;
                    console.log(" ");

                    emit OrderClosed(bid.uid);

                    remove_bids[next_remove_bid] = bid.uid;
                    next_remove_bid++;

                    if (_side == OrderSide.Bid) {
                        covered = true;
                        break;
                    }
                } else if (ask.quantity < bid.quantity) {
                    balances[address(this)] -= ask.quantity;
                    balances[bid.owner] += ask.quantity;
                    ask.owner.transfer(bid.price * ask.quantity);

                    closed_asks.push(ask);

                    console.log(" ");
                    console.log("Reducing bid quantity (%d) by %d", bid.quantity, ask.quantity);
                    bid.quantity -= ask.quantity;
                    console.log(" ");

                    emit OrderClosed(ask.uid);

                    remove_asks[next_remove_ask] = ask.uid;
                    next_remove_ask++;

                    if (_side == OrderSide.Ask) {
                        covered = true;
                        break;
                    }
                }
            }
        }

        if (_side == OrderSide.Ask) {
            for (uint256 i = 0; i < others.length; i++) {
                bids[i] = others[i];
            }
        } else if (_side == OrderSide.Bid) {
            for (uint256 i = 0; i < others.length; i++) {
                asks[i] = others[i];
            }
        }

        return (remove_asks, remove_bids, order, covered);
    }

    function removeStaleOrders() public {
        uint256 next_remove_bid = 0;
        uint256[] memory remove_bids = new uint256[](bids.length);
        uint256 next_remove_ask = 0;
        uint256[] memory remove_asks = new uint256[](asks.length);

        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].flags == OrderFlags.TimeInForce && bids[i].good_till < block.timestamp) {
                remove_bids[next_remove_bid++] = bids[i].uid;
                emit OrderCanceled(bids[i].uid);
                canceled_bids.push(bids[i]);
            }
        }
        for (uint256 i = 0; i < asks.length; i++) {
            if (asks[i].flags == OrderFlags.TimeInForce && asks[i].good_till < block.timestamp) {
                remove_asks[next_remove_ask++] = asks[i].uid;
                emit OrderCanceled(asks[i].uid);
                canceled_asks.push(asks[i]);
            }
        }

        this.filterAsksAndBids(remove_asks, remove_bids);
    }

    function filterAsksAndBids(
        uint256[] memory remove_asks,
        uint256[] memory remove_bids
    ) public {
        console.log(" ");
        console.log("Asks length before %d", asks.length);
        for (uint256 i = 0; i < remove_asks.length; i++) {
            uint256 uid_to_remove = remove_asks[i];
            console.log("Trying to remove %d", uid_to_remove);
            bool shift = false;
            for (uint256 j = 0; j < asks.length; j++) {
                console.log("Current ask uid %d", asks[j].uid);
                if (asks[j].uid == uid_to_remove) {
                    console.log("Found %d", uid_to_remove);
                    shift = true;
                } else if (shift) {
                    asks[j - 1] = asks[j];
                }
            }
            if (shift) {
                console.log("Trying to pop asks");
                asks.pop();
            }
        }
        console.log("Asks length after %d", asks.length);
        console.log(" ");
        console.log("Bids length before %d", bids.length);
        for (uint256 i = 0; i < remove_bids.length; i++) {
            uint256 uid_to_remove = remove_bids[i];
            console.log("Trying to remove %d", uid_to_remove);
            bool shift = false;
            for (uint256 j = 0; j < bids.length; j++) {
                if (bids[j].uid == uid_to_remove) {
                    console.log("Found %d", uid_to_remove);
                    shift = true;
                } else if (shift) {
                    bids[j - 1] = bids[j];
                }
            }
            if (shift) {
                bids.pop();
            }
        }
        console.log("Bids length after", bids.length);
    }
}
