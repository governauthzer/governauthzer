# governauthzer

**Govern access. Bring any provisioner – or use ours.**

A self-hosted open source decision-plane IGA: request, approve, audit. Provision access however you like – never
locked into a vendor.

> **Early stage – not production-ready.** Great for evaluation and feedback, not yet for governing real access.

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
![Rails 8.1](https://img.shields.io/badge/Rails-8.1-CC0000.svg)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-13%2B-336791.svg)


## What it is

governauthzer owns access *intent* – who should have what, who approved it, why – with an
append-only audit trail. It is **not** a provisioner and **not** an IdP. Every grant and
revoke is published as a signed webhook event, so you fulfill access with whatever you
already use.

→ Full overview, architecture, and feature docs: **[the docs site](https://governauthzer.github.io/governauthzer)**

## Quickstart (development)

Needs Ruby (per [`.ruby-version`](.ruby-version)) and PostgreSQL. A throwaway local DB:

```sh
docker run -d --name governauthzer-pg -e POSTGRES_HOST_AUTH_METHOD=trust -p 5432:5432 postgres:16
bin/setup                 # bundle + db:prepare, then starts bin/dev
bin/rails db:seed         # demo data → open http://localhost:3000/dev/sign-in
```

## Documentation

- **[Docs site](https://governauthzer.github.io/governauthzer)** – product overview, API, webhooks, deployment.
- **API reference** – `/api-docs` (raw spec at `/api-docs/v1.yaml`).
- **[Deployment](docs/deployment.md)** – env vars, TLS, secrets, bootstrap, audit protection.

## License

[GNU Affero General Public License v3.0](LICENSE).
