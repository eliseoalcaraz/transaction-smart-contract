// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract TransactionLedger {

    enum TransactionType {
        Trade,
        Donation,
        Purchase,
        Other
    }

    struct Transaction {
        uint id;
        address sender;
        address receiver;
        uint amount;
        TransactionType txType;
        uint timestamp;
        bytes32 detailsHash;
    }

    Transaction[] private transactions;

    mapping(address => uint[]) private userTxIds;

    event TransactionRecorded(
        uint indexed id,
        address indexed sender,
        address indexed receiver,
        uint8 txType,
        uint amount,
        bytes32 detailsHash,
        uint timestamp
    );

    function recordTransaction(
        address _receiver,
        uint _amount,
        TransactionType _txType,
        bytes32 _detailsHash
    ) external {
        require(_receiver != address(0), "Invalid receiver");

        uint newId = transactions.length;

        transactions.push(Transaction({
            id: newId,
            sender: msg.sender,
            receiver: _receiver,
            amount: _amount,
            txType: _txType,
            detailsHash: _detailsHash,
            timestamp: block.timestamp
        }));

        userTxIds[msg.sender].push(newId);

        if(_receiver != msg.sender) {
            userTxIds[_receiver].push(newId);
        }

        emit TransactionRecorded(
            newId,
            msg.sender,
            _receiver,
            uint8(_txType),
            _amount,
            _detailsHash,
            block.timestamp
        );
    }

     function totalTransactions() external view returns(uint) {
        return transactions.length;
    }

    function getTransactions(uint _id) external view returns (Transaction memory) {
        require(_id < transactions.length, "Invalid tx id");
        return transactions[_id];
    }

    function getAllTransactions() external view returns (Transaction[] memory) {
        return transactions;
    }

    function getUserTransactions(address _user) external view returns (Transaction[] memory userTxs) {
        uint[] storage ids = userTxIds[_user];
        uint len = ids.length;
        userTxs = new Transaction[](len);
        for(uint i = 0; i < len; ++i) {
            userTxs[i] = transactions[ids[i]];
        }
        return userTxs;
    }
}


