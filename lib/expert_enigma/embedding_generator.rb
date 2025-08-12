# frozen_string_literal: true

require 'onnxruntime'
require 'json'
require_relative 'ast_processor'

module ExpertEnigma
  # Generates embeddings for Ruby method ASTs using a pre-trained ONNX model.
  class EmbeddingGenerator
    def initialize(model_path = 'models/gnn_encoder.onnx')
      raise "Model file not found: #{model_path}" unless File.exist?(model_path)
      @model = OnnxRuntime::Model.new(model_path)
      @converter = ASTGraphConverter.new
    end

    def generate(ast_json)
      ast_hash = JSON.parse(ast_json)
      graph = @converter.parse_ast_hash(ast_hash)
      
      num_nodes = graph[:num_nodes]
      return nil if num_nodes == 0

      batch = Array.new(num_nodes, 0)
      
      inputs = {
        'x' => graph[:x],
        'edge_index' => graph[:edge_index],
        'batch' => batch
      }

      outputs = @model.predict(inputs)
      
      outputs['embedding']
    end
  end
end
