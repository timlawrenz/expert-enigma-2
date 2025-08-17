# PRD-02: Refactor MCP Server with Jimson Gem

## 1. Objective

To improve the stability, maintainability, and protocol compliance of the `mcp_server.rb` by refactoring it to use the `jimson` Ruby gem, a dedicated library for JSON-RPC 2.0.

## 2. Background

The current MCP server is implemented from scratch using Sinatra. While functional, it relies on manual parsing of JSON-RPC requests and manual formatting of responses. This approach is error-prone and can lead to subtle deviations from the JSON-RPC 2.0 specification.

The `jimson` gem is a mature and well-tested library that handles the protocol-level complexities, allowing our code to focus solely on the business logic of the tools. Adopting it will provide a more robust foundation for the server.

## 3. Scope

### In Scope

*   Integrating the `jimson` gem into the project's `Gemfile`.
*   Replacing the existing Sinatra-based request/response handling in `lib/mcp_server.rb` with a `Jimson::Server`.
*   Adapting the existing tool methods (e.g., `list_files`, `get_symbols`) to be exposed as RPC methods through Jimson.
*   Ensuring the refactored server passes all existing and future end-to-end tests.

### Out of Scope

*   Adding new tool functionalities.
*   Changing the underlying logic of the existing tools.
*   Modifying the database schema or queries.

## 4. Implementation Plan

1.  **Add Dependency:** Add `gem 'jimson'` to the `Gemfile`.
2.  **Install Gem:** Run `bundle install` to install the new dependency.
3.  **Create Handler Class:** Create a new handler class within `lib/mcp_server.rb` that will contain the logic for all the tool methods. This separates the RPC logic from the server setup.
4.  **Migrate Tool Logic:** Move the implementation of each tool (e.g., `list_files`, `get_symbols`) into methods within the new handler class. The database connection will be passed to or created by the handler as needed.
5.  **Instantiate Jimson Server:** Replace the Sinatra application with an instance of `Jimson::Server`. The server will be configured to use the newly created handler class.
6.  **Start the Server:** The main execution block will start the Jimson server, making it listen on the same port as the original server (65432).

## 5. Acceptance Criteria

*   The server starts without errors.
*   The server correctly handles all JSON-RPC 2.0 requests for the defined tool methods.
*   The server responds with valid JSON-RPC 2.0 success and error objects.
*   All tool methods (`list_files`, `get_symbols`, etc.) are accessible via RPC calls and return the same results as the original implementation.
*   The server successfully passes a suite of end-to-end tests executed by the yet-to-be-developed `mcp_client.rb`.
*   The server correctly handles invalid requests (e.g., method not found, invalid parameters) by returning appropriate JSON-RPC error codes.
