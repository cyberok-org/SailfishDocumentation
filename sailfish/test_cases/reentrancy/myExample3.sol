pragma solidity ^0.6.3;
contract EubChainIco {
    mapping(address => uint256) balance;


    function depositEther() public payable {
        if (msg.value > 0) { 
            balance[msg.sender] += msg.value;
        }
    }

    function vestedTransfer(address _to, uint256 _amount) public {
        if(_amount <= balance[msg.sender]) {
        //    uint amount = _amount - 1;
        
            _to.call.value(_amount)("");
        //balance[_to] += amount;

        // ...

            balance[msg.sender] -= _amount;
        //transfer(msg.sender, _to, amount);
        // uint256 v1 = _amount - 15;
        // uint256 wei = v1;
        // uint t1 = vesting.startTime;
        // emit VestTransfer(msg.sender, _to, wei,t1, _);
        }
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function getBalanceUser() public view returns (uint) {
        return balance[msg.sender];
    }
}
