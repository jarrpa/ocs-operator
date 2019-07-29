#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(readlink -e $(dirname "$BASH_SOURCE[0]")/../)"

# REPLACES_VERSION is the old CSV_VERSION
#   if REPLACES_VERSION == CSV_VERSION it will be ignored
REPLACES_VERSION="${REPLACES_VERSION:-0.0.1}"
CSV_VERSION="${CSV_VERSION:-0.0.1}"

NAMESPACE="${NAMESPACE:-storageclusters}"
DEPLOY_DIR="${PROJECT_ROOT}/deploy1"
CSV_DIR="${DEPLOY_DIR}/olm-catalog/ocs-operator/${CSV_VERSION}"

IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-IfNotPresent}"

# OCS Tag hardcoded to latest
CONTAINER_TAG="${CONTAINER_TAG:-latest}"

(cd ${PROJECT_ROOT}/tools/manifest-templator/ && go build)

function buildFlags {

	BUILD_FLAGS="--ocs-tag=latest \
	--namespace=${NAMESPACE} \
	--csv-version=${CSV_VERSION} \
	--replaces-version=${REPLACES_VERSION} \
	--image-pull-policy=${IMAGE_PULL_POLICY} \
	--container-tag=${CONTAINER_TAG}"

}

buildFlags

templates=$(cd ${PROJECT_ROOT}/templates && find . -type f -name "*.yaml.in")
for template in $templates; do
	infile="${PROJECT_ROOT}/templates/${template}"

	out_dir="$(dirname ${DEPLOY_DIR}/${template})"
	out_dir=${out_dir/VERSION/$CSV_VERSION}
	mkdir -p ${out_dir}

	out_file="${out_dir}/$(basename -s .in $template)"
	out_file=${out_file/VERSION/v$CSV_VERSION}

	rendered=$( \
		 ${PROJECT_ROOT}/tools/manifest-templator/manifest-templator \
		 ${BUILD_FLAGS} \
		 --converged \
		 --input-file=${infile} \
	)
	if [[ ! -z "$rendered" ]]; then
		echo -e "$rendered" > $out_file
		if [[ "${infile}" =~ .*crd.yaml.in ]]; then
			csv_out_dir="${CSV_DIR}"
			mkdir -p ${csv_out_dir}
			csv_out_file="${csv_out_dir}/$(basename -s .in $template)"

			echo -e "$rendered" > $csv_out_file
		fi
	fi
done

(cd ${PROJECT_ROOT}/tools/manifest-templator/ && go clean)
