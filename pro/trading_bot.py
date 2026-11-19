"""
trading_bot.py - core indicators and rule-based signals
=======================================================

What it does, for each asset:
  1. Downloads 2 years of daily prices (yfinance, free).
  2. Calculates indicators: EMA 20/50, RSI 14, MACD histogram, Bollinger Band
     position, ATR 14 and volume vs its 20-day average.
  3. Turns them into ONE score from -100 (very bearish) to +100 (very bullish):
        BUY  if score >= +40
        SELL if score <= -40
        WAIT otherwise
  4. Backtests itself: of all past days with a strong BUY (or SELL), how often
     was the price really higher (or lower) 5 days later?
  5. Builds a trade plan: stop-loss = 1.5 x ATR, target = 3 x ATR (1:2 risk/reward)
     and a position size that risks only RISK_PCT of your account.
  6. Finds the typical cheapest hour (best to buy) and most expensive hour
     (best to sell) in Doha time from the last 60 days of hourly prices.

Run:   python trading_bot.py            (analyses the TICKERS below)
       python trading_bot.py AAPL BTC-USD

Honest note: signals are probabilities, not guarantees. A realistic hit rate
is 55-60%. Always use the stop-loss, risk at most 1-2% per trade, and
paper-trade for at least a month first. This is not financial advice.
"""
import sys

import numpy as np
import pandas as pd

# ============================== SETTINGS ==============================
TICKERS = ["AAPL", "MSFT", "NVDA", "SPY", "BTC-USD", "ETH-USD"]
PERIOD = "2y"            # daily history used for indicators and backtest
HORIZON = 5              # days ahead we try to predict
BUY_SCORE = 40           # score >= this  -> BUY
SELL_SCORE = -40         # score <= this  -> SELL
HIGH_VOLUME = 1.5        # volume ratio above this boosts the score x1.2
STOP_ATR = 1.5           # stop-loss distance in ATRs
TARGET_ATR = 3.0         # target distance in ATRs (1:2 risk/reward)
ACCOUNT_SIZE = 1000.0    # your trading money (for position size)
RISK_PCT = 1.0           # % of account you accept to lose per trade (1-2% max)
LOCAL_TZ = "Asia/Qatar"  # Doha time (UTC+3)
HOURS_LOOKBACK = "60d"   # hourly history for "best hours"
DISCLAIMER = "Signals are probabilities, not guarantees. Not financial advice."
# ======================================================================


# ------------------------------------------------------------- data
def download(ticker, period=PERIOD, interval="1d"):
    """Download prices from Yahoo Finance and return a clean OHLCV table."""
    import yfinance as yf
    df = yf.download(ticker, period=period, interval=interval, auto_adjust=True,
                     progress=False, threads=False)
    return clean(df)


def clean(df):
    """Make yfinance output simple: single-level columns, no empty rows."""
    if df is None or len(df) == 0:
        return pd.DataFrame()
    if isinstance(df.columns, pd.MultiIndex):
        df = df.copy()
        df.columns = df.columns.get_level_values(0)
    keep = [c for c in ["Open", "High", "Low", "Close", "Volume"] if c in df.columns]
    return df[keep].dropna(subset=["Close"]).copy()


# ------------------------------------------------------------- indicators
def add_indicators(df):
    """Add every indicator as a new column. Uses only past and current data."""
    d = df.copy()
    c, h, l = d["Close"], d["High"], d["Low"]
    d["EMA20"] = c.ewm(span=20, adjust=False).mean()
    d["EMA50"] = c.ewm(span=50, adjust=False).mean()

    delta = c.diff()
    gain = delta.clip(lower=0).ewm(alpha=1 / 14, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1 / 14, adjust=False).mean()
    rs = gain / loss.replace(0, np.nan)
    d["RSI"] = (100 - 100 / (1 + rs)).fillna(100)

    macd = c.ewm(span=12, adjust=False).mean() - c.ewm(span=26, adjust=False).mean()
    d["MACD_HIST"] = macd - macd.ewm(span=9, adjust=False).mean()

    mid = c.rolling(20).mean()
    sd = c.rolling(20).std()
    width = (4 * sd).replace(0, np.nan)
    d["BB_POS"] = (c - (mid - 2 * sd)) / width          # 0 = lower band, 1 = upper band

    prev = c.shift(1)
    tr = pd.concat([h - l, (h - prev).abs(), (l - prev).abs()], axis=1).max(axis=1)
    d["ATR"] = tr.ewm(alpha=1 / 14, adjust=False).mean()

    vol = d["Volume"].astype(float) if "Volume" in d else pd.Series(1.0, index=d.index)
    d["VOL_RATIO"] = vol / vol.rolling(20).mean().replace(0, np.nan)
    return d


