##@ Testing

namespace-setup: ##
	sed 's/{{NAMESPACE}}/${NAMESPACE}/g' ${TEST_DEPLOY_DIR}/namespace-setup.yaml | ${OCP_OC} apply -f
	${OCP_OC} project ${NAMESPACE}
	${OCP_OC} delete -n ${NAMESPACE} po -l olm.catalogSource=odf-catalogsource --ignore-not-found

install-ocs-hax: namespace-setup ##
	${OCP_OC} apply -f upgrade-testing/subscribe-ocs-${OCS_SUBSCRIPTION_CHANNEL}.yaml

install-odf-hax: namespace-setup ##
	${OCP_OC} apply -f upgrade-testing/subscribe-odf-${ODF_SUBSCRIPTION_CHANNEL}.yaml

install-olm: hax install-ocs-hax install-odf-hax ##

uninstall-olm: ##
	${OCP_OC} delete subscription,csv,cm,job --all --force=true
	${OCP_OC} delete crd -l operators.coreos.com/odf-operator.${NAMESPACE}=
	${OCP_OC} delete crd -l operators.coreos.com/ocs-operator.${NAMESPACE}=
	${OCP_OC} delete crd -l operators.coreos.com/noobaa-operator.${NAMESPACE}=
	${OCP_OC} delete po -l olm.catalogSource=odf-catalogsource

create-storagecluster: ## Create StorageCluster CR
	$(KUSTOMIZE) build config/rook-configs/default/ | $(KUBECTL) apply -n ${NAMESPACE} -f -
	cat config/samples/ocs_v1_storagecluster.yaml | $(KUBECTL) apply -n ${NAMESPACE} -f -

create-storagecluster-provider: ## Create StorageCluster Provider CR
	cd config/provider && \
		$(KUSTOMIZE) edit set namespace $(OPERATOR_NAMESPACE)
	$(KUSTOMIZE) build config/provider | $(KUBECTL) apply -f -
	$(KUSTOMIZE) build config/rook-configs/remove-csi/ | $(KUBECTL) apply -n ${NAMESPACE} -f -
	cat config/samples/ocs_v1_storagecluster_provider.yaml | $(KUBECTL) apply -n ${NAMESPACE} -f -
	cat config/samples/ocs_v1_storageprofile.yaml | $(KUBECTL) apply -n ${NAMESPACE} -f -

delete-storagecluster: ## Delete StorageCluster CR
	cat config/samples/ocs_v1_storagecluster.yaml | $(KUBECTL) delete --ignore-not-found -n ${NAMESPACE} -f -
	cd config/provider && \
		$(KUSTOMIZE) edit set namespace $(OPERATOR_NAMESPACE)
	$(KUSTOMIZE) build config/provider | $(KUBECTL) delete -f -

delete-storagecluster-provider: ## Delete StorageCluster Provider CR
	cat config/samples/ocs_v1_storagecluster_provider.yaml | $(KUBECTL) delete --ignore-not-found -n ${NAMESPACE} -f -

delete-testing-resources: ## Delete all testing Pods and PVCs
	cat upgrade-testing/pod-* |  $(KUBECTL) delete --ignore-not-found -f -
	cat upgrade-testing/pvc-* |  $(KUBECTL) delete --ignore-not-found -f -

##@ Tech Demonstration

onboard-consumer: ##
	cd $(OCS_CLIENT_DIR); \
		make onboard-consumer

offboard-consumer: ##
	cat upgrade-testing/pod-nginx-consumer-rbd.yaml | $(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -
	cat upgrade-testing/pod-nginx-consumer-cephfs.yaml | $(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -
	$(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found route nginx-consumer-pvc-rbd
	$(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found service nginx-consumer-pvc-rbd
	cat upgrade-testing/pvc-consumer-rbd.yaml | $(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -
	cat upgrade-testing/pvc-consumer-cephfs.yaml | $(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -
	$(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found route nginx-example-pvc-rbd
	$(OC_CONSUMER) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found service nginx-example-pvc-rbd
	cd $(OCS_CLIENT_DIR); \
		make offboard-consumer

create-storageclassclaim-rbd: ## Create StorageClassClaim RBD CR
	cd $(OCS_CLIENT_DIR); \
		make storageclassclaim-rbd

create-storageclassclaim-cephfs: ## Create StorageClassClaim CephFS CR
	cd $(OCS_CLIENT_DIR); \
		make storageclassclaim-cephfs

deploy-pod-nginx-example-rbd: ##
	cat upgrade-testing/pvc-example-rbd.yaml | $(OCP_OC) apply -n ${NAMESPACE} -f -
	cat upgrade-testing/pod-nginx-example-rbd.yaml | $(OCP_OC) apply -n ${NAMESPACE} -f -

remove-pod-nginx-example-rbd: ##
	cat upgrade-testing/pod-nginx-example-rbd.yaml | $(OCP_OC) delete -n ${NAMESPACE} --ignore-not-found -f -
	cat upgrade-testing/pvc-example-rbd.yaml | $(OCP_OC) delete -n ${NAMESPACE} --ignore-not-found -f -

deploy-pod-nginx-example-cephfs: ##
	cat upgrade-testing/pvc-example-cephfs.yaml | $(OCP_OC) apply -n ${NAMESPACE} -f -
	cat upgrade-testing/pod-nginx-example-cephfs.yaml | $(OCP_OC) apply -n ${NAMESPACE} -f -

remove-pod-nginx-example-cephfs: ##
	cat upgrade-testing/pod-nginx-example-cephfs.yaml | $(OCP_OC) delete -n ${NAMESPACE} --ignore-not-found -f -
	cat upgrade-testing/pvc-example-cephfs.yaml | $(OCP_OC) delete -n ${NAMESPACE} --ignore-not-found -f -

deploy-pod-nginx-consumer-rbd: ##
	cat upgrade-testing/pvc-consumer-rbd.yaml | $(OCP_OC) apply -n ${NAMESPACE_CONSUMER} -f -
	cat upgrade-testing/pod-nginx-consumer-rbd.yaml | $(OCP_OC) apply -n ${NAMESPACE_CONSUMER} -f -

remove-pod-nginx-consumer-rbd: ##
	cat upgrade-testing/pod-nginx-consumer-rbd.yaml | $(OCP_OC) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -
	cat upgrade-testing/pvc-consumer-rbd.yaml | $(OCP_OC) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -

deploy-pod-nginx-consumer-cephfs: ##
	cat upgrade-testing/pvc-consumer-cephfs.yaml | $(OCP_OC) apply -n ${NAMESPACE_CONSUMER} -f -
	cat upgrade-testing/pod-nginx-consumer-cephfs.yaml | $(OCP_OC) apply -n ${NAMESPACE_CONSUMER} -f -

remove-pod-nginx-consumer-cephfs: ##
	cat upgrade-testing/pod-nginx-consumer-cephfs.yaml | $(OCP_OC) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -
	cat upgrade-testing/pvc-consumer-cephfs.yaml | $(OCP_OC) delete -n ${NAMESPACE_CONSUMER} --ignore-not-found -f -

remove-demo-pods: remove-pod-nginx-consumer-cephfs remove-pod-nginx-consumer-rbd remove-pod-nginx-example-cephfs remove-pod-nginx-example-rbd ##

provider-enablement: ##
	go run ./tools/provider-enablement

demo-setup: install install-client deploy deploy-rook create-storagecluster ##

demo-reset: ##
	make offboard-consumer
	make delete-storagecluster-provider
	make remove-client

