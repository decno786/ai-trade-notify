"""
Trade Helper signal bot.

Runs in the cloud every hour (GitHub Actions, free). For each coin it:
  1. downloads the latest finished hourly candles (free public price APIs)
  2. scores them with 6 indicators -> UP / DOWN / WAIT, confidence %, stars
  3. saves the result to Firebase Firestore  (collection "signals")
  4. when a NEW strong signal appears, saves it to "alerts" and sends a
     push notification to every phone/browser that turned alerts on

It never buys or sells anything. Signals come from past price patterns
and can be wrong.

Environment:
  FIREBASE_SERVICE_ACCOUNT  the service-account JSON (GitHub secret). If it is
                            missing the bot only prints results (test mode).
  APP_URL                   web app address, opened when a notification is tapped
  TEST_PUSH=1               also send a test notification
"""
import json
import math
import os
import sys
import time
import urllib.request

COINS = ["BTC", "ETH", "SOL", "XRP", "BNB", "ADA", "DOGE", "AVAX", "LINK", "DOT",
         "TRX", "LTC", "BCH", "NEAR", "SUI", "TON", "APT", "PEPE"]
# US stocks and ETFs (prices from Yahoo Finance, hourly candles, regular hours)
STOCKS = ["AAPL", "MSFT", "NVDA", "TSLA", "AMZN", "META", "GOOGL", "AMD", "NFLX", "PLTR", "COIN", "SPY", "QQQ", "GLD"]
TF_MIN = 60                # hourly candles
MIN_STARS_TO_ALERT = 4     # only push strong signals
MAX_ALERTS_PER_RUN = 3     # never more than 3 notifications per hour
TOPIC = "signals"
UA = {"User-Agent": "trade-helper-bot/1.0"}


# ------------------------------------------------------------------ prices
def _get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def from_binance(coin):
    now = time.time() * 1000
    rows = _get(f"https://data-api.binance.vision/api/v3/klines?symbol={coin}USDT&interval=1h&limit=200")
    return [{"t": int(k[0]), "o": float(k[1]), "h": float(k[2]), "l": float(k[3]),
             "c": float(k[4]), "v": float(k[5])} for k in rows if k[6] < now]


def from_coinbase(coin):
    now = time.time()
    rows = _get(f"https://api.exchange.coinbase.com/products/{coin}-USD/candles?granularity=3600")
    rows = sorted(r for r in rows if r[0] + 3600 <= now)
    return [{"t": int(r[0]) * 1000, "o": r[3], "h": r[2], "l": r[1], "c": r[4], "v": r[5]} for r in rows]


def from_kraken(coin):
    pair = {"BTC": "XBT", "DOGE": "XDG"}.get(coin, coin) + "USD"
    data = _get(f"https://api.kraken.com/0/public/OHLC?pair={pair}&interval=60")
    if data.get("error"):
        raise RuntimeError(data["error"])
    rows = next(v for k, v in data["result"].items() if k != "last")[:-1]  # last one is unfinished
    return [{"t": int(r[0]) * 1000, "o": float(r[1]), "h": float(r[2]), "l": float(r[3]),
             "c": float(r[4]), "v": float(r[6])} for r in rows]


SOURCES = [("Binance", from_binance), ("Coinbase", from_coinbase), ("Kraken", from_kraken)]
BROWSER_UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"}


def from_yahoo(ticker):
    """Hourly candles for a US stock/ETF + whether the market is open now."""
    last = None
    for host in ("query1", "query2"):
        try:
            req = urllib.request.Request(
                f"https://{host}.finance.yahoo.com/v8/finance/chart/{ticker}?interval=1h&range=60d", headers=BROWSER_UA)
            with urllib.request.urlopen(req, timeout=20) as r:
                res = json.load(r)["chart"]["result"][0]
            break
        except Exception as e:
            last = e
            time.sleep(1)
    else:
        raise RuntimeError(f"Yahoo: {last}")
    q = res["indicators"]["quote"][0]
    now = time.time()
    reg = res["meta"].get("currentTradingPeriod", {}).get("regular", {})
    is_open = bool(reg) and reg.get("start", 0) <= now < reg.get("end", 0)
    cd = []
    for i, t in enumerate(res.get("timestamp") or []):
        o, h, l, c, v = (q[k][i] for k in ("open", "high", "low", "close", "volume"))
        if None in (o, h, l, c):
            continue
        cd.append({"t": int(t) * 1000, "o": o, "h": h, "l": l, "c": c, "v": v or 0})
    if is_open and cd and cd[-1]["t"] / 1000 + 3600 > now:
        cd = cd[:-1]  # drop the hour that is still running
    live = res["meta"].get("regularMarketPrice")
    return cd[-200:], is_open, live


