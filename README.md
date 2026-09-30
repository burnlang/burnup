<p align="center">
    <img src="https://raw.githubusercontent.com/burnlang/burn/master/assets/logo.svg" alt="Burn logo" width="128">
</p>

# burnup

burnup installs, updates and uninstalls the [Burn](https://github.com/burnlang/burn) toolchain.

```sh
curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh
```

This puts everything into `~/.burn/bin` and adds it to your `PATH`:

| Command | What it is |
| --- | --- |
| `burn` | the all-in-one driver: run, build, check, fmt, init, repl, lsp |
| `burni` | the interpreter and REPL |
| `burnc` | the compiler: native executables, JavaScript and bvm bytecode |
| `burnfmt` | the code formatter |
| `burn-lsp` | the language server |
| `bvm` | the Burn virtual machine |
| `ash` | the [package manager](https://github.com/burnlang/ash) |
| `burnup` | this installer |

## Usage

```sh
burnup update       # the newest Burn, ash and burnup
burnup show         # installed versions
burnup uninstall    # remove Burn, downloaded packages and installed commands
burnup help
```

A prebuilt release is used when one exists for your platform; otherwise Burn is built from source, which needs
`git` and Rust 1.85 or newer (`--install-rust` installs Rust with rustup). ash is built from its Burn source with
the freshly installed compiler. Native executables need a C toolchain (`cc`).

## Options

| Option | Description |
| --- | --- |
| `--prefix <dir>` | install into `<dir>` instead of `~/.burn` |
| `--ref <ref>` | build a specific branch, tag or commit of Burn |
| `--ash-ref <ref>` | build a specific branch, tag or commit of ash |
| `--from-source` | always build from source |
| `--install-rust` | install Rust with rustup when `cargo` is missing |
| `--no-ash` | do not install ash |
| `--no-modify-path` | do not touch your shell profile |
| `-q`, `--quiet` | only print errors |

Pass options to the piped script with `sh -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh -s -- --prefix /opt/burn
```

Environment variables: `BURN_HOME` (the prefix), `BURN_REPO` and `BURN_REF`, `ASH_REPO` and `ASH_REF`.

`burnup uninstall` deletes the whole prefix only when burnup created it; otherwise it removes just the files it
installed. It also removes the lines it added to your shell profiles.

## License

[GNU General Public License v3.0](LICENSE)
