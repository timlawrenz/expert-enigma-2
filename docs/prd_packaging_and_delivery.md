# PRD: Packaging, Delivery, and Serving Strategy

## 1. Overview

This document outlines the requirements and proposed architecture for packaging, delivering, and serving the `expert-enigma` Model Context Protocol (MCP) server. The primary goal is to define a process that is simple, reliable, and easily automatable for both human developers and AI coding agents.

## 2. Target Personas

1.  **The Developer:** A software engineer working on a Ruby repository. They need a simple way to install, index their project, and run the MCP server locally.
2.  **The Automated Agent (e.g., Gemini):** An LLM-based coding agent. It requires a programmatic and deterministic way to start, stop, and interact with the MCP server for a given workspace.

## 3. Core Requirements & User Stories

### Packaging & Delivery

*   **As a Developer, I want** to install the server and all its dependencies with a single command, without worrying about system-level conflicts (especially for native extensions like `sqlite-vss` and `onnxruntime`).
*   **As an Automated Agent, I need** a self-contained, portable executable or image that guarantees a consistent runtime environment.

### Serving & Lifecycle Management

*   **As a Developer, I want** a simple Command Line Interface (CLI) to manage the server's lifecycle (index, start, stop, status).
*   **As a Developer, I want** to run the server against different projects on my machine without complex configuration.
*   **As an Automated Agent, I need** to programmatically start the server for a specific repository and receive a clear signal (e.g., a health check endpoint) when it is ready to accept requests.
*   **As an Automated Agent, I need** to manage the server as a background process that can be reliably terminated when my task is complete.

## 4. Proposed Architecture: Docker-First with a CLI

To meet the requirements for portability, dependency management, and ease of use, we propose a **Docker-first** distribution model. This approach encapsulates the entire Ruby environment, the ONNX runtime, and the `sqlite-vss` native extension into a single, immutable image.

A user-friendly Command Line Interface (CLI) will be the primary entry point for interacting with the server, whether run via Docker or locally.

### 4.1. Packaging: Docker Image

The application will be packaged as a Docker image.

*   **Base Image:** A standard Ruby image (e.g., `ruby:3.2-slim`).
*   **Dependencies:** The `Dockerfile` will handle:
    1.  Installing system dependencies (`build-essential`, `unzip`, `sqlite3`).
    2.  Setting up the `onnxruntime`.
    3.  Compiling the `sqlite-vss` extension.
    4.  Installing all required Gems via `bundle install`.
*   **Entrypoint:** The image's entry point will be a script that executes the CLI.

### 4.2. Delivery: Docker Hub

The official image will be published to Docker Hub, making it accessible via a standard `docker pull` command (e.g., `docker pull expert-enigma/server:latest`).

### 4.3. Serving: The `expert-enigma` CLI

A new CLI will be created to manage the server's state. This CLI will be the primary interface for both developers and agents.

**Proposed CLI Commands:**

| Command | Description | Example Usage |
| :--- | :--- | :--- |
| `expert-enigma index <path>` | Scans the repository at `<path>` and builds the `expert_enigma.db` file. This must be run before starting the server. | `expert-enigma index /path/to/my-project` |
| `expert-enigma start <path>` | Starts the MCP server for the project at `<path>`. Assumes the database has already been built. Exposes the server on `localhost:65432`. | `expert-enigma start /path/to/my-project` |
| `expert-enigma stop` | Stops the currently running server process. | `expert-enigma stop` |
| `expert-enigma status` | Reports whether the server is running and for which project. | `expert-enigma status` |
| `expert-enigma serve <path>` | A convenience command that runs `index` if the database is missing, and then immediately runs `start`. | `expert-enigma serve /path/to/my-project` |

## 5. Example Workflow (for an Automated Agent)

This workflow demonstrates how an agent would use the system within a target repository (`/path/to/target-repo`).

1.  **Pull the Image:**
    ```bash
    docker pull expert-enigma/server:latest
    ```

2.  **Index the Repository:** The agent mounts the target repository into the container and runs the `index` command. The database is created within the target repository's directory.
    ```bash
    docker run --rm -v "/path/to/target-repo:/app" expert-enigma/server:latest index /app
    ```

3.  **Start the Server:** The agent starts the server as a detached background process, mapping the required port.
    ```bash
    docker run -d -p 65432:65432 -v "/path/to/target-repo:/app" --name target-repo-mcp expert-enigma/server:latest start /app
    ```

4.  **Verify Health:** The agent polls the health check endpoint until it receives a `200 OK` response.
    ```bash
    curl --fail http://localhost:65432/
    ```

5.  **Interact with MCP:** The agent makes API calls to `localhost:65432` to analyze the code.

6.  **Shutdown:** Once finished, the agent stops and removes the container.
    ```bash
    docker stop target-repo-mcp && docker rm target-repo-mcp
    ```

## 6. Future Considerations

*   **Alternative Installation (RubyGems):** While Docker is primary, publishing a Gem would be beneficial for developers who prefer a non-Docker workflow. This would require providing clear instructions for installing the native dependencies.
*   **Configuration:** The server port and other settings could be configured via a `.expert_enigma.yml` file in the target repository or through environment variables.
*   **Incremental Indexing:** The `index` command could be enhanced with a `--watch` mode to support the real-time indexing feature mentioned in the `README.md`.
