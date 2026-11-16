# ADR-001: Use S3 for input and output files

- **Status:** Accepted
- **Date:** 2026-10-26
- **Ticket:** FP-17

## Context
The Payments Data team drops CSV files on a single server's disk. If that server dies, the files are lost, and only people with server access can see them.

## Decision
Store input and output files in separate, encrypted, versioned S3 buckets per environment. The server only gets permission to read input and write output.

## Options considered
| Option | Pros | Cons |
| --- | --- | --- |
| Server disk (today) | Simple | Lost if server dies, hard to share |
| EFS shared drive | Behaves like a folder | Costs more, more to manage |
| **S3** | Cheap, durable, versioned, fine-grained access | App must use the AWS API |

## Consequences
- The app has an S3 mode (`INPUT_BUCKET` / `OUTPUT_BUCKET`).
- Versioning means a bad output file can be restored.
- Servers become replaceable: no important data lives on them.