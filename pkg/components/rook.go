package components

import (
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	extv1beta1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	rookCephOperator = "rook-ceph-operator"
)

// GetRookCephDeployment returns a Deployment that deploys the rook-ceph
// operator
func GetRookCephDeployment(repository string, tag string, imagePullPolicy string) *appsv1.Deployment {
	registry_name := repository + "/rook/" + rookCephOperator
	rookCephImage := fmt.Sprintf("%s:%s", registry_name, tag)
	deployment := &appsv1.Deployment{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "apps/v1",
			Kind:       "Deployment",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: rookCephOperator,
			Labels: map[string]string{
				"operator":        "rook",
				"storage-backend": "ceph",
			},
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: int32Ptr(1),
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{
					"app": rookCephOperator,
				},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{
						"app": rookCephOperator,
					},
				},
				Spec: corev1.PodSpec{
					ServiceAccountName: "rook-ceph-system",
					Containers: []corev1.Container{
						{
							Name:            rookCephOperator,
							Image:           rookCephImage,
							ImagePullPolicy: corev1.PullPolicy(corev1.PullAlways),
							Args: []string{
								"ceph",
								"operator",
							},
							Env: []corev1.EnvVar{
								{
									Name:  "ROOK_CURRENT_NAMESPACE_ONLY",
									Value: "true",
								},
								{
									Name:  "FLEXVOLUME_DIR_PATH",
									Value: "/etc/kubernetes/kublet-plugins/volume/exec",
								},
								{
									Name:  "ROOK_ALLOW_MULTIPLE_FILESYSTEMS",
									Value: "false",
								},
								{
									Name:  "ROOK_LOG_LEVEL",
									Value: "INFO",
								},
								{
									Name:  "ROOK_MON_HEALTHCHECK_INTERVAL",
									Value: "45s",
								},
								{
									Name:  "ROOK_MON_OUT_TIMEOUT",
									Value: "600s",
								},
								{
									Name:  "ROOK_DISCOVER_DEVICES_INTERVAL",
									Value: "60m",
								},
								{
									Name:  "ROOK_HOSTPATH_REQUIRES_PRIVILEGED",
									Value: "true",
								},
								{
									Name:  "ROOK_ENABLE_SELINUX_RELABELING",
									Value: "true",
								},
								{
									Name:  "ROOK_ENABLE_FSGROUP",
									Value: "true",
								},
								{
									Name:  "ROOK_DISABLE_DEVICE_HOTPLUG",
									Value: "false",
								},
								{
									Name: "NODE_NAME",
									ValueFrom: &corev1.EnvVarSource{
										FieldRef: &corev1.ObjectFieldSelector{
											FieldPath: "spec.nodeName",
										},
									},
								},
								{
									Name: "POD_NAME",
									ValueFrom: &corev1.EnvVarSource{
										FieldRef: &corev1.ObjectFieldSelector{
											FieldPath: "metadata.name",
										},
									},
								},
								{
									Name: "POD_NAMESPACE",
									ValueFrom: &corev1.EnvVarSource{
										FieldRef: &corev1.ObjectFieldSelector{
											FieldPath: "metadata.namespace",
										},
									},
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								corev1.VolumeMount{
									Name:      "rook-config",
									MountPath: "/var/lib/rook",
								},
								corev1.VolumeMount{
									Name:      "default-config-dir",
									MountPath: "/etc/ceph",
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						corev1.Volume{
							Name: "rook-config",
							VolumeSource: corev1.VolumeSource{
								EmptyDir: &corev1.EmptyDirVolumeSource{},
							},
						},
						corev1.Volume{
							Name: "default-config-dir",
							VolumeSource: corev1.VolumeSource{
								EmptyDir: &corev1.EmptyDirVolumeSource{},
							},
						},
					},
				},
			},
		},
	}
	return deployment
}

// GetRookCephRoles returns a list of Roles needed by the rook-ceph operator
func GetRookCephRoles() []rbacv1.Role {
	return []rbacv1.Role{
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "Role",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-system",
				Labels: map[string]string{
					"operator":        "rook",
					"storage-backend": "ceph",
				},
			},
			Rules: []rbacv1.PolicyRule{
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"pods",
						"configmaps",
						"services",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"patch",
						"create",
						"update",
						"delete",
					},
				},
				{
					APIGroups: []string{
						"apps",
					},
					Resources: []string{
						"daemonsets",
						"statefulsets",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"create",
						"update",
						"delete",
					},
				},
			},
		},
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "Role",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-osd",
			},
			Rules: []rbacv1.PolicyRule{
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"configmaps",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"create",
						"update",
						"delete",
					},
				},
			},
		},
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "Role",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-mgr",
			},
			Rules: []rbacv1.PolicyRule{
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"pods",
						"services",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
					},
				},
				{
					APIGroups: []string{
						"batch",
					},
					Resources: []string{
						"jobs",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"create",
						"update",
						"delete",
					},
				},
				{
					APIGroups: []string{
						"ceph.rook.io",
					},
					Resources: []string{
						"*",
					},
					Verbs: []string{
						"*",
					},
				},
			},
		},
	}
}

