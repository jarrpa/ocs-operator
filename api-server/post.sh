#!/bin/bash

curl 0.0.0.0:8888/storagecluster \
  -X POST \
  -H 'Content-Type: application/json' \
  -d "${1}"