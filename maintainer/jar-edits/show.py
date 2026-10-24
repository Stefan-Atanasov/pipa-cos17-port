import pickle,sys,difflib
a,b=pickle.load(open('methods.pkl','rb'))
pat=sys.argv[1]
for k in a:
    if k in b and a[k]!=b[k] and pat in str(k):
        print('=====',k)
        for l in difflib.unified_diff((a[k] or '').split('\n'),(b[k] or '').split('\n'),'b4','c06',lineterm='',n=2): print(l[:220])
