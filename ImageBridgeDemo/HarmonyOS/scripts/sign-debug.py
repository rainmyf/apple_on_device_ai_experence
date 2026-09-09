#!/usr/bin/env python3
"""Sign for an OpenHarmony development device using SDK's public test identity.
Retail HarmonyOS devices require their normal DevEco signing profile instead.
No device security settings are changed. Output is local to ignored signing/.
"""
from pathlib import Path
import subprocess, json, time, uuid, re, sys, shutil
root=Path(__file__).resolve().parents[1]
sdk=Path('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains')
jdk=Path('/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin')
out=root/'signing'; out.mkdir(exist_ok=True)
serial=sys.argv[1] if len(sys.argv)>1 else '4YM0124C06000107'
udid_out=subprocess.check_output([str(sdk/'hdc'),'-t',serial,'shell','bm','get','--udid'],text=True)
udid=re.search(r'\b[A-F0-9]{64}\b',udid_out).group()
store=str(out/'OpenHarmony.p12')
shutil.copy2(sdk/'lib/OpenHarmony.p12',store)
# This is the SDK-distributed public test keystore password, not a user credential.
password='123456'
base=[str(jdk/'java'),'-jar',str(sdk/'lib/hap-sign-tool.jar')]
for alias,name in [('cacert','ca.cer'),('rootcacert','root.cer')]:
 cert=subprocess.check_output([str(jdk/'keytool'),'-exportcert','-rfc','-alias',alias,'-keystore',store,'-storepass',password],stderr=subprocess.DEVNULL,text=True)
 (out/name).write_text(cert)
subprocess.run(base+['generate-app-cert','-keyAlias','openharmony application release','-keyPwd',password,'-issuer','C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA','-issuerKeyAlias','openharmony application ca','-issuerKeyPwd',password,'-subject','C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=ImageBridge Debug','-validity','30','-signAlg','SHA256withECDSA','-keystoreFile',store,'-keystorePwd',password,'-outForm','certChain','-rootCaCertFile',str(out/'root.cer'),'-subCaCertFile',str(out/'ca.cer'),'-outFile',str(out/'app.cer')],check=True)
leaf=re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', (out/'app.cer').read_text(), re.S).group()+'\n'
p=json.loads((sdk/'lib/UnsgnedDebugProfileTemplate.json').read_text())
p['uuid']=str(uuid.uuid4()); p['validity']={'not-before':int(time.time())-3600,'not-after':int(time.time())+30*86400}
p['bundle-info']['bundle-name']='com.rain.imagebridge';p['bundle-info']['development-certificate']=leaf
p['debug-info']['device-ids']=[udid];p['acls']['allowed-acls']=[];p['permissions']['restricted-permissions']=[]
(out/'profile.json').write_text(json.dumps(p,indent=2))
base=[str(jdk/'java'),'-jar',str(sdk/'lib/hap-sign-tool.jar')]
subprocess.run(base+['sign-profile','-mode','localSign','-keyAlias','openharmony application profile debug','-keyPwd',password,'-profileCertFile',str(sdk/'lib/OpenHarmonyProfileDebug.pem'),'-inFile',str(out/'profile.json'),'-signAlg','SHA256withECDSA','-keystoreFile',store,'-keystorePwd',password,'-outFile',str(out/'profile.p7b')],check=True)
subprocess.run(base+['sign-app','-mode','localSign','-keyAlias','openharmony application release','-keyPwd',password,'-appCertFile',str(out/'app.cer'),'-profileFile',str(out/'profile.p7b'),'-inFile',str(root/'entry/build/default/outputs/default/entry-default-unsigned.hap'),'-signAlg','SHA256withECDSA','-keystoreFile',store,'-keystorePwd',password,'-outFile',str(out/'ImageBridge-signed.hap'),'-compatibleVersion','18'],check=True)
print('Signed:',out/'ImageBridge-signed.hap')
