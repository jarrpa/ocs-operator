package main

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	ocsv1alpha1 "github.com/red-hat-storage/ocs-operator/api/v4/v1alpha1"
	"github.com/red-hat-storage/ocs-operator/v4/pkg/operations"
	"github.com/spf13/cobra"
	corev1 "k8s.io/api/core/v1"
	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/klog/v2"
)

// TODO: Maybe import from Ceph-CSI
type ClusterConfigEntry struct {
	ClusterID       string       `json:"clusterID"`
	StorageClientID string       `json:"storageClientID"`
	Monitors        []string     `json:"monitors"`
	CephFS          *CephFSSpec  `json:"cephFS,omitempty"`
	CephRBD         *CephRBDSpec `json:"rbd,omitempty"`
}

type CephRBDSpec struct {
	RadosNamespace string `json:"radosNamespace,omitempty"`
}

type CephFSSpec struct {
	SubvolumeGroup string `json:"subvolumeGroup,omitempty"`
}

type StorageClassState struct {
	Phase      string
	WorkingPVs map[string]corev1.PersistentVolume
}

type JobState struct {
	StorageClassStates map[string]StorageClassState
}

const (
	migrationPhaseAnnotation  = "volume-migration.ops.ocs.openshift.io/phase"
	migrationSourceAnnotation = "volume-migration.ops.ocs.openshift.io/source"
	migrationTargetAnnotation = "volume-migration.ops.ocs.openshift.io/target"
)

var (
	DryRun     bool
	DryRunOpts = []string{}

	StateFilePath string
	State         JobState

	OpMode string

	KubeConfig  string
	KubeContext string
	Namespace   string

	ClientSets *Clientsets
	AllPVs     *corev1.PersistentVolumeList
)

// RootCmd represents the root cobra command
var RootCmd = &cobra.Command{
	Run: func(cmd *cobra.Command, args []string) {
		Do(cmd.Context())
	},
}

func init() {
	RootCmd.PersistentFlags().StringVar(&KubeConfig, "kubeconfig", "", "kubeconfig path")
	RootCmd.PersistentFlags().StringVar(&KubeContext, "context", "", "kubecontext to use")
	RootCmd.PersistentFlags().BoolVar(&DryRun, "dry-run", true, "no commitments")
	RootCmd.PersistentFlags().StringVarP(&StateFilePath, "state-file", "f", "state.json", "path to file where program will store state")
	RootCmd.PersistentFlags().StringVarP(&OpMode, "mode", "m", "converged", "'converged', 'provider', or 'consumer'")
}

func main() {
	err := RootCmd.Execute()
	if err != nil {
		klog.Fatal(err)
	}
}

func LoadState() error {
	klog.Info("Initializing operation state...")
	stateJSON, err := os.ReadFile(StateFilePath)
	if err != nil && os.IsNotExist(err) {
		State = JobState{
			StorageClassStates: map[string]StorageClassState{},
		}
		return nil
	} else if err != nil {
		return err
	}

	err = json.Unmarshal(stateJSON, &State)
	if err != nil {
		return err
	}

	return nil
}

func SaveState() error {
	klog.Info("Saving current state...")
	stateJSON, err := json.Marshal(State)
	if err != nil {
		return err
	}
	err = os.WriteFile(StateFilePath, stateJSON, 0644)
	if err != nil {
		return err
	}
	return nil
}

// Do does the main thing
func Do(ctx context.Context) {
	var err error

	klog.Info("Doing the thing!")
	if DryRun {
		klog.Info("...but not really.")
		DryRunOpts = append(DryRunOpts, "All")
	}

	Namespace = os.Getenv("POD_NAMESPACE")
	if Namespace == "" {
		klog.Fatal("Env var POD_NAMESPACE not set!")
	}

	// TODO: USE CONFIGMAP!!
	// Load or initialize job state
	err = LoadState()
	if err != nil {
		klog.Fatal(err)
	}

	// Get k8s clientsets
	ClientSets = GetClientsets(ctx)

	switch OpMode {
	case "converged":
		ConsumerDo(ctx)
		MigrateRbdVolumes(ctx)
		ConsumerDo(ctx)
	case "provider":
		MigrateRbdVolumes(ctx)
	case "consumer":
		ConsumerDo(ctx)
	}

	klog.Info("Done! Good luck out there.")
}

