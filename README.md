# Confluent Community 8.0.0 KRaft Deployment

Automated deployment system for Confluent Community Edition 8.0.0 with KRaft consensus protocol.

## Quick Start

### Local Development
```bash
cd src/deployment-scripts
./deploy-kafka-cluster.sh
# Answer: y (local), dev (environment), 1 (servers)
```

### Remote Production
```bash
cd src/deployment-scripts
./deploy-kafka-cluster.sh  
# Answer: n (remote), prod (environment), 3 (servers)
```

## Documentation

- **[Architecture](kafka-cluster-architecture.md)** - Technical architecture and design
- **[Deployment Guide](DEPLOYMENT.md)** - Complete deployment instructions
- **[Rules](.amazonq/rules/kafak-deployment-sh-script.md)** - Deployment script requirements

## Features

- Single or multi-node KRaft clusters
- Environment-specific naming
- Local and remote deployment modes
- Automated service configuration
- Provectus Kafka UI included

## Requirements

- RHEL 8 (remote) or macOS/Linux (local)
- SSH access for remote deployment
- Confluent Community 8.0.0 ZIP file
- Provectus Kafka UI JAR file