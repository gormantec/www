# www

## Run test harness locally

Use the local script to serve this directory and run the Snack harness from a single codebase:

```bash
cd /home/craig/code/www
./scripts/run-test-harness-local.sh
```

Default URL:

```text
http://127.0.0.1:8788/test/test_snack.html
```

Optional overrides:

```bash
TEST_HARNESS_HOST=0.0.0.0 TEST_HARNESS_PORT=8791 ./scripts/run-test-harness-local.sh
```