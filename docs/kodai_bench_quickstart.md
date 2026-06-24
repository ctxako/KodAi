# KodAi Inference Bench — Quickstart

> Run on-device AI benchmarks from your MacBook Air M4 and view live results in the dashboard.

---

## Step 1: Build

From the `KodaiCore` directory:

```bash
cd ~/kodai/KodaiCore

# Build all three bench targets
swift build --target KodaiBenchMac --target KodaiBenchServer -c release
```

---

## Step 2: Run the Batch Bench

Runs the standard 5-prompt set through Apple Foundation Models and uploads results.

```bash
swift run kodai-bench-mac \
  --experiment-id mac-baseline-001 \
  --endpoint https://bench-api.ctxa.ltd \
  --token kodai-kodi-22
```

Drop the `--endpoint` and `--token` flags to run locally without uploading.

---

## Step 3: Start the Live Server

Lets the dashboard run prompts in real time through the model on your Mac.

```bash
swift run kodai-bench-server
```

You should see:

```
bench-server: Apple Foundation Models live runner
bench-server: POST http://localhost:8788/run  {"prompt":"..."}
bench-server: listening on http://localhost:8788
```

Leave this running in its own terminal tab.

---

## Step 4: Serve the Dashboard

In a second terminal tab:

```bash
python3 -m http.server 8787 -d ~/CTXA.LLC/ctxa-site
```

---

## Step 5: Open the Dashboard

Open in your browser:

```
http://localhost:8787/lab/kodai/bench/
```

It will ask for your bench token on first visit:

```
kodai-kodi-22
```

---

## Step 6: Explore

### Historical Data

- Use the **Experiment** dropdown to pick an experiment
- Switch between **All / macOS / iOS** tabs to filter by platform
- Hover any summary card to see what that metric means
- Scroll to **"What am I looking at?"** for a glossary of terms

### Live Run

- Scroll to the **Live Run** section
- Confirm the green dot says **"Server connected"**
- Type a prompt in the text area
- Hit **Run**
- Watch the response stream in with live gauges for tok/s, TTFT, memory, and thermal state

---

## Stopping

```bash
# Stop the live server (Ctrl+C in its terminal tab)
# Stop the dashboard server (Ctrl+C in its terminal tab)
```
