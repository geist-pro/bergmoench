#!/usr/bin/env python3
"""TestFlight beta setup for Bergmönch through the App Store Connect API. Each step reads its result back.

    scripts/testflight_beta.py info | group | build <n> | submit <n> | status

  info        beta description, feedback e-mail, URLs, beta review contact and notes
  group       external group "Public beta" with a public link
  build <n>   put build <n> into the group and set its "What to Test"
  submit <n>  send build <n> to Beta App Review
  status      group, public link, builds and their review state

Reads scripts/release.local.env (not in git): ASC_APP_ID, ASC_KEY_ID, ASC_ISSUER_ID, optional ASC_KEY_PATH,
BETA_FEEDBACK_EMAIL, BETA_CONTACT_FIRST, BETA_CONTACT_LAST, BETA_CONTACT_EMAIL, BETA_CONTACT_PHONE.
Needs PyJWT with cryptography.
"""
import json, os, pathlib, sys, time, urllib.error, urllib.parse, urllib.request
import jwt

ROOT = pathlib.Path(__file__).resolve().parent
ENV = dict(os.environ)
for line in (ROOT / "release.local.env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.split("=", 1)
        ENV.setdefault(k.replace("export ", "").strip(), v.strip().strip("'\""))
APP = ENV["ASC_APP_ID"]
KEY = pathlib.Path(os.path.expanduser(ENV.get("ASC_KEY_PATH") or f"~/.appstoreconnect/private_keys/AuthKey_{ENV['ASC_KEY_ID']}.p8")).read_text()

SITE = "https://apps.geist.pro/bergmoench/"
GROUP, LINK_LIMIT = "Public beta", 500
DESCRIPTION = (
    "Bergmönch is a flashcard app. It opens Anki decks (.apkg) and schedules reviews with FSRS, "
    "on Anki's own backend. Everything stays on the device: no account, no tracking. Three course "
    "decks from TU Clausthal (Programmieren in German and English, Cooperation Systems) can be added on first run."
)
WHAT_TO_TEST = (
    "First beta. Please try:\n"
    "1. The first run: pick a course deck or import your own .apkg from Files.\n"
    "2. A review session, with two buttons or four (Settings), and undo.\n"
    "3. An exam date on a deck, the reading settings, and browse and search.\n"
    "4. The Home Screen widget, after a first review.\n"
    "A wrong card? The decks are open: github.com/geist-pro. Everything else: TestFlight feedback or e-mail."
)
REVIEW_NOTES = (
    "No account and no sign-in. On first run the app offers three bundled course decks; choose one "
    "(or skip and import an .apkg file) and start a review. Sync is optional and only talks to a "
    "self-hosted Anki sync server the user enters; it is not needed for review. The app makes no "
    "network requests otherwise. Source: https://github.com/geist-pro/bergmoench (AGPL-3.0)."
)


def call(method, path, params=None, body=None):
    url = "https://api.appstoreconnect.apple.com/v1/" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    now = int(time.time())
    tok = jwt.encode({"iss": ENV["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                     KEY, algorithm="ES256", headers={"kid": ENV["ASC_KEY_ID"]})
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None, method=method,
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path}: {e.code} {e.read().decode()[:1500]}")


def upsert(kind, existing, attrs, create_attrs, rel):
    if existing:
        call("PATCH", f"{kind}/{existing[0]['id']}", body={"data": {"type": kind, "id": existing[0]["id"], "attributes": attrs}})
    else:
        call("POST", kind, body={"data": {"type": kind, "attributes": {**create_attrs, **attrs}, "relationships": rel}})


def info():
    app = {"app": {"data": {"type": "apps", "id": APP}}}
    upsert("betaAppLocalizations", call("GET", f"apps/{APP}/betaAppLocalizations")["data"],
           {"description": DESCRIPTION, "feedbackEmail": ENV["BETA_FEEDBACK_EMAIL"], "marketingUrl": SITE,
            "privacyPolicyUrl": SITE + "privacy/"}, {"locale": "en-US"}, app)
    call("PATCH", f"betaAppReviewDetails/{APP}", body={"data": {"type": "betaAppReviewDetails", "id": APP, "attributes": {
        "contactFirstName": ENV["BETA_CONTACT_FIRST"], "contactLastName": ENV["BETA_CONTACT_LAST"],
        "contactEmail": ENV["BETA_CONTACT_EMAIL"], "contactPhone": ENV["BETA_CONTACT_PHONE"],
        "demoAccountRequired": False, "notes": REVIEW_NOTES}}})
    loc = call("GET", f"apps/{APP}/betaAppLocalizations")["data"][0]["attributes"]
    det = call("GET", f"apps/{APP}/betaAppReviewDetail")["data"]["attributes"]
    print("beta info:", loc["locale"], loc["privacyPolicyUrl"], "| review contact set:", bool(det["contactEmail"]),
          "notes:", len(det["notes"] or ""), "chars")


def group_id():
    return next((g["id"] for g in call("GET", f"apps/{APP}/betaGroups")["data"] if g["attributes"]["name"] == GROUP), None)


def group():
    attrs = {"publicLinkEnabled": True, "publicLinkLimitEnabled": True, "publicLinkLimit": LINK_LIMIT, "feedbackEnabled": True}
    gid = group_id()
    upsert("betaGroups", [{"id": gid}] if gid else [], attrs, {"name": GROUP}, {"app": {"data": {"type": "apps", "id": APP}}})
    g = call("GET", f"betaGroups/{group_id()}")["data"]["attributes"]
    print("group:", g["name"], "internal" if g.get("isInternalGroup") else "external", "| public link:", g.get("publicLink"))


def build_id(number):
    r = call("GET", "builds", {"filter[app]": APP, "filter[version]": number, "fields[builds]": "version,processingState"})["data"]
    if not r:
        raise SystemExit(f"build {number} not found (yet)")
    print("build", number, r[0]["attributes"]["processingState"])
    return r[0]["id"]


def build(number):
    bid, gid = build_id(number), group_id() or sys.exit("run the group step first")
    call("POST", f"betaGroups/{gid}/relationships/builds", body={"data": [{"type": "builds", "id": bid}]})
    upsert("betaBuildLocalizations", call("GET", f"builds/{bid}/betaBuildLocalizations")["data"],
           {"whatsNew": WHAT_TO_TEST}, {"locale": "en-US"}, {"build": {"data": {"type": "builds", "id": bid}}})
    print("build", number, "is in", GROUP, "with What to Test")


def submit(number):
    r = call("POST", "betaAppReviewSubmissions", body={"data": {"type": "betaAppReviewSubmissions",
             "relationships": {"build": {"data": {"type": "builds", "id": build_id(number)}}}}})
    print("beta review:", r["data"]["attributes"].get("betaReviewState"))


def status():
    gid = group_id()
    if gid:
        g = call("GET", f"betaGroups/{gid}")["data"]["attributes"]
        print("group:", g["name"], "| public link:", g.get("publicLink"), "| limit:", g.get("publicLinkLimit"))
    for b in call("GET", "builds", {"filter[app]": APP, "fields[builds]": "version,processingState,expired"})["data"]:
        d = call("GET", f"builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
        print("build", b["attributes"]["version"], b["attributes"]["processingState"],
              "| external:", d.get("externalBuildState"), "| internal:", d.get("internalBuildState"))


if __name__ == "__main__":
    args = sys.argv[1:] or sys.exit(__doc__)
    step = {"info": info, "group": group, "build": build, "submit": submit, "status": status}[args[0]]
    step(*args[1:2])
