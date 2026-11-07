import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FixedLocator, NullLocator
hz=[63,80,101,127,160,202,254,320,403,508,640,806,1016,1280,1613,2032,2560,3225,4064,5120,6451,8127,10240,12902,16255]
stock=[-41.0,-35.3,-26.1,-21.7,-17.3,-16.3,-12.1,-4.6,-7.3,-2.8,-0.1,2.8,3.8,0.8,-2.9,-1.4,-0.8,-6.4,-1.6,-2.0,0.7,1.3,-4.5,-11.7,-8.2]
b12=[-26.6,-21.3,-14.4,-10.0,-6.1,-8.2,-7.2,-1.5,-2.3,1.5,-0.2,2.3,1.5,-1.0,-2.0,-2.7,-0.5,-1.2,1.8,0.3,2.4,3.3,0.9,-9.8,-8.4]
b1delta={6451:-0.6,8127:-1.0,10240:-0.6}
final=[v+b1delta.get(h,0) for h,v in zip(hz,b12)]
bands=[47,141,234,328,469,656,844,1031,1313,1688,2250,3000,3750,4688,5813,7125,9000,11250,13875,19688]
eq=[4.62,10.62,3.62,1.62,1.62,-1.38,-3.88,-4.88,-3.17,-0.07,0.62,0.12,-0.88,-2.88,-2.38,-4.38,-2.88,1.62,1.62,-1.38]
S="#fcfcfb"; T1="#0b0b0b"; T2="#52514e"; G="#e4e3df"; C1="#2a78d6"; C2="#eb6834"
plt.rcParams.update({"font.family":"DejaVu Sans","font.size":11,"axes.edgecolor":G,"axes.labelcolor":T2,"xtick.color":T2,"ytick.color":T2})
fig,(a,b)=plt.subplots(2,1,figsize=(11,8.2),height_ratios=[3,1.6],facecolor=S)
ticks=[50,100,200,500,1000,2000,5000,10000,16000]; lab=["50","100","200","500","1k","2k","5k","10k","16k"]
for ax in (a,b):
    ax.set_facecolor(S); ax.set_xscale("log"); ax.set_xlim(38,22000)
    ax.xaxis.set_major_locator(FixedLocator(ticks)); ax.set_xticklabels(lab); ax.xaxis.set_minor_locator(NullLocator())
    ax.grid(True,axis="y",color=G,lw=0.8); ax.grid(True,axis="x",color=G,lw=0.5,alpha=0.6)
    for s in ("top","right","left"): ax.spines[s].set_visible(False)
    ax.tick_params(length=0)
a.plot(hz,stock,color=C1,lw=2,marker="o",ms=4,label="Stock Dolby (HyperOS tuning)")
a.plot(hz,final,color=C2,lw=2,marker="o",ms=4,label="Port Dolby with our speaker EQ (B1)")
a.text(63*0.93,stock[0],"Stock",color=T1,va="center",ha="right",fontsize=10)
a.text(63*0.93,final[0],"Ours",color=T1,va="center",ha="right",fontsize=10)
a.set_ylim(-44,8); a.set_ylabel("dB, relative to 0.5-2 kHz average")
a.set_title("Xiaomi Pad 6 speakers, Dolby on, 50 % volume (pink noise, mic at 35 cm)",loc="left",color=T1,fontsize=13,pad=26)
a.legend(loc="lower right",frameon=False,labelcolor=T1)
a.annotate("deeper bass", (127,-10), xytext=(160,-24), color=T2, fontsize=10, arrowprops=dict(arrowstyle="-",color=T2,lw=0.8))
a.annotate("3 kHz dip filled", (3225,-1.2), xytext=(1500,-14), color=T2, fontsize=10, arrowprops=dict(arrowstyle="-",color=T2,lw=0.8))
b.bar(bands,eq,width=[f*0.16 for f in bands],color=[C2]*20,edgecolor=S,linewidth=2)
b.axhline(0,color=T2,lw=0.8); b.set_ylim(-7.5,12.5); b.set_ylabel("EQ added, dB")
b.set_title("The EQ we added to the 4 speaker tunings (20 Dolby bands)",loc="left",color=T1,fontsize=12)
for x,y in zip(bands,eq):
    if abs(y)>=4: b.text(x,y+(0.6 if y>0 else -1.6),"%+.1f"%y,ha="center",color=T1,fontsize=9)
fig.text(0.01,0.005,"Dolby's limiter holds the bass back at higher volume: +2-4 dB at 75 %, 0 dB at max.\n'Ours' at 6.4-10 kHz = measured b12 minus the B1 change (computed). Uncalibrated USB mic: treble about +-2 dB.",color=T2,fontsize=8.5)
fig.tight_layout(rect=(0,0.045,1,1)); fig.savefig(__import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)),"pipa-dolby-eq.png"),dpi=130,facecolor=S)
