package main

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
)

// getStorageClassRequestName generates a name for a StorageClassRequest resource.
func getStorageClassRequestName(consumerUUID, storageClassRequestName string) string {
	var s struct {
		StorageConsumerUUID     string `json:"storageConsumerUUID"`
		StorageClassRequestName string `json:"storageClassRequestName"`
	}
	s.StorageConsumerUUID = consumerUUID
	s.StorageClassRequestName = storageClassRequestName

	requestName, err := json.Marshal(s)
	if err != nil {
		panic(fmt.Sprintf("failed to marshal a name for a storage class request based on %v. %v", s, err))
	}
	name := md5.Sum([]byte(requestName))
	// The name of the StorageClassRequest is the MD5 hash of the JSON
	// representation of the StorageClassRequest name and storageConsumer UUID.
	return fmt.Sprintf("storageclassrequest-%s", hex.EncodeToString(name[:16]))
}

func main() {
	var consumerId string
	var claimName string
	flag.StringVar(&consumerId, "consumer-id", "", "UUID of related StorageConsumer")
	flag.StringVar(&claimName, "claim-name", "", "Name of the StorageClassName being fulfilled")

	flag.Parse()

	fmt.Println(getStorageClassRequestName(consumerId, claimName))
}
