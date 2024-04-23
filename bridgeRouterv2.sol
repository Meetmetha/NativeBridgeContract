pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract bridgeRouter is Ownable, ReentrancyGuard, Pausable {
    address public pool;
    address public relayer;
    uint256 public depositNonce;
    uint16 public sourceChain;
    struct destinationId {
        bool isActive;
    }
    mapping(bytes32 => bool) public hashed;
    mapping(uint16 => destinationId) public chainID;

    constructor(address _relayer,uint16 _sourceChain) Ownable(msg.sender) payable {
        relayer = _relayer;
        sourceChain = _sourceChain;
    }

    // Modifiers
    modifier onlyRelayer(){
        require(msg.sender == relayer);
        _;
    }

    // Events
    event BridgeInitiated(address from,address addressTo,uint256 inputAmount,uint16 sourceChain, uint16 destinationChain,uint256 timestamp,uint256 sourceNonce, bytes32 hash);
    event BridgeSuccess(address user,uint256 bridgeAmount, bytes32 hash);

    // User functions
    function bridgeTo(uint16 destinationChain, address addressTo) external payable whenNotPaused nonReentrant {
        require(msg.value >= 0,"Bridge Amount is Zero");
        destinationId storage data = chainID[destinationChain];
        require(data.isActive,"Destination chain paused or Invalid");
        (bool success,) = pool.call{value: msg.value}("");
        require(success,"Error depositing token to Pool");
        bytes32 hash = keccak256(abi.encodePacked(msg.sender, addressTo, msg.value, sourceChain, destinationChain, block.timestamp, depositNonce));
        emit BridgeInitiated(msg.sender, addressTo, msg.value, sourceChain, destinationChain, block.timestamp, depositNonce, hash);
        depositNonce++;
    }

    function isBridgeHashProcessed(bytes32 hash) public view returns (bool){
        return hashed[hash];
    }

    // OnlyRelayer
    function executeBridgeRequest(address user,uint256 bridgeAmount,bytes32 hash) external payable whenNotPaused nonReentrant onlyRelayer {
        require(!hashed[hash],"Bridge already processed");
        hashed[hash]=true;
        IPool(pool).pullLiquidity(bridgeAmount);
        (bool success,) = user.call{value: bridgeAmount}("");
        require(success,"Error transfering to user");
        emit BridgeSuccess(user, bridgeAmount, hash);
    }

     // onlyOwner
    function addDestinationChain(uint16 id, bool _isActive) public onlyOwner  {
        destinationId storage data = chainID[id];
        data.isActive = _isActive;
    }

    function pauseDestinationChain(uint16 id) public onlyOwner {
        destinationId storage data = chainID[id];
        data.isActive = false;
    }

    function pause() public onlyOwner{
        _pause();
    }

    function unpause() public onlyOwner{
        _unpause();
    }

    function updatePool(address _pool) public onlyOwner {
        pool = _pool;
    }

    function emergencyRescue() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    function recoverUnsupportedTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(owner(), token.balanceOf(address(this)));
    }

    receive() external payable {}
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IPool {
    function pullLiquidity(uint256 transferAmount) external;
}
