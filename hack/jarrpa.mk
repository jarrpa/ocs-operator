PROJECT_DIR := $(PWD)

OCP_DIR ?= /home/jrivera/ocp/jarrpa-dev
OCP_CLUSTER_CONFIG ?= $(OCP_DIR)/install-config-aws.yaml.bak
OCP_CLUSTER_CONFIG_DIR ?= $(OCP_DIR)/aws-dev
OCP_INSTALLER ?= $(OCP_DIR)/bin/openshift-install
OCP_OC ?= $(OCP_DIR)/bin/oc
OCS_OC_PATH ?= $(OCP_OC)
KUBECTL ?= $(OCP_DIR)/bin/kubectl
#KUBECONFIG ?= $(OCP_CLUSTER_CONFIG_DIR)/auth/kubeconfig
TEST_DEPLOY_DIR ?= upgrade-testing/

IMAGE_TAG ?= latest
REGISTRY_NAMESPACE ?= jarrpa
OPERATOR_INDEX_NAME ?= ocs-registry
SKIP_CSV_DUMP ?= true

OCS_SUBSCRIPTION_CHANNEL = alpha
ODF_SUBSCRIPTION_CHANNEL ?= $(OCS_SUBSCRIPTION_CHANNEL)

NOOBAA_UPSTREAM_TAG ?= 5.10.1
NOOBAA_BUNDLE_IMG_TAG ?= v$(NOOBAA_UPSTREAM_TAG)
NOOBAA_BUNDLE_IMG_LOCATION ?= quay.io/jarrpa
NOOBAA_BUNDLE_IMAGE ?= $(NOOBAA_BUNDLE_IMG_LOCATION)/noobaa-operator-bundle:$(NOOBAA_BUNDLE_IMG_TAG)
NOOBAA_SUBSCRIPTION_STARTINGCSV ?= noobaa-operator.$(NOOBAA_BUNDLE_IMG_TAG)

GO_LINT_IMG_LOCATION ?= golangci/golangci-lint
GO_LINT_IMG_TAG ?= v1.47.3
GO_LINT_IMG ?= $(GO_LINT_IMG_LOCATION):$(GO_LINT_IMG_TAG)

csv: gen-latest-csv ##

ci: shellcheck-test lint unit-test verify-deps verify-generated verify-latest-deploy-yaml ##

watch: ##
	watch -n1 "${OCP_OC} get -n openshift-storage csv,subscription,storagecluster,storageconsumer,storageclassclaim,po"

push-op: update-generated ocs-operator ##
	docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-operator:${IMAGE_TAG}"

push-bundle: csv gen-latest-deploy-yaml operator-bundle ##
	docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-operator-bundle:${IMAGE_TAG}"

push-index: operator-index ##
	docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-registry:${IMAGE_TAG}"

push-must-gather: ocs-must-gather ##
	docker push "quay.io/${REGISTRY_NAMESPACE}/ocs-must-gather:${IMAGE_TAG}"

push-odf-bundle: docker-rmi ##
	cd ~/projects/github.com/red-hat-storage/odf-operator; \
	make bundle-build; \
	make bundle-push

push-noobaa-bundle: ##
	cd ~/projects/github.com/noobaa/noobaa-operator; \
	make bundle-image \
	  csv-name="noobaa-operator.csv.yaml" \
	  core-image="noobaa/noobaa-core:${NOOBAA_UPSTREAM_TAG}" \
	  db-image="centos/postgresql:12" \
	  operator-image="noobaa/noobaa-operator:${NOOBAA_UPSTREAM_TAG}" \
	  BUNDLE_IMAGE="${NOOBAA_BUNDLE_IMAGE}"
	docker push "${NOOBAA_BUNDLE_IMAGE}"

push-all: push-op push-bundle push-noobaa-bundle push-odf-bundle push-index ##

##@ Hax

hax: ## Apply temporary workarounds
	${OCP_OC} create -f deploy/csv-templates/crds/noobaa/noobaa-crd.yaml

.PHONY: oc
oc: ## Run oc commands with ARGS
	${OCP_OC} ${ARGS}

