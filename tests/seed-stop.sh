#!/bin/bash
#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Store 60 messages in one folder: three batches of 20, so an import stopped
# in the middle has a batch to finish and more left behind.

set -e

mail_module=${1:?missing mail module id}
user=${2:?missing user}
# Unique per run, so a rerun on the same host is not taken for duplicates.
tag=${3:?missing tag}
folder='import-stop'

runagent -m "${mail_module}" podman exec dovecot doveadm mailbox create -u "${user}" "${folder}"
for i in $(seq 1 60); do
    runagent -m "${mail_module}" podman exec -i dovecot doveadm save -u "${user}" -m "${folder}" <<EOF
From: <import@domain.test>
To: <${user}@domain.test>
Subject: import-stop ${tag} ${i}
Message-ID: <import-stop-${tag}-${i}@domain.test>
Date: $(date -u -R)
MIME-Version: 1.0
Content-Type: text/plain; charset="UTF-8"

Message ${i} of 60.
EOF
done
