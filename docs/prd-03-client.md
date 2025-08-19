# PRD-03: Create MCP Client for End-to-End Testing

## 1. Objective

To create a local MCP (Model Context Protocol) client that can communicate with the `mcp_server.rb` to perform end-to-end tests. This client is essential for verifying the server's functionality and ensuring it adheres to the expected protocol.

## 2. Background

To confidently test the MCP server, we need a client that can send valid requests and verify the server's responses. A dedicated client will allow us to create automated tests that cover all the server's functionalities, from the initial handshake to calling each specific tool.

Given the abandonment of the `jimson` gem for the server, the client will also be simplified to use Ruby's standard `net/http` and `json` libraries.

## 3. Scope

### In Scope

*   Creating a new file, `lib/mcp_client.rb`, to house the client.
*   Using the `net/http` and `json` libraries to handle the JSON-RPC 2.0 communication.
*   Implementing a class, `MCPClient`, that establishes a connection to the server.
*   Creating methods within the `MCPClient` class that correspond to each of the server's available tools (e.g., `list_files`, `get_symbols`).
*   The client will be designed to be used in automated test scripts.

### Out of Scope

*   A command-line interface (CLI) for interacting with the client.
*   A graphical user interface (GUI).
*   The implementation of the actual test suite.

## 4. Implementation Plan

1.  **Create File:** Create a new file at `lib/mcp_client.rb`.
2.  **Implement `MCPClient` Class:**
    *   The constructor (`initialize`) will take the server URL (e.g., `http://localhost:65432`) as an argument.
    *   A private method will handle the construction and sending of JSON-RPC requests using `Net::HTTP`.
    *   For each tool exposed by the server, a corresponding method will be created in the `MCPClient` class.
    *   Each method will call the remote server method, passing the required arguments.
    *   The methods will handle both successful responses and potential JSON-RPC errors returned by the server.

## 5. Acceptance Criteria

*   The `MCPClient` can successfully connect to a running `mcp_server.rb` instance.
*   The client can call each of the server's tool methods and receive a valid, parsed response.
*   The client correctly handles and reports JSON-RPC errors returned by the server.
*   The client can be easily instantiated and used from a separate Ruby script or test file.
