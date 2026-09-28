# AGENTS.md

NethServer 8 module for the piler mail archiver. Read README.md for the admin
side and piler-server/README.md for the image. This file lists what the code
does not say.

## Layout

- `imageroot/`: the module. Actions, systemd user units, `bin/` helpers.
- `piler-server/`: the piler container image, built in this repo.
  `build-images.sh` labels the module with the piler-server tag pushed for the
  same commit (`IMAGETAG`), never a hand-written tag.
- `ui/`: the admin UI.
- `tests/`: Robot Framework suites, run on real NS8 nodes.

## Testing

- `robot --dryrun tests` checks syntax only. It runs nothing on a node.
- CI: `test-module.yml` does not start by itself on a branch. Run
  `gh workflow run test-module.yml --ref <branch>` after `Publish images` is
  green for that commit.
- Against a real node, pass `--variable NODE_ADDR:<host>`, and
  `piler_module_id`, `MID` (mail module), `import_user` when not the CI defaults.
  `import_env:PILER_IMPORT_DELAY_MS=1` makes a large mailbox import fast.
- The `update` CI scenario only changes the core version. Nothing tests a piler
  update from the previous release yet.
- `validate-piler-server.yml` uses `workflow_run`, so it only runs once on `main`.

## Traps

- `pilerimport -i` imports nothing since piler 1.4.9 and exits 0
  (jsuto/piler#506). `import-emails` fetches over IMAP and runs `pilerimport -d`.
- `pilerimport -Z` skips the delay from 1000 ms up (whole value in `tv_nsec`).
- `podman exec` does not forward signals. Stop a process inside the container
  yourself, as `import-emails` does.
- A reload must run `fix_configs` from `/entrypoint.sh` again: the template
  lacks the settings the entrypoint adds from `--env`.
- piler logs only through syslog. `config/syslog-to-stderr.c` is an
  `LD_PRELOAD` shim that sends it to stderr, since a rootless container has no
  `/dev/log`.
- `restore-module` installs the image stored in the backup and gives the module
  a new id. Never assume the id after a restore.
- Mail without a `Message-ID` is archived again on every import. Upstream does
  that.

## Conventions

- Conventional Commits, one logical change per commit.
- PRs are squash-merged.
