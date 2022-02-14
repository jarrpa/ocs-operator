package main

import (
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"flag"
	"fmt"
	"os"
	"strings"
)

// TODO: Ticket struct??
func main() {
	keyfileStr := flag.String("keyfile", "", "path to private key file")
	ticketfileStr := flag.String("ticket", "onboarding_ticket.txt", "path to onboarding ticket file")
	flag.Parse()
	if *keyfileStr == "" {
		print("ERROR: '-keyfile' is a required argument\n")
		flag.Usage()
		os.Exit(1)
	}

	fmt.Printf("Reading key from: %s\n", *keyfileStr)
	keyfile, err := os.ReadFile(*keyfileStr)
	if err != nil {
		panic(err)
	}
	pemBlock, _ := pem.Decode(keyfile)
	privKey, err := x509.ParsePKCS1PrivateKey(pemBlock.Bytes)
	if err != nil {
		panic(err)
	}

	fmt.Printf("Reading ticket from: %s\n", *ticketfileStr)
	ticket_data, err := os.ReadFile(*ticketfileStr)
	if err != nil {
		panic(err)
	}
	ticket_arr := strings.Split(string(ticket_data), ".")

	payload, err := base64.StdEncoding.DecodeString(ticket_arr[0])
	if err != nil {
		panic(err)
	}
	sig, err := base64.StdEncoding.DecodeString(ticket_arr[1])
	if err != nil {
		panic(err)
	}

	decoded, err := privKey.Decrypt(nil, sig, nil)
	if err != nil {
		panic(err)
	}

	fmt.Printf("TICKET: %s\n", string(ticket_data))
	fmt.Printf("PAYLOAD: %s\n", string(payload))
	fmt.Printf("DECODED: %s\n", string(decoded))

	if string(payload) != string(decoded) {
		println("INVALID: Could not verify payload with attached signature")
		os.Exit(1)
	}

	println("Successfully validated data")
	os.Exit(0)
}
