---
title: Deploying with Kamal
parent: Deployment
nav_order: 2
---

# Deploying with Kamal
{: .no_toc }

A worked deployment: one server, Postgres beside the app, TLS from Let's Encrypt, and a
published release rather than a build of your own.
{: .fs-6 .fw-300 }

1. TOC
{:toc}

---

The repository carries this deployment, so there is nothing to reconstruct from a
tutorial: `config/deploy.yml` is the template for building your own image, and
`config/deploy.production.yml` is a complete destination that runs a published release.
None of its values are in the repository — it reads them from a `.env.production` you
keep out of git, and refuses to deploy while any of them is missing.

Nothing here is required. governauthzer is a plain Rails app in a Docker image; if you
deploy with Helm, Compose or an in-house tool, [Deployment](deployment.md) is the provider-neutral
reference and this page is one worked example of it.

## What you need

- A server with Docker and ports 80, 443 and 22 open. It needs about 2 GB of memory.
- DNS pointing at that server. `DOMAIN` is what Let's Encrypt will issue for.
- An SSH key at `~/.ssh/kamal_deploy`, authorized for `root` on the server. Use an
  **ed25519** key: Kamal's SSH client cannot sign with ECDSA keys on OpenSSL 3.5+, which
  fails with `EVP_PKEY_sign: provider signature failure`.
- The [`gh` CLI](https://cli.github.com/), signed in. The deploy reuses its token to log
  in to the registry, so there is no access token to store or rotate.

## Configure

```sh
cp .env.example .env.production
```

Fill it in. Every value has a comment saying what it is and how to generate it; the two
that need a command are:

```sh
bin/rails secret                        # SECRET_KEY_BASE
bin/governauthzer generate-encryption-keys   # the three encryption keys
```

Back the file up in a password manager. Losing the encryption keys loses every encrypted
value — currently the OIDC client secrets — and the database passwords are baked into the
Postgres volume when it first boots.

Leave `SMTP_HOST` unset to run without mail: approval notifications then fail quietly in
the background and the in-app inbox carries the workflow. Setting it wires the rest in.

## First deployment

Bring the database up before anything else. Kamal boots accessories *after* the
pre-deploy hook, and that hook is what migrates — so on a first run there would be
nothing to migrate against, and the deploy stops and tells you to do this:

```sh
bin/kamal accessory boot db -d production
```

That creates the Postgres container, and on its first boot only,
[`.kamal/db-init.sh`](https://github.com/governauthzer/governauthzer/blob/main/.kamal/db-init.sh)
creates the restricted runtime role and the three Solid-stack databases.

Then deploy a published version:

```sh
bin/kamal setup -d production -P --version 1.0.0
```

`-P` is not optional here. Without it Kamal builds your working tree and pushes it to the
*public* package under a git-sha tag. With it, Kamal pulls the release you named — so
deploying is also the last check that what the registry serves actually boots.

## Later deployments

```sh
bin/kamal deploy -d production -P --version 1.1.0
```

Published versions are listed on the
[releases page](https://github.com/governauthzer/governauthzer/releases); the images are
at `ghcr.io/governauthzer/governauthzer`, built for `linux/amd64` and `linux/arm64`.

To go back:

```sh
bin/kamal rollback -d production 1.0.0
```

A rollback boots the older image without touching the database — running an older
release's migrations is at best a no-op, at worst a schema its code cannot read. If a
release carried a migration you need undone, undo it deliberately.

## What happens on each deploy

Between pulling the image and starting it, the
[`pre-deploy` hook](https://github.com/governauthzer/governauthzer/blob/main/.kamal/hooks/pre-deploy)
does the two things the application container deliberately cannot do for itself:

1. **Migrates as the database owner.** The app serves as a restricted role that cannot
   `UPDATE` or `DELETE` `audit_events` — that grant *is* the
   [audit-log protection](audit-log-protection.md). Migrations need the owner. If the
   owner's password lived in the app container's environment, a compromised app process
   could reconnect as the owner and rewrite the audit log, and the separation would be
   decorative. So the owner password stays with whoever deploys: Kamal hands it to the
   hook, which reaches the database over SSH for the length of one command and never puts
   it in the application's environment.
2. **Applies `db/grants.sql` to all four databases, then verifies it took effect.** A
   deploy that would leave the audit log rewritable stops here, before the new container
   serves a request.

Secrets and SQL travel on stdin into a root-only temporary directory that is removed when
the hook exits — never as command-line arguments, which are visible in `ps` to anyone on
the machine.

A deploy with no `-d` destination skips all of this and lets the container entrypoint run
`db:prepare` on boot, which is the right behaviour for a single-role install.

## Bootstrap the first operator

Once the app is up, create the first operator and sign in — see
[Bootstrap the first operator](deployment.md#bootstrap-the-first-operator). Run the commands inside
the container:

```sh
bin/kamal app exec -d production --reuse "bin/governauthzer seed-admin --email you@example.com --name 'Your Name'"
bin/kamal app exec -d production --reuse "bin/governauthzer emergency-login --user you@example.com --reason bootstrap"
```

## Another destination

Copy `config/deploy.production.yml`, change the file name it loads at the top, and keep
its values in the matching `.env.<destination>`. Destination env files never load
together, so names inside them need no prefix.
