# @title Uniswap Exchange Interface V1
# @notice Source code found at https://github.com/uniswap
# @notice Use at your own risk

# Uniswap Factory 合约
contract Factory():
    # 获取交易对地址
    def getExchange(token_addr: address) -> address: constant

# 交易对合约
contract Exchange():
    # 获取从ETH到ERC20的输出价格
    def getEthToTokenOutputPrice(tokens_bought: uint256) -> uint256(wei): constant
    # 转换ETH->ERC20，并转给指定地址（指定最小转换token数量）
    def ethToTokenTransferInput(min_tokens: uint256, deadline: timestamp, recipient: address) -> uint256: modifying
    # 转换ETH->ERC20，并转给指定地址（指定购买的token数量）
    def ethToTokenTransferOutput(tokens_bought: uint256, deadline: timestamp, recipient: address) -> uint256(wei): modifying

# 定义 ETH 转换成 ERC20 Token事件
TokenPurchase: event({buyer: indexed(address), eth_sold: indexed(uint256(wei)), tokens_bought: indexed(uint256)})

# 定义 ERC20 转换成 ETH Token事件
EthPurchase: event({buyer: indexed(address), tokens_sold: indexed(uint256), eth_bought: indexed(uint256(wei))})

# 添加流动性事件
AddLiquidity: event({provider: indexed(address), eth_amount: indexed(uint256(wei)), token_amount: indexed(uint256)})

# 移除流动性事件
RemoveLiquidity: event({provider: indexed(address), eth_amount: indexed(uint256(wei)), token_amount: indexed(uint256)})

# 转账到指定地址事件
Transfer: event({_from: indexed(address), _to: indexed(address), _value: uint256})

# 授权事件
Approval: event({_owner: indexed(address), _spender: indexed(address), _value: uint256})


name: public(bytes32)                             # 合约名称
symbol: public(bytes32)                           # 合约符号
decimals: public(uint256)                         # 18: 代币小数点后位数
totalSupply: public(uint256)                      # 总供Token应量
balances: uint256[address]                        # 地址TOoken余额
allowances: (uint256[address])[address]           # 某个地址授权另一地址转移的Token数量
token: address(ERC20)                             # 此合约交易的ERC20代币的地址
factory: Factory                                  # 创建此合约的工厂的接口

# @dev This function acts as a contract constructor which is not currently supported in contracts deployed
#      using create_with_code_of(). It is called once by the factory during contract creation.
@public
def setup(token_addr: address):
    # 确保工厂和代币地址未被设置，且传入的代币地址非零地址
    assert (self.factory == ZERO_ADDRESS and self.token == ZERO_ADDRESS) and token_addr != ZERO_ADDRESS
    self.factory = msg.sender
    self.token = token_addr
    self.name = 0x556e697377617020563100000000000000000000000000000000000000000000
    self.symbol = 0x554e492d56310000000000000000000000000000000000000000000000000000
    self.decimals = 18

# 提供流动性方法
# 添加流动性的操作分为两种情况：
# 1. **首次添加流动性**：
#    - 在池子首次添加流动性时，兑换合约将铸造等同于合约ETH余额的流动性代币，并将其发给流动性提供者。
#    - 首次添加时，合约不限制代币的添加数量。这意味着第一位流动性提供者拥有对该代币的初始定价权，但后续的价格变动将不受其控制。

