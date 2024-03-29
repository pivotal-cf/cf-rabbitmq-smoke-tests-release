package smoke_tests

import (
	"crypto/tls"
	"fmt"
	"net/http"
	"time"

	"github.com/pivotal-cf/cf-rabbitmq-smoke-tests-release/src/rabbitmq-smoke-tests/tests/helper"

	"github.com/cloudfoundry/cf-test-helpers/v2/workflowhelpers"
	"github.com/google/uuid"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Smoke tests", func() {

	const appPath = "../assets/rabbit-example-app"

	smokeTestForPlan := func(planName string, createServiceWithTLS bool) func() {
		return func() {
			workflowhelpers.AsUser(wfh.RegularUserContext(), time.Hour, func() {
				serviceName := fmt.Sprintf("rmq-smoke-test-instance-%s", uuid.NewString()[:13])
				serviceKeyName := fmt.Sprintf("%s-key", serviceName)
				appName := fmt.Sprintf("rmq-smoke-tests-ruby-%s", uuid.NewString()[:13])

				if testConfig.ServiceOffering == "p.rabbitmq" {
					By("creating the service instance with TLS enabled")
					tlsString := fmt.Sprintf(`{"tls": %v}`, createServiceWithTLS)
					helper.CreateService(testConfig.ServiceOffering, planName, serviceName, tlsString)
				} else {
					By("creating the service instance")
					helper.CreateService(testConfig.ServiceOffering, planName, serviceName, "")
				}

				helper.CreateServiceKey(serviceName, serviceKeyName)

				defer func() {
					By("deleting the service key")
					helper.DeleteServiceKey(serviceName, serviceKeyName)
					By("deleting the service instance")
					helper.DeleteService(serviceName)
					helper.PrintAppLogs(appName)
					By("deleting the app")
					helper.DeleteApp(appName)
				}()

				defer func() {
					By("unbinding the app")
					helper.UnbindService(appName, serviceName)
				}()

				By("pushing and binding an app")
				appURL := helper.PushAndBindApp(appName, serviceName, appPath)

				// skip publishing and consuming msgs because additional setup is required when oauth is enforced
				if !testConfig.OAuthEnforced {
					By("sending and receiving rabbit messages")
					queue := fmt.Sprintf("%s-queue", appName)

					helper.SendMessage(appURL, queue, "foo")
					helper.SendMessage(appURL, queue, "bar")
					Expect(helper.ReceiveMessage(appURL, queue)).To(Equal("foo"))
					Expect(helper.ReceiveMessage(appURL, queue)).To(Equal("bar"))
				}

				By("accessing the management dashboard")
				serviceKey := helper.GetServiceKey(serviceName, serviceKeyName)

				client := http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
				resp, err := client.Get(serviceKey.DashboardUrl)
				Expect(err).NotTo(HaveOccurred())

				defer resp.Body.Close()
				Expect(resp.StatusCode).To(Equal(http.StatusOK))
			})
		}
	}

	switch testConfig.TLSSupport {
	case "disabled":
		for _, plan := range testConfig.TestPlans {
			It(fmt.Sprintf("pushes an app, sends, and reads a message from RabbitMQ: plan '%s'", plan.Name),
				smokeTestForPlan(plan.Name, false))
		}
	case "optional":
		for _, plan := range testConfig.TestPlans {
			It(fmt.Sprintf("pushes an app, sends, and reads a message from RabbitMQ: plan '%s'", plan.Name),
				smokeTestForPlan(plan.Name, false))
			It(fmt.Sprintf("pushes an app, sends, and reads a message from RabbitMQ over TLS: plan '%s'", plan.Name),
				smokeTestForPlan(plan.Name, true))
		}
	case "enforced":
		for _, plan := range testConfig.TestPlans {
			It(fmt.Sprintf("pushes an app, sends, and reads a message from RabbitMQ over TLS: plan '%s'", plan.Name),
				smokeTestForPlan(plan.Name, true))
		}
	default:
		for _, plan := range testConfig.TestPlans {
			It(fmt.Sprintf("pushes an app, sends, and reads a message from RabbitMQ: plan '%s'", plan.Name),
				smokeTestForPlan(plan.Name, false))
		}
	}
})
