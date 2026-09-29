#!/usr/bin/env python3

# SPDX-License-Identifier: GPL-3.0-or-later
#
# Download a mailbox over IMAP and feed it to pilerimport -d in batches:
# pilerimport -i imports nothing and exits 0 since piler 1.4.9 (jsuto/piler#506).
#
# Usage: imap-fetch.py <server> <user> <tmpdir> <batch> <delay_ms> <la_limit> [pilerimport args]
# The password comes on stdin, argv shows in ps.

import imaplib
import os
import re
import shutil
import signal
import subprocess
import sys

# One FETCH line carries a whole message, past the 10k default.
imaplib._MAXLINE = 10000000

server, user, tmpdir = sys.argv[1], sys.argv[2], sys.argv[3]
batch, delay_ms, la_limit = int(sys.argv[4]), sys.argv[5], sys.argv[6]
# Such as -A/-B, which pilerimport applies itself.
extra_args = sys.argv[7:]
password = sys.stdin.readline().rstrip('\n')

batch_dir = os.path.join(tmpdir, 'batch')
failed = 0
stopping = False


# Only a flag: killing pilerimport mid-message could store it half.
def stop(signum, frame):
    global stopping
    stopping = True


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)


def import_batch():
    """Import what has been downloaded, then start the directory over."""
    # pilerimport writes scratch files in its current directory, which must be writable.
    cmd = ['/usr/bin/pilerimport', '-Z', delay_ms, '-d', batch_dir, *extra_args]
    if la_limit != '0':
        # pilerimport rejects -z 0, though 0 is its own "no limit".
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
    print(f'cannot log in as {user}, skipping: {e}', file=sys.stderr)
    sys.exit(2)

# Every folder, Trash and Junk included, as pilerimport -i did.
# The name comes as an atom, an escaped quoted string, or a literal in a tuple.
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
    # A quoted name is already escaped, send it back as is.
    if literal or not name.startswith('"'):
        name = '"' + name.replace('\\', '\\\\').replace('"', '\\"') + '"'
    names.append(name)

# A run killed mid-batch leaves .eml behind.
shutil.rmtree(tmpdir, ignore_errors=True)
os.makedirs(batch_dir, exist_ok=True)

for folder in names:
    if stopping:
        break
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
            if stopping:
                break
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

        if os.listdir(batch_dir):
            failed += import_batch()
        if stopping:
            break

conn.logout()
shutil.rmtree(tmpdir, ignore_errors=True)
if stopping:
    print('stopped on request, the rest of the mailbox is not imported', file=sys.stderr)
    sys.exit(143)
if failed:
    print(f'{failed} batch(es) failed to import', file=sys.stderr)
    sys.exit(1)
