*** Settings ***
Library    SSHLibrary
Resource    api.resource
Resource    piler.resource

*** Variables ***
${restore_user}    u3
${mail_domain}    domain.test
${smtp_url}    smtp://127.0.0.1:10587

*** Keywords ***
Module environment
    [Arguments]    ${name}
    ${out} =    Execute Command    runagent -m ${piler_module_id} printenv ${name}
    RETURN    ${out.strip()}

The restore has run
    # Without it the checks below would pass against the old module.
    Should Be True    ${restored}    the restore did not complete

*** Test Cases ***
Record the archive before the backup
    ${total} =    Piler query    SELECT count(*) FROM metadata;
    Should Be True    ${total} > 0    the archive must hold mail from the previous suites
    ${sample} =    Piler query    SELECT piler_id FROM metadata ORDER BY id LIMIT 1;
    ${key} =    Key checksum
    ${message} =    Message checksum    ${sample}
    ${index} =    Index total
    ${uuid} =    Module environment    MODULE_UUID
    ${node} =    Module environment    NODE_ID
    Set Suite Variable    ${archived_total}    ${total}
    Set Suite Variable    ${sample_id}    ${sample}
    Set Suite Variable    ${key_sum}    ${key}
    Set Suite Variable    ${message_sum}    ${message}
    Set Suite Variable    ${index_total}    ${index}
    Set Suite Variable    ${module_uuid}    ${uuid}
    Set Suite Variable    ${module_node}    ${node}
    Set Suite Variable    ${old_module_id}    ${piler_module_id}
    Set Suite Variable    ${restored}    ${FALSE}

Use the node local backup repository
    # A repository URL must be unique: reuse the node's one if it exists.
    ${ip} =    Execute Command    redis-cli hget node/${module_node}/vpn ip_address
    ${url} =    Set Variable    webdav:http://${ip.strip()}:4694
    ${repos} =    Run task    cluster/list-backup-repositories    {}
    ${found} =    Evaluate    [r['id'] for r in $repos['repositories'] if r['url'] == $url]
    IF    ${found}
        Set Suite Variable    ${repository}    ${found}[0]
        Set Suite Variable    ${repository_created}    ${FALSE}
    ELSE
        ${out} =    Run task    cluster/add-backup-repository
        ...    {"provider":"cluster","name":"piler-test","url":"${url}","password":"","parameters":{}}
        Set Suite Variable    ${repository}    ${out}[id]
        Set Suite Variable    ${repository_created}    ${TRUE}
    END

Back up piler
    # run-backup skips a disabled backup, so enable it on a far schedule.
    ${bid} =    Run task    cluster/add-backup
    ...    {"name":"piler-test","instances":["${piler_module_id}"],"repository":"${repository}","schedule":"*-12-31 03:17:00","retention":1,"enabled":true}
    Set Suite Variable    ${backup_id}    ${bid}
    # Synchronous: it returns once every node has finished its part.
    Run task    cluster/run-backup    {"id":${backup_id}}
    ${snapshots} =    Run task    cluster/read-backup-snapshots
    ...    {"repository":"${repository}","path":"piler/${module_uuid}"}
    Should Not Be Empty    ${snapshots}
    Set Suite Variable    ${snapshot}    ${snapshots}[-1][id]

Restore piler in place
    ${out} =    Run task    cluster/restore-module
    ...    {"repository":"${repository}","path":"piler/${module_uuid}","snapshot":"${snapshot}","node":${module_node},"replace":true}
    Should Be Equal    ${out}[module_uuid]    ${module_uuid}
    Should Not Be Equal    ${out}[module_id]    ${old_module_id}
    Set Global Variable    ${piler_module_id}    ${out}[module_id]
    Set Suite Variable    ${restored}    ${TRUE}
    ${rc} =    Execute Command    runagent -m ${old_module_id} true
    ...    return_rc=True    return_stdout=False
    Should Not Be Equal As Integers    ${rc}    0    ${old_module_id} must be gone after a replace

Piler runs again after the restore
    [Setup]    The restore has run
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running

The restored piler answers on its route
    [Setup]    The restore has run
    # The restore runs configure-module again, which recreates the route.
    ${route} =    Piler route
    ${out} =    Execute Command    curl -s ${route}[url]
    Should Contain    ${out}    content="piler email archiver"

The archive is restored as it was
    [Setup]    The restore has run
    ${total} =    Piler query    SELECT count(*) FROM metadata;
    Should Be Equal    ${total}    ${archived_total}
    ${index} =    Index total
    Should Be Equal    ${index}    ${index_total}
    ${key} =    Key checksum
    Should Be Equal    ${key}    ${key_sum}
    ${message} =    Message checksum    ${sample_id}
    Should Be Equal    ${message}    ${message_sum}

New email is archived after the restore
    [Setup]    The restore has run
    # Unique per run: the UUID survives the restore.
    ${stamp} =    Evaluate    time.time_ns()    modules=time
    ${subject} =    Set Variable    after-restore ${stamp}
    ${out}    ${err}    ${rc} =    Execute Command
    ...    printf 'From: <u1@${mail_domain}>\\r\\nTo: <${restore_user}@${mail_domain}>\\r\\nSubject: ${subject}\\r\\nMessage-ID: <after-restore-%s@${mail_domain}>\\r\\nDate: %s\\r\\n\\r\\nafter restore\\r\\n' "$(date +%s%N)" "$(date -R)" | curl -s --url ${smtp_url} --mail-from u1@${mail_domain} --mail-rcpt ${restore_user}@${mail_domain} --upload-file -
    ...    return_rc=True    return_stderr=True
    Log    ${err}
    Should Be Equal As Integers    ${rc}    0
    Wait Until Keyword Succeeds    60 seconds    2 seconds
    ...    Archived count should be    ${subject}    1

Remove the test backup
    Run task    cluster/remove-backup    {"id":${backup_id}}
    IF    ${repository_created}
        Run task    cluster/remove-backup-repository    {"id":"${repository}"}
    END
