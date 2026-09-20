.PHONY: check offline-pkg

check:
	bash -n bin/mcpctl scripts/*.sh tunnel/*.sh tunnel/providers/*.sh

offline-pkg:
	bash ./scripts/build-offline.sh
