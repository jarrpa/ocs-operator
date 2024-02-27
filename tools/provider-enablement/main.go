package main

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	clientv1alpha1 "github.com/red-hat-storage/ocs-client-operator/api/v1alpha1"
	ocsv1 "github.com/red-hat-storage/ocs-operator/api/v4/v1"
	ocsv1alpha1 "github.com/red-hat-storage/ocs-operator/api/v4/v1alpha1"
	rookcephv1 "github.com/rook/rook/pkg/apis/ceph.rook.io/v1"

	"github.com/spf13/cobra"
	storagev1 "k8s.io/api/storage/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/klog/v2"
)

const (
	StorageRequestAnnotation      = "ocs.openshift.io.storagerequest"
	StorageCephUserTypeAnnotation = "ocs.openshift.io.cephusertype"
	StorageProfileSpecLabel       = "ocs.openshift.io/storageprofile-spec"
	ConsumerUUIDLabel             = "ocs.openshift.io/storageconsumer-uuid"
	StorageConsumerNameLabel      = "ocs.openshift.io/storageconsumer-name"
	StorageClassRequestLabel      = "ocs.openshift.io/storageclassrequest-name"
)

var (
	KubeConfig  string
	KubeContext string
	Namespace   string
)

func init() {
	RootCmd.PersistentFlags().StringVar(&KubeConfig, "kubeconfig", "", "kubeconfig path")
	RootCmd.PersistentFlags().StringVarP(&Namespace, "namespace", "n", "ocs-operator-system", "namespace where the StorageCluster CR is created")
	RootCmd.PersistentFlags().StringVar(&KubeContext, "context", "", "kubecontext to use")
}

// RootCmd represents the root cobra command
var RootCmd = &cobra.Command{
	Run: func(cmd *cobra.Command, args []string) {
		Do(cmd.Context())
	},
}

// GenerateStorageClassRequestName generates a name for a StorageClassRequest resource.
func GenerateStorageClassRequestName(consumerUUID, storageClassRequestName string) string {
	var s struct {
		StorageConsumerUUID     string `json:"storageConsumerUUID"`
		StorageClassRequestName string `json:"storageClassRequestName"`
	}
	s.StorageConsumerUUID = consumerUUID
	s.StorageClassRequestName = storageClassRequestName

	requestName, err := json.Marshal(s)
	if err != nil {
		klog.Fatalf("failed to marshal a name for a storage class request based on %v. %v", s, err)
	}
	name := md5.Sum([]byte(requestName))

	// The name of the StorageClassRequest is the MD5 hash of the JSON
	// representation of the StorageClassRequest name and storageConsumer UUID.
	return fmt.Sprintf("storageclassrequest-%s", hex.EncodeToString(name[:16]))
}

func GenerateHashForCephClient(storageConsumerName, cephUserType string) string {
	var c struct {
		StorageConsumerName string `json:"id"`
		CephUserType        string `json:"cephUserType"`
	}

	c.StorageConsumerName = storageConsumerName
	c.CephUserType = cephUserType

	cephClient, err := json.Marshal(c)
	if err != nil {
		klog.Fatal("failed to marshal")
	}
	name := md5.Sum([]byte(cephClient))
	return hex.EncodeToString(name[:16])
}

