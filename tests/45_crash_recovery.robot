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
    ${out} =    Module command    journalctl --user --since=-10min --no-pager -t manticore-app -t piler-app
    Should Contain    ${out}    ${text}

Archive total
    ${total} =    Piler query    SELECT count(*) FROM metadata WHERE deleted=0;
    RETURN    ${total}

*** Test Cases ***
Record the index before the crash
    ${index} =    Index total
    ${total} =    Archive total
    Should Be Equal    ${index}    ${total}    the index must be complete before the test
    Set Suite Variable    ${index_total}    ${index}

Piler starts again after a torn binlog
    Damage manticore file    binlog.meta
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    Journal should contain    binlog.meta is damaged
    Index total should be    ${index_total}

Piler rebuilds a torn search index
    Damage manticore file    piler1.meta
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    Journal should contain    piler1.meta is damaged
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index total should be    ${index_total}

The rebuild resumes where it stopped
    # A saved range must not restart from id 1: only ids from next on come back.
    ${max} =    Piler query    SELECT MAX(id) FROM metadata;
    ${next} =    Evaluate    ${max} // 2 + 1
    ${expected} =    Piler query    SELECT count(*) FROM metadata WHERE deleted=0 AND id >= ${next};
    Module command    systemctl --user stop piler-app.service
    Manticore query    TRUNCATE RTINDEX piler1
    Module command    echo ${next} ${max} > reindex.state
    Module command    systemctl --user start piler-app.service
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index total should be    ${expected}
    Module command    test ! -e reindex.state

Rebuild the whole index after the test
    # The suites after this one expect a complete index.
    Module command    systemctl --user stop piler-app.service
    Manticore query    TRUNCATE RTINDEX piler1
    Module command    systemctl --user start piler-app.service
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index total should be    ${index_total}
