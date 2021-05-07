// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IERC20.sol";

contract Leveraged {
    
    IERC20 usdt = IERC20(0x101848D5C5bBca18E6b4431eEdF6B95E9ADF82FA); // WEENUS token xDDD
    IERC20 weth = IERC20(0xc778417E063141139Fce010982780140Aa0cD5Ab); // testnet weth
    IUniswapV2Pair ethusdt = IUniswapV2Pair(0x38dd09910C00B5F96ed935f57289771923b1C1e5); // WEENUS / ETH pair 
    IUniswapV2Router02 uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // Uniswap router (testnet and mainnet)
    
    address public ceo;
    uint public totalShares = 0;
    mapping(address => uint) public shares;
    mapping(address => uint) public depositedFee;
    mapping(address => uint) public depositedUsdt;
    mapping(address => uint) public buyPrice;
    mapping(address => uint) public buyAmount;
    mapping(address => uint64) public buyTime;
    mapping(address => uint8) public buyLeverage;
    
    function getTotalUsdt() view private returns(uint256) {
        return usdt.balanceOf(address(this));
    }
    
    function getEtherPrice() view private returns(uint256) {
        // This is the "insecure" version - but for my purpouse I don't care - there is only a 0.01 ETH bounty per trade - Not enough to spend a ton of money to attempt to claim those fees
        (uint res0, uint res1,) = ethusdt.getReserves();
        res0 *= 10 ** uint(usdt.decimals());
        return res0 / res1;
    }
    
    function addToBank(uint usdtAmount) public {
        require(usdt.transferFrom(msg.sender, address(this), usdtAmount), "Leveraged: transferFrom failed");
        
        if (totalShares == 0) {
            shares[msg.sender] = usdtAmount;
            totalShares = usdtAmount;
        } else {
            shares[msg.sender] = usdtAmount * totalShares / getTotalUsdt();
            totalShares += shares[msg.sender];
        }
    }
    
    function withdrawFromBank() public {
        require(shares[msg.sender] > 0, "Leveraged: no shares");
        usdt.transfer(msg.sender, shares[msg.sender] / totalShares * getTotalUsdt());
    }
    
    function openBuy(uint leverage, uint usdtAmount, uint ethPrice) public payable {
        require(leverage <= 5 && leverage >= 2);
        require(msg.value >= 0.01 ether);
        require(usdt.transferFrom(msg.sender, address(this), usdtAmount), "Leveraged: transferFrom failed");
        require(usdt.approve(address(uniswap), usdtAmount * leverage), "Leveraged: approve failed");
        
        uint preBalance = address(this).balance;
        
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = uniswap.WETH();
        
        uniswap.swapExactTokensForETH(usdtAmount * leverage, usdtAmount * leverage / ethPrice, path, address(this), block.timestamp);
        
        buyAmount[msg.sender] = address(this).balance - preBalance;
        buyPrice[msg.sender] = ethPrice;
        buyTime[msg.sender] = uint64(block.timestamp);
    }
    
    function closePosition(uint ethPrice) public {
        require(buyAmount[msg.sender] >= 0);
        
        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = address(usdt);
        
        uint usdtTotal = buyAmount[msg.sender] / ethPrice / buyLeverage[msg.sender] / 985 * 1000;
        uniswap.swapExactETHForTokens(buyAmount[msg.sender] / 995 * 100, path, address(this), block.timestamp);
        
        require(usdt.approve(msg.sender, usdtTotal), "Leveraged: approve failed");
        msg.sender.transfer(0.01 ether);
        
        buyPrice[msg.sender] = 0;
        buyAmount[msg.sender] = 0;
        buyLeverage[msg.sender] = 0;
    }
    
    function liquidate(address trader) public {
        require(buyAmount[trader] >= 0);
        uint etherPrice = getEtherPrice();
        require(etherPrice - etherPrice / buyLeverage[trader] < getEtherPrice());
        
        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = address(usdt);
        
        uint usdtTotal = buyAmount[trader] / etherPrice / buyLeverage[trader] / 985 * 1000;
        uniswap.swapExactETHForTokens(buyAmount[msg.sender] / 995 * 100, path, address(this), block.timestamp);
    }
}