# 2. **后续添加流动性**：
#    - 在常规的流动性添加中，兑换合约会根据流动性提供者提交的ETH，等比例收取代币。
#    - 根据提供者添加的ETH占总量的比例，合约将铸造并发放相应的流动性代币。
@public
@payable
def addLiquidity(min_liquidity: uint256, max_tokens: uint256, deadline: timestamp) -> uint256:
    # 确保操作在截止时间之前，且最大token数量和发送的ETH数量都大于0
    assert deadline > block.timestamp and (max_tokens > 0 and msg.value > 0)
    total_liquidity: uint256 = self.totalSupply

    # 当已有流动性时，非该池子第一次添加流动性
    if total_liquidity > 0:
        # 添加的流动性最小也要大于0
        assert min_liquidity > 0

        # 计算ETH和Token的储备量
        eth_reserve: uint256(wei) = self.balance - msg.value
        token_reserve: uint256 = self.token.balanceOf(self)

        # 计算需要添加的token数量和流动性数量
        # 最后+1是手动向上取整，防止默认的向下取整减少流动性池应收的代币数量，进而逐渐稀释份额
        token_amount: uint256 = msg.value * token_reserve / eth_reserve + 1
        liquidity_minted: uint256 = msg.value * total_liquidity / eth_reserve

        # 确保token数量小于等于最大token数量，且mint的流动性大于最小流动性
        assert max_tokens >= token_amount and liquidity_minted >= min_liquidity

        # 更新当前用户的流动性余额
        self.balances[msg.sender] += liquidity_minted
        # 更新总流动性供应量
        self.totalSupply = total_liquidity + liquidity_minted

        # 从msg.sender转移token到本合约
        assert self.token.transferFrom(msg.sender, self, token_amount)

        # 触发添加流动性和转账事件
        log.AddLiquidity(msg.sender, msg.value, token_amount)
        log.Transfer(ZERO_ADDRESS, msg.sender, liquidity_minted)

        # 返回添加的流动性数量
        return liquidity_minted
    else: # 当没有流动性时
        # 确保factory 和 代币地址已设置，且发送的 ETH 数量大于 0.000001 ETH
        assert (self.factory != ZERO_ADDRESS and self.token != ZERO_ADDRESS) and msg.value >= 1000000000

        # 获取添加流动性 token 交易合约地址
        assert self.factory.getExchange(self.token) == self
        
        # 最大token数量为传入的token数量
        # 直接将用户的代币全部投入池子
        token_amount: uint256 = max_tokens

        # 计算流动性数量
        initial_liquidity: uint256 = as_unitless_number(self.balance)

        # 更新总流动性供应量
        self.totalSupply = initial_liquidity

        # 更新当前用户的流动性余额
        self.balances[msg.sender] = initial_liquidity

        # 从msg.sender转移token到本合约
        assert self.token.transferFrom(msg.sender, self, token_amount)

        # 触发添加流动性和转账事件
        log.AddLiquidity(msg.sender, msg.value, token_amount)
        log.Transfer(ZERO_ADDRESS, msg.sender, initial_liquidity)

        # 返回添加的流动性数量
        return initial_liquidity

# **移除流动性**：

# - 移除流动性的步骤直接且简洁。首先进行等比例的计算。
# - 计算完毕后，向移除者转账相应的金额或代币。
# - 同时，销毁相应数量的流动性代币。
@public
def removeLiquidity(amount: uint256, min_eth: uint256(wei), min_tokens: uint256, deadline: timestamp) -> (uint256(wei), uint256):
    # 确保移除的流动性数量大于0，且ETH和token的最小数量都大于0
    assert (amount > 0 and deadline > block.timestamp) and (min_eth > 0 and min_tokens > 0)

    # 计算流动性储备
    total_liquidity: uint256 = self.totalSupply
    assert total_liquidity > 0

    # 计算token的储备
    token_reserve: uint256 = self.token.balanceOf(self)

    # 计算移除流动性影响的ETH数量，交易所不亏损所以不向上取整
    eth_amount: uint256(wei) = amount * self.balance / total_liquidity
    # 计算移除流动性影响的token数量
    token_amount: uint256 = amount * token_reserve / total_liquidity

    # 确保移除的ETH和token数量大于最小数量
    assert eth_amount >= min_eth and token_amount >= min_tokens

    # 更新当前用户的流动性余额
    self.balances[msg.sender] -= amount
    # 更新总流动性余额
    self.totalSupply = total_liquidity - amount

    #向移除者发送ETH
    send(msg.sender, eth_amount)

    #向移除者发送代币
    assert self.token.transfer(msg.sender, token_amount)
    log.RemoveLiquidity(msg.sender, eth_amount, token_amount)
    log.Transfer(msg.sender, ZERO_ADDRESS, amount)

    # 返回移除的ETH和token数量
    return eth_amount, token_amount

