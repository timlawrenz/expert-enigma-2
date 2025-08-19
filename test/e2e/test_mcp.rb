require 'minitest/autorun'
ENV['MT_NO_PLUGINS'] = '1'
require_relative '../../lib/mcp_server'
require_relative '../../lib/mcp_client'
require 'fileutils'

# --- Test Suite Setup ---
DB_FILE = File.expand_path('../../expert_enigma.db', __dir__)

def self.rebuild_test_database
  puts "Setting up e2e test suite..."
  
  build_script = File.expand_path('../../scripts/05_build_database.rb', __dir__)
  fixtures_dir = File.expand_path('../fixtures', __dir__)
  
  puts "Building fresh test database from fixtures..."
  system("ruby", build_script, fixtures_dir)
  
  unless $?.success?
    raise "Failed to build the test database. Aborting tests."
  end
end

rebuild_test_database

SERVER_THREAD = Thread.new { McpServer.run! }
sleep 0.1 # Give the server a moment to start

Minitest.after_run do
  puts "\nTearing down e2e test suite..."
  McpServer.quit!
  SERVER_THREAD.join
  FileUtils.rm_f(DB_FILE)
  puts "Cleaned up test database."
end
# --- End Test Suite Setup ---


class TestMcpE2e < Minitest::Test
  def setup
    @port = McpServer.port
  end

  def test_client_server_communication
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.status
    assert_equal "ok", response["status"]
  end

  def test_list_files
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.list_files
    assert_instance_of Array, response["files"]
    assert_equal ["cat.rb", "dog.rb"], response["files"].sort
  end

  def test_get_symbols_for_cat
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_symbols('cat.rb')
    assert_instance_of Array, response['symbols']
    symbol_names = response['symbols'].map { |s| s['name'] }.sort
    assert_equal ["Cat", "initialize", "meow", "scratch"], symbol_names
  end

  def test_get_symbols_for_dog
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_symbols('dog.rb')
    assert_instance_of Array, response['symbols']
    symbol_names = response['symbols'].map { |s| s['name'] }.sort
    assert_equal ["Dog", "bark", "wag_tail"], symbol_names
  end

  def test_get_ast
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_ast('dog.rb')
    assert_instance_of Hash, response
    assert_equal "class", response['type']
  end

  def test_query_nodes
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.query_nodes('dog.rb', 'def')
    assert_instance_of Array, response['nodes']
    assert_equal 2, response['nodes'].length
    assert_equal "bark", response['nodes'][0]['children'][0]
  end

  def test_get_node_details
    client = MCPClient.new("http://localhost:#{@port}")
    # First, find a node to get details for.
    nodes_response = client.query_nodes('dog.rb', 'def')
    node_id = nodes_response['nodes'][0]['id']
    
    response = client.get_node_details('dog.rb', node_id)
    assert_instance_of Hash, response['node']
    assert_equal "def", response['node']['type']
    assert_equal "bark", response['node']['children'][0]
  end

  def test_get_ancestors
    client = MCPClient.new("http://localhost:#{@port}")
    # First, find a node to get ancestors for.
    nodes_response = client.query_nodes('dog.rb', 'def')
    node_id = nodes_response['nodes'][0]['id']

    response = client.get_ancestors('dog.rb', node_id)
    assert_instance_of Array, response['ancestors']
    assert_equal 2, response['ancestors'].length
    assert_equal "class", response['ancestors'][0]['type']
    assert_equal "begin", response['ancestors'][1]['type']
  end

  def test_find_definition
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.find_definition('Dog')
    assert_instance_of Array, response['definitions']
    assert_equal 1, response['definitions'].length
    assert_equal "dog.rb", response['definitions'][0]['file_path']
  end

  def test_find_references
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.find_references('Dog')
    assert_instance_of Array, response['references']
    assert_equal 2, response['references'].length
  end

  def test_get_call_hierarchy
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_call_hierarchy('cat.rb', 12)
    assert_instance_of Hash, response
    assert_equal "scratch", response['method']['name']
    assert_equal 1, response['outbound_calls'].length
    assert_equal "wag_tail", response['outbound_calls'][0]['name']
  end

  def test_get_symbols_for_non_existent_file
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_symbols('non_existent_file.rb')
    assert_equal "error", response["status"]
    assert_equal "File not found: non_existent_file.rb", response["message"]
  end

  def test_get_ast_for_non_existent_file
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_ast('non_existent_file.rb')
    assert_equal "error", response["status"]
    assert_equal "File not found: non_existent_file.rb", response["message"]
  end

  def test_query_nodes_for_non_existent_file
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.query_nodes('non_existent_file.rb', 'def')
    assert_equal "error", response["status"]
    assert_equal "File not found: non_existent_file.rb", response["message"]
  end

  def test_get_node_details_for_non_existent_file
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_node_details('non_existent_file.rb', 'root.children.0')
    assert_equal "error", response["status"]
    assert_equal "File not found: non_existent_file.rb", response["message"]
  end

  def test_get_node_details_for_non_existent_node
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_node_details('dog.rb', 'root.children.99')
    assert_equal "error", response["status"]
    assert_equal "Node with id 'root.children.99' not found in file 'dog.rb'", response["message"]
  end

  def test_get_ancestors_for_non_existent_file
    client = MCPClient.new("http://localhost:#{@port}")
    response = client.get_ancestors('non_existent_file.rb', 'root.children.0')
    assert_equal "error", response["status"]
    assert_equal "File not found: non_existent_file.rb", response["message"]
  end
end