module github.com/red-hat-storage/ocs-operator/services/provider

go 1.17

replace (
	github.com/red-hat-storage/ocs-operator => github.com/jarrpa/ocs-operator v1.4.12-0.rc2
	github.com/red-hat-storage/ocs-operator/api => github.com/jarrpa/ocs-operator/api v1.4.12-0.rc1
	github.com/red-hat-storage/ocs-operator/services/provider => github.com/jarrpa/ocs-operator/services/provider v1.4.12-0.rc2
)

// === Rook hacks ===

// This tag doesn't exist, but is imported by github.com/portworx/sched-ops.
exclude github.com/kubernetes-incubator/external-storage v0.20.4-openstorage-rc2

replace (
	github.com/kubernetes-incubator/external-storage => github.com/libopenstorage/external-storage v0.20.4-openstorage-rc3 // required by rook v1.7
	github.com/portworx/sched-ops => github.com/portworx/sched-ops v0.20.4-openstorage-rc3 // required by rook v1.7
	k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.23.4
	k8s.io/client-go => k8s.io/client-go v0.23.4
)
