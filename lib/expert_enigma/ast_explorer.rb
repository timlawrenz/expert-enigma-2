# frozen_string_literal: true

module ExpertEnigma
  # Provides methods to explore and query an AST hash structure.
  class ASTExplorer
    def initialize(ast_hash)
      @ast = ast_hash
    end

    # Finds all nodes of a specific type in the AST.
    #
    # @param type [String] The node type to search for (e.g., 'def', 'send').
    # @return [Array<Hash>] A list of matching nodes, each with an 'id' and its content.
    def find_nodes_by_type(type)
      results = []
      traverse(@ast, 'root') do |node, id|
        results << { id: id, **node } if node['type'] == type
      end
      results
    end

    # Finds a single node by its ID path.
    #
    # @param id [String] The dot-separated path to the node.
    # @return [Hash, nil] The found node or nil.
    def find_node_by_id(id)
      path_parts = id.split('.')
      # Drop the 'root' part for traversal
      path_parts.shift if path_parts.first == 'root'
      
      current = @ast
      path_parts.each do |part|
        if part == 'children' && current.is_a?(Hash)
          current = current['children']
        elsif current.is_a?(Array) && part.match?(/^\d+$/)
          current = current[part.to_i]
        else
          # Invalid path part
          return nil
        end
      end
      current.is_a?(Hash) ? current : nil
    end

    # Gets the ancestor nodes for a given node ID.
    #
    # @param id [String] The ID of the node.
    # @return [Array<Hash>] An ordered list of ancestor nodes.
    def get_ancestors(id)
      ancestors = []
      path_parts = id.split('.')
      # Iterate up to the second to last part to get all parents
      (1...path_parts.length).each do |i|
        ancestor_id = path_parts[0...i].join('.')
        node = find_node_by_id(ancestor_id)
        ancestors << { id: ancestor_id, **node } if node
      end
      ancestors
    end

    # Finds all outbound calls (send nodes) within a given AST node.
    #
    # @param start_node [Hash] The AST node to start the search from.
    # @return [Array<Hash>] A list of 'send' nodes.
    def find_outbound_calls(start_node)
      results = []
      traverse(start_node, 'start') do |node, id|
        results << { id: id, **node } if node['type'] == 'send'
      end
      results
    end

    private

    # Recursively traverses the AST hash.
    #
    # @param node [Hash, Array, any] The current node or value to process.
    # @param path [String] The current path (ID) to the node.
    # @yield [node, id] Gives the current node and its ID to the block.
    def traverse(node, path, &block)
      case node
      when Hash
        if node.key?('type')
          yield(node, path)
          
          children = node['children']
          if children.is_a?(Array)
            children.each_with_index do |child, index|
              new_path = path.empty? ? "children.#{index}" : "#{path}.children.#{index}"
              traverse(child, new_path, &block)
            end
          end
        end
      when Array
        node.each_with_index do |element, index|
          new_path = path.empty? ? index.to_s : "#{path}.#{index}"
          traverse(element, new_path, &block)
        end
      end
    end
  end
end
