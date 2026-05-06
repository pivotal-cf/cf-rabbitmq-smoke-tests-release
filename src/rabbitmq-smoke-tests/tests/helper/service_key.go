package helper

import (
	"encoding/json"
	"regexp"

	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
)

var serviceKeyHeader = regexp.MustCompile(`^\s*Getting key .*`)

type ServiceKey struct {
	DashboardUrl string                    `json:"dashboard_url"`
	Username     string                    `json:"username"`
	Password     string                    `json:"password"`
	Hostname     string                    `json:"hostname"`
	Hostnames    []string                  `json:"hostnames"`
	HttpApiUri   string                    `json:"http_api_uri"`
	HttpApiUris  []string                  `json:"http_api_uris"`
	URI          string                    `json:"uri"`
	URIs         []string                  `json:"uris"`
	VHOST        string                    `json:"vhost"`
	SSL          bool                      `json:"ssl"`
	Protocols    map[string]map[string]any `json:"protocols"`
}

func GetServiceKey(serviceName, keyName string) ServiceKey {
	// this function works with both CF CLI v7 and v8. CF CLI v8 wraps the service key in a "credentials" object
	session := CfWithBufferedOutput("service-key", serviceName, keyName)
	Expect(session).To(gexec.Exit(0))

	chopped := serviceKeyHeader.ReplaceAllLiteral(session.Buffer().Contents(), []byte{})

	// First try to parse as CF CLI v7 format (direct ServiceKey)
	var serviceKey ServiceKey
	err := json.Unmarshal(chopped, &serviceKey)
	if err == nil && serviceKey.DashboardUrl != "" {
		return serviceKey
	}

	// If that fails or DashboardUrl is empty, try CF CLI v8 format (wrapped in credentials)
	var v8Response struct {
		Credentials ServiceKey `json:"credentials"`
	}
	err = json.Unmarshal(chopped, &v8Response)
	if err == nil {
		return v8Response.Credentials
	}

	// If both fail, fall back to the original parsing and let it fail with the original error
	Expect(json.Unmarshal(chopped, &serviceKey)).To(Succeed())
	return serviceKey
}

func CreateServiceKey(serviceName, keyName string) {
	Expect(Cf("create-service-key", serviceName, keyName)).To(gexec.Exit(0))
}

func DeleteServiceKey(serviceName, keyName string) {
	Expect(Cf("delete-service-key", "-f", serviceName, keyName)).To(gexec.Exit(0))
}
