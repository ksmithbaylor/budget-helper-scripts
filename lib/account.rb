require 'bigdecimal'
require 'pmap'

require_relative './transaction'

# CoinbaseAccount represents a Coinbase account
class CoinbaseAccount
  attr_reader :data

  def initialize(data, client)
    @data = data
    @client = client
  end

  def resource_path
    @data['resource_path']
  end

  def name
    @data['name']
  end

  def type
    @data['type']
  end

  def currency
    @data['currency']['code']
  end

  def balance
    BigDecimal @data['balance']['amount']
  end

  def all_transactions
    %w[transactions deposits withdrawals].pmap do |sub_resource|
      @client.get("#{resource_path}/#{sub_resource}", expand: true).map do |tx|
        CoinbaseTransaction.new tx, self, @client
      end
    end.flatten
  end

  def transactions_back_to(date)
    %w[transactions deposits withdrawals].pmap do |sub_resource|
      path = "#{resource_path}/#{sub_resource}"
      @client
        .get_while(path) { |tx| tx['created_at'] > date }
        .map { |tx| CoinbaseTransaction.new tx, self, @client }
    end.flatten
  end
end
