require 'sinatra'
require 'sqlite3'
require 'json'
require_relative 'expert_enigma/ast_explorer'

# --- Configuration ---
set :port, 65432
set :bind, '0.0.0.0'
DB_FILE = File.expand_path('../../expert_enigma.db', __FILE__)

# --- JSON-RPC 2.0 Error Codes ---
JSONRPC_PARSE_ERROR      = -32700
JSONRPC_INVALID_REQUEST  = -32600
JSONRPC_METHOD_NOT_FOUND = -32601
JSONRPC_INVALID_PARAMS   = -32602
JSONRPC_INTERNAL_ERROR   = -32603

# --- Helper Functions ---
def get_db
  db = SQLite3::Database.new(DB_FILE, readonly: true)
  db.results_as_hash = true
  db
end

def jsonrpc_error(id, code, message, data = nil)
  {
    jsonrpc: '2.0',
    id: id,
    error: { code: code, message: message, data: data }
  }.to_json
end

def jsonrpc_success(id, result)
  {
    jsonrpc: '2.0',
    id: id,
    result: result
  }.to_json
end

# --- Tool Definitions ---
# This is where we manually define the tools our server supports.
TOOLS = {
  'list_files' => {
    description: 'Returns a list of all files that have been indexed in the database.',
    inputSchema: { type: 'object', properties: {} }
  },
  'get_symbols' => {
    description: 'Returns all symbols (methods, classes, etc.) defined in a specified file.',
    inputSchema: {
      type: 'object',
      properties: {
        file_path: { type: 'string', description: 'The path to the file.' }
      },
      required: ['file_path']
    }
  },
  'get_ast' => {
    description: 'Returns the complete Abstract Syntax Tree (AST) for a specified file.',
    inputSchema: {
      type: 'object',
      properties: {
        file_path: { type: 'string', description: 'The path to the file.' }
      },
      required: ['file_path']
    }
  },
  'query_nodes' => {
    description: "Finds all nodes of a specific type within a file's AST.",
    inputSchema: {
      type: 'object',
      properties: {
        file_path: { type: 'string', description: 'The path to the file.' },
        type: { type: 'string', description: 'The type of node to find (e.g., "def").' }
      },
      required: ['file_path', 'type']
    }
  },
  'get_node_details' => {
    description: "Returns detailed information about a specific node in a file's AST.",
    inputSchema: {
      type: 'object',
      properties: {
        file_path: { type: 'string', description: 'The path to the file.' },
        node_id: { type: 'string', description: 'The ID of the node.' }
      },
      required: ['file_path', 'node_id']
    }
  },
  'get_ancestors' => {
    description: 'Returns the ancestor nodes (parent hierarchy) of a specified AST node.',
    inputSchema: {
      type: 'object',
      properties: {
        file_path: { type: 'string', description: 'The path to the file.' },
        node_id: { type: 'string', description: 'The ID of the node.' }
      },
      required: ['file_path', 'node_id']
    }
  },
  'find_definition' => {
    description: 'Locates where a symbol (method, class, variable) is defined.',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'The name of the symbol.' }
      },
      required: ['name']
    }
  },
  'find_references' => {
    description: 'Finds all locations where a symbol is referenced or used.',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'The name of the symbol.' }
      },
      required: ['name']
    }
  }
}.freeze

