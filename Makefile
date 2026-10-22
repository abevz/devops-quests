.PHONY: install up reset test integration bootstrap lab-assets
install:
	python3 -m venv .venv
	.venv/bin/python -m pip install -e '.[test]' ruff==0.17.1 build==1.3.0
	npm ci --ignore-scripts
	npm run build
bootstrap:
	.venv/bin/python scripts/prepare_assets.py
lab-assets:
	.venv/bin/python scripts/lab_assets.py
up: bootstrap
	.venv/bin/python -m devops_quests
reset:
	.venv/bin/python -m devops_quests reset
test:
	.venv/bin/python -m pytest -q
	npm test
integration:
	DQ_INTEGRATION=1 .venv/bin/python -m pytest tests/test_quests.py -q
