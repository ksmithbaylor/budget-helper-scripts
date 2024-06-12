require 'bigdecimal'
require 'pry'

# CoinbaseTransaction represents a Coinbase transaction
class CoinbaseTransaction
  class UnknownType < StandardError; end

  attr_reader :account, :data

  TABLE_HEADERS = %w[
    Timestamp
    Account
    Type
    Description
    Amount
    Balance
  ].freeze

  def initialize(data, account, client)
    @data = data
    @client = client
    @account = account
  end

  def timestamp
    data['created_at']
  end

  def account_name
    @account.name
  end

  def decimals
    @account.data['currency']['exponent']
  end

  def type
    case data['resource']
    when 'transaction'
      data['type']
    else
      data['resource']
    end
  end

  def type_width
    type.size
  end

  def currency
    data['amount']['currency']
  end

  def amount
    subtotal = BigDecimal(data['amount']['amount'])
    if type == 'advanced_trade_fill'
      (subtotal - BigDecimal(data['advanced_trade_fill']['commission'])).round(decimals)
    else
      subtotal.round(decimals)
    end
  end

  def aligned_amount(value = amount, width = 14)
    as_string = value.to_s 'F'
    dot_position = as_string.index '.'
    (' ' * (7 - dot_position) + as_string).ljust(width, '0') + ' '
  end

  def balance_before(balance_after)
    balance_after - amount
  end

  def description
    method = "#{type}_description".to_sym
    raise UnknownType, type unless respond_to? method, true

    send(method)
  end

  def description_width
    description.size
  end

  def table_row(max_type_length, max_description_length, running_balance)
    [
      timestamp,
      account_name,
      type.ljust(max_type_length),
      description.ljust(max_description_length),
      aligned_amount,
      aligned_amount(running_balance)
    ].map { |s| "\e[4m #{s} \e[24m" }
  end

  def advanced_trade_operation
    return nil unless type == 'advanced_trade_fill'

    fill = data['advanced_trade_fill']
    [fill['order_side'], fill['product_id']]
  end

  private

  def subscription_rebate_description
    data['description'] || 'Unknown subscription rebate'
  end

  def interest_description
    'Interest received'
  end

  def advanced_trade_fill_description
    fill = data['advanced_trade_fill']
    desc = "#{fill['order_side']} #{fill['product_id']} @ #{fill['fill_price']}"
    desc[0].upcase + desc[1..]
  end

  def send_description
    operation = amount.negative? ? 'Sent to' : 'Received from'
    address = data.dig('to', 'address') || 'an address'
    network = data.dig('network', 'network_name') || 'an unknown network'
    "#{operation} #{address} on #{network}"
  end

  def buy_description
    "Bought #{currency} with #{data['buy']['payment_method_name']}"
  end

  def sell_description
    if account.type == 'wallet'
      "Sold #{currency} for USD"
    else
      "Sold from #{data['sell']['payment_method_name']}"
    end
  end

  def trade_description
    'Trade'
  end

  def fiat_withdrawal_description
    'Withdrew to bank'
  end

  def fiat_deposit_description
    'Deposited from bank'
  end

  def derivatives_settlement_description
    'Derivatives settlement'
  end

  def deposit_description
    "Deposited to #{@account.name}"
  end

  def withdrawal_description
    "Withdrew from #{@account.name}"
  end

  def staking_reward_description
    'Staking reward'
  end
end
