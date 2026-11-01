import os
import sys
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "tools", "vendor"))
import xtapp

print("=== VERIFYING INKARCANA XTAPP ===")

pack_cmd = [sys.executable, "xtpack.py", ".", "-o", "inkarcana.xtapp"]
res = subprocess.run(pack_cmd, cwd=HERE, capture_output=True, text=True)
print(res.stdout)
if res.returncode != 0:
    print(res.stderr)
    raise SystemExit("xtpack.py failed")

xtapp_path = os.path.join(HERE, "inkarcana.xtapp")
file_size = os.path.getsize(xtapp_path)
max_allowed = xtapp.LICORICE_FILE_MAX
assert file_size <= max_allowed, f"package is {file_size} bytes; limit is {max_allowed}"
print(f"Package size: {file_size} bytes")
print(f"Headroom: {max_allowed - file_size} bytes")

raw = open(xtapp_path, "rb").read()
head, manifest = xtapp.read_licorice_container(raw)

assert manifest["app_id"] == "inkarcana"
assert manifest["display_name"] == "InkArcana"
assert manifest["version"] == "1.3.0"
assert manifest["entry"] == "index.lua"
assert manifest["api"] == "2.0"
assert manifest.get("permissions", []) == []
assert manifest["dek_wrap_alg"] == xtapp.LICORICE_ALG
assert manifest["dek_wrap_key_id"] == xtapp.LICORICE_KEY_ID

sections = xtapp.licorice_sections(raw)
assert "code" in sections and sections["code"][1] > 0
assert sections["code"][1] <= xtapp.LICORICE_INMEM_MAX
assert "data" in sections and sections["data"][1] > 0
assert "icons" in sections and sections["icons"][1] > 0

icon_off, icon_len = sections["icons"]
assert icon_len > 0
assert raw[icon_off:icon_off + 4] == b"XTAB"

print("Manifest: PASS")
print("Code/data/icons sections: PASS")
print("Licorice size limit: PASS")
print("=== CONTAINER VERIFICATION COMPLETED ===")
