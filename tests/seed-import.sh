#!/bin/bash
#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Store 12 messages with doveadm, not SMTP, so only import-emails archives them.
# Three sets of four, 2 hours and 1 minute each side of distant timestamps.

set -e

mail_module=${1:?missing mail module id}
user=${2:?missing user}

doveadm() {
    runagent -m "${mail_module}" podman exec -i dovecot doveadm "$@"
}

seed() {
    local set=$1 folder=$2 t=$3 off
    doveadm mailbox create -u "${user}" "${folder}"
    for off in -7200 -60 +60 +7200; do
        doveadm save -u "${user}" -m "${folder}" <<EOF
From: <import@domain.test>
To: <${user}@domain.test>
Subject: import-test ${set} ${off}
Message-ID: <import-test-${set}${off}@domain.test>
Date: $(date -u -R -d "@$((t + off))")
MIME-Version: 1.0
Content-Type: text/plain; charset="UTF-8"

Set ${set}, ${off} seconds from ${t}.
EOF
    done
}

seed C 'import-test' 1400000000
doveadm mailbox create -u "${user}" 'Archivés'
seed M 'Archivés/2017' 1500000000
seed A 'piler "import"' 1600000000