// MigrateRbdVolumes does the main thing for provider mode
func MigrateRbdVolumes(ctx context.Context) {
	var err error

	klog.Info("Doing the thing as a storage provider")

	scrName := os.Getenv("STORAGE_REQUEST")
	scr := &ocsv1alpha1.StorageRequest{}
	err = ClientSets.OcsV1alpha1.Get().
		Name(scrName).
		Namespace(Namespace).
		Do(ctx).
		Into(scr)
	if err != nil && !errors.IsAlreadyExists(err) {
		klog.Error(err)
	}

	volOpFound := false
	var ops []string
	if pendingOps, ok := scr.Annotations[operations.PendingOperationsAnnotation]; ok {
		ops = strings.Split(pendingOps, ",")
		for _, op := range ops {
			if op == "volume-migration" {
				volOpFound = true
				continue
			}
		}
	}
	if !volOpFound {
		klog.Fatal("scr has no op!")
	}

	migrationPhase := scr.Annotations[migrationPhaseAnnotation]

	for migrationPhase != "Completed" {
		scrUpdate := false
		switch migrationPhase {
		case "":
			migrationPhase = "Requested"
			scrUpdate = true
		case "Requested":
			klog.Fatal("op needs consumer approval")
		case "Approved":
			// STRETCH TODO: maybe have some provider API call initiate an approval
			migrationSource := scr.Annotations[migrationSourceAnnotation]
			migrationTarget := scr.Annotations[migrationTargetAnnotation]

			if migrationSource == "" {
				for _, res := range scr.Status.CephResources {
					if res.Kind == "CephBlockPool" {
						migrationSource = res.Name
						scrUpdate = true
						break
					}
				}
				if migrationSource == "" {
					klog.Fatal("no migration source found")
				}
			}
			if migrationTarget == "" {
				md5Sum := md5.Sum([]byte(scr.Name))
				migrationTarget = fmt.Sprintf("cephradosnamespace-%s", hex.EncodeToString(md5Sum[:16]))
				scrUpdate = true
			}

			scr.Annotations[migrationSourceAnnotation] = migrationSource
			scr.Annotations[migrationTargetAnnotation] = migrationTarget

			migrationPhase = "DataMigrating"
			scrUpdate = true
		case "DataMigrating":
			migrationSource := scr.Annotations[migrationSourceAnnotation]
			migrationTarget := scr.Annotations[migrationTargetAnnotation]

			statusChan := make(chan string)
			go func() {
				err = PhaseDataMigration(migrationSource, migrationTarget, statusChan)
				if err != nil {
					klog.Error("ope!")
				} else {
					migrationPhase = "MigrationComplete"
					scrUpdate = true
				}
			}()

			for status := range statusChan {
				klog.Info(status)
			}

		case "MigrationCompleted":
			// STRETCH TODO: maybe have some provider API call initiate an approval
			for i, op := range ops {
				if op == "volume-migration" {
					ops = append(ops[:i], ops[i+1:]...)
					break
				}
			}
			scr.Annotations[operations.PendingOperationsAnnotation] = strings.Join(ops, ",")

			var newCephResources []*ocsv1alpha1.CephResourcesSpec
			for _, cephResourceSpec := range scr.Status.CephResources {
				if cephResourceSpec.Name != scr.Annotations[migrationSourceAnnotation] {
					newCephResources = append(newCephResources, cephResourceSpec)
				}
			}

			scr.Status.CephResources = newCephResources
			migrationPhase = "Completed"
			scrUpdate = true
		default:
			klog.Infof("data migration in progress for StorageRequest %q: %q", scr.Name, migrationPhase)
		}

		if scrUpdate {
			scr.Annotations[migrationPhaseAnnotation] = migrationPhase
			scrResult := &ocsv1alpha1.StorageRequest{}
			err = ClientSets.OcsV1alpha1.Post().
				Namespace(Namespace).
				Resource("storagerequests").
				Body(scr).
				Do(ctx).
				Into(scrResult)
			if err != nil && !errors.IsAlreadyExists(err) {
				klog.Fatal(err)
			}
			scr.ObjectMeta.ResourceVersion = scrResult.ResourceVersion
			err = ClientSets.OcsV1alpha1.Put().
				Name(scr.Name).
				Namespace(Namespace).
				Resource("storagerequests").
				SubResource("status").
				Body(scr).
				Do(ctx).
				Into(scrResult)
			if err != nil && !errors.IsAlreadyExists(err) {
				klog.Fatal(err)
			}
		}

		time.Sleep(time.Second * 5)
	}
}

