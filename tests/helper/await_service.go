package helper

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
)

const (
	FiveSecondTimeout   time.Duration = time.Second * 5
	ThirtySecondTimeout time.Duration = time.Second * 30
	FiveMinuteTimeout   time.Duration = time.Minute * 5
	TenMinuteTimeout    time.Duration = time.Minute * 10
	ThirtyMinuteTimeout time.Duration = time.Minute * 30
)

var succeededMatcher = regexp.MustCompile(`(?im)^\s*status\s*:\s+(create|update)\s+succeeded\s*$`)

// Keeps polling `cf service <service-name>` until service is created or updated.  For
// on-demand offerings the operation of creating or updating a service instance is
// async, which means that cf-cli immediately return `exit 0` while the
// operation is been handled in the background by On-Demand broker.
// This should be fast for multitenant offering, given that it's a sync operation.
func AwaitServiceAvailable(serviceName string) {
	Eventually(func() bool {
		session := Cf("service", serviceName)
		Eventually(session, FiveMinuteTimeout).Should(gexec.Exit(0))

		contents := session.Buffer().Contents()
		if succeededMatcher.Match(contents) {
			return true
		}

		if bytes.Contains(contents, []byte("failed")) {
			Fail("cf operation failed:\n" + string(contents))
		}

		time.Sleep(FiveSecondTimeout)
		return false
	}, ThirtyMinuteTimeout).Should(BeTrue())
}

// Keeps polling `cf services` until service is no longer found in the services
// list.  For On-Demand offerings this operation is async and might take longer.
func AwaitServiceDeletion(serviceName string) {
	Eventually(func() bool {
		session := Cf("services")
		Eventually(session, TenMinuteTimeout).Should(gexec.Exit(0))

		contents := session.Buffer().Contents()
		if !bytes.Contains(contents, []byte(serviceName)) {
			return true
		}

		lines := strings.Split(string(contents), "\n")
		for _, line := range lines {
			if strings.Contains(line, serviceName) && strings.Contains(line, "failed") {
				Fail(fmt.Sprintf("cf operation on service instance '%s' failed:\n"+string(contents), serviceName))
			}
		}

		time.Sleep(FiveSecondTimeout)
		return false
	}, ThirtyMinuteTimeout).Should(BeTrue())
}