// ClaimStorageClass creates the required resources for the provider server to
// manage StorageClasses and their corresponding Ceph resources.
func ClaimStorageClass(ctx context.Context, cs *Clientsets, storageConsumer ocsv1alpha1.StorageConsumer, sc *storagev1.StorageClass) error {
	var err error

	klog.Infof("claiming StorageClass %q with provisioner %q", sc.Name, sc.Provisioner)
	claimName := sc.GetName()
	storageClassClaim := &clientv1alpha1.StorageClassClaim{}
	err = cs.ClientV1alpha1.Get().
		Namespace(Namespace).
		Resource("storageclassclaims").
		Name(claimName).
		Do(ctx).
		Into(storageClassClaim)
	if err == nil {
		klog.Infof("found existing StorageClassClaim for StorageClass %q", claimName)
		return err
	} else if !apierrors.IsNotFound(err) {
		klog.Error(err)
		return err
	}

	// Find required StorageProfile
	storageProfiles := ocsv1.StorageProfileList{}
	err = cs.OcsV1.Get().Resource("storageprofiles").Do(ctx).Into(&storageProfiles)
	if err != nil {
		klog.Error(err)
		return err
	}
	storageProfile := storageProfiles.Items[0]
	klog.Infof("using StorageProfile %q with hash: %s", storageProfile.Name, storageProfile.GetSpecHash())

	// Generate resource names
	consumerID := string(storageConsumer.GetUID())
	scrName := GenerateStorageClassRequestName(consumerID, claimName)
	scrNsName := fmt.Sprintf("%s/%s", Namespace, scrName)
	klog.Info("generated StorageClassRequest name: " + scrName)
	provisionerClientName := GenerateHashForCephClient(scrName, "provisioner")
	klog.Info("generated provisioner CephClient name: " + provisionerClientName)
	nodeClientName := GenerateHashForCephClient(scrName, "node")
	klog.Info("generated node CephClient name: " + nodeClientName)

	// Initialize CephClients
	provisionerCephClient := &rookcephv1.CephClient{
		ObjectMeta: metav1.ObjectMeta{
			Name:      provisionerClientName,
			Namespace: Namespace,
			Annotations: map[string]string{
				StorageRequestAnnotation:      scrNsName,
				StorageCephUserTypeAnnotation: "provisioner",
			},
		},
		Spec: rookcephv1.ClientSpec{},
	}

	nodeCephClient := &rookcephv1.CephClient{
		ObjectMeta: metav1.ObjectMeta{
			Name:      nodeClientName,
			Namespace: Namespace,
			Annotations: map[string]string{
				StorageRequestAnnotation:      scrNsName,
				StorageCephUserTypeAnnotation: "node",
			},
		},
		Spec: rookcephv1.ClientSpec{},
	}

	// Initialize StorageClassRequest
	trueBool := true
	storageClassRequest := &ocsv1alpha1.StorageClassRequest{
		TypeMeta: metav1.TypeMeta{
			APIVersion: ocsv1alpha1.GroupVersion.String(),
			Kind:       "StorageClassRequest",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:      scrName,
			Namespace: Namespace,
			Labels: map[string]string{
				ConsumerUUIDLabel:        consumerID,
				StorageClassRequestLabel: claimName,
			},
			OwnerReferences: []metav1.OwnerReference{
				{
					APIVersion:         ocsv1alpha1.GroupVersion.String(),
					Kind:               storageConsumer.Kind,
					Name:               storageConsumer.GetName(),
					UID:                storageConsumer.GetUID(),
					BlockOwnerDeletion: &trueBool,
				},
			},
		},
		Spec: ocsv1alpha1.StorageClassRequestSpec{},
		Status: ocsv1alpha1.StorageClassRequestStatus{
			Phase: ocsv1alpha1.StorageClassRequestReady,
			CephResources: []*ocsv1alpha1.CephResourcesSpec{
				{
					Kind:  "CephClient",
					Name:  provisionerCephClient.Name,
					Phase: "Ready",
				},
				{
					Kind:  "CephClient",
					Name:  nodeCephClient.Name,
					Phase: "Ready",
				},
			},
		},
	}

	if strings.HasSuffix(sc.Provisioner, "rbd.csi.ceph.com") {
		// Find CephBlockPool and update labels
		cephBlockPools, err := cs.Rook.CephV1().CephBlockPools(Namespace).List(ctx, metav1.ListOptions{})
		if err != nil {
			klog.Error(err)
			return err
		} else if len(cephBlockPools.Items) < 1 {
			klog.Error("no cephblockpools")
			return err
		}
		cephBlockPool := cephBlockPools.Items[0]
		klog.Infof("using CephBlockPool %q", cephBlockPool.Name)

		cephBlockPool.Labels = map[string]string{
			StorageConsumerNameLabel: storageConsumer.Name,
			StorageProfileSpecLabel:  storageProfile.GetSpecHash(),
		}

		// Configure CephClients
		cephClientCaps := map[string]string{
			"mgr": "allow rw",
			"mon": "profile rbd",
			"osd": "profile rbd pool=" + cephBlockPool.Name,
		}

		provisionerCephClient.Spec.Caps = cephClientCaps
		provisionerCephClient.ObjectMeta.Annotations[StorageRequestAnnotation] = "rbd"

		nodeCephClient.Spec.Caps = cephClientCaps
		nodeCephClient.ObjectMeta.Annotations[StorageRequestAnnotation] = "rbd"

		storageClassRequest.Spec = ocsv1alpha1.StorageClassRequestSpec{
			Type: "blockpool",
		}
		storageClassRequest.Status.CephResources = append(storageClassRequest.Status.CephResources,
			&ocsv1alpha1.CephResourcesSpec{
				Kind:  "CephBlockPool",
				Name:  cephBlockPool.Name,
				Phase: "Ready",
				CephClients: map[string]string{
					"provisioner": provisionerCephClient.Name,
					"node":        nodeCephClient.Name,
				},
			})

		// Ensure CephClients
		klog.Infof("ensuring provisioner CephClient %q...", provisionerClientName)
		_, err = cs.Rook.CephV1().CephClients(Namespace).Create(ctx, provisionerCephClient, metav1.CreateOptions{})
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}

		klog.Infof("ensuring node CephClient %q...", nodeClientName)
		_, err = cs.Rook.CephV1().CephClients(Namespace).Create(ctx, nodeCephClient, metav1.CreateOptions{})
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}

		// Ensure StorageClassRequest
		klog.Infof("ensuring StorageClassRequest %q...", scrName)
		scrResult := &ocsv1alpha1.StorageClassRequest{}
		err = cs.OcsV1alpha1.Post().
			Namespace(Namespace).
			Resource("storageclassrequests").
			Body(storageClassRequest).
			Do(ctx).
			Into(scrResult)
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}
		storageClassRequest.ObjectMeta.ResourceVersion = scrResult.ResourceVersion
		err = cs.OcsV1alpha1.Put().
			Name(storageClassRequest.Name).
			Namespace(Namespace).
			Resource("storageclassrequests").
			SubResource("status").
			Body(storageClassRequest).
			Do(ctx).
			Into(scrResult)
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}

		scrOwnerRef := metav1.OwnerReference{
			APIVersion:         storageClassRequest.APIVersion,
			Kind:               storageClassRequest.Kind,
			Name:               scrResult.GetName(),
			UID:                scrResult.GetUID(),
			BlockOwnerDeletion: &trueBool,
			Controller:         &trueBool,
		}
		cephBlockPool.ObjectMeta.OwnerReferences = []metav1.OwnerReference{scrOwnerRef}
		klog.Info("updating CephBlockPool labels...")
		_, err = cs.Rook.CephV1().CephBlockPools(Namespace).Update(ctx, &cephBlockPool, metav1.UpdateOptions{})
		if err != nil {
			klog.Error(err)
			return err
		}
	} else if strings.HasSuffix(sc.Provisioner, ".cephfs.csi.ceph.com") {
		// Find CephFilesystemSubVolumeGroup and update labels
		cephSubvolumeGroup, err := cs.Rook.CephV1().CephFilesystemSubVolumeGroups(Namespace).Get(ctx, "example-storagecluster-cephfilesystem-csi", metav1.GetOptions{})
		if err != nil {
			klog.Error(err)
			return err
		}
		klog.Infof("using CephFilesystemSubVolumeGroup %q", cephSubvolumeGroup.Name)

		cephSubvolumeGroup.Labels = map[string]string{
			StorageConsumerNameLabel: storageConsumer.Name,
			StorageProfileSpecLabel:  storageProfile.GetSpecHash(),
		}

		// Configure CephClients
		cephClientCaps := map[string]string{
			"mds": "allow rw path=/volumes/" + cephSubvolumeGroup.Name,
			"mgr": "allow rw",
			"mon": "allow r",
			"osd": "allow rw tag cephfs *=*",
		}

		provisionerCephClient.Spec.Caps = cephClientCaps
		provisionerCephClient.ObjectMeta.Annotations[StorageRequestAnnotation] = "cephfs"

		nodeCephClient.Spec.Caps = cephClientCaps
		nodeCephClient.ObjectMeta.Annotations[StorageRequestAnnotation] = "cephfs"

		storageClassRequest.Spec = ocsv1alpha1.StorageClassRequestSpec{
			Type: "sharedfilesystem",
		}
		storageClassRequest.Status.CephResources = append(storageClassRequest.Status.CephResources,
			&ocsv1alpha1.CephResourcesSpec{
				Kind:  "CephFilesystemSubVolumeGroup",
				Name:  cephSubvolumeGroup.Name,
				Phase: "Ready",
				CephClients: map[string]string{
					"provisioner": provisionerCephClient.Name,
					"node":        nodeCephClient.Name,
				},
			})

		// Ensure CephClients
		klog.Infof("ensuring provisioner CephClient %q...", provisionerClientName)
		_, err = cs.Rook.CephV1().CephClients(Namespace).Create(ctx, provisionerCephClient, metav1.CreateOptions{})
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}

		klog.Infof("ensuring node CephClient %q...", nodeClientName)
		_, err = cs.Rook.CephV1().CephClients(Namespace).Create(ctx, nodeCephClient, metav1.CreateOptions{})
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}

		// Ensure StorageClassRequest
		klog.Infof("ensuring StorageClassRequest %q...", scrName)
		scrResult := &ocsv1alpha1.StorageClassRequest{}
		err = cs.OcsV1alpha1.Post().
			Namespace(Namespace).
			Resource("storageclassrequests").
			Body(storageClassRequest).
			Do(ctx).
			Into(scrResult)
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}

		storageClassRequest.ObjectMeta.ResourceVersion = scrResult.ResourceVersion
		err = cs.OcsV1alpha1.Put().
			Name(storageClassRequest.Name).
			Namespace(Namespace).
			Resource("storageclassrequests").
			SubResource("status").
			Body(storageClassRequest).
			Do(ctx).
			Into(scrResult)
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			return err
		}

		scrOwnerRef := metav1.OwnerReference{
			APIVersion:         storageClassRequest.APIVersion,
			Kind:               storageClassRequest.Kind,
			Name:               scrResult.GetName(),
			UID:                scrResult.GetUID(),
			BlockOwnerDeletion: &trueBool,
			Controller:         &trueBool,
		}
		cephSubvolumeGroup.ObjectMeta.OwnerReferences = []metav1.OwnerReference{scrOwnerRef}
		klog.Info("updating CephFilesystemSubVolumeGroup...")
		_, err = cs.Rook.CephV1().CephFilesystemSubVolumeGroups(Namespace).Update(ctx, cephSubvolumeGroup, metav1.UpdateOptions{})
		if err != nil {
			klog.Error(err)
			return err
		}
	}

	return nil
}

