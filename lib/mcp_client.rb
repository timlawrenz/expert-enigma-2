require 'jimson'

class MCPClientError < StandardError; end

class MCPClient
  def initialize(server_url)
    @client = Jimson::Client.new(server_url)
  end

  def method_missing(name, *args)
    begin
      if args.empty?
        @client.send(name.to_s)
      else
        # Handle both array and hash style arguments
        params = args.first.is_a?(Hash) ? args.first : args
        @client.send(name.to_s, params)
      end
    rescue => e
      raise MCPClientError, "JSON-RPC Error: #{e.message}"
    end
  end

  def respond_to_missing?(name, include_private = false)
    true
  end
end
