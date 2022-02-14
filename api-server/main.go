package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"strconv"

	"github.com/blang/semver"
	"github.com/oklog/run"
	"k8s.io/klog/v2"

	ocsv1 "github.com/red-hat-storage/ocs-operator/api/v1"
	ocsutil "github.com/red-hat-storage/ocs-operator/controllers/util"
	ocsver "github.com/red-hat-storage/ocs-operator/version"
)

// versionCheck populates the `.Spec.Version` field
func versionCheck(sc *ocsv1.StorageCluster) error {
	if sc.Spec.Version == "" {
		sc.Spec.Version = ocsver.Version
	} else if sc.Spec.Version != ocsver.Version { // check anything else only if the versions mis-match
		storClustSemV1, err := semver.Make(sc.Spec.Version)
		if err != nil {
			klog.Errorf("Error while parsing Storage Cluster version: %v", err)
			return err
		}
		ocsSemV1, err := semver.Make(ocsver.Version)
		if err != nil {
			klog.Errorf("Error while parsing ocs-operator version: %v", err)
			return err
		}
		// if the storage cluster version is higher than the invoking OCS Operator's version,
		// return error
		if storClustSemV1.GT(ocsSemV1) {
			err = fmt.Errorf("storage cluster version (%s) is higher than the OCS Operator version (%s)",
				sc.Spec.Version, ocsver.Version)
			klog.Errorf("Incompatible Storage cluster version: %v", err)
			return err
		}
		// if the storage cluster version is less than the OCS Operator version,
		// just update.
		sc.Spec.Version = ocsver.Version
	}
	return nil
}

// validateStorageClusterSpec must be called before reconciling. Any syntactic and sematic errors in the CR must be caught here.
func validateStorageClusterSpec(instance *ocsv1.StorageCluster) error {
	if err := versionCheck(instance); err != nil {
		klog.Errorf("Failed to validate StorageCluster version: %v (%v)", err, klog.KRef(instance.Namespace, instance.Name))

		instance.Status.Phase = ocsutil.PhaseError
		return err
	}

	return nil
}

func storageClusterServ(w http.ResponseWriter, r *http.Request) {
	var err error

	sc := ocsv1.StorageCluster{}

	decoder := json.NewDecoder(r.Body)
	err = decoder.Decode(&sc)
	if err != nil {
		http.Error(w, err.Error(), 500)
		r.Body.Close()
		klog.Errorf("Decode err: %v", err.Error())
		return
	}
	klog.V(2).Infof("Decoded data: %+v", sc)

	err = validateStorageClusterSpec(&sc)
	if err != nil {
		http.Error(w, err.Error(), 500)
		r.Body.Close()
		klog.Errorf("Validate err: %v", err.Error())
		return
	}

	w.Write([]byte("Success!\n"))
	klog.Info("SUCCESS!!")
	r.Body.Close()
}

func main() {
	var port int
	flag.IntVar(&port, "port", 8888, "usage")
	klog.InitFlags(flag.CommandLine)
	flag.Parse()
	klog.InfoS("START", "foo", "bar")

	//kubeconfig, err := clientcmd.BuildConfigFromFlags("", os.Getenv("KUBECONFIG"))
	err := error(nil)
	if err != nil {
		klog.Fatalf("failed to create cluster config: %v", err)
	}

	servMux := http.NewServeMux()
	servMux.Handle("/storagecluster", http.HandlerFunc(storageClusterServ))

	var rg run.Group
	rg.Add(listenAndServe(servMux, "0.0.0.0", port))

	err = rg.Run()
	if err != nil {
		klog.Fatalf("we died!: %v", err)
	}
}

func listenAndServe(mux *http.ServeMux, host string, port int) (func() error, func(error)) {
	var listener net.Listener
	serve := func() error {
		addr := net.JoinHostPort(host, strconv.Itoa(port))
		listener, err := net.Listen("tcp", addr)
		if err != nil {
			return err
		}
		return http.Serve(listener, mux)
	}
	cleanup := func(error) {
		err := listener.Close()
		if err != nil {
			klog.Errorf("failed to close listener: %v", err)
		}
	}
	return serve, cleanup
}
