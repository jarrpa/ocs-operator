#!/bin/bash

set -x

# Create the namespaces for the OCS
kubectl create ns openshift-storage

# Switch to the OCS namespace.
kubectl config set-context $(kubectl config current-context) --namespace=openshift-storage

# Launch all of the CRDs.
kubectl create -f crds/ceph.crd.yaml
kubectl create -f crds/ocs_v1alpha1_storagecluster.crd.yaml
kubectl create -f crds/rookcephblockpools.crd.yaml
kubectl create -f crds/rookcephobjectstores.crd.yaml
kubectl create -f crds/rookcephobjectstoreusers.crd.yaml

# Launch all of the Service Accounts, Cluster Role(Binding)s, and Operators.
kubectl create -f role.yaml
kubectl create -f service_account.yaml
kubectl create -f role_binding.yaml
kubectl create -f operator.yaml

# Create an OCS CustomResource, which creates the RCO CR, launching Rook-ceph cluster.
kubectl create -f crds/ocs_v1alpha1_storagecluster.cr.yaml
