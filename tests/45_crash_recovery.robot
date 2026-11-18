*** Settings ***
Library    SSHLibrary
Resource    api.resource
Resource    piler.resource

*** Keywords ***
Module command
    [Arguments]    ${command}
    ${out}    ${rc} =    Execute Command    runagent -m ${piler_module_id} bash -c '${command}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0    ${out}
    RETURN    ${out}

Damage manticore file
    [Arguments]    ${name}
    # A power loss leaves a file torn: its magic header is gone.
    Module command    systemctl --user stop piler.service
    Module command    podman unshare sh -c "printf garbage > \\$(podman volume inspect manticore-data --format {{.Mountpoint}})/${name}"
    Module command    systemctl --user start piler.service

Journal should contain
    [Arguments]    ${text}
    # Read as root: the module user cannot open the journal files.
    ${uid} =    Module command    id -u
    ${out} =    Execute Command
    ...    journalctl --since=-10min --no-pager -o cat _UID=${uid} _SYSTEMD_USER_UNIT=manticore-app.service + _UID=${uid} _SYSTEMD_USER_UNIT=piler-app.service
    Should Contain    ${out}    ${text}

Index should match the archive from id
    [Arguments]    ${first}=1
    # Compared on each try: mail keeps arriving during the test.
    ${total} =    Piler query    SELECT count(*) FROM metadata WHERE deleted=0 AND id >= ${first};
    Index total should be    ${total}

*** Test Cases ***
The index is complete before the crash
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index should match the archive from id

Piler starts again after a torn binlog
    Damage manticore file    binlog.meta
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    Journal should contain    binlog.meta is damaged
    Wait Until Keyword Succeeds    60 seconds    5 seconds
    ...    Index should match the archive from id

Piler rebuilds a torn search index
    Damage manticore file    piler1.meta
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    Journal should contain    piler1.meta is damaged
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index should match the archive from id

The rebuild resumes where it stopped
    # A saved range must not restart from id 1: only ids from next on come back.
    ${max} =    Piler query    SELECT MAX(id) FROM metadata;
    ${next} =    Evaluate    ${max} // 2 + 1
    # Stopping piler-app stops the whole pod: empty the index while it runs.
    Manticore query    TRUNCATE RTINDEX piler1
    Module command    echo ${next} ${max} > reindex.state
    Module command    systemctl --user restart piler-app.service
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index should match the archive from id    ${next}
    Module command    test ! -e reindex.state

Rebuild the whole index after the test
    # The suites after this one expect a complete index.
    # The saved range keeps a mail arriving after TRUNCATE from hiding the gap.
    ${max} =    Piler query    SELECT MAX(id) FROM metadata;
    Manticore query    TRUNCATE RTINDEX piler1
    Module command    echo 1 ${max} > reindex.state
    Module command    systemctl --user restart piler-app.service
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index should match the archive from id
