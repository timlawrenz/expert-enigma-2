# Category 1: Core AST Inspection (Single-File Focus)                                                                                                                                                                                                      10:41:09 [33/57]

These are the fundamental building blocks for working with a single file's AST.

* `get_ast(file_path)`
    * Purpose: Retrieves the full AST for a single specified file.
    * Returns: The root node of the tree, from which all other nodes can be traversed. The format would likely be a serialized tree structure (e.g., JSON).
    * Key Parameters: file_path.
* `query_nodes(file_path, query)`
    * Purpose: The primary workhorse function. It finds and returns a list of nodes within a single file's AST that match a specific query. This is like XPath or CSS selectors for code.
    * Returns: A list of matching nodes, each with a unique ID, its type, and source location (line/column).
    * Key Parameters: file_path, query (using a defined query language like Tree-sitter queries).
* `get_node_details(file_path, node_id)`
    * Purpose: Retrieves detailed information about a single, specific node.
    * Returns: An object containing the node's type (e.g., method_definition, string_literal), its exact source text, its start/end position, and the IDs of its parent and direct children.
    * Key Parameters: file_path, node_id.
* `get_ancestors(file_path, node_id)`
    * Purpose: Returns the chain of parent nodes from the specified node up to the root.
    * Returns: An ordered list of parent nodes.
    * Key Parameters: file_path, node_id.

# Category 2: Semantic & Cross-File Analysis

This is where the server's real power lies—understanding the relationships between nodes and across files. This requires the server to maintain a repository-wide index of symbols.

* `find_definition(file_path, position)`
    * Purpose: The classic "Go to Definition." Given a location in a file (e.g., where a variable or method is used), it finds where that symbol was originally defined.
    * Returns: The file path and position of the definition.
    * Key Parameters: file_path, position (line and column).
* `find_references(file_path, position)`
    * Purpose: The "Find All Usages" functionality. Given a location where a symbol is defined or used, it finds every other place in the repository that references it.
    * Returns: A list of locations (file path and position) where the symbol is used.
    * Key Parameters: file_path, position.
* `get_call_hierarchy(file_path, position)`
    * Purpose: For a given function definition, it finds all functions that call it (inbound calls) and all functions that it calls (outbound calls).
    * Returns: Two lists of locations: callers and callees.
    * Key Parameters: file_path, position.
* `resolve_import(file_path, import_node_id)`
    * Purpose: Given a node representing an import/require statement, it resolves the full path to the imported file or module.
    * Returns: The absolute file path of the resolved module.
    * Key Parameters: file_path, import_node_id.

# Category 3: Code Transformation (The "Write" API)

These functions would allow for safe, programmatic refactoring. They are the most powerful and would require careful design to ensure correctness.

* `replace_node_text(file_path, node_id, new_text)`
    * Purpose: Replaces the source text of a specific node with new text. The server would be responsible for re-parsing the change to ensure the resulting AST is still valid before committing the change.
    * Returns: The updated AST for the file and a confirmation of success/failure.
    * Key Parameters: file_path, node_id, new_text.
* `rename_symbol(file_path, position, new_name)`
    * Purpose: A high-level, safe refactoring command. It would use find_definition and find_references internally to rename a symbol across the entire repository.
    * Returns: A list of all files that were modified.
    * Key Parameters: file_path, position, new_name.
* `apply_transformation_plan(plan)`
    * Purpose: A transactional endpoint to perform a series of complex changes. This prevents leaving the codebase in a partially-refactored state. The plan would be a list of primitive operations (e.g., replace, delete, insert).
    * Returns: A status indicating whether the entire plan was successfully applied.
    * Key Parameters: plan (a JSON object describing all intended changes).

# Category 4: Server Management and Metadata

These functions are for managing the server itself.

* `get_supported_languages()`
    * Purpose: Lists the programming languages the server knows how to parse.
    * Returns: A list of language names (e.g., ruby, javascript, python).
* `get_server_status()`
    * Purpose: Provides metadata about the server's state.
    * Returns: Information like whether it's currently indexing, the last time it scanned the repository, and the total number of files indexed.
