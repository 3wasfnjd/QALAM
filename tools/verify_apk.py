import hashlib,json,os,pathlib,re,subprocess,zipfile,xml.etree.ElementTree as ET
p=pathlib.Path('build/QALAM-Quest-AR-v0.1.0.apk')
sdk=pathlib.Path(os.environ['ANDROID_HOME'])
analyzer=sdk/'cmdline-tools/latest/bin/apkanalyzer'
xml=subprocess.check_output([str(analyzer),'manifest','print',str(p)],text=True)
pathlib.Path('build/AndroidManifest.xml').write_text(xml)
r=ET.fromstring(xml); a='{http://schemas.android.com/apk/res/android}'
assert r.attrib['package']=='com.abodengames.qalam'
uses=r.find('uses-sdk'); assert uses.get(a+'targetSdkVersion')=='34'
assert uses.get(a+'minSdkVersion')=='29'
meta={m.get(a+'name'):m.get(a+'value') for m in r.findall('.//meta-data')}
assert meta.get('com.oculus.supportedDevices')=='quest3|quest3s',meta
assert meta.get('com.oculus.ossplash')=='true'
features={f.get(a+'name'):f for f in r.findall('uses-feature')}
assert features['android.hardware.vr.headtracking'].get(a+'required')=='true'
assert features['com.oculus.feature.PASSTHROUGH'].get(a+'required')=='true'
permissions=[m.get(a+'name') for m in r.findall('uses-permission')]
assert 'android.permission.RECORD_AUDIO' not in permissions
assert 'android.permission.CAMERA' not in permissions
with zipfile.ZipFile(p) as z:
    abis={n.split('/')[1] for n in z.namelist() if n.startswith('lib/') and n.endswith('.so')}
    assert abis=={'arm64-v8a'},abis
    assert any(n.endswith('vr_splash.png') for n in z.namelist())
signer=sdk/'build-tools/36.1.0/apksigner'
verified=subprocess.check_output([str(signer),'verify','--verbose','--print-certs',str(p)],text=True)
cert=subprocess.check_output(['keytool','-exportcert','-keystore',str(pathlib.Path.home()/'.android/debug.keystore'),'-storepass','android','-alias','androiddebugkey'])
certificate_sha=hashlib.sha256(cert).hexdigest()
assert certificate_sha in verified.lower(),verified
sha=hashlib.sha256(p.read_bytes()).hexdigest()
report={'stage':'QALAM v0.1 — page one gameplay test','apk_built':True,'package_verified':True,'automated_tests_passed':True,'device_installed':False,'quest_gameplay_tested':False,'bytes':p.stat().st_size,'sha256':sha,'certificate_sha256':certificate_sha,'signing':'development','target_sdk':34,'abis':sorted(abis)}
pathlib.Path('build/package-report.json').write_text(json.dumps(report,indent=2))
pathlib.Path(str(p)+'.sha256').write_text(sha+'  '+p.name+'\n')
print(json.dumps(report,indent=2))
