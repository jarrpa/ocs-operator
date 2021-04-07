PROJECT_DIR := $(PWD)

OCP_DIR ?= /home/jrivera/ocp/jarrpa-dev
OCP_BINDIR ?= /home/jrivera/ocp/jarrpa-dev/bin
OCP_CLUSTER_CONFIG ?= $(OCP_DIR)/install-config-aws-ocs-osd.yaml.bak
OCP_CLUSTER_CONFIG_DIR ?= $(OCP_DIR)/aws-dev
OCP_INSTALLER ?= $(OCP_DIR)/bin/openshift-install
OCP_OC ?= $(OCP_BINDIR)/oc
OCS_OC_PATH ?= $(OCP_OC)
KUBECTL ?= $(OCP_BINDIR)/kubectl
#KUBECONFIG ?= $(OCP_CLUSTER_CONFIG_DIR)/auth/kubeconfig
TEST_DEPLOY_DIR ?= upgrade-testing

IMAGE_REGISTRY ?= quay.io
IMAGE_TAG ?= latest
REGISTRY_NAMESPACE ?= jarrpa
OPERATOR_INDEX_NAME ?= odf-operator-catalog
SKIP_CSV_DUMP ?= true

OCS_SUBSCRIPTION_CHANNEL = alpha
ODF_SUBSCRIPTION_CHANNEL ?= $(OCS_SUBSCRIPTION_CHANNEL)

NOOBAA_UPSTREAM_TAG ?= 5.10.10
NOOBAA_BUNDLE_IMG_TAG ?= v$(NOOBAA_UPSTREAM_TAG)
NOOBAA_BUNDLE_IMG_LOCATION ?= quay.io/jarrpa
NOOBAA_BUNDLE_IMAGE ?= $(NOOBAA_BUNDLE_IMG_LOCATION)/noobaa-operator-bundle:$(NOOBAA_BUNDLE_IMG_TAG)
NOOBAA_SUBSCRIPTION_STARTINGCSV ?= noobaa-operator.$(NOOBAA_BUNDLE_IMG_TAG)

GO_LINT_IMG_LOCATION ?= golangci/golangci-lint
GO_LINT_IMG_TAG ?= v1.47.3
GO_LINT_IMG ?= $(GO_LINT_IMG_LOCATION):$(GO_LINT_IMG_TAG)

NAMESPACE ?= ocs-osd
PROVIDER_NAMESPACE ?= ocs-osd-provider

csv: gen-latest-csv ##

ci: shellcheck-test lint unit-test verify-deps verify-generated verify-latest-deploy-yaml ##

watch: ##
	watch -n1 "${OCP_OC} get -n ${NAMESPACE} storagecluster,storageconsumer,cephcluster,cephblockpool,cephfilesystem; \
		${OCP_OC} get -n ${NAMESPACE} csv,subscription,po"

#watch -n1 "${OCP_OC} get -n ${NAMESPACE} storagecluster,storageconsumer,storageclassclaim,cephcluster,cephblockpool,cephfilesystem; \

push-op: update-generated ocs-operator ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-operator:${IMAGE_TAG}"

push-bundle: csv gen-latest-deploy-yaml operator-bundle ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-operator-bundle:${IMAGE_TAG}"

push-index: operator-index ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/odf-operator-catalog:${IMAGE_TAG}"

push-must-gather: ocs-must-gather ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-must-gather:${IMAGE_TAG}"

push-odf-bundle: #docker-rmi ##
	cd ~/projects/github.com/red-hat-storage/odf-operator; \
	make bundle-build; \
	make bundle-push

push-odf-catalog: #docker-rmi ##
	cd ~/projects/github.com/red-hat-storage/odf-operator; \
	make catalog-build; \
	make catalog-push

push-noobaa-bundle: ##
	cd ~/projects/github.com/noobaa/noobaa-operator; \
	make bundle-image \
	  csv-name="noobaa-operator.csv.yaml" \
	  core-image="noobaa/noobaa-core:${NOOBAA_UPSTREAM_TAG}" \
	  db-image="centos/postgresql:12" \
	  operator-image="noobaa/noobaa-operator:${NOOBAA_UPSTREAM_TAG}" \
	  BUNDLE_IMAGE="${NOOBAA_BUNDLE_IMAGE}"
	docker push "${NOOBAA_BUNDLE_IMAGE}"