// GetRookCephClusterRoles returns a list of ClusterRoles required by the rook-ceph operator
func GetRookCephClusterRoles() []rbacv1.ClusterRole {
	return []rbacv1.ClusterRole{
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-cluster-mgmt",
				Labels: map[string]string{
					"operator":        "rook",
					"storage-backend": "ceph",
				},
			},
			AggregationRule: &rbacv1.AggregationRule{
				ClusterRoleSelectors: []metav1.LabelSelector{
					{
						MatchLabels: map[string]string{
							"rbac.ceph.rook.io/aggregate-to-rook-ceph-cluster-mgmt": "true",
						},
					},
				},
			},
			Rules: []rbacv1.PolicyRule{},
		},
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-cluster-mgmt-rules",
				Labels: map[string]string{
					"operator":        "rook",
					"storage-backend": "ceph",
					"rbac.ceph.rook.io/aggregate-to-rook-ceph-cluster-mgmt": "true",
				},
			},
			Rules: []rbacv1.PolicyRule{
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"secrets",
						"pods",
						"pods/log",
						"services",
						"configmaps",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"patch",
						"create",
						"update",
						"delete",
					},
				},
				{
					APIGroups: []string{
						"apps",
					},
					Resources: []string{
						"deployments",
						"daemonsets",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"create",
						"update",
						"delete",
					},
				},
			},
		},

		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-global",
				Labels: map[string]string{
					"operator":        "rook",
					"storage-backend": "ceph",
				},
			},
			AggregationRule: &rbacv1.AggregationRule{
				ClusterRoleSelectors: []metav1.LabelSelector{
					{
						MatchLabels: map[string]string{
							"rbac.ceph.rook.io/aggregate-to-rook-ceph-global": "true",
						},
					},
				},
			},
			Rules: []rbacv1.PolicyRule{},
		},
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-global-rules",
				Labels: map[string]string{
					"operator":        "rook",
					"storage-backend": "ceph",
					"rbac.ceph.rook.io/aggregate-to-rook-ceph-global": "true",
				},
			},
			Rules: []rbacv1.PolicyRule{
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"pods",
						"nodes",
						"nodes/proxy",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
					},
				},
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"events",
						"persistentvolumes",
						"persistentvolumeclaims",
						"endpoints",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"patch",
						"create",
						"update",
						"delete",
					},
				},
				{
					APIGroups: []string{
						"storage.k8s.io",
					},
					Resources: []string{
						"storageclasses",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
					},
				},
				{
					APIGroups: []string{
						"batch",
					},
					Resources: []string{
						"jobs",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
						"create",
						"update",
						"delete",
					},
				},
				{
					APIGroups: []string{
						"ceph.rook.io",
					},
					Resources: []string{
						"*",
					},
					Verbs: []string{
						"*",
					},
				},
				{
					APIGroups: []string{
						"rook.io",
					},
					Resources: []string{
						"*",
					},
					Verbs: []string{
						"*",
					},
				},
			},
		},

		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-mgr-cluster",
				Labels: map[string]string{
					"operator":        "rook",
					"storage-backend": "ceph",
				},
			},
			AggregationRule: &rbacv1.AggregationRule{
				ClusterRoleSelectors: []metav1.LabelSelector{
					{
						MatchLabels: map[string]string{
							"rbac.ceph.rook.io/aggregate-to-rook-ceph-mgr-cluster": "true",
						},
					},
				},
			},
			Rules: []rbacv1.PolicyRule{},
		},
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-mgr-cluster-rules",
				Labels: map[string]string{
					"operator":        "rook",
					"storage-backend": "ceph",
					"rbac.ceph.rook.io/aggregate-to-rook-ceph-mgr-cluster": "true",
				},
			},
			Rules: []rbacv1.PolicyRule{
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"configmaps",
						"nodes",
						"nodes/proxy",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
					},
				},
			},
		},

		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-mgr-system",
			},
			AggregationRule: &rbacv1.AggregationRule{
				ClusterRoleSelectors: []metav1.LabelSelector{
					{
						MatchLabels: map[string]string{
							"rbac.ceph.rook.io/aggregate-to-rook-ceph-mgr-system": "true",
						},
					},
				},
			},
			Rules: []rbacv1.PolicyRule{},
		},
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "rbac.authorization.k8s.io/v1",
				Kind:       "ClusterRole",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "rook-ceph-mgr-system-rules",
				Labels: map[string]string{
					"rbac.ceph.rook.io/aggregate-to-rook-ceph-mgr-system": "true",
				},
			},
			Rules: []rbacv1.PolicyRule{
				{
					APIGroups: []string{
						"",
					},
					Resources: []string{
						"configmaps",
					},
					Verbs: []string{
						"get",
						"list",
						"watch",
					},
				},
			},
		},
	}
}

