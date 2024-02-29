package smoke_tests

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/pivotal-cf/cf-rabbitmq-smoke-tests-release/src/rabbitmq-smoke-tests/tests/helper"

	"github.com/cloudfoundry/cf-test-helpers/v2/config"
	"github.com/cloudfoundry/cf-test-helpers/v2/workflowhelpers"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"testing"
)

const (
	securityGroupName = "cf-rabbitmq-smoke-tests"
	quotaName         = "cf-rabbitmq-smoke-tests-quota"
)

var (
	configPath = os.Getenv("CONFIG_PATH")
	testConfig = loadTestConfig(configPath)
	logBase    = os.Getenv("SMOKE_TESTS_BASE_LOG_DIR")
	wfh        *workflowhelpers.ReproducibleTestSuiteSetup
)

func TestLifecycle(t *testing.T) {
	SynchronizedBeforeSuite(func() []byte {
		wfh = workflowhelpers.NewTestSuiteSetup(&testConfig.Config)
		wfh.Setup()

		workflowhelpers.AsUser(wfh.AdminUserContext(), 30*time.Second, func() {
			helper.CreateAndBindSecurityGroup(securityGroupName, wfh.TestSpace.OrganizationName(), wfh.TestSpace.SpaceName())
		})

		return []byte{}
	}, func([]byte) {
		if wfh == nil {
			wfh = workflowhelpers.NewTestSuiteSetup(&testConfig.Config)
			wfh.Setup()
		}
	})

	SynchronizedAfterSuite(
		func() {
			time.Sleep(5 * time.Second) // Ensure service instance deletion does not block teardown
			wfh.Teardown()
		},
		func() {
			workflowhelpers.AsUser(wfh.AdminUserContext(), 30*time.Second, func() {
				helper.DeleteSecurityGroup(securityGroupName)
			})

			time.Sleep(5 * time.Second) // Ensure service instance deletion does not block teardown
			wfh.Teardown()
		},
	)

	if len(logBase) == 0 {
		logBase = "."
	}

	g := NewWithT(t)

	filename := fmt.Sprintf("%s/smoke-test-%d.log", logBase, time.Now().UnixMilli())
	fileWriter, err := os.Create(filename)
	g.Expect(err).ToNot(HaveOccurred())
	GinkgoWriter.TeeTo(fileWriter)
	defer fileWriter.Close()

	RegisterFailHandler(Fail)
	RunSpecs(t, "Smoke Tests Suite")
}

func loadTestConfig(configPath string) TestConfig {
	if configPath == "" {
		panic(errors.New("path to config file is empty -- Did you set CONFIG_PATH?"))
	}
	configFile, err := os.Open(configPath)
	if err != nil {
		panic(fmt.Errorf("could not open config file at %s --  ERROR %w", configPath, err))
	}

	defer configFile.Close()
	var testConfig TestConfig
	err = json.NewDecoder(configFile).Decode(&testConfig)
	if err != nil {
		panic(fmt.Errorf("could not decode config json -- ERROR: %w", err))
	}

	return testConfig
}

type TestConfig struct {
	config.Config

	TestPlans       []TestPlan `json:"plans"`
	ServiceOffering string     `json:"service_offering"`
	TLSSupport      string     `json:"tls_support"`
	OAuthEnforced   bool       `json:"oauth_enforced"`
}

type TestPlan struct {
	Name string `json:"name"`
}
