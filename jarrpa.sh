#!/bin/bash

set -e

OCP_DIR="${OCP_DIR:-/home/jrivera/ocp/jarrpa-dev}"
OCP_CLUSTER_CONFIG_DIR="${OCP_CLUSTER_CONFIG_DIR:-${OCP_DIR}/aws-dev}"
export OCP_INSTALLER="${OCP_INSTALLER:-${OCP_DIR}/bin/openshift-install}"
export OCP_OC="${OCP_OC:-${OCP_DIR}/bin/oc}"
export KUBECTL="${KUBECTL:-${OCP_DIR}/bin/kubectl}"
export KUBECONFIG="${KUBECONFIG:-${OCP_CLUSTER_CONFIG_DIR}/auth/kubeconfig}"

export IMAGE_TAG="${IMAGE_TAG:-latest}"
export REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-jarrpa}"

export SKIP_CSV_DUMP="${SKIP_CSV_DUMP}"

export OCS_SUBSCRIPTION_CHANNEL="stable-4.9"

help_msg() {
  cat << USAGE
Usage:
  $0 <cmd>

Available Commands:
USAGE

  funcs=$(declare -F | awk '/-f [^_]/{print $NF}' | sort)
  for f in $funcs; do
    awk -v cmd="${f}" '
      BEGIN {
        desc=""
      }
      /^#\s*/ {
        while ($0 ~ /^# /) {
          sub(/^#\s*/, "")
          desc=desc FS $0
          getline
        }
      }
      (index($0, cmd) == 1) {
        printf "  %-20s %s\n", cmd, desc
        exit
      }
      desc=""
    ' < "$0"
  done
}

# Build and push operator image
push_op() {
  make update-generated
  make ocs-operator
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-operator:${IMAGE_TAG}"
}

# make gen-latest-csv
csv() {
  make gen-latest-csv
}

#  aaaaaaa
push_reg() {
  csv
  make gen-latest-deploy-yaml
  make operator-bundle
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-operator-bundle:${IMAGE_TAG}"
  make operator-index OPERATOR_INDEX_NAME="ocs-registry"
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-registry:${IMAGE_TAG}"
}

#  
push_must_gather() {
  make ocs-must-gather
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-must-gather:${IMAGE_TAG}"
}

#  
push_all() {
  push_op
  push_reg
  push_must_gather
}

#  
ci() {
  make ocs-operator-ci
}

#  
deploy() {
  make cluster-deploy
}

#  
destroy() {
  make cluster-clean
}

#  
make_cmd() {
  make "$@"
}

#  
opm() {
  source hack/common.sh
  source hack/ensure-opm.sh
  ${OPM} "$@"
}

#  
ocp_install()
{
  # shellcheck disable=SC2115
  rm -rf "${OCP_CLUSTER_CONFIG_DIR}"
  mkdir "${OCP_CLUSTER_CONFIG_DIR}"
  cp "${OCP_DIR}/install-config-aws.yaml.bak" "${OCP_CLUSTER_CONFIG_DIR}/install-config.yaml"

  ${OCP_INSTALLER} create cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" --log-level debug
}

#  
clear_recordsets()
{
  aws route53 list-resource-record-sets --hosted-zone-id Z3URY6TWQ91KVV | \
    jq '[.ResourceRecordSets[] |select(.Name|test(".*jarrpa-dev.devcluster.openshift.com."))]|map(.| { Action: "DELETE", ResourceRecordSet: .})|{Comment: "Delete jarrpa recordset",Changes: .}' | \
    tee /tmp/recordsets.json
  aws route53 change-resource-record-sets --hosted-zone-id Z3URY6TWQ91KVV --change-batch file:///tmp/recordsets.json
}

#  
ocp_destroy()
{
  ${OCP_INSTALLER} destroy cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" || true
  clear_recordsets
}

#  
functest() {
  make functest ARGS="-ginkgo.focus=\"$*\"" OCS_CLUSTER_UNINSTALL=false
}

#  
oc_dev() {
  # shellcheck disable=SC2068
  ${OCP_OC} "$@"
}

if [ "$1" = "-h" ]; then
  help_msg
  exit
fi

case "$1" in
  make)
    shift
    make_cmd "$@"
  ;;
  oc)
    shift
    # shellcheck disable=SC2068
    oc_dev "$@"
  ;;
  *)
    if [[ $(type -t "${1}") == function ]]; then
      cmd="${1}"
      shift
      ${cmd} "$@"
    else
      help_msg
    fi
  ;;
esac
