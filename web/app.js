"use strict";

const ICONS = {
  refresh: '<path d="M20 12a8 8 0 1 1-2.34-5.66"/><path d="M20 4v5h-5"/>',
  downloadAll: '<path d="M12 3.5v11"/><path d="m7.5 10 4.5 4.5 4.5-4.5"/><path d="M4.5 19.5h15"/>',
  download: '<path d="M12 4.5v11"/><path d="m7.5 11 4.5 4.5 4.5-4.5"/><path d="M6 19.5h12"/>',
  done: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  add: '<path d="M12 5v14"/><path d="M5 12h14"/>',
  trash: '<path d="M4.5 7h15"/><path d="M9.5 7V4.5h5V7"/><path d="m6.5 7 .9 12.1a1.5 1.5 0 0 0 1.5 1.4h6.2a1.5 1.5 0 0 0 1.5-1.4L17.5 7"/><path d="M10.2 11v6"/><path d="M13.8 11v6"/>',
  youtube: '<path d="M14 4.5h5.5V10"/><path d="m19.5 4.5-8 8"/><path d="M17.5 14v4.5a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-11a1 1 0 0 1 1-1H10"/>',
  grid: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
  list: '<rect x="3.5" y="5" width="6" height="4" rx="1"/><rect x="3.5" y="15" width="6" height="4" rx="1"/><path d="M13 6h7.5"/><path d="M13 8.5h4.5"/><path d="M13 16h7.5"/><path d="M13 18.5h4.5"/>',
  up: '<path d="M12 19V5"/><path d="m6.5 10.5 5.5-5.5 5.5 5.5"/>',
  down: '<path d="M12 5v14"/><path d="m6.5 13.5 5.5 5.5 5.5-5.5"/>',
  back: '<path d="m14.5 5.5-6.5 6.5 6.5 6.5"/>',
  play: '<path d="M8 5.8v12.4a.8.8 0 0 0 1.2.7l10-6.2a.8.8 0 0 0 0-1.4l-10-6.2A.8.8 0 0 0 8 5.8Z" fill="currentColor"/>',
  pause: '<rect x="6.5" y="5" width="3.8" height="14" rx="1" fill="currentColor"/><rect x="13.7" y="5" width="3.8" height="14" rx="1" fill="currentColor"/>',
  transcript: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M13 9h4.5"/><path d="M13 12h4.5"/><path d="M13 15h3"/><path d="M6.5 9h3"/><path d="M6.5 12h3"/><path d="M6.5 15h3"/>',
};

const icon = (name) => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name]}</svg>`;

const SECTION_TITLES = {
  subscriptions: "Subscriptions",
  watchLater: "Watch Later",
  downloaded: "Downloaded",
};
const EMPTY_TEXT = {
  subscriptions: "No uploads from your subscriptions in the past week.",
  watchLater: "Watch Later is empty. Save videos on YouTube or from Subscriptions to see them here.",
  downloaded: "Nothing downloaded yet. Click a video in Watch Later to download and play it.",
};
const RESUME_MIN = 5;
const RESUME_END_MARGIN = 10;
const SKIP = 5;
const RING_C = 2 * Math.PI * 19;

const $ = (sel, root = document) => root.querySelector(sel);

const store = {
  get(key, fallback) {
    try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
  },
  set(key, value) { localStorage.setItem(key, JSON.stringify(value)); },
};

const settings = Object.assign(
  { section: "watchLater", view: "grid", sort: "default", ascending: true,
    speed: 1, captions: false, transcript: false },
  store.get("wb.settings", {}),
);
const saveSettings = () => store.set("wb.settings", settings);
const positions = store.get("wb.positions", {});
const savePositions = () => store.set("wb.positions", positions);

let state = { watchLater: [], subscriptions: [], downloads: {}, local: new Set(), loading: true, error: null };
let pendingPlay = null;
const cards = new Map();

/* Formatting */

function fmtDuration(seconds) {
  const s = Math.max(0, Math.floor(seconds || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  const pad = (n) => String(n).padStart(2, "0");
  return h ? `${h}:${pad(m)}:${pad(r)}` : `${m}:${pad(r)}`;
}

function fmtAge(timestamp) {
  if (!timestamp) return "";
  const days = Math.floor((Date.now() / 1000 - timestamp) / 86400);
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  for (const [size, unit] of [[365, "year"], [30, "month"], [7, "week"]]) {
    if (days >= size) {
      const n = Math.floor(days / size);
      return `${n} ${unit}${n > 1 ? "s" : ""} ago`;
    }
  }
  return `${days} days ago`;
}

/* Server */

async function api(path, body) {
  const res = await fetch(path, body === undefined ? {} : {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${path} returned ${res.status}`);
  return res.json();
}

