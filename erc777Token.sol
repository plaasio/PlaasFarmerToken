pragma solidity 0.5.3;

/*-------------------------------------------------------------------
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
 


//****************************************************************************//
//------------     HELPER CONTRACT INTERFACE STARTS HERE       ---------------//
//****************************************************************************//

interface TokensRecipientInterface {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;
}

interface TokensSenderInterface {
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;
}


//****************************************************************************//
//------------   HELPER CONTRACT ERC 1820 CODE STARTS HERE     ---------------//
//****************************************************************************//


contract ERC1820Registry {
    function setInterfaceImplementer(address _addr, bytes32 _interfaceHash, address _implementer) external;
    function getInterfaceImplementer(address _addr, bytes32 _interfaceHash) external view returns (address);
    function setManager(address _addr, address _newManager) external;
    function getManager(address _addr) public view returns (address);
}


/// Base client to interact with the registry.
contract ERC1820Client {
    ERC1820Registry constant ERC1820REGISTRY = ERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    function setInterfaceImplementation(string memory _interfaceLabel, address _implementation) internal {
        bytes32 interfaceHash = keccak256(abi.encodePacked(_interfaceLabel));
        ERC1820REGISTRY.setInterfaceImplementer(address(this), interfaceHash, _implementation);
    }

    function interfaceAddr(address addr, string memory _interfaceLabel) internal view returns(address) {
        bytes32 interfaceHash = keccak256(abi.encodePacked(_interfaceLabel));
        return ERC1820REGISTRY.getInterfaceImplementer(addr, interfaceHash);
    }

    function delegateManagement(address _newManager) internal {
        ERC1820REGISTRY.setManager(address(this), _newManager);
    }
}


//****************************************************************************//
//-------------------    MAIN CONTRACT CODE STARTS HERE     ------------------//
//****************************************************************************//


