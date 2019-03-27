package smoke_tests

import (
	"fmt"

	"rabbitmq-smoke-tests/tests/helper"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/pborman/uuid"
)

var _ = Describe("Smoke tests", func() {

	const appName = "rmq-smoke-tests-ruby"
	const appPath = "../assets/rabbit-example-app"

	AfterEach(func() {
		helper.PrintAppLogs(appName)
		helper.DeleteApp(appName)
	})

	smokeTestForPlan := func(planName string) func() {
		return func() {
			serviceName := fmt.Sprintf("rmq-smoke-test-instance-%s", uuid.New()[:18])
			helper.CreateService(testConfig.ServiceOffering, planName, serviceName, useTLS, testConfig.BindingWithDNS)

			defer func() {
				By("deleting the service instance")
				helper.DeleteService(serviceName)
			}()

			defer func() {
				By("unbinding the app")
				helper.UnbindService(appName, serviceName)
			}()

			By("pushing and binding an app")
			appURL := helper.PushAndBindApp(appName, serviceName, appPath)

			By("sending and receiving rabbit messages")
			queue := fmt.Sprintf("%s-queue", appName)

			helper.SendMessage(appURL, queue, "foo")
			helper.SendMessage(appURL, queue, "bar")
			Expect(helper.ReceiveMessage(appURL, queue)).To(Equal("foo"))
			Expect(helper.ReceiveMessage(appURL, queue)).To(Equal("bar"))
		}
	}

	for _, plan := range testConfig.TestPlans {
		It(fmt.Sprintf("pushes an app, sends, and reads a message from RabbitMQ: plan '%s'", plan.Name),
			smokeTestForPlan(plan.Name))
	}
})
