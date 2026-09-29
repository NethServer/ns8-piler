*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${smtp_url}    smtp://127.0.0.1:10587
${mail_domain}    domain.test
${web_from}    u1
${web_to}    u3
${admin_cookie}    /tmp/piler-test-admin.txt
${auditor_cookie}    /tmp/piler-test-auditor.txt

*** Keywords ***
Login redirect
    [Arguments]    ${user}    ${password}    ${cookie}
    ${out} =    Execute Command
    ...    curl -sS -D - -o /dev/null -c ${cookie} --data-urlencode username=${user} --data-urlencode password=${password} ${backend_url}/login.php | grep -i '^location:'
    RETURN    ${out.strip()}

Send mail
    [Arguments]    ${subject}    ${attachment}=${FALSE}
    # Through the mail server, so the always_bcc relay to piler is tested too.
    ${from} =    Set Variable    ${web_from}@${mail_domain}
    ${to} =    Set Variable    ${web_to}@${mail_domain}
    ${boundary} =    Set Variable    piler-test-boundary
    IF    ${attachment}
        ${body} =    Catenate    SEPARATOR=\\r\\n
        ...    Content-Type: multipart/mixed; boundary="${boundary}"
        ...    ${EMPTY}
        ...    --${boundary}
        ...    Content-Type: text/plain
        ...    ${EMPTY}
        ...    Mail with an attachment.
        ...    --${boundary}
        ...    Content-Type: text/plain; name="note.txt"
        ...    Content-Disposition: attachment; filename="note.txt"
        ...    Content-Transfer-Encoding: base64
        ...    ${EMPTY}
        ...    YXR0YWNobWVudCBjb250ZW50Cg==
        ...    --${boundary}--
    ELSE
        ${body} =    Catenate    SEPARATOR=\\r\\n    Content-Type: text/plain    ${EMPTY}    Plain mail.
    END
    ${out}    ${err}    ${rc} =    Execute Command
    ...    printf 'From: <${from}>\\r\\nTo: <${to}>\\r\\nSubject: ${subject}\\r\\nMessage-ID: <%s@${mail_domain}>\\r\\nDate: %s\\r\\nMIME-Version: 1.0\\r\\n${body}\\r\\n' "$(date +%s%N)" "$(date -R)" | curl -s --url ${smtp_url} --mail-from ${from} --mail-rcpt ${to} --upload-file -
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    0    ${err}

Piler query
    [Arguments]    ${sql}
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec -i mariadb-app mysql -N -s -e "USE piler; ${sql}"
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${out.strip()}

Archived count should be
    [Arguments]    ${subject_like}    ${expected}
    ${count} =    Piler query    SELECT count(*) FROM metadata WHERE subject LIKE '${subject_like}';
    Should Be Equal As Integers    ${count}    ${expected}

Search finds
    [Arguments]    ${subject}
    ${out} =    Execute Command
    ...    curl -sS -b ${auditor_cookie} --data-urlencode searchtype=simple --data-urlencode "subject=${subject}" --data-urlencode page=0 --data-urlencode sort=1 --data-urlencode order=date ${backend_url}/search-helper.php
    Should Contain    ${out}    ${subject}

In container
    [Arguments]    ${command}
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec piler-app sh -c '${command}'
    ...    return_rc=True
    RETURN    ${rc}    ${out.strip()}

Process runs
    [Arguments]    ${name}
    ${rc}    ${out} =    In container    pgrep -x ${name}
    Should Be Equal As Integers    ${rc}    0    ${name} is not running

Spool holds mail
    ${rc}    ${out} =    In container    find /var/piler/tmp -type f | wc -l
    Should Be True    ${out} > 0

*** Test Cases ***
Tag this run
    # Unique per run, so a rerun on the same host is not taken for duplicates.
    ${stamp} =    Evaluate    time.time_ns()    modules=time
    Set Suite Variable    ${run}    web-${stamp}
    ${since} =    Execute Command    date +%s
    Set Suite Variable    ${since}    ${since.strip()}

Admin logs in to the health page
    ${location} =    Login redirect    admin@local    pilerrocks    ${admin_cookie}
    Should Match Regexp    ${location}    (?i)route=health/health\\s*$

Auditor logs in to the search page
    ${location} =    Login redirect    auditor@local    auditor    ${auditor_cookie}
    Should Match Regexp    ${location}    (?i)search\\.php\\s*$

Mail with an attachment is archived
    Send mail    ${run} attachment    attachment=${TRUE}
    Wait Until Keyword Succeeds    60 seconds    2 seconds
    ...    Archived count should be    ${run} attachment    1
    ${attachments} =    Piler query    SELECT attachments FROM metadata WHERE subject = '${run} attachment';
    Should Be True    ${attachments} >= 1    attachment not recorded

Search finds the archived mail
    Wait Until Keyword Succeeds    60 seconds    2 seconds    Search finds    ${run} attachment

Piler logs reach the journal
    # Only the syslog shim gets them there: a rootless container has no /dev/log.
    ${out} =    Execute Command    journalctl --since @${since} --no-pager -o cat
    Should Match Regexp    ${out}    piler-smtp\\[[0-9]+\\]: received:
    Should Match Regexp    ${out}    piler\\[[0-9]+\\]: .*status=stored

Supervisord restarts killed daemons
    FOR    ${name}    IN    piler-smtp    piler
        # -o is the master among the forked children, -x keeps piler apart
        # from piler-smtp.
        In container    kill "$(pgrep -o -x ${name})"
        # piler-smtp may wait for TIME_WAIT to clear before it binds again.
        Wait Until Keyword Succeeds    120 seconds    2 seconds    Process runs    ${name}
    END
    Send mail    ${run} respawn
    Wait Until Keyword Succeeds    60 seconds    2 seconds
    ...    Archived count should be    ${run} respawn    1

Mail left in the spool is archived after a restart
    # Freeze the archiver so the mails pile up in the spool, then restart:
    # the spool is a volume, so the new container must archive them.
    ${before} =    Piler query    SELECT count(*) FROM metadata;
    In container    for p in $(pgrep -x piler); do kill -STOP "$p"; done
    FOR    ${i}    IN RANGE    20
        Send mail    ${run} spool ${i}
    END
    Wait Until Keyword Succeeds    60 seconds    2 seconds    Spool holds mail
    ${rc} =    Execute Command    runagent -m ${piler_module_id} systemctl --user restart piler-app
    ...    return_rc=True    return_stdout=False
    Should Be Equal As Integers    ${rc}    0
    Wait Until Keyword Succeeds    120 seconds    2 seconds
    ...    Archived count should be    ${run} spool %    20
    ${after} =    Piler query    SELECT count(*) FROM metadata;
    Should Be Equal As Integers    ${after}    ${${before} + 20}
