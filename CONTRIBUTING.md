# Contributing

For details on branches, checks, and how releases work, see [AGENTS.md](AGENTS.md#contribute-code) and [docs/release-channels.md](docs/release-channels.md).

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
| Contributor | Anyone. Fork the repository and open a pull request. | Open issues and pull requests. Until your first pull request is merged, please keep only one pull request open at a time. |
| Invited contributor | Have three or more pull requests merged, and receive an invitation from a maintainer. | Triage access to add labels and close issues. You cannot merge pull requests. |
| Core contributor | Make sustained contributions over time, and receive an invitation from a maintainer. | Listed in [CODEOWNERS](.github/CODEOWNERS) and in the Core contributors section of the [README](README.md#core-contributors). |
| Maintainer | Repository owner. | Approve releases and change repository settings. |

Only maintainers can merge pull requests into `main`. Moving up a level is decided by maintainers based on the quality and consistency of your work.

## AI assistance

You are welcome to use AI tools. The pull request template asks you to include one line:

> AI assistance: None, Claude Code, Codex, or Other. I have reviewed and understand these changes.

List the tool you used, and confirm that you have read and understood the entire change. Be ready to explain any line during review.

## How to open a pull request

You do not have write access to `JosssphZhou/poki`, so running `git push` directly to it will fail with `permission denied`. This is expected. Instead, push to your own fork and open the pull request from there.

With the GitHub CLI, from your local clone after creating your branch:

```sh
gh repo fork --remote            # creates your fork, adds it as origin, and renames the old origin to upstream
git push -u origin <branch>
gh pr create --base main
```

Without the GitHub CLI, click **Fork** on GitHub, then run:

```sh
git remote add fork https://github.com/<you>/poki.git
git push -u fork <branch>
```

and then open a pull request on GitHub from your branch into `main` on `JosssphZhou/poki`.

Before opening your pull request, run `npm test` and fill out the [pull request template](.github/PULL_REQUEST_TEMPLATE.md) with what changed, how you tested it, and the two checkboxes. Say in the pull request whether you also tested on a Simulator or a physical iPhone. All checks in the `PR checks` workflow must pass.

By submitting a contribution, you agree to release it under the [AGPL-3.0-only license](LICENSE).

Only include third-party code if its license is compatible with AGPL-3.0-only. Keep the original copyright notice and add the code to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Never commit device screenshots, clipboard contents, pairing records, passcodes, or tokens.
