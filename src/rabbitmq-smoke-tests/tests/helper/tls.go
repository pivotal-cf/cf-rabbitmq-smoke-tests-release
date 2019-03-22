package helper

import (
	"encoding/json"
	"regexp"

	. "github.com/onsi/gomega"
)

const keyName = "service-key-for-tls"

var serviceKeyHeader = regexp.MustCompile(`^\s*Getting key .*`)

func EnableTLSForODB(serviceName string, useHostnames bool) {
	var tlsConfig string
	if useHostnames {
		CreateServiceKey(serviceName, keyName)
		key := GetServiceKey(serviceName, keyName)
		DeleteServiceKey(serviceName, keyName)

		tlsConfig = readTLSConfigFromServiceKey(key)
	} else {
		tlsConfig = generateTLSConfigBoolean()
	}

	UpdateService(serviceName, tlsConfig)
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

func generateTLSConfigBoolean() string {
	type tlsConfigData struct {
		TLS bool `json:"tls"`
	}

	tlsConfig := tlsConfigData{
		TLS: true,
	}

	config, err := json.Marshal(tlsConfig)
	Expect(err).NotTo(HaveOccurred())
	return string(config)
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
