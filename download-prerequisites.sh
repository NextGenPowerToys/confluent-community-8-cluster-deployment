#!/bin/bash

set -e

DEPLOYMENT_FILES_DIR="/Users/alexk/pipelines/kafka-community-8/deployment-files"
mkdir -p "$DEPLOYMENT_FILES_DIR"

echo "=== Downloading Kafka Deployment Prerequisites ==="
echo "Target directory: $DEPLOYMENT_FILES_DIR"
echo ""

# Download Confluent Community 8.0.0
echo "Downloading Confluent Community 8.0.0..."
if [[ ! -f "$DEPLOYMENT_FILES_DIR/confluent-community-8.0.0.zip" ]]; then
    curl -L -o "$DEPLOYMENT_FILES_DIR/confluent-community-8.0.0.zip" \
        "https://packages.confluent.io/archive/8.0/confluent-community-8.0.0.zip"
    echo "✅ Confluent Community 8.0.0 downloaded"
else
    echo "✅ Confluent Community 8.0.0 already exists"
fi

# Download JDK 21 for Linux ARM64
echo "Downloading JDK 21 for Linux ARM64..."
if [[ ! -f "$DEPLOYMENT_FILES_DIR/jdk-21_linux-aarch64_bin.tar.gz" ]]; then
    curl -L -o "$DEPLOYMENT_FILES_DIR/jdk-21_linux-aarch64_bin.tar.gz" \
        "https://download.oracle.com/java/21/latest/jdk-21_linux-aarch64_bin.tar.gz"
    echo "✅ JDK 21 Linux ARM64 downloaded"
else
    echo "✅ JDK 21 Linux ARM64 already exists"
fi

echo ""
echo "=== Download Complete ==="
echo "Files downloaded to: $DEPLOYMENT_FILES_DIR"
ls -la "$DEPLOYMENT_FILES_DIR"
echo ""
echo "Ready for offline deployment!"