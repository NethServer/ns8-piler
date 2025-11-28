*** Settings ***
Library    SSHLibrary
Resource    api.resource

*** Variables ***
${curl_timeout}    9

*** Keywords ***
Retry test
    [Arguments]    ${keyword}
    Wait Until Keyword Succeeds    60 seconds    1 second    ${keyword}

Backend URL is reachable
    ${rc} =    Execute Command    curl -f ${backend_url}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0


*** Test Cases ***
Check if piler is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${piler_module_id}    ${output.module_id}

Check if we can retrieve the mail server UUID
    FOR    ${i}    IN RANGE    30
        ${ocfg} =   Run task    module/${piler_module_id}/get-configuration    {}
        Log    ${ocfg}
        Run Keyword If    ${ocfg}    Exit For Loop
        Sleep    2s
    END
    Set Suite Variable     ${mail_server_UUID}    ${ocfg['mail_server_URL'][0]['module_uuid']}
    Should Not Be Empty    ${mail_server_UUID}


Check if piler can be configured
    ${rc} =    Execute Command    api-cli run module/${piler_module_id}/configure-module --data '{"host": "piler.domain.org","http2https": true,"lets_encrypt": false,"mail_server": "${mail_server_UUID}","retention_days": 2557}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Retrieve piler backend URL
    # Assuming the test is running on a single node cluster
    ${response} =    Run task     module/traefik1/get-route    {"instance":"${piler_module_id}"}
    Set Suite Variable    ${backend_url}    ${response['url']}

Check if piler works as expected
    Retry test    Backend URL is reachable

Verify piler frontend title
    ${output} =    Execute Command    curl -s ${backend_url}
    Should Contain    ${output}    content="piler email archiver"

Send email to the mail server
    Put File    ${CURDIR}/test-msa.sh    /tmp/test-msa.sh
    ${mail_server} =    Set Variable    smtp://127.0.0.1:10587
    ${from} =    Set Variable    u1@domain.test
    ${to} =    Set Variable    u3@domain.test
    ${out}  ${err}  ${rc} =    Execute Command
    ...    MAIL_SERVER=${mail_server} bash /tmp/test-msa.sh ${to} ${from}
    ...    return_rc=True    return_stderr=True
    Log    Mail helper stdout: ${out}
    Log    Mail helper stderr: ${err}
    Should Be Equal As Integers    ${rc}  0

Verify if piler has received the email previously sent
    ${success} =    Set Variable    False
    FOR    ${i}    IN RANGE    5
        ${mysql_out}    ${mysql_err}    ${mysql_rc} =    Execute Command
        ...    runagent -m ${piler_module_id} podman exec -i mariadb-app mysql -N -s -e "USE piler; SELECT rcvd FROM counter;"
        ...    return_rc=True    return_stdout=True    return_stderr=True

        Should Be Equal As Integers    ${mysql_rc}    0

        ${mysql_clean} =    Evaluate    str(${mysql_out}).strip()
        Log    Tentative ${i}: rcvd=${mysql_clean}

        Run Keyword If    int(${mysql_clean}) == 1    Set Test Variable    ${success}    True
        Run Keyword If    ${success}    Exit For Loop
        Sleep    1s
    END
    Should Be True    ${success}    the counter is equal to 1
