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

help_msg() {
  echo -e "$0 <cmd>
  push                Build and push all container images
  push-op             Build and push operator image
  push-reg            Build and push registry image
  push-must-gather    Build and push must-gather image
  csv                 make gen-latest-csv
  ci                  make ocs-operator-ci
  deploy              make cluster-deploy
  destroy             make cluster-clean
  oc                  Use custom oc binary
  functest            make functest
"
}
push_op() {
  make update-generated
  make ocs-operator
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-operator:${IMAGE_TAG}"
}

csv() {
  make gen-latest-csv
}

push_reg() {
  csv
  make gen-latest-deploy-yaml
  make operator-bundle
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-operator-bundle:${IMAGE_TAG}"
  make operator-index OPERATOR_INDEX_NAME="ocs-registry"
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-registry:${IMAGE_TAG}"
}

push_must_gather() {
  make ocs-must-gather
  docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-must-gather:${IMAGE_TAG}"
}

push_all() {
  push_op
  push_reg
  push_must_gather
}

ci() {
  make ocs-operator-ci
}

deploy() {
  make cluster-deploy
}

destroy() {
  make cluster-clean
}

make_cmd() {
  make "$@"
}

opm() {
  source hack/common.sh
  source hack/ensure-opm.sh
  ${OPM} "$@"
}

ocp_install()
{
  # shellcheck disable=SC2115
  rm -rf "${OCP_CLUSTER_CONFIG_DIR}"
  mkdir "${OCP_CLUSTER_CONFIG_DIR}"
  cp "${OCP_DIR}/install-config-aws.yaml.bak" "${OCP_CLUSTER_CONFIG_DIR}/install-config.yaml"

  ${OCP_INSTALLER} create cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" --log-level debug
}

clear_recordsets()
{
  aws route53 list-resource-record-sets --hosted-zone-id Z3URY6TWQ91KVV | \
    jq '[.ResourceRecordSets[] |select(.Name|test(".*jarrpa-dev.devcluster.openshift.com."))]|map(.| { Action: "DELETE", ResourceRecordSet: .})|{Comment: "Delete jarrpa recordset",Changes: .}' | \
    tee /tmp/recordsets.json
  aws route53 change-resource-record-sets --hosted-zone-id Z3URY6TWQ91KVV --change-batch file:///tmp/recordsets.json
}

ocp_destroy()
{
  ${OCP_INSTALLER} destroy cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" || true
  clear_recordsets
}

functest() {
  make functest ARGS="-ginkgo.focus=\"$*\"" OCS_CLUSTER_UNINSTALL=false
}

oc_dev() {
  # shellcheck disable=SC2068
  ${OCP_OC} "$@"
}

if [ "$1" = "-h" ]; then
  help_msg
  exit
fi

case "$1" in
  push)
    push_all
  ;;
  push-op)
    push_op
  ;;
  push-reg)
    push_reg
  ;;
  push-must-gather)
    push_must_gather
  ;;
  csv)
    csv
  ;;
  ci)
    ci
  ;;
  deploy)
    deploy
  ;;
  destroy)
    destroy
  ;;
  make)
    shift
    make_cmd "$@"
  ;;
  opm)
    shift
    opm "$@"
  ;;
  ocp-install)
    ocp_install
  ;;
  ocp-destroy)
    ocp_destroy
  ;;
  oc)
    shift
    # shellcheck disable=SC2068
    oc_dev "$@"
  ;;
  functest)
    shift
    # shellcheck disable=SC2068
    functest "$@"
  ;;
esac