# 用于计算最终所兑换出来的币（ETH或代币）的数量，
# 输入为两个币的储备量和用于兑换的币的数量，输出为能够兑换出来的币的数量。
#
# 计算过程：
# Uniswap使用的是恒定做市商，即xy=k，(x+x')(y-y')=k。
# 这里x=input_reserve，x'=input_amount，y=output_reserve
# 此函数计算方式为：(input_reserve+input_amount)(output_reserve-output_amount)=k -> 求output_amount
# (input_reserve+input_amount)(output_reserve-output_amount) = input_reserve*output_reserve
# input_reserve*output_reserve + input_amount*output_reserve - input_reserve*output_amount - input_amount*output_amount = input_reserve*output_reserve
# input_amount*output_reserve - input_reserve*output_amount - input_amount*output_amount = 0
# input_amount*output_reserve - input_amount*output_amount = input_reserve*output_amount
# input_amount*output_reserve = input_amount*output_amount + input_reserve*output_amount
# input_amount*output_reserve = output_amount*(input_amount + input_reserve)
# output_amount = input_amount*output_reserve / (input_amount + input_reserve)
# 返回值即是 output_amount
@private
@constant
def getInputPrice(input_amount: uint256, input_reserve: uint256, output_reserve: uint256) -> uint256:
    # 确定 ETH 和 Token 的储备量都大于0
    assert input_reserve > 0 and output_reserve > 0

    # 计算扣除0.3%手续费后剩余的数量
    input_amount_with_fee: uint256 = input_amount * 997

    # 计算输出数量output_amount
    numerator: uint256 = input_amount_with_fee * output_reserve
    denominator: uint256 = (input_reserve * 1000) + input_amount_with_fee
    return numerator / denominator

# 与getInputPrice函数一样，指定output_amount，返回input_amount，计算的过程中需要收取0.3%手续费
# 
# +1 加了个1，这是因为uint256的除法会产生浮点数，向下取整后小数会被舍去，因此兑换者实际需要支付的代币数量会比理论上少一点。
# 为了避免每次交易后交易所产生亏损（会导致流动性池内资金越来越少），因此在最后的计算结果手动加1向上取整，
# 不过因为结算单位是wei，所以向上取整给用户带来的损失可以忽略不计。
#
# 返回值即是 input_amount
@private
@constant
def getOutputPrice(output_amount: uint256, input_reserve: uint256, output_reserve: uint256) -> uint256:
    assert input_reserve > 0 and output_reserve > 0
    numerator: uint256 = input_reserve * output_amount * 1000
    denominator: uint256 = (output_reserve - output_amount) * 997
    return numerator / denominator + 1

# 根据输入的ETH计算可以交易到的Token数量
@private
def ethToTokenInput(eth_sold: uint256(wei), min_tokens: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and (eth_sold > 0 and min_tokens > 0)

    # 计算token的储备量
    token_reserve: uint256 = self.token.balanceOf(self)

    # 计算可以交易到的token数量
    tokens_bought: uint256 = self.getInputPrice(as_unitless_number(eth_sold), as_unitless_number(self.balance - eth_sold), token_reserve)
    
    # eth_sold: 售卖eth_sold的数量，返回值是用户应该获得的token数量
    # (self.balance - eth_sold):交易是先转账再执行合约，所以获得ETH储备量的时候需要先减去该买者已经发送的ETH数量.
    assert tokens_bought >= min_tokens

    # 向用户发送token，完成兑换
    assert self.token.transfer(recipient, tokens_bought)
    log.TokenPurchase(buyer, eth_sold, tokens_bought)
    return tokens_bought

# 用ETH兑换代币的默认函数，用户只需要指定输入的ETH的数量
@public
@payable
def __default__():
    self.ethToTokenInput(msg.value, 1, block.timestamp, msg.sender, msg.sender)

# 将ETH兑换成目标代币，通过msg.value指定输入的ETH数量
@public
@payable
def ethToTokenSwapInput(min_tokens: uint256, deadline: timestamp) -> uint256:
    return self.ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, msg.sender)

# 将ETH兑换成目标代币，指定接收地址
@public
@payable
def ethToTokenTransferInput(min_tokens: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, recipient)

