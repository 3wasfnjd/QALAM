import hashlib, os, pathlib, shutil, urllib.request, zipfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = pathlib.Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'shadda-deps'
CACHE.mkdir(parents=True, exist_ok=True)
VERSION = '4.7.2-stable'
BASE = f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}/'

def download(url, name):
    p = CACHE / name
    if not p.exists():
        with urllib.request.urlopen(url, timeout=120) as r, p.open('wb') as f:
            shutil.copyfileobj(r, f)
    return p

def digest(p, algorithm='sha256'):
    h = hashlib.new(algorithm)
    with p.open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''): h.update(block)
    return h.hexdigest()

sums = download(BASE+'SHA512-SUMS.txt', 'SHA512-SUMS.txt')
assert digest(sums) == 'b8bdff6704f833e7a021df16ec08e1478edd5a285c1f894929b91a7f74a5c7c0', 'Official checksums changed'
checksums = {line.split()[-1].lstrip('*'): line.split()[0] for line in sums.read_text().splitlines() if line.strip()}
for name in ['Godot_v4.7.2-stable_linux.x86_64.zip', 'Godot_v4.7.2-stable_export_templates.tpz']:
    p = download(BASE+name, name)
    assert digest(p, 'sha512') == checksums[name], f'SHA-512 mismatch: {name}'
    with zipfile.ZipFile(p) as z:
        if name.endswith('.zip'): z.extractall(CACHE)
        else:
            target = pathlib.Path.home()/'.local/share/godot/export_templates/4.7.2.stable'
            target.mkdir(parents=True, exist_ok=True)
            for member in z.infolist():
                if not member.is_dir():
                    dst=target/pathlib.Path(member.filename).name
                    with z.open(member) as r, dst.open('wb') as f: shutil.copyfileobj(r,f)
engine = CACHE/'Godot_v4.7.2-stable_linux.x86_64'
engine.chmod(0o755)
# This title only runs on a headset. The vendor's hybrid-app library defaults
# head tracking to optional; override that in the app manifest before Gradle's
# manifest merger runs. The official archive was verified above, before this
# deliberate project-specific configuration.
android_source = pathlib.Path.home()/'.local/share/godot/export_templates/4.7.2.stable/android_source.zip'
configured_source = android_source.with_suffix('.configured.zip')
patched = 0
with zipfile.ZipFile(android_source) as source, zipfile.ZipFile(configured_source, 'w') as configured:
    for member in source.infolist():
        data = source.read(member.filename)
        if member.filename.endswith('AndroidManifest.xml') and b'.GodotApp' in data and b'<application' in data:
            android_ns = 'http://schemas.android.com/apk/res/android'
            tools_ns = 'http://schemas.android.com/tools'
            ET.register_namespace('android', android_ns)
            ET.register_namespace('tools', tools_ns)
            manifest = ET.fromstring(data)
            for existing in list(manifest.findall('uses-feature')):
                if existing.get('{'+android_ns+'}name') == 'android.hardware.vr.headtracking':
                    manifest.remove(existing)
            feature = ET.Element('uses-feature', {
                '{'+android_ns+'}name': 'android.hardware.vr.headtracking',
                '{'+android_ns+'}required': 'true',
                '{'+android_ns+'}version': '1',
                '{'+tools_ns+'}node': 'replace',
            })
            manifest.insert(0, feature)
            data = ET.tostring(manifest, encoding='utf-8', xml_declaration=True)
            patched += 1
            print('Configured required headset tracking:', member.filename)
        configured.writestr(member, data)
assert patched >= 1, 'No app manifest found in the verified Android template'
configured_source.replace(android_source)
plugin=download('https://github.com/GodotVR/godot_openxr_vendors/releases/download/5.1.0-stable/godotopenxrvendorsaddon.zip','vendors.zip')
assert digest(plugin)=='6a838dbdf4115549e4511ebee0da9a5dcc8f9f6258d4cc2f2ee57a907a3e2911'
unpack = CACHE/'vendor-unpack'
with zipfile.ZipFile(plugin) as z: z.extractall(unpack)
addon = next(unpack.glob('**/addons/godotopenxrvendors'))
shutil.copytree(addon, ROOT/'addons/godotopenxrvendors', dirs_exist_ok=True)
assert (ROOT/'addons/godotopenxrvendors/plugin.gdextension').is_file()
assert list((ROOT/'addons/godotopenxrvendors/.bin/linux').rglob('*.so'))
settings=pathlib.Path.home()/'.config/godot/editor_settings-4.7.tres'
settings.parent.mkdir(parents=True,exist_ok=True)
settings.write_text('[gd_resource type="EditorSettings" format=3]\n[resource]\n'+
    f'export/android/android_sdk_path = "{os.environ["ANDROID_HOME"]}"\n'+
    f'export/android/java_sdk_path = "{os.environ["JAVA_HOME"]}"\n'+
    f'export/android/debug_keystore = "{pathlib.Path.home()}/.android/debug.keystore"\n'+
    'export/android/debug_keystore_user = "androiddebugkey"\nexport/android/debug_keystore_pass = "android"\n')
preset=ROOT/'export_presets.cfg'
preset.write_text(preset.read_text().replace('version/code=1', 'version/code='+os.environ.get('GITHUB_RUN_NUMBER','1')))
with open(os.environ['GITHUB_PATH'],'a') as f:f.write(str(CACHE)+'\n')
shutil.copy2(engine,CACHE/'godot')
(ROOT/'build').mkdir(exist_ok=True)
(ROOT/'build/.gdignore').write_text('')
(ROOT/'build/versions.txt').write_text('QALAM v0.1.0\nGodot 4.7.2-stable\nOpenXR Vendors 5.1.0-stable\nJDK 17\nSDK compile 36 / target 34 / min 29\nNDK 29.0.14206865\nMobile Vulkan\nDevelopment signature; not tested on Quest 3\n')
print('Pinned Godot SHA-512 and official vendor SHA-256 verified')
