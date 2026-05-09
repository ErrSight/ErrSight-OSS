# Contributing to ErrSight OSS

Thanks for your interest in contributing. This document describes how contributions are accepted, the licensing terms that apply, and what to expect from review.

## TL;DR

1. **Open an issue first** for anything beyond a small bug fix or doc change.
2. **Sign the CLA** when the bot prompts you on your first PR — once, then never again.
3. **Run the tests and linters** before opening a PR.
4. **Keep PRs small and focused** — one logical change per PR.

## Code of Conduct

This project follows the [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating you agree to uphold it. Report unacceptable behavior to hi@errsight.com.

## Reporting security issues

Please **do not** file public issues for security vulnerabilities. See [`SECURITY.md`](SECURITY.md) for the full policy — in short, email hi@errsight.com directly (or use GitHub's private "Report a vulnerability" advisory), and we'll acknowledge within 72 hours.

## Reporting bugs

Open a GitHub issue. Helpful reports include:

- ErrSight version or commit SHA
- Ruby and Rails versions
- PostgreSQL version and OS
- Minimal steps to reproduce
- Expected vs. actual behavior
- Relevant logs with secrets redacted

## Proposing features

For anything non-trivial, open a discussion or feature-request issue **before** writing code. ErrSight OSS has a defined scope (see "Scope" below); we'd rather redirect a proposal early than reject a finished PR.

## Contribution licensing

ErrSight OSS is licensed under the **GNU Affero General Public License v3.0 (AGPLv3)**. All contributions are accepted under that same license.

In addition, **all contributors must sign the ErrSight Contributor License Agreement (CLA)** before their first contribution is merged.

### Why we require a CLA

The CLA gives the maintainer the legal authority to (a) ship your contribution as part of ErrSight OSS under AGPLv3, and (b) include it in proprietary or commercial software (such as the hosted SaaS at errsight.com) without legal ambiguity. You retain copyright in your contribution — the CLA is a license grant, not an assignment.

### How to sign

When you open your first pull request, the **CLA Assistant** bot will comment with a link. Sign in with GitHub, read the agreement, and click to sign. The signature is recorded against your GitHub account and applies to all future contributions.

If you are contributing on behalf of an employer (during work hours, on company equipment, or to code related to your employer's business), please email hi@errsight.com before submitting. Your employer may need to sign a separate Corporate CLA.

PRs without a signed CLA cannot be merged; the bot blocks the merge automatically.

### What if I'm only fixing a typo?

We still ask you to sign. The CLA covers all contributions, however small, and signing once removes friction from any future PRs. It takes under a minute.

## Third-party code

If your contribution includes code or assets copied from another project, the source must be license-compatible with AGPLv3. Compatible: MIT, BSD-2/3-Clause, Apache-2.0, MPL-2.0, ISC, LGPL, GPLv3. Not compatible: GPLv2-only, proprietary, unknown-license. Always preserve original copyright and license notices, and call out the source in your PR description.

## Trademark and branding

The AGPLv3 license covers ErrSight OSS **source code only**. The name "ErrSight" and the ErrSight logo are trademarks of Jijo Bose and are **not** licensed under AGPLv3.

You may fork, modify, and redistribute the code. You may **not** distribute a modified version under the "ErrSight" name or use the logo without permission. Forks should be renamed.

## A note on AGPLv3 and network use

AGPLv3 §13 ("Remote Network Interaction") means that if you run a modified ErrSight as a network service, users interacting with that service over the network are entitled to the complete corresponding source of your modified version. This obligation falls on whoever operates the modified service, not on upstream contributors — but you should understand it before forking and self-hosting.

## Development setup

Prerequisites: Ruby (see `.ruby-version`), PostgreSQL, Redis, Node.js + Yarn.

```bash
git clone https://github.com/<your-fork>/ErrSight-OSS.git
cd errsight-community
cp .env.example .env        # then edit local values
bin/setup
bin/dev
```

Open http://localhost:3000. See `README.md` for environment-variable details.

## Running tests and linters

```bash
bin/rails test                # full test suite
bin/rails test test/path/     # single file or directory
bin/rubocop                   # lint
bin/rubocop -A                # safe autocorrect
bin/brakeman                  # security scan
```

PRs must pass tests, Rubocop, and Brakeman in CI before review.

## Commit messages

- Imperative mood: "Fix race condition in ingest worker."
- First line ≤72 characters.
- Body explains _why_, not _what_ — the diff shows what.
- Reference issues at the end: `Closes #123`.
- One logical change per commit where reasonable. We may squash on merge.

## Pull request process

1. Fork the repo and branch from `main`: `git checkout -b fix/ingest-deadlock`.
2. Make focused changes. Keep refactors separate from behavior changes when practical.
3. Add or update tests. New behavior without tests is rarely accepted.
4. Update docs if behavior or APIs change.
5. Run tests and linters locally.
6. Open a PR using the template. Describe _what_ changed, _why_, and _how to verify_.
7. Sign the CLA when prompted (first-time contributors).
8. Respond to review feedback. Force-push is fine; we squash on merge.

Expect a first response within about a week. ErrSight is maintained primarily by one person — if a PR sits longer, a polite ping is welcome.

## Scope: OSS vs. hosted SaaS

ErrSight OSS is the open-source error-tracking core. Some features are intentionally reserved for the hosted SaaS at errsight.com — typically those tied to multi-tenant SaaS operations, billing, SSO/SAML, audit logs, and large-scale ingestion infrastructure.

Before proposing a feature, check open issues and discussions to gauge fit.

Generally welcome in OSS:

- Bug fixes, performance improvements, security fixes
- Better error grouping, search, and notifications
- New SDK/integration support
- Documentation, tests, developer experience
- Accessibility and i18n

Generally not in OSS:

- Features primarily aimed at multi-tenant SaaS operations
- Enterprise authentication (SAML, SCIM provisioning)
- Anything that would duplicate hosted-SaaS functionality

When in doubt, ask first.

## License

By contributing, you agree your contributions will be licensed under AGPLv3 (see `LICENSE`) and that you grant the additional rights described in the CLA you signed.
