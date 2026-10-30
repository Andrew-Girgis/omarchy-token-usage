# Contributing

Thanks for helping. Issues and focused pull requests are welcome.

## Reporting a bug

Open an issue at https://github.com/Andrew-Girgis/omarchy-token-usage/issues with your Omarchy version
(`omarchy version`), what you did, what you expected, and the output of
`omarchy-shell girgie.token-usage status`. Leave out tokens, API keys and private paths.

## Working on the plugin

Clone the repo straight into your plugins folder so the shell hot-reloads your edits:

```sh
git clone https://github.com/Andrew-Girgis/omarchy-token-usage ~/.config/omarchy/plugins/girgie.token-usage
omarchy plugin enable girgie.token-usage
```

Before opening a pull request, run:

```sh
python3 -m unittest discover -s tests -v
node --test tests/model.test.cjs
omarchy plugin validate .
```

## Guidelines

- Keep it dependency-free at runtime: QML, the Python standard library or shell tools
  Omarchy already ships.
- Never write, print or pass credentials on a command line; read them at runtime.
- Render untrusted text as plain text (`UsageText.qml`, `Model.sharedText` for tooltips).
- Put user-facing strings in `i18n/en.json`.
- Bump `version` in `manifest.json` when behaviour changes.
- The data comes from the [Wakapi fork](https://github.com/Andrew-Girgis/wakapi)'s
  `/api/dashboard/*` endpoints; new fields need a change there first.

By contributing you agree that your work is released under the [MIT licence](LICENSE).
