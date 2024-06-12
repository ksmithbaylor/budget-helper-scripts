require 'json'
require 'jwt'
require 'openssl'
require 'securerandom'
require 'httparty'

require_relative './account'

# CoinbaseClient allows calls to Coinbase's APIs
class CoinbaseClient
  class DoneWithData < StandardError; end

  BASE_URL = 'api.coinbase.com'.freeze
  CACHE_DIR = '.request_cache'

  def initialize(key_path = 'cdp_api_key.json')
    key = JSON.parse(File.read(key_path))
    @api_key_name = key['name']
    @api_key_private_key = key['privateKey']
  end

  def all_accounts
    get('/v2/accounts', expand: true).map do |account_data|
      CoinbaseAccount.new account_data, self
    end
  end

  def get(path, expand: false)
    cached = read_cache(path, expand)
    return cached unless cached.nil?

    response = get_with_jwt(path)
    unless expand
      cache(path, expand, response['data'])
      return response['data']
    end

    results = []

    loop do
      break if response['data'].nil?

      response['data'].each do |data|
        raise DoneWithData, 'condition false' if block_given? && !(yield data)

        results << data
      end

      break if out_of_data?(response)

      response = get_with_jwt(response['pagination']['next_uri'])
    rescue DoneWithData
      break
    end

    cache(path, expand, results)
    results
  end

  def get_while(path, &block)
    get(path, expand: true, &block)
  end

  private

  def cache(path, expand, results)
    Dir.mkdir(CACHE_DIR) unless Dir.exist?(CACHE_DIR)

    File.write(cache_filepath(path, expand), results.to_json)
  end

  def read_cache(path, expand)
    return nil unless Dir.exist?(CACHE_DIR)

    filepath = cache_filepath(path, expand)
    return nil unless File.exist?(filepath)

    JSON.parse(File.read(filepath))
  end

  def cache_filepath(path, expand)
    "#{CACHE_DIR}/#{cache_filename(path, expand)}"
  end

  def cache_filename(path, expand)
    "#{path.gsub('/', '---')}.expand-#{expand}.json"
  end

  def out_of_data?(response)
    response['pagination'].nil? ||
      response['pagination']['next_uri'].nil? ||
      response['pagination']['next_uri'] == '' ||
      response['data'].last.nil?
  end

  def get_with_jwt(path)
    puts "GET #{path}"
    HTTParty.get(
      uri(path),
      {
        headers: {
          'Content-Type': 'application/json',
          Authorization: "Bearer #{jwt_for('GET', path)}"
        }
      }
    )
  end

  def uri(path)
    "https://#{BASE_URL}#{path}"
  end

  def jwt_for(method, path)
    path_without_query = path.gsub(/\?.*/, '')
    jwt_uri = "#{method} #{BASE_URL}#{path_without_query}"
    JWT.encode(jwt_claims(jwt_uri), private_key, 'ES256', jwt_header)
  end

  def private_key
    OpenSSL::PKey.read(@api_key_private_key)
  end

  def jwt_claims(uri)
    {
      sub: @api_key_name,
      iss: 'cdp',
      aud: ['cdp_service'],
      nbf: Time.now.to_i,
      exp: Time.now.to_i + 60, # Expiration time: 1 minute from now.
      uris: [uri]
    }
  end

  def jwt_header
    {
      typ: 'JWT',
      kid: @api_key_name,
      nonce: SecureRandom.hex(16)
    }
  end
end
