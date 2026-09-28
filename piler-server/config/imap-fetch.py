#!/usr/bin/env python3

# SPDX-License-Identifier: GPL-3.0-or-later
#
# Download a mailbox over IMAP and feed it to pilerimport in small batches.
#
# pilerimport's own IMAP mode (-i) is broken since piler 1.4.9: libcurl 8.18.0
# hands it the untagged "* N FETCH (BODY[] {size}" line together with the body,
# its memmem() lookup fails, and it imports nothing while still exiting 0. See
# https://github.com/jsuto/piler/issues/506. Importing plain .eml files from a
# directory is the path upstream documents as the reliable one.
#
# Usage: imap-fetch.py <server> <user> <tmpdir> <batch> <delay_ms> <la_limit> [pilerimport args]
# The password is read from the first line of stdin, never passed in argv,
# which is world-readable in ps.

import imaplib
import os
import re
import shutil
import subprocess
import sys

# A single FETCH response line carries a whole message, well past the 10k default.
imaplib._MAXLINE = 10000000

server, user, tmpdir = sys.argv[1], sys.argv[2], sys.argv[3]
batch, delay_ms, la_limit = int(sys.argv[4]), sys.argv[5], sys.argv[6]
# Such as -A/-B: pilerimport filters on them itself, as it did in IMAP mode.
extra_args = sys.argv[7:]
password = sys.stdin.readline().rstrip('\n')

batch_dir = os.path.join(tmpdir, 'batch')
failed = 0


def import_batch():
    """Import what has been downloaded, then start the directory over."""
    # -Z paces the archiver, -z parks it while the load average is too high;
    # both live in import_message(), shared by the directory path. pilerimport
    # writes scratch files into the current directory and aborts with
    # "cannot write current directory!" if it is not writable.
    cmd = ['/usr/bin/pilerimport', '-Z', delay_ms, '-d', batch_dir, *extra_args]
    if la_limit != '0':
        # Only when asked for: pilerimport rejects -z 0 outright, even though 0
        # is the value it uses internally to mean "no limit".
        cmd += ['-z', la_limit]
    rc = subprocess.run(cmd, cwd=batch_dir).returncode
    shutil.rmtree(batch_dir, ignore_errors=True)
    os.makedirs(batch_dir, exist_ok=True)
    if rc != 0:
        print(f'pilerimport failed (rc={rc})', file=sys.stderr)
    return rc != 0


conn = imaplib.IMAP4(server, 143)
try:
    conn.login(user, password)
except imaplib.IMAP4.error as e:
    # The caller may hand us an account with no mailbox to log into; say so in
    # one line instead of a traceback.
    print(f'cannot log in as {user}, skipping: {e}', file=sys.stderr)
    sys.exit(2)

# No skip list: pilerimport -i archived every folder, including Trash and Junk,
# so filtering any of them out here would silently shrink what gets archived.
# LIST answers '(\flags) "<separator>" <name>'. The name comes as an atom, a
# quoted string with its own escapes, or a literal split across the tuple.
names = []
for f in conn.list()[1]:
    literal = isinstance(f, tuple)
    if literal:
        f = re.sub(rb'\{\d+\}$', b'', f[0]) + f[1]
    m = re.match(r'\(([^)]*)\) (?:"[^"]*"|NIL) (.*)', f.decode('utf-8', 'replace'))
    if not m:
        continue
    # Shared and Public namespace roots are listed but hold no messages.
    if re.search(r'\\(Noselect|NonExistent)\b', m.group(1), re.I):
        continue
    name = m.group(2)
    # A quoted name is already escaped, send it back as is; anything else gets
    # quoted here, escaping what a quoted string cannot hold raw.
    if literal or not name.startswith('"'):
        name = '"' + name.replace('\\', '\\\\').replace('"', '\\"') + '"'
    names.append(name)

# Start from a clean slate: a run killed mid-batch leaves .eml behind, and
# importing them again would only make pilerimport count duplicates.
shutil.rmtree(tmpdir, ignore_errors=True)
os.makedirs(batch_dir, exist_ok=True)

for folder in names:
    if conn.select(folder, readonly=True)[0] != 'OK':
        print(f'cannot open folder {folder}, skipping', file=sys.stderr)
        continue

    rc, data = conn.search(None, 'ALL')
    nums = data[0].split() if rc == 'OK' and data and data[0] else []
    if not nums:
        continue
    print(f'folder {folder}: {len(nums)} message(s)', file=sys.stderr)

    for i in range(0, len(nums), batch):
        for num in nums[i:i + batch]:
            try:
                rc, data = conn.fetch(num, '(RFC822)')
            except imaplib.IMAP4.error as e:
                print(f'cannot fetch {num.decode()} in {folder}: {e}', file=sys.stderr)
                continue
            if rc != 'OK' or not data or not isinstance(data[0], tuple):
                print(f'cannot fetch {num.decode()} in {folder}', file=sys.stderr)
                continue

            with open(os.path.join(batch_dir, num.decode() + '.eml'), 'wb') as fh:
                fh.write(data[0][1])

        # Empty when every fetch in this slice failed; nothing to hand over.
        if os.listdir(batch_dir):
            failed += import_batch()

conn.logout()
shutil.rmtree(tmpdir, ignore_errors=True)
if failed:
    print(f'{failed} batch(es) failed to import', file=sys.stderr)
    sys.exit(1)
