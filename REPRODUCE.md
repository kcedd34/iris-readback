# Reproduce it

How to run the test battery, how to reproduce the evaluation and the ablation (free in replay, paid live), and how to connect an MCP client from your machine. The commands below are meant to be run from the root of the repository, in bash, with the Early Access image already loaded (see [Load and rename the image](README.md#load-and-rename-the-image)).

## 1. Prerequisites of the test battery

`tests/e2e/triage_check.sh` runs every check, 31 steps, and stops at the first failure. It needs:

- Docker with the compose plugin, and the image `irishealth-community:2026.3.0AI.154.0`;
- Python 3 with `pytest` (`python3 -m pip install pytest`; nothing else, the rest is the standard library);
- Node.js 20 or later and npm (the interface checks run `npm ci` in `frontend/`);
- the Chromium of Playwright: the interface checks install it themselves (`npx playwright install chromium`, about 150 MB);
- network, once: the IPM client, the interface packages, the MCP Inspector package and the local embedding model are downloaded.

The battery takes about 35 minutes on a laptop with a warm Docker cache. It runs in a stack of its own, with its own compose project (`readback-battery`), its own images and the ports 8180 to 8183, so a stack you started yourself is never stopped, recreated or emptied. If those names or ports clash with something else, set `READBACK_TEST_PROJECT` and `READBACK_TEST_PORT_BASE` (four consecutive ports from the base are used).

```
python3 -m pip install pytest
tests/e2e/triage_check.sh; echo EXIT=$?
```

A passing run ends with `EXIT=0`. The battery needs no provider key and never reads one.

## 2. A separate stack

To run the product next to another copy, give it a compose project name and its own ports. Compose names the project after the folder, so two clones in folders of the same name would share containers and volumes without this:

```
export COMPOSE_PROJECT_NAME=readback-second
export READBACK_UI_PORT=8280 READBACK_PORTAL_PORT=52890 READBACK_HL7_PORT=5101 READBACK_MCP_PORT=8865
cp .env.example .env     # set READBACK_DEMO_PASSWORD; leave OPENAI_API_KEY empty for replay
src/ops/preflight.sh && docker compose up -d --build && src/ops/verify.sh
```

The panel is then at http://127.0.0.1:8280. The variables are the same ones `docker-compose.yml` reads; the image names can also be changed (`READBACK_IMAGE`, `READBACK_UI_IMAGE`). To remove that stack and its data: `docker compose down -v` with the same variables set.

## 3. Reproduce the evaluation

The evaluation runs the whole product over the 240 subject cases of `data/eval/dataset.jsonl` (446 messages with the earlier results of each patient) and builds `data/eval/report.md` and `report.json`.

**In replay: free, no key, about a minute per model.** The recorded answers of the real run are replayed through the product. The run needs a fresh stack with the key empty; it refuses to run otherwise.

```
docker compose down -v && docker compose up -d && src/ops/verify.sh
src/ops/evaluate.sh replay
git status --short data/eval
```

`replay` with no argument replays both shipped sets, `gpt-5.4` and `gpt-5.4-mini`, one after the other, and rebuilds the full report. The report comes out identical to the shipped one, so `git status` shows nothing changed. `src/ops/evaluate.sh replay gpt-5.4-mini` replays one set only; the full report is not touched, and that set's report is written to `.local/eval/report-gpt-5.4-mini/`, which the command prints.

**Live: paid, needs a key.** Put the key in `.env` as `OPENAI_API_KEY=...` (the file is not committed, and the key is read from the environment only, never printed or written), then start a fresh stack and run:

```
docker compose down -v && docker compose up -d && src/ops/verify.sh
src/ops/evaluate.sh live gpt-5.4
```

Without `--yes` nothing is sent: the command prints the number of messages and the estimated cost and stops. The estimate is the price table (`data/config/price-table.json`, dated) times the tokens per call. The measured cost of the shipped runs is 9.73 USD per thousand results for `gpt-5.4` and 2.84 for `gpt-5.4-mini`, so a full run of the 446 messages costs about 4.30 USD and about 1.30 USD. To try the paid path for a few cents first, add `--pilot 5`: it sends 14 messages (about five subject cases, one per category, with the earlier results of their patients), estimates about 0.05 USD for `gpt-5.4-mini`, and records nothing; the rows go to `.local/eval/` and the files under `data/` stay as shipped.

```
src/ops/evaluate.sh live gpt-5.4-mini --pilot 5 --yes
```

Add `--yes` to run the full set:

```
src/ops/evaluate.sh live gpt-5.4 --yes
src/ops/evaluate.sh live gpt-5.4-mini --yes     # on a fresh stack again
```

A live run writes into tracked files, the recordings in `data/replay/recordings.jsonl` and the report in `data/eval/`; `git checkout data` restores the shipped ones. A live run that stopped can be finished with `--resume`. The run stops by itself at the hourly cost ceiling it sets (6 USD, `EVAL_HOURLY_COST` changes it).

## 4. Reproduce the ablation

The ablation replays the recorded answers through five arrangements of the layers and writes `data/eval/ablation.json`.

**In replay: free, a few seconds, no stack needed.**

```
ABLATION_DATE=2026-11-03 PYTHONPATH=src/python python3 -m readback.evaluation.ablation --out /tmp/ablation.json
cmp /tmp/ablation.json data/eval/ablation.json && echo identical
```

The file carries the day it was measured, which is why `ABLATION_DATE` pins it (the date inside the shipped file); without it the output differs from the shipped file in that one line only. The arrangement with the full product is checked against the confusion matrices of the report on every run.

**Live: paid.** The arrangements without the rule's verdict use a separate run per model, in which the change tool gives the agent the earlier values and the variation but not the verdict or the limit (`--variant no-verdict`). It sends the 420 messages of the dataset only, on a fresh stack with the key in `.env`:

```
docker compose down -v && docker compose up -d && src/ops/verify.sh
src/ops/evaluate.sh live gpt-5.4 --variant no-verdict
```

That prints the estimate and stops: about 5.24 USD for `gpt-5.4` and about 1.60 USD for `gpt-5.4-mini` (the prices dated in the table). Add `--yes` to run it; the answers are recorded into `data/eval/ablation-no-verdict.jsonl`, and the ablation is rebuilt with the replay command above, without `ABLATION_DATE`. This variant never rebuilds the report.

## 5. Connect an MCP client from your machine

The product's read-only MCP server is reached through the platform's gateway, `iris-mcp-server`, which the image ships. It listens inside the container; compose publishes its port on the loopback of your machine only (`127.0.0.1:8765`, or `READBACK_MCP_PORT`), and the public proxy does not route it. With the stack running and your demonstration password in `READBACK_DEMO_PASSWORD`:

```
export READBACK_DEMO_PASSWORD='<the password you set in .env>'
docker compose exec -T iris sh -c 'cat > /tmp/mcp.toml' <<EOF
[[iris]]
name = "readback"
[iris.server]
host = "127.0.0.1"
port = 1972
username = "observer"
password = "$READBACK_DEMO_PASSWORD"
[[iris.endpoints]]
path = "/readback/mcp"
EOF
docker compose exec -d iris sh -c '/usr/irissys/bin/iris-mcp-server -c /tmp/mcp.toml -t http://0.0.0.0:8000 run > /tmp/mcp.log 2>&1'
sleep 8
```

The second command starts the gateway in the background of the container (`docker compose exec -T iris pkill iris-mcp-server` stops it). Then, from your machine, with the MCP Inspector in command-line mode (the client verified for this project):

```
AUTH=$(printf 'observer:%s' "$READBACK_DEMO_PASSWORD" | base64 -w0)
npx -y @modelcontextprotocol/inspector@2.13.0 --cli http://127.0.0.1:8765/mcp --transport http --header "Authorization: Basic $AUTH" --method tools/list
```

The four tools are listed, `readback_mcp_list_pending_criticals`, `readback_mcp_explain_decision`, `readback_mcp_read_evaluation` and `readback_mcp_read_ablation`, and no tool confirms a read-back. Any client that speaks the streamable HTTP transport connects to `http://127.0.0.1:8765/mcp` with the same `Authorization` header. A caller with no credentials, or an account without the `Readback_MCP` resource, is listed no tool.
