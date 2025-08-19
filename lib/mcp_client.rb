require 'net/http'
require 'json'

class MCPClientError < StandardError; end

class MCPClient
  def initialize(server_url)
    @uri = URI(server_url)
  end

  def method_missing(name, *args)
    begin
      http = Net::HTTP.new(@uri.host, @uri.port)
      request = Net::HTTP::Post.new(@uri.request_uri, 'Content-Type' => 'application/json')

      params = args.first
      
      request.body = {
        jsonrpc: '2.0',
        method: name,
        params: params,
        id: 1
      }.to_json

      response = http.request(request)
      
      body = JSON.parse(response.body)

      if body['error']
        raise MCPClientError, "JSON-RPC Error: #{body['error']['message']}"
      else
        body['result']
      end
    rescue => e
      raise MCPClientError, "HTTP Error: #{e.message}"
    end
  end

  def respond_to_missing?(name, include_private = false)
    true
  end
end