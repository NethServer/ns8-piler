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

## Traps

- `pilerimport -i` imports nothing since piler 1.4.9 and exits 0
  (jsuto/piler#506). `import-emails` fetches over IMAP and runs `pilerimport -d`.
- `reindex` from a read-only work dir prints `cannot write current directory!`,
  indexes nothing and exits 0. Run it with `-w /var/piler/imap`.
- Tags, notes and audit live only in manticore (`tag1`, `note1`, `audit1`).
  `reindex` rebuilds `piler1` only, so the backup dumps the other three.
- A torn `binlog.meta` makes searchd die on start (`invalid meta file`).
  `manticore-repair` moves the binlog and a damaged `piler1` aside, never
  `tag1`, `note1` or `audit1`.
- `index-check` must run before piler-smtp takes mail: one new indexed mail
  raises `MAX(id)` of `piler1` and hides the gap. It saves the range in
  `state/reindex.state`, which `reindex-resume` works through in chunks.
  `module-cleanup-state` must not remove it.
- `pilerimport -Z` skips the delay from 1000 ms up (whole value in `tv_nsec`).
- `podman exec` does not forward signals. Stop a process inside the container
  yourself, as `import-emails` does.
- A reload must run `fix_configs` from `/entrypoint.sh` again: the template
  lacks the settings the entrypoint adds from `--env`. Never HUP piler-app:
  supervisord restarts php-fpm, which finds its socket still held, goes FATAL
  and takes the pod down. `rc.piler reload` rereads piler.conf.
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
