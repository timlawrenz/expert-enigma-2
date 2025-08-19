require 'sqlite3'
require 'json'
require 'sinatra/base'
require_relative 'expert_enigma/ast_explorer'

# MCP Handler class containing all tool methods
class MCPHandler
  def initialize(db_file)
    @db_file = db_file
  end

  # --- Database Connection ---
  def get_db
    db = SQLite3::Database.new(@db_file, readonly: true)
    db.results_as_hash = true
    db
  end

  # Simple status check
  def status
    { status: 'ok', message: 'Expert Enigma MCP Server is running.' }
  end

  # List all indexed files
  def list_files
    db = get_db
    begin
      files = db.execute("SELECT DISTINCT file_path FROM files ORDER BY file_path").map { |row| row['file_path'] }
      { files: files }
    ensure
      db.close
    end
  end

  # Get all symbols (methods) for a given file
  def get_symbols(file_path)
    raise ArgumentError, 'Missing required parameter: file_path' unless file_path

    db = get_db
    begin
      file_id = db.get_first_value("SELECT id FROM files WHERE file_path = ?", file_path)
      unless file_id
        return { status: 'error', message: "File not found: #{file_path}" }
      end
      
      symbols = db.execute("SELECT name, type, scope, start_line, end_line FROM symbols WHERE file_id = ?", file_id)
      { symbols: symbols }
    ensure
      db.close
    end
  end

  # Get the full AST for a given file
  def get_ast(file_path)
    raise ArgumentError, 'Missing required parameter: file_path' unless file_path

    db = get_db
    begin
      result = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)
      if result
        # The AST is stored as a JSON string. We return it as parsed JSON.
        JSON.parse(result['ast_json'])
      else
        { status: 'error', message: "File not found: #{file_path}" }
      end
    ensure
      db.close
    end
  end

  # Query for nodes within a file's AST
  def query_nodes(file_path, node_type)
    raise ArgumentError, 'Missing required parameters: file_path and type' unless file_path && node_type

    db = get_db
    begin
      ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
      
      if ast_json
        ast_hash = JSON.parse(ast_json)
        explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
        nodes = explorer.find_nodes_by_type(node_type)
        { nodes: nodes }
      else
        { status: 'error', message: "File not found: #{file_path}" }
      end
    ensure
      db.close
    end
  end

  # Get details for a specific node in a file
  def get_node_details(file_path, node_id)
    raise ArgumentError, 'Missing required parameters: file_path and node_id' unless file_path && node_id

    db = get_db
    begin
      ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
      
      if ast_json
        ast_hash = JSON.parse(ast_json)
        explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
        node = explorer.find_node_by_id(node_id)
        
        if node
          { node: node }
        else
          { status: 'error', message: "Node with id '#{node_id}' not found in file '#{file_path}'" }
        end
      else
        { status: 'error', message: "File not found: #{file_path}" }
      end
    ensure
      db.close
    end
  end

  # Get ancestors of a specific node in a file
  def get_ancestors(file_path, node_id)
    raise ArgumentError, 'Missing required parameters: file_path and node_id' unless file_path && node_id

    db = get_db
    begin
      ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
      
      if ast_json
        ast_hash = JSON.parse(ast_json)
        explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
        ancestors = explorer.get_ancestors(node_id)
        { ancestors: ancestors }
      else
        { status: 'error', message: "File not found: #{file_path}" }
      end
    ensure
      db.close
    end
  end

  # Find the definition of a symbol
  def find_definition(name)
    raise ArgumentError, 'Missing required parameter: name' unless name

    db = get_db
    begin
      # This is a simplified implementation. A real version would consider scope.
      sql = <<-SQL
        SELECT s.name, s.type, s.scope, s.start_line, s.end_line, f.file_path
        FROM symbols s
        JOIN files f ON s.file_id = f.id
        WHERE s.name = ?
      SQL
      
      definitions = db.execute(sql, name)
      { definitions: definitions }
    ensure
      db.close
    end
  end

  # Find all references to a symbol
  def find_references(name)
    raise ArgumentError, 'Missing required parameter: name' unless name

    db = get_db
    begin
      sql = <<-SQL
        SELECT r.symbol_name, r.start_line, r.end_line, f.file_path
        FROM "references" r
        JOIN files f ON r.file_id = f.id
        WHERE r.symbol_name = ?
      SQL
      
      references = db.execute(sql, name)
      { references: references }
    ensure
      db.close
    end
  end
end

class McpServer < Sinatra::Base
  def self.create_and_start(database_file, server_port = 65432, bind_address = '0.0.0.0')
    # Validate database file exists
    unless File.exist?(database_file)
      raise ArgumentError, "Database file does not exist: #{database_file}"
    end
    
    # Create a new instance to avoid conflicts with class variables
    app = self.new
    app.class.set :port, server_port
    app.class.set :bind, bind_address
    app.class.set :handler, MCPHandler.new(database_file)
    
    # Start the server
    app.class.run!
  end

  def self.stop
    quit!
  end

  def handler
    settings.handler
  end

  def create_success_response(id, result)
    {
      jsonrpc: '2.0',
      result: result,
      id: id
    }.to_json
  end

  def create_error_response(id, code, message)
    {
      jsonrpc: '2.0',
      error: {
        code: code,
        message: message
      },
      id: id
    }.to_json
  end

  post '/' do
    content_type :json
    begin
      request_data = JSON.parse(request.body.read)
      id = request_data['id']
      method_name = request_data['method']
      params = request_data['params']

      unless handler.respond_to?(method_name)
        return create_error_response(id, -32601, 'Method not found')
      end

      if params.is_a?(Hash)
        result = handler.send(method_name, **params)
      else
        result = handler.send(method_name, *params)
      end

      create_success_response(id, result)
    rescue JSON::ParserError
      create_error_response(nil, -32700, 'Parse error')
    rescue ArgumentError => e
      create_error_response(id, -32602, "Invalid params: #{e.message}")
    rescue => e
      create_error_response(id, -32603, "Internal error: #{e.message}")
    end
  end

  get '/' do
    content_type :json
    handler.status.to_json
  end

  def self.start
    run!
  end

  def self.stop
    quit!
  end
end
