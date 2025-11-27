# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2025-01-27

### Fixed

- Updated dependency to `offline_first_sync_drift: ^0.1.1`

### Documentation

- Improved installation and usage examples

## [0.1.0] - 2024-11-27

### Added

- Initial release
- `RestTransport` implementation of `TransportAdapter`
- REST API contract with standard CRUD endpoints
- Configurable retry with exponential backoff
- Parallel push support via `pushConcurrency` parameter
- Conflict detection with `409 Conflict` response handling
- Force push headers (`X-Force-Update`, `X-Force-Delete`)
- Idempotency support via `X-Idempotency-Key` header
- `TestServer` for E2E testing with:
  - Data seeding and manipulation
  - Error simulation (network errors, invalid JSON)
  - Request recording and inspection
  - Configurable conflict checking

