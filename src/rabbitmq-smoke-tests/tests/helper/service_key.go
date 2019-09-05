package helper

import (
	"encoding/json"
	"regexp"

	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
)

var serviceKeyHeader = regexp.MustCompile(`^\s*Getting key .*`)

type ServiceKey struct {
	DashboardUrl string                            `json:"dashboard_url"`
	Username     string                            `json:"username"`
	Password     string                            `json:"password"`
	Hostname     string                            `json:"hostname"`
	Hostnames    []string                          `json:"hostnames"`
	HttpApiUri   string                            `json:"http_api_uri"`
	HttpApiUris  []string                          `json:"http_api_uris"`
	URI          string                            `json:"uri"`
	URIs         []string                          `json:"uris"`
	VHOST        string                            `json:"vhost"`
	SSL          bool                              `json:"ssl"`
	Protocols    map[string]map[string]interface{} `json:"protocols"`
}

func GetServiceKey(serviceName, keyName string) ServiceKey {
	session := Cf("service-key", serviceName, keyName)
	Expect(session).To(gexec.Exit(0))

	chopped := serviceKeyHeader.ReplaceAllLiteral(session.Buffer().Contents(), []byte{})

	var serviceKey ServiceKey
	err := json.Unmarshal(chopped, &serviceKey)
	Expect(err).NotTo(HaveOccurred())

	return serviceKey
}

func CreateServiceKey(serviceName, keyName string) {
	Expect(Cf("create-service-key", serviceName, keyName)).To(gexec.Exit(0))
}

func DeleteServiceKey(serviceName, keyName string) {
	Expect(Cf("delete-service-key", "-f", serviceName, keyName)).To(gexec.Exit(0))
}
