# Security Policy

Thank you for helping keep ErrSight OSS and its users safe. This document
explains how to report a vulnerability in the **ErrSight OSS software**.

> **Self-hosted deployments.** ErrSight OSS is software you run yourself.
> The security of any particular instance — its server, network, secrets,
> backups, and configuration — is the responsibility of whoever operates
> it. This policy covers vulnerabilities in the _software itself_, not in a
> specific deployment. If you've found a problem with a hosted instance you
> don't operate, contact that instance's operator.

## Supported versions

ErrSight OSS is developed on a rolling basis. Security fixes are made
against the latest `main` branch and the most recent release. If you run a
self-hosted instance, the most reliable way to stay secure is to **track
the latest release** and apply updates promptly (`git pull` → `bundle
install` → `bin/rails db:migrate` → restart; see the README).

| Version                 | Supported                      |
| ----------------------- | ------------------------------ |
| Latest release / `main` | ✅ Yes                         |
| Older commits           | ⚠️ Best effort — please update |

## Reporting a vulnerability

**Please do not open a public GitHub issue, pull request, or discussion for
a security vulnerability.** Public disclosure before a fix is available puts
every self-hosted instance at risk.

Report privately through either channel:

1. **Email** — send details to **hi@errsight.com** with a subject line
   starting `[SECURITY]`.
2. **GitHub private advisory** — use the **"Report a vulnerability"** button
   on the repository's **Security** tab
   (<https://github.com/ErrSight/ErrSight-community/security/advisories/new>),
   which opens a private channel visible only to the maintainer.

### What to include

A good report helps us reproduce and fix the issue quickly. Where possible,
please include:

- A description of the vulnerability and its impact (what an attacker can
  do).
- The affected component, file, endpoint, or version / commit SHA.
- Step-by-step reproduction instructions or a minimal proof of concept.
- Any relevant logs, requests, or screenshots — **redact secrets** (API
  keys, tokens, passwords, customer data) before sending.
- Your assessment of severity, if you have one.

## What to expect

- **Acknowledgement within 72 hours** of your report.
- An initial assessment and, where confirmed, agreement on a remediation
  timeline. ErrSight is maintained primarily by one person, so complex
  fixes may take longer — we'll keep you informed.
- Notification when a fix is released.
- Credit for the discovery in the release notes or advisory, if you'd like
  it (let us know how you wish to be credited, or if you prefer to remain
  anonymous).

## Coordinated disclosure

We follow a coordinated-disclosure model. Please give us a reasonable
opportunity to investigate and release a fix before any public disclosure —
**90 days** from your report is the usual upper bound, sooner once a fix has
shipped and self-hosters have had time to update. We're happy to coordinate
timing with you.

## Good-faith research

We will not pursue or support legal action against anyone who:

- Makes a good-faith effort to comply with this policy,
- Reports promptly and privately, and
- Avoids privacy violations, data destruction, service degradation, and
  access to or modification of data beyond what is necessary to demonstrate
  the vulnerability.

Testing should only ever be performed against instances you own or are
explicitly authorized to test — never against someone else's deployment.

## Scope

**In scope:** vulnerabilities in the ErrSight OSS source code in this
repository — for example, authentication/authorization flaws, injection,
cross-site scripting, insecure defaults, data exposure in the API or web
UI, or issues in the event-ingestion path.

**Out of scope:** the security posture of third-party instances you don't
operate; vulnerabilities in dependencies (please report those upstream,
though a heads-up is welcome); issues that require a compromised server or
privileged local access to exploit; and findings from automated scanners
without a demonstrated, realistic impact.
