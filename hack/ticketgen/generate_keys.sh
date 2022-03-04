 openssl genrsa -out key.pem 4096
 openssl rsa -in key.pem -out pubkey.pem -outform PEM -pubout
