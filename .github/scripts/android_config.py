"""Reads app/google-services.json and writes app/lib/firebase_config.dart.
Usage: android_config.py <google-services.json> <out.dart> <package name>"""
import json, sys

src, out, pkg = sys.argv[1], sys.argv[2], sys.argv[3]
g = json.load(open(src))
c = next((x for x in g.get("client", [])
          if x["client_info"].get("android_client_info", {}).get("package_name") == pkg), None)
if c is None:
    sys.exit(f"::error::google-services.json has no Android app with package name {pkg}.")
p = g["project_info"]
vals = {
    "fbApiKey": c["api_key"][0]["current_key"],
    "fbAndroidAppId": c["client_info"]["mobilesdk_app_id"],
    "fbSenderId": p["project_number"],
    "fbProjectId": p["project_id"],
    "fbStorageBucket": p.get("storage_bucket", ""),
}
with open(out, "w") as f:
    f.write("// Generated from google-services.json by the build robot.\n")
    for k, v in vals.items():
        f.write(f"const {k} = '{v}';\n")
print("Firebase config written for", pkg, "in project", p["project_id"])