// GetRookCephCRDs returns a list of CustomResourceDefinitions for the Rook
// Ceph custom resources.
func GetRookCephCRDs() []*extv1beta1.CustomResourceDefinition {
	return []*extv1beta1.CustomResourceDefinition{
		// CephCluster CRD
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "apiextensions.k8s.io/v1beta1",
				Kind:       "CustomResourceDefinition",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "cephclusters.ceph.rook.io",
			},
			Spec: extv1beta1.CustomResourceDefinitionSpec{
				Group:   "ceph.rook.io",
				Version: "v1",
				Scope:   "Namespaced",
				Names: extv1beta1.CustomResourceDefinitionNames{
					Kind:     "CephCluster",
					ListKind: "CephClusterList",
					Plural:   "cephclusters",
					Singular: "cephcluster",
				},

				Validation: &extv1beta1.CustomResourceValidation{
					OpenAPIV3Schema: &extv1beta1.JSONSchemaProps{
						Properties: map[string]extv1beta1.JSONSchemaProps{
							"spec": extv1beta1.JSONSchemaProps{
								Type: "object",
								Properties: map[string]extv1beta1.JSONSchemaProps{
									"cephVersion": extv1beta1.JSONSchemaProps{
										Properties: map[string]extv1beta1.JSONSchemaProps{
											"allowUnsupported": extv1beta1.JSONSchemaProps{
												Type: "boolean",
											},
											"image": extv1beta1.JSONSchemaProps{
												Type: "string",
											},
											"name": extv1beta1.JSONSchemaProps{
												Type:    "string",
												Pattern: "^(luminous|mimic|nautilus)$",
											},
										},
									},
									"dashboard": extv1beta1.JSONSchemaProps{
										Properties: map[string]extv1beta1.JSONSchemaProps{
											"enabled": extv1beta1.JSONSchemaProps{
												Type: "boolean",
											},
											"urlPrefix": extv1beta1.JSONSchemaProps{
												Type: "string",
											},
											"port": extv1beta1.JSONSchemaProps{
												Type: "integer",
											},
										},
									},
									"dataDirHostPath": extv1beta1.JSONSchemaProps{
										Type:    "string",
										Pattern: "^/(\\S+)",
									},
									"mon": extv1beta1.JSONSchemaProps{
										Properties: map[string]extv1beta1.JSONSchemaProps{
											"allowMultiplePerNode": extv1beta1.JSONSchemaProps{
												Type: "boolean",
											},
											"count": extv1beta1.JSONSchemaProps{
												Type:    "integer",
												Maximum: float64ptr(9),
												Minimum: float64ptr(1),
											},
											"preferredCount": extv1beta1.JSONSchemaProps{
												Type:    "integer",
												Maximum: float64ptr(9),
												Minimum: float64ptr(0),
											},
										},
									},
									"network": extv1beta1.JSONSchemaProps{
										Properties: map[string]extv1beta1.JSONSchemaProps{
											"hostNetwork": extv1beta1.JSONSchemaProps{
												Type: "boolean",
											},
										},
									},
									"storage": extv1beta1.JSONSchemaProps{
										Properties: map[string]extv1beta1.JSONSchemaProps{
											"nodes": extv1beta1.JSONSchemaProps{
												Type: "array",
											},
											"useAllDevices": extv1beta1.JSONSchemaProps{
												Type: "boolean",
											},
											"useAllNodes": extv1beta1.JSONSchemaProps{
												Type: "boolean",
											},
											// TODO: Include StorageClassDeviceSets when merged in
											// rook-ceph.
										},
									},
								},
								Required: []string{
									"mon",
								},
							},
						},
					},
				},
				AdditionalPrinterColumns: []extv1beta1.CustomResourceColumnDefinition{
					{
						Name:        "DataDirHostPath",
						Type:        "string",
						Description: "Directory user on the K8s nodes",
						JSONPath:    ".spec.dataDirHostPath",
					},
					{
						Name:        "MonCount",
						Type:        "string",
						Description: "Number of MONs",
						JSONPath:    ".spec.mon.count",
					},
					{
						Name:     "Age",
						Type:     "date",
						JSONPath: ".metadata.creationTimestamp",
					},
					{
						Name:        "State",
						Type:        "string",
						Description: "Current State",
						JSONPath:    ".status.state",
					},
					{
						Name:        "Health",
						Type:        "string",
						Description: "Ceph Health",
						JSONPath:    ".status.ceph.health",
					},
				},
			},
		},
		// CephBlockPool CRD
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "apiextensions.k8s.io/v1beta1",
				Kind:       "CustomResourceDefinition",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "cephblockpools.ceph.rook.io",
			},
			Spec: extv1beta1.CustomResourceDefinitionSpec{
				Group:   "ceph.rook.io",
				Version: "v1",
				Scope:   "Namespaced",
				Names: extv1beta1.CustomResourceDefinitionNames{
					Kind:     "CephBlockPool",
					ListKind: "CephBlockPoolList",
					Plural:   "cephblockpools",
					Singular: "cephblockpool",
				},
			},
		},
		// CephObjectStore CRD
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "apiextensions.k8s.io/v1beta1",
				Kind:       "CustomResourceDefinition",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "cephobjectstores.ceph.rook.io",
			},
			Spec: extv1beta1.CustomResourceDefinitionSpec{
				Group:   "ceph.rook.io",
				Version: "v1",
				Scope:   "Namespaced",
				Names: extv1beta1.CustomResourceDefinitionNames{
					Kind:     "CephObjectStore",
					ListKind: "CephObjectStoreList",
					Plural:   "cephobjectstores",
					Singular: "cephobjectstore",
				},
			},
		},
		// CephObjectStoreUser CRD
		{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "apiextensions.k8s.io/v1beta1",
				Kind:       "CustomResourceDefinition",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "cephobjectstoreusers.ceph.rook.io",
			},
			Spec: extv1beta1.CustomResourceDefinitionSpec{
				Group:   "ceph.rook.io",
				Version: "v1",
				Scope:   "Namespaced",
				Names: extv1beta1.CustomResourceDefinitionNames{
					Kind:     "CephObjectStoreUser",
					ListKind: "CephObjectStoreUserList",
					Plural:   "cephobjectstoreusers",
					Singular: "cephobjectstoreuser",
				},
			},
		},
	}
}

// GetRookCephCRs is not included as we don't intend for users to directly create CephClusters.
