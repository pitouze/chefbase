import json
import re
from pathlib import Path

import requests
from bs4 import BeautifulSoup

URL = "https://www.cuisinebassetemperature.com/tableau-recapitulatif-de-cuisson-a-basse-temperature/"
OUT = Path("assets/data/sous_vide.json")

SITE_CATEGORIES = [
    "BOEUF",
    "VEAU",
    "PORC",
    "AGNEAU",
    "POULET, PINTADE",
    "CANARD",
    "VOLAILLES AUTRES",
    "CERF",
    "CHEVREUIL",
    "LAPIN",
    "POISSONS D’EAU DOUCE SANS PEAU",
    "POISSONS D’EAU DOUCE AVEC PEAU",
    "POISSONS DE MER SANS PEAU",
    "POISSONS DE MER AVEC PEAU",
    "CRUSTACES",
    "COQUILLAGES",
    "CEPHALOPODES",
    "OEUFS",
    "LEGUMES BRUTS, PARES, NETTOYES",
    "LEGUMES DIVERS",
    "FRUITS",
    "DIVERS",
    "FOIE GRAS",
]

SKIP_LINES = {
    "COPYRIGHT © 2014 BARATTE PHILIPPE",
    "TOUTE REPRODUCTION INTERDITE SANS L’AUTORISATION DE L’AUTEUR. TOUS DROITS RÉSERVÉS.",
    "TOUTE REPRODUCTION INTERDITE SANS L’AUTORISATION DE L’AUTEUR. TOUS DROITS RÉSERVÉS",
    "WWW.CUISINEBASSETEMPERATURE.COM",
    "PHILIPPE BARATTE, VOTRE CHEF TOQUÉ DU THERMOMÈTRE",
    "PHILIPPE BARATTE, VOTRE CHEF TOQUE DU THERMOMETRE",
    "POIDS/EPAISSEURS",
    "MOYENS",
    "DUREE DE CUISSON",
    "DUREE DE",
    "CUISSON",
    "SOUS VIDE",
    "TEMPERATURE:",
    "BAIN-MARIE",
    "FOUR MIXTE",
    "TEMPERATURE",
    "DE CUISSON",
    "A COEUR",
    "A POINT DE",
    "SAISIR A LA POELE SUR TOUTES LES FACES LORS DU SERVICE A POINT DE CUISSON",
}

TIME_RE = re.compile(
    r"\b(?:\d+\s*h(?:\s*\d+\s*min)?|\d+\s*heures?|\d+\s*heure|\d+\s*min(?:\s*\d+)?|\d+\s*à\s*\d+\s*min)\b",
    re.IGNORECASE,
)
TEMP_RE = re.compile(
    r"\b\d+\s*°\s*C(?:\s*à\s*\d+\s*°\s*C)?\b",
    re.IGNORECASE,
)

def clean(s: str) -> str:
    s = s.replace("\xa0", " ")
    s = s.replace("’", "’")
    s = re.sub(r"\s+", " ", s).strip()
    return s

def norm(s: str) -> str:
    s = clean(s).upper()
    s = s.replace("Œ", "OE")
    s = s.replace("É", "E").replace("È", "E").replace("Ê", "E").replace("Ë", "E")
    s = s.replace("À", "A").replace("Â", "A")
    s = s.replace("Ù", "U").replace("Û", "U")
    s = s.replace("Î", "I").replace("Ï", "I")
    s = s.replace("Ô", "O")
    s = s.replace("Ç", "C")
    return s

CATEGORY_MAP = {norm(x): x for x in SITE_CATEGORIES}
SKIP_MAP = {norm(x) for x in SKIP_LINES}

def classify_texture(text: str) -> str:
    t = norm(text)
    if "MI-CUIT" in t:
        return "mi-cuit"
    if "CONFIT" in t:
        return "confit"
    if "BLEU" in t:
        return "bleu"
    if "SAIGNANT" in t:
        return "saignant"
    if "ROSE" in t:
        return "rosé"
    if "NACRE" in t:
        return "nacré"
    if "CREMEUX" in t:
        return "crémeux"
    if "FONDANT" in t:
        return "fondant"
    if "A POINT" in t:
        return "à point"
    if "BIEN CUIT" in t:
        return "bien cuit"
    return ""

def match_category(lines, i):
    max_len = min(4, len(lines) - i)
    for n in range(max_len, 0, -1):
        candidate = " ".join(lines[i:i+n])
        candidate_n = norm(candidate)
        if candidate_n in CATEGORY_MAP:
            return CATEGORY_MAP[candidate_n], n
    return None, 0

def parse_entry(line: str, category: str):
    line = clean(line)
    time_match = TIME_RE.search(line)
    if not time_match:
        return None

    temp_match = TEMP_RE.search(line, time_match.end())
    if not temp_match:
        return None

    title = clean(line[:time_match.start()])
    time = clean(time_match.group(0))
    temp = clean(temp_match.group(0))
    tail = clean(line[temp_match.end():]).strip("- ").strip()

    if not title:
        return None

    return {
        "title": title,
        "siteCategory": category,
        "temp": temp,
        "time": time,
        "texture": classify_texture(tail),
        "note": tail,
    }

html = requests.get(URL, timeout=30)
html.raise_for_status()

soup = BeautifulSoup(html.text, "lxml")
lines = [clean(x) for x in soup.get_text("\n").splitlines()]
lines = [x for x in lines if x]

start_idx = None
for idx, line in enumerate(lines):
    if "TABLEAUX DE CUISSON SOUS VIDE" in norm(line):
        start_idx = idx + 1
        break

if start_idx is None:
    raise RuntimeError("Section sous-vide introuvable")

lines = lines[start_idx:]

entries = []
current_category = None
buffer = []

def flush_buffer():
    global buffer
    if not buffer or not current_category:
        buffer = []
        return
    merged = clean(" ".join(buffer))
    item = parse_entry(merged, current_category)
    if item:
        entries.append(item)
    buffer = []

i = 0
while i < len(lines):
    line = lines[i]
    line_n = norm(line)

    if line_n.startswith("POSTED ") or line_n.startswith("BONJOUR") or line_n.startswith("MERCI"):
        break

    category, consumed = match_category(lines, i)
    if category:
        flush_buffer()
        current_category = category
        i += consumed
        continue

    if line_n in SKIP_MAP:
        flush_buffer()
        i += 1
        continue

    if not current_category:
        i += 1
        continue

    if TIME_RE.search(line) and buffer:
        flush_buffer()
        buffer = [line]
    else:
        buffer.append(line)

    i += 1

flush_buffer()

deduped = []
seen = set()
for e in entries:
    key = (e["siteCategory"], e["title"], e["temp"], e["time"], e["note"])
    if key not in seen:
        seen.add(key)
        deduped.append(e)

OUT.write_text(json.dumps(deduped, ensure_ascii=False, indent=2))
print(f"{len(deduped)} entrées écrites dans {OUT}")
