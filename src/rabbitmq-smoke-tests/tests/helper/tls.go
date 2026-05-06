package helper

import (
	"encoding/json"

	. "github.com/onsi/gomega"
)

const keyName = "service-key-for-tls"

func generateServiceKeyOutput(serviceName string) ServiceKey {
	CreateServiceKey(serviceName, keyName)
	defer DeleteServiceKey(serviceName, keyName)
	key := GetServiceKey(serviceName, keyName)
	return key
}

func generateTLSConfigFromHostnames(hostnames []string) string {
	type tlsConfigData struct {
		TLS []string `json:"tls"`
	}

	tlsConfig := tlsConfigData{
		TLS: hostnames,
	}

	config, err := json.Marshal(tlsConfig)
	Expect(err).NotTo(HaveOccurred())
	return string(config)
}