# 根据目标token数量把给定的ETH转换成Token
@private
def ethToTokenOutput(tokens_bought: uint256, max_eth: uint256(wei), deadline: timestamp, buyer: address, recipient: address) -> uint256(wei):
    assert deadline >= block.timestamp and (tokens_bought > 0 and max_eth > 0)

    # 计算token的储备量
    token_reserve: uint256 = self.token.balanceOf(self)

    # 用getOutputPrice获得所需支付的ETH数量
    # 因为交易是先转账再执行合约代码，所以调用该合约时ETH已经转到兑换合约中，
    # 而入口函数会直接将msg.value作为max_eth传入，所以ETH储备量为self.balance-max_eth
    eth_sold: uint256 = self.getOutputPrice(tokens_bought, as_unitless_number(self.balance - max_eth), token_reserve)
    # Throws if eth_sold > max_eth
    # 计算需要退还给用户的ETH数量
    eth_refund: uint256(wei) = max_eth - as_wei_value(eth_sold, 'wei')

    # 如果需要退还给用户的ETH数量大于0，则转账ETH给用户
    if eth_refund > 0:
        send(buyer, eth_refund)
    
    # 向用户发送token，完成兑换
    assert self.token.transfer(recipient, tokens_bought)
    log.TokenPurchase(buyer, as_wei_value(eth_sold, 'wei'), tokens_bought)
    return as_wei_value(eth_sold, 'wei')

# 指定输出的token数量，把msg.value指定为最大的ETH数量，兑换成token
@public
@payable
def ethToTokenSwapOutput(tokens_bought: uint256, deadline: timestamp) -> uint256(wei):
    return self.ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, msg.sender)

# 指定输出的token数量，把msg.value指定为最大的ETH数量，兑换成token，并转给指定地址
@public
@payable
def ethToTokenTransferOutput(tokens_bought: uint256, deadline: timestamp, recipient: address) -> uint256(wei):
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, recipient)

# 类似ETH->Token的兑换，只是这里是Token->ETH
# 根据要卖出的Token数量计算可以得到的ETH数量，完成兑换
@private
def tokenToEthInput(tokens_sold: uint256, min_eth: uint256(wei), deadline: timestamp, buyer: address, recipient: address) -> uint256(wei):
    assert deadline >= block.timestamp and (tokens_sold > 0 and min_eth > 0)
    # 计算token的储备量
    token_reserve: uint256 = self.token.balanceOf(self)

    # 计算可以交易到的ETH数量
    eth_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, as_unitless_number(self.balance))
    # 将单位转换成we
    wei_bought: uint256(wei) = as_wei_value(eth_bought, 'wei')
    # 确保可以交易到的ETH数量大于最小数量
    assert wei_bought >= min_eth
    # 向用户发送ETH，完成兑换
    send(recipient, wei_bought)
    # 将卖出的Token从用户转移到本合约
    assert self.token.transferFrom(buyer, self, tokens_sold)
    log.EthPurchase(buyer, tokens_sold, wei_bought)
    return wei_bought


# 指定输入的代币数量，根据代币数量兑换ETH并发送给消息调用者
@public
def tokenToEthSwapInput(tokens_sold: uint256, min_eth: uint256(wei), deadline: timestamp) -> uint256(wei):
    return self.tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, msg.sender)

# 指定输入的代币数量和指定地址，根据代币数量兑换ETH并发送给指定地址
@public
def tokenToEthTransferInput(tokens_sold: uint256, min_eth: uint256(wei), deadline: timestamp, recipient: address) -> uint256(wei):
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, recipient)

# 指定所想要兑换到的ETH数量并将ETH发送给消息调用者，函数根据要兑换的ETH计算扣除代币
@private
def tokenToEthOutput(eth_bought: uint256(wei), max_tokens: uint256, deadline: timestamp, buyer: address, recipient: address) -> uint256:
    assert deadline >= block.timestamp and eth_bought > 0

    # 计算token的储备量
    token_reserve: uint256 = self.token.balanceOf(self)

    # 计算想要兑换到的ETH数量所要支付的token数量
    tokens_sold: uint256 = self.getOutputPrice(as_unitless_number(eth_bought), token_reserve, as_unitless_number(self.balance))
    # tokens sold is always > 0
    # 确保支付的token数量小于最大数量
    assert max_tokens >= tokens_sold

    # 向用户发送ETH，完成兑换
    send(recipient, eth_bought)
    # 将兑换的Token从用户转移到本合约
    assert self.token.transferFrom(buyer, self, tokens_sold)
    log.EthPurchase(buyer, tokens_sold, eth_bought)
    return tokens_sold

