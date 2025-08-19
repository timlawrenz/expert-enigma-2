# PRD: Packaging, Delivery, and Serving Strategy

## 1. Overview

This document outlines the requirements and proposed architecture for packaging, delivering, and serving the `expert-enigma` Model Context Protocol (MCP) server. The primary goal is to define a process that is simple, reliable, and easily automatable for both human developers and AI coding agents, with a specific focus on supporting multiple, concurrent projects.

## 2. Target Personas

1.  **The Developer:** A software engineer working on one or more Ruby repositories. They need a simple way to install the server and run isolated instances for each of their projects.
2.  **The Automated Agent (e.g., Gemini):** An LLM-based coding agent. It requires a programmatic and deterministic way to start, stop, and interact with a dedicated MCP server for a given workspace, without conflicting with other running servers.

## 3. Core Requirements & User Stories

### Packaging & Delivery

*   **As a Developer, I want** to install the server and all its dependencies with a single command, without worrying about system-level conflicts (especially for native extensions like `sqlite-vss` and `onnxruntime`).
*   **As an Automated Agent, I need** a self-contained, portable executable or image that guarantees a consistent runtime environment.

### Serving & Lifecycle Management

*   **As a Developer, I want** a simple Command Line Interface (CLI) to manage the server's lifecycle (index, start, stop, status) on a per-project basis.
*   **As a Developer, I want** to run MCP servers for multiple projects simultaneously on my machine without them interfering with each other.
*   **As an Automated Agent, I need** to programmatically start a server for a specific repository on a dedicated port and receive a clear signal (e.g., a health check endpoint) when it is ready to accept requests.
*   **As an Automated Agent, I need** to manage the server as a background process that can be reliably terminated when my task is complete.

## 4. Proposed Architecture: Docker-First with a Project-Scoped CLI

To meet the requirements for portability, dependency management, and multi-project isolation, we propose a **Docker-first** distribution model. This approach encapsulates the entire runtime environment into a single, immutable image.

The server will be managed via a CLI designed to operate on a specific project directory. Each project will have its own isolated database and run on its own dedicated port, preventing data corruption and port collisions.

### 4.1. Database & State Isolation

To ensure projects do not interfere with each other, all state will be stored within the project's own directory.

*   **Database Location:** The indexer will create the database at `<project_path>/.expert_enigma/expert_enigma.db`.
*   **Project-Scoped Operations:** All CLI commands (`index`, `start`, etc.) will operate on the project directory they are pointed at, ensuring that indexing and serving are always correctly scoped.

### 4.2. Packaging: Docker Image

The application will be packaged as a Docker image.

*   **Base Image:** A standard Ruby image (e.g., `ruby:3.2-slim`).
*   **Dependencies:** The `Dockerfile` will handle all system and gem dependencies.
*   **Entrypoint:** The image's entry point will be a script that executes the CLI.

### 4.3. Delivery: Docker Hub

The official image will be published to Docker Hub, making it accessible via a standard `docker pull` command (e.g., `docker pull expert-enigma/server:latest`).

### 4.4. Serving: The `expert-enigma` CLI

A new CLI will be created to manage the server's state on a per-project basis.

**Proposed CLI Commands:**

| Command | Description | Example Usage |
| :--- | :--- | :--- |
| `expert-enigma index <path>` | Scans the repository at `<path>` and builds the database inside `<path>/.expert_enigma/`. This must be run before starting the server. | `expert-enigma index /path/to/my-project` |
| `expert-enigma start <path> [--port <port>]` | Starts the MCP server for the project at `<path>`. Assumes the database has been built. Defaults to port `65432` if not specified. | `expert-enigma start /path/to/my-project --port 8001` |
| `expert-enigma stop` | Stops the currently running server process. | `expert-enigma stop` |
| `expert-enigma status` | Reports whether the server is running and for which project. | `expert-enigma status` |
| `expert-enigma serve <path> [--port <port>]` | A convenience command that runs `index` if the database is missing, and then immediately runs `start`. | `expert-enigma serve /path/to/my-project --port 8001` |

## 5. User Installation and Setup Guide

This section describes the end-to-end process for a user to install and run the `expert-enigma` server.

### Step 1: Install Docker