deploy: ##
	${OCP_OC} apply -f upgrade-testing/storagecluster-provider.yaml

destroy: ##
	${OCP_OC} delete storagecluster --all

docker-rmi: ##
	docker rmi --force $$(docker images -a --filter=dangling=true -q)

clear-aws-recordsets: ##
	aws route53 list-resource-record-sets --output json --hosted-zone-id Z087500514U36JHEM14R5 | \
	  jq '[.ResourceRecordSets[] |select(.Name|test("jarrpa-dev.ocs.syseng.devcluster.openshift.com."))]|map(.| { Action: "DELETE", ResourceRecordSet: .})|{Comment: "Delete jarrpa recordset",Changes: .}' | \
	  tee /tmp/recordsets.json
	aws route53 change-resource-record-sets --hosted-zone-id Z087500514U36JHEM14R5 --change-batch file:///tmp/recordsets.json || :
	rm -f /tmp/recordsets.json

ocp-deploy: clear-aws-recordsets ##
	rm -rf "${OCP_CLUSTER_CONFIG_DIR}"
	mkdir "${OCP_CLUSTER_CONFIG_DIR}"
	cp "${OCP_CLUSTER_CONFIG}" "${OCP_CLUSTER_CONFIG_DIR}/install-config.yaml"
	${OCP_INSTALLER} create cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" --log-level debug

ocp-destroy: ##
	${OCP_INSTALLER} destroy cluster --dir "${OCP_CLUSTER_CONFIG_DIR}" || true
	make clear-aws-recordsets

namespace-setup: ##
	${OCP_OC} apply -f ${TEST_DEPLOY_DIR}/namespace-setup.yaml
	${OCP_OC} project openshift-storage
	${OCP_OC} delete -n openshift-storage po -l olm.catalogSource=odf-catalogsource

install-ocs: namespace-setup ##
	${OCP_OC} apply -f upgrade-testing/subscribe-ocs-${OCS_SUBSCRIPTION_CHANNEL}.yaml

install-odf: namespace-setup ##
	${OCP_OC} apply -f upgrade-testing/subscribe-odf-${ODF_SUBSCRIPTION_CHANNEL}.yaml

install: hax install-ocs install-odf ##

uninstall: ##
	${OCP_OC} delete subscription,csv,cm,job --all --force=true
	${OCP_OC} delete crd -l operators.coreos.com/odf-operator.openshift-storage=
	${OCP_OC} delete crd -l operators.coreos.com/ocs-operator.openshift-storage=
	${OCP_OC} delete crd -l operators.coreos.com/noobaa-operator.openshift-storage=
	${OCP_OC} delete po -l olm.catalogSource=odf-catalogsource

##@ Managed Service Development

CONTEXT_PROVIDER ?= openshift-storage/api-dbindra-pro-ns1d-s1-devshift-org:6443/kube:admin
CONTEXT_CONSUMER ?= openshift-storage-consumer/api-dbindra-cons-a91y-s1-devshift-org:6443/kube:admin
OC_CONSUMER=$(OCP_OC) --context=$(CONTEXT_CONSUMER)
OC_PROVIDER=$(OCP_OC) --context=$(CONTEXT_PROVIDER)

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
	watch -n1 "${OC_PROVIDER} get -n openshift-storage storagecluster,storageconsumer,cephcluster,cephclient,cephblockpool,cephfilesystem,cephfilesystemsubvolumegroup,pvc,po"

watch-consumer: ## Watch consumer resources
	watch -n1 "${OC_CONSUMER} get -n openshift-storage-consumer ocsinitialization,storagecluster,storageconsumer,storageclassclaim,cephcluster,po"

namespace-setup-provider: ## Provider namespace setup
	${OC_PROVIDER} apply -f ${TEST_DEPLOY_DIR}/namespace-setup.yaml
	${OC_PROVIDER} project openshift-storage
	${OC_PROVIDER} delete -n openshift-storage po -l olm.catalogSource=odf-catalogsource

