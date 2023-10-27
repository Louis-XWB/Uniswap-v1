contract Exchange():
    def setup(token_addr: address): modifying

# 创建新的代币交易合约事件
NewExchange: event({token: indexed(address), exchange: indexed(address)})

exchangeTemplate: public(address) # 存储交易合约模板地址的变量
tokenCount: public(uint256) # 存储代币合约的变量
token_to_exchange: address[address] # 将代币地址映射到其对应的交换合约地址
exchange_to_token: address[address] # 将交换合约地址映射到其对应的代币地址
id_to_token: address[uint256] # 将代币id映射到其对应的代币地址

# 初始化Factory
@public
def initializeFactory(template: address):
    assert self.exchangeTemplate == ZERO_ADDRESS
    assert template != ZERO_ADDRESS
    self.exchangeTemplate = template

# 根据给定的Token地址创建ETH-ERC20交易合约
@public
def createExchange(token: address) -> address:
    assert token != ZERO_ADDRESS
    assert self.exchangeTemplate != ZERO_ADDRESS

    # 确认该代币还没有交易合约
    assert self.token_to_exchange[token] == ZERO_ADDRESS

    # 创建交易合约
    exchange: address = create_with_code_of(self.exchangeTemplate)

    # 初始化交易合约 in uniswap_exchange.vy
    Exchange(exchange).setup(token)

    # 更新交易合约相关存储
    self.token_to_exchange[token] = exchange
    self.exchange_to_token[exchange] = token

    # 生成对应ID并存储
    token_id: uint256 = self.tokenCount + 1
    self.tokenCount = token_id
    self.id_to_token[token_id] = token
    log.NewExchange(token, exchange)
    return exchange

@public
@constant
def getExchange(token: address) -> address:
    return self.token_to_exchange[token]

@public
@constant
def getToken(exchange: address) -> address:
    return self.exchange_to_token[exchange]

@public
@constant
def getTokenWithId(token_id: uint256) -> address:
    return self.id_to_token[token_id]
