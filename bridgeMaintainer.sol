pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract bridgeMaintainer is Pausable, AccessControl, Ownable {
    // Variables & Structs
    uint8 public quorumThreshold;
    address public maintainer;
    uint256 public processedRequests;
    struct destinationId {
        bool isActive;
    }
    mapping(address => bool) public WhitelistedStampers;
    mapping(uint16 => destinationId) public chainID;
    mapping(bytes32 => bool) public hashedBridgeRequests;

    constructor (uint8 _quorumThreshold, address _maintainer) Ownable(msg.sender) {
        quorumThreshold = _quorumThreshold;
        maintainer = _maintainer;
    }

    // Modifiers
    modifier onlyMaintainer() {
        require(msg.sender == maintainer, "Caller is not Maintainer");
        _;
    }

    // Events
    event QuorumThresholdChanged(uint8 newThreshold);
    event maintainerUpdated(address newMaintainer);
    event StamperAdded(address stamper);
    event StamperRemoved(address stamper);
    event ExecuteBridgeRequest(address from,address addressTo,uint256 inputAmount,uint256 outputAmount,uint16 sourceChain,uint16 destinationChain,bytes32 hash);

    // View Functions
    function isWhitelistedStamper(address stamper) external view returns (bool) {
        return WhitelistedStampers[stamper];
    }

    function isBridgeHashExecuted(bytes32 hash) external view returns (bool) {
        return hashedBridgeRequests[hash];
    }

    function VerifyMessageSignature(bytes32 _hashedMessage, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        address signer = ecrecover(_hashedMessage, _v, _r, _s);
        return signer;
    }

    function verifyMessageByStampers(bytes32 _hashedMessage, address[] memory stamperIds, uint8[] memory _v, bytes32[] memory _r, bytes32[] memory _s) internal view {
        require(stamperIds.length == _v.length && _v.length == _r.length && _v.length == _s.length, "Invalid input lengths");
        require(stamperIds.length >= quorumThreshold,"Signature does not meet threshold requirement");
        for(uint8 i=0;i<stamperIds.length;i++){
            address signer = VerifyMessageSignature(_hashedMessage,_v[i],_r[i],_s[i]);
            require(stamperIds[i] == signer,"Stamper signature mismatch");
        }
    }

    // onlyMaintainer
    function processBridgeRequest(address from,address addressTo, uint256 inputAmount, uint256 outputAmount, uint16 sourceChain, uint16 destinationChain, uint256 timestamp, uint256 depositNonce, bytes32 hash,
        bytes32 signedMessageHash, 
        address[] memory stamperIds, 
        uint8[] memory _v,
        bytes32[] memory _r,
        bytes32[] memory _s) external whenNotPaused onlyMaintainer {
        require(!hashedBridgeRequests[hash],"Bridge request already processed");
        //bytes32 derivedHash = keccak256(abi.encodePacked(from, addressTo, inputAmount, destinationChain, timestamp, depositNonce));
        //require(derivedHash == hash,"Hash doesn't Match");
        // Check for stampers
        verifyMessageByStampers(signedMessageHash,stamperIds,_v,_r,_s);
        hashedBridgeRequests[hash]=true;
        processedRequests++;
        emit ExecuteBridgeRequest(from,addressTo,inputAmount,outputAmount,sourceChain,destinationChain,hash);
    }

    // onlyOwner functions
    function updateMaintainer(address _newMaintainer) external onlyOwner {
        maintainer = _newMaintainer;
        emit maintainerUpdated(maintainer);
    }

    function adminChangeQuorumThreshold(uint8 newThreshold) external onlyOwner {
        quorumThreshold = newThreshold;
        emit QuorumThresholdChanged(newThreshold);
    }

    function addDestinationChain(uint16 id, bool _isActive) public onlyOwner  {
        destinationId storage data = chainID[id];
        data.isActive = _isActive;
    }

    function pauseDestinationChain(uint16 id) public onlyOwner {
        destinationId storage data = chainID[id];
        data.isActive = false;
    }

    function addWhitelistedStamper(address _address) external onlyOwner {
        WhitelistedStampers[_address] = true;
    }

    function removeWhitelistedStamper(address _address) external onlyOwner {
        WhitelistedStampers[_address] = false;
    }

    function pause() public onlyOwner{
        _pause();
    }

    function unpause() public onlyOwner{
        _unpause();
    }

    function emergencyRescue() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    function recoverUnsupportedTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(owner(), token.balanceOf(address(this)));
    }
}
