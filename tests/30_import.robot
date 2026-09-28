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

*** Keywords ***
Import emails
    [Arguments]    @{args}
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} import-emails @{args}
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

Fail when the mail server is unknown
    ${out}    ${err}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} env MAIL_SERVER=00000000-0000-0000-0000-000000000000 import-emails
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}    1
    Should Contain    ${err}    No IMAP service found
