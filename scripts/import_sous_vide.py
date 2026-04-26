import json
import re
from pathlib import Path

import requests
from bs4 import BeautifulSoup

URL = "https://www.cuisinebassetemperature.com/tableau-recapitulatif-de-cuisson-a-basse-temperature/"
OUT = Path("assets/data/sous_vide.json")

GROUP_MAP = {
    "BOEUF": "bœuf",
    "VEAU": "veau",
    "PORC": "porc",
    "AGNEAU": "agneau",
    "POULET, PINTADE": "volaille",
    "CANARD": "canard",
    "VOLAILLES AUTRES": "volaille",
    "CERF": "gibier",
    "CHEVREUIL": "gibier",
    "LAPIN": "lapin",
    "POISSONS D’EAU DOUCE SANS PEAU": "poisson",
    "POISSONS D’EAU DOUCE AVEC PEAU": "poisson",
    "POISSONS DE MER SANS PEAU": "poisson",
    "POISSONS DE MER AVEC PEAU": "poisson",
    "CRUSTACES": "crustacés",
    "COQUILLAGES": "coquillages",
    "CEPHALOPODES": "céphalopodes",
    "OEUFS": "œuf",
    "LEGUMES": "légumes",
    "FRUITS": "fruits",
    "FOIE GRAS": "foie gras",
}

SKIP_PREFIXES = (
    "COPYRIGHT",
    "TOUTE REPRODUCTION",
    "WWW.CUISINEBASSETEMPERATURE.COM",
    "PHILIPPE BARATTE",
    "MOYENS",
    "DUREE DE",
    "DUREE DE CUISSON",
    "SOUS VIDE",
    "TEMPERATURE",
    "BAIN-MARIE",
    "FOUR MIXTE",
    "SAISIR A LA POELE",
    "A POINT DE CUISSON",
    "A COEUR",
    "POIDS/EPAISSEURS",
)

