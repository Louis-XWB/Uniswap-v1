## Uniswap 系列汇总

[uniswap-v1](https://github.com/Louis-XWB/Uniswap-v1/)

[uniswap-v2-core](https://github.com/Louis-XWB/uniswap-v2-core)

[uniswap-v2-periphery](https://github.com/Louis-XWB/uniswap-v2-periphery)

[uniswap-v3-core](https://github.com/Louis-XWB/uniswap-v3-core)

[uniswap-v3-periphery](https://github.com/Louis-XWB/uniswap-v3-periphery)

# Uniswap-v1 源码学习

## Intro

Uniswap V1 是该协议的第一个版本，于 2018 年 11 月推出，设计上相对简单，提供了一个在以太坊上轻松交换 ERC20 代币的系统。通过减少不必要的手续费，避开中心化中间商的控制，它可以实现更快、更有效的代币交换。

### 主要功能
* 通过 Uniswap Factory 可以添加任意 ERC20 代币的交易对
* 加入流动性池实现交易和流动的储备金
* 使用恒定乘积公式对交易自动定价,实现自动做市
* 支持将 ETH 直接交换为任意 ERC20 代币
* 支持任意 ERC20 之间的转换 (通过 ETH 的间接交换)

### 如何运作
1) **ETH-ERC20 交换合约**

    Uniswap 由一系列 ETH-ERC20 交换合约组成，每个 ERC20 代币有且只有一份交换合约。
    
    Uniswap Factory 相当于公共注册表，任何人都可以使用 Uniswap Factory 创建 ETH-ERC20 交换合约，也可以通过它来查找已经添加到系统中的 ERC20 代币和交易地址。

2) **代币储备**

    每个 ETH-ERC20 合约都持有 ETH 及其相关 ERC20 代币的储备。
    
    任何人都可以为 ETH-ERC20 交易合约提供流动性，也就是注入代币储备。
    
    与直接买卖不同，它需要存入等值的 ETH 和相关的 ERC20 代币。当流动性存入系统时，池代币就会被铸造，并且可以随时销毁以提取一定比例的储备金。

3) **自动做市**

    ETH-ERC20 交易合约就是 ETH-ERC20 交易对的自动做市商。
    
    交易者可以通过增加其中一个的流动性储备并从另一个的储备中提取来在两者之间进行双向互换。
    
    由于 ETH 是所有 ERC20 交易对的通用代币，因此它可以用作中介，允许在单笔交易中直接进行 ERC20-ERC20 交易。

4) **自动做市公式：恒定乘积**

    Uniswap 使用“恒定乘积”公式来实现自动做市，根据 ETH 和 ERC20 储备的相对规模以及传入交易改变该比率的金额来设定汇率。

    恒定乘积公式是这样的： `x * y = k`，其中 `x` 和 `y` 是交易池中两种资产的数量，而 `k` 是一个恒定值，即这两种资产的乘积是一个固定的值。

    当第一个人添加 `x` 个 ETH 和 `y` 个 ERC20 的作为流动性时，决定了 `k` 值的初始大小。

    这意味着，如果后面某个人要在 Uniswap 上购买某种资产，他们所支付的另一种资产的数量会导致池中的资产数量发生变化，但这两种资产的乘积仍然保持不变。

    **举例：**
    
    * 你将 1 ETH 放入交易池中，所以池中的 ETH 数量增加
    * 池中的 ETH 数量变为 `x + 1`
    * 为了保持乘积不变，新的 ERC20 数量（设为 `y'`）应该满足` (x + 1) * y' = k`
    * 从这个公式中，我们可以解出 `y'`。然后，你获得的 ERC20 的数量就是 `y - y'`
    * 其他，由于购买行为使得池中 ERC20 的数量减少，根据供求关系，ERC20 的价格相对于 ETH 会上升。换句话说，你需要付出更多的ETH才能获得同样数量的 ERC20。
    * 反之亦然。

    
    出售 ETH 换取 ERC20 代币会增加 ETH 储备规模，同时会减少 ERC20 储备规模。这改变了准备金率（两种资产在池中的比率），从而提高了后续交易中 ERC20 代币相对于 ETH 的价格。相对于储备总规模的交易规模越大，价格滑点（实际交易价格与预期价格之间的差异）就会越大。
    
    本质上，交易合约利用金融市场的供需关系来自动决定每种资产的价格。

5) **激励流动性提供者**

    每笔交易都会收取0.30%的费用，这些费用直接加入到交易池的储备金中。因此，即使交易池中的ETH和ERC20代币的比率持续变化，总的储备金量还是会随着每次交易而增加。这些额外的储备金可以被视为对流动性提供者的奖励。

    当流动性提供者想要退出并取回他们的资金时，他们可以销毁他们的池代币，并按比例提取储备金，这时他们也会获得这部分奖励。


## Code Learning

### [uniswap_exchange.vy](https://github.com/Louis-XWB/Uniswap-v1/blob/learn_v/contracts/uniswap_exchange.vy)

* [addLiquidity](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L70)

* [removeLiquidity](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L142)

* [getInputPrice](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L194)

* [getOutputPrice](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L215)

* [ethToTokenInput](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L223)

* [ethToTokenOutput](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L262C5-L262C21)

* [tokenToEthInput](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L301)

* [tokenToEthOutput](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L333C5-L333C21)

* [tokenToTokenInput](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L367)

* [tokenToTokenOutput](https://github.com/Louis-XWB/Uniswap-v1/blob/1b7be3470830b30881076a6f0dacad0718863935/contracts/uniswap_exchange.vy#L402)


### [uniswap_factory.vy](https://github.com/Louis-XWB/Uniswap-v1/blob/learn_v/contracts/uniswap_factory.vy)

* [createExchange](https://github.com/Louis-XWB/Uniswap-v1/blob/ed757a3fdeee7178155e98c672437879123cf001/contracts/uniswap_factory.vy#L22)


## FAQ
1) Uniswap 的前端展示创建的 Token 信息是从哪里获取的？
  
    代币信息（包括名称、符号、小数点等）直接从代币合约中提取。图标是从 TrustWallet 中提取的，所以如果想更新代币图标，可以向 TrustWallet 的github repo https://github.com/trustwallet/assets 提交PR。



## Resources

Uniswap-v1 doc: [v1/overview](https://docs.uniswap.org/contracts/v1/overview)

Uniswap-v1 Whitepaper: [hackmd.io](https://hackmd.io/@HaydenAdams/HJ9jLsfTz?type=view)