registry-login: ## Check or prompt login to image registry
	docker login ${IMAGE_REGISTRY}

#push-all: registry-login push-op push-bundle push-noobaa-bundle push-odf-bundle push-index ##

push-all: registry-login push-op push-bundle push-index ##

##@ Hax

hax: ## Apply temporary workarounds
	${OCP_OC} create -f deploy/csv-templates/crds/noobaa/noobaa-crd.yaml

.PHONY: oc
oc: ## Run oc commands with ARGS
	${OCP_OC} ${ARGS}

oc-check: ##
	${OCP_OC} version
	${OCP_OC} whoami
	${OCP_OC} config current-context
	${OCP_OC} config view

deploy: ##
	${OCP_OC} apply -f upgrade-testing/storagecluster-provider.yaml

destroy: ##
	${OCP_OC} delete storagecluster --all

docker-rmi: ##
	docker rmi --force $$(docker images -a --filter=dangling=true -q)

AWS_DOMAIN ?= ocs-osd.syseng.devcluster.openshift.com
AWS_HOSTED_ZONE_ID ?= Z01835182X7TBTISQP81S

aws-clear-recordsets: ##
	aws route53 list-resource-record-sets --output json --hosted-zone-id $${AWS_HOSTED_ZONE_ID} | \
	  jq '[.ResourceRecordSets[] |select(.Name|test("jarrpa-dev.$${AWS_DOMAIN}."))]|map(.| { Action: "DELETE", ResourceRecordSet: .})|{Comment: "Delete jarrpa recordset",Changes: .}' | \
	  tee /tmp/recordsets.json
	aws route53 change-resource-record-sets --hosted-zone-id $${AWS_HOSTED_ZONE_ID} --change-batch file:///tmp/recordsets.json || :
	rm -f /tmp/recordsets.json

CLUSTER_TAG ?= r7kf5
aws-ceph-ports: ##
	-export GROUP_ID="$$(aws ec2 describe-security-groups --output json --filters Name=tag:Name,Values=*-$(CLUSTER_TAG)-worker-sg --query 'SecurityGroups[*].{ID:GroupId,Tags:Tags[?Key==`Name`].Value}' | jq -r '.[] | .ID')"; \
	echo "Group ID: $${GROUP_ID}"; \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 31659 || true; \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 9283  || true; \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 6789 || true;  \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 3300 || true;  \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 6800-7300 || true;

CEPH_PORTS_JSON ?= /home/jrivera/projects/github.com/red-hat-storage/ocs-operator/hack/ceph-ports.json
aws-ceph-ports-json: ##
	-export GROUP_ID="$$(aws ec2 describe-security-groups --output json --filters Name=tag:Name,Values=*-$(CLUSTER_TAG)-worker-sg --query 'SecurityGroups[*].{ID:GroupId,Tags:Tags[?Key==`Name`].Value}' | jq -r '.[] | .ID')"; \
	echo "Group ID: $${GROUP_ID}"; \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --cli-input-json '$(shell cat $(CEPH_PORTS_JSON))' || true;

rosa-get-bin: ##
	curl --progress-bar -L https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar -xz -C $(OCP_BINDIR);

#OCP_BIN_URL ?= https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest
OCP_BIN_VER ?= latest
OCP_BIN_URL ?= https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/$(OCP_BIN_VER)
OCP_BINS ?= openshift-client-linux.tar.gz openshift-install-linux.tar.gz opm-linux.tar.gz
ocp-get-bin: ## Download latest stable OCP binaries
	for bin in $(OCP_BINS); do \
	  echo "Downloading $$bin"; \
	  curl --progress-bar -L $(OCP_BIN_URL)/$$bin | tar -xzv -C $(OCP_BINDIR); \
	done

