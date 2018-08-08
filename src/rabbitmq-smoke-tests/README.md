# cf-rabbitmq-smoke-tests
Smoke tests for the CF RabbitMQ Service
[Multitenant](https://github.com/pivotal-cf/cf-rabbitmq-multitenant-broker-release) and
[On-Demand](https://github.com/pivotal-cf/rabbitmq-on-demand-adapter-release) offerings

## Run tests
In order to run the tests:
- Run `make deps` to update dependencies
- Copy `assets/example_config.json` and update:
  - `api` to point to Cloud Foundry
  - The `admin_user` and `admin_password`
  - The `service_offering` and `plans` names
- Run `make test` with `CONFIG_PATH` set to your config file

## Notes
- Run `make` to list all options
