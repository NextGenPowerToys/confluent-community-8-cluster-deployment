# Deployment Files Directory

This directory contains the binary distributions required for Kafka deployment.

## Required Files

Place the following files in this directory before running deployment scripts:

### 1. Confluent Community Kafka 8.0.0
- **File**: `confluent-community-8.0.0.zip`
- **Source**: https://packages.confluent.io/archive/8.0/confluent-community-8.0.0.zip
- **Size**: ~363MB
- **Description**: Confluent Community Kafka distribution with KRaft support

### 2. Oracle JDK 21.0.8 LTS
- **File**: `jdk-21.0.8-macos-x64.tar.gz` (or appropriate platform version)
- **Source**: https://download.oracle.com/java/21/latest/
- **Size**: ~181MB
- **Description**: Oracle JDK 21 LTS compressed archive

#### Platform-specific JDK Downloads:
- **macOS x64**: `jdk-21_macos-x64_bin.dmg` → Archive as `jdk-21.0.8-macos-x64.tar.gz`
- **Linux x64**: `jdk-21_linux-x64_bin.tar.gz` → Archive as `jdk-21.0.8-linux-x64.tar.gz`

## File Structure

```
deployment-files/
├── README.md                           # This file
├── confluent-community-8.0.0.zip      # Kafka distribution
└── jdk-21.0.8-macos-x64.tar.gz       # JDK archive
```

## Notes

- These files are excluded from git tracking via `.gitignore`
- Download files manually due to licensing and distribution restrictions
- Deployment scripts will automatically extract archives during installation
- Ensure file integrity after download before deployment

## License Requirements

- **Confluent Community**: Apache License 2.0
- **Oracle JDK**: Oracle No-Fee Terms and Conditions License

Please review and comply with respective license terms before use.
