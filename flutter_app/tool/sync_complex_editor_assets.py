#!/usr/bin/env python3
"""Copy existing public BookStark engines; default verifies, --sync updates owned copies."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,difflib
APP=Path(__file__).resolve().parents[1]
PROJECT=APP.parent
DEST=APP/'assets/complex_editors'
BEGIN='    # BEGIN BOOKSTARK COMPLEX EDITOR ASSETS'
END='    # END BOOKSTARK COMPLEX EDITOR ASSETS'
def digest(data):return hashlib.sha256(data).hexdigest()
def messages(path):
    result={}
    pattern=re.compile(r'^\s*("(?:[^"\\]|\\.)*")\s*:\s*("(?:[^"\\]|\\.)*")\s*,\s*(?://.*)?$')
    for line in path.read_text().splitlines():
        if not line.lstrip().startswith('"'):continue
        match=pattern.match(line)
        if not match:raise RuntimeError('Unsupported upstream translation literal; do not silently omit it')
        key,value=map(json.loads,match.groups())
        if key in result:raise RuntimeError('Duplicate upstream translation key')
        result[key]=value
    if not result:raise RuntimeError('Missing original editor translations')
    return result

def apply_owned_hunks(raw,patch):
 import re
 source=raw.decode("utf-8").splitlines(True)
 lines=patch.decode("utf-8").splitlines(True)
 result=[];cursor=0;index=0;count=0
 while index<len(lines):
  header=lines[index]
  if not header.startswith("@@"):index+=1;continue
  match=re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@",header)
  if not match:raise RuntimeError("Invalid unified hunk header")
  start=int(match[1])-1;old_count=int(match[2] or 1);new_count=int(match[4] or 1)
  if old_count==0:start=int(match[1])
  if start<cursor:raise RuntimeError("Overlapping or reordered hunks")
  result.extend(source[cursor:start]);old=[];new=[];index+=1
  while index<len(lines) and not lines[index].startswith(("@@","--- ","+++ ")):
   line=lines[index]
   if line[:1] not in (" ","+","-"):raise RuntimeError("Unsupported unified hunk line")
   if line[0]!="+":old.append(line[1:])
   if line[0]!="-":new.append(line[1:])
   index+=1
  if len(old)!=old_count or len(new)!=new_count or source[start:start+old_count]!=old:
   raise RuntimeError("Exact hunk position/content mismatch")
  result.extend(new);cursor=start+old_count;count+=1
 if not count:raise RuntimeError("No unified hunks")
 result.extend(source[cursor:])
 return "".join(result).encode("utf-8")

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sync',action='store_true');args=parser.parse_args()
    source=PROJECT/'static';records={};copies={}
    for path in sorted(source.rglob('*')):
        if path.is_symlink():raise RuntimeError('Public asset symlinks are not permitted')
        if not path.is_file():continue
        relative='static/'+str(path.relative_to(source));data=path.read_bytes()
        if len(data)>32*1024*1024:raise RuntimeError('Single editor asset exceeds bound')
        records[relative]={'source':str(path.relative_to(PROJECT)),'bytes':len(data),'sha256':digest(data)};copies[relative]=data
    # One explicit, reproducible adapter extension; original server static stays unchanged.
    relative='static/js/univer-adapter.js';original=copies[relative].decode()
    needle='    normalizeData: normalizeData,\n'
    if original.count(needle)!=1:raise RuntimeError('Review changed original Univer adapter before rebasing its owned hook')
    addition="    // Owned mobile-host hook: use the original engine's public result barrier.\n    waitForCalculation: async function(timeout) {\n      if (!running || !univerAPI || typeof univerAPI.getFormula !== 'function') throw new Error('formula_unavailable');\n      var formula = univerAPI.getFormula();\n      if (!formula || typeof formula.executeCalculation !== 'function' || typeof formula.onCalculationResultApplied !== 'function') throw new Error('formula_barrier_unavailable');\n      formula.executeCalculation();\n      await formula.onCalculationResultApplied(timeout || 10000);\n      return true;\n    },\n"
    patched=original.replace(needle,addition+needle)
    patch=''.join(difflib.unified_diff(original.splitlines(True),patched.splitlines(True),fromfile='a/static/js/univer-adapter.js',tofile='b/static/js/univer-adapter.js')).encode()
    patch_name='patches/univer-calculation-barrier.patch'
    if (DEST/patch_name).read_bytes()!=patch:raise RuntimeError('Owned formula barrier patch differs; review before sync')
    records[relative]['source_sha256']=digest(copies[relative]);copies[relative]=patched.encode()
    records[relative].update({'bytes':len(copies[relative]),'sha256':digest(copies[relative]),'adaptation':patch_name,'adaptation_sha256':digest(patch)})
    copies[patch_name]=patch;records[patch_name]={'source':'owned mobile adapter hook; original library/version retained','bytes':len(patch),'sha256':digest(patch)}
    # Owned reading hooks are reproducible; never overwrite them with upstream copies.
    owned_reading_hooks={'static/js/excalidraw/excalidraw-percentages-BXMCSKIN.js': ('patches/excalidraw-reading13.patch', 'ff27e61a0e780fb4a78494484af9c087acfb90cc8ac534d6e3d308bedb3b924b'), 'static/js/pptist-adapter.js': ('patches/pptist-reading13.patch', 'ed2c0bde1c95ce674a733392ecfa5e2255db8fb474c51d4f1a358b619b3f6cde')}
    owned_reading_hooks['static/pptist/assets/index-DeKNemMI.js']=('patches/pptist-owned-images.patch', 'd1325b1bf8155a099574736b1fd8ba15bd74d7d9d8e4f52cb4bef7e2d9ba2001')
    for relative,(patch_name,source_sha256) in owned_reading_hooks.items():
        original=copies[relative]
        if digest(original)!=source_sha256:raise RuntimeError('Original reading engine changed; review/rebase owned hook before sync')
        patch=(DEST/patch_name).read_bytes()
        patched=apply_owned_hunks(original,patch)
        records[relative].update({'source_sha256':source_sha256,'bytes':len(patched),'sha256':digest(patched),'adaptation':patch_name,'adaptation_sha256':digest(patch)})
        copies[relative]=patched;copies[patch_name]=patch
        records[patch_name]={'source':'owned mobile reading hook; original library/version retained','bytes':len(patch),'sha256':digest(patch)}
    for lang in ('zh','en'):
        original=PROJECT/'i18n'/f'{lang}.go';data=('window.__I18N_MESSAGES='+json.dumps(messages(original),ensure_ascii=False,separators=(',',':'))+';window.__currentLang='+json.dumps(lang)+';\n').encode()
        name=f'messages-{lang}.js';copies[name]=data
        records[name]={'source':str(original.relative_to(PROJECT)),'source_sha256':digest(original.read_bytes()),'bytes':len(data),'sha256':digest(data)}
    vendor_path=DEST/'vendor-manifest.json'
    vendor=json.loads(vendor_path.read_text())
    for name,info in vendor['files'].items():
        if not name.startswith('vendor/fake-indexeddb/') or '..' in Path(name).parts:raise RuntimeError('Invalid vendor asset path')
        path=DEST/name
        if path.is_symlink():raise RuntimeError('Vendor symlinks are not permitted')
        data=path.read_bytes()
        if len(data)!=info['bytes'] or digest(data)!=info['sha256']:raise RuntimeError('Pinned memory DB source differs')
        copies[name]=data
        records[name]={'source':vendor['registry']+'#'+name,'package_integrity':vendor['integrity'],**info}
    copies['vendor-manifest.json']=vendor_path.read_bytes()
    records['vendor-manifest.json']={'source':'reviewed pinned vendor manifest','bytes':len(copies['vendor-manifest.json']),'sha256':digest(copies['vendor-manifest.json'])}
    manifest=(json.dumps({'version':1,'origin':'existing BookStark public static assets and i18n maps','files':records},ensure_ascii=False,indent=2)+'\n').encode()
    previous=DEST/'source-manifest.json'
    if args.sync:
        if previous.exists():
            old=json.loads(previous.read_text())['files']
            for name in old.keys()-records.keys():
                path=DEST/name
                if path.exists():
                    if digest(path.read_bytes())!=old[name]['sha256']:raise RuntimeError('Owned copied asset was locally edited; inspect before sync')
                    path.unlink()
        for name,data in copies.items():
            path=DEST/name;path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists() or path.read_bytes()!=data:path.write_bytes(data)
        previous.write_bytes(manifest)
    else:
        if not previous.is_file() or previous.read_bytes()!=manifest:raise RuntimeError('Editor asset source manifest changed; review then --sync before freezing')
        for name,data in copies.items():
            if not (DEST/name).is_file() or (DEST/name).read_bytes()!=data:raise RuntimeError('Editor asset copy differs from reviewed upstream source')
    directories=sorted({str((DEST/name).parent.relative_to(APP))+'/' for name in copies if '/' in name})
    entries=['assets/complex_editors/host.html','assets/complex_editors/host.js','assets/complex_editors/local-drawing.js','assets/complex_editors/local-presentation.js', 'assets/complex_editors/reading13.js','assets/complex_editors/host-merge.js','assets/complex_editors/markdown-editor.js','assets/complex_editors/markdown-preview.js','assets/complex_editors/memory-storage.js','assets/complex_editors/memory-indexeddb.js','assets/complex_editors/source-manifest.json','assets/complex_editors/vendor-manifest.json','assets/complex_editors/messages-zh.js','assets/complex_editors/messages-en.js',*directories]
    block=BEGIN+'\n'+''.join('    - '+p+'\n' for p in entries)+END
    pubspec=APP/'pubspec.yaml';text=pubspec.read_text()
    if BEGIN in text:updated=re.sub(re.escape(BEGIN)+r'.*?'+re.escape(END),lambda _:block,text,flags=re.S)
    else:updated=text.replace('    - assets/licenses/spreadsheet_calc.txt','    - assets/licenses/spreadsheet_calc.txt\n'+block)
    if args.sync:pubspec.write_text(updated)
    elif text!=updated:raise RuntimeError('Reviewed editor pubspec asset list differs')
    print('PASS original editor assets:',len(records),'files,',sum(v['bytes'] for v in records.values()),'bytes; mode',('sync' if args.sync else 'verify'))
if __name__=='__main__':main()