ocp-deploy: #aws-clear-recordsets ##
	rm -rf "${OCP_CLUSTER_CONFIG_DIR}"
	mkdir "${OCP_CLUSTER_CONFIG_DIR}"
	cp "${OCP_CLUSTER_CONFIG}" "${OCP_CLUSTER_CONFIG_DIR}/install-config.yaml"
	${OCP_INSTALLER} create cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" --log-level debug

ocp-destroy: ##
	${OCP_INSTALLER} destroy cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" || true
	make aws-clear-recordsets

namespace-setup: ##
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/namespace-setup.yaml | ${OCP_OC} apply -f
	${OCP_OC} project ${NAMESPACE}
	${OCP_OC} delete -n ${NAMESPACE} po -l olm.catalogSource=odf-catalogsource

install-ocs: namespace-setup ##
	${OCP_OC} apply -f upgrade-testing/subscribe-ocs-${OCS_SUBSCRIPTION_CHANNEL}.yaml

install-odf: namespace-setup ##
	${OCP_OC} apply -f upgrade-testing/subscribe-odf-${ODF_SUBSCRIPTION_CHANNEL}.yaml

install: hax install-ocs install-odf ##

uninstall: ##
	${OCP_OC} delete subscription,csv,cm,job --all --force=true
	${OCP_OC} delete crd -l operators.coreos.com/odf-operator.${NAMESPACE}=
	${OCP_OC} delete crd -l operators.coreos.com/ocs-operator.${NAMESPACE}=
	${OCP_OC} delete crd -l operators.coreos.com/noobaa-operator.${NAMESPACE}=
	${OCP_OC} delete po -l olm.catalogSource=odf-catalogsource

##@ Managed Service Development

CONTEXT_PROVIDER ?= jarrpa-dev-admin
CONTEXT_CONSUMER ?= jarrpa-dev-client-admin
OC_PROVIDER ?= oc --context $(CONTEXT_PROVIDER)
OC_CONSUMER ?= oc --context $(CONTEXT_CONSUMER)

hax-ms: ## Apply temporary workarounds
	${OC_PROVIDER} create -f deploy/csv-templates/crds/noobaa/noobaa-crd.yaml
	${OC_CONSUMER} create -f deploy/csv-templates/crds/noobaa/noobaa-crd.yaml

reset-ms: ## Delete some pods
	$(OC_CONSUMER) delete po -lname=ocs-operator
	$(OC_PROVIDER) delete po -lname=ocs-operator
	$(OC_PROVIDER) delete po -l=app=ocsProviderApiServer
	$(OC_PROVIDER) delete po -l=app=rook-ceph-operator

get-claim-secrets: ## Get secrets for StorageClassClaims on provider
	${OC_PROVIDER} get secret -l=ocs.openshift.io/storageclassclaim-name -oyaml | grep StorageClassClaim | awk '{print $$2}' | base64 -d | jq

watch-provider: ## Watch provider resources
	watch -n1 "${OC_PROVIDER} get -n ${NAMESPACE} storagecluster,storageconsumer,cephcluster,cephblockpool,cephfilesystem; echo ""; \
		${OC_PROVIDER} get -n ${NAMESPACE} csv,subscription,po"

watch-consumer: ## Watch consumer resources
	watch -n1 "${OC_CONSUMER} get -n ${NAMESPACE}-consumer ocsinitialization,storagecluster,storageconsumer,storageclassclaim,cephcluster,po"

namespace-setup-provider: ## Provider namespace setup
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/namespace-setup-provider.yaml | ${OC_PROVIDER} apply -f -
	${OC_PROVIDER} project ${NAMESPACE}
	${OC_PROVIDER} delete -n ${NAMESPACE} po -l olm.catalogSource=odf-catalogsource

namespace-setup-consumer: ## Consumer namespace setup
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/namespace-setup.yaml | ${OC_CONSUMER} apply -f -
	${OC_CONSUMER} project ${NAMESPACE}-consumer
	${OC_CONSUMER} delete -n ${NAMESPACE}-consumer po -l olm.catalogSource=odf-catalogsource

