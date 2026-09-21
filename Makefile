.PHONY: check offline-pkg

check:
	bash -n bin/mcpctl scripts/*.sh tunnel/*.sh tunnel/providers/*.sh tests/*.sh
	bash tests/test-instance-env.sh

offline-pkg:
	bash ./scripts/build-offline.sh
