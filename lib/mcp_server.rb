require 'sqlite3'
require 'json'
require_relative 'expert_enigma/ast_explorer'

DB_FILE = File.expand_path('../../expert_enigma.db', __FILE__)

# MCP Handler class containing all tool methods
class MCPHandler
  # --- Database Connection ---
  def get_db
    db = SQLite3::Database.new(DB_FILE, readonly: true)
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
      symbols = db.execute("SELECT name, type, scope, start_line, end_line FROM symbols WHERE file_id = (SELECT id FROM files WHERE file_path = ?)", [file_path])
      { symbols: symbols }
    ensure
      db.close
    end
  end

  # Search for methods using vector similarity
  def search(query, limit = 10)
    raise ArgumentError, 'Missing required parameter: query' unless query

    # --- Placeholder for Query Embedding ---
    # In a real implementation, we would generate an embedding for the query text.
    # For now, we'll generate a random vector of the correct dimension (64).
    query_embedding = Array.new(64) { rand(-1.0..1.0) }
    # --- End Placeholder ---

    db = get_db
    db.enable_load_extension(true)
    
    # Load the VSS extension
    vector_lib_path = File.expand_path('../../vendor/sqlite-vss/vector0.so', __FILE__)
    vss_lib_path = File.expand_path('../../vendor/sqlite-vss/vss0.so', __FILE__)
    db.load_extension(vector_lib_path)
    db.load_extension(vss_lib_path)

    begin
      # Find the k-nearest neighbors
      sql = <<-SQL
        SELECT
          s.name,
          s.start_line,
          s.end_line,
          f.file_path,
          e.distance
        FROM symbol_embeddings e
        JOIN symbols s ON s.id = e.rowid
        JOIN files f ON s.file_id = f.id
        WHERE vss_search(e.embedding, ?)
        ORDER BY e.distance
        LIMIT ?
      SQL

      results = db.execute(sql, JSON.generate(query_embedding), limit)
      { results: results }
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
        raise StandardError, 'File not found or not indexed'
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
        raise StandardError, 'File not found or not indexed'
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
          raise StandardError, "Node with id '#{node_id}' not found in file '#{file_path}'"
        end
      else
        raise StandardError, "File not found or not indexed"
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
        raise StandardError, "File not found or not indexed"
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

  # Get the call hierarchy for a method
  def get_call_hierarchy(file_path, line)
    raise ArgumentError, 'Missing required parameters: file_path and line' unless file_path && line

    db = get_db
    begin
      # Find the method at the given location
      method = db.get_first_row(
        "SELECT * FROM symbols WHERE file_id = (SELECT id FROM files WHERE file_path = ?) AND start_line <= ? AND end_line >= ? AND type IN ('method', 'singleton_method') ORDER BY (end_line - start_line) ASC LIMIT 1",
        [file_path, line, line]
      )

      unless method
        raise StandardError, "No method found at #{file_path}:#{line}"
      end

      # Get inbound calls (callers)
      inbound_sql = <<-SQL
        SELECT r.symbol_name, r.start_line, r.end_line, f.file_path
        FROM "references" r
        JOIN files f ON r.file_id = f.id
        WHERE r.symbol_name = ?
      SQL
      inbound_calls = db.execute(inbound_sql, [method['name']])

      # Get outbound calls (callees)
      outbound_calls = []
      if method['ast_json']
        method_ast = JSON.parse(method['ast_json'])
        explorer = ExpertEnigma::ASTExplorer.new(method_ast)
        send_nodes = explorer.find_outbound_calls(method_ast)
        
        send_nodes.each do |node|
          # This is a simplified representation. A real implementation would
          # try to resolve the definition of the called method.
          outbound_calls << {
            name: node['children'][1].to_s,
            # Location would require parsing the AST node's loc info, which we don't store yet.
          }
        end
      end

      {
        method: { name: method['name'], file_path: file_path, line: method['start_line'] },
        inbound_calls: inbound_calls,
        outbound_calls: outbound_calls.uniq # Uniq to remove duplicate calls
      }

    ensure
      db.close
    end
  end
end

# --- Server Setup ---
# Create a simple JSON-RPC 2.0 server using WEBrick
require 'webrick'
require 'json'

class JSONRPCServer
  def initialize(handler, port, host)
    @handler = handler
    @port = port
    @host = host
  end

  def start
    server = WEBrick::HTTPServer.new(
      :Port => @port,
      :BindAddress => @host,
      :Logger => WEBrick::Log.new(STDERR, WEBrick::Log::INFO),
      :AccessLog => []
    )

    server.mount_proc '/' do |req, res|
      handle_request(req, res)
    end

    trap('INT') { server.shutdown }
    server.start
  end

  private

  def handle_request(req, res)
    res['Content-Type'] = 'application/json'
    
    if req.request_method == 'POST'
      begin
        request_data = JSON.parse(req.body)
        response = process_jsonrpc_request(request_data)
        res.body = JSON.generate(response)
      rescue JSON::ParserError
        res.body = JSON.generate(create_error_response(nil, -32700, 'Parse error'))
      rescue => e
        res.body = JSON.generate(create_error_response(nil, -32603, "Internal error: #{e.message}"))
      end
    elsif req.request_method == 'GET' && req.path == '/'
      # Simple status endpoint for compatibility
      res.body = JSON.generate({ status: 'ok', message: 'Expert Enigma MCP Server is running.' })
    else
      res.status = 405
      res.body = JSON.generate(create_error_response(nil, -32601, 'Method not found'))
    end
  end

  def process_jsonrpc_request(request)
    # Validate JSON-RPC 2.0 format
    unless request['jsonrpc'] == '2.0' && request['method']
      return create_error_response(request['id'], -32600, 'Invalid Request')
    end

    method_name = request['method']
    params = request['params'] || []
    id = request['id']

    # Check if method exists
    unless @handler.respond_to?(method_name)
      return create_error_response(id, -32601, 'Method not found')
    end

    begin
      # Call the method with parameters
      if params.is_a?(Array)
        result = @handler.send(method_name, *params)
      elsif params.is_a?(Hash)
        result = @handler.send(method_name, **params)
      else
        result = @handler.send(method_name)
      end

      # Return success response
      create_success_response(id, result)
    rescue ArgumentError => e
      create_error_response(id, -32602, "Invalid params: #{e.message}")
    rescue => e
      # Check if it's a Jimson error (for compatibility with our error handling)
      if e.class.name.include?('Jimson')
        error_code = case e.class.name
        when /InvalidParams/
          -32602
        when /InternalError/
          -32603
        else
          -32603
        end
        create_error_response(id, error_code, e.message)
      else
        create_error_response(id, -32603, "Internal error: #{e.message}")
      end
    end
  end

  def create_success_response(id, result)
    {
      jsonrpc: '2.0',
      result: result,
      id: id
    }
  end

  def create_error_response(id, code, message)
    {
      jsonrpc: '2.0',
      error: {
        code: code,
        message: message
      },
      id: id
    }
  end
end

handler = MCPHandler.new
server = JSONRPCServer.new(handler, 65432, '0.0.0.0')

puts "Expert Enigma MCP Server starting on port 65432"
server.start
