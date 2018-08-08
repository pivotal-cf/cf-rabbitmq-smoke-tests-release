package smoke_tests

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"rabbitmq-smoke-tests/tests/helper"

	"github.com/cloudfoundry-incubator/cf-test-helpers/config"
	"github.com/cloudfoundry-incubator/cf-test-helpers/workflowhelpers"
	. "github.com/onsi/ginkgo"
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
	useTLS     = len(testConfig.TLSSupport) > 0 && testConfig.TLSSupport != "disabled"
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
	})

	SynchronizedAfterSuite(func() {
	}, func() {
		workflowhelpers.AsUser(wfh.AdminUserContext(), 30*time.Second, func() {
			helper.DeleteSecurityGroup(securityGroupName)
		})

		wfh.Teardown()
	})

	RegisterFailHandler(Fail)
	RunSpecs(t, "Smoke Tests Suite")
}

func loadTestConfig(configPath string) TestConfig {
	if configPath == "" {
		panic(fmt.Errorf("Path to config file is empty -- Did you set CONFIG_PATH?"))
	}
	configFile, err := os.Open(configPath)
	if err != nil {
		panic(fmt.Errorf("Could not open config file at %s --  ERROR %s", configPath, err.Error()))
	}

	defer configFile.Close()
	var testConfig TestConfig
	err = json.NewDecoder(configFile).Decode(&testConfig)
	if err != nil {
		panic(fmt.Errorf("Could not decode config json -- ERROR: %s", err.Error()))
	}

	return testConfig
}

type TestConfig struct {
	config.Config

	TestPlans       []TestPlan `json:"plans"`
	ServiceOffering string     `json:"service_offering"`
	TLSSupport      string     `json:"tls_support"`
}

type TestPlan struct {
	Name string `json:"name"`
}
