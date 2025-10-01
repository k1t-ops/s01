#!/bin/bash

set -e
for i in $(seq 1 20); do
  if (echo > /dev/tcp/s01-ca-test/9000) >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for s01-ca-test:9000..."
  sleep 2
done

echo 'Bootstrapping step CLI'
echo "$(step certificate fingerprint /step/certs/root_ca.crt)"
step ca bootstrap --ca-url "https://s01-ca-test:9000" --fingerprint "$(step certificate fingerprint /step/certs/root_ca.crt)" --force
echo 'Creating s01-server-test cert'
step ca certificate s01-server-test /out/test-server.crt /out/test-server.key \
  --san "s01-server-test" \
  --san "server-test" \
  --san "localhost" \
  --provisioner admin \
  --provisioner-password-file /step/secrets/password \
  --not-after 24h \
  --force

echo 'Copying root CA'
cp /step/certs/root_ca.crt /out/root_ca.crt
echo 'Creating client cert'
step ca certificate s01-client /out/client.crt /out/client.key \
  --provisioner admin \
  --provisioner-password-file /step/secrets/password \
  --force

echo 'Creating test-client cert'
step ca certificate s01-test-client /out/test-client.crt /out/test-client.key \
  --san "test-client" \
  --provisioner admin \
  --provisioner-password-file /step/secrets/password \
  --force
