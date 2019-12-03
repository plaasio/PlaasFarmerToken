pragma solidity 0.5.13;

/*

___________________________________________________________________
  _      _                                        ______           
  |  |  /          /                                /              
--|-/|-/-----__---/----__----__---_--_----__-------/-------__------
  |/ |/    /___) /   /   ' /   ) / /  ) /___)     /      /   )     
__/__|____(___ _/___(___ _(___/_/_/__/_(___ _____/______(___/__o_o_



  _____  _                          _____       _______ ____  _  ________ _   _        _______          __     _____  _____ _____ _   _  _____ 
 |  __ \| |        /\        /\    / ____|     |__   __/ __ \| |/ /  ____| \ | |      / ____\ \        / /\   |  __ \|  __ \_   _| \ | |/ ____|
 | |__) | |       /  \      /  \  | (___          | | | |  | | ' /| |__  |  \| |     | (___  \ \  /\  / /  \  | |__) | |__) || | |  \| | |  __ 
 |  ___/| |      / /\ \    / /\ \  \___ \         | | | |  | |  < |  __| | . ` |      \___ \  \ \/  \/ / /\ \ |  ___/|  ___/ | | | . ` | | |_ |
 | |    | |____ / ____ \  / ____ \ ____) |        | | | |__| | . \| |____| |\  |      ____) |  \  /\  / ____ \| |    | |    _| |_| |\  | |__| |
 |_|    |______/_/    \_\/_/    \_\_____/         |_|  \____/|_|\_\______|_| \_|     |_____/    \/  \/_/    \_\_|    |_|   |_____|_| \_|\_____|
                                                                                                                                               
                                                                                                                                               


=== 'PLAAS' Token Swapping contract with following features ===
    => SafeMath implementation 
    => Conversion of ERC20 PLAAS tokens to ERC777 PLAAS tokens


-------------------------------------------------------------------
 Copyright (c) 2019 onwards PLAAS Inc. ( https://plaas.io )
 Contract designed with ❤ by EtherAuthority ( https://EtherAuthority.io )
-------------------------------------------------------------------
*/ 

//*******************************************************************//
//------------------------ SafeMath Library -------------------------//
//*******************************************************************//
/**
    * @title SafeMath
    * @dev Math operations with safety checks that throw on error
    */
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
        return 0;
    }
    uint256 c = a * b;
    require(c / a == b, 'SafeMath mul failed');
    return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a, 'SafeMath sub failed');
    return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, 'SafeMath add failed');
    return c;
    }
}


//*******************************************************************//
//------------------ Contract to Manage Ownership -------------------//
//*******************************************************************//
    
contract owned {
    address payable public owner;
    address payable internal newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address payable _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    //this flow is to prevent transferring ownership to wrong wallet by mistake
    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}


interface ERC20Essential 
{
    function balanceOf(address _tokenHolder) external view returns (uint256);
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);
}




interface ERC777Essential 
{
    function balanceOf(address _tokenHolder) external view returns (uint256);
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);
}



contract tokenSwapping is owned {
  using SafeMath for uint256;
  uint public exchangeRate = 500; // 1 erc 777 token = ? erc 20 token. Here the conversion is: 1 erc777 = 500 erc20
  address public oldTokenContract;
  address public newTokenContract;
  address public ERC777OwnerAddress;
  uint256 internal tokenAmount;
  uint256 internal newTokenAmount;
  
  // This will log swapping of token
  event Exchanged(uint256 curTime, address oldToken, address newToken, address user, uint oldAmount, uint newAmount);
  
  constructor(address ERC20Contract, address ERC777Contract, address ERC777Owner) public {
    require(ERC20Contract!=address(0), 'Invalid token address');
	oldTokenContract = ERC20Contract;
	newTokenContract = ERC777Contract;
	 ERC777OwnerAddress = ERC777Owner;
  }
  
  function updateExchangeRate(uint256 _exchangeRate) public onlyOwner {
	exchangeRate = _exchangeRate;
  }
  
  function tokenSwap() public {
    //remember to call Token(address).approve(address(this), amount) or this contract will not be able to do the transfer on your behalf.
	tokenAmount = ERC20Essential(oldTokenContract).balanceOf(msg.sender);
	require(tokenAmount > 0, "Insufficient Old Token Balance");
	newTokenAmount = tokenAmount.div(exchangeRate);
	require(newTokenAmount <= ERC777Essential(newTokenContract).balanceOf(ERC777OwnerAddress), "Insufficient New Token Balance");
    require(ERC20Essential(oldTokenContract).transferFrom(msg.sender, address(this), tokenAmount), 'old tokens could not be transferred');
    require(ERC777Essential(newTokenContract).transferFrom(ERC777OwnerAddress, msg.sender, newTokenAmount), 'new tokens could not be transferred');
    emit Exchanged(now, oldTokenContract, newTokenContract, msg.sender, tokenAmount, newTokenAmount);
	
  }
}