function applyState(data) {
  state = { ...data, local: new Set(data.local) };
  if (pendingPlay && state.local.has(pendingPlay) && $(".theater").hidden) {
    const id = pendingPlay;
    pendingPlay = null;
    openPlayer(id);
  }
  render();
}

let pollTimer = null;
async function poll() {
  clearTimeout(pollTimer);
  try {
    applyState(await api("/api/state"));
  } catch {
    state.error = "Lost the connection to the server. Start it again with ./run.sh.";
    render();
  }
  const busy = state.loading || Object.keys(state.downloads || {}).some(
    (id) => ["queued", "downloading"].includes(state.downloads[id].status));
  pollTimer = setTimeout(poll, busy ? 1000 : 15000);
}

async function act(path, id) {
  try {
    applyState(await api(path, id ? { id } : {}));
  } catch (e) {
    state.error = e.message;
    render();
  }
  poll();
}

/* Library */

function videosFor(section) {
  const wlIds = new Set(state.watchLater.map((v) => v.id));
  let vids;
  if (section === "subscriptions") {
    vids = state.subscriptions.map((v) => ({ ...v, inWatchLater: wlIds.has(v.id) }));
  } else if (section === "watchLater") {
    vids = state.watchLater.slice();
  } else {
    vids = state.watchLater.filter((v) => state.local.has(v.id) || state.downloads[v.id]);
  }
  return sortVideos(vids);
}

function sortVideos(vids) {
  const dir = settings.ascending ? 1 : -1;
  if (settings.sort === "title") {
    vids.sort((a, b) => dir * a.title.localeCompare(b.title));
  } else if (settings.sort === "duration") {
    vids.sort((a, b) => dir * (a.duration - b.duration));
  } else if (settings.sort === "published") {
    const dated = vids.filter((v) => v.timestamp).sort((a, b) => dir * (a.timestamp - b.timestamp));
    vids = dated.concat(vids.filter((v) => !v.timestamp));
  } else if (!settings.ascending) {
    vids.reverse();
  }
  return vids;
}

function render() {
  const section = settings.section;
  const downloadedCount = videosFor("downloaded").length;
  const counts = {
    subscriptions: state.subscriptions.length,
    watchLater: state.watchLater.length,
    downloaded: downloadedCount,
  };
  for (const btn of document.querySelectorAll(".sections button")) {
    const s = btn.dataset.section;
    btn.setAttribute("aria-current", String(s === section));
    $(".count", btn).textContent = counts[s] || "";
  }
  $(".section-title").textContent = SECTION_TITLES[section];

  const active = Object.values(state.downloads || {}).filter(
    (d) => d.status === "downloading" || d.status === "queued").length;
  const status = $(".status");
  status.classList.toggle("error", Boolean(state.error));
  status.textContent = state.error
    || (state.loading ? "Refreshing from YouTube..." : "")
    || (active ? `Downloading ${active} ${active === 1 ? "video" : "videos"}` : "");

  $('[data-action="download-all"]').hidden = section !== "watchLater";
  $('[data-action="refresh"]').classList.toggle("spin", state.loading);
  for (const btn of document.querySelectorAll("[data-view]")) {
    btn.setAttribute("aria-pressed", String(btn.dataset.view === settings.view));
  }
  $('[data-action="sort"]').value = settings.sort;
  const dirBtn = $('[data-action="direction"]');
  dirBtn.innerHTML = icon(settings.ascending ? "up" : "down");

  const list = $(".videos");
  list.className = `videos ${settings.view}`;
  const vids = videosFor(section);
  const mode = section;
  const seen = new Set();
  const order = [];
  for (const video of vids) {
    const key = `${mode}:${video.id}`;
    const sig = cardSignature(video, mode);
    let entry = cards.get(key);
    if (!entry || entry.sig !== sig) {
      const el = buildCard(video, mode);
      if (entry) entry.el.replaceWith(el);
      entry = { el, sig };
      cards.set(key, entry);
    }
    seen.add(key);
    order.push(entry.el);
  }
  for (const [key, entry] of cards) {
    if (!seen.has(key)) {
      entry.el.remove();
      cards.delete(key);
    }
  }
  order.forEach((el, i) => {
    if (list.children[i] !== el) list.insertBefore(el, list.children[i] || null);
  });

  const empty = $(".empty");
  empty.hidden = vids.length > 0;
  empty.textContent = state.loading && !vids.length ? "Loading..." : EMPTY_TEXT[section];
}

