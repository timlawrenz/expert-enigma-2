#!/usr/bin/env ruby
# Server launcher script to avoid Sinatra class method conflicts

require_relative 'mcp_server'

# Get arguments from environment or command line
db_file = ARGV[0] || ENV['EXPERT_ENIGMA_DB_FILE']
port = (ARGV[1] || ENV['EXPERT_ENIGMA_PORT'] || '65432').to_i

# Validate inputs
unless db_file && File.exist?(db_file)
  puts "Error: Database file not found: #{db_file}"
  exit(1)
end

# Configure and start server
puts "Starting MCP server on port #{port} with database #{db_file}"

class McpServerRunner < McpServer
end

McpServerRunner.set :port, port
McpServerRunner.set :bind, '0.0.0.0'
McpServerRunner.set :handler, MCPHandler.new(db_file)
McpServerRunner.run!