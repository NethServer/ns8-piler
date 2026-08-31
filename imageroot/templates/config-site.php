<?php
// Written by the container from --env, so absent here: DB_HOSTNAME, DB_DATABASE,
// DB_USERNAME, DB_PASSWORD, SPHINX_HOSTNAME*, $memcached_server, RT.

define('SITE_NAME_CONST', 'SITE_NAME');

$config[SITE_NAME_CONST] = '{{host}}';
$config['SITE_URL'] = 'https://{{host}}/';
$config['PATH_PREFIX'] = '/';

$config['SMTP_DOMAIN'] = $config[SITE_NAME_CONST];
$config['SMTP_FROMADDR'] = 'no-reply@' . $config[SITE_NAME_CONST];
$config['ADMIN_EMAIL'] = 'admin@' . $config[SITE_NAME_CONST];
$config['SMARTHOST'] = '{{provider_ip}}';
$config['SMARTHOST_PORT'] = 25;
$config['SMARTHOST_USER'] = '';
$config['SMARTHOST_PASSWORD'] = '';

$config['DECRYPT_BINARY'] = '/usr/bin/pilerget';
$config['DECRYPT_ATTACHMENT_BINARY'] = '/usr/bin/pileraget';
$config['PILER_BINARY'] = '/usr/sbin/piler';

$config['MEMCACHED_ENABLED'] = 1;

$config['ENABLE_IMAP_AUTH'] = 0;
$config['RESTORE_OVER_IMAP'] = 0;
$config['IMAP_RESTORE_FOLDER_INBOX'] = 'INBOX';
$config['IMAP_RESTORE_FOLDER_SENT'] = 'Sent';
$config['IMAP_HOST'] = '{{provider_ip}}';
$config['IMAP_PORT'] =  993;
$config['IMAP_SSL'] = true;

$config['CAPTCHA_FAILED_LOGIN_COUNT'] = 0;

$config['SPHINX_DRIVER'] = 'sphinx';
$config['SPHINX_DATABASE'] = '';
$config['SPHINX_MAIN_INDEX'] = 'piler1';

# Same unprivileged piler uid runs php-fpm and the daemon, so reload directly
# via the init script - no sudo/systemctl (avoids jsuto/piler#479).
$config['RELOAD_COMMAND'] = '/etc/init.d/rc.piler reload';
