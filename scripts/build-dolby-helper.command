#!/bin/zsh
# Build the app-owned read-only helper; the running app never installs tools.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
APP_DIR="${1:?Pass the owned app bundle destination}"
HELPER_DIR="$PROJECT_DIR/Tools/DolbyMetadataAudit"
if ! command -v cargo >/dev/null; then
  print -u2 "Building Dolby inspection requires Rust/Cargo. Install the documented development toolchain."
  exit 2
fi
python3 - "$HELPER_DIR" <<'PY'
from pathlib import Path
import hashlib,json,sys,tomllib
root=Path(sys.argv[1]);packages=json.loads((root/'DEPENDENCY-LICENSES.json').read_text())
locked={(p['name'],p['version']) for p in tomllib.loads((root/'Cargo.lock').read_text())['package'] if p['name']!='staxrip-dolby-metadata-audit'}
if locked!={(p['name'],p['version']) for p in packages}:
    raise SystemExit('The Dolby helper notice inventory does not match Cargo.lock.')
for package in packages:
    for entry in package['license_texts']:
        path=root/'LICENSES'/(package['name']+'-'+package['version'])/entry['name']
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:
            raise SystemExit('A Dolby helper dependency notice is missing or changed.')
PY
# The Rust standard library is linked into this executable but is not in Cargo.lock.
# Include the active toolchain's supplied library attribution catalog as well.
python3 - "$APP_DIR" <<'PYRUST'
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
root=Path(subprocess.check_output(['rustc','--print','sysroot'],text=True).strip())
docs=root/'share/doc/rustc'
required=[root/'LICENSE-MIT',root/'LICENSE-APACHE',root/'COPYRIGHT',docs/'COPYRIGHT-library.html']
if not all(p.is_file() for p in required) or not (docs/'licenses').is_dir():
    raise SystemExit('Rust toolchain library notices are missing. Use the documented Homebrew Rust development installation.')
target=Path(sys.argv[1])/'Contents/Resources/DolbyMetadataLicenses/RustLibrary'
target.mkdir(parents=True,exist_ok=True)
for p in required: shutil.copy2(p,target/p.name)
shutil.copytree(docs/'licenses',target/'licenses',dirs_exist_ok=True)
entries=[{'name':p.relative_to(target).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(target.rglob('*')) if p.is_file() and p.name!='BUILD-INVENTORY.json']
(target/'BUILD-INVENTORY.json').write_text(json.dumps({'compiler':subprocess.check_output(['rustc','--version'],text=True).strip(),'suppliedLibraryCatalog':True,'files':entries},indent=2)+'\n')
PYRUST
cargo build --locked --release --manifest-path "$HELPER_DIR/Cargo.toml" --target-dir "$HELPER_DIR/target"
mkdir -p "$APP_DIR/Contents/Helpers" "$APP_DIR/Contents/Resources/DolbyMetadataLicenses"
cp "$HELPER_DIR/target/release/staxrip-dolby-metadata-audit" "$APP_DIR/Contents/Helpers/staxrip-dolby-metadata-audit"
codesign --force --sign - "$APP_DIR/Contents/Helpers/staxrip-dolby-metadata-audit"
cp -R "$HELPER_DIR/LICENSES/." "$APP_DIR/Contents/Resources/DolbyMetadataLicenses/"
cp "$HELPER_DIR/LICENSE" "$APP_DIR/Contents/Resources/DolbyMetadataLicenses/LICENSE-staxrip-helper"
cp "$HELPER_DIR/DEPENDENCY-LICENSES.json" "$APP_DIR/Contents/Resources/DolbyMetadataLicenses/DEPENDENCY-LICENSES.json"