# 指定所想要兑换到的ETH数量并将ETH发送给消息调用者，函数根据要兑换的ETH计算扣除代币
@public
def tokenToEthSwapOutput(eth_bought: uint256(wei), max_tokens: uint256, deadline: timestamp) -> uint256:
    return self.tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, msg.sender)

# 指定所想要兑换到的ETH数量并将ETH发送给指定地址，函数根据要兑换的ETH计算扣除代币
@public
def tokenToEthTransferOutput(eth_bought: uint256(wei), max_tokens: uint256, deadline: timestamp, recipient: address) -> uint256:
    assert recipient != self and recipient != ZERO_ADDRESS
    return self.tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, recipient)

# 实现ERC20 -> ERC20的兑换
# 在将支付代币兑换成ETH后，就将ETH发送到目标代币的兑换合约地址，
# 并调用其ethToTokenTransferInput函数来将ETH兑换成目标代币。
@private
def tokenToTokenInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, buyer: address, recipient: address, exchange_addr: address) -> uint256:
    assert (deadline >= block.timestamp and tokens_sold > 0) and (min_tokens_bought > 0 and min_eth_bought > 0)
    # 确保交易对地址不是本合约地址和零地址
    assert exchange_addr != self and exchange_addr != ZERO_ADDRESS

    # 计算token的储备量
    token_reserve: uint256 = self.token.balanceOf(self)
    # 计算可以交易到的ETH数量
    eth_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, as_unitless_number(self.balance))
    wei_bought: uint256(wei) = as_wei_value(eth_bought, 'wei')
    assert wei_bought >= min_eth_bought

    # 把用户要对话的Token转移到本合约
    assert self.token.transferFrom(buyer, self, tokens_sold)

    # 向目标交易对合约地址发送ETH，并调用其ethToTokenTransferInput函数
    # 把ETH兑换成目标代币，并转给指定地址，完成兑换
    tokens_bought: uint256 = Exchange(exchange_addr).ethToTokenTransferInput(min_tokens_bought, deadline, recipient, value=wei_bought)
    log.EthPurchase(buyer, tokens_sold, wei_bought)
    return tokens_bought

# 根据指定的token 地址，将本合约的token兑换成token_addr的token
@public
def tokenToTokenSwapInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr)

# 根据指定的token 地址，将本合约的token兑换成token_addr的token，并转给指定地址
@public
def tokenToTokenTransferInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, recipient: address, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, recipient, exchange_addr)

# 根据指定的token 地址和指定购买的目标token数量，将本合约的token兑换成token_addr的token
@private
def tokenToTokenOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, buyer: address, recipient: address, exchange_addr: address) -> uint256:
    assert deadline >= block.timestamp and (tokens_bought > 0 and max_eth_sold > 0)

    # 确保交易对地址不是本合约地址和零地址
    assert exchange_addr != self and exchange_addr != ZERO_ADDRESS

    # 计算购买指定数量的token所需支付的ETH数量
    eth_bought: uint256(wei) = Exchange(exchange_addr).getEthToTokenOutputPrice(tokens_bought)

    # 计算卖出token的数量
    token_reserve: uint256 = self.token.balanceOf(self)

    # 根据购买目标token所需的ETH数量，计算需要卖出的token数量
    tokens_sold: uint256 = self.getOutputPrice(as_unitless_number(eth_bought), token_reserve, as_unitless_number(self.balance))
    # tokens sold is always > 0
    # 确保卖出的token数量小于最大数量
    assert max_tokens_sold >= tokens_sold and max_eth_sold >= eth_bought

    # 把用户要卖出的Token转移到本合约
    assert self.token.transferFrom(buyer, self, tokens_sold)

    # 向目标交易对合约地址发送ETH，并调用其ethToTokenTransferInput函数
    # 把ETH兑换成目标代币，并转给指定地址，完成兑换
    eth_sold: uint256(wei) = Exchange(exchange_addr).ethToTokenTransferOutput(tokens_bought, deadline, recipient, value=eth_bought)
    log.EthPurchase(buyer, tokens_sold, eth_bought)
    return tokens_sold

