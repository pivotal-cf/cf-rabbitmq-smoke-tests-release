# cf-rabbitmq-smoke-tests-release
Smoke tests for the CF RabbitMQ Service

## Contributing

Even though the default branch is `release`, you should push changes to `master`. [The `release` branch is the default so that bosh.io can find our releases](https://github.com/bosh-io/releases#how-does-boshio-find-my-release).

## Run tests
In order to run the tests for development:
- Change directory to `src/rabbitmq-smoke-tests`
- Copy `assets/example_config.json` and update:
  - `api` to point to Cloud Foundry
  - The `admin_user` and `admin_password`
  - The `service_offering` and `plans` names
- Run `make test` with `CONFIG_PATH` set to your config file

## Create BOSH release
```bash
$ bosh sync-blobs
$ bosh create-release #--force --tarball=cf-rabbitmq-smoke-tests-release-VERSION.tgz
```

## Notes
- Change directory to `src/rabbitmq-smoke-tests` and run `make` to list all of the available options
