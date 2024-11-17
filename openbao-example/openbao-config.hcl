listener "tcp" {
	address = "0.0.0.0:8200"
	tls_cert_file = "ssl/openbao.pem"
	tls_key_file = "ssl/openbao-key.pem"
}

storage "file" {
  path = "/mnt/openbao/data"
}

max_lease_ttl = "730d"
default_lease_ttl = "730d"
