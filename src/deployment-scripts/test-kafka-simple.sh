#!/bin/bash

# Simple Kafka test script
echo "Testing Kafka deployment..."

# Set Java home
JAVA_HOME="/opt/jdk-21.0.8.jdk/Contents/Home"
export JAVA_HOME

# Test if Kafka is accessible
echo "Testing Kafka connectivity..."
if JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-broker-api-versions --bootstrap-server localhost:9092 >/dev/null 2>&1; then
    echo "✅ Kafka is running and accessible"
else
    echo "❌ Kafka is not accessible"
    echo "Check if Kafka is running: ps aux | grep kafka"
    echo "Check logs: sudo tail -f /tmp/log/confluent/kafka/kafka.log"
    exit 1
fi

# Create a test topic
echo "Creating test topic..."
if JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --create --topic test-topic --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 >/dev/null 2>&1; then
    echo "✅ Test topic created successfully"
else
    echo "⚠️  Test topic might already exist or creation failed"
fi

# List topics
echo "Listing topics..."
TOPICS=$(JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null)
if [[ -n "$TOPICS" ]]; then
    echo "✅ Topics found:"
    echo "$TOPICS" | sed 's/^/  - /'
else
    echo "⚠️  No topics found"
fi

# Test producer/consumer
echo "Testing producer/consumer..."
TEST_MESSAGE="Hello Kafka $(date)"
echo "$TEST_MESSAGE" | JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-console-producer --topic test-topic --bootstrap-server localhost:9092 >/dev/null 2>&1

# Read back the message
CONSUMED_MESSAGE=$(JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-console-consumer --topic test-topic --bootstrap-server localhost:9092 --from-beginning --max-messages 1 --timeout-ms 5000 2>/dev/null | tail -1)

if [[ "$CONSUMED_MESSAGE" == "$TEST_MESSAGE" ]]; then
    echo "✅ Producer/Consumer test passed"
else
    echo "⚠️  Producer/Consumer test failed or timed out"
fi

echo ""
echo "✅ Kafka deployment test completed!"
echo ""
echo "Access points:"
echo "  Kafka Broker: localhost:9092"
echo ""
echo "Useful commands:"
echo "  List topics: JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --list --bootstrap-server localhost:9092"
echo "  Create topic: JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --create --topic <name> --bootstrap-server localhost:9092"
echo "  Delete topic: JAVA_HOME=$JAVA_HOME /opt/kafka/bin/kafka-topics --delete --topic <name> --bootstrap-server localhost:9092"
echo "  Create topic: /opt/kafka/bin/kafka-topics --create --topic <name> --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1"
echo "  Send message: echo 'test' | /opt/kafka/bin/kafka-console-producer --topic <name> --bootstrap-server localhost:9092"
echo "  Read messages: /opt/kafka/bin/kafka-console-consumer --topic <name> --bootstrap-server localhost:9092 --from-beginning"
