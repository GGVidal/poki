# Contributing

For details on branches, checks, and how releases work, see [AGENTS.md](AGENTS.md#contribute-code) and [docs/release-channels.md](docs/release-channels.md). Run `npm test` before you submit, and say in the pull request whether you also tested on a Simulator or a physical iPhone.

## When to open an issue first

To fix a typo, a small bug, or a documentation gap, feel free to open a pull request right away.

To add a feature or make a large change, open an issue first and wait for a maintainer to confirm that it is welcome before writing the code. A large change is any of the following:

- A new feature
- A change to how Poki operates the phone, including input, taps, screen reading, stopping a task, or keeping a task alive in the background
- A change to the first-time setup flow
- A change to the main flow of the interface
- A change that touches 10 or more files

If you are not sure whether your change counts as large, open an issue and ask. A pull request for an unapproved large change may be closed without review, no matter how good the code is.

## Contributor levels

There are four contributor levels. Everyone starts at the first level, and you do not need anyone to vouch for you before opening a pull request.

| Level | How you get there | What you can do |
| --- | --- | --- |
| Contributor | Anyone. Fork the repository and open a pull request. | Open issues and pull requests. On your first pull request you agree once to the [Poki Contributor Agreement](CONTRIBUTOR_AGREEMENT.md). Until your first pull request is merged, please keep only one pull request open at a time. |
| Invited contributor | Have three or more pull requests merged, and receive an invitation from a maintainer. | Triage access to add labels and close issues. You cannot merge pull requests. |
| Core contributor | Make sustained contributions over time, and receive an invitation from a maintainer. | Listed in [CODEOWNERS](.github/CODEOWNERS) and in the Core contributors section of the [README](README.md#core-contributors). |
| Maintainer | Repository owner. | Approve releases and change repository settings. |

Only maintainers can merge pull requests into `main`. Moving up a level is decided by maintainers based on the quality and consistency of your work.

## AI assistance

You are welcome to use AI tools. The pull request template asks you to include one line:

> AI assistance: None, Claude Code, Codex, or Other. I have reviewed and understand these changes.

List the tool you used, and confirm that you have read and understood the entire change. Be ready to explain any line during review. If an AI agent opens a pull request for you, the [Poki Contributor Agreement](CONTRIBUTOR_AGREEMENT.md) is still yours to give: read it and post the agreement comment yourself, or tell your agent to.

## How to open a pull request

You do not have write access to `JosssphZhou/poki`, so `git push` to it fails with `permission denied`. That is expected. Push to your own fork and open the pull request from there.

With the GitHub CLI, from your clone with the branch already made:

```sh
gh repo fork --remote            # creates your fork, adds it as origin, renames the old origin to upstream
git push -u origin <branch>
gh pr create --base main
```

Without it: click **Fork** on GitHub, then

```sh
git remote add fork https://github.com/<you>/poki.git
git push -u fork <branch>
```

and open a pull request from that branch into `main` of `JosssphZhou/poki` on the website.

Before you open it, run `npm test` and fill in the [pull request template](.github/PULL_REQUEST_TEMPLATE.md): what changes and how you tested it. The `PR checks` workflow must pass.

By submitting a contribution, you release it under the [AGPL-3.0-only license](LICENSE). You confirm this once: on your first pull request, Poki Repo Bot asks you to agree to the [Poki Contributor Agreement](CONTRIBUTOR_AGREEMENT.md) by commenting `I agree to the Poki Contributor Agreement` from your own account. That covers your later pull requests too, and the `Contributor agreement` status on the pull request turns green.

Use third-party code only if its license is compatible with AGPL-3.0-only. Keep the original copyright notice and list the code in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Do not commit device screenshots, clipboard contents, pairing records, passcodes, or tokens.