function cardSignature(video, mode) {
  return JSON.stringify([
    video.title, video.duration, video.channel, video.timestamp, video.inWatchLater,
    state.local.has(video.id), state.downloads[video.id] || null,
    Math.round(watchedFraction(video) * 100), settings.view, mode,
  ]);
}

function watchedFraction(video) {
  const pos = positions[video.id];
  return pos && video.duration ? Math.min(1, pos / video.duration) : 0;
}

function buildCard(video, mode) {
  const local = state.local.has(video.id);
  const dl = state.downloads[video.id];
  const fetching = dl && (dl.status === "downloading" || dl.status === "queued");
  const failed = dl && dl.status === "failed";

  const el = document.createElement("article");
  el.className = "video";
  el.dataset.id = video.id;
  el.tabIndex = 0;

  const thumb = document.createElement("div");
  thumb.className = "thumb";
  const img = document.createElement("img");
  img.loading = "lazy";
  img.alt = "";
  img.src = `https://i.ytimg.com/vi/${video.id}/hq720.jpg`;
  img.addEventListener("error", () => {
    if (!img.src.includes("mqdefault")) img.src = `https://i.ytimg.com/vi/${video.id}/mqdefault.jpg`;
  }, { once: true });
  thumb.append(img);
  if (video.duration) {
    const d = document.createElement("span");
    d.className = "duration";
    d.textContent = fmtDuration(video.duration);
    thumb.append(d);
  }
  const watched = watchedFraction(video);
  if (watched) {
    const bar = document.createElement("div");
    bar.className = "watched";
    bar.innerHTML = `<span style="width:${(watched * 100).toFixed(1)}%"></span>`;
    thumb.append(bar);
  }
  if (fetching) {
    const pct = dl.progress;
    const waiting = pct === null || pct === undefined;
    const offset = waiting ? RING_C * 0.72 : RING_C * (1 - pct / 100);
    const overlay = document.createElement("div");
    overlay.className = "fetching";
    overlay.innerHTML = `<svg class="ring${waiting ? " waiting" : ""}" viewBox="0 0 46 46" aria-hidden="true">
      <circle class="track" cx="23" cy="23" r="19"/>
      <circle class="fill" cx="23" cy="23" r="19" stroke-dasharray="${RING_C}" stroke-dashoffset="${offset}"/></svg>`;
    thumb.append(overlay);
  }

  const info = document.createElement("div");
  info.className = "info";
  const title = document.createElement("h3");
  title.className = "title";
  title.textContent = video.title;
  title.title = video.title;
  const meta = document.createElement("p");
  meta.className = "meta";
  if (fetching) {
    meta.textContent = dl.status === "queued" ? "Queued"
      : dl.progress == null ? "Downloading..." : `Downloading ${Math.floor(dl.progress)}%`;
  } else if (failed) {
    meta.textContent = dl.message || "Download failed. Click to retry.";
    meta.classList.add("failed");
  } else {
    meta.textContent = [video.channel, fmtAge(video.timestamp)].filter(Boolean).join(", ");
  }

  const actions = document.createElement("div");
  actions.className = "actions";
  const button = (name, act, label, extra = "") => {
    const b = document.createElement("button");
    b.className = `icon-btn ${extra}`.trim();
    b.dataset.act = act;
    b.title = label;
    b.setAttribute("aria-label", label);
    b.innerHTML = icon(name);
    actions.append(b);
    return b;
  };
  if (mode !== "downloaded") {
    button("youtube", "youtube", "Open on YouTube");
    if (local) button("done", "", "Downloaded", "done");
    else if (!fetching) button("download", "download", "Download");
  }
  if (mode === "subscriptions") {
    if (video.inWatchLater) button("done", "", "In Watch Later", "done");
    else button("add", "add", "Add to Watch Later");
  } else if (mode === "watchLater") {
    button("trash", "remove", "Remove from Watch Later");
  } else if (local) {
    button("trash", "delete", "Delete download");
  }

  info.append(title, meta, actions);
  el.append(thumb, info);
  return el;
}

