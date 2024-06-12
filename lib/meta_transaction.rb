require 'bigdecimal'

# MetaTransaction represents a set of transactions that should be considered
# together as one "operation". They'll be summed up and have their descriptions
# combined.
class MetaTransaction
  attr_reader :transactions

  TABLE_HEADERS = %w[
    Timestamp
    Account
    Type
    Description
    Amount
    Balance
    Total
  ].freeze

  def initialize
    @transactions = []
  end

  def add(transaction)
    @transactions << transaction
  end

  def amount
    @transactions.map(&:amount).inject(BigDecimal('0'), &:+)
  end

  def timestamps
    stamps = @transactions.map(&:timestamp).map { |s| " #{s} " }
    stamps.unshift color_by_account(stamps[0][0..10].ljust(stamps[0].size))
    stamps[stamps.size - 1] = underline stamps.last
    stamps.join("\n")
  end

  def timestamp
    if @transactions.empty?
      nil
    else
      @transactions.first.timestamp
    end
  end

  def account_name
    if @transactions.empty?
      nil
    else
      @transactions.first.account_name
    end
  end

  def account_names(max_account_length)
    names = [" #{@transactions.first.account_name.ljust(max_account_length)} "]
    blank = ' ' * names.first.size
    @transactions.size.times do
      names << blank
    end
    names[names.size - 1] = underline(names.size > 1 ? blank : names.first)
    names[0] = color_by_account names[0]
    names.join("\n")
  end

  def types(max_type_length)
    ts = @transactions.map(&:type).map { |s| " #{s} " }
    ts[ts.size - 1] = underline ts.last.ljust(max_type_length + 2)
    ts.unshift(' ' * (max_type_length + 2))
    ts[0] = color_by_account ts[0]
    ts.join("\n")
  end

  def type_width
    @transactions.map(&:type_width).max
  end

  def description(max_description_length)
    descriptions = @transactions.map(&:description).map { |s| " #{s} " }
    descriptions[descriptions.size - 1] =
      underline descriptions.last.ljust(max_description_length + 2)
    descriptions.unshift(' ' * (max_description_length + 2))
    descriptions[0] = color_by_account descriptions[0]
    descriptions.join("\n")
  end

  def description_width
    @transactions.map(&:description_width).max
  end

  def aligned_amounts
    amounts = @transactions.map(&:aligned_amount)
    amounts[amounts.size - 1] = underline amounts.last
    amounts.unshift(aligned_amount)
    amounts[0] = color_by_account amounts[0]
    amounts.join("\n")
  end

  def aligned_amount(value = amount, width = 14)
    as_string = value.to_s 'F'
    as_string = as_string.gsub('-', '') if value.zero?
    dot_position = as_string.index '.'
    (' ' * (7 - dot_position) + as_string).ljust(width, '0') + ' '
  end

  def should_add(transaction)
    return true if @transactions.empty?

    last_transaction = @transactions.last
    return false unless last_transaction.account_name == transaction.account_name

    time_diff = (Time.new(last_transaction.timestamp) - Time.new(transaction.timestamp)).to_i.abs

    case [last_transaction, transaction].map(&:type)
    in ['subscription_rebate', 'subscription_rebate']
      true
    in ['subscription_rebate', 'advanced_trade_fill']
      time_diff < 60 && matches_advanced_trade(transaction)
    in ['advanced_trade_fill', 'advanced_trade_fill']
      time_diff < 60 && matches_advanced_trade(transaction)
    in ['advanced_trade_fill', 'subscription_rebate']
      time_diff < 3600
    else
      false
    end
  end

  def table_row(
    max_account_length,
    max_type_length,
    max_description_length,
    account_balance,
    total_balance
  )
    [
      timestamps,
      account_names(max_account_length),
      types(max_type_length),
      description(max_description_length),
      aligned_amounts,
      color_by_account(aligned_amount(account_balance.round(2), 10)),
      color_total(aligned_amount(total_balance.round(2), 10))
    ]
  end

  private

  def color_by_account(str)
    case account_name
    when 'USDC Wallet'
      "\e[48;5;12m#{str}\e[0m"
    when 'Cash (USD)'
      "\e[48;5;28m#{str}\e[0m"
    else
      str
    end
  end

  def color_total(str)
    "\e[48;5;23m#{str}\e[0m"
  end

  def underline(str)
    # "\e[4m#{str}\e[24m"
    str
  end

  def matches_advanced_trade(transaction)
    fills = advanced_trade_fills
    return true if fills.empty?

    fills.any? { |t| t.advanced_trade_operation == transaction.advanced_trade_operation }
  end

  def advanced_trade_fills
    @transactions.filter { |t| t.type == 'advanced_trade_fill' }
  end
end
