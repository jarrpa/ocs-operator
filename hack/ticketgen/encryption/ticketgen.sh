#!/bin/bash

PUBKEY_FILE="${1:-"consumer_keyfile_pub.pem"}"
if [[ ! -f "${PUBKEY_FILE}" ]]; then
  echo "No public key specified or found, generating new public/private key pair"
  openssl genrsa -out consumer_keyfile.pem 4096
  echo "Private key written to consumer_keyfile.pem"
  openssl rsa -in consumer_keyfile.pem -out "${PUBKEY_FILE}" -outform PEM -pubout
  echo "Public key written to ${PUBKEY_FILE}"
fi

# In case the system doesn't have uuidgen, fall back to /dev/urandom
NEW_CONSUMER_ID="$(uuidgen || (cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 36 | head -n 1) || echo "00000000-0000-0000-0000-000000000000")"

declare -A DATA
DATA=(
  ["consumer_id"]="${NEW_CONSUMER_ID}"
)

JSON="{"
for k in ${!DATA[@]}; do
  JSON+="\"$k\":\"${DATA[$k]}\","
done
JSON="${JSON:0:-1}}"

PAYLOAD="$(echo -n "${JSON}" | base64 -w 0)"
SIG="$(echo -n "${JSON}"| openssl pkeyutl -encrypt -pubin -inkey "${PUBKEY_FILE}" | base64 -w 0)"
echo -n "${PAYLOAD}.${SIG}" > onboarding_ticket.txt
echo "Onboarding ticket written to onboarding_ticket.txt"
