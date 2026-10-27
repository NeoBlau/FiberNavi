"""Локальная страница проверки разметки (только 127.0.0.1)."""
from __future__ import annotations

import json
import mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

EVENTS = ["turn", "arrival", "reroute", "speeding", "confirm", "chatter", "none"]
APP_EVENTS = ["turn_left", "turn_right", "keep_left", "keep_right", "straight", "uturn", "roundabout", "arrived",
              "reroute", "speeding", "speed_camera", "traffic_jam", "long_straight", "night_driving", "long_stop",
              "bad_gps", "route_start", "confirm"]

PAGE = r"""<!doctype html><html lang="ru"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>voice_tagger</title>
<style>
:root{color-scheme:light dark;--bg:#fff;--fg:#111;--mut:#666;--line:#ddd;--acc:#7a3fd1;--bad:#c33}
@media(prefers-color-scheme:dark){:root{--bg:#141414;--fg:#eee;--mut:#999;--line:#333}}
body{font:14px/1.4 system-ui;margin:0;padding:16px;background:var(--bg);color:var(--fg)}
h1{font-size:18px}h2{font-size:15px;margin-top:28px}
table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid var(--line);padding:6px;text-align:left;vertical-align:top}
.mut{color:var(--mut)}button{cursor:pointer}.rej{opacity:.35;text-decoration:line-through}
select{max-width:140px}.chips label{display:inline-block;margin:0 6px 2px 0;font-size:12px}
.bar{position:sticky;top:0;background:var(--bg);padding:8px 0;border-bottom:1px solid var(--line);z-index:1}
input[type=search]{width:min(420px,100%);padding:6px}
</style>
<div class="bar"><h1>Разметка реплик: <span id="char"></span></h1>
<input type="search" id="q" placeholder="Фильтр по тексту"> <select id="fe"><option value="">все события</option></select>
<button id="save">Сохранить tags.json</button> <span id="st" class="mut"></span></div>
<h2>Склейки инструкций (слой 2)</h2><div id="stitch"></div>
<h2>Дубли слов</h2><div id="words"></div>
<h2>Реплики</h2><table id="t"><thead><tr><th>▶</th><th>Текст</th><th>Событие</th><th>События навигатора</th><th>Мат</th><th>✓</th></tr></thead><tbody></tbody></table>
<script>
const EVENTS=__EVENTS__, APP=__APP__;
const TEMPLATES={turn_left_near:["turn","left"],turn_right_near:["turn","right"],turn_left_now:["now","left"],
 turn_right_now:["now","right"],turn_left_far:["up_ahead","turn","left"],keep_left_near:["keep","left"],
 keep_right_near:["keep","right"],straight_near:["keep","straight"],uturn_near:["turn","around"],arrived:["we're","here"]};
let tags=[],man=null;const $=s=>document.querySelector(s);
const audio=new Audio();function play(f){audio.src='/audio/'+encodeURIComponent(f);audio.play()}
async function playSeq(files){for(const f of files){await new Promise(r=>{const a=new Audio('/audio/'+encodeURIComponent(f));a.onended=r;a.onerror=r;a.play()})}}
function best(w){const t=(man?.words?.[w]||[]).filter(x=>!x.rejected);return t[0]?.file}
function renderStitch(){const d=$('#stitch');d.innerHTML='';for(const[k,ws]of Object.entries(TEMPLATES)){
 const files=ws.map(best);const ok=files.every(Boolean);const b=document.createElement('button');
 b.textContent=k+(ok?'':' — нет слов: '+ws.filter((w,i)=>!files[i]).join(', '));b.disabled=!ok;b.onclick=()=>playSeq(files);
 d.append(b,' ')}}
function renderWords(){const d=$('#words');d.innerHTML='';if(!man){d.textContent='Сначала build.';return}
 for(const[w,takes]of Object.entries(man.words||{})){const p=document.createElement('p');p.innerHTML='<b>'+w+'</b> ';
  takes.forEach(t=>{const s=document.createElement('span');s.className=t.rejected?'rej':'';
   const pb=document.createElement('button');pb.textContent='▶ '+t.score;pb.onclick=()=>play(t.file);
   const rb=document.createElement('button');rb.textContent=t.rejected?'вернуть':'брак';
   rb.onclick=async()=>{t.rejected=!t.rejected;await fetch('/api/reject',{method:'POST',body:JSON.stringify({word:w,file:t.file,rejected:t.rejected})});renderWords();renderStitch()};
   s.append(pb,rb,' ');p.append(s)});d.append(p)}}
function renderTags(){const tb=$('#t tbody');tb.innerHTML='';const q=$('#q').value.toLowerCase(),fe=$('#fe').value;
 tags.forEach((t,i)=>{if(q&&!t.text.toLowerCase().includes(q))return;if(fe&&t.event!==fe)return;
  const tr=document.createElement('tr');
  tr.innerHTML=`<td><button>▶</button></td><td>${t.text.replace(/</g,'&lt;')||'<i class=mut>(пусто)</i>'}<div class=mut>${t.file} · ${t.confidence}</div></td>
  <td><select>${EVENTS.map(e=>`<option ${e===t.event?'selected':''}>${e}</option>`).join('')}</select></td>
  <td class=chips>${APP.map(e=>`<label><input type=checkbox value="${e}" ${t.app_events?.includes(e)?'checked':''}>${e}</label>`).join('')}</td>
  <td><select class=ex>${[0,1,2].map(v=>`<option ${v===t.explicit?'selected':''}>${v}</option>`).join('')}</select></td>
  <td><input type=checkbox class=rv ${t.reviewed?'checked':''}></td>`;
  tr.querySelector('button').onclick=()=>play(t.file);
  tr.querySelector('select').onchange=e=>{t.event=e.target.value;t.reviewed=true;tr.querySelector('.rv').checked=true};
  tr.querySelector('.ex').onchange=e=>{t.explicit=+e.target.value};
  tr.querySelectorAll('.chips input').forEach(c=>c.onchange=()=>{t.app_events=[...tr.querySelectorAll('.chips input:checked')].map(x=>x.value);t.reviewed=true;tr.querySelector('.rv').checked=true});
  tr.querySelector('.rv').onchange=e=>{t.reviewed=e.target.checked};tb.append(tr)})}
$('#q').oninput=renderTags;$('#fe').onchange=renderTags;EVENTS.forEach(e=>$('#fe').add(new Option(e,e)));
$('#save').onclick=async()=>{const r=await fetch('/api/tags',{method:'POST',body:JSON.stringify(tags)});$('#st').textContent=r.ok?'сохранено, теперь запусти build':'ошибка'};
(async()=>{tags=await (await fetch('/api/tags')).json();const m=await fetch('/api/manifest');man=m.ok?await m.json():null;
 $('#char').textContent=man?.character||'';renderTags();renderWords();renderStitch()})();
</script></html>"""


