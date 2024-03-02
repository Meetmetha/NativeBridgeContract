pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract bridgeRouter is Ownable, ReentrancyGuard, Pausable {
    address public pool;
    address public relayer;
    uint256 public nonce;
    struct destinationId {
        string networkName;
        bool isEVM;
        bool isActive;
    }
    mapping(uint16 => destinationId) public destIdData;

    constructor(address _pool,address _relayer) payable {
        pool = _pool;
        relayer = _relayer;
    }

    // Modifiers
    modifier onlyRelayer(){
        require(msg.sender == relayer);
        _;
    }

    // Events
    event TokenDeposited(address user,uint256 etherAmount,uint16 destinationChain,bytes32 destinationAddress,uint256 sourceNonce);
    event BridgeSuccess(address user,uint256 bridgeAmount);

    // User functions
    function bridgeToken(bytes32 destinationAddress,uint16 destinationChain) external payable whenNotPaused {
        destinationId storage data = destIdData[destinationChain];
        require(data.isActive,"Destination chain paused or Invalid");
        (bool success,) = pool.call{value: msg.value}("");
        require(success,"Error depositing token to Pool");
        nonce++;
        emit TokenDeposited(msg.sender, msg.value, destinationChain, destinationAddress,nonce);
    }

    // OnlyRelayer
    function processBridgeRequest(address user,uint256 bridgeAmount) external payable whenNotPaused onlyRelayer {
        IPool(pool).pullLiquidity(bridgeAmount);
        (bool success,) = user.call{value: bridgeAmount}("");
        require(success,"Error transfering token to user");
        emit BridgeSuccess(user, bridgeAmount);
    }

    // Internal Functions
    function _getEVMAddress(bytes32 targetAddress) internal pure returns (address) {
        require(bytes12(targetAddress) == 0, "EVM Address Invalid");
        return address(uint160(uint256(targetAddress)));
    }

    // onlyOwner
    function addDestinationChain(uint16 id, string memory _networkName, bool _isEVM, bool _isActive) public onlyOwner  {
        destinationId storage data = destIdData[id];
        data.networkName = _networkName;
        data.isEVM = _isEVM;
        data.isActive = _isActive;
    }

    function pauseDestinationChain(uint16 id) public onlyOwner {
        destinationId storage data = destIdData[id];
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
