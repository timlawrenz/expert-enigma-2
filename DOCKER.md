# Docker Usage

This directory contains a Dockerfile for containerizing the expert-enigma application.

## Building the Docker Image

```bash
docker build -t expert-enigma/server:latest .
```

## Running the Container

```bash
# Index a project
docker run --rm -v /path/to/project:/project expert-enigma/server:latest index /project

# Start the server
docker run --rm -v /path/to/project:/project -p 65432:65432 expert-enigma/server:latest start /project

# Show help
docker run --rm expert-enigma/server:latest --help
```

## Image Details

- **Base Image**: ruby:3.2-slim
- **System Dependencies**: build-essential, libsqlite3-dev, sqlite3, pkg-config, ca-certificates  
- **Ruby Gems**: All dependencies from Gemfile including sqlite3, onnxruntime, sinatra, etc.
- **Entrypoint**: bin/expert-enigma CLI executable
- **Working Directory**: /app

## Development Notes

The Dockerfile includes a workaround for SSL certificate verification during gem installation, which may be needed in some development environments. In production builds with proper SSL certificates, this workaround can be removed.