contract MyERC777 is ERC1820Client {
    using SafeMath for uint256;

    string internal mName;
    string internal mSymbol;
    uint256 internal mGranularity;
    uint256 internal mTotalSupply;


    mapping(address => uint) internal mBalances;

    address[] internal mDefaultOperators;
    mapping(address => bool) internal mIsDefaultOperator;
    mapping(address => mapping(address => bool)) internal mRevokedDefaultOperator;
    mapping(address => mapping(address => bool)) internal mAuthorizedOperators;

    /* Events */
    event Sent(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data,
        bytes operatorData
    );
    event Minted(
        address indexed operator,
        address indexed to,
        uint256 amount,
        bytes data,
        bytes operatorData
    );
    event Burned(
        address indexed operator,
        address indexed from,
        uint256 amount,
        bytes data,
        bytes operatorData
    );
    event AuthorizedOperator(
        address indexed operator,
        address indexed holder
    );
    event RevokedOperator(address indexed operator, address indexed holder);

    /* -- Constructor -- */
    //
    /// @notice Constructor to create a ReferenceToken
    /// @param _name Name of the new token
    /// @param _symbol Symbol of the new token.
    /// @param _granularity Minimum transferable chunk.
    constructor(string memory _name, string memory _symbol, uint256 _granularity, address[] memory _defaultOperators) internal {
        mName = _name;
        mSymbol = _symbol;
        mTotalSupply = 0;
        require(_granularity >= 1, "Granularity must be > 1");
        mGranularity = _granularity;

        mDefaultOperators = _defaultOperators;
        for (uint256 i = 0; i < mDefaultOperators.length; i++) {
			mIsDefaultOperator[mDefaultOperators[i]] = true; 
		}

        //setInterfaceImplementation("ERC777Token", address(this));
    }

    //
    /// @return the name of the token
    function name() public view returns (string memory) { return mName; }

    /// @return the symbol of the token
    function symbol() public view returns (string memory) { return mSymbol; }

    /// @return the granularity of the token
    function granularity() public view returns (uint256) { return mGranularity; }

    /// @return the total supply of the token
    function totalSupply() public view returns (uint256) { return mTotalSupply; }

    /// @notice Return the account balance of some account
    /// @param _tokenHolder Address for which the balance is returned
    /// @return the balance of `_tokenAddress`.
    function balanceOf(address _tokenHolder) public view returns (uint256) { return mBalances[_tokenHolder]; }

    /// @notice Return the list of default operators
    /// @return the list of all the default operators
    function defaultOperators() public view returns (address[] memory) { return mDefaultOperators; }

    /// @notice Send `_amount` of tokens to address `_to` passing `_data` to the recipient
    /// @param _to The address of the recipient
    /// @param _amount The number of tokens to be sent
    function send(address _to, uint256 _amount, bytes calldata _data) external {
        doSend(msg.sender, msg.sender, _to, _amount, _data, "", true);
    }

    /// @notice Authorize a third party `_operator` to manage (send) `msg.sender`'s tokens.
    /// @param _operator The operator that wants to be Authorized
    function authorizeOperator(address _operator) external {
        require(_operator != msg.sender, "Cannot authorize yourself as an operator");
        if (mIsDefaultOperator[_operator]) {
            mRevokedDefaultOperator[_operator][msg.sender] = false;
        } else {
            mAuthorizedOperators[_operator][msg.sender] = true;
        }
        emit AuthorizedOperator(_operator, msg.sender);
    }

    /// @notice Revoke a third party `_operator`'s rights to manage (send) `msg.sender`'s tokens.
    /// @param _operator The operator that wants to be Revoked
    function revokeOperator(address _operator) external {
        require(_operator != msg.sender, "Cannot revoke yourself as an operator");
        if (mIsDefaultOperator[_operator]) {
            mRevokedDefaultOperator[_operator][msg.sender] = true;
        } else {
            mAuthorizedOperators[_operator][msg.sender] = false;
        }
        emit RevokedOperator(_operator, msg.sender);
    }

    /// @notice Check whether the `_operator` address is allowed to manage the tokens held by `_tokenHolder` address.
    /// @param _operator address to check if it has the right to manage the tokens
    /// @param _tokenHolder address which holds the tokens to be managed
    /// @return `true` if `_operator` is authorized for `_tokenHolder`
    function isOperatorFor(address _operator, address _tokenHolder) public view returns (bool) {
        return (_operator == _tokenHolder // solium-disable-line operator-whitespace
            || mAuthorizedOperators[_operator][_tokenHolder]
            || (mIsDefaultOperator[_operator] && !mRevokedDefaultOperator[_operator][_tokenHolder]));
    }

    /// @notice Send `_amount` of tokens on behalf of the address `from` to the address `to`.
    /// @param _from The address holding the tokens being sent
    /// @param _to The address of the recipient
    /// @param _amount The number of tokens to be sent
    /// @param _data Data generated by the user to be sent to the recipient
    /// @param _operatorData Data generated by the operator to be sent to the recipient
    function operatorSend(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data,
        bytes calldata _operatorData
    )
        external
    {
        require(isOperatorFor(msg.sender, _from), "Not an operator");
        doSend(msg.sender, _from, _to, _amount, _data, _operatorData, true);
    }

    function burn(uint256 _amount, bytes calldata _data) external {
        doBurn(msg.sender, msg.sender, _amount, _data, "");
    }

    function operatorBurn(
        address _tokenHolder,
        uint256 _amount,
        bytes calldata _data,
        bytes calldata _operatorData
    )
        external
    {
        require(isOperatorFor(msg.sender, _tokenHolder), "Not an operator");
        doBurn(msg.sender, _tokenHolder, _amount, _data, _operatorData);
    }

    /* -- Helper Functions -- */
    //
    /// @notice Internal function that ensures `_amount` is multiple of the granularity
    /// @param _amount The quantity that want's to be checked
    function requireMultiple(uint256 _amount) internal view {
        require(_amount % mGranularity == 0, "Amount is not a multiple of granualrity");
    }

    /// @notice Check whether an address is a regular address or not.
    /// @param _addr Address of the contract that has to be checked
    /// @return `true` if `_addr` is a regular address (not a contract)
    function isRegularAddress(address _addr) internal view returns(bool) {
        if (_addr == address(0)) { return false; }
        uint size;
        assembly { size := extcodesize(_addr) } // solium-disable-line security/no-inline-assembly
        return size == 0;
    }

    /// @notice Helper function actually performing the sending of tokens.
    /// @param _operator The address performing the send
    /// @param _from The address holding the tokens being sent
    /// @param _to The address of the recipient
    /// @param _amount The number of tokens to be sent
    /// @param _data Data generated by the user to be passed to the recipient
    /// @param _operatorData Data generated by the operator to be passed to the recipient
    /// @param _preventLocking `true` if you want this function to throw when tokens are sent to a contract not
    ///  implementing `tokensRecipientInterface`.
    ///  ERC777 native Send functions MUST set this parameter to `true`, and backwards compatible ERC20 transfer
    ///  functions SHOULD set this parameter to `false`.
    function doSend(
        address _operator,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data,
        bytes memory _operatorData,
        bool _preventLocking
    )
        internal
    {
        requireMultiple(_amount);

        callSender(_operator, _from, _to, _amount, _data, _operatorData);

        require(_to != address(0), "Cannot send to 0x0");
        require(mBalances[_from] >= _amount, "Not enough funds");

        mBalances[_from] = mBalances[_from].sub(_amount);
        mBalances[_to] = mBalances[_to].add(_amount);

        callRecipient(_operator, _from, _to, _amount, _data, _operatorData, _preventLocking);

        emit Sent(_operator, _from, _to, _amount, _data, _operatorData);
    }

    /// @notice Helper function actually performing the burning of tokens.
    /// @param _operator The address performing the burn
    /// @param _tokenHolder The address holding the tokens being burn
    /// @param _amount The number of tokens to be burnt
    /// @param _data Data generated by the token holder
    /// @param _operatorData Data generated by the operator
    function doBurn(
        address _operator,
        address _tokenHolder,
        uint256 _amount,
        bytes memory _data,
        bytes memory _operatorData
    )
        internal
    {
        callSender(_operator, _tokenHolder, address(0), _amount, _data, _operatorData);

        requireMultiple(_amount);
        require(balanceOf(_tokenHolder) >= _amount, "Not enough funds");

        mBalances[_tokenHolder] = mBalances[_tokenHolder].sub(_amount);
        mTotalSupply = mTotalSupply.sub(_amount);

        emit Burned(_operator, _tokenHolder, _amount, _data, _operatorData);
    }

    /// @notice Helper function that checks for TokensRecipientInterface on the recipient and calls it.
    ///  May throw according to `_preventLocking`
    /// @param _operator The address performing the send or mint
    /// @param _from The address holding the tokens being sent
    /// @param _to The address of the recipient
    /// @param _amount The number of tokens to be sent
    /// @param _data Data generated by the user to be passed to the recipient
    /// @param _operatorData Data generated by the operator to be passed to the recipient
    /// @param _preventLocking `true` if you want this function to throw when tokens are sent to a contract not
    ///  implementing `TokensRecipientInterface`.
    ///  ERC777 native Send functions MUST set this parameter to `true`, and backwards compatible ERC20 transfer
    ///  functions SHOULD set this parameter to `false`.
    function callRecipient(
        address _operator,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data,
        bytes memory _operatorData,
        bool _preventLocking
    )
        internal
    {
        address recipientImplementation = interfaceAddr(_to, "TokensRecipientInterface");
        if (recipientImplementation != address(0)) {
                TokensRecipientInterface(recipientImplementation).tokensReceived(
                _operator, _from, _to, _amount, _data, _operatorData);
        } else if (_preventLocking) {
            require(isRegularAddress(_to), "Cannot send to contract without TokensRecipientInterface");
        }
    }

    /// @notice Helper function that checks for TokensSenderInterface on the sender and calls it.
    ///  May throw according to `_preventLocking`
    /// @param _from The address holding the tokens being sent
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be sent
    /// @param _data Data generated by the user to be passed to the recipient
    /// @param _operatorData Data generated by the operator to be passed to the recipient
    ///  implementing `TokensSenderInterface`.
    ///  ERC777 native Send functions MUST set this parameter to `true`, and backwards compatible ERC20 transfer
    ///  functions SHOULD set this parameter to `false`.
    function callSender(
        address _operator,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data,
        bytes memory _operatorData
    )
        internal
    {
        address senderImplementation = interfaceAddr(_from, "TokensSenderInterface");
        if (senderImplementation == address(0)) { return; }
        TokensSenderInterface(senderImplementation).tokensToSend(
            _operator, _from, _to, _amount, _data, _operatorData);
    }
}    