/* Player */

const theater = $(".theater");
const videoEl = $(".theater video");
const scrubber = $(".scrubber");
const speedInput = $(".speed input");
const linesEl = $(".transcript-lines");
let playing = null;
let transcript = { starts: [], rows: [] };
let currentLine = -1;
let scrubbing = false;
let lastSave = 0;

function findVideo(id) {
  return state.watchLater.find((v) => v.id === id)
    || state.subscriptions.find((v) => v.id === id)
    || { id, title: "", duration: 0 };
}

async function openPlayer(id) {
  playing = findVideo(id);
  $(".now-playing").textContent = playing.title;
  document.title = `${playing.title} - WatchBar`;
  theater.hidden = false;
  for (const t of videoEl.querySelectorAll("track")) t.remove();
  videoEl.src = `/media/${id}.mp4`;
  const track = document.createElement("track");
  track.kind = "subtitles";
  track.srclang = "en";
  track.label = "English";
  track.src = `/media/${id}.vtt`;
  videoEl.append(track);
  applyCaptions();
  videoEl.playbackRate = settings.speed;
  videoEl.defaultPlaybackRate = settings.speed;
  setFill(scrubber, 0);
  $(".elapsed").textContent = "0:00";
  $(".total").textContent = fmtDuration(playing.duration);
  updatePlayButton();
  setTranscriptOpen(settings.transcript);
  loadTranscript(id);
  videoEl.play().catch(() => updatePlayButton());
}

function closePlayer() {
  if (!playing) return;
  rememberPosition(true);
  videoEl.pause();
  videoEl.removeAttribute("src");
  videoEl.load();
  playing = null;
  theater.hidden = true;
  document.title = "WatchBar";
  render();
}

function togglePlay() {
  if (!playing) return;
  if (videoEl.paused || videoEl.ended) videoEl.play();
  else videoEl.pause();
}

function skip(seconds) {
  if (!playing) return;
  const end = Number.isFinite(videoEl.duration) ? videoEl.duration : Infinity;
  videoEl.currentTime = Math.min(end, Math.max(0, videoEl.currentTime + seconds));
}

function updatePlayButton() {
  const paused = videoEl.paused || videoEl.ended;
  const btn = $('[data-action="play"]');
  btn.innerHTML = icon(paused ? "play" : "pause");
  btn.setAttribute("aria-label", paused ? "Play" : "Pause");
}

function setFill(input, value) {
  const min = Number(input.min), max = Number(input.max);
  const pct = max > min ? ((value - min) / (max - min)) * 100 : 0;
  input.style.setProperty("--fill", `${pct}%`);
}

function rememberPosition(force) {
  if (!playing || !Number.isFinite(videoEl.currentTime)) return;
  const now = Date.now();
  if (!force && now - lastSave < 5000) return;
  lastSave = now;
  if (videoEl.ended) delete positions[playing.id];
  else if (videoEl.currentTime > 0) positions[playing.id] = Math.round(videoEl.currentTime * 10) / 10;
  savePositions();
}

function applyCaptions() {
  const btn = $('[data-action="captions"]');
  btn.setAttribute("aria-pressed", String(settings.captions));
  btn.title = settings.captions ? "Hide subtitles" : "Show subtitles";
  for (const track of videoEl.textTracks) track.mode = settings.captions ? "showing" : "hidden";
}

