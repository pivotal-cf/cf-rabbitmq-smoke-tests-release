package helper

import (
	"encoding/json"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
	"regexp"
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
	// this function only works with CF CLI v7. CF CLI v8 changed the format of the service key
	session := CfWithBufferedOutput("service-key", serviceName, keyName)
	Expect(session).To(gexec.Exit(0))

	chopped := serviceKeyHeader.ReplaceAllLiteral(session.Buffer().Contents(), []byte{})

	var serviceKey ServiceKey
	Expect(json.Unmarshal(chopped, &serviceKey)).To(Succeed())

	return serviceKey
}

func CreateServiceKey(serviceName, keyName string) {
	Expect(Cf("create-service-key", serviceName, keyName)).To(gexec.Exit(0))
}

func DeleteServiceKey(serviceName, keyName string) {
	Expect(Cf("delete-service-key", "-f", serviceName, keyName)).To(gexec.Exit(0))
}
