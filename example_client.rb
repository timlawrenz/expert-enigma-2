#!/usr/bin/env ruby

# Example usage of the MCP Client
# This script demonstrates how to use the MCPClient to interact with the Expert Enigma MCP Server

require_relative 'lib/mcp_client'

begin
  # Initialize the client with the server URL
  client = MCPClient.new('http://localhost:65432')
  
  puts "Expert Enigma MCP Client Example"
  puts "================================"
  
  # Check server status
  puts "\n1. Server Status:"
  status = client.status
  puts "   #{status['message']}"
  
  # List all indexed files
  puts "\n2. Available Files:"
  files = client.list_files
  files['files'].each { |file| puts "   - #{file}" }
  
  # Get symbols for the first file
  if files['files'] && !files['files'].empty?
    file_path = files['files'].first
    puts "\n3. Symbols in #{file_path}:"
    symbols = client.get_symbols(file_path)
    symbols['symbols'].each do |symbol|
      puts "   - #{symbol['name']} (#{symbol['type']}) at lines #{symbol['start_line']}-#{symbol['end_line']}"
    end
    
    # Find references to a symbol if available
    if symbols['symbols'] && !symbols['symbols'].empty?
      symbol_name = symbols['symbols'].first['name']
      puts "\n4. References to '#{symbol_name}':"
      references = client.find_references(symbol_name)
      if references['references'].empty?
        puts "   No references found"
      else
        references['references'].each do |ref|
          puts "   - #{ref['file_path']}:#{ref['start_line']}"
        end
      end
    end
  end
  
  puts "\nExample completed successfully!"

rescue MCPClientError => e
  puts "Error: #{e.message}"
  puts "\nMake sure the MCP server is running on http://localhost:65432"
  puts "Start it with: ruby lib/mcp_server.rb"
  exit 1
rescue => e
  puts "Unexpected error: #{e.message}"
  exit 1
end