# fr2.py out.npy rec1.wav [rec2.wav...]: Farina log-sweep deconvolution, 1/6-oct smoothed magnitude (dB re 1 kHz), averaged
import sys, wave, numpy as np
fs=48000; d=sys.argv[0].rsplit('/',1)[0]; s=np.load(d+'/sweep10.npy'); T=len(s)/fs; K=T/np.log(1000.)
def load(p):
    w=wave.open(p); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.uint8).reshape(-1,3)
    x=(a[:,0].astype(np.int32)|a[:,1].astype(np.int32)<<8|a[:,2].astype(np.int32)<<16); x=np.where(x>=1<<23,x-(1<<24),x)/float(1<<23); return x
t=np.arange(len(s))/fs; inv=s[::-1]*np.exp(-t/K)  # reversed sweep, -6 dB/oct envelope (Farina)
N=1<<21; INV=np.fft.rfft(inv,N); REF=np.fft.rfft(s,N)*INV; f=np.fft.rfftfreq(N,1/fs)
def ir(x):
    h=np.fft.irfft(np.fft.rfft(x,N)*INV/ (np.abs(REF).max()),N); return h
def resp(p):
    h=ir(load(p)); pk=int(np.argmax(np.abs(h))); pre=int(0.003*fs); post=int(0.006*fs)  # 6 ms: direct sound + desk reflection
    g=h[pk-pre:pk+post].copy(); tl=int(0.002*fs); g[-tl:]*=np.hanning(2*tl)[tl:]; g[:int(0.001*fs)]*=np.hanning(2*int(0.001*fs))[:int(0.001*fs)]
    gl=h[pk-pre:pk+int(0.3*fs)].copy()  # long window: in-room (incl. reflections), better bass resolution
    n=1<<16; F=np.fft.rfftfreq(n,1/fs); return F, np.abs(np.fft.rfft(g,n))**2, np.abs(np.fft.rfft(gl,n))**2
rs=[resp(p) for p in sys.argv[2:]]; F=rs[0][0]; Ps=np.mean([r[1] for r in rs],0); Pl=np.mean([r[2] for r in rs],0)
cent=np.array([20*2**(i/6) for i in range(61)]); cent=cent[(cent>=50)&(cent<20000)]
def sm(P): return np.array([10*np.log10(P[(F>=fc*2**(-1/12))&(F<fc*2**(1/12))].mean()+1e-30) for fc in cent])
# merge: long window below 500 Hz (short window cannot resolve bass), short above
Ls,Ll=sm(Ps),sm(Pl); m=cent<500
out=np.where(m, Ll-(np.interp(500,cent,Ll)-np.interp(500,cent,Ls)), Ls); out-=np.interp(1000,cent,out)
np.save(sys.argv[1],np.stack([cent,out]))
