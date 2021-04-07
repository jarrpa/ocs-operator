watch-resources-old: ##
	function showcursor() { tput cnorm; }; trap showcursor EXIT; tput civis; clear; \
	while true; do \
		tput cup 0 0; \
		output="$$(${OCP_OC} get -n ${NAMESPACE} storagecluster,storageconsumer,storageclassrequest,cephcluster,cephblockpool,cephfilesystem,cephfilesystemsubvolumegroup,cephclient -o go-template-file=hack/watch.gotemplate --ignore-not-found; ${OCP_OC} get -n ${NAMESPACE} storageclient,storageclassclaim -o go-template-file=hack/watch.gotemplate --ignore-not-found; echo "KIND/NAME"; $(OCP_OC) get -n ${NAMESPACE} -oname sc,pvc,pv)"; \
		clear; echo "$$output"; sleep 1; \
	done

watch-old: ##
	watch -n1 "${OCP_OC} get -n ${NAMESPACE} storagecluster,storageconsumer,storageclassclaim,cephcluster,cephblockpool,cephfilesystem"
		${OCP_OC} get -n ${NAMESPACE} cephcluster,cephblockpool,cephfilesystem,cephfilesystemsubvolumegroup,cephclient -o go-template-file=hack/watch.gotemplate --ignore-not-found; \

watch-provider: ## Watch provider resources
	watch -n1 "${OC_PROVIDER} get -n ${NAMESPACE} storagecluster,storageconsumer,cephcluster,cephclient,cephblockpool,cephfilesystem,cephfilesystemsubvolumegroup,pvc,po"

watch-consumer: ## Watch consumer resources
	clear; watch -tn2 "\
		${OC_CONSUMER} get -n ${NAMESPACE_CONSUMER} storageclient,storageclassclaim -o go-template-file=hack/watch.gotemplate --ignore-not-found; \
		${OC_CONSUMER} get -n ${NAMESPACE_CONSUMER} cm,po,pvc"

watch-consumer-new: ##
	function showcursor() { tput cnorm; }; trap showcursor EXIT; tput civis; clear; \
	while true; do \
		tput cup 0 0; \
		output="$$(${OC_CONSUMER} get -n ${NAMESPACE_CONSUMER} storageclient,storageclassclaim -o go-template-file=hack/watch.gotemplate --ignore-not-found; ${OC_CONSUMER} get -n ${NAMESPACE_CONSUMER} cm,po,pvc)"; \
		clear; echo "$$output"; sleep 1; \
	done

watch-consumer-old: ##
	watch -n1 "${OC_CONSUMER} get -n ${NAMESPACE}-consumer ocsinitialization,storagecluster,storageconsumer,storageclassclaim,cephcluster,po"

old-deploy: ##
	${OCP_OC} apply -f upgrade-testing/storagecluster-provider.yaml

old-destroy: ##
	${OCP_OC} delete storagecluster --all

TICKETGEN_DIR ?= /home/jrivera/projects/github.com/red-hat-storage/ocs-operator/hack/ticketgen
onboard-consumer-old: ## Create and onboard Consumer StorageCluster
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

CONSUMER_ID ?= $(shell oc get storageconsumer -o go-template --template='{{range .items}}{{.metadata.uid}}{{end}}')
CLAIM_NAME ?= example-storagecluster-ceph-rbd
storageclassrequest: ## Create StorageClassRequest with generated name
	go run hack/provider-tools/gen-storageclassrequest-name.go --consumer-id=$(CONSUMER_ID) --claim-name=$(CLAIM_NAME)

get-claim-secrets: ## Get secrets for StorageClassClaims on provider
	${OC_PROVIDER} get secret -l=ocs.openshift.io/storageclassclaim-name -oyaml | grep StorageClassClaim | awk '{print $$2}' | base64 -d | jq

apply-%: ## Replace namespace in yaml files
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/$* | ${OC_PROVIDER} apply -f -

