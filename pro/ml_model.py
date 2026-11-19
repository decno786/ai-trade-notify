"""
ml_model.py - machine learning that learns its own weights
==========================================================

Instead of hand-picked weights (trading_bot.py), a model learns from 5 years of
history which indicator values tended to come before a 5-day rise.

How it stays honest:
  * Features only use data up to that day (no peeking into the future).
  * Label = "was the price higher 5 days later?" (1 = yes, 0 = no).
  * Walk-forward exam: the last 180 days are hidden during training, with a
    10-day gap so no training label overlaps the exam.
  * It is compared against a dumb baseline (always guessing the most common
    answer). If it doesn't beat the baseline by 2+ points on its confident
    calls, it says "NO EDGE - don't trade".

Commands:
  python ml_model.py train      (weekly)  learn + exam + save model.joblib
  python ml_model.py scan       (daily)   find today's picks, send to Telegram
  python ml_model.py picks      (any)     print today's picks as JSON

Not financial advice. Realistic accuracy is 55-60%; 80%+ usually means a bug.
"""
import json
import os
import sys
import time

import numpy as np
import pandas as pd

import scanner_alerts as sa
import trading_bot as tb

# ============================== SETTINGS ==============================
MODEL_FILE = os.environ.get("MODEL_FILE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "model.joblib"))
TRAIN_PERIOD = "5y"          # history used for learning
SCAN_PERIOD = "1y"           # history needed to compute today's features
HORIZON = 5                  # predict 5 days ahead
TEST_DAYS = 180              # last 180 days = unseen exam
GAP_DAYS = 10                # gap between training and exam (prevents leakage)
CONFIDENT_UP = 0.60          # probability >= 60% -> BUY
CONFIDENT_DOWN = 0.40        # probability <= 40% -> SELL
MIN_EDGE = 0.02              # must beat the baseline by 2 points
MIN_ASSET_ACCURACY = 0.55    # per-asset exam accuracy needed to send a pick
MIN_ASSET_SAMPLES = 20       # ...over at least 20 exam signals
TOP_N = 3
FEATURES = ["ema_gap", "dist_ema20", "rsi", "macd_rel", "bb_pos", "atr_rel",
            "vol_ratio", "ret1", "ret5", "ret20", "dow"]
FEATURE_NAMES = {
    "ema_gap": "EMA20 vs EMA50", "dist_ema20": "Distance from EMA20", "rsi": "RSI",
    "macd_rel": "MACD / price", "bb_pos": "Bollinger position", "atr_rel": "ATR / price (volatility)",
    "vol_ratio": "Volume vs 20-day avg", "ret1": "1-day return", "ret5": "5-day return",
    "ret20": "20-day return", "dow": "Day of week",
}
# ======================================================================


def make_features(df, with_label=True):
    """Scale-free features (comparable across assets) + optional 5-day label."""
    d = tb.add_indicators(tb.clean(df))
    c = d["Close"]
    f = pd.DataFrame(index=d.index)
    f["ema_gap"] = d["EMA20"] / d["EMA50"] - 1
    f["dist_ema20"] = c / d["EMA20"] - 1
    f["rsi"] = d["RSI"] / 100
    f["macd_rel"] = d["MACD_HIST"] / c
    f["bb_pos"] = d["BB_POS"]
    f["atr_rel"] = d["ATR"] / c
    f["vol_ratio"] = d["VOL_RATIO"].clip(upper=10)
    f["ret1"] = c.pct_change(1)
    f["ret5"] = c.pct_change(5)
    f["ret20"] = c.pct_change(20)
    f["dow"] = d.index.dayofweek
    f["close"] = c
    f["atr"] = d["ATR"]
    f["dollar_volume"] = (c * d["Volume"]).rolling(20).mean() if "Volume" in d else np.nan
    f = f.iloc[50:]                                 # skip indicator warm-up
    if with_label:
        future = c.shift(-HORIZON).loc[f.index]
        f["label"] = np.where(future.isna(), np.nan, (future > f["close"]).astype(float))
    return f.replace([np.inf, -np.inf], np.nan)


def build_dataset(data):
    parts = []
    for t, df in data.items():
        try:
            f = make_features(df)
        except Exception:
            continue
        f["ticker"] = t
        f["date"] = f.index.tz_localize(None) if f.index.tz is not None else f.index
        parts.append(f)
    ds = pd.concat(parts, ignore_index=True)
    return ds.dropna(subset=FEATURES)


def make_models():
    from sklearn.ensemble import HistGradientBoostingClassifier
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler
    return {
        "Logistic Regression": make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000)),
        "Gradient Boosting": HistGradientBoostingClassifier(
            max_iter=300, learning_rate=0.05, max_leaf_nodes=31, l2_regularization=1.0,
            min_samples_leaf=200, random_state=7),
    }


