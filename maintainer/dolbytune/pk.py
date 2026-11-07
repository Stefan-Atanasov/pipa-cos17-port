# pk.py out.npy rec.wav : in-room response from pink noise (Welch PSD of recording / PSD of source), 1/6 oct, re 1 kHz
import sys, wave, numpy as np
fs=48000; d=sys.argv[0].rsplit('/',1)[0]; src=np.load(d+'/pink.npy')
def load(p):
    w=wave.open(p); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.uint8).reshape(-1,3)
    x=(a[:,0].astype(np.int32)|a[:,1].astype(np.int32)<<8|a[:,2].astype(np.int32)<<16); x=np.where(x>=1<<23,x-(1<<24),x)/float(1<<23); return x
def psd(x,n=16384):
    w=np.hanning(n); segs=[x[i:i+n]*w for i in range(0,len(x)-n,n//2)]; return np.mean([np.abs(np.fft.rfft(s))**2 for s in segs],0)
x=load(sys.argv[2])
# use the middle 16 s of the recording (skip leveler settling: start 4 s after the onset)
env=np.convolve(x**2,np.ones(4800)/4800,'same'); on=int(np.argmax(env>env.max()*0.1))
seg=x[on+4*fs:on+20*fs]; P=psd(seg)/psd(src[4*fs:20*fs]); F=np.fft.rfftfreq(16384,1/fs)
cent=np.array([20*2**(i/6) for i in range(61)]); cent=cent[(cent>=50)&(cent<20000)]
out=np.array([10*np.log10(P[(F>=fc*2**(-1/12))&(F<fc*2**(1/12))].mean()) for fc in cent]); out-=np.interp(1000,cent,out)
np.save(sys.argv[1],np.stack([cent,out]))
