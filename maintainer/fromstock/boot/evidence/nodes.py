import sys,re
path=[];out=[]
for l in open(sys.argv[1]):
    s=l.strip()
    if s.endswith('{'):
        path.append(s[:-1].strip()); out.append('/'.join(path)); continue
    if s.startswith('};'):
        path.pop(); continue
    m=re.match(r'(compatible|status|model|label|qcom,ion-heap-type)\s*=\s*(.*);',s)
    if m: out.append('/'.join(path)+' :'+m.group(1)+'='+m.group(2))
print('\n'.join(sorted(out)))
