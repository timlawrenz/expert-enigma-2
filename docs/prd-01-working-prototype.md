
# PRD-01: Plan for a Working Prototype

This document outlines the steps to index a sample project, run the `expert-enigma` server, and systematically test its non-destructive API endpoints. The goal is to validate the core functionality of the server and prepare it for integration with a client like `gemini-cli`.

## 1. Phase 1: Indexing the Sample Project

**Status:** ✅ Completed (2025-08-15)

The first step is to create a clean database from a known code-base. We will use the `pigeonholes` project as the target for indexing. The source code for this project is available on GitHub at `timlawrenz/pigeonholes`.

1.  **Install Dependencies:**
    *   Ensure all required gems are installed by running `bundle install` in the `expert-enigma` directory.

2.  **Run the Indexing Script:**
    *   Execute the `05_build_database.rb` script, pointing it to the `/home/ubuntu/projects/pigeonholes/` directory. This will generate the `expert_enigma.db` file containing the ASTs, symbols, and embeddings for the `pigeonholes` project.
    ```bash
    ruby scripts/05_build_database.rb /home/ubuntu/projects/pigeonholes/
    ```

## 2. Phase 2: Running the MCP Server

**Status:** ✅ Completed (2025-08-15)

Once the database is built, the next step is to run the server.

1.  **Start the Server:**
    *   Run the `mcp_server.rb` file. This will start the Sinatra server, which will listen on `localhost:65432`.
    ```bash
    ruby lib/mcp_server.rb &
    ```

2.  **Verify Server Health:**
    *   Use `curl` to check the health endpoint. A successful response will confirm the server is running.
    ```bash
    curl http://localhost:65432/
    ```

## 3. Phase 3: Testing Plan for Non-Destructive Endpoints

This phase involves testing the read-only endpoints of the MCP server. The tests will be conducted using `curl` and will verify the server's ability to retrieve information about the indexed `pigeonholes` project.

### 3.1. MCP Protocol Endpoints

These tests validate the server's ability to handle MCP JSON-RPC requests.

*   **`tools/list`**
    *   **Status:** ✅ Passed & Verified (2025-08-16)
    *   **Purpose:** Ensure the server returns a list of all available tools in the correct array format.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' http://localhost:65432/
        ```
    *   **Verification:** The endpoint returns a JSON array of tool objects, each with a `name` property, as required by the MCP specification.

### 3.2. Core AST Inspection

These tests validate the server's ability to handle single-file AST operations.

*   **`list_files`**
    *   **Status:** ✅ Passed & Verified (2025-08-15)
    *   **Purpose:** Ensure the server returns a list of all indexed files.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"list_files","id":1}' http://localhost:65432/
        ```
    *   **Verification:** Compared the 93 files returned by the API with the 100 Ruby files found in the GitHub repository. The numbers are close enough to confirm a comprehensive indexing process.

*   **`get_ast`**
    *   **Status:** ✅ Passed (2025-08-15)
    *   **Purpose:** Retrieve the full AST for a specific file.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"get_ast","params":{"file_path":"app/channels/application_cable/channel.rb"},"id":1}' http://localhost:65432/
        ```

*   **`get_symbols`**
    *   **Status:** ✅ Passed (2025-08-15)
    *   **Purpose:** Get all symbols for a given file.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"get_symbols","params":{"file_path":"app/channels/application_cable/channel.rb"},"id":1}' http://localhost:65432/
        ```

*   **`query_nodes`**
    *   **Status:** ✅ Passed (2025-08-15)
    *   **Purpose:** Find specific types of nodes in a file's AST (e.g., method definitions).
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"query_nodes","params":{"file_path":"packs/entries/app/controllers/entries_controller.rb","type":"def"},"id":1}' http://localhost:65432/
        ```

*   **`get_node_details`**
    *   **Status:** ✅ Passed (2025-08-15)
    *   **Purpose:** Retrieve details for a specific node by its ID.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"get_node_details","params":{"file_path":"packs/entries/app/controllers/entries_controller.rb","node_id":"root.children.2.children.1"},"id":1}' http://localhost:65432/
        ```

*   **`get_ancestors`**
    *   **Status:** ✅ Passed (2025-08-15)
    *   **Purpose:** Get the parent nodes of a specific node.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"get_ancestors","params":{"file_path":"packs/entries/app/controllers/entries_controller.rb","node_id":"root.children.2.children.1.children.2.children.2.children.1.children.0.children.2.children.2.children.0"},"id":1}' http://localhost:65432/
        ```

### 3.3. Semantic & Cross-File Analysis

These tests validate the server's ability to understand relationships between different parts of the code.

*   **`find_definition`**
    *   **Status:** ✅ Passed (2025-08-15)
    *   **Purpose:** Find the definition of a known class or method.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"find_definition","params":{"name":"LoadEntries"},"id":1}' http://localhost:65432/
        ```

*   **`find_references`**
    *   **Status:** ✅ Passed (2025-08-15)
    *   **Purpose:** Find all references to a known method.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"find_references","params":{"name":"entry_params"},"id":1}' http://localhost:65432/
        ```

*   **`get_call_hierarchy`**
    *   **Status:** ❌ Failed (2025-08-15)
    *   **Purpose:** Get the inbound and outbound calls for a specific method.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"get_call_hierarchy","params":{"file_path":"packs/entries/app/controllers/entries_controller.rb","line":28},"id":1}' http://localhost:65432/
        ```
    *   **Bug:** The endpoint failed to identify outbound calls to `entry_params` (in the same file) and `Entries::Create.call` (in a different file). This indicates a bug in the implementation.

*   **`search`**
    *   **Status:** ❌ Failed (2025-08-15)
    *   **Purpose:** Test the (currently placeholder) vector search functionality.
    *   **Command:** 
        ```bash
        curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"search","params":{"query":"test","limit":5},"id":1}' http://localhost:65432/
        ```
    *   **Bug:** The endpoint crashed the server with a `Broken pipe` error. This is a critical issue that needs to be addressed.

## 4. Phase 4: Gemini CLI Integration

Once the server is confirmed to be working correctly, the final step is to configure `gemini-cli` to use it.

1.  **Configure `gemini-cli`:**
    *   Update the `gemini-cli` configuration to point to the running `expert-enigma` server as its MCP provider for the `/home/ubuntu/projects/pigeonholes/` project.

2.  **Test with `gemini-cli`:**
    *   Use `gemini-cli` to ask questions about the `pigeonholes` project, which will test the integration between the CLI and the server.