def evaluate(prob, y):
    pred = (prob >= 0.5).astype(int)
    conf = (prob >= CONFIDENT_UP) | (prob <= CONFIDENT_DOWN)
    n_conf = int(conf.sum())
    return {
        "accuracy": round(float((pred == y).mean()), 4),
        "confident_accuracy": round(float((pred[conf] == y[conf]).mean()), 4) if n_conf else None,
        "confident_count": n_conf,
        "coverage": round(n_conf / len(y), 4) if len(y) else 0,
    }


def train(data=None, save=True, verbose=True):
    """Walk-forward exam, pick the best model, retrain on everything, save."""
    import joblib
    from sklearn.inspection import permutation_importance

    log = print if verbose else (lambda *a, **k: None)
    if data is None:
        log("Downloading", TRAIN_PERIOD, "of daily prices for the whole universe...")
        data = sa.download_many(sa.universe(), period=TRAIN_PERIOD)
    ds = build_dataset(data)
    labelled = ds.dropna(subset=["label"])
    last_day = labelled["date"].max()
    test_start = last_day - pd.Timedelta(days=TEST_DAYS)
    train_end = test_start - pd.Timedelta(days=GAP_DAYS)
    tr = labelled[labelled["date"] < train_end]
    te = labelled[labelled["date"] >= test_start]
    log(f"Rows: train {len(tr):,} (until {train_end.date()}), exam {len(te):,} "
        f"({test_start.date()} to {last_day.date()}), {labelled['ticker'].nunique()} assets")

    Xtr, ytr = tr[FEATURES].to_numpy(), tr["label"].to_numpy().astype(int)
    Xte, yte = te[FEATURES].to_numpy(), te["label"].to_numpy().astype(int)
    up_share = float(yte.mean())
    baseline = max(up_share, 1 - up_share)
    log(f"Baseline (always guess '{'up' if up_share >= 0.5 else 'down'}'): {baseline * 100:.1f}%")

    results, fitted = {}, {}
    for name, model in make_models().items():
        model.fit(Xtr, ytr)
        prob = model.predict_proba(Xte)[:, 1]
        results[name] = evaluate(prob, yte)
        fitted[name] = (model, prob)
        r = results[name]
        ca = f"{r['confident_accuracy'] * 100:.1f}%" if r["confident_accuracy"] is not None else "n/a"
        log(f"{name:<20} exam accuracy {r['accuracy'] * 100:.1f}% | confident calls {ca} "
            f"on {r['confident_count']:,} ({r['coverage'] * 100:.0f}% of days)")

    def key(n):
        r = results[n]
        return r["confident_accuracy"] if r["confident_count"] >= 200 and r["confident_accuracy"] else r["accuracy"] - 0.01
    best = max(results, key=key)
    best_score = key(best)
    edge = best_score - baseline
    has_edge = edge >= MIN_EDGE
    log(f"\nChosen: {best}. Edge over baseline: {edge * 100:+.1f} points -> "
        + ("EDGE FOUND" if has_edge else "NO EDGE - don't trade on this model"))

    # what the models learned
    lr = fitted["Logistic Regression"][0]
    weights = dict(zip(FEATURES, lr[-1].coef_[0].round(4).tolist()))
    log("\nLogistic Regression weights (+ pushes toward 'up'):")
    for k, v in sorted(weights.items(), key=lambda kv: -abs(kv[1])):
        log(f"   {FEATURE_NAMES[k]:<28} {v:+.4f}")
    gb = fitted["Gradient Boosting"][0]
    n = min(len(Xte), 20000)
    idx = np.random.default_rng(7).choice(len(Xte), n, replace=False)
    pi = permutation_importance(gb, Xte[idx], yte[idx], n_repeats=3, random_state=7, scoring="accuracy")
    importance = dict(zip(FEATURES, pi.importances_mean.round(5).tolist()))
    log("\nGradient Boosting permutation importance (accuracy lost when shuffled):")
    for k, v in sorted(importance.items(), key=lambda kv: -kv[1]):
        log(f"   {FEATURE_NAMES[k]:<28} {v * 100:+.2f} pts")

    # per-asset exam accuracy of the chosen model (confident calls only)
    prob = fitted[best][1]
    ex = te[["ticker"]].copy()
    ex["correct"] = ((prob >= 0.5).astype(int) == yte)
    ex["conf"] = (prob >= CONFIDENT_UP) | (prob <= CONFIDENT_DOWN)
    g = ex[ex["conf"]].groupby("ticker")["correct"].agg(["mean", "count"])
    per_asset = {t: {"accuracy": round(float(r["mean"]), 3), "n": int(r["count"])} for t, r in g.iterrows()}

    # final model: retrain the chosen type on ALL labelled data
    final = make_models()[best]
    final.fit(labelled[FEATURES].to_numpy(), labelled["label"].to_numpy().astype(int))
    bundle = {
        "model": final, "model_name": best, "features": FEATURES,
        "trained_at": time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime()),
        "exam": {"start": str(test_start.date()), "end": str(last_day.date()), "rows": int(len(te))},
        "baseline": round(baseline, 4), "results": results, "edge": round(edge, 4), "has_edge": has_edge,
        "weights": weights, "importance": importance, "per_asset": per_asset,
    }
    if save:
        joblib.dump(bundle, MODEL_FILE)
        log(f"\nSaved {MODEL_FILE}")
    return bundle


