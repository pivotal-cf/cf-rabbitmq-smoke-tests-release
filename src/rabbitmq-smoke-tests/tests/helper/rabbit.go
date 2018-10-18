package helper

import (
	"crypto/tls"
	"fmt"
	"io/ioutil"
	"net"
	"net/http"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

func SendMessage(testAppURL, queueName, message string) {
	postReq, err := http.NewRequest(
		http.MethodPost,
		fmt.Sprintf("https://%s/queues/%s", testAppURL, queueName),
		strings.NewReader(message),
	)
	postReq.Header.Add("Content-Type", "text/plain")
	Expect(err).ToNot(HaveOccurred())
	makeAndCheckHttpRequest(postReq)
}

func ReceiveMessage(testAppURL, queueName string) string {
	getReq, err := http.NewRequest(
		http.MethodGet,
		fmt.Sprintf("https://%s/queues/%s", testAppURL, queueName),
		nil,
	)
	getReq.Header.Add("Content-Type", "text/plain")
	Expect(err).ToNot(HaveOccurred())
	msg := makeAndCheckHttpRequest(getReq)
	return strings.TrimSpace(msg)
}

func makeAndCheckHttpRequest(req *http.Request) string {
	client := &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			Dial: (&net.Dialer{
				Timeout:   30 * time.Second,
				KeepAlive: 30 * time.Second,
			}).Dial,
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		},
	}

	resp, err := client.Do(req)
	Expect(err).ToNot(HaveOccurred())
	defer resp.Body.Close()

	bodyContent, err := ioutil.ReadAll(resp.Body)
	Expect(err).ToNot(HaveOccurred())

	fmt.Fprintf(GinkgoWriter,
		"response from %s %s: %d\n------------------------------\n%s\n------------------------------\n",
		req.Method,
		req.URL.String(),
		resp.StatusCode,
		bodyContent,
	)
	Expect(resp.StatusCode).To(BeNumerically("<", 300))

	return string(bodyContent)
}
