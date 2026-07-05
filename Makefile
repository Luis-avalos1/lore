# lore — developer tasks (not part of the published plugin).
#
#   make test        run the dependency-free test suite (bash 3.2 + BSD/GNU)
#   make validate    claude plugin validate the manifests (needs the CLI)
#   make shellcheck  lint every shipped script (needs shellcheck)
#   make check       test + validate + shellcheck
.PHONY: test validate shellcheck check

test:
	bash tests/run.sh

validate:
	claude plugin validate . --strict
	claude plugin validate ./plugins/lore --strict

shellcheck:
	shellcheck -x --source-path=SCRIPTDIR \
	  plugins/lore/lib/common.sh \
	  plugins/lore/lib/apply-block.sh \
	  plugins/lore/hooks/check-state.sh \
	  plugins/lore/skills/refresh/scripts/recon.sh \
	  plugins/lore/skills/status/scripts/recon.sh \
	  plugins/lore/skills/review/scripts/recon.sh \
	  tests/run.sh

check: test validate shellcheck