def day_stats(cd):
    """Change vs previous trading day's close, and today's high/low (New York days)."""
    day = lambda x: (x["t"] // 1000 - 5 * 3600) // 86400
    today = day(cd[-1])
    prev = [x for x in cd if day(x) < today]
    now = [x for x in cd if day(x) == today]
    pc = prev[-1]["c"] if prev else cd[0]["o"]
    return {"chg24": round((cd[-1]["c"] / pc - 1) * 100, 2), "prevClose": pc,
            "hi24": max(x["h"] for x in now), "lo24": min(x["l"] for x in now),
            "vol24": round(sum(x["v"] * x["c"] for x in now))}


def get_candles(coin):
    errors = []
    for name, fn in SOURCES:
        try:
            cd = fn(coin)
            if len(cd) >= 60:
                return cd[-200:], name
            errors.append(f"{name}: only {len(cd)} candles")
        except Exception as e:
            errors.append(f"{name}: {e}")
    raise RuntimeError("; ".join(errors))


# ------------------------------------------------------------------ indicators
def ema(v, n):
    k, out, p = 2 / (n + 1), [], None
    for i, x in enumerate(v):
        if i < n - 1:
            out.append(None)
            continue
        p = sum(v[:n]) / n if p is None else x * k + p * (1 - k)
        out.append(p)
    return out


def rsi(c, n=14):
    g = sum(max(c[i] - c[i - 1], 0) for i in range(1, n + 1)) / n
    l = sum(max(c[i - 1] - c[i], 0) for i in range(1, n + 1)) / n
    for i in range(n + 1, len(c)):
        d = c[i] - c[i - 1]
        g, l = (g * (n - 1) + max(d, 0)) / n, (l * (n - 1) + max(-d, 0)) / n
    return 100.0 if l == 0 else 100 - 100 / (1 + g / l)


def analyse(cd):
    c = [x["c"] for x in cd]
    price = c[-1]
    e9, e21, e50 = ema(c, 9), ema(c, 21), ema(c, 50)
    r = rsi(c)
    e12, e26 = ema(c, 12), ema(c, 26)
    line = [a - b for a, b in zip(e12, e26) if a is not None and b is not None]
    sig = ema(line, 9)
    mh, mph = line[-1] - sig[-1], line[-2] - sig[-2]
    w = c[-20:]
    mid = sum(w) / 20
    sd = math.sqrt(sum((x - mid) ** 2 for x in w) / 20)
    lo, up = mid - 2 * sd, mid + 2 * sd
    trs = [max(cd[i]["h"] - cd[i]["l"], abs(cd[i]["h"] - cd[i - 1]["c"]), abs(cd[i]["l"] - cd[i - 1]["c"]))
           for i in range(1, len(cd))]
    a = sum(trs[:14]) / 14
    for t in trs[14:]:
        a = (a * 13 + t) / 14
    vn = sum(x["v"] for x in cd[-5:]) / 5
    va = sum(x["v"] for x in cd[-50:]) / 50

    ck = []
    tr = 1 if price > e50[-1] and e21[-1] > e50[-1] else -1 if price < e50[-1] and e21[-1] < e50[-1] else 0
    ck.append(("Trend", tr, 2, "The bigger trend is going up" if tr > 0 else
               "The bigger trend is going down" if tr < 0 else "No clear bigger trend"))
    cr = 1 if e9[-1] > e21[-1] else -1
    ck.append(("Short trend", cr, 1.5, "Recent prices are rising" if cr > 0 else "Recent prices are falling"))
    rs = 1 if 50 < r < 70 else -1 if 30 < r < 50 else (-0.5 if r >= 70 else 0.5)
    ck.append(("Strength", rs, 1, "Bought too much already, may pull back" if r >= 70 else
               "Sold too much already, may bounce" if r <= 30 else
               "Buyers are stronger" if r > 50 else "Sellers are stronger"))
    m = 1 if mh > 0 and mh > mph else -1 if mh < 0 and mh < mph else (0.5 if mh > 0 else -0.5)
    ck.append(("Speed", m, 1.5, "Upward speed is growing" if m > 0 else "Downward speed is growing"))
    bs = -0.5 if price > up else 0.5 if price < lo else (0.5 if price > mid else -0.5)
    ck.append(("Range", bs, 1, "Price is unusually high" if price > up else "Price is unusually low" if price < lo
               else "Price is in the top half of its range" if price > mid else "Price is in the bottom half of its range"))
    vs = 1 if vn > va * 1.2 else 0
    ck.append(("Volume", vs, 1, "More people trading than usual (confirms the move)" if vs else "Normal trading activity"))

    raw = sum(x[1] * x[2] for x in ck[:-1]) / sum(x[2] for x in ck[:-1])
    if vs and raw:
        raw = max(-1.0, min(1.0, raw * 1.15))
    conf = round(abs(raw) * 100)
    d = "WAIT" if conf < 35 else "UP" if raw > 0 else "DOWN"
    stars = 0 if d == "WAIT" else min(5, 1 + conf // 18)
    s = 1 if d == "UP" else -1
    day = cd[-24:]
    o24 = day[0]["o"]
    extra = {
        "chg24": round((price / o24 - 1) * 100, 2) if o24 else 0,
        "hi24": max(x["h"] for x in day), "lo24": min(x["l"] for x in day),
        "vol24": round(sum(x["v"] * x["c"] for x in day)),
        "ema21": e21[-1], "ema50": e50[-1], "macd": mh, "bbPos": round((price - lo) / (up - lo), 3) if up > lo else 0.5,
        "volRatio": round(vn / va, 2) if va else 1,
        # last 72 hourly candles for the charts: [time, open, high, low, close]
        "candles": [[x["t"], x["o"], x["h"], x["l"], x["c"]] for x in cd[-72:]],
    }
    return {**extra, "price": price, "dir": d, "conf": conf, "stars": stars, "atr": a, "rsi": round(r, 1),
            "stop": price - s * 1.5 * a, "tp1": price + s * 2 * a, "tp2": price + s * 4 * a,
            "checks": [{"label": n, "score": sc, "note": note} for n, sc, _, note in ck],
            "candleClose": cd[-1]["t"] + TF_MIN * 60000}


def fmt(p):
    if p >= 100:
        return f"{p:,.2f}"
    if p >= 1:
        return f"{p:,.4f}"
    return f"{p:.10f}".rstrip("0") if p < 0.001 else f"{p:.6f}"


def is_strong(s):
    return s and s.get("dir") in ("UP", "DOWN") and s.get("stars", 0) >= MIN_STARS_TO_ALERT


def is_new_alert(new, old):
    """Alert only when a coin BECOMES a strong signal, not every hour it stays one."""
    return is_strong(new) and not (is_strong(old) and old.get("dir") == new["dir"])


# ------------------------------------------------------------------ firebase
def connect():
    raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if not raw:
        return None, None
    import firebase_admin
    from firebase_admin import credentials, firestore, messaging
    firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
    return firestore, messaging


def push(messaging, title, body, app_url):
    msg = messaging.Message(
        topic=TOPIC,
        notification=messaging.Notification(title=title, body=body),
        android=messaging.AndroidConfig(priority="high"),
        webpush=messaging.WebpushConfig(
            fcm_options=messaging.WebpushFCMOptions(link=app_url)) if app_url.startswith("https://") else None,
    )
    return messaging.send(msg)


def subscribe_new_browsers(db, messaging):
    """Web browsers register their push token in 'tokens'; add them to the topic."""
    docs = list(db.collection("tokens").limit(1000).stream())
    if not docs:
        return 0
    res = messaging.subscribe_to_topic([d.id for d in docs], TOPIC)
    for d in docs:
        d.reference.delete()
    return res.success_count


def main():
    firestore, messaging = connect()
    db = firestore.client() if firestore else None
    app_url = os.environ.get("APP_URL", "").strip()
    if not db:
        print("TEST MODE: no FIREBASE_SERVICE_ACCOUNT, results are only printed.\n")

    if db:
        print(f"New browsers subscribed to alerts: {subscribe_new_browsers(db, messaging)}")

    results, failed, sources = [], [], set()
    now_ms = int(time.time() * 1000)
    for coin in COINS:
        try:
            cd, src = get_candles(coin)
            s = analyse(cd)
            s.update(name=coin, source=src, market="crypto", marketOpen=True,
                     validUntil=s["candleClose"] + TF_MIN * 60000 + 5 * 60000)
            results.append(s)
            sources.add(src)
            print(f"{coin:<5} {s['dir']:<5} {s['conf']:>3}%  {'*' * s['stars']:<5} {fmt(s['price']):>12}  ({src})")
        except Exception as e:
            failed.append(coin)
            print(f"{coin:<5} could not get prices: {e}")
    for tk in STOCKS:
        try:
            cd, is_open, last = from_yahoo(tk)
            if len(cd) < 60:
                raise RuntimeError(f"only {len(cd)} candles")
            s = analyse(cd)
            s.update(day_stats(cd))
            s.update(name=tk, source="Yahoo", market="stock", marketOpen=is_open, lastPrice=last or s["price"],
                     validUntil=s["candleClose"] + TF_MIN * 60000 + 5 * 60000 if is_open else 0)
            results.append(s)
            sources.add("Yahoo")
            print(f"{tk:<5} {s['dir']:<5} {s['conf']:>3}%  {'open' if is_open else 'closed':<6} {fmt(s['price']):>12}")
        except Exception as e:
            failed.append(tk)
            print(f"{tk:<5} could not get prices: {e}")

    if not results:
        print("No prices from any source.")
        sys.exit(1)

    best = max(results, key=lambda r: (r["dir"] != "WAIT", r["conf"]))
    next_ms = (now_ms // 3_600_000 + 1) * 3_600_000 + 5 * 60_000
    alerts = []

    if db:
        batch = db.batch()
        for s in results:
            ref = db.collection("signals").document(s["name"])
            old = ref.get()
            old = old.to_dict() if old.exists else None
            if is_new_alert(s, old):
                alerts.append(s)
            # when did the current direction start? (for "signal active since")
            s["since"] = old.get("since", now_ms) if old and old.get("dir") == s["dir"] else now_ms
            s["issuedAt"] = now_ms
            batch.set(ref, {**s, "updatedAt": firestore.SERVER_TIMESTAMP})
        batch.set(db.collection("status").document("bot"), {
            "lastRun": firestore.SERVER_TIMESTAMP, "lastRunMs": now_ms, "nextRunMs": next_ms,
            "tf": TF_MIN, "coins": len(results), "failed": failed, "stocks": len(STOCKS), "crypto": len(COINS),
            "sources": sorted(sources), "best": best["name"],
        })
        batch.commit()

        alerts = sorted(alerts, key=lambda s: s["conf"], reverse=True)[:MAX_ALERTS_PER_RUN]
        for s in alerts:
            buy = s["dir"] == "UP"
            pair = s["name"] if s.get("market") == "stock" else f"{s['name']}/USDT"
            if s.get("market") == "stock" and not s.get("marketOpen"):
                continue  # don't alert on stocks while the market is closed
            title = f"{'BUY' if buy else 'SELL'} {pair} {'▲' if buy else '▼'} · Signal strength {s['conf']}/100"
            body = f"Entry {fmt(s['price'])} · Target {fmt(s['tp1'])} · Stop {fmt(s['stop'])}"
            db.collection("alerts").add({
                "name": s["name"], "market": s.get("market", "crypto"), "dir": s["dir"], "conf": s["conf"], "stars": s["stars"],
                "price": s["price"], "tp1": s["tp1"], "stop": s["stop"],
                "at": firestore.SERVER_TIMESTAMP, "atMs": now_ms, "title": title, "body": body})
            try:
                push(messaging, title, body, app_url)
                print("Pushed:", title)
            except Exception as e:
                print("Push failed:", e)

        if os.environ.get("TEST_PUSH") == "1":
            push(messaging, "AI Trade Notify · test", "Alerts are working. You'll get a message like this for strong signals.", app_url)
            print("Test notification sent.")

    print(f"\nBest now: {best['name']} {best['dir']} {best['conf']}%. New alerts: {len(alerts)}.")


if __name__ == "__main__":
    main()
