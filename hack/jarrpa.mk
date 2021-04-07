include hack/demo.mk

PROJECT_DIR := $(PWD)

OCP_DIR ?= /home/jrivera/ocp/jarrpa-dev
OCP_BINDIR ?= /home/jrivera/ocp/jarrpa-dev/bin
OCP_CLUSTER_CONFIG ?= $(OCP_DIR)/install-config-aws-ocs-osd.yaml
OCP_CLUSTER_CONFIG_DIR ?= $(OCP_DIR)/aws-dev
OCP_INSTALLER ?= $(OCP_DIR)/bin/openshift-install
OCP_OC ?= $(OCP_BINDIR)/oc
OCS_OC_PATH ?= $(OCP_OC)
KUBECTL ?= $(OCP_BINDIR)/kubectl
#KUBECONFIG ?= $(OCP_CLUSTER_CONFIG_DIR)/auth/kubeconfig
TEST_DEPLOY_DIR ?= upgrade-testing

RBAC_PROXY_IMG ?= gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0

IMAGE_REGISTRY ?= quay.io
IMAGE_TAG ?= latest
REGISTRY_NAMESPACE ?= jarrpa
OPERATOR_IMAGE_NAME ?= ocs-operator
OPERATOR_INDEX_NAME ?= odf-operator-catalog
SKIP_CSV_DUMP ?= true

IMG ?= $(IMAGE_REGISTRY)/$(REGISTRY_NAMESPACE)/$(OPERATOR_IMAGE_NAME):$(IMAGE_TAG)
OPERATOR_FULL_IMAGE_NAME ?= $(IMG)
LATEST_MUST_GATHER_IMAGE ?= $(IMAGE_REGISTRY)/$(REGISTRY_NAMESPACE)/ocs-must-gather:$(IMAGE_TAG)
OCS_MUST_GATHER_IMAGE ?= $(IMAGE_REGISTRY)/$(REGISTRY_NAMESPACE)/ocs-must-gather:$(IMAGE_TAG)

OCS_SUBSCRIPTION_CHANNEL = alpha
ODF_SUBSCRIPTION_CHANNEL ?= $(OCS_SUBSCRIPTION_CHANNEL)

NOOBAA_UPSTREAM_TAG ?= 5.10.10
NOOBAA_BUNDLE_IMG_TAG ?= v$(NOOBAA_UPSTREAM_TAG)
NOOBAA_BUNDLE_IMG_LOCATION ?= quay.io/jarrpa
NOOBAA_BUNDLE_IMAGE ?= $(NOOBAA_BUNDLE_IMG_LOCATION)/noobaa-operator-bundle:$(NOOBAA_BUNDLE_IMG_TAG)
NOOBAA_SUBSCRIPTION_STARTINGCSV ?= noobaa-operator.$(NOOBAA_BUNDLE_IMG_TAG)

GO_LINT_IMG_LOCATION ?= golangci/golangci-lint
GO_LINT_IMG_TAG ?= v1.54.2
GO_LINT_IMG ?= $(GO_LINT_IMG_LOCATION):$(GO_LINT_IMG_TAG)

NAMESPACE ?= ocs-operator-system
INSTALL_NAMESPACE ?= $(NAMESPACE)

csv: gen-latest-csv ##

ci: shellcheck-test lint unit-test verify-deps verify-generated verify-latest-deploy-yaml ##

watch: ##
	clear; watch -ptn3 "\
	${OCP_OC} get -n ${NAMESPACE} storagecluster,storageconsumer,storageclassrequest -o go-template-file=hack/watch.gotemplate --ignore-not-found; \
	${OCP_OC} get -n ${NAMESPACE} cephcluster,cephblockpool,cephfilesystem,cephfilesystemsubvolumegroup,cephclient -o go-template-file=hack/watch.gotemplate --ignore-not-found; \
	${OCP_OC} get -n ${NAMESPACE} po; echo ""; \
	echo "NAME"; ${OCP_OC} get sc -oname; ${OCP_OC} get pvc -l app=upgrade-testing -o name"

watch-pods: ##
	function showcursor() { tput cnorm; }; trap showcursor EXIT; tput civis; clear; \
	while true; do \
		tput cup 0 0; \
		output="$$(${OCP_OC} get -n ${NAMESPACE} po)"; \
		clear; echo "$$output"; sleep 1; \
	done

watch-resources: ##
	function showcursor() { tput cnorm; }; trap showcursor EXIT; tput civis; clear; \
	while true; do \
		tput cup 0 0; \
		output="$$(\
		${OCP_OC} get -n ${NAMESPACE} -o go-template-file=hack/watch.gotemplate --ignore-not-found storagecluster,storageconsumer,storageclassrequest; \
		${OCP_OC} get -n ${NAMESPACE} -o go-template-file=hack/watch.gotemplate --ignore-not-found cephcluster,cephblockpool,cephblockpoolradosnamespace,cephfilesystem,cephfilesystemsubvolumegroup,cephclient; \
		${OCP_OC} get -n ${NAMESPACE} -o go-template-file=hack/watch.gotemplate --ignore-not-found storageclient,storageclassclaim,storageclaim 2>/dev/null; \
		$(OCP_OC) get -n ${NAMESPACE} -o go-template-file=hack/watch.gotemplate --ignore-not-found -l app=upgrade-testing pvc; \
		$(OCP_OC) get -n ${NAMESPACE} sc -o custom-columns=STORAGECLASS:.metadata.name,PROVISIONER:.provisioner)"; \
		clear; echo "$$output"; sleep 1; \
	done

