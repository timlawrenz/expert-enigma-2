# Use the official Ruby 3.2 slim image as base
FROM ruby:3.2-slim

# Set working directory
WORKDIR /app

# Install system dependencies required for gems
RUN apt-get update && apt-get install -y \
    build-essential \
    libsqlite3-dev \
    sqlite3 \
    pkg-config \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

# Copy Gemfile and Gemfile.lock first for better Docker layer caching
COPY Gemfile Gemfile.lock ./

# Install Ruby gems with SSL workaround for development environment
# Note: In production environments with proper SSL certificates, remove the
# ssl_verify_mode workaround and use: RUN bundle install
# For development builds in environments with SSL issues, the workaround is needed
ENV BUNDLE_FORCE_RUBY_PLATFORM=1
RUN bundle config set --global ssl_verify_mode 0 && \
    bundle install && \
    bundle config unset ssl_verify_mode

# Copy the entire application
COPY . .

# Make the CLI executable
RUN chmod +x bin/expert-enigma

# Set the entrypoint to the CLI executable
ENTRYPOINT ["bin/expert-enigma"]