def add_score(d):
    """Combine the votes into a score from -100 to +100."""
    c, hist = d["Close"], d["MACD_HIST"]
    trend = np.where((c > d["EMA20"]) & (d["EMA20"] > d["EMA50"]), 1.0,
                     np.where((c < d["EMA20"]) & (d["EMA20"] < d["EMA50"]), -1.0, 0.0))
    rising = hist > hist.shift(1)
    momentum = np.where((hist > 0) & rising, 1.0,
                        np.where((hist < 0) & ~rising, -1.0, np.where(hist > 0, 0.5, -0.5)))
    rsi = d["RSI"]
    rsi_vote = np.where(rsi < 30, 1.0, np.where(rsi > 70, -1.0, np.where(rsi >= 50, 0.5, -0.5)))
    bb = d["BB_POS"]
    bb_vote = np.where(bb < 0.1, 1.0, np.where(bb > 0.9, -1.0, 0.0))  # stretched -> expect snap back

    score = 40 * trend + 25 * momentum + 20 * rsi_vote + 15 * bb_vote
    score = np.where(d["VOL_RATIO"] > HIGH_VOLUME, score * 1.2, score)
    d = d.copy()
    d["SCORE"] = np.clip(score, -100, 100).round(1)
    d["SIGNAL"] = np.where(d["SCORE"] >= BUY_SCORE, "BUY",
                           np.where(d["SCORE"] <= SELL_SCORE, "SELL", "WAIT"))
    return d


# ------------------------------------------------------------- backtest
def backtest(d, horizon=HORIZON):
    """How often did past strong signals call the next-5-day direction right?

    Only days whose 5-day outcome is already known are counted, so today's
    signal never 'sees' the future.
    """
    fwd = d["Close"].shift(-horizon) / d["Close"] - 1
    known = fwd.notna()
    out = {}
    for side, mask, good in (("BUY", d["SCORE"] >= BUY_SCORE, fwd > 0),
                             ("SELL", d["SCORE"] <= SELL_SCORE, fwd < 0)):
        m = mask & known
        n = int(m.sum())
        out[side] = {"n": n, "accuracy": round(float(good[m].mean()), 3) if n else None}
    n_all = out["BUY"]["n"] + out["SELL"]["n"]
    hits = sum((out[s]["accuracy"] or 0) * out[s]["n"] for s in out)
    out["ALL"] = {"n": n_all, "accuracy": round(hits / n_all, 3) if n_all else None}
    return out


# ------------------------------------------------------------- trade plan
def trade_plan(entry, atr, side, account=ACCOUNT_SIZE, risk_pct=RISK_PCT):
    """Entry, stop, target and position size for one trade."""
    s = 1 if side == "BUY" else -1
    stop = entry - s * STOP_ATR * atr
    target = entry + s * TARGET_ATR * atr
    risk_per_unit = abs(entry - stop)
    risk_money = account * risk_pct / 100
    qty = risk_money / risk_per_unit if risk_per_unit > 0 else 0
    return {
        "entry": round(entry, 6), "stop": round(stop, 6), "target": round(target, 6),
        "risk_reward": round(TARGET_ATR / STOP_ATR, 2),
        "risk_money": round(risk_money, 2), "position_units": round(qty, 6),
        "position_value": round(qty * entry, 2),
    }