function setTranscriptOpen(open) {
  $(".transcript").hidden = !open;
  const btn = $('[data-action="transcript"]');
  btn.setAttribute("aria-pressed", String(open));
  btn.title = open ? "Hide transcript" : "Show transcript";
  if (open) followTranscript(videoEl.currentTime, true);
}

async function loadTranscript(id) {
  linesEl.innerHTML = "";
  transcript = { starts: [], rows: [] };
  currentLine = -1;
  const empty = $(".transcript-empty");
  empty.hidden = false;
  empty.textContent = "Loading transcript...";
  let data;
  try {
    data = await api(`/api/transcript/${id}`);
  } catch {
    data = { lines: [], chapters: [] };
  }
  if (!playing || playing.id !== id) return;
  const hasLines = data.lines.length > 0;
  $('[data-action="captions"]').disabled = !hasLines;
  empty.hidden = hasLines;
  empty.textContent = "This video has no transcript.";
  const chapters = data.chapters.slice();
  const frag = document.createDocumentFragment();
  data.lines.forEach(([start, text, newSpeaker], i) => {
    while (chapters.length && chapters[0][0] <= start + 0.5) {
      const [at, title] = chapters.shift();
      frag.append(transcriptRow(at, title, "chapter"));
    }
    const row = transcriptRow(start, text, newSpeaker && i > 0 ? "speaker" : "");
    transcript.starts.push(start);
    transcript.rows.push(row);
    frag.append(row);
  });
  linesEl.append(frag);
  followTranscript(videoEl.currentTime, true);
}

function transcriptRow(start, text, kind) {
  const li = document.createElement("li");
  li.className = `line ${kind}`.trim();
  li.dataset.at = start;
  const at = document.createElement("span");
  at.className = "at";
  at.textContent = fmtDuration(start);
  const body = document.createElement("span");
  body.textContent = text;
  li.append(at, body);
  return li;
}

function followTranscript(time, force) {
  if ($(".transcript").hidden || !transcript.starts.length) return;
  let lo = 0, hi = transcript.starts.length - 1, index = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (transcript.starts[mid] <= time + 0.05) { index = mid; lo = mid + 1; } else hi = mid - 1;
  }
  if (index === currentLine && !force) return;
  const panel = $(".transcript");
  const prev = transcript.rows[currentLine];
  // Follow along only while the previous line is on screen, so reading
  // elsewhere in the transcript is not interrupted.
  const follow = force || !prev || isVisible(prev, panel);
  prev?.classList.remove("current");
  currentLine = index;
  const row = transcript.rows[index];
  if (!row) return;
  row.classList.add("current");
  if (follow) panel.scrollTo({ top: row.offsetTop - panel.clientHeight / 3 });
}

function isVisible(el, container) {
  const top = el.offsetTop - container.scrollTop;
  return top + el.offsetHeight > 0 && top < container.clientHeight;
}

videoEl.addEventListener("loadedmetadata", () => {
  const resume = positions[playing?.id] || 0;
  if (resume >= RESUME_MIN && resume < videoEl.duration - RESUME_END_MARGIN) {
    videoEl.currentTime = resume;
  }
  scrubber.max = videoEl.duration;
  $(".total").textContent = fmtDuration(videoEl.duration);
  applyCaptions();
});
videoEl.addEventListener("timeupdate", () => {
  if (!scrubbing) {
    scrubber.value = videoEl.currentTime;
    setFill(scrubber, videoEl.currentTime);
    $(".elapsed").textContent = fmtDuration(videoEl.currentTime);
  }
  followTranscript(videoEl.currentTime);
  rememberPosition(false);
});
videoEl.addEventListener("play", updatePlayButton);
videoEl.addEventListener("pause", () => { updatePlayButton(); rememberPosition(true); });
videoEl.addEventListener("ended", () => { updatePlayButton(); rememberPosition(true); });
videoEl.textTracks.addEventListener("addtrack", applyCaptions);

scrubber.addEventListener("input", () => {
  scrubbing = true;
  setFill(scrubber, Number(scrubber.value));
  $(".elapsed").textContent = fmtDuration(Number(scrubber.value));
  videoEl.currentTime = Number(scrubber.value);
});
scrubber.addEventListener("change", () => { scrubbing = false; });

