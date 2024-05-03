<?php
define('SITE_NAME_CONST', 'SITE_NAME');

$config[SITE_NAME_CONST] = '{{host}}';
$config['SITE_URL'] = 'https://{{host}}/';

$config['SMTP_DOMAIN'] = $config[SITE_NAME_CONST];
$config['SMTP_FROMADDR'] = 'no-reply@' . $config[SITE_NAME_CONST];
$config['ADMIN_EMAIL'] = 'admin@' . $config[SITE_NAME_CONST];

$config['DECRYPT_BINARY'] = '/usr/bin/pilerget';
$config['DECRYPT_ATTACHMENT_BINARY'] = '/usr/bin/pileraget';
$config['PILER_BINARY'] = '/usr/sbin/piler';
$config['DB_HOSTNAME'] = '127.0.0.1';
$config['DB_PASSWORD'] = 'piler';
$config['ENABLE_MEMCACHED'] = 1;
$memcached_server = ['memcached', 11211];

$config['ENABLE_IMAP_AUTH'] = 1;
$config['RESTORE_OVER_IMAP'] = 1;
$config['IMAP_RESTORE_FOLDER_INBOX'] = 'INBOX';
$config['IMAP_RESTORE_FOLDER_SENT'] = 'Sent';
$config['IMAP_HOST'] = '{{imap_host}}';
$config['IMAP_PORT'] =  993;
$config['IMAP_SSL'] = true;

$config['CAPTCHA_FAILED_LOGIN_COUNT'] = 3;
$config['CUSTOM_EMAIL_QUERY_FUNCTION'] = 'my_custom_func';

function my_custom_func($username = '') {
   $session = Registry::get('session');
   $data = $session->get("auth_data");

   $a = array();

   // Array of domains to be appended
   $domains = {{domains}};

   foreach($data['emails'] as $email) {
      $s = explode("@", $email);
      // Iterate over each domain and append it to the username
      foreach ($domains as $domain) {
          array_push($a, $s[0] . "@" . $domain);
      }
   }

   $data['emails'] = array_merge($data['emails'] , $a);

   $session->set("auth_data", $data);
}