//****************************************************************************//
//---------------------        Helper Contracts          ---------------------//
//****************************************************************************//



contract ERC1820ImplementerInterface {
    bytes32 constant ERC1820_ACCEPT_MAGIC = keccak256(abi.encodePacked("ERC1820_ACCEPT_MAGIC"));

    /// @notice Indicates whether the contract implements the interface `interfaceHash` for the address `addr`.
    /// @param interfaceHash keccak256 hash of the name of the interface
    /// @param addr Address for which the contract will implement the interface
    /// @return ERC1820_ACCEPT_MAGIC only if the contract implements `ìnterfaceHash` for the address `addr`.
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address addr) external view returns(bytes32);
}


contract TokensRecipient is ERC1820Client, ERC1820ImplementerInterface, TokensRecipientInterface, owned {

    bool private allowTokensReceived;

    mapping(address => address) public token;
    mapping(address => address) public operator;
    mapping(address => address) public from;
    mapping(address => address) public to;
    mapping(address => uint256) public amount;
    mapping(address => bytes) public data;
    mapping(address => bytes) public operatorData;
    mapping(address => uint256) public balanceOf;

    constructor(bool _setInterface) public {
        if (_setInterface) { setInterfaceImplementation("TokensRecipientInterface", address(this)); }
        allowTokensReceived = true;
    }

    function tokensReceived(
        address _operator,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data,
        bytes calldata _operatorData
    )
        external
    {
        require(allowTokensReceived, "Receive not allowed");
        token[_to] = msg.sender;
        operator[_to] = _operator;
        from[_to] = _from;
        to[_to] = _to;
        amount[_to] = _amount;
        data[_to] = _data;
        operatorData[_to] = _operatorData;
        balanceOf[_from] = MyERC777(msg.sender).balanceOf(_from);
        balanceOf[_to] = MyERC777(msg.sender).balanceOf(_to);
    }

    function acceptTokens() public onlyOwner { allowTokensReceived = true; }

    function rejectTokens() public onlyOwner { allowTokensReceived = false; }

    function canImplementInterfaceForAddress(bytes32 _interfaceHash, address _addr) external view returns(bytes32) {
        return ERC1820_ACCEPT_MAGIC;
    }
}