install-ocs-provider: namespace-setup-provider ## Install OCS on provider
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/subscribe-ocs-${OCS_SUBSCRIPTION_CHANNEL}.yaml | ${OC_PROVIDER} apply -f -

install-ocs-consumer: namespace-setup-consumer ## Install OCS on consumer
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/subscribe-ocs-consumer-${OCS_SUBSCRIPTION_CHANNEL}.yaml | ${OC_CONSUMER} apply -f -

install-ms: hax-ms install-ocs-provider install-ocs-consumer ## Install OCS on provider and consumer

uninstall-provider: destroy-provider ## Uninstall OCS from provider
	${OC_PROVIDER} delete subscription,csv,cm,job --all --force=true
	${OC_PROVIDER} delete crd -l operators.coreos.com/odf-operator.${NAMESPACE}=
	${OC_PROVIDER} delete crd -l operators.coreos.com/ocs-operator.${NAMESPACE}=
	${OC_PROVIDER} delete crd -l operators.coreos.com/noobaa-operator.${NAMESPACE}=
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/namespace-setup-provider.yaml | ${OC_PROVIDER} delete -f -

uninstall-consumer: destroy-consumer ## Uninstall OCS from consumer
	${OC_CONSUMER} delete subscription,csv,cm,job --all --force=true
	${OC_CONSUMER} delete crd -l operators.coreos.com/odf-operator.${NAMESPACE}=
	${OC_CONSUMER} delete crd -l operators.coreos.com/ocs-operator.${NAMESPACE}=
	${OC_CONSUMER} delete crd -l operators.coreos.com/noobaa-operator.${NAMESPACE}=
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/namespace-setup.yaml | ${OC_CONSUMER} delete -f -

uninstall-ms: uninstall-provider uninstall-consumer ## Destroy StorageClusters and uninstall OCS from provider and consumer

apply-%: ## Replace namespace in yaml files
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/$* | ${OC_PROVIDER} apply -f -

deploy-provider: ## Deploy StorageCluster on provider
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/storagecluster-provider.yaml | ${OC_PROVIDER} apply -f -

destroy-provider: ## Destroy StorageClusters on provider
	${OC_PROVIDER} delete storagecluster --all || true

destroy-consumer: ## Destroy StorageClusters on consumer
	${OC_CONSUMER} delete storagecluster --all || true

destroy-ms: destroy-consumer destroy-provider ## Destroy StorageClusters on provider and consumer

TICKETGEN_DIR ?= /home/jrivera/projects/github.com/red-hat-storage/ocs-operator/hack/ticketgen
onboard-consumer: ## Create and onboard Consumer StorageCluster
	cd $(TICKETGEN_DIR); ./ticketgen.sh key.pem > onboarding-ticket.txt
	$(OC_PROVIDER) delete secret -n ${NAMESPACE} --ignore-not-found onboarding-ticket-key
	$(OC_PROVIDER) create secret -n ${NAMESPACE} generic onboarding-ticket-key \
		--from-file=key=$(TICKETGEN_DIR)/pubkey.pem
	cat upgrade-testing/storagecluster-consumer.yaml | $(OC_CONSUMER) delete -n ${NAMESPACE}-consumer --ignore-not-found -f -
	export ONBOARDING_TICKET="$$(cat $(TICKETGEN_DIR)/onboarding-ticket.txt)"; echo "$${ONBOARDING_TICKET}"; \
		export PROVIDER_ENDPOINT="$$($(OC_PROVIDER) get -n ${NAMESPACE} storagecluster -oyaml | grep ProviderEndpoint | sed "s/^.*: //")"; echo "$${PROVIDER_ENDPOINT}"; \
		cat upgrade-testing/storagecluster-consumer.yaml | \
		sed "s#storageProviderEndpoint: .*#storageProviderEndpoint: \"$${PROVIDER_ENDPOINT}\"#g" | \
		sed "s#onboardingTicket: .*#onboardingTicket: \"$${ONBOARDING_TICKET}\"#g" | \
		$(OC_CONSUMER) apply -n ${NAMESPACE}-consumer -f -
