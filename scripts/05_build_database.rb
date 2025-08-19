#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'parser/current'
require 'fileutils'
require 'pathname'
require_relative '../lib/expert_enigma/embedding_generator'

# --- Configuration ---
# If a directory is provided as a command-line argument, use it. Otherwise, default to the 'test' directory.
TARGET_DIR = ARGV[0] || File.expand_path('../test', __dir__)
DB_FILE = File.expand_path('../expert_enigma.db', __dir__)
MODEL_FILE = File.expand_path('../models/gnn_encoder.onnx', __dir__)

# --- Database Setup ---
def setup_database
  FileUtils.rm_f(DB_FILE)
  db = SQLite3::Database.new(DB_FILE)
  db.enable_load_extension(true)

  vector_lib_path = File.expand_path('../vendor/sqlite-vss/vector0.so', __dir__)
  vss_lib_path = File.expand_path('../vendor/sqlite-vss/vss0.so', __dir__)
  
  db.load_extension(vector_lib_path)
  db.load_extension(vss_lib_path)

  puts "Creating database schema..."
  db.execute_batch(<<-SQL
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

    CREATE VIRTUAL TABLE IF NOT EXISTS symbol_embeddings USING vss0(
        embedding(64)
    );
  SQL
  )
  puts "Schema created."
  db
end

# --- AST Processing ---
def ast_to_hash(node)
  return node unless node.is_a?(Parser::AST::Node)
  {
    type: node.type,
    children: node.children.map { |child| ast_to_hash(child) }
  }
end

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
      add_reference(node, node.children.last.to_s)
      node.children.each { |c| traverse(c) }
    when :send
      method_name = node.children[1].to_s
      add_reference(node, method_name)
      node.children.each { |c| traverse(c) }
    else
      node.children.each { |c| traverse(c) }
    end
  end

  def add_symbol(node, name, type)
    @symbols << {
      file_id: @file_id,
      name: name,
      type: type,
      scope: @scope_stack.join('::'),
      start_line: node.loc.line,
      end_line: node.loc.last_line,
      source_code: (type == 'method' || type == 'singleton_method') ? node.loc.expression.source : nil,
      ast_json: (type == 'method' || type == 'singleton_method') ? ast_to_hash(node).to_json : nil
    }
  end

  def add_reference(node, name)
    @references << {
      file_id: @file_id,
      symbol_name: name,
      start_line: node.loc.line,
      end_line: node.loc.last_line
    }
  end
end

# --- Main Execution ---
def main
  db = setup_database
  embedding_generator = ExpertEnigma::EmbeddingGenerator.new(MODEL_FILE)

  insert_file_stmt = db.prepare("INSERT INTO files (file_path, ast_json) VALUES (?, ?)")
  insert_symbol_stmt = db.prepare(
    "INSERT INTO symbols (file_id, name, type, scope, start_line, end_line, source_code, ast_json) 
     VALUES (:file_id, :name, :type, :scope, :start_line, :end_line, :source_code, :ast_json)"
  )
  insert_ref_stmt = db.prepare(
    "INSERT INTO \"references\" (file_id, symbol_name, start_line, end_line) 
     VALUES (:file_id, :symbol_name, :start_line, :end_line)"
  )
  insert_embedding_stmt = db.prepare("INSERT INTO symbol_embeddings (rowid, embedding) VALUES (?, ?)")

  puts "Scanning for Ruby files in #{TARGET_DIR}..."
  
  Dir.glob("#{TARGET_DIR}/**/*.rb").each do |file_path|
    relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(TARGET_DIR)).to_s
    puts "Processing #{relative_path}..."
    
    begin
      source = File.read(file_path)
      ast = Parser::CurrentRuby.parse(source)
      next unless ast

      file_ast_json = ast_to_hash(ast).to_json
      insert_file_stmt.execute(relative_path, file_ast_json)
      file_id = db.last_insert_row_id

      extractor = SymbolExtractor.new(file_id, relative_path)
      extractor.process(ast)

      extractor.symbols.each do |symbol_data|
        puts "  Inserting symbol: #{symbol_data[:name]} (#{symbol_data[:type]}) at line #{symbol_data[:start_line]}"
        insert_symbol_stmt.execute(symbol_data)
        symbol_id = db.last_insert_row_id
        
        if symbol_data[:ast_json]
          embedding = embedding_generator.generate(symbol_data[:ast_json])
          insert_embedding_stmt.execute(symbol_id, JSON.generate(embedding)) if embedding
        end
      end

      extractor.references.each do |ref_data|
        insert_ref_stmt.execute(ref_data)
      end
    rescue Parser::SyntaxError => e
      puts "  Skipping due to syntax error: #{e.message}"
    rescue => e
      puts "  An unexpected error occurred: #{e.message}"
    end
  end

  puts "Database build process complete."
  db.close
end

main if __FILE__ == $PROGRAM_NAME
