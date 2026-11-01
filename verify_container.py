import os
import sys
import subprocess

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, 'tools', 'vendor'))
import xtapp

print("=== VERIFYING XTAPP CONTAINER FOR LICORICE FIRMWARE ===")

# 1. Run xtpack.py to build fresh inkarcana.xtapp
pack_cmd = [sys.executable, "xtpack.py", ".", "-o", "inkarcana.xtapp"]
res = subprocess.run(pack_cmd, cwd=here, capture_output=True, text=True)
print(res.stdout)
if res.returncode != 0:
    print(res.stderr)
    raise SystemExit("xtpack.py failed")

# 2. Check file size against firmware ceiling
xtapp_path = os.path.join(here, "inkarcana.xtapp")
file_size = os.path.getsize(xtapp_path)
max_allowed = xtapp.LICORICE_FILE_MAX  # 0x100000 = 1,048,576 bytes (1 MB)

print(f"File size: {file_size} bytes ({file_size / 1024:.1f} KB)")
print(f"Firmware limit: {max_allowed} bytes (1024 KB)")
assert file_size <= max_allowed, f"File size {file_size} exceeds firmware limit {max_allowed}!"
print(f"Headroom under 1 MB limit: {max_allowed - file_size} bytes ({(max_allowed - file_size)/1024:.1f} KB)")

# 3. Read and validate Licorice container header
raw_data = open(xtapp_path, "rb").read()
head, manifest = xtapp.read_licorice_container(raw_data)
print("Container Header:", head)
print("Manifest:", manifest)

# 4. Validate manifest fields against Licorice firmware expectations (FUN_42108590)
assert manifest["app_id"] == "inkarcana", "app_id mismatch"
assert manifest["display_name"] == "InkArcana", "display_name mismatch"
assert manifest["version"] == "1.0", "version mismatch"
assert manifest["entry"] == "index.lua", "entry mismatch"
assert manifest["dek_wrap_alg"] == xtapp.LICORICE_ALG, "dek_wrap_alg mismatch"
assert manifest["dek_wrap_key_id"] == xtapp.LICORICE_KEY_ID, "dek_wrap_key_id mismatch"

# 5. Check section table offsets & bounds (FUN_42108380 / FUN_42108f68)
sec = xtapp.licorice_sections(raw_data)
print("Container Sections:", sec)
assert "code" in sec and sec["code"][1] > 0, "Missing or empty code section"
assert sec["code"][1] <= xtapp.LICORICE_INMEM_MAX, f"Code section {sec['code'][1]} exceeds RAM limit {xtapp.LICORICE_INMEM_MAX}"

# 6. Check Icons section (app_icon_s for Mini Apps grid)
assert "icons" in sec and sec["icons"][1] > 0, "Missing or empty icons section"
icons_blob = raw_data[sec["icons"][0]:sec["icons"][0] + sec["icons"][1]]
assert icons_blob[:4] == b'XTAB', "Icons magic is not XTAB"
print("Icons section OK (XTAB present)")

print("=== ALL CONTAINER & FIRMWARE CHECKS PASSED ===")