# ------------------------------------------------------------- best hours (Doha)
def best_hours_from(hourly, tz=LOCAL_TZ, min_samples=10):
    """Typical cheapest hour (buy) and most expensive hour (sell) in local time."""
    h = clean(hourly)
    if len(h) < 50:
        return None
    idx = h.index if h.index.tz is not None else h.index.tz_localize("UTC")
    h = h.set_axis(idx.tz_convert(tz))
    day = h.index.date
    rel = h["Close"] / h["Close"].groupby(day).transform("mean") - 1
    by_hour = rel.groupby(h.index.hour).agg(["mean", "count"])
    by_hour = by_hour[by_hour["count"] >= min_samples]
    if by_hour.empty:
        return None
    buy, sell = int(by_hour["mean"].idxmin()), int(by_hour["mean"].idxmax())
    return {"buy_hour": f"{buy:02d}:00", "sell_hour": f"{sell:02d}:00", "timezone": "Doha (UTC+3)",
            "edge_pct": round(float((by_hour['mean'].max() - by_hour['mean'].min()) * 100), 2)}


def best_hours(ticker):
    try:
        return best_hours_from(download(ticker, period=HOURS_LOOKBACK, interval="1h"))
    except Exception:
        return None


# ------------------------------------------------------------- one asset
def analyze_df(df, ticker=""):
    """Full analysis of a price table. Returns a dict for the latest day."""
    d = add_score(add_indicators(clean(df)))
    if len(d) < 60:
        raise ValueError("not enough history")
    last = d.iloc[-1]
    side = str(last["SIGNAL"])
    bt = backtest(d)
    res = {
        "ticker": ticker, "date": str(d.index[-1].date()), "price": round(float(last["Close"]), 6),
        "score": float(last["SCORE"]), "signal": side,
        "rsi": round(float(last["RSI"]), 1), "atr": round(float(last["ATR"]), 6),
        "vol_ratio": round(float(last["VOL_RATIO"]), 2) if pd.notna(last["VOL_RATIO"]) else None,
        "dollar_volume": float((d["Close"] * d.get("Volume", 0)).tail(20).mean()),
        "backtest": bt,
        "accuracy": bt[side]["accuracy"] if side in ("BUY", "SELL") else bt["ALL"]["accuracy"],
        "samples": bt[side]["n"] if side in ("BUY", "SELL") else bt["ALL"]["n"],
    }
    if side in ("BUY", "SELL"):
        res["plan"] = trade_plan(float(last["Close"]), float(last["ATR"]), side)
    return res


def analyze(ticker, with_hours=True):
    res = analyze_df(download(ticker), ticker)
    if with_hours:
        res["hours"] = best_hours(ticker)
    return res


def fmt(x):
    return f"{x:,.2f}" if abs(x) >= 100 else f"{x:,.4f}" if abs(x) >= 1 else f"{x:.6f}"


def report(r):
    lines = [f"{r['ticker']:<9} {r['signal']:<4}  score {r['score']:+6.1f}  price {fmt(r['price'])}"]
    acc = r["accuracy"]
    lines.append(f"   past accuracy: {acc * 100:.0f}% of {r['samples']} signals" if acc is not None
                 else "   past accuracy: not enough history")
    if "plan" in r:
        p = r["plan"]
        lines.append(f"   entry {fmt(p['entry'])}  stop {fmt(p['stop'])}  target {fmt(p['target'])}  "
                     f"(risk ${p['risk_money']}, size {p['position_units']:g})")
    if r.get("hours"):
        lines.append(f"   best buy hour {r['hours']['buy_hour']}, best sell hour {r['hours']['sell_hour']} Doha")
    return "\n".join(lines)


if __name__ == "__main__":
    for t in (sys.argv[1:] or TICKERS):
        try:
            print(report(analyze(t)))
        except Exception as e:
            print(f"{t}: skipped ({e})")
    print("\n" + DISCLAIMER)
