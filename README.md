# Pi for Mavericks

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut its first release.

The [Pi coding agent](https://github.com/earendil-works/pi) (`@earendil-works/pi-coding-agent`) for Mac OS X 10.9 Mavericks.
An unofficial community build, not affiliated with Pi's authors.

It's a launcher named `pi` that does these things for you:

- Install Pi on first run, into Pi's own managed-install tree in your home directory, at the version this release was made for
- Let Pi update itself from then on, the way it does everywhere else
- Swap in a build of Pi's native addon that loads on 10.9, so clipboard and image support work
- Point Pi at 10.9-safe `fd` and `rg`, so it never downloads its own

Pi itself is never in the package. The package holds the launcher, the 10.9 addon, and a Sparkle updater that keeps the launcher current. The updater never touches Pi.

## What you need first

Install these Mavergreen products, then this one; the installer refuses to run without them:

- [Node.js 24 for Mavericks](https://github.com/Mavergreen/nodejs-24/releases/latest)
- [fd for Mavericks](https://github.com/Mavergreen/fd/releases/latest)
- [ripgrep for Mavericks](https://github.com/Mavergreen/rg/releases/latest)

## Before you install

If you installed Pi yourself with Node.js 24's `npm -g`, remove it first. Its `pi` command would clash with this one, so the installer refuses to run while it is there:

```sh
sudo /usr/local/mavergreen/node24/bin/npm -g uninstall @earendil-works/pi-coding-agent
sudo mavergreen unlink node24 && sudo mavergreen link node24
```

This leaves `~/.pi` alone, so your settings, logins and sessions carry over.

## How to use

Install the latest `.pkg` from [Releases](https://github.com/Mavergreen/pi/releases/latest), open a new Terminal window, and run `pi`.

The first run downloads and installs Pi, so it needs the network and can take a minute.

## Uninstall

```sh
sudo mavergreen uninstall pi
```

That removes the launcher and its updater. Pi itself lives in each user's home directory, and each user removes it there.

To remove Pi but keep your settings, logins and sessions:

```sh
rm -rf ~/.pi/agent/install
rm -f ~/.pi/agent/bin/fd ~/.pi/agent/bin/rg
rm -rf ~/"Library/Application Support/dev.mavergreen.pi"
```

To remove everything, including your settings, logins (`auth.json`) and sessions:

```sh
rm -rf ~/.pi
rm -rf ~/"Library/Application Support/dev.mavergreen.pi"
```

If you set `PI_CODING_AGENT_DIR`, use that directory in place of `~/.pi/agent`.
