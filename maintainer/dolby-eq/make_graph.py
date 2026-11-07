import os, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FixedLocator, NullLocator
HERE=os.path.dirname(os.path.abspath(__file__))
d=np.load(os.path.join(HERE,"curves.npz")); g=d["grid"]
b1=-1.0*np.exp(-0.5*(np.log2(g/7125)/0.35)**2)-1.0*np.exp(-0.5*(np.log2(g/9000)/0.35)**2)
ours=d["ours"]+np.maximum(b1,-1.2)
S="#fcfcfb"; T1="#0b0b0b"; T2="#52514e"; G="#e7e6e2"; C1="#2a78d6"; C2="#eb6834"; OFF="#a3a29c"
plt.rcParams.update({"font.family":"DejaVu Sans","font.size":12})
fig,(a,b)=plt.subplots(2,1,figsize=(12,8.6),height_ratios=[3.2,1.3],facecolor=S,gridspec_kw={"hspace":0.42})
ticks=[50,100,200,500,1000,2000,5000,10000,16000]; lab=["50","100","200","500","1k","2k","5k","10k","16k"]
for ax in (a,b):
    ax.set_facecolor(S); ax.set_xscale("log"); ax.set_xlim(42,16500)
    ax.xaxis.set_major_locator(FixedLocator(ticks)); ax.set_xticklabels(lab); ax.xaxis.set_minor_locator(NullLocator())
    ax.grid(True,color=G,lw=0.8); ax.set_axisbelow(True)
    for s in ax.spines.values(): s.set_visible(False)
    ax.tick_params(length=0,colors=T2)
a.axvspan(42,90,color=G,alpha=0.6,lw=0); a.text(62,-41,"room noise\n(unreliable)",ha="center",color=T2,fontsize=9)
a.plot(g,d["stock"],color=C1,lw=2.2,label="Stock Dolby (= HyperOS)")
a.plot(g,ours,color=C2,lw=2.6,label="Ours (stock + our speaker EQ)")
a.set_ylim(-45,10); a.set_ylabel("dB vs 0.5-2 kHz",color=T2)
fig.suptitle("Xiaomi Pad 6 speakers: Dolby with our EQ",x=0.06,ha="left",y=0.975,fontsize=17,color=T1,fontweight="bold")
fig.text(0.06,0.925,"Pink noise, landscape, 50 % volume, USB mic at 35 cm. 1/6-octave smoothing.",color=T2,fontsize=11)
a.legend(loc="lower right",frameon=False,labelcolor=T1,fontsize=11)
for f,t in ((165,"bass + speaker\nresonance"),):
    y=np.interp(f,g,ours); a.annotate(t,(f,y),xytext=(f*1.7,y+9),color=T2,fontsize=10,arrowprops=dict(arrowstyle="-",color=T2,lw=0.8))
y=np.interp(3225,g,d["stock"]); a.annotate("stock 3 kHz dip, filled",(3225,y),xytext=(1250,-22),color=T2,fontsize=10,arrowprops=dict(arrowstyle="-",color=T2,lw=0.8))
bands=np.array([47,141,234,328,469,656,844,1031,1313,1688,2250,3000,3750,4688,5813,7125,9000,11250,13875,19688])
eq=np.array([4.62,10.62,3.62,1.62,1.62,-1.38,-3.88,-4.88,-3.17,-0.07,0.62,0.12,-0.88,-2.88,-2.38,-4.38,-2.88,1.62,1.62,-1.38])
m=bands<=16500
b.bar(bands[m],eq[m],width=bands[m]*0.17,color=np.where(eq[m]>=0,C2,"#f3a27f"),edgecolor=S,linewidth=2)
b.axhline(0,color=T2,lw=0.9); b.set_ylim(-7,13.5); b.set_yticks([-5,0,5,10]); b.set_ylabel("dB",color=T2)
b.set_title("Our EQ, added to Dolby's 4 speaker tunings (headphones and BT unchanged)",loc="left",color=T1,fontsize=12)
for x,y in zip(bands[m],eq[m]):
    if abs(y)>=4: b.text(x,y+0.7 if y>0 else y-2.4,"%+.1f"%y,ha="center",color=T1,fontsize=10)
fig.text(0.06,0.012,"At higher volume Dolby's limiter takes the extra bass back (+2-4 dB at 75 %, none at max). 7-9 kHz of 'Ours': measured curve minus the\nlast -1 dB change (computed). Uncalibrated mic: treble about ±2 dB; below 90 Hz the room noise dominates.",color=T2,fontsize=9.5)
fig.savefig(os.path.join(HERE,"pipa-dolby-eq.png"),dpi=130,facecolor=S,bbox_inches="tight",pad_inches=0.3)
