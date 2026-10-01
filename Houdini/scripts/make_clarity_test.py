"""Build a self-contained HTML page for judging sprite cell size on a real display.

Embeds the Test_Crag_C128/C256/C512 sheets (render them first, see Docs/Sprite_Pipeline.md) and
draws them at true device pixels, downsampled through a mip chain the way a GPU would.

Usage (any python 3):  python Houdini/scripts/make_clarity_test.py
Output: Houdini/render/ClarityTest/Sprite_Clarity_Test.html (single file; copy it to the device).
"""
import base64
import json
import pathlib
import sys

HOUDINI_DIR = pathlib.Path(__file__).resolve().parents[1]
VARIANTS = [128, 256, 512]
ASSET = "Test_Crag"


def main():
    data = {}
    for c in VARIANTS:
        d = HOUDINI_DIR / "render" / f"{ASSET}_C{c}"
        meta = json.loads((d / f"{ASSET}_C{c}_Sheet.json").read_text(encoding="utf-8"))
        if len(meta["sheets"]) != 1:
            sys.exit(f"{ASSET}_C{c}: expected one sheet")
        png = base64.b64encode((d / meta["sheets"][0]["file"]).read_bytes()).decode("ascii")
        anim = meta["animations"][0]
        data[c] = {"cell": meta["cell"]["w"], "pivot": meta["pivot_px"], "rows": anim["rows"],
                   "frames": anim["frames"], "fps": anim["fps"], "content": meta["content_rect"],
                   "png": "data:image/png;base64," + png}
    out = HOUDINI_DIR / "render" / "ClarityTest" / "Sprite_Clarity_Test.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(PAGE.replace("__DATA__", json.dumps(data)), encoding="utf-8", newline="\n")
    print(f"[clarity] wrote {out} ({out.stat().st_size / 2**20:.1f} MB)")


