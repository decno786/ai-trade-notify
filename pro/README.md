# AI Trade Notify PRO: stocks + crypto, 5-day predictions, Telegram

Files (settings are at the top of each one):

| File | What it does | Run |
|---|---|---|
| `trading_bot.py` | Indicators, score -100..+100, backtest, trade plan, best Doha hours | `python trading_bot.py AAPL BTC-USD` |
| `scanner_alerts.py` | Scans S&P 500 + top 10 crypto, filters, sends top 3 to Telegram | `python scanner_alerts.py` |
| `ml_model.py` | Machine learning with an honest exam and a "no edge" check | `python ml_model.py train` (weekly), `python ml_model.py scan` (daily) |
| `api_server.py` | Web dashboard + `/api/signals` for the Android app | `python api_server.py` |
| `android-webview/` | Android app (Kotlin WebView) that shows the dashboard | see below |

> Signals are probabilities, not guarantees. Realistic accuracy is 55-60%; claims of 80%+ usually mean a bug.
> Always use the stop-loss, risk at most 1-2% per trade, and paper-trade for at least a month first. Not financial advice.

---

## 1. Install (Windows, once)
1. Install Python from python.org and tick **Add Python to PATH**.
2. Open **Command Prompt** in this folder (in File Explorer, click the address bar, type `cmd`, press Enter).
3. Run: `pip install -r requirements.txt`

## 2. Telegram (optional, 2 minutes)
1. In Telegram open **@BotFather** → send `/newbot` → choose a name → copy the **token**.
2. Send any message (e.g. "hi") to your new bot.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser and copy the number after `"chat":{"id":`.
4. Put both at the top of `scanner_alerts.py` (`TELEGRAM_TOKEN`, `TELEGRAM_CHAT_ID`), or set them as environment variables.

## 3. First run
```
python trading_bot.py          # quick check on a few tickers
python ml_model.py train       # 10-20 min: downloads 5 years for ~510 assets, runs the exam, saves model.joblib
python ml_model.py scan        # today's top 3 → Telegram
```
Read the `train` output: if it says **NO EDGE**, the model didn't beat guessing - don't trade on it.

## 4. Android app (Android Studio)
1. Install **Android Studio** (free) → **New Project** → **Empty Views Activity** → Language **Kotlin**,
   package name `com.aitradenotify.web`, Minimum SDK **API 24**.
2. Replace the generated files with the ones in `android-webview/` (same paths: `app/build.gradle.kts`,
   `app/src/main/AndroidManifest.xml`, `MainActivity.kt`, `res/layout/activity_main.xml`, `res/values/*`, `res/drawable/ic_launcher.xml`).
   Click **Sync Now** when Android Studio asks.
3. On your PC run `python api_server.py` and find your PC's address: Command Prompt → `ipconfig` → **IPv4 Address** (e.g. 192.168.1.10).
4. Build the APK: **Build → Build App Bundle(s) / APK(s) → Build APK(s)** → **locate** →
   `app/build/outputs/apk/debug/app-debug.apk`. Copy it to your phone and open it (allow "install unknown apps").
5. On first launch the app asks for the server address: type `http://192.168.1.10:5000` (your IPv4). Phone and PC must be on the same Wi-Fi.
   Tap the error message or long-press the page to change it later. Pull down to refresh.

## 5. Use it away from home: ~$5/month cloud server with HTTPS
1. Rent a small Linux server (Ubuntu 24.04, 1-2 GB RAM): e.g. Hetzner, DigitalOcean, Vultr or AWS Lightsail.
2. Buy or use a domain and point an **A record** (e.g. `signals.yourname.com`) to the server's IP.
3. On the server:
   ```
   sudo apt update && sudo apt install -y python3-pip python3-venv caddy
   git clone <your repo> && cd ai-trade-notify/pro
   python3 -m venv venv && . venv/bin/activate && pip install -r requirements.txt
   python ml_model.py train
   ```
4. Keep the server running with systemd (`/etc/systemd/system/signals.service`):
   ```
   [Service]
   WorkingDirectory=/root/ai-trade-notify/pro
   ExecStart=/root/ai-trade-notify/pro/venv/bin/waitress-serve --host=127.0.0.1 --port=5000 api_server:app
   Environment=TELEGRAM_TOKEN=xxx TELEGRAM_CHAT_ID=yyy
   Restart=always
   [Install]
   WantedBy=multi-user.target
   ```
   `sudo systemctl enable --now signals`
5. Free automatic HTTPS with Caddy (`/etc/caddy/Caddyfile`):
   ```
   signals.yourname.com {
       reverse_proxy 127.0.0.1:5000
   }
   ```
   `sudo systemctl reload caddy` → your app address becomes `https://signals.yourname.com`.

## 6. Scheduling (scan daily 09:00 Doha, train weekly)

**Windows Task Scheduler** (PC clock set to Qatar time). Open Command Prompt **in this folder** and run:
```
schtasks /Create /TN "AI Trade Scan"  /TR "cmd /c cd /d %CD% && python ml_model.py scan"  /SC DAILY  /ST 09:00
schtasks /Create /TN "AI Trade Train" /TR "cmd /c cd /d %CD% && python ml_model.py train" /SC WEEKLY /D SUN /ST 08:00
```
The PC must be on at those times (Task Scheduler → task → Properties → Conditions → *Wake the computer to run this task*).

**Linux cron** (`crontab -e`):
```
CRON_TZ=Asia/Qatar
0 9 * * *  cd /root/ai-trade-notify/pro && venv/bin/python ml_model.py scan  >> scan.log 2>&1
0 8 * * 0  cd /root/ai-trade-notify/pro && venv/bin/python ml_model.py train >> train.log 2>&1
```

**Free, no PC needed:** the GitHub workflow `.github/workflows/daily-scan.yml` in this repository already runs the
scan every day at 09:00 Doha and retrains weekly, then updates your AI Trade Notify app and Telegram.

## Future ideas (ask before building)
- Qatar Exchange stocks: add `.QA` tickers to `EXTRA` in `scanner_alerts.py` (e.g. `QNBK.QA`).
- A Telegram `/scan` command for on-demand signals.
- A paper-trading tracker that records every signal and its real outcome.
