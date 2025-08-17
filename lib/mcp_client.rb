require 'net/http'
require 'json'
require 'uri'
require 'timeout'

# MCP Client for communicating with the Expert Enigma MCP Server
# 
# This client provides a Ruby interface for all MCP server tools,
# handling JSON-RPC 2.0 communication and error handling.
#
# Example usage:
#   client = MCPClient.new('http://localhost:65432')
#   files = client.list_files
#   symbols = client.get_symbols('lib/mcp_server.rb')
class MCPClient
  # JSON-RPC 2.0 error codes
  PARSE_ERROR = -32700
  INVALID_REQUEST = -32600
  METHOD_NOT_FOUND = -32601
  INVALID_PARAMS = -32602
  INTERNAL_ERROR = -32603
  
  # Initialize a new MCP client
  #
  # @param server_url [String] The URL of the MCP server (e.g., 'http://localhost:65432')
  # @param timeout [Integer] HTTP timeout in seconds (default: 30)
  def initialize(server_url, timeout: 30)
    @server_url = server_url
    @uri = URI(server_url)
    @timeout = timeout
    @request_id = 0
  end

  # Get server status
  #
  # @return [Hash] Server status information
  # @example
  #   client.status
  #   # => { "status" => "ok", "message" => "Expert Enigma MCP Server is running." }
  def status
    call_method('status')
  end

  # List all indexed files in the repository
  #
  # @return [Hash] Hash containing array of file paths
  # @example
  #   client.list_files
  #   # => { "files" => ["lib/mcp_server.rb", "test/test_file_1.rb"] }
  def list_files
    call_method('list_files')
  end

  # Get all symbols (methods, classes, etc.) for a given file
  #
  # @param file_path [String] Path to the file to analyze
  # @return [Hash] Hash containing array of symbols with their metadata
  # @example
  #   client.get_symbols('test/test_file_1.rb')
  #   # => { "symbols" => [{"name" => "method_one", "type" => "method", "scope" => "TestModule::TestClass", "start_line" => 3, "end_line" => 5}] }
  def get_symbols(file_path)
    call_method('get_symbols', file_path)
  end

  # Search for methods using vector similarity
  #
  # @param query [String] Search query text
  # @param limit [Integer] Maximum number of results to return (default: 10)
  # @return [Hash] Hash containing array of search results with similarity scores
  # @example
  #   client.search('method', 5)
  #   # => { "results" => [{"name" => "method_one", "start_line" => 3, "end_line" => 5, "file_path" => "test/test_file_1.rb", "distance" => 0.25}] }
  def search(query, limit = 10)
    call_method('search', { query: query, limit: limit })
  end

  # Get the full Abstract Syntax Tree (AST) for a given file
  #
  # @param file_path [String] Path to the file to analyze
  # @return [Hash] The parsed AST as a Ruby hash
  # @example
  #   client.get_ast('test/test_file_1.rb')
  #   # => { "type" => "begin", "children" => [...] }
  def get_ast(file_path)
    call_method('get_ast', file_path)
  end

  # Query for specific node types within a file's AST
  #
  # @param file_path [String] Path to the file to analyze
  # @param node_type [String] Type of AST nodes to find (e.g., 'def', 'class', 'module')
  # @return [Hash] Hash containing array of matching nodes
  # @example
  #   client.query_nodes('test/test_file_1.rb', 'def')
  #   # => { "nodes" => [{"type" => "def", "id" => "node_123", ...}] }
  def query_nodes(file_path, node_type)
    call_method('query_nodes', file_path, node_type)
  end

  # Get details for a specific node in a file's AST
  #
  # @param file_path [String] Path to the file containing the node
  # @param node_id [String] Unique identifier of the node to retrieve
  # @return [Hash] Hash containing detailed node information
  # @example
  #   client.get_node_details('test/test_file_1.rb', 'node_123')
  #   # => { "node" => {"type" => "def", "name" => "method_one", ...} }
  def get_node_details(file_path, node_id)
    call_method('get_node_details', file_path, node_id)
  end

  # Get ancestors of a specific node in a file's AST
  #
  # @param file_path [String] Path to the file containing the node
  # @param node_id [String] Unique identifier of the node
  # @return [Hash] Hash containing array of ancestor nodes
  # @example
  #   client.get_ancestors('test/test_file_1.rb', 'node_123')
  #   # => { "ancestors" => [{"type" => "class", "name" => "TestClass", ...}] }
  def get_ancestors(file_path, node_id)
    call_method('get_ancestors', file_path, node_id)
  end

  # Find the definition of a symbol
  #
  # @param name [String] Name of the symbol to find
  # @return [Hash] Hash containing array of definitions
  # @example
  #   client.find_definition('method_one')
  #   # => { "definitions" => [{"name" => "method_one", "type" => "method", "file_path" => "test/test_file_1.rb", "start_line" => 3}] }
  def find_definition(name)
    call_method('find_definition', name)
  end

  # Find all references to a symbol
  #
  # @param name [String] Name of the symbol to find references for
  # @return [Hash] Hash containing array of references
  # @example
  #   client.find_references('class_method_one')
  #   # => { "references" => [{"symbol_name" => "class_method_one", "file_path" => "test/test_file_2.rb", "start_line" => 3}] }
  def find_references(name)
    call_method('find_references', name)
  end

  # Get the call hierarchy for a method at a specific location
  #
  # @param file_path [String] Path to the file containing the method
  # @param line [Integer] Line number where the method is located
  # @return [Hash] Hash containing method information and its call hierarchy
  # @example
  #   client.get_call_hierarchy('test/test_file_1.rb', 3)
  #   # => { "method" => {"name" => "method_one", "file_path" => "test/test_file_1.rb", "line" => 3}, "inbound_calls" => [], "outbound_calls" => [] }
  def get_call_hierarchy(file_path, line)
    call_method('get_call_hierarchy', file_path, line)
  end

  private

  # Make a JSON-RPC 2.0 method call to the server
  #
  # @param method_name [String] Name of the method to call
  # @param *args [Array] Arguments to pass to the method
  # @return [Object] The result of the method call
  # @raise [MCPClientError] If the server returns an error
  def call_method(method_name, *args)
    @request_id += 1
    
    request_body = {
      jsonrpc: '2.0',
      method: method_name,
      params: args,
      id: @request_id
    }

    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = (@uri.scheme == 'https')
    http.read_timeout = @timeout
    http.open_timeout = @timeout

    request = Net::HTTP::Post.new(@uri.path.empty? ? '/' : @uri.path)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(request_body)

    begin
      response = http.request(request)
      
      unless response.code == '200'
        raise MCPClientError.new("HTTP error: #{response.code} #{response.message}")
      end

      response_data = JSON.parse(response.body)
      
      # Handle JSON-RPC errors
      if response_data['error']
        error = response_data['error']
        raise MCPClientError.new("JSON-RPC error #{error['code']}: #{error['message']}")
      end

      response_data['result']
    rescue JSON::ParserError => e
      raise MCPClientError.new("Invalid JSON response: #{e.message}")
    rescue Timeout::Error, Net::ReadTimeout, Net::OpenTimeout => e
      raise MCPClientError.new("Request timeout: #{e.message}")
    rescue Errno::ECONNREFUSED => e
      raise MCPClientError.new("Connection refused: #{e.message}")
    rescue => e
      raise MCPClientError.new("Unexpected error: #{e.message}")
    end
  end
end

# Custom exception class for MCP client errors
class MCPClientError < StandardError
  def initialize(message)
    super(message)
  end
end