// Do does the main thing
func Do(ctx context.Context) {
	var err error

	klog.Info("Doing the thing!")

	// Get k8s clientsets
	cs := GetClientsets(ctx)

	// Get the list of StorageClasses and check for any CephCSI provisioners
	storageClasses := []storagev1.StorageClass{}
	storageClassList, err := cs.Kube.StorageV1().StorageClasses().List(ctx, metav1.ListOptions{})
	if err != nil {
		klog.Fatal(err)
	}
	cephCsiRegex := regexp.MustCompile("openshift-storage" + `\.(rbd|cephfs)\.csi\.ceph\.com`)
	//cephCsiRegex := regexp.MustCompile("openshift-storage" + `\.(rbd)\.csi\.ceph\.com`)
	for _, sc := range storageClassList.Items {
		if cephCsiRegex.MatchString(sc.Provisioner) {
			storageClasses = append(storageClasses, sc)
		}
	}
	if len(storageClasses) == 0 {
		klog.Fatal("No StorageClasses found, doing no such thing!")
	}

	// Find StorageConsumer
	storageConsumers := ocsv1alpha1.StorageConsumerList{}
	err = cs.OcsV1alpha1.Get().
		Namespace(Namespace).
		Resource("storageconsumers").
		Do(ctx).
		Into(&storageConsumers)
	if err != nil {
		klog.Fatal(err)
	}
	if len(storageConsumers.Items) == 0 {
		klog.Fatal("uh-oh, none StorageConsumers found!")
	}
	storageConsumer := storageConsumers.Items[0]
	consumerID := string(storageConsumer.GetUID())
	klog.Infof("using StorageConsumer %q with UID: %s", storageConsumer.Name, consumerID)

	for _, sc := range storageClasses {
		// We need to create a StorageClassClaim with the same name as
		// the corresponding StorageClass. Check to see if it exists,
		// first.
		err = ClaimStorageClass(ctx, cs, storageConsumer, &sc)
		if err != nil && !apierrors.IsAlreadyExists(err) {
			klog.Error(err)
			continue
		}
	}

	klog.Info("Done! Good luck out there.")
}

func main() {
	err := RootCmd.Execute()
	if err != nil {
		klog.Fatal(err)
	}
}
