// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract liquidityPool is ERC20, Ownable, ReentrancyGuard, Pausable {
    address public router;
    constructor(address _router)
        ERC20("PooledETH", "pETH")
        Ownable(msg.sender)
    {
        router = _router;
    }
    
    // Modifiers
    modifier onlyRouter(){
        require(msg.sender == router);
        _;
    }

    // User Functions
    function addToPool(uint256 mintAmount) public payable nonReentrant whenNotPaused {
        require(msg.value >= mintAmount,"Value is less that mintAmount");
        _mint(msg.sender, mintAmount);
    }

    function removeFromPool(uint256 burnAmount) public payable nonReentrant whenNotPaused{
        require(address(this).balance >= burnAmount,"Pool doesn't have enough Tokens");
        _burn(msg.sender, burnAmount);
        (bool success,) = msg.sender.call{value: burnAmount}("");
        require(success,"Transfer failed!"); 
    }

    // onlyRouter functions
    function pullLiquidity(uint256 transferAmount) public payable whenNotPaused nonReentrant onlyRouter {
        require(address(this).balance >= transferAmount,"Pool doesn't have enough Tokens");
        (bool success,) = router.call{value: transferAmount}("");
        require(success,"Transfer failed!");
    }

    // onlyOwner functions
    function updateRouter(address _router) public onlyOwner {
        router = _router;
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

    receive() external payable {}
}
