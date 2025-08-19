# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'parser/current'
require 'fileutils'
require 'pathname'
require_relative 'embedding_generator'

module ExpertEnigma
  # Builds a database index for a Ruby project directory
  class IndexBuilder
    def initialize(target_dir, db_file, model_file = nil)
      @target_dir = File.expand_path(target_dir)
      @db_file = File.expand_path(db_file)
      @model_file = model_file || File.expand_path('../../models/gnn_encoder.onnx', __dir__)
    end

    def build_index
      validate_inputs
      setup_output_directory
      
      puts "Starting indexing process for: #{@target_dir}"
      puts "Database will be created at: #{@db_file}"
      
      db = setup_database
      embedding_generator = create_embedding_generator
      
      prepare_statements(db)
      process_ruby_files(db, embedding_generator)
      
      puts "Database build process complete."
      db.close
    end

    private

    def validate_inputs
      unless File.directory?(@target_dir)
        raise ArgumentError, "Target directory does not exist or is not a directory: #{@target_dir}"
      end
    end

    def setup_output_directory
      db_dir = File.dirname(@db_file)
      FileUtils.mkdir_p(db_dir) unless File.directory?(db_dir)
    end

    def setup_database
      FileUtils.rm_f(@db_file)
      db = SQLite3::Database.new(@db_file)
      
      # Try to load extensions, but continue without them if they fail
      begin
        db.enable_load_extension(true)
        vector_lib_path = File.expand_path('../../vendor/sqlite-vss/vector0', __dir__)
        vss_lib_path = File.expand_path('../../vendor/sqlite-vss/vss0', __dir__)
        
        db.load_extension(vector_lib_path)
        db.load_extension(vss_lib_path)
        @has_vss_extensions = true
        puts "VSS extensions loaded successfully."
      rescue => e
        puts "Warning: Could not load VSS extensions (#{e.message}). Continuing without vector search support."
        @has_vss_extensions = false
      end

      puts "Creating database schema..."
      create_schema(db)
      puts "Schema created."
      db
    end

    def create_schema(db)
      schema_sql = <<-SQL
        CREATE TABLE IF NOT EXISTS files (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_path TEXT NOT NULL UNIQUE,
          ast_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS symbols (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          scope TEXT NOT NULL,
          start_line INTEGER NOT NULL,
          end_line INTEGER NOT NULL,
          source_code TEXT,
          ast_json TEXT,
          FOREIGN KEY (file_id) REFERENCES files (id)
        );

        CREATE TABLE IF NOT EXISTS "references" (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_id INTEGER NOT NULL,
          symbol_name TEXT NOT NULL,
          start_line INTEGER NOT NULL,
          end_line INTEGER NOT NULL,
          FOREIGN KEY (file_id) REFERENCES files (id)
        );
      SQL
      
      if @has_vss_extensions
        schema_sql += <<-SQL
          CREATE VIRTUAL TABLE IF NOT EXISTS symbol_embeddings USING vss0(
              embedding(64)
          );
        SQL
      end
      
      db.execute_batch(schema_sql)
    end

    def create_embedding_generator
      if File.exist?(@model_file)
        ExpertEnigma::EmbeddingGenerator.new(@model_file)
      else
        puts "Warning: Model file not found at #{@model_file}. Skipping embedding generation."
        nil
      end
    end

    def prepare_statements(db)
      @insert_file_stmt = db.prepare("INSERT INTO files (file_path, ast_json) VALUES (?, ?)")
      @insert_symbol_stmt = db.prepare(
        "INSERT INTO symbols (file_id, name, type, scope, start_line, end_line, source_code, ast_json) 
         VALUES (:file_id, :name, :type, :scope, :start_line, :end_line, :source_code, :ast_json)"
      )
      @insert_ref_stmt = db.prepare(
        "INSERT INTO \"references\" (file_id, symbol_name, start_line, end_line) 
         VALUES (:file_id, :symbol_name, :start_line, :end_line)"
      )
      if @has_vss_extensions
        @insert_embedding_stmt = db.prepare("INSERT INTO symbol_embeddings (rowid, embedding) VALUES (?, ?)")
      end
    end

    def process_ruby_files(db, embedding_generator)
      puts "Scanning for Ruby files in #{@target_dir}..."
      
      Dir.glob("#{@target_dir}/**/*.rb").each do |file_path|
        relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@target_dir)).to_s
        puts "Processing #{relative_path}..."
        
        begin
          source = File.read(file_path)
          ast = Parser::CurrentRuby.parse(source)
          next unless ast

          file_ast_json = ast_to_hash(ast).to_json
          @insert_file_stmt.execute(relative_path, file_ast_json)
          file_id = db.last_insert_row_id

          extractor = SymbolExtractor.new(file_id, relative_path)
          extractor.process(ast)

          extractor.symbols.each do |symbol_data|
            puts "  Inserting symbol: #{symbol_data[:name]} (#{symbol_data[:type]}) at line #{symbol_data[:start_line]}"
            @insert_symbol_stmt.execute(symbol_data)
            symbol_id = db.last_insert_row_id
            
            if @has_vss_extensions && embedding_generator && symbol_data[:ast_json]
              embedding = embedding_generator.generate(symbol_data[:ast_json])
              @insert_embedding_stmt.execute(symbol_id, JSON.generate(embedding)) if embedding
            end
          end

          extractor.references.each do |ref_data|
            @insert_ref_stmt.execute(ref_data)
          end
        rescue Parser::SyntaxError => e
          puts "  Skipping due to syntax error: #{e.message}"
        rescue => e
          puts "  An unexpected error occurred: #{e.message}"
        end
      end
    end

    def ast_to_hash(node)
      return node unless node.is_a?(Parser::AST::Node)
      {
        type: node.type,
        children: node.children.map { |child| ast_to_hash(child) }
      }
    end

    # SymbolExtractor class extracted from the original script
    class SymbolExtractor
      attr_reader :symbols, :references

      def initialize(file_id, file_path)
        @file_id = file_id
        @file_path = file_path
        @symbols = []
        @references = []
        @scope_stack = []
      end

      def process(ast)
        traverse(ast)
      end

      private

      def traverse(node)
        return unless node.is_a?(Parser::AST::Node)

        case node.type
        when :class
          name_node = node.children[0]
          class_name = name_node.children.last.to_s
          add_symbol(node, class_name, 'class')
          
          @scope_stack.push(class_name)
          node.children.each { |c| traverse(c) }
          @scope_stack.pop
        when :module
          name_node = node.children[0]
          module_name = name_node.children.last.to_s
          add_symbol(node, module_name, 'module')

          @scope_stack.push(module_name)
          node.children.each { |c| traverse(c) }
          @scope_stack.pop
        when :def
          method_name = node.children[0].to_s
          add_symbol(node, method_name, 'method')
          node.children.each { |c| traverse(c) }
        when :defs
          method_name = "self.#{node.children[1]}"
          add_symbol(node, method_name, 'singleton_method')
          node.children.each { |c| traverse(c) }
        when :const
          const_name = node.children[1].to_s
          add_reference(node, const_name)
          node.children.each { |c| traverse(c) }
        when :send
          method_name = node.children[1].to_s if node.children[1]
          add_reference(node, method_name) if method_name
          node.children.each { |c| traverse(c) }
        else
          node.children.each { |c| traverse(c) }
        end
      end

      def add_symbol(node, name, type)
        source_location = node.location
        start_line = source_location.line
        end_line = source_location.last_line

        begin
          source_code = source_location.expression.source
        rescue
          source_code = nil
        end

        scope = @scope_stack.join('::')
        scope = 'global' if scope.empty?

        symbol_data = {
          file_id: @file_id,
          name: name,
          type: type,
          scope: scope,
          start_line: start_line,
          end_line: end_line,
          source_code: source_code,
          ast_json: ast_to_hash(node).to_json
        }

        @symbols << symbol_data
      end

      def add_reference(node, symbol_name)
        return unless symbol_name

        source_location = node.location
        start_line = source_location.line
        end_line = source_location.last_line

        ref_data = {
          file_id: @file_id,
          symbol_name: symbol_name,
          start_line: start_line,
          end_line: end_line
        }

        @references << ref_data
      end

      def ast_to_hash(node)
        return node unless node.is_a?(Parser::AST::Node)
        {
          type: node.type,
          children: node.children.map { |child| ast_to_hash(child) }
        }
      end
    end
  end
end