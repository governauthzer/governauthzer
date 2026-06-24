# Security Policy

governauthzer is an identity-governance system — security issues are treated as
top priority.

## Reporting a vulnerability

**Please do not open public issues, pull requests, or discussions for security
vulnerabilities.**

Report privately via GitHub's
[private vulnerability reporting](https://github.com/governauthzer/governauthzer/security/advisories/new)
(repo **Security → Report a vulnerability**). This keeps the report confidential until a
fix is available.

Please include:

- affected version or commit SHA,
- a description of the issue and its impact,
- reproduction steps or a proof of concept,
- any suggested remediation.

We aim to acknowledge a report within **3 business days** and to agree on a disclosure
timeline with you.

> **No bug bounty (yet).** governauthzer does not currently offer monetary rewards for
> vulnerability reports. We gratefully credit reporters in the published advisory unless
> they prefer to remain anonymous. This may change as the project matures.

## Areas of particular interest

Given the threat model, we especially want to hear about:

- authentication or authorization bypass (OIDC flow, session/cookie handling, API tokens,
  break-glass tokens),
- privilege escalation (e.g. a non-operator gaining operator capability),
- audit-log tampering or gaps,
- exposure of secrets (OIDC client secrets, encryption keys, signing secrets),
- webhook signature forgery or reconciliation-callback abuse.

## Disclosure

We follow coordinated disclosure: we will work with you on a fix, credit you (unless you
prefer otherwise), and publish an advisory once a fix is available.