namespace-setup-consumer: ## Consumer namespace setup
	${OC_CONSUMER} apply -f ${TEST_DEPLOY_DIR}/namespace-setup.yaml
	${OC_CONSUMER} project openshift-storage-consumer
	${OC_CONSUMER} delete -n openshift-storage-consumer po -l olm.catalogSource=odf-catalogsource

install-ocs-provider: namespace-setup-provider ## Install OCS on provider
	${OC_PROVIDER} apply -f upgrade-testing/subscribe-ocs-${OCS_SUBSCRIPTION_CHANNEL}.yaml

install-ocs-consumer: namespace-setup-consumer ## Install OCS on consumer
	${OC_CONSUMER} apply -f upgrade-testing/subscribe-ocs-consumer-${OCS_SUBSCRIPTION_CHANNEL}.yaml

install-ms: hax-ms install-ocs-provider install-ocs-consumer ## Install OCS on provider and consumer

uninstall-provider: destroy-provider ## Uninstall OCS from provider
	${OC_PROVIDER} delete subscription,csv,cm,job --all --force=true
	${OC_PROVIDER} delete crd -l operators.coreos.com/odf-operator.openshift-storage=
	${OC_PROVIDER} delete crd -l operators.coreos.com/ocs-operator.openshift-storage=
	${OC_PROVIDER} delete crd -l operators.coreos.com/noobaa-operator.openshift-storage=
	${OC_PROVIDER} delete -f upgrade-testing/namespace-setup.yaml

uninstall-consumer: destroy-consumer ## Uninstall OCS from consumer
	${OC_CONSUMER} delete subscription,csv,cm,job --all --force=true
	${OC_CONSUMER} delete crd -l operators.coreos.com/odf-operator.openshift-storage=
	${OC_CONSUMER} delete crd -l operators.coreos.com/ocs-operator.openshift-storage=
	${OC_CONSUMER} delete crd -l operators.coreos.com/noobaa-operator.openshift-storage=
	${OC_CONSUMER} delete -f upgrade-testing/namespace-setup.yaml

uninstall-ms: uninstall-provider uninstall-consumer ## Destroy StorageClusters and uninstall OCS from provider and consumer

deploy-provider: ## Deploy StorageCluster on provider
	${OC_PROVIDER} apply -f "upgrade-testing/storagecluster-provider.yaml"

destroy-provider: ## Destroy StorageClusters on provider
	${OC_PROVIDER} delete storagecluster --all

destroy-consumer: ## Destroy StorageClusters on consumer
	${OC_CONSUMER} delete storagecluster --all

destroy-ms: destroy-consumer destroy-provider ## Destroy StorageClusters on provider and consumer

TICKETGEN_DIR ?= /home/jrivera/projects/github.com/red-hat-storage/ocs-operator/hack/ticketgen
onboard-consumer: ## Create and onboard Consumer StorageCluster
	cd $(TICKETGEN_DIR); ./ticketgen.sh key.pem > onboarding-ticket.txt
	$(OC_PROVIDER) delete secret -n openshift-storage --ignore-not-found onboarding-ticket-key
	$(OC_PROVIDER) create secret -n openshift-storage generic onboarding-ticket-key \
		--from-file=key=$(TICKETGEN_DIR)/pubkey.pem
	cat upgrade-testing/storagecluster-consumer.yaml | $(OC_CONSUMER) delete -n openshift-storage-consumer --ignore-not-found -f -
	export ONBOARDING_TICKET="$$(cat $(TICKETGEN_DIR)/onboarding-ticket.txt)"; echo "$${ONBOARDING_TICKET}"; \
		export PROVIDER_ENDPOINT="$$($(OC_PROVIDER) get -n openshift-storage storagecluster -oyaml | grep ProviderEndpoint | sed "s/^.*: //")"; echo "$${PROVIDER_ENDPOINT}"; \
		cat upgrade-testing/storagecluster-consumer.yaml | \
		sed "s#storageProviderEndpoint: .*#storageProviderEndpoint: \"$${PROVIDER_ENDPOINT}\"#g" | \
		sed "s#onboardingTicket: .*#onboardingTicket: \"$${ONBOARDING_TICKET}\"#g" | \
		$(OC_CONSUMER) apply -n openshift-storage-consumer -f -