def serve(voice: Path, port: int) -> int:
    voice = voice.resolve()
    page = PAGE.replace("__EVENTS__", json.dumps(EVENTS)).replace("__APP__", json.dumps(APP_EVENTS))

    class Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, body: bytes, ctype: str = "application/json") -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802
            path = unquote(urlparse(self.path).path)
            if path == "/":
                return self._send(200, page.encode(), "text/html; charset=utf-8")
            if path == "/api/tags":
                p = voice / "tags.json"
                return self._send(200, p.read_bytes() if p.exists() else b"[]")
            if path == "/api/manifest":
                p = voice / "voice_manifest.json"
                return self._send(200, p.read_bytes()) if p.exists() else self._send(404, b"{}")
            if path.startswith("/audio/"):
                target = (voice / path[len("/audio/"):]).resolve()
                if voice not in target.parents or not target.is_file():
                    return self._send(404, b"")
                return self._send(200, target.read_bytes(), mimetypes.guess_type(target.name)[0] or "audio/wav")
            self._send(404, b"")

        def do_POST(self) -> None:  # noqa: N802
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            path = urlparse(self.path).path
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                return self._send(400, b"")
            if path == "/api/tags" and isinstance(data, list):
                (voice / "tags.json").write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
                return self._send(200, b"{}")
            if path == "/api/reject":
                p = voice / "voice_manifest.json"
                manifest = json.loads(p.read_text(encoding="utf-8"))
                for take in manifest.get("words", {}).get(data.get("word"), []):
                    if take["file"] == data.get("file"):
                        take["rejected"] = bool(data.get("rejected"))
                p.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
                return self._send(200, b"{}")
            self._send(404, b"")

        def log_message(self, *args) -> None:
            pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Открой http://localhost:{port}  (Ctrl+C — выход)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0
