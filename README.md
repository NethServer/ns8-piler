# ns8-piler

Email archiving for NethServer 8. The module archives a copy of every email
sent or received by a [Mail](https://github.com/NethServer/ns8-mail) instance,
keeps it for a configurable number of days, and lets you search it from a web UI.

- The module runs [piler](https://github.com/jsuto/piler) inside a container
  image this repo builds itself, `piler-server/` - see
  [piler-server/README.md](piler-server/README.md) for the image (rootless
  design, environment variables, CI).
- To raise an issue against piler itself, use [github piler](https://github.com/jsuto/piler).

## Requirements

A Mail module must already be installed in the cluster.

## Install

Instantiate the module with:

    add-module ghcr.io/nethserver/piler:latest 1

The output of the command will return the instance name.
Output example:

    {"module_id": "piler1", "image_name": "piler", "image_url": "ghcr.io/nethserver/piler:latest"}

## Update

Updates start from 1.2.3. The `org.nethserver.min-from` label keeps this version
from being offered to an older instance, so update that one to 1.2.3 first.

## Configure

Let's assume that the piler instance is named `piler1`.

Launch `configure-module`, by setting the following parameters:
- `host`: a fully qualified domain name for the application
- `http2https`: enable or disable HTTP to HTTPS redirection
- `lets_encrypt`: enable or disable Let's Encrypt certificate
- `mail_server`: UUID of the mail module whose mail piler archives, run
  `runagent -m mail1 printenv MODULE_UUID` to get it
- `retention_days`: how many days piler keeps an email. Piler sets the expiry
  date when it archives an email, so a change applies only to emails archived
  after it

Example:

```
 api-cli run configure-module --agent module/piler1 --data - <<EOF
{
      "host": "piler.domain.com",
      "http2https": true,
      "lets_encrypt": false,
      "mail_server": "c990d0d0-6216-4651-9d0b-d393117d0f7e",
      "retention_days": 2557
    }
EOF
```

The above command will:
- start and configure the piler instance
- configure a virtual host for traefik to access the instance

The mail server cannot be changed later. To archive another mail server, remove
piler, install it again on the new mail server, then run `import-emails` (see
below). Removing piler deletes the whole archive: emails that are no longer in
the mailboxes cannot be imported again.

## How mail reaches piler

`configure-module` sets the mail server up for you. It adds an always BCC to
`archive@piler1` and a relay rule that sends this address to the piler SMTP
port. Nothing has to be changed by hand on the mail server.

## Default accounts

Piler starts with two local accounts:

- `admin@local`, password `pilerrocks`: manages users and settings, cannot read emails
- `auditor@local`, password `auditor`: can search and read every archived email

These passwords are public. Change them from the piler web UI right after the
first configuration.

## Get the configuration
You can retrieve the configuration with

```
api-cli run get-configuration --agent module/piler1 --data null | jq
```

```
{
  "host": "piler.domain.com",
  "http2https": true,
  "lets_encrypt": false,
  "mail_server": "c990d0d0-6216-4651-9d0b-d393117d0f7e",
  "mail_server_URL": [],
  "retention_days": 2557,
  "is_default_password_admin": true,
  "is_default_password_auditor": true,
  "always_bcc_correctly_set": true,
  "piler_is_running": true
}
```

## Custom configuration files

You can modify the configuration by adding a config-site.php.local file to the folder `/home/piler1/.config/state/templates`, if the file is present it is used instead of the default one and it is included in the backup of the module

```
runagent -m piler1
# copy the source file to be customized
cp ../templates/config-site.php templates/config-site.php.local 
# edit the file
nano templates/config-site.php.local
# restart the service
systemctl restart --user piler.service
```

The container writes some keys itself, on every start, from the `--env` values in
`piler-app.service`. Editing these in a `.local` copy has no effect; change the
matching `--env` instead:

`DB_HOSTNAME`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `SPHINX_HOSTNAME`,
`SPHINX_HOSTNAME_READONLY`, `$memcached_server`, `RT`, and in `piler.conf` the
keys its own header lists.

`RT` is there because manticore runs in its own container and the image ships no
`indexer`, so real-time indexing is the only mode it can do. Nothing to set,
nothing to remember.

Everything else is yours, including `SPHINX_MAIN_INDEX`, `MEMCACHED_ENABLED`,
`RELOAD_COMMAND` and the binary paths: the container supplies those only when the
file does not already state them.

## Let mail users log in

By default only the local accounts can log in, so users who lose an email must
ask the auditor, who can read every archived email. With IMAP login enabled,
each user logs in with their own mail account and searches only their own
emails. Users get back lost emails by themselves, and fewer people need the
auditor account.

IMAP login is off by default. To turn it on, create the custom configuration
file described in [Custom configuration files](#custom-configuration-files) and
set:

```php
$config['ENABLE_IMAP_AUTH'] = 1;
```

Keep the other `IMAP_*` values: `IMAP_HOST` is filled with the address of the
configured mail server, and port 993 with SSL works with it. Restart piler:

    runagent -m piler1 systemctl --user restart piler.service

Users log in with their full email address, like `john@example.com`, and their
mail password. Piler shows the emails sent to or from that address. A login
without the domain is accepted too, but shows no email. The local accounts
`admin@local` and `auditor@local` keep working.

## Uninstall

To uninstall the instance:

    remove-module --no-preserve piler1

Removing the instance also removes the always BCC and the relay rule from the
mail server.

## Backup

The backup includes the database, the archive, the manticore index and the
custom templates. It also includes `piler.key`: the archive is encrypted with it
and cannot be read without it. The spool of emails not yet archived is left out
on purpose, restoring it would mix unarchived mail into an older database.

A restore needs the mail module the backup was taken from, with the same UUID.
If that mail module is gone, the restore fails with `mail_server_is_not_valid`.

## CI

This repository publishes two images from one pipeline: `build-piler-server.yml`
builds `ghcr.io/nethserver/piler-server` from `piler-server/Dockerfile`, then
`publish-images.yml` builds the module image `ghcr.io/nethserver/piler`, whose
`org.nethserver.images` label names the tag the first job just pushed. See
[piler-server/README.md](piler-server/README.md#ci) for the piler-server-specific
workflows.

## Running tests locally

This module uses the NS8 standard testing infrastructure. For instructions on how to run the test suite locally, refer to the [Running tests locally](https://github.com/NethServer/ns8-github-actions/blob/v1/README.md#running-tests-locally) section of NS8 GitHub Actions.

## Import emails to piler

Piler archives new emails as they are delivered. Emails already in the mailboxes are not imported automatically. To import every mailbox of the configured mail server, run:

    runagent -m piler1 import-emails

To import only a time range, pass a unix timestamp. The emails are filtered on their `Date` header:

    runagent -m piler1 import-emails -A 1735689600                 # sent after
    runagent -m piler1 import-emails -B 1735689600                 # sent before
    runagent -m piler1 import-emails -A 1704067200 -B 1735689600   # both

The import can be run again safely: piler skips the emails it already has. Emails without a `Message-ID` header are the exception, piler archives them again on every run.

Only one import runs at a time. Stopping it with Ctrl-C finishes the batch in progress first.

To go easier on a busy server, raise the pause between two emails, 200 ms by default. Keep it under 1000 ms: from 1000 up, pilerimport silently skips the pause.

    runagent -m piler1 env PILER_IMPORT_DELAY_MS=500 import-emails

Other variables, passed the same way:

- `PILER_IMPORT_BATCH`: emails fetched before each pilerimport run, 20 by default.
- `PILER_IMPORT_LOAD_LIMIT`: pause the archiver while the 1 minute load average is above this value. 0, the default, turns it off.
- `PILER_IMPORT_SKIP_USERS`: comma separated users never imported, `root` by default.
- `PILER_IMPORT_TMPDIR`: where emails wait inside the container before import, `/var/piler/imap` by default.

## Recreate the index

This is a troubleshooting task, use it only when you have to or you are advised to rebuild the manticore index from scratch.

Piler relies heavily on the manticore index data. The reindex utility is for healing it if anything goes wrong.

    runagent -m piler1 podman exec -w /var/piler/imap piler-app reindex -a -p