push-op: update-generated ocs-operator ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-operator:${IMAGE_TAG}"

push-bundle: csv gen-latest-deploy-yaml operator-bundle ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-operator-bundle:${IMAGE_TAG}"

push-catalog: operator-catalog ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-operator-catalog:${IMAGE_TAG}"

push-must-gather: ocs-must-gather ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-must-gather:${IMAGE_TAG}"

push-metrics-exporter: ocs-metrics-exporter ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-metrics-exporter:${IMAGE_TAG}"

push-vol-mv: volume-migration-tool ##
	docker push "${IMAGE_REGISTRY}/${REGISTRY_NAMESPACE}/ocs-volume-migration:${IMAGE_TAG}" quay.io/jarrpa/ocs-volume-migration:latest

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

push-all: registry-login push-op push-bundle push-catalog ##

##@ Deployment

install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -
	$(KUSTOMIZE) build config/rook-crd | $(KUBECTL) apply -f -

uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete -f -
	$(KUSTOMIZE) build config/rook-crd | $(KUBECTL) delete -f -

# manager env variables
OPERATOR_NAMEPREFIX ?= ocs-operator-
OPERATOR_NAMESPACE ?= $(OPERATOR_NAMEPREFIX)system

deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	cd config/ux-backend && $(KUSTOMIZE) edit set image controller=${IMG}
	cd config/default && \
		$(KUSTOMIZE) edit set image kube-rbac-proxy=$(RBAC_PROXY_IMG) && \
		$(KUSTOMIZE) edit set namespace $(OPERATOR_NAMESPACE) && \
		$(KUSTOMIZE) edit set nameprefix $(OPERATOR_NAMEPREFIX)
	$(KUSTOMIZE) build config/default | $(KUBECTL) apply -f -

delete-all: delete-testing-resources delete-storagecluster delete-storagecluster-provider ## Delete testing resources and StorageClusters

remove: kustomize ## Remove controller from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/default | $(KUBECTL) delete -f -

##@ Rook Deployment

deploy-rook: kustomize ## Deploy rook-ceph to the K8s cluster specified in ~/.kube/config.
	cd config/rook && \
		$(KUSTOMIZE) edit set namespace $(OPERATOR_NAMESPACE)
	$(KUSTOMIZE) build config/rook | $(KUBECTL) apply -f -

remove-rook: kustomize ## Remove rook-ceph from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/rook | $(KUBECTL) delete -f -

##@ Client Operator Deployment
OCS_CLIENT_DIR ?= ~/projects/github.com/red-hat-storage/ocs-client-operator

install-client: ##
	cd $(OCS_CLIENT_DIR); \
		make install

deploy-client: ##
	cd $(OCS_CLIENT_DIR); \
		make deploy

remove-client: ##
	cd $(OCS_CLIENT_DIR); \
		make remove

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

docker-rmi: ##
	docker rmi --force $$(docker images -a --filter=dangling=true -q)

AWS_DOMAIN ?= ocs-osd.syseng.devcluster.openshift.com
AWS_HOSTED_ZONE_ID ?= Z01835182X7TBTISQP81S
AWS_VPC_ID ?= vpc-04caaebfaab14e899

aws-clear-recordsets: ##
	aws route53 list-resource-record-sets --output json --hosted-zone-id $${AWS_HOSTED_ZONE_ID} | \
	  jq '[.ResourceRecordSets[] |select(.Name|test("jarrpa-dev.$${AWS_DOMAIN}."))]|map(.| { Action: "DELETE", ResourceRecordSet: .})|{Comment: "Delete jarrpa recordset",Changes: .}' | \
	  tee /tmp/recordsets.json
	aws route53 change-resource-record-sets --hosted-zone-id $${AWS_HOSTED_ZONE_ID} --change-batch file:///tmp/recordsets.json || :
	rm -f /tmp/recordsets.json

aws-ceph-ports: ##
	-export GROUP_ID="$$(aws ec2 describe-security-groups --output json --filters Name=vpc-id,Values=$(AWS_VPC_ID) --query 'SecurityGroups[*].{ID:GroupId,Tags:Tags[?Key==`Name`].Value}' | jq -r '.[] | .ID')"; \
	export GROUP_ID="sg-0f7c479ac988bfd13"; \
	echo "Group ID: $$GROUP_ID"; \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 31659 || true; \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 9283  || true; \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 6789 || true;  \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 3300 || true;  \
	aws ec2 authorize-security-group-ingress --group-id $${GROUP_ID} --protocol tcp --cidr 10.0.0.0/16 --port 6800-7300 || true;

