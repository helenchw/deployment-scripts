#!/bin/bash

# Pre-requisite: binaries 'cfssl' and 'cfssljson' are available in the current directory
# - Download the 'cfssl' binary for amd64 architecture: https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64. Copy it to /usr/local/bin, add executable permission, and create a symbolic link with name 'cfssl'.
# - Do the same for 'cfssljson' binary at https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64. Rename to 'cfssljson'.

gen_ca() {

cat <<EOF | ./cfssl gencert -initca - | ./cfssljson -bare ssl/ca
{
  "CN": "openbao",
  "key": {
    "algo": "rsa",
    "size": 2048
  }
}
EOF

}

gen_cert() {
cat <<EOF | ./cfssl gencert -ca ssl/ca.pem -ca-key ssl/ca-key.pem - | ./cfssljson -bare ssl/openbao
{
  "hosts": [
    "openbao",
    "127.0.0.1"
  ],
  "CN": "openbao",
  "key": {
    "algo": "ecdsa",
    "size": 256
  }
}
EOF

}

if [ ! -f ./cfssl ] || [ ! -f ./cfssljson ]; then
  echo "Please check the script comments and download two required binaries (cfssl and cfssljson) before script run!"
  exit 1
fi

# create the directory for keys and certifications
mkdir -p ssl
# generate keys and certifications
gen_ca
gen_cert
# update the permission of certificates and keys 
chmod 444 ssl/*
