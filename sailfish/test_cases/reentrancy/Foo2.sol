pragma solidity ^0.4.24;

contract Foo2 {
  mapping(address => uint) balance;
  uint x = 0;
    
  function depositEther() public payable {
    if (msg.value > 0) { 
      balance[msg.sender] = balance[msg.sender] + msg.value;
    }
  }

  function withdrawAllBalance() public {
    if (balance[msg.sender] > 0) {
      msg.sender.call.value(balance[msg.sender])("");
    } else {
        x++;
        msg.sender.call.value(balance[msg.sender] - x)("");
    }
  }
}

