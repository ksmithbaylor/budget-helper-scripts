require 'terminal-table'
require 'pmap'

require_relative '../lib/client'
require_relative '../lib/meta_transaction'

def print_transaction_table(txs, balances_by_account)
  max_account_length = txs.map(&:account_name).map(&:size).max
  max_description_length = txs.map(&:description_width).max
  max_type_length = txs.map(&:type_width).max
  table = Terminal::Table.new do |t|
    t.headings = txs.first.class::TABLE_HEADERS.map { |s| " #{s} " }
    rows = []
    txs.each do |tx|
      account_name = tx.account_name
      account_balance = balances_by_account[account_name]
      total_balance = balances_by_account.values.sum
      rows << tx.table_row(
        max_account_length,
        max_type_length,
        max_description_length,
        account_balance,
        total_balance
      )
      balances_by_account[account_name] -= tx.amount
    end
    t.rows = rows
    t.style = {
      border: :unicode_round,
      padding_left: 0,
      padding_right: 0
    }
  end
  puts table
end

DATE = ARGV[0]

client = CoinbaseClient.new
accounts = client.all_accounts
usd_accounts = accounts.filter { |a| a.currency == 'USD' }
usdc_account = accounts.find { |a| a.currency == 'USDC' }

txs_by_account = [usdc_account, *usd_accounts]
                 .pmap { |account| account.transactions_back_to(DATE) }
                 .flatten
                 .reject { |tx| %w[deposit withdrawal].include? tx.type }
                 .group_by(&:account)
                 .transform_values { |txs| txs.sort_by(&:timestamp).reverse }

metatransactions_by_account = {}

txs_by_account.each do |account, txs|
  break if txs.empty?

  metatransactions_by_account[account] = []

  metatransaction = MetaTransaction.new
  txs.each do |tx|
    unless metatransaction.should_add(tx)
      metatransactions_by_account[account] << metatransaction
      metatransaction = MetaTransaction.new
    end
    metatransaction.add(tx)
  end
end

balances_by_account = metatransactions_by_account.keys.map do |account|
  [account.name, account.balance]
end.to_h

all_txs = metatransactions_by_account.values.flatten.sort_by(&:timestamp).reverse

print_transaction_table(all_txs, balances_by_account)
