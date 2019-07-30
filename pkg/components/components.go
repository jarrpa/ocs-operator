package components

import (
	"fmt"

	ocsv1alpha1 "github.com/openshift/ocs-operator/pkg/apis/ocs/v1alpha1"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	extv1beta1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	operatorName = "ocs-operator"
)

// GetDeployment returns a Deployment which deploys the OCS operator
func GetDeployment(repository string, tag string, imagePullPolicy string) *appsv1.Deployment {
	registry_name := repository + "/openshift/" + operatorName
	image := fmt.Sprintf("%s:%s", registry_name, tag)
	deployment := &appsv1.Deployment{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "apps/v1",
			Kind:       "Deployment",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: operatorName,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: int32Ptr(1),
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{
					"name": operatorName,
				},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{
						"name": operatorName,
					},
				},
				Spec: corev1.PodSpec{
					ServiceAccountName: operatorName,
					Containers: []corev1.Container{
						{
							Name:            operatorName,
							Image:           image,
							ImagePullPolicy: corev1.PullPolicy(corev1.PullAlways),
							Ports: []corev1.ContainerPort{
								{
									ContainerPort: 60000,
									Name:          "metrics",
								},
							},
							// TODO: command being name is artifact of operator-sdk usage
							Command: []string{operatorName},
							ReadinessProbe: &corev1.Probe{
								Handler: corev1.Handler{
									Exec: &corev1.ExecAction{
										Command: []string{
											"stat",
											"/tmp/operator-sdk-ready",
										},
									},
								},
								InitialDelaySeconds: 5,
								PeriodSeconds:       5,
								FailureThreshold:    1,
							},
							Env: []corev1.EnvVar{
								{
									Name:  "OPERATOR_NAME",
									Value: operatorName,
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
									Name: "WATCH_NAMESPACE",
									ValueFrom: &corev1.EnvVarSource{
										FieldRef: &corev1.ObjectFieldSelector{
											FieldPath: "metadata.namespace",
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}
	return deployment
}

// GetRole returns the Role required by the OCS operator to function
func GetRole() *rbacv1.Role {
	role := &rbacv1.Role{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "rbac.authorization.k8s.io/v1",
			Kind:       "ClusterRole",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: operatorName,
			Labels: map[string]string{
				"name": operatorName,
			},
		},
		Rules: []rbacv1.PolicyRule{
			{
				APIGroups: []string{
					"",
				},
				Resources: []string{
					"pods",
					"services",
					"endpoints",
					"persistentvolumeclaims",
					"events",
					"configmaps",
					"secrets",
				},
				Verbs: []string{
					"*",
				},
			},
			{
				APIGroups: []string{
					""},
				Resources: []string{
					"namespaces",
				},
				Verbs: []string{
					"get",
				},
			},
			{
				APIGroups: []string{
					"apps",
				},
				Resources: []string{
					"deployments",
					"daemonsets",
					"replicasets",
					"statefulesets",
				},
				Verbs: []string{
					"get",
					"create",
				},
			},
			{
				APIGroups: []string{
					"monitoring.coreos.com",
				},
				Resources: []string{
					"servicemonitors",
				},
				Verbs: []string{
					"get",
					"create",
				},
			},
			{
				APIGroups: []string{
					"ocs.openshift.io",
				},
				Resources: []string{
					"storageclusters",
					"*",
				},
				Verbs: []string{
					"*",
				},
			},
		},
	}
	return role
}

// GetCRD returns a CustomResourceDefinition for the StorageCluster custom resource
func GetCRD() *extv1beta1.CustomResourceDefinition {
	crd := &extv1beta1.CustomResourceDefinition{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "apiextensions.k8s.io/v1beta1",
			Kind:       "CustomResourceDefinition",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: "storageclusters.ocs.openshift.io",
		},
		Spec: extv1beta1.CustomResourceDefinitionSpec{
			Group:   "ocs.openshift.io",
			Version: "v1alpha1",
			Scope:   "Namespaced",

			Versions: []extv1beta1.CustomResourceDefinitionVersion{
				{
					Name:    "v1alpha1",
					Served:  true,
					Storage: true,
				},
			},

			Names: extv1beta1.CustomResourceDefinitionNames{
				Plural:   "storageclusters",
				Singular: "storagecluster",
				Kind:     "StorageCluster",
				ListKind: "StorageClusterList",
			},

			Validation: &extv1beta1.CustomResourceValidation{
				OpenAPIV3Schema: &extv1beta1.JSONSchemaProps{
					Properties: map[string]extv1beta1.JSONSchemaProps{
						"apiVersion": extv1beta1.JSONSchemaProps{
							Type: "string",
						},
						"kind": extv1beta1.JSONSchemaProps{
							Type: "string",
						},
						"metadata": extv1beta1.JSONSchemaProps{
							Type: "object",
						},
						"status": extv1beta1.JSONSchemaProps{
							Type: "object",
						},
						"spec": extv1beta1.JSONSchemaProps{
							Type: "object",
							Properties: map[string]extv1beta1.JSONSchemaProps{
								"instanceType": extv1beta1.JSONSchemaProps{
									Type: "string",
								},
								"manageNodes": extv1beta1.JSONSchemaProps{
									Type: "boolean",
								},
								"storageDeviceSets": extv1beta1.JSONSchemaProps{
									Type: "array",
									Items: &extv1beta1.JSONSchemaPropsOrArray{
										Schema: &extv1beta1.JSONSchemaProps{
											Properties: map[string]extv1beta1.JSONSchemaProps{
												"config": extv1beta1.JSONSchemaProps{
													Type: "object",
												},
												"count": extv1beta1.JSONSchemaProps{
													Type:   "integer",
													Format: "int64",
												},
												"name": extv1beta1.JSONSchemaProps{
													Type: "string",
												},
												"placement": extv1beta1.JSONSchemaProps{
													Type: "object",
													Properties: map[string]extv1beta1.JSONSchemaProps{
														"nodeAffinity": extv1beta1.JSONSchemaProps{
															Type: "object",
														},
														"podAffinity": extv1beta1.JSONSchemaProps{
															Type: "object",
														},
														"podAntiAffinity": extv1beta1.JSONSchemaProps{
															Type: "object",
														},
														"tolerations": extv1beta1.JSONSchemaProps{
															Type: "array",
															Items: &extv1beta1.JSONSchemaPropsOrArray{
																Schema: &extv1beta1.JSONSchemaProps{
																	Type: "object",
																},
															},
														},
													},
												},
												"resources": extv1beta1.JSONSchemaProps{
													Type: "object",
												},
												"volumeClaimTemplates": extv1beta1.JSONSchemaProps{
													Type: "object",
												},
											},
											Required: []string{"name", "count", "resources", "placement", "volumeClaimTemplates"},
											Type:     "object",
										},
									},
								},
							},
							Required: []string{"storageDeviceSets"},
						},
					},
				},
			},
		},
	}
	return crd
}

// GetCR returns an example StorageCluster custom resource
func GetCR() *ocsv1alpha1.StorageCluster {
	return &ocsv1alpha1.StorageCluster{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "ocs.openshift.io/v1alpha1",
			Kind:       "StorageCluster",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:      "example-storagecluster",
			Namespace: "openshift-storage",
		},
		Spec: ocsv1alpha1.StorageClusterSpec{
			ManageNodes: false,
			// TODO: Add an example for StorageDeviceSets
			StorageDeviceSets: []ocsv1alpha1.StorageDeviceSet {

			},
		},
	}
}