# 根据指定的token 地址和指定购买的目标token数量，将本合约的token兑换成token_addr的token
@public
def tokenToTokenSwapOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, msg.sender, exchange_addr)

# 根据指定的token 地址和指定购买的目标token数量，将本合约的token兑换成token_addr的token，并转给指定地址
@public
def tokenToTokenTransferOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, recipient: address, token_addr: address) -> uint256:
    exchange_addr: address = self.factory.getExchange(token_addr)
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr)

# 指定最小ETH购买数量，Token -> Token 的兑换
@public
def tokenToExchangeSwapInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, exchange_addr: address) -> uint256:
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr)

# 指定最小ETH购买数量，Token -> Token 的兑换，并转给指定地址
@public
def tokenToExchangeTransferInput(tokens_sold: uint256, min_tokens_bought: uint256, min_eth_bought: uint256(wei), deadline: timestamp, recipient: address, exchange_addr: address) -> uint256:
    assert recipient != self
    return self.tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, recipient, exchange_addr)

# 指定最小ETH卖出数量，Token -> Token 的兑换
@public
def tokenToExchangeSwapOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, exchange_addr: address) -> uint256:
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, msg.sender, exchange_addr)

# 指定最小ETH卖出数量，Token -> Token 的兑换，并转给指定地址
@public
def tokenToExchangeTransferOutput(tokens_bought: uint256, max_tokens_sold: uint256, max_eth_sold: uint256(wei), deadline: timestamp, recipient: address, exchange_addr: address) -> uint256:
    assert recipient != self
    return self.tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr)

# 根据指定卖出的ETH数量计算可以交易到的Token数量
@public
@constant
def getEthToTokenInputPrice(eth_sold: uint256(wei)) -> uint256:
    assert eth_sold > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    return self.getInputPrice(as_unitless_number(eth_sold), as_unitless_number(self.balance), token_reserve)

# 根据指定卖出的Token数量计算可以交易到的ETH数量
@public
@constant
def getEthToTokenOutputPrice(tokens_bought: uint256) -> uint256(wei):
    assert tokens_bought > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_sold: uint256 = self.getOutputPrice(tokens_bought, as_unitless_number(self.balance), token_reserve)
    return as_wei_value(eth_sold, 'wei')

# 根据指定卖出的Token数量计算可以交易到的ETH数量
@public
@constant
def getTokenToEthInputPrice(tokens_sold: uint256) -> uint256(wei):
    assert tokens_sold > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    eth_bought: uint256 = self.getInputPrice(tokens_sold, token_reserve, as_unitless_number(self.balance))
    return as_wei_value(eth_bought, 'wei')

# 根据指定卖出的ETH数量计算可以交易到的Token数量
@public
@constant
def getTokenToEthOutputPrice(eth_bought: uint256(wei)) -> uint256:
    assert eth_bought > 0
    token_reserve: uint256 = self.token.balanceOf(self)
    return self.getOutputPrice(as_unitless_number(eth_bought), token_reserve, as_unitless_number(self.balance))

# @return Address of Token that is sold on this exchange.
@public
@constant
def tokenAddress() -> address:
    return self.token

# @return Address of factory that created this exchange.
@public
@constant
def factoryAddress() -> address(Factory):
    return self.factory

# ERC20 compatibility for exchange liquidity modified from
# https://github.com/ethereum/vyper/blob/master/examples/tokens/ERC20.vy
@public
@constant
def balanceOf(_owner : address) -> uint256:
    return self.balances[_owner]

@public
def transfer(_to : address, _value : uint256) -> bool:
    self.balances[msg.sender] -= _value
    self.balances[_to] += _value
    log.Transfer(msg.sender, _to, _value)
    return True

@public
def transferFrom(_from : address, _to : address, _value : uint256) -> bool:
    self.balances[_from] -= _value
    self.balances[_to] += _value
    self.allowances[_from][msg.sender] -= _value
    log.Transfer(_from, _to, _value)
    return True

@public
def approve(_spender : address, _value : uint256) -> bool:
    self.allowances[msg.sender][_spender] = _value
    log.Approval(msg.sender, _spender, _value)
    return True

@public
@constant
def allowance(_owner : address, _spender : address) -> uint256:
    return self.allowances[_owner][_spender]
