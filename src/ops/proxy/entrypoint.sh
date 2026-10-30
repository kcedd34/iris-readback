#!/bin/sh
# Renders the nginx configuration and ui-config.json from the environment, then starts nginx.
# Needs READBACK_DEMO_PASSWORD (the password of the demo accounts, chosen by the person who deploys; the proxy uses
# the observer account's for the read-only paths). The value is never printed. READBACK_PUBLISH_DEMO_ACCOUNTS=1
# shows the three accounts on the page.
set -eu

if [ -z "${READBACK_DEMO_PASSWORD:-}" ]; then
  echo "readback-ui: READBACK_DEMO_PASSWORD is empty. Set it in the environment or in .env before starting the interface." >&2
  exit 1
fi

# The read-only account's credentials are added by the proxy on the server side; they never reach the browser.
READONLY_AUTH="$(printf 'observer:%s' "$READBACK_DEMO_PASSWORD" | base64 | tr -d '\n')"
export READONLY_AUTH
export IRIS_UPSTREAM="${IRIS_UPSTREAM:-iris:52773}"

envsubst '${READONLY_AUTH} ${IRIS_UPSTREAM}' < /etc/nginx/readback.conf.template > /etc/nginx/conf.d/default.conf

# Everything the page may show about the demo accounts. Passwords are published only on request.
if [ "${READBACK_PUBLISH_DEMO_ACCOUNTS:-0}" = "1" ]; then
  # JSON-escape the password (backslash and double quote) before writing it.
  ESCAPED="$(printf '%s' "$READBACK_DEMO_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"publishDemoAccounts":true,"accounts":[{"user":"communicator1","password":"%s","canConfirm":true},{"user":"communicator2","password":"%s","canConfirm":true},{"user":"observer","password":"%s","canConfirm":false}]}\n' "$ESCAPED" "$ESCAPED" "$ESCAPED" > /usr/share/nginx/html/ui-config.json
  echo "readback-ui: demo accounts are published on the page"
else
  printf '{"publishDemoAccounts":false,"accounts":[]}\n' > /usr/share/nginx/html/ui-config.json
  echo "readback-ui: demo accounts are not published"
fi

exec nginx -g 'daemon off;'
