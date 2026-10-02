*** Settings ***
Library    SSHLibrary
Resource    api.resource

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

Archived count
    [Arguments]    ${subject_like}
    ${count} =    Piler query    SELECT count(*) FROM metadata WHERE subject LIKE '${subject_like}';
    RETURN    ${count}

Archived count should be
    [Arguments]    ${subject_like}    ${expected}
    ${count} =    Archived count    ${subject_like}
    Should Be Equal As Integers    ${count}    ${expected}

Piler route
    ${node} =    Execute Command    runagent -m ${piler_module_id} printenv NODE_ID
    ${traefik} =    Execute Command    redis-cli get node/${node.strip()}/default_instance/traefik
    ${route} =    Run task    module/${traefik.strip()}/get-route    {"instance":"${piler_module_id}"}
    RETURN    ${route}

Piler daemons are running
    ${out} =    Execute Command    runagent -m ${piler_module_id} podman exec piler-app /etc/init.d/rc.piler status
    Should Contain    ${out}    piler is running
    Should Contain    ${out}    piler-smtp is running