#export GROUP_ID="$$(aws ec2 describe-security-groups --output json --filters Name=tag:Name,Values=*-worker-sg --query 'SecurityGroups[*].{ID:GroupId,Tags:Tags[?Key==`Name`].Value}' | jq -r '.[] | .ID')"; \
#export GROUP_ID="$$(aws ec2 describe-security-groups --filter Name=tag:Name,Values=*worker-sg* | grep SECURITYGROUPS | awk '{print $$6}')"; \

rosa-get-bin: ##
	curl --progress-bar -L https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar -xz -C $(OCP_BINDIR);

CLUSTER_NAME ?= jarrpa-dev
rosa-create-cluster: ##
	time bash -c "rosa create cluster --cluster-name $(CLUSTER_NAME) --sts --role-arn arn:aws:iam::495507785675:role/ManagedOpenShift-HCP-ROSA-Installer-Role --support-role-arn arn:aws:iam::495507785675:role/ManagedOpenShift-HCP-ROSA-Support-Role --worker-iam-role arn:aws:iam::495507785675:role/ManagedOpenShift-HCP-ROSA-Worker-Role --operator-roles-prefix jarrpa-dev-hcp --oidc-config-id 2636ge0jjotldd7jtk6h3loqu4fb87k8 --region us-east-2 --version 4.13.10 --replicas 3 --compute-machine-type m5.4xlarge --machine-cidr 10.0.0.0/16 --service-cidr 172.30.0.0/16 --pod-cidr 10.128.0.0/14 --host-prefix 23 --subnet-ids subnet-0f2dedaee9188451f,subnet-0c2556315c28b86d0,subnet-05ee9306ebafe4040,subnet-0284e507139b383bf,subnet-0d158a843904e7926,subnet-0e5db264c35513678 --hosted-cp; rosa logs install -c $(CLUSTER_NAME) --watch"

CLUSTER_ADDR ?= ""
CLUSTER_PASSWD ?= ""
rosa-login-cluster: ##
	while ! $(OCP_OC) login api.$(CLUSTER_NAME).$(CLUSTER_ADDR).openshiftapps.com:6443 --username cluster-admin --password "$(CLUSTER_PASSWD)"; do \
		  echo "Retrying in 2..."; \
		  sleep 2; \
		done;

rosa-delete-cluster: ##
	time bash -c "rosa delete cluster -y -c $(CLUSTER_NAME); rosa logs uninstall -c $(CLUSTER_NAME) --watch"

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

##@ Provider/Consumer Development

CONTEXT_PROVIDER ?= ${NAMESPACE}/api-dbindra-pro-ns1d-s1-devshift-org:6443/kube:admin
CONTEXT_CONSUMER ?= ${NAMESPACE}-consumer/api-dbindra-cons-a91y-s1-devshift-org:6443/kube:admin
#OC_CONSUMER=$(OCP_OC) --context=$(CONTEXT_CONSUMER)
#OC_PROVIDER=$(OCP_OC) --context=$(CONTEXT_PROVIDER)
OC_CONSUMER=$(OCP_OC) -n ${NAMESPACE}-consumer
#OC_PROVIDER=$(OCP_OC) -n ${NAMESPACE}
OC_PROVIDER=oc
NAMESPACE_PROVIDER ?= $(NAMESPACE)
NAMESPACE_CONSUMER ?= $(NAMESPACE)

hax-ms: ## Apply temporary workarounds
	${OC_PROVIDER} create -f deploy/csv-templates/crds/noobaa/noobaa-crd.yaml
	${OC_CONSUMER} create -f deploy/csv-templates/crds/noobaa/noobaa-crd.yaml

reset: ## Delete some pods
	$(OCP_OC) -n $(NAMESPACE) delete po -l=app.kubernetes.io/name=ocs
	$(OCP_OC) -n $(NAMESPACE) delete po -l=app=rook-ceph-operator

reset-ms: ## Delete some pods
	$(OC_CONSUMER) delete po -lname=ocs-operator
	$(OC_PROVIDER) delete po -lname=ocs-operator
	$(OC_PROVIDER) delete po -l=app=ocsProviderApiServer
	$(OC_PROVIDER) delete po -l=app=rook-ceph-operator

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
	${OC_CONSUMER} delete -f upgrade-testing/namespace-setup.yaml

uninstall-ms: uninstall-provider uninstall-consumer ## Destroy StorageClusters and uninstall OCS from provider and consumer

deploy-provider: ## Deploy StorageCluster on provider
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/storagecluster-provider.yaml | ${OC_PROVIDER} apply -f -

destroy-provider: ## Destroy StorageClusters on provider
	${OC_PROVIDER} delete storagecluster --all

destroy-consumer: ## Destroy StorageClusters on consumer
	${OC_CONSUMER} delete storagecluster --all

destroy-ms: destroy-consumer destroy-provider ## Destroy StorageClusters on provider and consumer
