*** Settings ***
Library    SSHLibrary
Resource    api.resource
Resource    piler.resource

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

Web UI reaches its database
    ${out} =    Execute Command    curl -s ${backend_url}
    Should Contain    ${out}    content="piler email archiver"
    Should Not Contain    ${out}    SQLSTATE

Spool holds mail
    ${rc}    ${out} =    In container    find /var/piler/tmp -type f | wc -l
    Should Be True    ${out} > 0

Configure piler
    [Arguments]    ${host}    ${retention}
    Run task    module/${piler_module_id}/configure-module
    ...    {"host":"${host}","http2https":${config}[http2https],"lets_encrypt":${config}[lets_encrypt],"mail_server":"${config}[mail_server]","retention_days":${retention}}

Restore the configuration
    Configure piler    ${config}[host]    ${config}[retention_days]
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running

Piler conf value
    [Arguments]    ${key}
    ${rc}    ${out} =    In container    grep "^${key}=" /etc/piler/piler.conf
    RETURN    ${out}

*** Test Cases ***
Tag this run
    # Unique per run, so a rerun on the same host is not taken for duplicates.
    ${stamp} =    Evaluate    time.time_ns()    modules=time
    Set Suite Variable    ${run}    web-${stamp}
    ${since} =    Execute Command    date +%s
    Set Suite Variable    ${since}    ${since.strip()}
    # 20_piler keeps its backend URL to itself, so look it up again.
    ${route} =    Piler route
    Set Suite Variable    ${backend_url}    ${route}[url]

Reload keeps the database settings
    # A reload used to rewrite config-site.php without the settings the
    # entrypoint adds, and the web UI lost its database until a restart.
    ${started} =    Execute Command    runagent -m ${piler_module_id} podman inspect piler-app --format '{{.State.StartedAt}}'
    ${rc} =    Execute Command    runagent -m ${piler_module_id} systemctl --user reload piler-app
    ...    return_rc=True    return_stdout=False
    Should Be Equal As Integers    ${rc}    0
    # A broken reload took the pod down some seconds later, not at once.
    Sleep    20 seconds
    ${after} =    Execute Command    runagent -m ${piler_module_id} podman inspect piler-app --format '{{.State.StartedAt}}'
    Should Be Equal    ${after}    ${started}    piler-app restarted after the reload
    Web UI reaches its database

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
        # -o: the master, not a child. -x: piler, not piler-smtp.
        In container    kill "$(pgrep -o -x ${name})"
        # piler-smtp may wait for TIME_WAIT to clear before it binds again.
        Wait Until Keyword Succeeds    120 seconds    2 seconds    Process runs    ${name}
    END
    Send mail    ${run} respawn
    Wait Until Keyword Succeeds    60 seconds    2 seconds
    ...    Archived count should be    ${run} respawn    1

Mail left in the spool is archived after a restart
    # Frozen archiver, then a restart: the spool volume must carry the mails over.
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

A new configuration reaches the route and piler
    [Teardown]    Restore the configuration
    ${cfg} =    Run task    module/${piler_module_id}/get-configuration    {}
    # JSON booleans, since the values go back into a JSON payload.
    ${cfg} =    Evaluate    {k: (str(v).lower() if isinstance(v, bool) else v) for k, v in $cfg.items()}
    Set Suite Variable    ${config}    ${cfg}
    ${host} =    Set Variable    reconfigured.${mail_domain}
    Configure piler    ${host}    365
    ${after} =    Run task    module/${piler_module_id}/get-configuration    {}
    Should Be Equal    ${after}[host]    ${host}
    Should Be Equal As Integers    ${after}[retention_days]    365
    ${route} =    Piler route
    Should Be Equal    ${route}[host]    ${host}
    Set Suite Variable    ${backend_url}    ${route}[url]
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    ${retention} =    Piler conf value    default_retention_days
    Should Be Equal    ${retention}    default_retention_days=365
    ${hostid} =    Piler conf value    hostid
    Should Be Equal    ${hostid}    hostid=${host}
    Wait Until Keyword Succeeds    60 seconds    2 seconds    Web UI reaches its database
