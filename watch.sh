#!/bin/bash

watch -n1 "./oc get --ignore-not-found=true storagesystems; echo;
  ./oc get --ignore-not-found=true storageclusters,cephclusters,noobaa; echo;
  ./oc get po,deployments,statefulsets,daemonsets; echo;
  ./oc get --all-namespaces operatorconditions,csv,installplans,subscription,operatorgroup,catalogsource"
#watch -n1 "./oc get po,deployments,statefulsets && echo &&
#  ./oc get --all-namespaces operatorconditions,csv,installplans,subscription,operatorgroup,catalogsource"
