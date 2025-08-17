# Model Context Protocol (MCP) Summary

## Overview

The Model Context Protocol (MCP) is an open, standardized protocol designed to facilitate communication between Large Language Models (LLMs) and development tools, such as IDEs. Its primary purpose is to provide a consistent way for an AI model to access information and perform actions within the user's codebase.

This allows the model to understand the project structure, read files, analyze code, and use other development tools in a structured manner, without needing a custom integration for every single tool or IDE.

## Core Concepts

### Transport Layer

*   **JSON-RPC 2.0:** MCP is built on top of the JSON-RPC 2.0 specification. This means all communication between the client (the AI model's environment) and the server (the IDE or tool) consists of JSON objects.
*   **Standard I/O:** The protocol typically uses standard input and standard output for communication, making it language and platform-agnostic.

### Communication Flow

1.  **Initialization (Handshake):** When the connection is established, the client sends an `initialize` request to the server. The server responds with its capabilities, such as the tools it supports. This is a critical first step to establish a common ground for communication.

2.  **Tool Discovery:** The client can request a list of available tools from the server using a `tools/list` request. The server returns a list of tool definitions, including their names, descriptions, and input schemas.

3.  **Tool Execution:** The client can request the execution of a specific tool by sending a `tools/call` request. This request includes the tool's name and the required arguments (as a JSON object). The server executes the tool and returns the result to the client.

## Standard Methods

While servers can implement any custom tools, the MCP specification defines a few standard methods that form the core of the protocol:

*   `initialize`: Establishes the connection and exchanges capabilities.
*   `tools/list`: Fetches the list of all available tools from the server.
*   `tools/call`: Executes a specific tool with given parameters.

## Message Structure

All messages adhere to the JSON-RPC 2.0 format.

### Request Object

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "get_symbols",
    "arguments": {
      "file_path": "lib/expert_enigma.rb"
    }
  }
}
```

### Response Object (Success)

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "symbols": [
      { "name": "ExpertEnigma", "type": "module" }
    ]
  }
}
```

### Response Object (Error)

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found"
  }
}
```
