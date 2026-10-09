<p align="center">
    <img src="https://raw.githubusercontent.com/burnlang/burn/master/assets/logo.svg" alt="Burn logo" width="128">
</p>

# burnup

burnup installs [Burn](https://github.com/burnlang/burn), keeps it up to date and switches between versions. It is
written in Burn.

```sh
curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh
```

This installs burnup, the newest Burn and [ash](https://github.com/burnlang/ash), the package manager, into
`~/.burn` and adds `~/.burn/bin` to your `PATH`.

## Versions

```sh
burnup install 26.1          # a release (26.1 means the newest 26.1.x)
burnup install master        # the newest commit, built from source
burnup default 26.1          # use it everywhere
burnup list                  # installed versions
burnup list --remote         # versions that can be installed
burnup update                # rebuild branch versions that moved, and update ash
burnup uninstall master
```

A version is a release (`26.1`, `v26.1.0`, `^26.1`), `latest`, a branch such as `master`, or a commit. Releases
are downloaded prebuilt; branches and commits are built from source, which needs Rust for bvm. Burn is written in
Burn, so a source build first installs the release named in the checkout's `compiler/STAGE0` and lets it compile
the compiler once.

## Projects

A project can ask for a Burn version in `burn.toml`:

```toml
[package]
name = "github.com/you/app"
burn = "26.1"
```

or with a `.burn-version` file in any folder. `burnup pin 26.1` writes one or the other. Inside that folder,
`burn`, `burni`, `burnc` and the other tools run that version, and burnup installs it the first time it is needed.

```sh
burnup show                  # which version runs here, and why
burnup which burnc           # the file that runs
burnup run master burn check # one command with another version
BURN_TOOLCHAIN=26.1 burn run # or choose with an environment variable
```

The version is chosen in this order: `BURN_TOOLCHAIN`, then the nearest `burn.toml` with a `burn` key or
`.burn-version`, then the default.

## How it works

```text
~/.burn/
├── bin/                burn, burni, burnc, burnfmt, burn-lsp, bvm: small shims that run the active version
│   ├── ash
│   └── burnup
├── toolchains/
│   ├── v26.1.0/        one folder per version
│   └── master/
├── burnup.toml         the default version
├── packages/           packages downloaded by ash
└── env                 adds bin/ to PATH
```

The shims ask burnup which version to use, which adds a few milliseconds to each command. `burnup link dev
~/burn/dist/burn` adds a local build (for example from `sh scripts/package.sh` in a Burn checkout) as the version
`dev`.

## Setup

| Command | What it does |
| --- | --- |
| `burnup ash` | install or update ash |
| `burnup self update` | update burnup itself |
| `burnup self uninstall` | remove Burn, burnup, ash, downloaded packages and the `PATH` lines |

Installer options, passed with `sh -s --`:

| Option | Description |
| --- | --- |
| `--prefix <dir>` | install into `<dir>` instead of `~/.burn` |
| `--toolchain <version>` | the Burn version to install first |
| `--from-source` | build Burn and burnup from source |
| `--install-rust` | install Rust with rustup when a source build needs it |
| `--no-ash` | do not install ash |
| `--no-modify-path` | do not touch your shell profile |

The installer downloads a prebuilt burnup when there is one for your platform. Otherwise it builds Burn once from
source, starting from the release named in `compiler/STAGE0`, and compiles burnup with it.

## Development

```sh
burn run tests/main.bn                        # unit tests
BURNUP_BIN=build/burnup sh tests/e2e.sh       # end-to-end tests with local releases
```

## License

[GNU General Public License v3.0](LICENSE)
