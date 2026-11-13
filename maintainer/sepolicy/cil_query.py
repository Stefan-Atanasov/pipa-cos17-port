import sys,re,collections
def parse(s):
    toks=re.findall(r'\(|\)|[^\s()]+',s); st=[[]]
    for t in toks:
        if t=='(': st.append([])
        elif t==')':
            x=st.pop(); st[-1].append(x)
        else: st[-1].append(t)
    return st[0]
files=sys.argv[1].split(','); src=sys.argv[2]; cls=sys.argv[3]; perm=sys.argv[4]; targets=sys.argv[5:]
types=set(); attrs=collections.defaultdict(list); rules=[]
for f in files:
    for ln,l in enumerate(open(f,errors='replace'),1):
        if l.startswith('(type '): types.add(l.split()[1].rstrip(')\n'))
        elif l.startswith('(typeattributeset '):
            e=parse(l)[0]; attrs[e[1]].append(e[2])
        elif l.startswith('(allow ') and cls in l:
            e=parse(l)[0]; rules.append((f,ln,e))
memo={}
def ev(x):
    if isinstance(x,str):
        if x=='all': return set(types)
        if x in memo: return memo[x]
        if x in attrs:
            memo[x]=set(); r=set()
            for e in attrs[x]: r|=ev(e)
            memo[x]=r; return r
        return {x}
    if not x: return set()
    if x[0]=='and': 
        r=ev(x[1])
        for y in x[2:]: r=r&ev(y)
        return r
    if x[0]=='or':
        r=set()
        for y in x[1:]: r|=ev(y)
        return r
    if x[0]=='not': return set(types)-ev(x[1] if len(x)==2 else x[1:])
    r=set()
    for y in x: r|=ev(y)
    return r
res=collections.defaultdict(list)
for f,ln,e in rules:
    if len(e)<4 or not isinstance(e[3],list): continue
    c=e[3]
    if c[0]!=cls or perm not in (c[1] if isinstance(c[1],list) else [c[1]]): continue
    if src not in ev(e[1]): continue
    tg=ev(e[2])
    for t in targets:
        if t in tg: res[t].append(f"{f.split('/')[-1]}:{ln} src={e[1]} tgt={e[2] if isinstance(e[2],str) else '(expr)'}")
for t in targets:
    print(('YES ' if res[t] else 'NO  ')+t, '|', '; '.join(res[t][:2]))
