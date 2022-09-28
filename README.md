# ns8-piler

Start and configure a piler instance.
- The module uses [piler Docker Image](https://hub.docker.com/r/sutoj/piler).
- The code source and the link to raise issues to the project developer can be found at [bitbucket piler](https://bitbucket.org/jsuto/piler/)

## Install

Instantiate the module with:

    add-module ghcr.io/nethserver/piler:latest 1

The output of the command will return the instance name.
Output example:

    {"module_id": "piler1", "image_name": "piler", "image_url": "ghcr.io/nethserver/piler:latest"}

## Configure

Let's assume that the piler instance is named `piler1`.

Launch `configure-module`, by setting the following parameters:
- `host`: a fully qualified domain name for the application
- `http2https`: enable or disable HTTP to HTTPS redirection
- `lets_encrypt`: enable or disable Let's Encrypt certificate
- `imap_host`: set a hostname of an imap server to authenticate user from it

Example:

```
 api-cli run configure-module --agent module/piler1 --data - <<EOF
{
      "host": "piler.domain.com",
      "http2https": true,
      "lets_encrypt": false,
      "imap_host": "imap.domain.com"
    }
EOF
```

The above command will:
- start and configure the piler instance
- configure a virtual host for traefik to access the instance

## Get the configuration
You can retrieve the configuration with

```
api-cli run get-configuration --agent module/piler1 --data null | jq
```

```
{
  "host": "piler.domain.com",
  "imap_host": "imap.domain.com",
  "http2https": true,
  "lets_encrypt": false,
  "tcp_port_archive": "2525"
}
```

## Uninstall

To uninstall the instance:

    remove-module --no-preserve piler1

## Testing

Test the module using the `test-module.sh` script:


    ./test-module.sh <NODE_ADDR> ghcr.io/nethserver/piler:latest

The tests are made using [Robot Framework](https://robotframework.org/)

## send email to piler

Piler is waiting email on a TCP port on 2525, to send email to the archive system you need

- Bcc email of your domain to archive@piler.domain.com
- adapt your email server to send email to piler.domain.com on the custom smtp port

This can be done by adapting the `/etc/postfix/transport/`

`piler.domain.com smtp:piler.domain.com:2525`

- postmap the configuration file (if needed) : `postmap /etc/postfix/transport`
- restart postfix : `systemctl restart postfix`


On NS7 you can set it by

```
db smarthosts set @piler.domain.com recipient Host piler.domain.com Password '' Port 2525 TlsStatus enabled Username '' status enabled
signal-event nethserver-mail-smarthost-save
```
