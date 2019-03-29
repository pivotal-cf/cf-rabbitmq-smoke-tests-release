package helper

import (
	"encoding/json"
	"regexp"

	. "github.com/onsi/gomega"
)

const keyName = "service-key-for-tls"

var serviceKeyHeader = regexp.MustCompile(`^\s*Getting key .*`)

func TLSConfigUsingIPs(serviceName string) string {
	key := generateServiceKeyOutput(serviceName)
	return readTLSConfigFromServiceKey(key)
}

func generateServiceKeyOutput(serviceName string) []byte {
	CreateServiceKey(serviceName, keyName)
	key := GetServiceKey(serviceName, keyName)
	DeleteServiceKey(serviceName, keyName)
	return key
}

func readTLSConfigFromServiceKey(serviceKey []byte) string {
	chopped := serviceKeyHeader.ReplaceAllLiteral(serviceKey, []byte{})
	hostnames := parseServiceKey(chopped)
	return generateTLSConfigFromHostnames(hostnames)
}

func parseServiceKey(chopped []byte) []string {
	var serviceKeyData struct {
		Hostnames []string `json:"hostnames"`
	}
	err := json.Unmarshal(chopped, &serviceKeyData)
	Expect(err).NotTo(HaveOccurred())
	Expect(serviceKeyData.Hostnames).ToNot(HaveLen(0))
	return serviceKeyData.Hostnames
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
