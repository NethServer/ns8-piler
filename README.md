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

Example:

```
 api-cli run configure-module --agent module/piler1 --data - <<EOF
{
      "host": "piler.domain.com",
      "http2https": true,
      "lets_encrypt": false,
      "mail_server": "c990d0d0-6216-4651-9d0b-d393117d0f7e"
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
  "http2https": true,
  "lets_encrypt": false,
  "mail_server": "c990d0d0-6216-4651-9d0b-d393117d0f7e",
  "mail_server_URL": []
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

Piler is waiting email on a TCP port on a random port(>20000/tcp), to send email to the archive system you need

- Bcc email of your domain to archive@piler.domain.com
- adapt your email server to send email to piler.domain.com on the custom smtp port

This can be done by adapting the `/etc/postfix/transport/`

`piler.domain.com smtp:piler.domain.com:20001`

- postmap the configuration file (if needed) : `postmap /etc/postfix/transport`
- restart postfix : `systemctl restart postfix`

## Import emails to piler

Previous emails are sent automatically one time to piler after the first configuration, but if you want to launch manually the synchronisation, you can trigger this service in the terminal:

    runagent -m piler1
    systemctl --user start --no-block import-email-to-piler.service

Piler should understand and manage about duplicated emails.