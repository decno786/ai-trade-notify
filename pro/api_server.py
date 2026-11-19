"""
api_server.py - Flask server for the picks + a phone-friendly dashboard
======================================================================

  /             dark mobile dashboard (signal cards)
  /api/signals  the same data as JSON (for apps)
  /health       "ok"

A background thread refreshes the picks every REFRESH_MINUTES. It uses the
ML model (ml_model.py) when model.joblib exists, otherwise the rule-based
scanner (scanner_alerts.py).

Run:   python api_server.py         -> open http://<this-computer-ip>:5000
Production (cloud server):  pip install waitress && waitress-serve --port=5000 api_server:app
Not financial advice.
"""
import os
import threading
import time
import traceback

from flask import Flask, jsonify, Response

import ml_model as ml
import scanner_alerts as sa
import trading_bot as tb

# ============================== SETTINGS ==============================
HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", 5000))
REFRESH_MINUTES = 60
APP_TITLE = "AI Trade Notify"
# ======================================================================

app = Flask(__name__)
STATE = {"status": "starting", "picks": [], "model": None, "source": None,
         "updated_at": None, "error": None, "disclaimer": tb.DISCLAIMER}
_lock = threading.Lock()


def refresh_once():
    try:
        if os.path.exists(ml.MODEL_FILE):
            res = ml.find_picks()
            source = "ml"
        else:
            picks, stats = sa.scan_rules()
            res = {"model": None, "picks": picks, "stats": stats}
            source = "rules"
        with _lock:
            STATE.update(status="ok", picks=res["picks"], model=res.get("model"), stats=res.get("stats"),
                         source=source, updated_at=time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime()), error=None)
    except Exception as e:
        traceback.print_exc()
        with _lock:
            STATE.update(status="error", error=str(e))


def refresher():
    while True:
        refresh_once()
        time.sleep(REFRESH_MINUTES * 60)


@app.route("/api/signals")
def api_signals():
    with _lock:
        return jsonify(STATE)


@app.route("/health")
def health():
    return "ok"


@app.route("/")
def dashboard():
    return Response(PAGE.replace("{{TITLE}}", APP_TITLE), mimetype="text/html")


PAGE = r"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{{TITLE}}</title>
<meta name="theme-color" content="#0A0F1E">
<style>
:root{--bg:#0A0F1E;--card:#131A2F;--card2:#1B2442;--line:#263052;--text:#EAF0FF;--mut:#8C98BC;--up:#22C55E;--dn:#F0445A;--warn:#F5A524;--acc:#5B7CFF;--acc2:#A35CFF}
*{box-sizing:border-box}html{background:#0A0F1E}body{margin:0;background:linear-gradient(180deg,#111833,#0A0F1E 45%) fixed;color:var(--text);font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;min-height:100vh}
.wrap{max-width:560px;margin:0 auto;padding:16px 14px 40px}
.top{display:flex;align-items:center;gap:10px;margin-bottom:6px}
.logo{width:40px;height:40px;border-radius:12px;background:linear-gradient(135deg,var(--acc),var(--acc2));display:grid;place-items:center;box-shadow:0 8px 20px rgba(91,124,255,.4)}
h1{font-size:21px;margin:0}.sub{color:var(--mut);font-size:13px;margin-bottom:14px}
.card{background:linear-gradient(135deg,var(--card2),var(--card));border:1px solid var(--line);border-radius:18px;padding:16px;margin-bottom:12px;animation:up .5s both}
@keyframes up{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
.warn{border-color:var(--warn);color:var(--warn);font-weight:600}
.row{display:flex;justify-content:space-between;align-items:center}
.tk{font-size:22px;font-weight:800}.pill{padding:3px 10px;border-radius:99px;font-weight:800;font-size:13px}
.BUY .pill{background:rgba(34,197,94,.15);color:var(--up)}.SELL .pill{background:rgba(240,68,90,.15);color:var(--dn)}
.BUY{border-left:4px solid var(--up)}.SELL{border-left:4px solid var(--dn)}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:12px}
.grid div{background:rgba(10,15,30,.5);border-radius:12px;padding:8px}.grid span{display:block;font-size:11px;color:var(--mut)}.grid b{font-size:15px}
.g{color:var(--up)}.r{color:var(--dn)}.m{color:var(--mut);font-size:13px}
.foot{color:var(--mut);font-size:12px;text-align:center;margin-top:16px}
</style></head><body><div class="wrap">
<div class="top"><div class="logo"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/></svg></div><h1>{{TITLE}}</h1></div>
<div class="sub" id="sub">Loading...</div><div id="out"></div>
<div class="foot">Signals are probabilities, not guarantees. Use the stop-loss, risk max 1-2% per trade, paper-trade first. Not financial advice.</div>
</div><script>
const f=x=>Math.abs(x)>=100?x.toLocaleString(undefined,{maximumFractionDigits:2}):Math.abs(x)>=1?x.toFixed(4):x.toPrecision(4);
async function load(){
 try{const s=await (await fetch('api/signals',{cache:'no-store'})).json();
  const m=s.model;let h='';
  document.getElementById('sub').textContent=(s.source==='ml'?'ML 5-day picks':'Rule-based picks')+(s.updated_at?' · updated '+s.updated_at:'')+(s.status==='starting'?' · first scan running (a few minutes)':'');
  if(s.status==='error')h+=`<div class="card warn">Error: ${s.error}</div>`;
  if(m&&!m.has_edge)h+=`<div class="card warn">⚠️ NO EDGE - don't trade. The model did not beat simple guessing on its ${m.exam.start} → ${m.exam.end} exam.</div>`;
  if(m)h+=`<div class="card m">Model: ${m.name} · confident-call accuracy ${(100*(m.confident_accuracy||0)).toFixed(0)}% vs baseline ${(100*m.baseline).toFixed(0)}% · trained ${m.trained_at}</div>`;
  if(s.status!=='starting'&&!s.picks.length)h+=`<div class="card">No trade today. Nothing passed the accuracy filters. Waiting is a position too.</div>`;
  s.picks.forEach((p,i)=>{const pl=p.plan||{},hr=p.hours;
   h+=`<div class="card ${p.signal}" style="animation-delay:${i*.08}s"><div class="row"><span class="tk">${p.ticker}</span><span class="pill">${p.signal}</span></div>
   <div class="m">${p.probability?`${(p.probability*100).toFixed(0)}% chance of going ${p.signal==='BUY'?'up':'down'} in 5 days · `:`score ${p.score} · `}past accuracy ${(p.accuracy*100).toFixed(0)}% of ${p.samples}</div>
   <div class="grid"><div><span>Entry</span><b>${f(pl.entry)}</b></div><div><span>Stop</span><b class="r">${f(pl.stop)}</b></div><div><span>Target</span><b class="g">${f(pl.target)}</b></div>
   <div><span>Best buy (Doha)</span><b>${hr?hr.buy_hour:'-'}</b></div><div><span>Best sell (Doha)</span><b>${hr?hr.sell_hour:'-'}</b></div><div><span>Risk</span><b>$${pl.risk_money}</b></div></div></div>`});
  document.getElementById('out').innerHTML=h;
 }catch(e){document.getElementById('sub').textContent='Cannot reach the server: '+e.message}
}
load();setInterval(load,300000);
</script></body></html>"""


threading.Thread(target=refresher, daemon=True).start()

if __name__ == "__main__":
    app.run(host=HOST, port=PORT, debug=False)
