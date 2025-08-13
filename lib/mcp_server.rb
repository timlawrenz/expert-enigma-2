require 'sinatra'
require 'sqlite3'
require 'json'

# Set server port according to MCP standards
set :port, 65432
set :bind, '0.0.0.0'

DB_FILE = File.expand_path('../../expert_enigma.db', __FILE__)

# --- Database Connection ---
def get_db
  db = SQLite3::Database.new(DB_FILE, readonly: true)
  db.results_as_hash = true
  db
end

# --- MCP Endpoints ---

# Simple root path to confirm server is running
get '/' do
  content_type :json
  { status: 'ok', message: 'Expert Enigma MCP Server is running.' }.to_json
end

# List all indexed files
get '/list_files' do
  content_type :json
  db = get_db
  begin
    files = db.execute("SELECT DISTINCT file_path FROM files ORDER BY file_path").map { |row| row['file_path'] }
    { files: files }.to_json
  ensure
    db.close
  end
end

# Get all symbols (methods) for a given file
# Get all symbols (methods) for a given file
get '/get_symbols' do
  content_type :json
  file_path = params['file_path']

  unless file_path
    status 400
    return { error: 'Missing required parameter: file_path' }.to_json
  end

  db = get_db
  begin
    symbols = db.execute("SELECT name, type, scope, start_line, end_line FROM symbols WHERE file_id = (SELECT id FROM files WHERE file_path = ?)", [file_path])
    { symbols: symbols }.to_json
  ensure
    db.close
  end
end

# Search for methods using vector similarity
get '/search' do
  content_type :json
  query = params['query']
  limit = params.fetch('limit', 10).to_i

  unless query
    status 400
    return { error: 'Missing required parameter: query' }.to_json
  end

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
    { results: results }.to_json
  ensure
    db.close
  end
end

require_relative 'expert_enigma/ast_explorer'

# ... (other setup code)

# Get the full AST for a given file
get '/get_ast' do
  content_type :json
  file_path = params['file_path']

  unless file_path
    status 400
    return { error: 'Missing required parameter: file_path' }.to_json
  end

  db = get_db
  begin
    result = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)
    if result
      # The AST is stored as a JSON string. We send it directly.
      result['ast_json']
    else
      status 404
      { error: 'File not found or not indexed' }.to_json
    end
  ensure
    db.close
  end
end

# Query for nodes within a file's AST
get '/query_nodes' do
  content_type :json
  file_path = params['file_path']
  node_type = params['type']

  unless file_path && node_type
    status 400
    return { error: 'Missing required parameters: file_path and type' }.to_json
  end

  db = get_db
  begin
    ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
    
    if ast_json
      ast_hash = JSON.parse(ast_json)
      explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
      nodes = explorer.find_nodes_by_type(node_type)
      { nodes: nodes }.to_json
    else
      status 404
      { error: 'File not found or not indexed' }.to_json
    end
  ensure
    db.close
  end
end

# Get details for a specific node in a file
get '/get_node_details' do
  content_type :json
  file_path = params['file_path']
  node_id = params['node_id']

  unless file_path && node_id
    status 400
    return { error: 'Missing required parameters: file_path and node_id' }.to_json
  end

  db = get_db
  begin
    ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
    
    if ast_json
      ast_hash = JSON.parse(ast_json)
      explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
      node = explorer.find_node_by_id(node_id)
      
      if node
        { node: node }.to_json
      else
        status 404
        { error: "Node with id '#{node_id}' not found in file '#{file_path}'" }.to_json
      end
    else
      status 404
      { error: "File not found or not indexed" }.to_json
    end
  ensure
    db.close
  end
end

# Get ancestors of a specific node in a file
get '/get_ancestors' do
  content_type :json
  file_path = params['file_path']
  node_id = params['node_id']

  unless file_path && node_id
    status 400
    return { error: 'Missing required parameters: file_path and node_id' }.to_json
  end

  db = get_db
  begin
    ast_json = db.get_first_row("SELECT ast_json FROM files WHERE file_path = ?", file_path)&.dig('ast_json')
    
    if ast_json
      ast_hash = JSON.parse(ast_json)
      explorer = ExpertEnigma::ASTExplorer.new(ast_hash)
      ancestors = explorer.get_ancestors(node_id)
      { ancestors: ancestors }.to_json
    else
      status 404
      { error: "File not found or not indexed" }.to_json
    end
  ensure
    db.close
  end
end

# Find the definition of a symbol
get '/find_definition' do
  content_type :json
  name = params['name']

  unless name
    status 400
    return { error: 'Missing required parameter: name' }.to_json
  end

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
    { definitions: definitions }.to_json
  ensure
    db.close
  end
end

# Find all references to a symbol
get '/find_references' do
  content_type :json
  name = params['name']

  unless name
    status 400
    return { error: 'Missing required parameter: name' }.to_json
  end

  db = get_db
  begin
    sql = <<-SQL
      SELECT r.symbol_name, r.start_line, r.end_line, f.file_path
      FROM "references" r
      JOIN files f ON r.file_id = f.id
      WHERE r.symbol_name = ?
    SQL
    
    references = db.execute(sql, name)
    { references: references }.to_json
  ensure
    db.close
  end
end

# Get the call hierarchy for a method
get '/get_call_hierarchy' do
  content_type :json
  file_path = params['file_path']
  line = params['line']&.to_i

  unless file_path && line
    status 400
    return { error: 'Missing required parameters: file_path and line' }.to_json
  end

  db = get_db
  begin
    # Find the method at the given location
    method = db.get_first_row(
      "SELECT * FROM symbols WHERE file_id = (SELECT id FROM files WHERE file_path = ?) AND start_line <= ? AND end_line >= ? AND type IN ('method', 'singleton_method') ORDER BY (end_line - start_line) ASC LIMIT 1",
      [file_path, line, line]
    )

    unless method
      status 404
      return { error: "No method found at #{file_path}:#{line}" }.to_json
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
    }.to_json

  ensure
    db.close
  end
end

puts "Expert Enigma MCP Server starting on port #{settings.port}"