def load_bundle():
    import joblib
    if not os.path.exists(MODEL_FILE):
        raise FileNotFoundError("No model yet. Run:  python ml_model.py train")
    return joblib.load(MODEL_FILE)


def model_info(b):
    r = b["results"][b["model_name"]]
    return {"name": b["model_name"], "trained_at": b["trained_at"], "exam": b["exam"],
            "baseline": b["baseline"], "accuracy": r["accuracy"], "confident_accuracy": r["confident_accuracy"],
            "edge": b["edge"], "has_edge": bool(b["has_edge"])}


def find_picks(data=None, bundle=None, top_n=TOP_N, with_hours=True):
    """Returns {"model": {...}, "picks": [...], "stats": {...}} - nothing is sent."""
    b = bundle or load_bundle()
    if data is None:
        data = sa.download_many(sa.universe(), period=SCAN_PERIOD)
    rows = []
    for t, df in data.items():
        try:
            f = make_features(df, with_label=False).dropna(subset=FEATURES)
        except Exception:
            continue
        if f.empty:
            continue
        last = f.iloc[-1]
        if not (last["dollar_volume"] >= sa.MIN_DOLLAR_VOLUME):
            continue
        rows.append((t, f.index[-1], last))
    stats = {"universe": len(data), "liquid": len(rows), "confident": 0, "qualified": 0}
    if not rows:
        return {"model": model_info(b), "picks": [], "stats": stats}
    X = np.array([[r[2][k] for k in FEATURES] for r in rows])
    probs = b["model"].predict_proba(X)[:, 1]
    cands = []
    for (t, day, last), p in zip(rows, probs):
        if CONFIDENT_DOWN < p < CONFIDENT_UP:
            continue
        stats["confident"] += 1
        acc = b["per_asset"].get(t)
        if not acc or acc["accuracy"] < MIN_ASSET_ACCURACY or acc["n"] < MIN_ASSET_SAMPLES:
            continue
        side = "BUY" if p >= CONFIDENT_UP else "SELL"
        prob_side = float(p if side == "BUY" else 1 - p)
        cands.append({
            "ticker": t, "date": str(pd.Timestamp(day).date()), "signal": side,
            "probability": round(prob_side, 3), "accuracy": acc["accuracy"], "samples": acc["n"],
            "price": round(float(last["close"]), 6),
            "plan": tb.trade_plan(float(last["close"]), float(last["atr"]), side),
            "rank": round((prob_side - 0.5) * 2 * acc["accuracy"], 4),
        })
    stats["qualified"] = len(cands)
    cands.sort(key=lambda c: c["rank"], reverse=True)
    picks = cands[:top_n]
    if with_hours:
        for p in picks:
            p["hours"] = tb.best_hours(p["ticker"])
    return {"model": model_info(b), "picks": picks, "stats": stats,
            "generated_at": time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())}


def scan(result=None):
    """Find picks and send them to Telegram."""
    res = result or find_picks()
    m = res["model"]
    note = (f"Model: {m['name']} | exam accuracy on confident calls "
            f"{(m['confident_accuracy'] or 0) * 100:.0f}% vs baseline {m['baseline'] * 100:.0f}%")
    if not m["has_edge"]:
        note = "⚠️ <b>NO EDGE - don't trade.</b> The model did not beat simple guessing on its exam.\n" + note
    sa.send_telegram(sa.format_message(res["picks"], title="ML 5-day picks", note=note))
    return res


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if cmd == "train":
        train()
    elif cmd == "scan":
        out = scan()
        if len(sys.argv) > 2:
            json.dump(out, open(sys.argv[2], "w"), default=str, indent=1)
    elif cmd == "picks":
        print(json.dumps(find_picks(), default=str, indent=1))
    else:
        print(__doc__)