def clean_line(s: str) -> str:
    s = s.replace("\xa0", " ")
    s = re.sub(r"【\d+†[^】]*】", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s

def normalize_heading(lines, i):
    line = lines[i]
    if line == "POULET," and i + 1 < len(lines) and lines[i + 1] == "PINTADE":
        return "POULET, PINTADE", i + 1
    if line == "VOLAILLES" and i + 1 < len(lines) and lines[i + 1] == "AUTRES":
        return "VOLAILLES AUTRES", i + 1
    if line == "POISSONS" and i + 3 < len(lines) and lines[i + 1] == "D’EAU" and lines[i + 2] == "DOUCE" and lines[i + 3] == "SANS PEAU":
        return "POISSONS D’EAU DOUCE SANS PEAU", i + 3
    if line == "POISSONS" and i + 3 < len(lines) and lines[i + 1] == "D’EAU" and lines[i + 2] == "DOUCE" and lines[i + 3] == "AVEC PEAU":
        return "POISSONS D’EAU DOUCE AVEC PEAU", i + 3
    if line == "POISSONS" and i + 3 < len(lines) and lines[i + 1] == "DE MER" and lines[i + 2] == "SANS" and lines[i + 3] == "PEAU":
        return "POISSONS DE MER SANS PEAU", i + 3
    if line == "POISSONS" and i + 3 < len(lines) and lines[i + 1] == "DE MER" and lines[i + 2] == "AVEC" and lines[i + 3] == "PEAU":
        return "POISSONS DE MER AVEC PEAU", i + 3
    return line, i

def is_heading(s: str) -> bool:
    return s in GROUP_MAP

def split_fields(line: str):
    m = re.search(r"\b(\d+\s*h(?:\s*\d+\s*min)?|\d+\s*heures?|\d+\s*heure|\d+\s*min(?:\s*\d+)?|\d+\s*à\s*\d+\s*min)\b", line, flags=re.I)
    if not m:
        return None
    left = line[:m.start()].strip(" -")
    rest = line[m.start():].strip()

    m2 = re.match(r"^(?P<time>\d+\s*h(?:\s*\d+\s*min)?|\d+\s*heures?|\d+\s*heure|\d+\s*min(?:\s*\d+)?|\d+\s*à\s*\d+\s*min)\s+(?P<tail>.+)$", rest, flags=re.I)
    if not m2:
        return None

    time = m2.group("time").strip()
    tail = m2.group("tail").strip()

    temp_match = re.search(r"(\d+\s*°C(?:\s*à\s*\d+\s*°C)?)", tail, flags=re.I)
    if not temp_match:
        return None

    temp = temp_match.group(1).replace(" ", "")
    after_temp = tail[temp_match.end():].strip(" -")
    after_temp = re.sub(r"\s+", " ", after_temp).strip()

    temp = temp.replace("°c", "°C").replace("° C", "°C")
    time = time.replace("heure", "h").replace("heures", "h")
    time = re.sub(r"\s+", " ", time).strip()

    return left, time, temp, after_temp

def classify_texture(note: str) -> str:
    n = note.lower()
    if "mi-cuit" in n:
        return "mi-cuit"
    if "confit" in n:
        return "confit"
    if "bleu" in n:
        return "bleu"
    if "saignant" in n:
        return "saignant"
    if "rosé" in n:
        return "rosé"
    if "crémeux" in n:
        return "crémeux"
    if "nacré" in n:
        return "nacré"
    if "fondant" in n:
        return "fondant"
    if "à point" in n or "a point" in n:
        return "à point"
    if "bien cuit" in n:
        return "bien cuit"
    return ""

html = requests.get(URL, timeout=30)
html.raise_for_status()
soup = BeautifulSoup(html.text, "lxml")
text = soup.get_text("\n")
raw_lines = [clean_line(x) for x in text.splitlines()]
raw_lines = [x for x in raw_lines if x]

start = None
for idx, line in enumerate(raw_lines):
    if "TABLEAUX DE CUISSON SOUS VIDE À BASSE TEMPÉRATURE" in line.upper() or "TABLEAUX DE CUISSON SOUS VIDE A BASSE TEMPERATURE" in line.upper():
        start = idx + 1
        break

if start is None:
    raise RuntimeError("Section sous-vide introuvable")

lines = raw_lines[start:]

entries = []
current_group = None
i = 0
buffer = []

def flush_buffer(buf, current_group):
    out = []
    if not current_group:
        return out
    if not buf:
        return out
    line = " ".join(buf)
    line = re.sub(r"\s+", " ", line).strip()
    fields = split_fields(line)
    if fields:
        title, time, temp, note = fields
        item = {
            "title": title,
            "group": GROUP_MAP[current_group],
            "temp": temp,
            "time": time,
            "texture": classify_texture(note),
            "note": note,
        }
        out.append(item)
    return out

while i < len(lines):
    line = lines[i]
    heading, new_i = normalize_heading(lines, i)
    if is_heading(heading):
        entries.extend(flush_buffer(buffer, current_group))
        buffer = []
        current_group = heading
        i = new_i + 1
        continue

    upper = line.upper()
    if upper.startswith(SKIP_PREFIXES):
        entries.extend(flush_buffer(buffer, current_group))
        buffer = []
        i += 1
        continue

    if line == "—" or line == "-":
        i += 1
        continue

    if current_group:
        if split_fields(line):
            entries.extend(flush_buffer(buffer, current_group))
            buffer = [line]
        else:
            if buffer:
                buffer.append(line)
        i += 1
        continue

    i += 1

entries.extend(flush_buffer(buffer, current_group))

seen = set()
final = []
for e in entries:
    key = (e["group"], e["title"], e["temp"], e["time"], e["note"])
    if key not in seen:
        seen.add(key)
        final.append(e)

OUT.write_text(json.dumps(final, ensure_ascii=False, indent=2))
print(f"{len(final)} entrées écrites dans {OUT}")
