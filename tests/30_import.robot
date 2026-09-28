*** Settings ***
Library    SSHLibrary
Library    Collections
Library    String
Resource    api.resource

*** Variables ***
${import_user}    u3
# Centres of the three sets stored by seed-import.sh
${TC}    1400000000
${TM}    1500000000
${TA}    1600000000
# Slow enough that a batch of 20 takes 18 seconds, so the stop lands mid-batch.
# pilerimport skips the delay from 1000 up: it puts it all in tv_nsec, and
# nanosleep rejects that.
${stop_delay_ms}    900
# Extra variables for the import that finishes the job, such as
# PILER_IMPORT_DELAY_MS=1 on a host with a large mailbox.
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
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec -i mariadb-app mysql -N -s -e "USE piler; SELECT subject FROM metadata WHERE subject LIKE 'import-test %';"
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    @{actual} =    Split To Lines    ${out}
    Lists Should Be Equal    ${actual}    ${expected}    ignore_order=True

Archived total
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec -i mariadb-app mysql -N -s -e "USE piler; SELECT count(*) FROM metadata;"
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${out.strip()}

Archived import-stop count
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec -i mariadb-app mysql -N -s -e "USE piler; SELECT count(*) FROM metadata WHERE subject LIKE 'import-stop ${stop_tag} %';"
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${out.strip()}

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
    ${before} =    Archived total
    Import emails
    ${after} =    Archived total
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

Import again after a stop
    ${cmd_env} =    Set Variable If    '${import_env}' != ''    env ${import_env}    ${EMPTY}
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} ${cmd_env} import-emails
    ...    return_rc=True    return_stderr=True
    Log    ${err}
    Should Be Equal As Integers    ${rc}    0
    ${count} =    Archived import-stop count
    Should Be Equal As Integers    ${count}    60

Fail when the mail server is unknown
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} env MAIL_SERVER=00000000-0000-0000-0000-000000000000 import-emails
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    1
    Should Contain    ${err}    No IMAP service found
