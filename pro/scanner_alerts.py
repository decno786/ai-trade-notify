"""
scanner_alerts.py - automatic market search + Telegram alerts
=============================================================

Every run it:
  1. Builds the universe: all S&P 500 stocks (from Wikipedia) + top 10 cryptos.
  2. Downloads 2 years of daily prices for all of them in one go.
  3. Skips anything trading less than $20M per day (hard to buy/sell cleanly).
  4. Scores each asset with trading_bot.py and backtests it.
  5. Keeps only BUY/SELL signals whose past accuracy is >= 55% with >= 20 examples.
  6. Ranks them by |score| x accuracy, adds best Doha hours for the top 3,
     and sends them to Telegram (or "no trade today").

Run:   python scanner_alerts.py

Telegram setup (2 minutes):
  1. In Telegram, open @BotFather, send /newbot, follow the steps -> you get a TOKEN.
  2. Send any message to your new bot, then open
     https://api.telegram.org/bot<TOKEN>/getUpdates  and copy "chat":{"id": ...}
  3. Put both below, or set environment variables TELEGRAM_TOKEN / TELEGRAM_CHAT_ID.
Without them the message is just printed.
"""
import json
import os
import sys
import time
from io import StringIO

import pandas as pd

import trading_bot as tb

# ============================== SETTINGS ==============================
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")      # from @BotFather
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")  # your chat id
CRYPTO = ["BTC-USD", "ETH-USD", "BNB-USD", "SOL-USD", "XRP-USD",
          "ADA-USD", "DOGE-USD", "AVAX-USD", "LINK-USD", "DOT-USD"]
EXTRA = []                     # add your own tickers here, e.g. ["QNBK.QA"]
MIN_DOLLAR_VOLUME = 20e6       # skip assets trading under $20M per day
MIN_ACCURACY = 0.55            # keep signals right >= 55% of the time in the past
MIN_SAMPLES = 20               # ...over at least 20 past examples
TOP_N = 3                      # how many trades to send
BATCH = 100                    # tickers per download request
WIKI_URL = "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies"
USER_AGENT = "Mozilla/5.0 (compatible; ai-trade-notify/1.0)"
BACKUP_SP500 = [  # used if Wikipedia can't be reached
    "AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "GOOG", "META", "BRK-B", "AVGO", "TSLA",
    "LLY", "JPM", "V", "UNH", "XOM", "MA", "JNJ", "PG", "HD", "COST", "ABBV", "MRK",
    "ORCL", "CVX", "KO", "PEP", "ADBE", "WMT", "BAC", "CRM", "NFLX", "AMD", "TMO",
    "MCD", "CSCO", "ACN", "LIN", "ABT", "INTC", "WFC", "DIS", "QCOM", "TXN", "DHR",
    "VZ", "PM", "CAT", "IBM", "AMGN", "GE", "INTU", "NOW", "UNP", "SPGI", "GS",
    "HON", "BA", "LOW", "AMAT", "ISRG", "BKNG", "PFE", "T", "NEE", "RTX", "UBER",
]
# ======================================================================


def sp500_tickers():
    """Current S&P 500 list from Wikipedia (BRK.B -> BRK-B for Yahoo)."""
    try:
        import requests
        html = requests.get(WIKI_URL, headers={"User-Agent": USER_AGENT}, timeout=20).text
        table = pd.read_html(StringIO(html))[0]
        syms = [str(s).strip().replace(".", "-") for s in table["Symbol"]]
        if len(syms) > 400:
            return syms
    except Exception as e:
        print("Wikipedia failed, using backup list:", e)
    return list(BACKUP_SP500)


