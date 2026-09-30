*** Settings ***
Library    SSHLibrary
Resource    api.resource
Resource    piler.resource
# 20_piler installed the stable release in this scenario; move it to the image
# under test and check nothing archived before is lost.
Suite Setup    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}, nothing to update

*** Variables ***
${SCENARIO}    install
${update_user}    u1
${mail_domain}    domain.test
${smtp_url}    smtp://127.0.0.1:10587
# Such as PILER_IMPORT_DELAY_MS=1, for a large mailbox on a test host.
${import_env}    ${EMPTY}

*** Keywords ***
Archived like should be
    [Arguments]    ${subject_like}    ${expected}
    ${count} =    Piler query    SELECT count(*) FROM metadata WHERE subject LIKE '${subject_like}';
    Should Be Equal As Integers    ${count}    ${expected}

Index is complete
    ${total} =    Piler query    SELECT count(*) FROM metadata;
    ${index} =    Index total
    Should Be Equal As Integers    ${index}    ${total}

Archive state
    ${total} =    Piler query    SELECT count(*) FROM metadata;
    ${distinct} =    Piler query    SELECT count(DISTINCT message_id) FROM metadata;
    ${index} =    Index total
    ${key} =    Key checksum
    ${first} =    Message checksum    ${first_id}
    ${last} =    Message checksum    ${last_id}
    RETURN    ${total} ${distinct} ${index} ${key} ${first} ${last}

*** Test Cases ***
Archive mail with the stable import
    ${stamp} =    Evaluate    time.time_ns()    modules=time
    Set Suite Variable    ${tag}    pre-update-${stamp}
    ${since} =    Evaluate    int(time.time()) - 3600    modules=time
    # Stored with doveadm, not SMTP, so only the stable import-emails archives them.
    FOR    ${i}    IN RANGE    5
        ${out}    ${err}    ${rc} =    Execute Command
        ...    printf 'From: <import@${mail_domain}>\\r\\nTo: <${update_user}@${mail_domain}>\\r\\nSubject: ${tag} ${i}\\r\\nMessage-ID: <${tag}-${i}@${mail_domain}>\\r\\nDate: %s\\r\\n\\r\\nArchived before the update.\\r\\n' "$(date -R)" | runagent -m ${MID} podman exec -i dovecot doveadm save -u ${update_user}
        ...    return_rc=True    return_stderr=True
        Should Be Equal As Integers    ${rc}    0    ${err}
    END
    # -A keeps the stable pilerimport -i to these mails.
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} import-emails -A ${since}
    ...    return_rc=True    return_stderr=True
    Log    ${err}
    Should Be Equal As Integers    ${rc}    0
    Wait Until Keyword Succeeds    60 seconds    2 seconds
    ...    Archived like should be    ${tag} %    5

Record the archive before the update
    ${first} =    Piler query    SELECT piler_id FROM metadata ORDER BY id LIMIT 1;
    ${last} =    Piler query    SELECT piler_id FROM metadata ORDER BY id DESC LIMIT 1;
    Set Suite Variable    ${first_id}    ${first}
    Set Suite Variable    ${last_id}    ${last}
    Wait Until Keyword Succeeds    60 seconds    2 seconds    Index is complete
    ${state} =    Archive state
    Set Suite Variable    ${before}    ${state}
    Log    ${before}

Update to the image under test
    ${rc} =    Execute Command
    ...    api-cli run update-module --data '{"module_url":"${IMAGE_URL}","instances":["${piler_module_id}"]}'
    ...    return_rc=True    return_stdout=False
    Should Be Equal As Integers    ${rc}    0
    ${image} =    Execute Command    runagent -m ${piler_module_id} printenv IMAGE_URL
    Should Be Equal    ${image.strip()}    ${IMAGE_URL}

Piler runs after the update
    Wait Until Keyword Succeeds    120 seconds    5 seconds    Piler daemons are running

The archive is the same after the update
    ${after} =    Archive state
    Should Be Equal    ${after}    ${before}

The update left the old layout behind
    ${volumes} =    Execute Command    runagent -m ${piler_module_id} podman volume ls --format '{{.Name}}'
    Should Contain    ${volumes}    piler_spool
    ${rc} =    Execute Command    runagent -m ${piler_module_id} printenv PILER_IMAGE
    ...    return_rc=True    return_stdout=False
    Should Not Be Equal As Integers    ${rc}    0    PILER_IMAGE is still set, the stable image was not reclaimed

New mail is archived after the update
    ${subject} =    Set Variable    ${tag} after
    ${out}    ${err}    ${rc} =    Execute Command
    ...    printf 'From: <${update_user}@${mail_domain}>\\r\\nTo: <${update_user}@${mail_domain}>\\r\\nSubject: ${subject}\\r\\nMessage-ID: <${tag}-after@${mail_domain}>\\r\\nDate: %s\\r\\n\\r\\nArchived after the update.\\r\\n' "$(date -R)" | curl -s --url ${smtp_url} --mail-from ${update_user}@${mail_domain} --mail-rcpt ${update_user}@${mail_domain} --upload-file -
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    0    ${err}
    Wait Until Keyword Succeeds    60 seconds    2 seconds
    ...    Archived like should be    ${subject}    1

The new import skips what the stable one archived
    ${before_ids} =    Piler query    SELECT count(*) FROM metadata WHERE message_id <> piler_id;
    ${cmd_env} =    Set Variable If    '${import_env}' != ''    env ${import_env}    ${EMPTY}
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} ${cmd_env} import-emails
    ...    return_rc=True    return_stderr=True
    Log    ${err}
    Should Be Equal As Integers    ${rc}    0
    # Mail without a Message-ID is archived again on every import, by design.
    ${after_ids} =    Piler query    SELECT count(*) FROM metadata WHERE message_id <> piler_id;
    Should Be Equal    ${after_ids}    ${before_ids}
