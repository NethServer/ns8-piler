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

Volume command
    [Arguments]    ${command}
    # The files belong to the container user: only podman unshare can touch them.
    ${out} =    Module command
    ...    podman unshare sh -c "cd \\$(podman volume inspect manticore-data --format {{.Mountpoint}}) && ${command}"
    RETURN    ${out}

Damage manticore file
    [Arguments]    ${name}
    # A power loss leaves a file torn: its magic header is gone.
    Module command    systemctl --user stop piler.service
    Volume command    printf garbage > ${name}
    Module command    systemctl --user start piler.service

Now
    ${now} =    Execute Command    date +%s
    RETURN    ${now}

Journal since
    [Arguments]    ${since}
    # Read as root: the module user cannot open the journal files.
    ${uid} =    Module command    id -u
    ${out} =    Execute Command
    ...    journalctl --since=@${since} --no-pager -o cat _UID=${uid} _SYSTEMD_USER_UNIT=manticore-app.service + _UID=${uid} _SYSTEMD_USER_UNIT=piler-app.service + _UID=${uid} _SYSTEMD_USER_UNIT=piler-reindex.service
    RETURN    ${out}

Journal should contain
    [Arguments]    ${since}    ${text}
    ${out} =    Journal since    ${since}
    Should Contain    ${out}    ${text}

Index should match the archive from id
    [Arguments]    ${first}=1
    # Compared on each try: mail keeps arriving during the test.
    ${total} =    Piler query    SELECT count(*) FROM metadata WHERE deleted=0 AND id >= ${first};
    Index total should be    ${total}

Index should be complete
    Wait Until Keyword Succeeds    300 seconds    5 seconds
    ...    Index should match the archive from id

Restart piler-app
    # Stopping piler-app stops the whole pod: change the index while it runs.
    Module command    systemctl --user restart piler-app.service
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running

Put back tag1
    Module command    systemctl --user stop piler.service
    Volume command    mv -f tag1.meta.orig tag1.meta
    Module command    systemctl --user start piler.service
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running

*** Test Cases ***
The index is complete before the crash
    Index should be complete

A clean restart repairs nothing
    # Sound files must never be moved aside.
    ${since} =    Now
    ${before} =    Volume command    ls | grep -c ^broken- || true
    Module command    systemctl --user restart piler.service
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    ${after} =    Volume command    ls | grep -c ^broken- || true
    Should Be Equal    ${after}    ${before}
    ${out} =    Journal since    ${since}
    Should Not Contain    ${out}    damaged
    Index should be complete

Piler starts again after a torn binlog
    ${since} =    Now
    Damage manticore file    binlog.meta
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    Journal should contain    ${since}    binlog.meta is damaged
    Index should be complete

Piler rebuilds a torn search index
    ${since} =    Now
    Damage manticore file    piler1.meta
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    Journal should contain    ${since}    piler1.meta is damaged
    Index should be complete

A torn tag table is kept and left out of the backup
    [Teardown]    Put back tag1
    ${since} =    Now
    Module command    systemctl --user stop piler.service
    Volume command    cp -p tag1.meta tag1.meta.orig
    Module command    systemctl --user start piler.service
    Damage manticore file    tag1.meta
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running
    Journal should contain    ${since}    tag1.meta is damaged
    # Not repaired: the file stays as it is for a manual fix.
    ${meta} =    Volume command    cat tag1.meta
    Should Be Equal    ${meta}    garbage
    Module command    module-dump-state
    ${dump} =    Module command    cat manticore.sql
    Should Not Contain    ${dump}    `tag1`
    Should Contain    ${dump}    `audit1`
    Module command    module-cleanup-state

The rebuild resumes where it stopped
    # A saved range must not restart from id 1.
    ${max} =    Piler query    SELECT MAX(id) FROM metadata;
    ${half} =    Evaluate    ${max} // 2
    Manticore query    DELETE FROM piler1 WHERE id > ${half}
    ${lo} =    Manticore query    SELECT MAX(id) FROM piler1
    ${next} =    Evaluate    int(re.search(r'\\d+', $lo).group()) + 1    modules=re
    Module command    echo ${next} ${max} > reindex.state
    ${since} =    Now
    Restart piler-app
    Index should be complete
    Journal should contain    ${since}    Rebuilding the search index from id ${next} to
    Module command    test ! -e reindex.state

A saved range above the index end is lowered
    # piler1 lost rows below next since the rebuild stopped.
    ${max} =    Piler query    SELECT MAX(id) FROM metadata;
    ${half} =    Evaluate    ${max} // 2
    Manticore query    TRUNCATE RTINDEX piler1
    Module command    echo ${half} ${max} > reindex.state
    ${since} =    Now
    Restart piler-app
    Index should be complete
    Journal should contain    ${since}    Rebuilding the search index from id 1 to

A torn rebuild state is dropped
    # A power loss right after the rename can leave the file empty or torn.
    Module command    printf garbage > reindex.state
    ${since} =    Now
    Restart piler-app
    Journal should contain    ${since}    reindex.state is damaged
    Module command    test ! -e reindex.state
    Index should be complete

Rebuild the whole index after the test
    # The suites after this one expect a complete index.
    # The saved range keeps a mail arriving after TRUNCATE from hiding the gap.
    ${max} =    Piler query    SELECT MAX(id) FROM metadata;
    Manticore query    TRUNCATE RTINDEX piler1
    Module command    echo 1 ${max} > reindex.state
    Restart piler-app
    Index should be complete
