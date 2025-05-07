<?php
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
$config['DB_HOSTNAME'] = '127.0.0.1';
$config['DB_PASSWORD'] = 'piler';
$config['DB_DATABASE'] = 'piler';
$config['DB_USERNAME'] = 'piler';

$config['MEMCACHED_ENABLED'] = 1;
$memcached_server = ['127.0.0.1', 11211];

$config['ENABLE_IMAP_AUTH'] = 0;
$config['RESTORE_OVER_IMAP'] = 0;
$config['IMAP_RESTORE_FOLDER_INBOX'] = 'INBOX';
$config['IMAP_RESTORE_FOLDER_SENT'] = 'Sent';
$config['IMAP_HOST'] = '{{provider_ip}}';
$config['IMAP_PORT'] =  993;
$config['IMAP_SSL'] = true;

$config['CAPTCHA_FAILED_LOGIN_COUNT'] = 0;

$config['SPHINX_HOSTNAME'] = '127.0.0.1:9306';
$config['SPHINX_HOSTNAME_READONLY'] = '127.0.0.1:9307';
$config['SPHINX_MAIN_INDEX'] = 'piler1';
$config['RT'] = 1;
