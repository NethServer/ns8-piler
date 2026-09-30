*** Settings ***
Library    SSHLibrary

*** Keywords ***
Piler query
    [Arguments]    ${sql}
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec -i mariadb-app mysql -N -s -e "USE piler; ${sql}"
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${out.strip()}

Index total
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec manticore-app mysql -h127.0.0.1 -P9306 -N -B -e "SELECT count(*) FROM piler1"
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    # The manticore client draws a table even with -B, padded per version.
    ${count} =    Evaluate    re.search(r'\\d+', $out).group()    modules=re
    RETURN    ${count}

Key checksum
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec piler-app sha256sum /etc/piler/piler.key
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${out.split()[0]}

Message checksum
    [Arguments]    ${piler_id}
    # pilerget decrypts with piler.key: a matching checksum proves key and store still go together.
    ${out}    ${rc} =    Execute Command
    ...    runagent -m ${piler_module_id} podman exec -u piler piler-app pilerget ${piler_id} | sha256sum
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    RETURN    ${out.split()[0]}

Piler daemons are running
    ${out} =    Execute Command    runagent -m ${piler_module_id} podman exec piler-app /etc/init.d/rc.piler status
    Should Contain    ${out}    piler is running
    Should Contain    ${out}    piler-smtp is running
