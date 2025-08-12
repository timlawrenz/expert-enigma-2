# frozen_string_literal: true

require "parser/current"
require "json"

module ExpertEnigma
  # Encodes AST node types into feature vectors.
  class ASTNodeEncoder
    def initialize
      # Vocabulary of AST node types from the parser gem
      @node_types = %i[
        def defs args arg begin end lvasgn ivasgn gvasgn
        cvasgn send block if unless while until for case
        when rescue ensure retry break next redo return
        yield super zsuper lambda proc and or not true
        false nil self int float str sym regexp array
        hash pair splat kwsplat block_pass const cbase
        lvar ivar gvar cvar casgn masgn mlhs op_asgn
        and_asgn or_asgn back_ref nth_ref class sclass module
        defined? alias undef range irange erange regopt
      ].map(&:to_s)
      @type_to_idx = @node_types.each_with_index.to_h
      @unknown_idx = @node_types.size
      @vocab_size = @node_types.size + 1
    end

    def encode_node_type(node_type)
      @type_to_idx.fetch(node_type.to_s, @unknown_idx)
    end

    def create_node_features(node_type)
      features = Array.new(@vocab_size, 0.0)
      idx = encode_node_type(node_type)
      features[idx] = 1.0
      features
    end

    attr_reader :vocab_size
  end

  # Converts an AST into a graph representation.
  class ASTGraphConverter
    def initialize
      @node_encoder = ASTNodeEncoder.new
      reset
    end

    def reset
      @nodes = []
      @edges = []
      @node_count = 0
    end

    def parse_ast_hash(ast_hash)
      reset
      process_node_hash(ast_hash)
      
      # Handle cases with no edges
      edge_index = @edges.empty? ? [[], []] : @edges.transpose

      {
        x: @nodes,
        edge_index: edge_index,
        num_nodes: @node_count
      }
    end

    private

    def process_node_hash(node, parent_idx = nil)
      return unless node.is_a?(Hash) && node.key?('type')

      current_idx = @node_count
      @node_count += 1

      features = @node_encoder.create_node_features(node['type'])
      @nodes << features

      @edges << [parent_idx, current_idx] if parent_idx

      node['children']&.each do |child|
        process_node_hash(child, current_idx)
      end
    end
  end
end
