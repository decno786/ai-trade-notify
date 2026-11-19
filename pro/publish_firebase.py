"""Saves the daily ML picks to Firestore (picks/latest) so the AI Trade Notify apps show them,
and sends one push notification to the 'signals' topic.  Used by the daily GitHub workflow.
Needs the FIREBASE_SERVICE_ACCOUNT environment variable (the same GitHub secret as the hourly bot)."""
import json
import os
import sys
import time

APP_URL = os.environ.get("APP_URL", "")


def main(path):
    res = json.load(open(path))
    raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if not raw:
        print("No FIREBASE_SERVICE_ACCOUNT - skipping Firebase upload")
        return
    import firebase_admin
    from firebase_admin import credentials, firestore, messaging
    firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
    db = firestore.client()
    model, picks = res.get("model") or {}, res.get("picks") or []
    doc = {
        "model": model, "picks": picks, "stats": res.get("stats", {}),
        "generatedAt": res.get("generated_at"), "updatedMs": int(time.time() * 1000),
        "horizonDays": 5, "disclaimer": "Signals are probabilities, not guarantees. Not financial advice.",
    }
    db.collection("picks").document("latest").set(json.loads(json.dumps(doc, default=str)))
    print(f"Saved {len(picks)} picks to Firestore picks/latest")

    if picks and model.get("has_edge"):
        body = " · ".join(f"{p['signal']} {p['ticker']} ({p['probability'] * 100:.0f}%)" for p in picks)
        title = "📈 Today's 5-day picks"
    elif not model.get("has_edge"):
        title, body = "Daily scan: no edge today", "The model did not beat simple guessing on its exam. Don't trade on it today."
    else:
        title, body = "Daily scan: no trade today", "No setup passed the accuracy filters. Waiting is a position too."
    msg = messaging.Message(
        topic="signals", notification=messaging.Notification(title=title, body=body),
        android=messaging.AndroidConfig(priority="high"),
        webpush=messaging.WebpushConfig(fcm_options=messaging.WebpushFCMOptions(link=APP_URL))
        if APP_URL.startswith("https://") else None)
    try:
        messaging.send(msg)
        print("Push sent:", title)
    except Exception as e:
        print("Push failed:", e)


if __name__ == "__main__":
    main(sys.argv[1])