# --- Method Implementations ---
MCP_METHODS = {
  'tools/list' => ->(params, db) {
    { tools: TOOLS.map { |name, definition| { name: name }.merge(definition) } }
  },
  'initialize' => ->(params, db) {
    {
      protocolVersion: '2025-06-18',
      serverInfo: {
        name: 'expert-enigma',
        version: '0.1.0'
      },
      capabilities: {
        tools: {}
      }
    }
  },
  'list_files' => ->(params, db) {
    files = db.execute("SELECT DISTINCT file_path FROM files ORDER BY file_path").map { |row| row['file_path'] }
    { files: files }
  },
  'get_symbols' => ->(params, db) {
    file_path = params['file_path']
    raise ArgumentError, 'Missing required parameter: file_path' unless file_path
    symbols = db.execute("SELECT name, type, scope, start_line, end_line FROM symbols WHERE file_id = (SELECT id FROM files WHERE file_path = ?)", [file_path])
    { symbols: symbols }
  },
  'get_ast' => ->(params, db) {
    file_path = params['file_path']
    raise ArgumentError, 'Missing required parameter: file_path' unless file_path
    result = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)
    raise "File not found or not indexed: #{file_path}" unless result
    JSON.parse(result['ast_json'])
  },
  'query_nodes' => ->(params, db) {
    file_path = params['file_path']
    node_type = params['type']
    raise ArgumentError, 'Missing required parameters: file_path and type' unless file_path && node_type
    
    ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
    raise "File not found or not indexed: #{file_path}" unless ast_json

    ast_hash = JSON.parse(ast_json)
    explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
    nodes = explorer.find_nodes_by_type(node_type)
    { nodes: nodes }
  },
  'get_node_details' => ->(params, db) {
    file_path = params['file_path']
    node_id = params['node_id']
    raise ArgumentError, 'Missing required parameters: file_path and node_id' unless file_path && node_id

    ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
    raise "File not found or not indexed: #{file_path}" unless ast_json

    ast_hash = JSON.parse(ast_json)
    explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
    node = explorer.find_node_by_id(node_id)
    raise "Node with id '#{node_id}' not found in file '#{file_path}'" unless node
    { node: node }
  },
  'get_ancestors' => ->(params, db) {
    file_path = params['file_path']
    node_id = params['node_id']
    raise ArgumentError, 'Missing required parameters: file_path and node_id' unless file_path && node_id

    ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
    raise "File not found or not indexed: #{file_path}" unless ast_json

    ast_hash = JSON.parse(ast_json)
    explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
    ancestors = explorer.get_ancestors(node_id)
    { ancestors: ancestors }
  },
  'find_definition' => ->(params, db) {
    name = params['name']
    raise ArgumentError, 'Missing required parameter: name' unless name

    sql = "SELECT s.name, s.type, s.scope, s.start_line, s.end_line, f.file_path FROM symbols s JOIN files f ON s.file_id = f.id WHERE s.name = ?"
    definitions = db.execute(sql, name)
    { definitions: definitions }
  },
  'find_references' => ->(params, db) {
    name = params['name']
    raise ArgumentError, 'Missing required parameter: name' unless name

    sql = "SELECT r.symbol_name, r.start_line, r.end_line, f.file_path FROM \"references\" r JOIN files f ON r.file_id = f.id WHERE r.symbol_name = ?"
    references = db.execute(sql, name)
    { references: references }
  }
}.freeze

# --- Sinatra Routes ---
get '/' do
  content_type :json
  { status: 'ok', message: 'Expert Enigma MCP Server is running.' }.to_json
end

post '/' do
  content_type :json
  request_body = request.body.read
  
  begin
    payload = JSON.parse(request_body)
  rescue JSON::ParserError
    return jsonrpc_error(nil, JSONRPC_PARSE_ERROR, 'Invalid JSON')
  end

  id = payload['id']
  method_name = payload['method']
  params = payload['params'] || {}

  unless method_name && MCP_METHODS.key?(method_name)
    return jsonrpc_error(id, JSONRPC_METHOD_NOT_FOUND, "Method not found: #{method_name}")
  end

  db = get_db
  begin
    result = MCP_METHODS[method_name].call(params, db)
    jsonrpc_success(id, result)
  rescue ArgumentError => e
    jsonrpc_error(id, JSONRPC_INVALID_PARAMS, e.message)
  rescue => e
    puts "Internal error: #{e.message}"
    puts e.backtrace
    jsonrpc_error(id, JSONRPC_INTERNAL_ERROR, "Internal server error: #{e.message}")
  ensure
    db.close
  end
end

puts "Expert Enigma MCP Server starting on port #{settings.port}"