// ConsumerDo does the main thing for consumer mode
func ConsumerDo(ctx context.Context) {
	klog.Info("Doing the thing as a storage consumer")

	clusterID := os.Getenv("CLUSTER_ID")

	// Get the list of StorageClasses and check for a CephCSI class
	// matching the desired clusterID
	var sc *storagev1.StorageClass
	storageClassList, err := ClientSets.Kube.StorageV1().StorageClasses().List(ctx, metav1.ListOptions{})
	if err != nil {
		klog.Fatal(err)
	}
	for i, storageClass := range storageClassList.Items {
		if id, ok := storageClass.Parameters["clusterID"]; ok && id == clusterID {
			sc = &storageClassList.Items[i]
		}
	}
	if sc == nil {
		klog.Fatal("No StorageClass found, doing no such thing!")
	}

	AllPVs, err = ClientSets.Kube.CoreV1().PersistentVolumes().List(ctx, metav1.ListOptions{})
	if err != nil {
		klog.Fatal(err)
	}

	klog.Infof("Migrating volumes for StorageClass %q", sc.Name)
	err = MigrateStorageClass(ctx, sc)
	if err != nil && !errors.IsAlreadyExists(err) {
		klog.Error(err)
	}
	sc.ObjectMeta.Annotations[migrationPhaseAnnotation] = State.StorageClassStates[sc.Name].Phase
	_, err = ClientSets.Kube.StorageV1().StorageClasses().Update(ctx, sc, metav1.UpdateOptions{DryRun: DryRunOpts})
	if err != nil {
		klog.Fatal(err)
	}
}

func MigrateStorageClass(ctx context.Context, sc *storagev1.StorageClass) error {
	workingState, ok := State.StorageClassStates[sc.Name]
	if !ok {
		workingState = StorageClassState{
			Phase:      "Initializing",
			WorkingPVs: map[string]corev1.PersistentVolume{},
		}
		State.StorageClassStates[sc.Name] = workingState
	} else if workingState.Phase == "Migrated" || sc.ObjectMeta.Annotations[migrationPhaseAnnotation] == "Migrated" {
		workingState.Phase = "Migrated"
		return nil
	}

	for _, pv := range AllPVs.Items {
		if pv.Spec.StorageClassName == sc.Name {
			workingState.WorkingPVs[pv.Name] = pv
		}
	}

	pvs := workingState.WorkingPVs
	if len(pvs) == 0 {
		klog.Infof("no PVs found for StorageClass %q", sc.Name)
		workingState.Phase = "Migrated"
		return nil
	}

	SaveState()

	switch workingState.Phase {
	case "Initializing":
		workingState.Phase = "DeletingVolumes"
		fallthrough
	case "DeletingVolumes":
		remainingVolumes, err := deleteVolumes(ctx, sc, &workingState)
		if err != nil {
			return err
		}
		if len(remainingVolumes) != 0 {
			klog.Error("multiple volumes left, restart")
			return nil
		}
		workingState.Phase = "RestoringVolumes"
	case "RestoringVolumes":
		err := restoreVolumes(ctx, sc, &workingState)
		if err != nil {
			return err
		}
		workingState.Phase = "Migrated"
	}

	return nil
}

func deleteVolumes(ctx context.Context, sc *storagev1.StorageClass, workingState *StorageClassState) (map[string]corev1.PersistentVolume, error) {
	pvClient := ClientSets.Kube.CoreV1().PersistentVolumes()
	pvs := workingState.WorkingPVs
	pvsDeleting := true

	for pvsDeleting {
		pvsDeleting = false
		for pvName := range pvs {
			pv, err := pvClient.Get(ctx, pvName, metav1.GetOptions{})
			if errors.IsNotFound(err) {
				delete(pvs, pvName)
				continue
			}
			if !DryRun {
				pvsDeleting = true
			}
			if !pv.ObjectMeta.DeletionTimestamp.IsZero() {
				klog.Infof("Volume %q for StorageClass %q is deleting...", pvName, sc.Name)
				continue
			}

			// Look for Pods referencing a PVC that is bound to the PV
			if inUse, err := volumeInUse(ctx, pv); err != nil || inUse {
				if err != nil {
					klog.Error(err)
				}
				continue
			}
			klog.Infof("No Pods found using PV %q, let's go!", pvName)

			// Edit and delete the PV without deleting the underlying RBD volume
			klog.Infof("Deleting volume %q for StorageClass %q", pvName, sc.Name)
			pv.Spec.PersistentVolumeReclaimPolicy = corev1.PersistentVolumeReclaimRetain
			pv.ObjectMeta.Finalizers = nil

			updatedPv, err := pvClient.Update(ctx, pv,
				metav1.UpdateOptions{DryRun: DryRunOpts})
			if err != nil {
				klog.Error(err)
				continue
			}
			pvs[pvName] = *updatedPv

			err = pvClient.Delete(ctx, pvName,
				metav1.DeleteOptions{DryRun: DryRunOpts})
			if err != nil {
				klog.Error(err)
				continue
			}
		}
	}

	return pvs, nil
}

