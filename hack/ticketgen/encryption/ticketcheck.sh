#!/bin/bash

set -e

usage() {
  echo "USAGE: $0 <private_key_file> [<ticket_file>]"
}

if [ $# == 0 ]; then
  echo "Missing argument for key file!"
  usage
  exit 1
fi

KEY_FILE="${1}"
if [[ ! -f "${KEY_FILE}" ]]; then
  echo "Key file '${KEY_FILE}' not found!"
  usage
  exit 1
fi

TICKET_FILE="${2:-onboarding_ticket.txt}"
TICKET="$(cat "${TICKET_FILE}")"

IFS='.' read -ra TICKET_ARR <<< "${TICKET}"
PAYLOAD="${TICKET_ARR[0]}"
SIG="${TICKET_ARR[1]}"

JSON="$(echo "${PAYLOAD}" | base64 -d)"
DECRYPTED="$(echo -n "${SIG}" | base64 -d | openssl pkeyutl -decrypt -inkey "${KEY_FILE}")"

if [[ "${JSON}" == "${DECRYPTED}" ]]; then
  echo "Successfully validated data:"
  echo "${DECRYPTED}"
else
  echo "INVALID: Could not verify payload with attached signature"
fi
