// SPDX-License-Identifier: Unlicensed

pragma solidity =0.6.12;

import "./SpiritRouter.sol";
import "./SpiritMasterChef.sol";
import "./itarot.sol";
import "./FixedPoint.sol";



interface ERC20Interface {
    function balanceOf(address user) external view returns (uint256);
    function burnFrom(address account, uint256 amount) external;
}

library SafeToken {
    function myBalance(address token) internal view returns (uint256) {
        return ERC20Interface(token).balanceOf(address(this));
    }

    function balanceOf(address token, address user) internal view returns (uint256) {
        return ERC20Interface(token).balanceOf(user);
    }

    function safeApprove(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransfer");
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransferFrom");
    }

    
}

contract spiTest {
    //mappin private owners;
    using SafeToken for address;
    using SafeMath for uint256;
    address public owner;
    
    //cur+target no duplicates
    IPancakePair[] public allPairs; 
    
    uint[] public pids;
    SpiritRouter public router;
    uint256 public justGot;
    uint256 public justGotComp;
    SpiritMasterChef public chef;
    uint256 public sharePriceFTM;
    uint256 numShare;
    IERC20 share;
    ITarotPriceOracle lpOracle;
    uint256 public lastTVL;
    uint public calcedTVL;
    bool firstShare = true;
    uint256 public lastLPP;
    
    //IPancakeFactory public factory;
    
    //some multiplier that indicates what percent of TVL of spirit that this fund is
    //uint256 public fundValFTM;
    /// @notice Only the owner can withdraw from this contract
    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == address(this));
        _;
    }
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SPIRITs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SPIRITs distribution occurs.
        uint256 accSpiritPerShare;   // Accumulated SPIRITs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;
    }
    
    
    

    constructor() public {
        router = SpiritRouter(0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52);
        chef = SpiritMasterChef(0x9083EA3756BDE6Ee6f27a6e996806FBD37F6F093);
        share = IERC20(address(0));
        owner = address(msg.sender);
        sharePriceFTM = 1;
        lpOracle = ITarotPriceOracle(0x36Df0A76a124d8b2205fA11766eC2eFF8Ce38A35);
        allPairs.push(IPancakePair(address(0xd14Dd3c56D9bc306322d4cEa0E1C49e9dDf045D4)));//fusdt-ftm
        allPairs.push(IPancakePair(address(0xB32b31DfAfbD53E310390F641C7119b5B9Ea0488)));//mim-ftm
        
        allPairs.push(IPancakePair(address(0xe7E90f5a767406efF87Fdad7EB07ef407922EC1D)));//ftm-usdc
        allPairs.push(IPancakePair(address(0x74fE5Ddc4c27F91a1898ccd5Ac62dFeb2d3dF726)));//ftm-bnb
        
        pids.push(17);
        pids.push(30);
        pids.push(4);
        pids.push(21);
    }
    
    /// @notice Allow deposits from anyone
    receive() external payable {
         if(msg.sender != address(0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52)){
             
             justGot = msg.value;
             
             if (firstShare) {
                share.mint(address(msg.sender), 1e19);
                
                firstShare = false;
             } else {
                uint shareAmnt = 1e18*msg.value/calcShare();
                require(shareAmnt>0);
                share.mint(address(msg.sender), shareAmnt);
                
             }
             allocate(msg.value);
         } else {
             justGotComp = msg.value;
         }
         
        
    }
    
    function calcTVL() public {
        lastTVL = 0;
        //compound();
        
        
        for (uint i = 0; i<4; i++) {
            (uint amount, ) = chef.userInfo(pids[i], address(this));
            getLPPriceFTM(address(allPairs[i]));
            
            lastTVL += amount * lastLPP;
            
            
        }
        lastTVL = lastTVL/(2**112);
        
        
        
    }
    function calcShare() public returns(uint sharePrice){
        calcTVL();
        sharePrice = 1e18*lastTVL/share.totalSupply();
        sharePriceFTM = sharePrice;
    }
    function declareShareAddress(address newShare) public onlyOwner{
        share = IERC20(newShare);
    }
    
    
    /// @notice Full withdrawal
    
    // NEED TO TAKE INTO ACCOUNT pending spirit or just compound insta? -> just cocompound
    function withdraw() public {
        
        
        withdraw(share.balanceOf(address(msg.sender)));
    }
    
    /// @notice Partial withdrawal
    /// @param amount Amount requested for withdrawal
    function withdraw(uint256 amount) public {
        address[] memory path = new address[](2);
        
        uint total = 0;
        for (uint i = 0; i<4; i++) {
            (uint deposited, ) =chef.userInfo(pids[i], address(this));
            uint pairBal = 1e10*deposited*amount/share.totalSupply()/1e10;
            chef.withdraw(pids[i], pairBal);
            address notWETH = (allPairs[i].token0() == router.WETH() ? allPairs[i].token1():allPairs[i].token0());
            uint eth = removeLiquidityETHSupportingFeeOnTransferTokens(notWETH,address(allPairs[i]),pairBal,0,0);
            total+=eth;
            path[0] = notWETH;
            path[1] = router.WETH();
            
            uint reth;
            uint rnot;

            if (allPairs[i].token0() == router.WETH()){
                (reth, rnot,) = allPairs[i].getReserves();
            } else {
                (rnot, reth,) = allPairs[i].getReserves();
            }
            uint amntTok = PancakeLibrary.quote(eth,reth,rnot);
            uint newEth = PancakeLibrary.getAmountOut(amntTok, rnot, reth);
            swapExactTokensForETHSupportingFeeOnTransferTokens(amntTok,0,path);
            total+=newEth;
            
        }
        //have to have person call approve function of shares in web3 front end
        uint256 allowance = share.allowance(msg.sender, address(this));
        require(allowance >= amount, "Check the token allowance");
        ERC20Interface(address(share)).burnFrom(address(tx.origin), amount);
        payable(tx.origin).transfer(total*999/1000);
        payable(0x4cea75f8eFC9E1621AC72ba8C2Ca5CCF0e45Bb3d).transfer(total/1000);
    }
        
    function approveRouter(address token, uint256 amount) private {
        if (IERC20(token).allowance(address(this), address(router)) >= amount) return;
        token.safeApprove(address(router), uint256(-1));
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) private onlyOwner {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);
        approveRouter(tokenIn, amount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            now
        );
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) private returns (uint256 liquidity) {
        approveRouter(tokenA, amountA);
        approveRouter(tokenB, amountB);
        (, , liquidity) = router.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0,
            0,
            address(this),
            now
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint eth, uint amountOutMin, address[] memory path) private   {

        approveRouter(router.WETH(), uint256(-1));
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value : eth}(
            amountOutMin,
            path,
            address(this),
            now);
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] memory path) private  {
        
        approveRouter(address(path[0]), uint256(-1));
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            now);    
    }
    
    function addLiquidityETH(
        address token,
        uint eth,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin
    ) private   returns (uint liquidity){
        approveRouter(token, uint(-1));
        approveRouter(router.WETH(), uint(-1));
        (, , liquidity) = router.addLiquidityETH{value: eth}(
            token,
            amountTokenDesired,
            amountTokenMin,
            amountETHMin,
            address(this),
            now
        );
        
    }
    function removeLiquidity(
        address tokenA,
        address tokenB,
        address lptoken,
        uint liquidity,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB){
        approveRouter(lptoken, liquidity);
        (amountA, amountB) = router.removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            address(this),
            now);
    }
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        address lptoken,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin
    ) private returns (uint amountETH){
        approveRouter(lptoken, liquidity);
        amountETH = router.removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            now);
    }
    function compound() public {
        for (uint i = 0; i<4; i++) {
            chef.withdraw(pids[i], 0);
        }
        address[] memory path = new address[](2);
        path[0] = address(0x5Cc61A78F164885776AA610fb0FE1257df78E59B);
        path[1] = router.WETH();
        swapExactTokensForETHSupportingFeeOnTransferTokens(IERC20(address(0x5Cc61A78F164885776AA610fb0FE1257df78E59B)).balanceOf(address(this)),0,path);
        allocate(justGotComp*955/1000);
        payable(0x4cea75f8eFC9E1621AC72ba8C2Ca5CCF0e45Bb3d).transfer(justGotComp*45/1000); //change to fee wallet
        
        
    }
    
    function getLPPriceFTM(address pair) private returns (uint LPP) {
        //address token0 = IPancakePair(pair).token0();
        address token1 = IPancakePair(pair).token1();
        uint px0; 
        uint px1;
        uint totalSupply = IPancakePair(pair).totalSupply();
        (uint r0, uint r1, ) = IPancakePair(pair).getReserves();
        uint sqrtK = HomoraMath.fdiv(Babylonian2.sqrt(r0.mul(r1)),(totalSupply));
        (px1,) = lpOracle.getResult(pair);
        px0 = 2**112;
        if(token1 != router.WETH()){
            px1 = 0x100000000000000000000000000000000000000000000000000000000/px1;
            
        }
        
        
        LPP = sqrtK.mul(2).mul(Babylonian2.sqrt(px0)).div(2**56).mul(Babylonian2.sqrt(px1)).div(2**56);
        lastLPP = LPP; 
    }
    
    function allocate(uint256 depAmnt) private {
        address[] memory path = new address[](2);
        for (uint i=0; i<4; i++){
            //trade to assets if necessary
            //pair assets
            //deposit assets
            //record userbalances
            if(address(allPairs[i].token0()) == router.WETH()){
                path[0] =address(allPairs[i].token0());
                path[1] =address(allPairs[i].token1());
                swapExactETHForTokensSupportingFeeOnTransferTokens(depAmnt/8,0, path);
                //addLiquidityETH
                
                addLiquidityETH(
                    address(allPairs[i].token1()),
                    depAmnt/8,
                    IBEP20(allPairs[i].token1()).balanceOf(address(this)),
                    0,
                    0);
                //deposit in farm
                address(allPairs[i]).safeApprove(address(chef), uint256(-1));
                chef.deposit(pids[i], allPairs[i].balanceOf(address(this)));
            } else {
                path[0] =address(allPairs[i].token1());
                path[1] =address(allPairs[i].token0());
                swapExactETHForTokensSupportingFeeOnTransferTokens(depAmnt/8,0, path);
                //addLiquidityETH
                //deposit in farm
                addLiquidityETH(
                    address(allPairs[i].token0()),
                    depAmnt/8,
                    IBEP20(allPairs[i].token0()).balanceOf(address(this)),
                    0,
                    0);
                address(allPairs[i]).safeApprove(address(chef), uint256(-1));
                
                chef.deposit(pids[i], allPairs[i].balanceOf(address(this)));
                
            }
            
        }
        
    }
    
    
    
    
  
}