func volumeInUse(ctx context.Context, pv *corev1.PersistentVolume) (bool, error) {
	coreClient := ClientSets.Kube.CoreV1()
	foundPods := false

	pvc, err := coreClient.PersistentVolumeClaims(pv.Spec.ClaimRef.Namespace).Get(ctx, pv.Spec.ClaimRef.Name, metav1.GetOptions{})
	if err != nil {
		klog.Error(err)
		return foundPods, err
	}
	klog.Infof("found PVC bound to volume %q: %q", pv.Name, pvc.Name)

	pods, err := coreClient.Pods(pv.Spec.ClaimRef.Namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		klog.Error(err)
		return foundPods, err
	}

	for _, pod := range pods.Items {
		for _, volume := range pod.Spec.Volumes {
			if volume.VolumeSource.PersistentVolumeClaim != nil && volume.VolumeSource.PersistentVolumeClaim.ClaimName == pvc.Name {
				klog.Warningf("found Pod using PVC %q: %q", pvc.Name, pod.Name)
				foundPods = true
			}
		}
	}
	if foundPods {
		klog.Errorf("found Pods using PVC %q, will not migrate", pvc.Name)
		return foundPods, err
	}

	return foundPods, nil
}

func restoreVolumes(ctx context.Context, sc *storagev1.StorageClass, workingState *StorageClassState) error {
	pvClient := ClientSets.Kube.CoreV1().PersistentVolumes()
	pvs := workingState.WorkingPVs
	newSc, err := ClientSets.Kube.StorageV1().StorageClasses().Get(ctx, sc.Name, metav1.GetOptions{})
	if err != nil {
		return err
	}
	clusterID := newSc.Parameters["clusterID"]
	cm, err := ClientSets.Kube.CoreV1().ConfigMaps(Namespace).Get(ctx, "ceph-csi-configs", metav1.GetOptions{})
	if err != nil {
		return err
	}
	csiConfigs := []ClusterConfigEntry{}
	err = json.Unmarshal([]byte(cm.Data["config.json"]), &csiConfigs)
	if err != nil {
		return err
	}

	newRadosNamespace := ""
	for _, config := range csiConfigs {
		if config.ClusterID == clusterID && config.CephRBD != nil && config.CephRBD.RadosNamespace != "" {
			newRadosNamespace = config.CephRBD.RadosNamespace
			break
		}
	}

	for pvName, pv := range pvs {
		actualPv, err := pvClient.Get(ctx, pvName, metav1.GetOptions{})
		if !errors.IsNotFound(err) {
			if phase, ok := actualPv.Annotations["migration-state"]; ok && phase == "migrated" {
				delete(pvs, pvName)
			}
			continue
		}

		if newRadosNamespace != "" {
			pv.Spec.CSI.VolumeAttributes["radosNamespace"] = newRadosNamespace
		}
		pv.Spec.CSI.VolumeAttributes["clusterID"] = clusterID
		pv.Spec.CSI.VolumeAttributes["staticVolume"] = "true"
		pv.Spec.CSI.VolumeHandle = pv.Spec.CSI.VolumeAttributes["imageName"]
		pv.Spec.PersistentVolumeReclaimPolicy = corev1.PersistentVolumeReclaimDelete

		pv.ObjectMeta.Annotations["storage-migration.odf.openshift.io/state"] = "migrated"

		createdPv, err := pvClient.Create(ctx, &pv,
			metav1.CreateOptions{DryRun: DryRunOpts})
		if err != nil {
			klog.Error(err)
			if createdPv.Annotations["migration-state"] != "migrated" {
				klog.Warningf("volumes remain, re-run job")
			}
			continue
		}

		delete(pvs, pvName)
	}

	workingState.WorkingPVs = pvs
	return nil
}
