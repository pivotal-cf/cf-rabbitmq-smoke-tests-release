package helper

import (
	"encoding/json"

	. "github.com/onsi/gomega"
)

const keyName = "service-key-for-tls"

func TLSConfigUsingIPs(serviceName string) string {
	key := generateServiceKeyOutput(serviceName)
	Expect(key.Hostnames).ToNot(HaveLen(0))

	return generateTLSConfigFromHostnames(key.Hostnames)
}

func generateServiceKeyOutput(serviceName string) ServiceKey {
	CreateServiceKey(serviceName, keyName)
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
