package helper

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/cloudfoundry/cf-test-helpers/v2/cf"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
)

const RETRY_LIMIT = 5
const COMMAND_TIMEOUT = 5 * time.Minute

// TODO: add Context to these functions, so that a cancelled test cleans up before the COMMAND_TIMEOUT

func CfWithTimeout(timeout time.Duration, args ...string) *gexec.Session {
	session := cf.Cf(args...)

	select {
	case <-session.Exited:
	case <-time.After(timeout):
		session.Kill().Wait()
	}
	return session
}

func Cf(args ...string) *gexec.Session {
	var s *gexec.Session
	for i := 0; i <= RETRY_LIMIT; i++ {
		s = CfWithTimeout(COMMAND_TIMEOUT, args...)
		if s.ExitCode() == 0 {
			return s
		}
		fmt.Printf("Retried: %d out of %d", i, RETRY_LIMIT)
		time.Sleep(5 * time.Second)
	}
	return s
}

// CfWithBufferedOutput runs cf with given args. It has a command timeout of
// COMMAND_TIMEOUT minutes, and retries failed commands up to RETRY_LIMIT. The
// output of the command is not sent to the standard output. Output of the
// command can be accessed via the returned Session.
func CfWithBufferedOutput(args ...string) (s *gexec.Session) {
	cmdOutput := &bytes.Buffer{}
	for i := 0; i <= RETRY_LIMIT; i++ {
		var err error
		s, err = gexec.Start(exec.Command("cf", args...), cmdOutput, cmdOutput)
		if err != nil {
			panic(err)
		}

		select {
		case <-s.Exited:
		case <-time.After(COMMAND_TIMEOUT):
			s.Kill().Wait()
		}
		if s.ExitCode() == 0 {
			return s
		}
		fmt.Printf("Retried: %d out of %d", i, RETRY_LIMIT)
		time.Sleep(5 * time.Second)
	}
	return s
}

func CreateSecurityGroup(securityGroupName string) {
	sgs := []struct {
		Protocol    string `json:"protocol"`
		Destination string `json:"destination"`
		Ports       string `json:"ports"`
	}{
		{"tcp", "0.0.0.0/0", "5671,5672,1883,8883,61613,61614,15672,15674"},
	}

	sgFile, err := ioutil.TempFile("", "smoke-test-security-group-")
	Expect(err).NotTo(HaveOccurred())
	defer sgFile.Close()
	defer os.Remove(sgFile.Name())

	err = json.NewEncoder(sgFile).Encode(sgs)
	Expect(err).NotTo(HaveOccurred(), `{"FailReason": "Failed to encode security groups"}`)

	Expect(Cf("create-security-group", securityGroupName, sgFile.Name())).To(gexec.Exit(0))
}

func BindSecurityGroup(securityGroupName, orgName, spaceName string) {
	Expect(Cf("bind-security-group", securityGroupName, orgName, "--space", spaceName)).To(gexec.Exit(0))
}

func DeleteSecurityGroup(securityGroupName string) {
	Expect(Cf("delete-security-group", securityGroupName, "-f")).To(gexec.Exit(0))
}

func PushAndBindApp(appName, serviceName, testAppPath string) string {
	Expect(Cf("push", "-f", filepath.Join(testAppPath, "manifest.yml"), "--no-start", "--random-route", appName)).To(gexec.Exit(0))
	Expect(Cf("bind-service", appName, serviceName)).To(gexec.Exit(0))
	Expect(Cf("start", appName)).To(gexec.Exit(0))
	return LookupAppURL(appName)
}

func LookupAppURL(appName string) string {
	appDetails := Cf("app", appName)
	Expect(appDetails).To(gexec.Exit(0))

	appDetailsOutput := string(appDetails.Buffer().Contents())
	testAppURL := findURL(appDetailsOutput)
	Expect(testAppURL).NotTo(BeEmpty())

	return testAppURL
}

func DeleteApp(appName string) {
	Expect(Cf("delete", appName, "-f", "-r")).To(gexec.Exit(0))
}

func PrintAppLogs(appName string) {
	Expect(Cf("logs", appName, "--recent")).To(gexec.Exit(0))
}

func CreateService(serviceOffering, servicePlan, serviceName, params string) {
	if params != "" {
		Expect(Cf("create-service", serviceOffering, servicePlan, serviceName, "-c", params)).To(gexec.Exit(0))
	} else {
		Expect(Cf("create-service", serviceOffering, servicePlan, serviceName)).To(gexec.Exit(0))
	}
	AwaitServiceAvailable(serviceName)
}

func UpdateService(serviceName, params string) {
	Expect(Cf("update-service", serviceName, "-c", params)).To(gexec.Exit(0))
	AwaitServiceAvailable(serviceName)
}

func UnbindService(appName, serviceName string) {
	Expect(Cf("unbind-service", appName, serviceName)).To(gexec.Exit(0))
}

func DeleteService(serviceName string) {
	Expect(Cf("delete-service", serviceName, "-f")).To(gexec.Exit(0))
	AwaitServiceDeletion(serviceName)
}

func findURL(cliOutput string) string {
	for _, line := range strings.Split(cliOutput, "\n") {
		if strings.HasPrefix(line, "routes:") {
			return strings.Fields(line)[1]
		}
	}
	return ""
}