PAGE = r"""<!doctype html>
<html><head><meta charset="utf-8"><title>TowerClash sprite clarity test</title>
<style>
 body{font:14px -apple-system,Segoe UI,sans-serif;background:#222;color:#ddd;margin:16px}
 h2{margin:18px 0 4px;font-size:16px} .row{display:flex;gap:24px;flex-wrap:wrap;align-items:flex-end}
 .v{display:flex;flex-direction:column;gap:4px} .v b{color:#fff} .bad{color:#f88} .ok{color:#8f8}
 canvas{display:block} .pix canvas{image-rendering:pixelated} small{color:#999}
 fieldset{border:1px solid #555;margin:0 0 8px;padding:6px 10px} label{margin-right:14px}
</style></head><body>
<h1 style="font-size:18px">Sprite clarity test - pick the smallest cell that still looks sharp</h1>
<fieldset><legend>On-screen size</legend>
 <label><input type="radio" name="mode" value="phone" checked> iPhone 15 Pro Max plan estimate (enemy 80 px, boss 160 px tall)</label>
 <label><input type="radio" name="mode" value="frac"> Same fraction of screen height on this display (enemy 6.2 %, boss 12.4 %)</label>
 <label><input type="radio" name="mode" value="custom"> Custom enemy height <input id="custom" type="range" min="40" max="300" value="80"> <span id="customv"></span> px</label>
</fieldset>
<fieldset><legend>View</legend>
 <label>Ground <select id="bg"><option value="#5d7a3a">grass</option><option value="#8a6b47">dirt</option><option value="#2a2a2a">dark</option><option value="#c9c2b0">stone</option></select></label>
 <label><input type="checkbox" id="anim" checked> animate</label>
 <label><input type="checkbox" id="mips" checked> GPU-style mipmaps (off = browser resampling)</label>
 <label><input type="checkbox" id="zoom"> 4x pixel zoom (inspect only)</label>
</fieldset>
<div id="info"><small></small></div>
<h2>Standard enemy</h2><div class="row" id="enemy"></div>
<h2>Boss</h2><div class="row" id="boss"></div>
<p><small>Memory figures: 8 directions, ASTC 4x4 (~1 byte/px), power-of-2 sheets, no mips. Enemy = Walk 8 + Hit 2 + Death 4 frames;
boss = + Intro 4. Directions shown: S, SE, E. Not shown: ASTC compression artifacts, engine filtering differences, real art (Crag is a stand-in).</small></p>
<p><small>Whole-game sprite totals (8 towers + 3 hero towers + 6 enemies + 2 bosses, all 8-directional, + 5.1 MB other),
enemies/bosses at 256 px (decided): towers 128 px = 87 MB; towers 256 px = 134-153 MB. Original plan budget was 64 MB.</small></p>
<script>
const D=__DATA__, dpr=window.devicePixelRatio||1;
const TESTS={enemy:{sizes:[128,256,512],frac:0.062,phone:80,cost:{128:'1.75 MB',256:'7 MB',512:'28 MB'},
                    fits:{512:'over 2048 sheet cap'}},
             boss:{sizes:[256,512],frac:0.124,phone:160,cost:{256:'9 MB',512:'36 MB'},
                    fits:{512:'over 2048 sheet cap'}}};
const DIRS=['S','SE','E'];
// frame canvases + mip chains, built once per variant
const cache={};
function load(c){return new Promise(r=>{const v=D[c],img=new Image();img.onload=()=>{
  const frames={};for(const d of DIRS){frames[d]=[];for(let f=0;f<v.frames;f++){
    let lv=[document.createElement('canvas')];lv[0].width=lv[0].height=v.cell;
    lv[0].getContext('2d').drawImage(img,f*v.cell,v.rows[d]*v.cell,v.cell,v.cell,0,0,v.cell,v.cell);
    while(lv[lv.length-1].width>1){const p=lv[lv.length-1],n=document.createElement('canvas');
      n.width=n.height=Math.max(1,p.width>>1);const g=n.getContext('2d');g.imageSmoothingEnabled=true;
      g.drawImage(p,0,0,n.width,n.height);lv.push(n);}
    frames[d].push(lv);}}
  cache[c]=frames;r();};img.src=v.png;});}
function enemyPx(){const m=document.querySelector('input[name=mode]:checked').value;
  if(m==='phone')return TESTS.enemy.phone; if(m==='frac')return Math.round(screen.height*dpr*TESTS.enemy.frac);
  return +document.getElementById('custom').value;}
const views=[];
function build(){for(const k of ['enemy','boss']){const host=document.getElementById(k);host.innerHTML='';
  for(const c of TESTS[k].sizes){const v=document.createElement('div');v.className='v';
    const cv=document.createElement('canvas');const cap=document.createElement('div');
    const f=TESTS[k].fits[c];
    cap.innerHTML=`<b>${c} px cell</b> ${TESTS[k].cost[c]} / unit`+(f?` <span class="bad">(${f})</span>`:'');
    v.append(cap,cv);host.append(v);views.push({k,c,cv});}}}
let t0=performance.now();
function draw(){const e=enemyPx(),zoom=document.getElementById('zoom').checked,mips=document.getElementById('mips').checked;
  document.getElementById('customv').textContent=document.getElementById('custom').value;
  document.getElementById('info').innerHTML=`<small>devicePixelRatio ${dpr}, screen ${screen.width*dpr}x${screen.height*dpr} device px.
   Enemy drawn ${e} px tall, boss ${2*e} px tall (device pixels).</small>`;
  document.body.classList.toggle('pix',zoom);
  for(const vw of views){const v=D[vw.c],target=vw.k==='enemy'?e:2*e;
    const s=target/v.content.h, cellPx=Math.ceil(v.cell*s), W=cellPx*DIRS.length+8*(DIRS.length+1), H=cellPx+8;
    if(vw.cv.width!==W||vw.cv.height!==H){vw.cv.width=W;vw.cv.height=H;}
    vw.cv.style.width=(W/dpr*(zoom?4:1))+'px';vw.cv.style.height=(H/dpr*(zoom?4:1))+'px';
    const g=vw.cv.getContext('2d');g.imageSmoothingEnabled=true;g.imageSmoothingQuality='high';
    g.fillStyle=document.getElementById('bg').value;g.fillRect(0,0,W,H);
    const fr=document.getElementById('anim').checked?Math.floor((performance.now()-t0)/1000*v.fps)%v.frames:0;
    DIRS.forEach((d,i)=>{const lv=cache[vw.c][d][fr];
      let L=0; if(mips){while(L+1<lv.length&&lv[L+1].width>=v.cell*s)L++;}
      g.drawImage(lv[L],8+i*(cellPx+8),4,cellPx,cellPx);});}
  requestAnimationFrame(draw);}
Promise.all(Object.keys(D).map(load)).then(()=>{build();draw();});
</script></body></html>
"""

if __name__ == "__main__":
    main()
