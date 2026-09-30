*** Settings ***
Library    SSHLibrary
Library    Collections
Library    String
Resource    api.resource
Resource    piler.resource

*** Variables ***
${import_user}    u3
# A second mailbox of the domain, disabled for a while by the multi-user test.
${other_user}    u1
# Centres of the three sets stored by seed-import.sh
${TC}    1400000000
${TM}    1500000000
${TA}    1600000000
# A batch of 20 takes 18s, so the stop lands mid-batch. pilerimport skips any
# delay from 1000 up (all of it in tv_nsec, which nanosleep rejects).
${stop_delay_ms}    900
# Such as PILER_IMPORT_DELAY_MS=1, for a large mailbox on a test host.
${import_env}    ${EMPTY}

*** Keywords ***
Import emails
    [Arguments]    @{args}
    ${cmd_args} =    Catenate    @{args}
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} import-emails ${cmd_args}
    ...    return_rc=True    return_stderr=True
    Log    ${err}
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${err}

Archived import tests should be
    [Arguments]    @{expected}
    ${out} =    Piler query    SELECT subject FROM metadata WHERE subject LIKE 'import-test %';
    @{actual} =    Split To Lines    ${out}
    Lists Should Be Equal    ${actual}    ${expected}    ignore_order=True

Archived import-stop count
    ${count} =    Archived count    import-stop ${stop_tag} %
    RETURN    ${count}

Store a tagged mail
    [Arguments]    ${user}    ${subject}
    # Before any disable: dovecot no longer knows a disabled user.
    ${out}    ${err}    ${rc} =    Execute Command
    ...    printf 'From: <import@domain.test>\r\nTo: <${user}@domain.test>\r\nSubject: ${subject}\r\nMessage-ID: <%s@domain.test>\r\nDate: %s\r\n\r\nmulti-user test\r\n' "$(date +%s%N)" "$(date -R)" | runagent -m ${MID} podman exec -i dovecot doveadm save -u ${user}
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    0    ${err}

Set mailbox enabled
    [Arguments]    ${user}    ${enabled}
    Run task    module/${MID}/set-mailbox-enabled    {"user":"${user}","enabled":${enabled}}

Import recent emails
    ${cmd_env} =    Set Variable If    '${import_env}' != ''    env ${import_env}    ${EMPTY}
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} ${cmd_env} import-emails -A ${multi_since}
    ...    return_rc=True    return_stderr=True
    Log    ${err}
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${err}

Import-stop batch has started
    ${count} =    Archived import-stop count
    Should Be True    ${count} > 0

No import is left in the container
    ${out}    ${rc} =    Execute Command
    ...    pgrep -f '^(python3 /usr/local/bin/piler-imap-fetch|/usr/bin/pilerimport) '
    ...    return_rc=True
    Should Not Be Equal As Integers    ${rc}    0    still running: ${out}

*** Test Cases ***
Store emails in a mailbox without delivering them
    Put File    ${CURDIR}/seed-import.sh    /tmp/seed-import.sh
    ${out}    ${err}    ${rc} =    Execute Command
    ...    bash /tmp/seed-import.sh ${MID} ${import_user}
    ...    return_rc=True    return_stderr=True
    Log    ${err}
    Should Be Equal As Integers    ${rc}    0
    Archived import tests should be

Import only emails sent before a timestamp
    Import emails    -B    ${TC}
    Archived import tests should be    import-test C -7200    import-test C -60

Import only emails sent after a timestamp
    Import emails    -A    ${TA}
    Archived import tests should be    import-test C -7200    import-test C -60
    ...    import-test A +60    import-test A +7200

Import only emails sent between two timestamps
    ${after} =    Evaluate    ${TM} - 3600
    ${before} =    Evaluate    ${TM} + 3600
    Import emails    -A    ${after}    -B    ${before}
    Archived import tests should be    import-test C -7200    import-test C -60
    ...    import-test A +60    import-test A +7200
    ...    import-test M -60    import-test M +60

Import every email left
    ${err} =    Import emails
    Should Contain    ${err}    Importing ${import_user} to
    Archived import tests should be
    ...    import-test C -7200    import-test C -60    import-test C +60    import-test C +7200
    ...    import-test M -7200    import-test M -60    import-test M +60    import-test M +7200
    ...    import-test A -7200    import-test A -60    import-test A +60    import-test A +7200

Import again without duplicates
    ${before} =    Piler query    SELECT count(*) FROM metadata;
    Import emails
    ${after} =    Piler query    SELECT count(*) FROM metadata;
    Should Be Equal    ${before}    ${after}

Stop an import in the middle of a batch
    ${tag} =    Evaluate    int(time.time())    modules=time
    Set Suite Variable    ${stop_tag}    ${tag}
    Put File    ${CURDIR}/seed-stop.sh    /tmp/seed-stop.sh
    ${out}    ${err}    ${rc} =    Execute Command
    ...    bash /tmp/seed-stop.sh ${MID} ${import_user} ${stop_tag}
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    0    ${err}
    ${out}    ${err}    ${rc} =    Execute Command
    ...    systemd-run --unit=piler-import-stop-test --collect runagent -m ${piler_module_id} env PILER_IMPORT_DELAY_MS=${stop_delay_ms} import-emails
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    0    ${err}
    Wait Until Keyword Succeeds    300 seconds    1 second    Import-stop batch has started
    Execute Command    systemctl stop piler-import-stop-test
    Wait Until Keyword Succeeds    60 seconds    2 seconds    No import is left in the container
    ${spool} =    Execute Command    runagent -m ${piler_module_id} podman exec piler-app ls -A /var/piler/imap
    Should Be Empty    ${spool}
    # The batch in hand is finished, the ones after it are not started.
    ${count} =    Archived import-stop count
    Should Be True    ${count} % 20 == 0 and 0 < ${count} < 60    ${count} archived

Import every enabled mailbox and skip a disabled one
    [Teardown]    Set mailbox enabled    ${other_user}    true
    ${stamp} =    Evaluate    time.time_ns()    modules=time
    Set Suite Variable    ${multi}    multi-${stamp}
    ${since} =    Evaluate    int(time.time()) - 3600    modules=time
    Set Suite Variable    ${multi_since}    ${since}
    Store a tagged mail    ${import_user}    ${multi} ${import_user}
    Store a tagged mail    ${other_user}    ${multi} ${other_user}
    Set mailbox enabled    ${other_user}    false
    ${err} =    Import recent emails
    Should Contain    ${err}    Importing ${import_user} to
    Should Contain    ${err}    Skipped ${other_user}, mailbox is disabled
    # The window also covers what the stopped import left behind.
    Archived count should be    import-stop ${stop_tag} %    60
    Archived count should be    ${multi} ${import_user}    1
    Archived count should be    ${multi} ${other_user}    0

A mailbox enabled again is imported
    ${err} =    Import recent emails
    Should Contain    ${err}    Importing ${other_user} to
    Archived count should be    ${multi} ${other_user}    1
    Archived count should be    ${multi} ${import_user}    1

Fail when the mail server is unknown
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} env MAIL_SERVER=00000000-0000-0000-0000-000000000000 import-emails
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    1
    Should Contain    ${err}    No IMAP service found
