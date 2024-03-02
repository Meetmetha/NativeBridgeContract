pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./SafeMath.sol";
import "./SafeCast.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Maintainer is Pausable, AccessControl, Ownable, SafeMath {
    // Variables & Structs
    uint8   public relayerThreshold; // 5 
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant VETO_ROLE = keccak256("VETO_ROLE");
    enum ProposalStatus {Inactive, Active, Passed, Executed, Cancelled}
    struct Proposal {
        ProposalStatus _status;
        uint8   yesParticipant;
        uint8 noParticipant;
        address sourceChainAddress;
        bytes32 destinationChainAddress;
        uint16 sourceChain;
        uint16 destinationChain;
        uint256 sourceChainNonce;
        uint40  proposedBlock;
    }
    mapping(bytes32 => address[]) public votersByProposal;
    mapping(bytes32 => Proposal) public proposals;

    constructor (uint8 _initialRelayerThreshold) {
        relayerThreshold = _initialRelayerThreshold;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Modifiers
    modifier onlyRelayers() {
        require(hasRole(RELAYER_ROLE, msg.sender), "sender doesn't have relayer role");
        _;
    }

    modifier onlyVeto() {
        require(hasRole(VETO_ROLE, msg.sender), "sender doesn't have veto role");
        _;
    }

    event RelayerThresholdChanged(uint256 newThreshold);
    event RelayerAdded(address relayer);
    event RelayerRemoved(address relayer);
    event ProposalCreated(
        bytes32 proposalHash,
        uint8 relayerThreshold,
        address sourceChainAddress,
        bytes32 destinationChainAddress,
        uint16 sourceChain,
        uint16 destinationChain,
        uint256 sourcechainNonce,
        ProposalStatus status
    );
    event ProposalExecuted(
        bytes32 proposalHash,
        uint8 relayerThreshold,
        address sourceChainAddress,
        bytes32 destinationChainAddress,
        uint16 sourceChain,
        uint16 destinationChain,
        uint256 sourcechainNonce,
        ProposalStatus status
    );
    event ProposalStatusChanged(
        bytes32 proposalHash,
        ProposalStatus status
    );
    event ProposalPausedByDisagreement(
        bytes32 proposalHash,
        ProposalStatus status
    );


    // View Functions
    function isRelayer(address relayer) external view returns (bool) {
        return hasRole(RELAYER_ROLE, relayer);
    }

    function hasVotedOnProposal(bytes32 proposalHash, address relayer) public view returns (bool) {
        address[] memory participants = votersByProposal[proposalHash];
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == relayer) {
                return true;
            }
        }
        return false;
    }

    function getProposalHash(address _sourceChainAddress, bytes32 _destinationAddress, uint16 _sourceChain, uint16 _destinationChain , uint256 _sourceNonce) public view returns(bytes32){
        return keccak256(abi.encodePacked(_sourceChainAddress, _destinationAddress,_sourceChain,_destinationChain,_sourceNonce));
    }
    
    // onlyVeto Functions
    function createProposal(address _sourceChainAddress, bytes32 _destinationChainAddress, uint16 _sourceChain, uint16 _destinationChain , uint256 _sourceChainNonce) external onlyVeto whenNotPaused {
        bytes32 proposalHash = keccak256(abi.encodePacked(_sourceChainAddress, _destinationChainAddress,_sourceChain,_destinationChain,_sourceChainNonce));
        Proposal memory proposalData = proposals[proposalHash];
        require(uint(proposalData._status) <= 1, "proposal already executed/cancelled");
        if (proposalData._status == ProposalStatus.Inactive) {
            proposalData = Proposal({
                _status : ProposalStatus.Active,
                yesParticipant : 0,
                noParticipant : 0,
                sourceChainAddress: _sourceChainAddress,
                destinationChainAddress: _destinationChainAddress,
                sourceChain: _sourceChain,
                destinationChain: _destinationChain,
                sourceChainNonce: _sourceChainNonce,
                proposedBlock : uint40(block.number)
            });
            emit ProposalCreated(proposalHash, relayerThreshold, _sourceChainAddress, _destinationChainAddress, _sourceChain, _destinationChain, _sourceChainNonce, ProposalStatus.Active);
        }
    }

    function cancelProposal(bytes32 proposalHash) public onlyVeto {
        Proposal memory proposalData = proposals[proposalHash];
        ProposalStatus currentStatus = proposalData._status;
        require(currentStatus == ProposalStatus.Active || currentStatus == ProposalStatus.Passed,"Proposal cannot be cancelled");
        proposalData._status = ProposalStatus.Cancelled;
        emit ProposalStatusChanged(proposalHash,proposalData._status);
    }

    // onlyRelayer
    function voteProposal(bytes32 proposalHash,bool IsVoteYes) external onlyRelayers whenNotPaused {
        Proposal memory proposalData = proposals[proposalHash];
        if (proposalData._status == ProposalStatus.Passed) {
            executeProposal(proposalHash);
            return;
        }
        require(uint(proposalData._status) <= 1, "proposal already executed/cancelled");
        require(!hasVotedOnProposal(proposalHash, msg.sender), "relayer already voted");
        if (proposalData._status != ProposalStatus.Cancelled) {
            if (IsVoteYes){
                proposalData.yesParticipant += 1;
            }else{
                proposalData.noParticipant += 1;
            }
            votersByProposal[proposalHash].push(msg.sender);
            if(proposalData.noParticipant >= relayerThreshold || proposalData.noParticipant > proposalData.yesParticipant){ //Check condition if its for or against threshhold
                proposalData._status = ProposalStatus.Cancelled;
                emit ProposalPausedByDisagreement(proposalHash,proposalData._status);
            } 
            if (proposalData.yesParticipant >= relayerThreshold) {
                proposalData._status = ProposalStatus.Passed;
                emit ProposalStatusChanged(proposalHash,proposalData._status);
            }
        }

        if (proposalData._status == ProposalStatus.Passed) {
            executeProposal(proposalHash);
        }
    }

    function executeProposal(bytes32 proposalHash) public onlyRelayers whenNotPaused {
        Proposal memory proposalData = proposals[proposalHash];
        require(uint(proposalData._status) <= 1, "proposal already executed/cancelled");
        require(proposalData.yesParticipant >= relayerThreshold,"relayerThreshold Error");
        require(proposalData._status == ProposalStatus.Passed, "Proposal must have Passed status");
        proposalData._status = ProposalStatus.Executed;
        emit ProposalExecuted(proposalHash, relayerThreshold, proposalData.sourceChainAddress, proposalData.destinationChainAddress, proposalData.sourceChain, proposalData.destinationChain, proposalData.sourceChainNonce, proposalData._status);
    }


    // onlyOwner functions
    function CancelProposalByOwner(bytes32 proposalHash) public onlyOwner {
        Proposal memory proposalData = proposals[proposalHash];
        ProposalStatus currentStatus = proposalData._status;
        require(currentStatus == ProposalStatus.Active || currentStatus == ProposalStatus.Passed,"Proposal cannot be cancelled");
        proposalData._status = ProposalStatus.Cancelled;
        emit ProposalStatusChanged(proposalHash,proposalData._status);
    }

    function ForceExecuteProposal(bytes32 proposalHash) public onlyOwner {
        Proposal memory proposalData = proposals[proposalHash];
        proposalData._status = ProposalStatus.Executed;
        emit ProposalExecuted(proposalHash, relayerThreshold, proposalData.sourceChainAddress, proposalData.destinationChainAddress, proposalData.sourceChain, proposalData.destinationChain, proposalData.sourcechainNonce);
    }

    function adminChangeRelayerThreshold(uint256 newThreshold) external onlyOwner {
        relayerThreshold = newThreshold.toUint8();
        emit RelayerThresholdChanged(newThreshold);
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

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