contract TokensSender is ERC1820Client, ERC1820ImplementerInterface, TokensSenderInterface, owned {

    bool private allowTokensToSend;

    mapping(address => address) public token;
    mapping(address => address) public operator;
    mapping(address => address) public from;
    mapping(address => address) public to;
    mapping(address => uint256) public amount;
    mapping(address => bytes) public data;
    mapping(address => bytes) public operatorData;
    mapping(address => uint256) public balanceOf;

    constructor(bool _setInterface) public {
        if (_setInterface) { setInterfaceImplementation("ERC777TokensSender", address(this)); }
        allowTokensToSend = true;
    }

    function tokensToSend(
        address _operator,
        address _from,
        address _to,
        uint _amount,
        bytes calldata _data,
        bytes calldata _operatorData
    )
        external
    {
        require(allowTokensToSend, "Send not allowed");
        token[_to] = msg.sender;
        operator[_to] = _operator;
        from[_to] = _from;
        to[_to] = _to;
        amount[_to] = _amount;
        data[_to] = _data;
        operatorData[_to] = _operatorData;
        balanceOf[_from] = MyERC777(msg.sender).balanceOf(_from);
        balanceOf[_to] = MyERC777(msg.sender).balanceOf(_to);
    }

    function acceptTokensToSend() public onlyOwner { allowTokensToSend = true; }

    function rejectTokensToSend() public onlyOwner { allowTokensToSend = false; }

    function canImplementInterfaceForAddress(bytes32 _interfaceHash, address _addr) external view  returns(bytes32) {
        return ERC1820_ACCEPT_MAGIC;
    }

}


