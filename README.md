# expert-enigma: A GNN-Powered Model Context Protocol Server for Ruby

A next-generation, local-first Model Context Protocol (MCP) server for Ruby repositories. It uses Graph Neural Networks (GNNs) to provide LLMs and coding agents with a deep, structural understanding of code, far beyond simple text analysis.

## The Problem

Modern LLM-based coding agents are powerful, but they often lack a true understanding of a project's architecture. When analyzing dynamic languages like Ruby, they rely on text-based heuristics and miss the rich structural relationships within the code (inheritance, method calls, composition). This leads to shallow, context-poor responses.

## The Solution

This project provides a highly intelligent context server that speaks the standard MCP language. Instead of just parsing text, it transforms Ruby code into a graph and uses a Graph Neural Network to create sophisticated embeddings that capture the code's structure and intent.

The core innovation is leveraging the research and models from the **[jubilant-palm-tree](https://github.com/timlawrenz/jubilant-palm-tree)** project, which demonstrated that GNNs can learn meaningful representations of Ruby ASTs.

## Core Concepts

*   **AST to Graph Transformation:** Ruby files are parsed into Abstract Syntax Trees (ASTs), which are then converted into rich graph structures where nodes represent code entities (classes, methods) and edges represent their relationships (calls, inherits, includes).
*   **GNN-Powered Embeddings:** We use a pre-trained GNN model (in ONNX format) to generate vector embeddings for each code symbol. Unlike text embeddings, these vectors capture the *structural* similarity and complexity of the code, allowing for powerful semantic search.
*   **Lightweight & Local-First:** The entire engine is designed to run with minimal overhead on a developer's machine. It uses an embedded database solution (**SQLite** with the **`sqlite-vss`** extension for vector search) that requires no external services.

## Architecture & Implementation Details

The data pipeline is designed for a rich, offline-first experience:

`Ruby Files -> AST Parser -> Symbol/Reference Extractor -> GNN Inference (ONNX) -> SQLite DB -> MCP API -> LLM Agent`

### Key Components

*   **`scripts/05_build_database.rb`**: This is the main script for indexing a repository. It scans for Ruby files, extracts symbols and references, generates embeddings, and populates the SQLite database.
*   **`lib/expert_enigma/symbol_extractor.rb`**: A class that uses the `parser` gem to traverse the AST of a Ruby file and extract definitions (classes, modules, methods) and references (usages) of symbols.
*   **`lib/expert_enigma/embedding_generator.rb`**: This class loads the pre-trained GNN model (in `.onnx` format) and uses the `onnxruntime` gem to generate vector embeddings for method ASTs.
*   **`lib/expert_enigma/ast_explorer.rb`**: A utility class for querying and navigating the AST of a file, with methods to find nodes by type, ID, and to get ancestors.
*   **`lib/mcp_server.rb`**: A Sinatra-based web server that exposes the MCP API endpoints. It queries the SQLite database to provide information about the codebase.
*   **`expert_enigma.db`**: An SQLite database containing the indexed data for the repository, including file ASTs, symbols, references, and vector embeddings for methods.

## Progress & Implemented Features

The project has a functional core that successfully covers all planned features from the "Core AST Inspection" and "Semantic & Cross-File Analysis" categories.

### Completed

*   **Phase 1: Core Integration**
    *   [x] Port the graph and embedding generation logic from `jubilant-palm-tree`.
    *   [x] Set up the `SQLite` database schema (for symbols, files, relations).
    *   [x] Integrate `sqlite-vss` for vector storage and search.
*   **Phase 2: Indexer & API**
    *   [x] Build the main indexer process for full repository scans.
    *   [x] Implemented all core MCP API endpoints for inspection and analysis.

### Next Steps

*   [ ] **Phase 3: Stabilize & Refine Core Features**
    *   [ ] **Functional Search:** Replace the placeholder random vector in the `/search` endpoint with a real query embedding mechanism.
    *   [ ] **Robust VSS Loading:** Make the loading of the `sqlite-vss` extension portable by removing hardcoded paths.
    *   [ ] **Server Refactoring:** Refactor `mcp_server.rb` to reduce code duplication for database connections and AST loading.
*   [ ] **Phase 4: Code Transformation & Real-time Indexing**
    *   [ ] Implement the code transformation endpoints (`/replace_node_text`, etc.).
    *   [ ] Add a file watcher for real-time, incremental indexing.
*   [ ] **Phase 5: Tooling & DX**
    *   [ ] Create a simple CLI for starting the server and managing the index.
    *   [ ] Develop a GitHub Actions workflow for CI-based index generation.

## API Documentation

The server runs on `http://localhost:65432`. All endpoints return JSON.

| Endpoint | Description | Parameters | Example `curl` Command |
| :--- | :--- | :--- | :--- |
| **`GET /`** | Health check | None | `curl http://localhost:65432/` |
| **`GET /list_files`** | Lists all indexed files in the repository. | None | `curl http://localhost:65432/list_files` |
| **`GET /get_ast`** | Retrieves the full AST for a single file. | `file_path` (string) | `curl "http://localhost:65432/get_ast?file_path=test/test_file_1.rb"` |
| **`GET /get_symbols`** | Returns all symbols for a given file. | `file_path` (string) | `curl "http://localhost:65432/get_symbols?file_path=test/test_file_1.rb"` |
| **`GET /query_nodes`** | Finds nodes of a specific type in a file's AST. | `file_path`, `type` | `curl "http://localhost:65432/query_nodes?file_path=test/test_file_1.rb&type=def"` |
| **`GET /get_node_details`** | Retrieves details for a specific node by its ID. | `file_path`, `node_id` | `curl "http://localhost:65432/get_node_details?file_path=test/test_file_1.rb&node_id=root.children.0"`|
| **`GET /get_ancestors`** | Returns the ancestor nodes for a given node ID. | `file_path`, `node_id` | `curl "http://localhost:65432/get_ancestors?file_path=test/test_file_1.rb&node_id=root.children.0.children.2.children.0"` |
| **`GET /find_definition`** | Finds the definition of a symbol by name. | `name` (string) | `curl "http://localhost:65432/find_definition?name=MyClass"` |
| **`GET /find_references`** | Finds all references to a symbol by name. | `name` (string) | `curl "http://localhost:65432/find_references?name=my_method"` |
| **`GET /get_call_hierarchy`**| Gets inbound/outbound calls for a method. | `file_path`, `line` | `curl "http://localhost:65432/get_call_hierarchy?file_path=test/test_file_1.rb&line=3"` |
| **`GET /search`** | *Placeholder:* Vector search for methods. | `query`, `limit` | `curl "http://localhost:65432/search?query=database&limit=5"` |


## Testing Approach

The server's endpoints are tested using a set of controlled Ruby files in the `test/` directory. The testing process is as follows:

1.  **Create Test Files:** The `test/` directory contains Ruby files with a known structure of classes, modules, methods, and references.
2.  **Build Test Database:** The `scripts/05_build_database.rb` script is configured to scan only the `test/` directory, creating a clean `expert_enigma.db` with only the test data.
3.  **Verify with `curl`:** The MCP server is started, and `curl` commands are used to systematically test each endpoint against the known content of the test files, verifying the JSON output.

This approach ensures that the core functionality of the server is working as expected before moving on to more complex features.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.