First, ensure Docker is installed. Official instructions are available at [https://docs.docker.com/engine/install/](https://docs.docker.com/engine/install/).

### Step 2: Get the Docker Image

Users can get the image in one of two ways:

*   **Option A: Pull from Docker Hub (Recommended)**
    ```bash
    docker pull expert-enigma/server:latest
    ```
*   **Option B: Build from Source**
    ```bash
    # Navigate to the project's source directory
    docker build -t expert-enigma/server:latest .
    ```

### Step 3: Install the Command-Line Wrapper

To provide a seamless, native-like CLI experience, users should install a wrapper script that handles the Docker commands.

1.  **Create the script file** in a directory that is part of the system's `PATH` (e.g., `/usr/local/bin`).
    ```bash
    sudo nano /usr/local/bin/expert-enigma
    ```

2.  **Add the following content** to the file. This script translates `expert-enigma` commands into the appropriate `docker run` calls, automatically mounting the current directory.
    ```bash
    #!/bin/bash
    #
    # Wrapper script for running the expert-enigma MCP server via Docker.
    # This script mounts the current working directory into the container
    # and passes all command-line arguments to the server's CLI.
    #
    # Usage: expert-enigma [index|start|serve|stop|status] [options]
    #
    # Commands:
    #   index             Scans the current directory and builds the database
    #   start [--port N]  Starts the MCP server (detached mode, default port 65432)
    #   serve [--port N]  Convenience command that runs index if needed, then start
    #   stop              Stops the currently running server process
    #   status            Reports whether the server is running
    #
    # Options:
    #   --port <port>     Specify the port number (default: 65432)
    #

    set -e

    IMAGE_NAME="expert-enigma/server:latest"
    PROJECT_PATH="$(pwd)"
    DEFAULT_PORT=65432

    # Function to parse port from arguments
    parse_port() {
        local port=$DEFAULT_PORT
        local args=("$@")
        local i=0
        
        while [ $i -lt ${#args[@]} ]; do
            if [ "${args[$i]}" = "--port" ]; then
                if [ $((i + 1)) -lt ${#args[@]} ]; then
                    port="${args[$((i + 1))]}"
                    # Validate port is a number
                    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
                        echo "Error: Port must be a number" >&2
                        exit 1
                    fi
                    # Validate port range
                    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                        echo "Error: Port must be between 1 and 65535" >&2
                        exit 1
                    fi
                else
                    echo "Error: --port option requires a value" >&2
                    exit 1
                fi
                break
            fi
            i=$((i + 1))
        done
        
        echo "$port"
    }

    # Function to show usage
    show_usage() {
        echo "Usage: expert-enigma [index|start|serve|stop|status] [options]"
        echo
        echo "Commands:"
        echo "  index             Scans the current directory and builds the database"
        echo "  start [--port N]  Starts the MCP server (detached mode, default port 65432)"
        echo "  serve [--port N]  Convenience command that runs index if needed, then start"
        echo "  stop              Stops the currently running server process"
        echo "  status            Reports whether the server is running"
        echo
        echo "Options:"
        echo "  --port <port>     Specify the port number (default: 65432)"
        echo
    }

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed or not in PATH" >&2
        echo "Please install Docker from https://docs.docker.com/engine/install/" >&2
        exit 1
    fi

    # Check if any arguments provided
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi

    # The main command to be executed inside the container is the first argument
    COMMAND="$1"
    shift # Removes the first argument, so $@ contains the rest

    case "$COMMAND" in
        start)
            # For the 'start' command, we handle port mapping and run in detached mode
            PORT=$(parse_port "$@")
            CONTAINER_NAME="mcp-server-$(basename "${PROJECT_PATH}")"
            
            echo "Starting expert-enigma server in detached mode..."
            echo "Project: ${PROJECT_PATH}"
            echo "Port: ${PORT}"
            echo "Container: ${CONTAINER_NAME}"
            
            # Check if container with same name already exists
            if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                echo "Container '${CONTAINER_NAME}' already exists. Removing it first..."
                docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
            fi
            
            docker run -d -p "${PORT}:65432" -v "${PROJECT_PATH}:/app" --name "${CONTAINER_NAME}" "$IMAGE_NAME" start /app "$@"
            echo "✓ Server started successfully"
            echo "✓ Server is listening on port ${PORT}"
            echo "✓ Container name: ${CONTAINER_NAME}"
            ;;
        serve)
            # For the 'serve' command, we handle port mapping and run in detached mode
            PORT=$(parse_port "$@")
            CONTAINER_NAME="mcp-server-$(basename "${PROJECT_PATH}")"
            
            echo "Running expert-enigma serve (index + start)..."
            echo "Project: ${PROJECT_PATH}"
            echo "Port: ${PORT}"
            echo "Container: ${CONTAINER_NAME}"
            
            # Check if container with same name already exists
            if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                echo "Container '${CONTAINER_NAME}' already exists. Removing it first..."
                docker rm -f "${CONTAINER_NAME}" > /dev/null 2>&1 || true
            fi
            
            docker run -d -p "${PORT}:65432" -v "${PROJECT_PATH}:/app" --name "${CONTAINER_NAME}" "$IMAGE_NAME" serve /app "$@"
            echo "✓ Server started successfully"
            echo "✓ Server is listening on port ${PORT}"
            echo "✓ Container name: ${CONTAINER_NAME}"
            ;;
        index)
            # For the 'index' command, run the container and remove it when done
            echo "Indexing project: ${PROJECT_PATH}"
            docker run --rm -v "${PROJECT_PATH}:/app" "$IMAGE_NAME" index /app "$@"
            ;;
        stop)
            # For the 'stop' command, run the container and remove it when done
            echo "Stopping expert-enigma server..."
            docker run --rm -v "${PROJECT_PATH}:/app" "$IMAGE_NAME" stop /app "$@"
            
            # Also stop and remove any detached containers for this project
            CONTAINER_NAME="mcp-server-$(basename "${PROJECT_PATH}")"
            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                echo "Stopping detached container: ${CONTAINER_NAME}"
                docker stop "${CONTAINER_NAME}" > /dev/null
                docker rm "${CONTAINER_NAME}" > /dev/null
                echo "✓ Detached container stopped and removed"
            fi
            ;;
        status)
            # For the 'status' command, run the container and remove it when done
            echo "Checking expert-enigma server status..."
            docker run --rm -v "${PROJECT_PATH}:/app" "$IMAGE_NAME" status /app "$@"
            
            # Also check if detached container is running
            CONTAINER_NAME="mcp-server-$(basename "${PROJECT_PATH}")"
            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                echo "✓ Detached container '${CONTAINER_NAME}' is running"
            fi
            ;;
        --help|-h|help)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown command '${COMMAND}'" >&2
            echo >&2
            show_usage
            exit 1
            ;;
    esac
    ```

3.  **Make the script executable:**
    ```bash
    sudo chmod +x /usr/local/bin/expert-enigma
    ```

### Step 4: Usage Example

With the wrapper installed, the server can be managed like any other CLI tool.

```bash
# Navigate to your Ruby project
cd /path/to/my-ruby-project

# Index the project (creates ./.expert_enigma/expert_enigma.db)
expert-enigma index

# Start the server for this project
expert-enigma start

# To run a server for a second project, open a new terminal:
# cd /path/to/another-project
# expert-enigma index
# expert-enigma start --port 8001
```

## 6. Example Workflow: Handling Multiple Projects (Automated Agent)

This workflow demonstrates how an agent would manage two separate MCP server instances for two different repositories.

### Project A

1.  **Index the Repository:** The agent mounts the first project into a container and runs the `index` command. The database is created at `/path/to/project-a/.expert_enigma/expert_enigma.db`.
    ```bash
    docker run --rm -v "/path/to/project-a:/app" expert-enigma/server:latest index /app
    ```

2.  **Start the Server:** The agent starts the server as a detached background process, mapping the container's internal port to `8001` on the host.
    ```bash
    docker run -d -p 8001:65432 -v "/path/to/project-a:/app" --name project-a-mcp expert-enigma/server:latest start /app --port 65432
    ```

3.  **Interact with MCP for Project A:** The agent makes API calls to `http://localhost:8001`.

### Project B

1.  **Index the Repository:** In parallel, the agent indexes the second project. The database is created at `/path/to/project-b/.expert_enigma/expert_enigma.db`.
    ```bash
    docker run --rm -v "/path/to/project-b:/app" expert-enigma/server:latest index /app
    ```

2.  **Start the Server:** The agent starts a second, isolated server instance, mapping its port to `8002` on the host.
    ```bash
    docker run -d -p 8002:65432 -v "/path/to/project-b:/app" --name project-b-mcp expert-enigma/server:latest start /app --port 65432
    ```

3.  **Interact with MCP for Project B:** The agent makes API calls to `http://localhost:8002`.

### Shutdown

Once finished, the agent stops and removes the containers by name.
```bash
docker stop project-a-mcp && docker rm project-a-mcp
docker stop project-b-mcp && docker rm project-b-mcp
```

## 7. Future Considerations

*   **Alternative Installation (RubyGems):** While Docker is primary, publishing a Gem would be beneficial for developers who prefer a non-Docker workflow. This would require providing clear instructions for installing the native dependencies.
*   **Configuration:** The server port and other settings could be configured via a `.expert_enigma.yml` file in the target repository or through environment variables.
*   **Incremental Indexing:** The `index` command could be enhanced with a `--watch` mode to support the real-time indexing feature mentioned in the `README.md`.

## 8. Implementation Tickets

This feature will be implemented by completing the following tickets in the specified order.

1.  **[#9](https://github.com/timlawrenz/expert-enigma-2/issues/9)**: `[Setup] Create CLI Executable and Basic Structure`
2.  **[#11](https://github.com/timlawrenz/expert-enigma-2/issues/11)**: `[CLI] Implement expert-enigma index Command`
3.  **[#7](https://github.com/timlawrenz/expert-enigma-2/issues/7)**: `[CLI] Implement expert-enigma start Command`
4.  **[#12](https://github.com/timlawrenz/expert-enigma-2/issues/12)**: `[CLI] Implement expert-enigma status Command`
5.  **[#8](https://github.com/timlawrenz/expert-enigma-2/issues/8)**: `[CLI] Implement expert-enigma stop Command`
6.  **[#13](https://github.com/timlawrenz/expert-enigma-2/issues/13)**: `[CLI] Implement expert-enigma serve Command`
7.  **[#10](https://github.com/timlawrenz/expert-enigma-2/issues/10)**: `[Docker] Create Dockerfile for the Application`
8.  **[#15](https://github.com/timlawrenz/expert-enigma-2/issues/15)**: `[Infra] Create and Document the expert-enigma Wrapper Script`
9.  **[#14](https://github.com/timlawrenz/expert-enigma-2/issues/14)**: `[Infra] Publish Docker Image to Docker Hub`