function applySpeed() {
  speedInput.value = settings.speed;
  setFill(speedInput, settings.speed);
  $(".speed-value").textContent = `${settings.speed}x`;
  videoEl.playbackRate = settings.speed;
  videoEl.defaultPlaybackRate = settings.speed;
}
speedInput.addEventListener("input", () => {
  settings.speed = Number(speedInput.value);
  saveSettings();
  applySpeed();
});

$(".screen").addEventListener("click", togglePlay);
linesEl.addEventListener("click", (e) => {
  const li = e.target.closest(".line");
  if (!li) return;
  videoEl.currentTime = Number(li.dataset.at);
  followTranscript(videoEl.currentTime, true);
});

theater.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-action]");
  if (!btn) return;
  btn.blur();
  const action = btn.dataset.action;
  if (action === "close-player") closePlayer();
  else if (action === "play") togglePlay();
  else if (action === "captions") {
    settings.captions = !settings.captions;
    saveSettings();
    applyCaptions();
  } else if (action === "transcript") {
    settings.transcript = !settings.transcript;
    saveSettings();
    setTranscriptOpen(settings.transcript);
  }
});

document.addEventListener("keydown", (e) => {
  if (theater.hidden || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === " ") { e.preventDefault(); togglePlay(); }
  else if (e.key === "ArrowLeft") { e.preventDefault(); skip(-SKIP); }
  else if (e.key === "ArrowRight") { e.preventDefault(); skip(SKIP); }
  else if (e.key === "Escape") closePlayer();
});

/* Library events */

function openVideo(id) {
  if (state.local.has(id)) {
    openPlayer(id);
  } else {
    pendingPlay = id;
    act("/api/download", id);
  }
}

$(".videos").addEventListener("click", (e) => {
  const card = e.target.closest(".video");
  if (!card) return;
  const id = card.dataset.id;
  const btn = e.target.closest("button[data-act]");
  if (!btn) return openVideo(id);
  const action = btn.dataset.act;
  if (action === "youtube") window.open(`https://www.youtube.com/watch?v=${id}`, "_blank");
  else if (action === "download") act("/api/download", id);
  else if (action === "add") act("/api/watch-later/add", id);
  else if (action === "remove") act("/api/watch-later/remove", id);
  else if (action === "delete") act("/api/delete-local", id);
});
$(".videos").addEventListener("keydown", (e) => {
  const card = e.target.closest(".video");
  if (card && e.target === card && (e.key === "Enter" || e.key === " ")) {
    e.preventDefault();
    openVideo(card.dataset.id);
  }
});

document.querySelector(".rail").addEventListener("click", (e) => {
  const target = e.target.closest("[data-section]");
  if (!target) return;
  e.preventDefault();
  settings.section = target.dataset.section;
  saveSettings();
  window.scrollTo({ top: 0 });
  render();
});

$(".toolbar").addEventListener("click", (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  if (btn.dataset.view) {
    settings.view = btn.dataset.view;
    saveSettings();
    render();
  } else if (btn.dataset.action === "direction") {
    settings.ascending = !settings.ascending;
    saveSettings();
    render();
  } else if (btn.dataset.action === "refresh") {
    act("/api/refresh");
  } else if (btn.dataset.action === "download-all") {
    act("/api/download-all");
  }
});
$('[data-action="sort"]').addEventListener("change", (e) => {
  settings.sort = e.target.value;
  saveSettings();
  render();
});

/* Static icons */

$('[data-action="download-all"]').innerHTML = icon("downloadAll");
$('[data-action="refresh"]').innerHTML = icon("refresh");
$('[data-view="grid"]').innerHTML = icon("grid");
$('[data-view="list"]').innerHTML = icon("list");
$('[data-action="close-player"]').innerHTML = icon("back");
$('[data-action="captions"]').innerHTML = '<span class="cc-box"><span>CC</span></span>';
$('[data-action="transcript"]').innerHTML = icon("transcript");
applySpeed();

document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });
window.addEventListener("pagehide", () => rememberPosition(true));
render();
poll();