def universe():
    seen, out = set(), []
    for t in sp500_tickers() + CRYPTO + EXTRA:
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def download_many(tickers, period=tb.PERIOD, interval="1d"):
    """Download many tickers in batches. Returns {ticker: DataFrame}."""
    import yfinance as yf
    data = {}
    for i in range(0, len(tickers), BATCH):
        chunk = tickers[i:i + BATCH]
        for attempt in range(3):
            try:
                raw = yf.download(chunk, period=period, interval=interval, auto_adjust=True,
                                  group_by="ticker", progress=False, threads=True)
                break
            except Exception as e:
                print("download retry:", e)
                time.sleep(5)
        else:
            continue
        time.sleep(2)  # be gentle with Yahoo's free service
        for t in chunk:
            try:
                df = raw[t] if isinstance(raw.columns, pd.MultiIndex) else raw
                df = tb.clean(df)
                if len(df) >= 60:
                    data[t] = df
            except KeyError:
                pass
    return data


def scan_rules(data=None, top_n=TOP_N, with_hours=True):
    """Rule-based scan. Returns (picks, stats)."""
    tickers = universe()
    if data is None:
        data = download_many(tickers)
    stats = {"universe": len(tickers), "downloaded": len(data), "liquid": 0, "signals": 0}
    candidates = []
    for t, df in data.items():
        try:
            r = tb.analyze_df(df, t)
        except Exception:
            continue
        if r["dollar_volume"] < MIN_DOLLAR_VOLUME:
            continue
        stats["liquid"] += 1
        if r["signal"] == "WAIT":
            continue
        stats["signals"] += 1
        if r["accuracy"] is None or r["accuracy"] < MIN_ACCURACY or r["samples"] < MIN_SAMPLES:
            continue
        r["rank"] = abs(r["score"]) / 100 * r["accuracy"]
        candidates.append(r)
    candidates.sort(key=lambda r: r["rank"], reverse=True)
    picks = candidates[:top_n]
    if with_hours:
        for p in picks:
            p["hours"] = tb.best_hours(p["ticker"])
    stats["qualified"] = len(candidates)
    return picks, stats


def format_message(picks, title="Rule-based scan", note=""):
    lines = [f"<b>AI Trade Notify - {title}</b>", time.strftime("%Y-%m-%d") + " (next 5 days)", ""]
    if note:
        lines += [note, ""]
    if not picks:
        lines.append("No trade today - no setup passed the accuracy filter. Waiting is a position too.")
    for i, p in enumerate(picks, 1):
        side = p["signal"]
        icon = "🟢" if side == "BUY" else "🔴"
        lines.append(f"{icon} <b>{i}. {side} {p['ticker']}</b>")
        if "probability" in p:
            lines.append(f"   Chance of going {'up' if side == 'BUY' else 'down'}: {p['probability'] * 100:.0f}%")
        else:
            lines.append(f"   Score {p['score']:+.0f}")
        lines.append(f"   Past accuracy: {p['accuracy'] * 100:.0f}% of {p['samples']} signals")
        pl = p.get("plan")
        if pl:
            lines.append(f"   Entry {tb.fmt(pl['entry'])} | Stop {tb.fmt(pl['stop'])} | Target {tb.fmt(pl['target'])}")
        h = p.get("hours")
        if h:
            lines.append(f"   Best buy {h['buy_hour']} / sell {h['sell_hour']} Doha")
        lines.append("")
    lines.append("Use the stop-loss, risk max 1-2% per trade, paper-trade first.")
    lines.append(tb.DISCLAIMER)
    return "\n".join(lines)


def send_telegram(text, token=None, chat_id=None):
    token = token or TELEGRAM_TOKEN
    chat_id = chat_id or TELEGRAM_CHAT_ID
    if not token or not chat_id:
        print("(Telegram not set up - printing instead)\n")
        print(text)
        return False
    import requests
    r = requests.post(f"https://api.telegram.org/bot{token}/sendMessage",
                      json={"chat_id": chat_id, "text": text, "parse_mode": "HTML",
                            "disable_web_page_preview": True}, timeout=20)
    if not r.ok:
        print("Telegram error:", r.status_code, r.text[:200])
    return r.ok


def main():
    picks, stats = scan_rules()
    print(json.dumps(stats))
    send_telegram(format_message(picks))


if __name__ == "__main__":
    sys.exit(main())
