"use strict";

const ICONS = {
  refresh: '<path d="M244,56v48a12,12,0,0,1-12,12H184a12,12,0,1,1,0-24H201.1l-19-17.38c-.13-.12-.26-.24-.38-.37A76,76,0,1,0,127,204h1a75.53,75.53,0,0,0,52.15-20.72,12,12,0,0,1,16.49,17.45A99.45,99.45,0,0,1,128,228h-1.37A100,100,0,1,1,198.51,57.06L220,76.72V56a12,12,0,0,1,24,0Z"/>',
  downloadAll: '<path d="M208,28H48A20,20,0,0,0,28,48V208a20,20,0,0,0,20,20H208a20,20,0,0,0,20-20V48A20,20,0,0,0,208,28Zm-4,24v92H179.31a19.86,19.86,0,0,0-14.14,5.86L147,168H109L90.83,149.86A19.86,19.86,0,0,0,76.69,144H52V52ZM52,204V168H75l18.14,18.14A19.86,19.86,0,0,0,107.31,192h41.38a19.86,19.86,0,0,0,14.14-5.86L181,168h23v36Zm35.51-87.51a12,12,0,0,1,17-17L116,111V76a12,12,0,0,1,24,0v35l11.51-11.52a12,12,0,0,1,17,17l-32,32a12,12,0,0,1-17,0Z"/>',
  download: '<path d="M228,144v64a12,12,0,0,1-12,12H40a12,12,0,0,1-12-12V144a12,12,0,0,1,24,0v52H204V144a12,12,0,0,1,24,0Zm-108.49,8.49a12,12,0,0,0,17,0l40-40a12,12,0,0,0-17-17L140,115V32a12,12,0,0,0-24,0v83L96.49,95.51a12,12,0,0,0-17,17Z"/>',
  done: '<path d="M176.49,95.51a12,12,0,0,1,0,17l-56,56a12,12,0,0,1-17,0l-24-24a12,12,0,1,1,17-17L112,143l47.51-47.52A12,12,0,0,1,176.49,95.51ZM236,128A108,108,0,1,1,128,20,108.12,108.12,0,0,1,236,128Zm-24,0a84,84,0,1,0-84,84A84.09,84.09,0,0,0,212,128Z"/>',
  undownload: '<path d="M168.49,104.49,145,128l23.52,23.51a12,12,0,0,1-17,17L128,145l-23.51,23.52a12,12,0,0,1-17-17L111,128,87.51,104.49a12,12,0,0,1,17-17L128,111l23.51-23.52a12,12,0,0,1,17,17ZM236,128A108,108,0,1,1,128,20,108.12,108.12,0,0,1,236,128Zm-24,0a84,84,0,1,0-84,84A84.09,84.09,0,0,0,212,128Z"/>',
  stop: '<path d="M128,20A108,108,0,1,0,236,128,108.12,108.12,0,0,0,128,20Zm0,192a84,84,0,1,1,84-84A84.09,84.09,0,0,1,128,212Zm40-112v56a12,12,0,0,1-12,12H100a12,12,0,0,1-12-12V100a12,12,0,0,1,12-12h56A12,12,0,0,1,168,100Z"/>',
  add: '<path d="M128,20A108,108,0,1,0,236,128,108.12,108.12,0,0,0,128,20Zm0,192a84,84,0,1,1,84-84A84.09,84.09,0,0,1,128,212Zm52-84a12,12,0,0,1-12,12H140v28a12,12,0,0,1-24,0V140H88a12,12,0,0,1,0-24h28V88a12,12,0,0,1,24,0v28h28A12,12,0,0,1,180,128Z"/>',
  trash: '<path d="M216,48H180V36A28,28,0,0,0,152,8H104A28,28,0,0,0,76,36V48H40a12,12,0,0,0,0,24h4V208a20,20,0,0,0,20,20H192a20,20,0,0,0,20-20V72h4a12,12,0,0,0,0-24ZM100,36a4,4,0,0,1,4-4h48a4,4,0,0,1,4,4V48H100Zm88,168H68V72H188ZM116,104v64a12,12,0,0,1-24,0V104a12,12,0,0,1,24,0Zm48,0v64a12,12,0,0,1-24,0V104a12,12,0,0,1,24,0Z"/>',
  youtube: '<path d="M228,104a12,12,0,0,1-24,0V69l-59.51,59.51a12,12,0,0,1-17-17L187,52H152a12,12,0,0,1,0-24h64a12,12,0,0,1,12,12Zm-44,24a12,12,0,0,0-12,12v64H52V84h64a12,12,0,0,0,0-24H48A20,20,0,0,0,28,80V208a20,20,0,0,0,20,20H176a20,20,0,0,0,20-20V140A12,12,0,0,0,184,128Z"/>',
  grid: '<path d="M100,36H56A20,20,0,0,0,36,56v44a20,20,0,0,0,20,20h44a20,20,0,0,0,20-20V56A20,20,0,0,0,100,36ZM96,96H60V60H96ZM200,36H156a20,20,0,0,0-20,20v44a20,20,0,0,0,20,20h44a20,20,0,0,0,20-20V56A20,20,0,0,0,200,36Zm-4,60H160V60h36Zm-96,40H56a20,20,0,0,0-20,20v44a20,20,0,0,0,20,20h44a20,20,0,0,0,20-20V156A20,20,0,0,0,100,136Zm-4,60H60V160H96Zm104-60H156a20,20,0,0,0-20,20v44a20,20,0,0,0,20,20h44a20,20,0,0,0,20-20V156A20,20,0,0,0,200,136Zm-4,60H160V160h36Z"/>',
  list: '<path d="M208,136H48a20,20,0,0,0-20,20v36a20,20,0,0,0,20,20H208a20,20,0,0,0,20-20V156A20,20,0,0,0,208,136Zm-4,52H52V160H204Zm4-144H48A20,20,0,0,0,28,64v36a20,20,0,0,0,20,20H208a20,20,0,0,0,20-20V64A20,20,0,0,0,208,44Zm-4,52H52V68H204Z"/>',
  up: '<path d="M128,128a12,12,0,0,1-12,12H48a12,12,0,0,1,0-24h68A12,12,0,0,1,128,128ZM48,76H180a12,12,0,0,0,0-24H48a12,12,0,0,0,0,24Zm52,104H48a12,12,0,0,0,0,24h52a12,12,0,0,0,0-24Zm132.49-20.49a12,12,0,0,0-17,0L196,179V112a12,12,0,0,0-24,0v67l-19.51-19.52a12,12,0,0,0-17,17l40,40a12,12,0,0,0,17,0l40-40A12,12,0,0,0,232.49,159.51Z"/>',
  down: '<path d="M36,128a12,12,0,0,1,12-12h68a12,12,0,0,1,0,24H48A12,12,0,0,1,36,128ZM48,76h52a12,12,0,0,0,0-24H48a12,12,0,0,0,0,24ZM180,180H48a12,12,0,0,0,0,24H180a12,12,0,0,0,0-24ZM232.49,79.51l-40-40a12,12,0,0,0-17,0l-40,40a12,12,0,0,0,17,17L172,77v67a12,12,0,0,0,24,0V77l19.51,19.52a12,12,0,0,0,17-17Z"/>',
  back: '<path d="M228,128a12,12,0,0,1-12,12H69l51.52,51.51a12,12,0,0,1-17,17l-72-72a12,12,0,0,1,0-17l72-72a12,12,0,0,1,17,17L69,116H216A12,12,0,0,1,228,128Z"/>',
  play: '<path d="M240,128a15.74,15.74,0,0,1-7.6,13.51L88.32,229.65a16,16,0,0,1-16.2.3A15.86,15.86,0,0,1,64,216.13V39.87a15.86,15.86,0,0,1,8.12-13.82,16,16,0,0,1,16.2.3L232.4,114.49A15.74,15.74,0,0,1,240,128Z"/>',
  pause: '<path d="M216,48V208a16,16,0,0,1-16,16H160a16,16,0,0,1-16-16V48a16,16,0,0,1,16-16h40A16,16,0,0,1,216,48ZM96,32H56A16,16,0,0,0,40,48V208a16,16,0,0,0,16,16H96a16,16,0,0,0,16-16V48A16,16,0,0,0,96,32Z"/>',
  transcript: '<path d="M216,36H40A20,20,0,0,0,20,56V200a20,20,0,0,0,20,20H216a20,20,0,0,0,20-20V56A20,20,0,0,0,216,36Zm-4,160H44V60H212ZM68,92A12,12,0,0,1,80,80h96a12,12,0,0,1,0,24H80A12,12,0,0,1,68,92Zm0,36a12,12,0,0,1,12-12h96a12,12,0,0,1,0,24H80A12,12,0,0,1,68,128Zm0,36a12,12,0,0,1,12-12h96a12,12,0,0,1,0,24H80A12,12,0,0,1,68,164Z"/>',
  captions: '<path d="M224,44H32A20,20,0,0,0,12,64V192a20,20,0,0,0,20,20H224a20,20,0,0,0,20-20V64A20,20,0,0,0,224,44Zm-4,144H36V68H220ZM52,128a44,44,0,0,1,66-38.11,12,12,0,0,1-12,20.78,20,20,0,1,0,0,34.66,12,12,0,1,1,12,20.77A44,44,0,0,1,52,128Zm80,0a44,44,0,0,1,66-38.11,12,12,0,0,1-12,20.78,20,20,0,1,0,0,34.66,12,12,0,1,1,12,20.77A44,44,0,0,1,132,128Z"/>',
};

const icon = (name) => `<svg class="icon" viewBox="0 0 256 256" aria-hidden="true">${ICONS[name]}</svg>`;

const SECTION_TITLES = {
  subscriptions: "Subscriptions",
  watchLater: "Watch Later",
  downloaded: "Downloaded",
};
const EMPTY_TEXT = {
  watchLater: "Watch Later is empty. Save videos on YouTube or from Subscriptions to see them here.",
  downloaded: "Nothing downloaded yet. Click a video in Watch Later to download and play it.",
};
const RESUME_MIN = 5;
const RESUME_END_MARGIN = 10;
const SKIP = 5;
const FLASH_MS = 600;
const SORT_LABELS = { added: "Date added", published: "Date published", title: "Title", duration: "Length" };
const DEFAULT_SORTS = {
  subscriptions: { key: "published", ascending: false },
  channel: { key: "published", ascending: false },
  watchLater: { key: "added", ascending: true },
  downloaded: { key: "added", ascending: true },
};
const WEDGE_C = 2 * Math.PI * 10;

const $ = (sel, root = document) => root.querySelector(sel);

const store = {
  get(key, fallback) {
    try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
  },
  set(key, value) { localStorage.setItem(key, JSON.stringify(value)); },
};

const settings = Object.assign(
  { section: "watchLater", view: "grid", sorts: {},
    speed: 1, captions: false, transcript: false },
  store.get("wb.settings", {}),
);
const isFeed = (section) => section === "subscriptions" || section === "channel";
if (!SECTION_TITLES[settings.section] && !(settings.section === "channel" && settings.channel)) {
  settings.section = "watchLater";
}
const saveSettings = () => store.set("wb.settings", settings);
const positions = store.get("wb.positions", {});
const savePositions = () => store.set("wb.positions", positions);

let state = { watchLater: [], subscriptions: [], downloads: {}, local: new Set(), loading: true, error: null };
let pendingPlay = null;
const channels = { list: null, loading: false, failed: false };
const channelView = {
  id: null, videos: [], end: false, loading: false, loadingMore: false, failed: false, subscribing: false,
};
let channelRequest = 0;
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
    state.error = "Lost the connection to the server. Open WatchBar again to restart it.";
    render();
  }
  const busy = state.loading || state.loadingMore || Object.keys(state.downloads || {}).some(
    (id) => ["queued", "downloading"].includes(state.downloads[id].status));
  pollTimer = setTimeout(poll, busy ? 1000 : 15000);
}

async function act(path, id, options = {}) {
  try {
    applyState(await api(path, id ? { id, ...options } : {}));
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
  if (isFeed(section)) {
    const feed = section === "channel" ? channelView.videos : state.subscriptions;
    vids = feed.map((v) => ({ ...v, inWatchLater: wlIds.has(v.id) }));
  } else if (section === "watchLater") {
    vids = state.watchLater.slice();
  } else {
    vids = state.watchLater.concat(state.otherDownloads || [])
      .filter((v) => state.local.has(v.id) || state.downloads[v.id]);
  }
  return sortVideos(vids, sortFor(section));
}

function sortFor(section) {
  return settings.sorts[section] || DEFAULT_SORTS[section];
}

function setSort(changes) {
  settings.sorts[settings.section] = { ...sortFor(settings.section), ...changes };
  saveSettings();
  render();
}

// Watch Later arrives in playlist order, which is the order videos were added.
function sortVideos(vids, { key, ascending }) {
  const dir = ascending ? 1 : -1;
  if (key === "title") {
    vids.sort((a, b) => dir * a.title.localeCompare(b.title));
  } else if (key === "duration") {
    vids.sort((a, b) => dir * (a.duration - b.duration));
  } else if (key === "published") {
    const dated = vids.filter((v) => v.timestamp).sort((a, b) => dir * (a.timestamp - b.timestamp));
    vids = dated.concat(vids.filter((v) => !v.timestamp));
  } else if (!ascending) {
    vids.reverse();
  }
  return vids;
}

function renderSortSelect(section, key) {
  const select = $('[data-action="sort"]');
  const keys = Object.keys(SORT_LABELS).filter((k) => k !== "added" || !isFeed(section));
  if (select.dataset.keys !== keys.join()) {
    select.dataset.keys = keys.join();
    select.innerHTML = keys.map((k) => `<option value="${k}">${SORT_LABELS[k]}</option>`).join("");
  }
  select.value = key;
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
  markCurrentChannel();
  const onChannel = section === "channel";
  $(".section-title").textContent = onChannel ? settings.channel.name : SECTION_TITLES[section];
  const refreshing = state.loading || (onChannel && channelView.loading && !channelView.loadingMore);

  const active = Object.values(state.downloads || {}).filter(
    (d) => d.status === "downloading" || d.status === "queued").length;
  const status = $(".status");
  status.classList.toggle("error", Boolean(state.error));
  status.textContent = state.error
    || (refreshing && (state.loading || channelView.videos.length) ? "Refreshing from YouTube..." : "")
    || (active ? `Downloading ${active} ${active === 1 ? "video" : "videos"}` : "");

  $('[data-action="download-all"]').hidden = section !== "watchLater";
  $('[data-action="open-channel"]').hidden = !onChannel;
  renderSubscribeButton(onChannel);
  $('[data-action="refresh"]').classList.toggle("spin", refreshing);
  for (const btn of document.querySelectorAll("[data-view]")) {
    btn.setAttribute("aria-pressed", String(btn.dataset.view === settings.view));
  }
  const sort = sortFor(section);
  renderSortSelect(section, sort.key);
  $('[data-action="direction"]').innerHTML = icon(sort.ascending ? "up" : "down");

  const list = $(".videos");
  list.className = `videos ${settings.view}`;
  const vids = videosFor(section);
  const mode = onChannel ? "subscriptions" : section;
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
  const loadMore = $(".load-more");
  empty.hidden = vids.length > 0;
  empty.textContent = refreshing && !vids.length ? "Loading..."
    : onChannel && channelView.failed ? "Videos did not load. Refresh to try again."
    : onChannel ? "This channel has no videos."
    : section === "subscriptions"
      ? `No uploads from your subscriptions in the past ${state.subscriptionDays} days.`
      : EMPTY_TEXT[section];
  const more = onChannel
    ? { show: !channelView.end && vids.length > 0, busy: channelView.loadingMore }
    : { show: section === "subscriptions" && !state.subscriptionsEnd && !(state.loading && !vids.length),
        busy: state.loadingMore };
  loadMore.hidden = !more.show;
  loadMore.disabled = Boolean(more.busy);
  loadMore.textContent = more.busy ? "Loading..." : "Load more";
}

async function loadChannelVideos(mode = "") {
  const id = settings.channel.id;
  if (channelView.id !== id) {
    Object.assign(channelView, { id, videos: [], end: false, failed: false });
  }
  const request = ++channelRequest;
  channelView.loading = true;
  channelView.loadingMore = mode === "more";
  render();
  let data = null;
  try {
    data = await api(`/api/channel/${encodeURIComponent(id)}${mode ? `?${mode}=1` : ""}`);
  } catch {}
  if (request !== channelRequest) return;
  channelView.loading = channelView.loadingMore = false;
  channelView.failed = !data;
  if (data) {
    channelView.videos = data.videos;
    channelView.end = data.end;
  }
  render();
}

function renderSubscribeButton(onChannel) {
  const button = $(".subscribe");
  button.hidden = !onChannel || !channels.list;
  if (button.hidden) return;
  const subscribed = channels.list.some((c) => c.id === settings.channel.id);
  button.classList.toggle("subscribed", subscribed);
  button.disabled = channelView.subscribing;
  button.textContent = channelView.subscribing
    ? (subscribed ? "Unsubscribing..." : "Subscribing...")
    : (subscribed ? "Unsubscribe" : "Subscribe");
}

async function setSubscribed(subscribed) {
  channelView.subscribing = true;
  render();
  try {
    const data = await api("/api/subscription", { channel: settings.channel, subscribed });
    if (data.channels) channels.list = data.channels;
    if (!data.ok) {
      state.error = `${subscribed ? "Subscribing" : "Unsubscribing"} failed. Check that Safari is signed in to YouTube.`;
    }
  } catch (e) {
    state.error = e.message;
  }
  channelView.subscribing = false;
  renderChannels();
  render();
}

function markCurrentChannel() {
  for (const row of document.querySelectorAll(".channel")) {
    const current = settings.section === "channel" && row.dataset.channelId === settings.channel.id;
    row.setAttribute("aria-current", String(current));
  }
}

async function loadChannels(force = false) {
  if (channels.loading) return;
  channels.loading = true;
  renderChannels();
  try {
    const data = await api(`/api/channels${force ? "?refresh=1" : ""}`);
    channels.failed = data.channels === null;
    channels.list = data.channels ?? channels.list;
  } catch {
    channels.failed = true;
  }
  channels.loading = false;
  renderChannels();
}

function renderChannels() {
  const note = channels.list?.length ? ""
    : channels.loading ? "Loading..."
    : channels.failed ? "Did not load. Refresh to try again."
    : channels.list ? "No subscriptions" : "";
  const rows = note ? [noteRow(note)] : (channels.list || []).map(channelRow);
  $(".channel-list").replaceChildren(...rows);
  markCurrentChannel();
}

function noteRow(text) {
  const li = document.createElement("li");
  li.className = "channel-note";
  li.textContent = text;
  return li;
}

function channelRow(channel) {
  const button = document.createElement("button");
  button.className = "channel";
  button.dataset.section = "channel";
  button.dataset.channelId = channel.id;
  const avatar = document.createElement("img");
  avatar.loading = "lazy";
  avatar.alt = "";
  if (channel.avatar) avatar.src = channel.avatar;
  const name = document.createElement("span");
  name.textContent = channel.name;
  button.append(avatar, name);
  const li = document.createElement("li");
  li.append(button);
  return li;
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
    const fraction = waiting ? 0 : pct / 100;
    const overlay = document.createElement("div");
    overlay.className = "fetching";
    overlay.innerHTML = `<svg class="stopwatch${waiting ? " waiting" : ""}" viewBox="0 0 60 68" aria-hidden="true">
      <rect class="crown" x="24" y="0" width="12" height="9" rx="3"/>
      <circle class="case" cx="30" cy="38" r="28"/>
      <circle class="face" cx="30" cy="38" r="21"/>
      <circle class="wedge" cx="30" cy="38" r="10" transform="rotate(-90 30 38)"
        stroke-dasharray="${WEDGE_C}" stroke-dashoffset="${WEDGE_C * (1 - fraction)}"/>
      <line class="hand" x1="30" y1="38" x2="30" y2="21" transform="rotate(${fraction * 360} 30 38)"/>
      <circle class="pin" cx="30" cy="38" r="3.5"/></svg>`;
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
  if (mode !== "downloaded") button("youtube", "youtube", "Open on YouTube");
  if (fetching) {
    button("stop", "cancel", "Stop download");
  } else if (local && mode !== "downloaded") {
    button("done", "delete", "Delete download", "downloaded").innerHTML += icon("undownload");
  } else if (mode !== "downloaded") {
    button("download", "download", "Download");
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
const scrubPreview = $(".scrub-preview");
const previewCanvas = $(".scrub-preview canvas");
const previewVideo = document.createElement("video");
previewVideo.muted = true;
previewVideo.preload = "auto";
let previewTarget = null;
let previewSeeking = false;
const speedInput = $(".speed input");
const linesEl = $(".transcript-lines");
const flashEl = $(".flash");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
const transcriptPanel = $(".transcript");
let playing = null;
let transcript = { starts: [], rows: [] };
let currentLine = -1;
let skipShown = 0;
let skipShownAt = 0;
let followPaused = false;
let scrubbing = false;
let lastSave = 0;

function findVideo(id) {
  return state.watchLater.find((v) => v.id === id)
    || state.subscriptions.find((v) => v.id === id)
    || channelView.videos.find((v) => v.id === id)
    || (state.otherDownloads || []).find((v) => v.id === id)
    || { id, title: "", duration: 0 };
}

async function openPlayer(id) {
  playing = findVideo(id);
  $(".now-playing").textContent = playing.title;
  document.title = `${playing.title} - WatchBar`;
  theater.hidden = false;
  for (const t of videoEl.querySelectorAll("track")) t.remove();
  videoEl.src = `/media/${id}.mp4`;
  previewVideo.src = videoEl.src;
  previewCanvas.getContext("2d").clearRect(0, 0, previewCanvas.width, previewCanvas.height);
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
  previewVideo.removeAttribute("src");
  previewVideo.load();
  scrubPreview.hidden = true;
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
  flashSkip(seconds);
}

function flash(html, position) {
  flashEl.className = `flash ${position}`;
  flashEl.innerHTML = html;
  void flashEl.offsetWidth;
  flashEl.classList.add("show");
}

function toggleFromScreen() {
  if (!playing) return;
  togglePlay();
  flash(icon(videoEl.paused ? "pause" : "play"), "center");
}

// Repeated skips in one direction add up while the indicator is visible.
function flashSkip(seconds) {
  const now = Date.now();
  const continues = now - skipShownAt < FLASH_MS && Math.sign(skipShown) === Math.sign(seconds);
  skipShown = continues ? skipShown + seconds : seconds;
  skipShownAt = now;
  flash(`${skipShown > 0 ? "+" : "\u2212"}${Math.abs(skipShown)}s`, skipShown > 0 ? "forward" : "back");
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
  if (open) resumeFollow("instant");
}

async function loadTranscript(id) {
  linesEl.innerHTML = "";
  transcript = { starts: [], rows: [] };
  currentLine = -1;
  setFollowPaused(false);
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
  followTranscript(videoEl.currentTime, true, "instant");
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

function followTranscript(time, force, behavior = "smooth") {
  if ($(".transcript").hidden || !transcript.starts.length) return;
  let lo = 0, hi = transcript.starts.length - 1, index = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (transcript.starts[mid] <= time + 0.05) { index = mid; lo = mid + 1; } else hi = mid - 1;
  }
  if (index === currentLine && !force) return;
  transcript.rows[currentLine]?.classList.remove("current");
  currentLine = index;
  const row = transcript.rows[index];
  if (!row) return;
  row.classList.add("current");
  if (force || !followPaused) {
    transcriptPanel.scrollTo({
      top: row.offsetTop - transcriptPanel.clientHeight / 3,
      behavior: reduceMotion.matches ? "instant" : behavior,
    });
  }
}

function setFollowPaused(paused) {
  followPaused = paused;
  $(".resync").hidden = !paused;
}

function resumeFollow(behavior) {
  setFollowPaused(false);
  followTranscript(videoEl.currentTime, true, behavior);
}

function pauseFollow() {
  if (transcriptPanel.scrollHeight > transcriptPanel.clientHeight) setFollowPaused(true);
}

// Listen for user input; "scroll" also fires when the transcript follows the video.
transcriptPanel.addEventListener("wheel", pauseFollow, { passive: true });
transcriptPanel.addEventListener("touchmove", pauseFollow, { passive: true });
transcriptPanel.addEventListener("pointerdown", (e) => {
  if (e.target === transcriptPanel) pauseFollow();
});

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

const SCRUB_THUMB = 16;
const PREVIEW_WIDTH = 176;

scrubber.addEventListener("pointermove", (e) => {
  const duration = Number(scrubber.max);
  if (!playing || e.pointerType === "touch" || !(duration > 0)) return;
  const rect = scrubber.getBoundingClientRect();
  const track = rect.width - SCRUB_THUMB;
  const fraction = Math.min(1, Math.max(0, (e.clientX - rect.left - SCRUB_THUMB / 2) / track));
  const time = fraction * duration;
  $(".scrub-time").textContent = fmtDuration(time);
  const half = PREVIEW_WIDTH / 2 + 4;
  const x = Math.min(window.innerWidth - half, Math.max(half, e.clientX));
  scrubPreview.style.left = `${x - rect.left}px`;
  scrubPreview.hidden = false;
  requestPreview(time);
});
scrubber.addEventListener("pointerleave", () => { scrubPreview.hidden = true; });

// Seek only to the latest hovered time once the previous seek finishes, so
// the preview keeps up with fast mouse movement.
function requestPreview(time) {
  previewTarget = time;
  if (!previewSeeking) seekPreview();
}

function seekPreview() {
  if (previewTarget === null) return;
  previewSeeking = true;
  previewVideo.currentTime = previewTarget;
  previewTarget = null;
}

previewVideo.addEventListener("loadedmetadata", () => {
  previewCanvas.width = PREVIEW_WIDTH * devicePixelRatio;
  previewCanvas.height = Math.round(previewCanvas.width * previewVideo.videoHeight / previewVideo.videoWidth);
});
previewVideo.addEventListener("seeked", () => {
  previewCanvas.getContext("2d").drawImage(previewVideo, 0, 0, previewCanvas.width, previewCanvas.height);
  previewSeeking = false;
  seekPreview();
});

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

$(".screen").addEventListener("click", toggleFromScreen);
linesEl.addEventListener("click", (e) => {
  const li = e.target.closest(".line");
  if (!li) return;
  videoEl.currentTime = Number(li.dataset.at);
  resumeFollow();
});

theater.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-action]");
  if (!btn) return;
  btn.blur();
  const action = btn.dataset.action;
  if (action === "close-player") closePlayer();
  else if (action === "play") togglePlay();
  else if (action === "resync") resumeFollow();
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
  if (e.key === " ") { e.preventDefault(); toggleFromScreen(); }
  else if (e.key === "ArrowLeft") { e.preventDefault(); skip(-SKIP); }
  else if (e.key === "ArrowRight") { e.preventDefault(); skip(SKIP); }
  else if (e.key === "Escape") closePlayer();
});

/* Library events */

// Videos from a channel page download without being saved to Watch Later.
const downloadOptions = () => (settings.section === "channel" ? { watchLater: false } : {});

function openVideo(id) {
  if (state.local.has(id)) {
    openPlayer(id);
  } else {
    pendingPlay = id;
    act("/api/download", id, downloadOptions());
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
  else if (action === "download") act("/api/download", id, downloadOptions());
  else if (action === "add") act("/api/watch-later/add", id);
  else if (action === "remove") act("/api/watch-later/remove", id);
  else if (action === "delete") act("/api/delete-local", id);
  else if (action === "cancel") {
    if (pendingPlay === id) pendingPlay = null;
    act("/api/cancel", id);
  }
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
  if (target.dataset.channelId) {
    settings.channel = channels.list.find((c) => c.id === target.dataset.channelId);
  }
  saveSettings();
  window.scrollTo({ top: 0 });
  if (settings.section === "channel") loadChannelVideos();
  else render();
});

$(".toolbar").addEventListener("click", (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  if (btn.dataset.view) {
    settings.view = btn.dataset.view;
    saveSettings();
    render();
  } else if (btn.dataset.action === "direction") {
    setSort({ ascending: !sortFor(settings.section).ascending });
  } else if (btn.dataset.action === "refresh") {
    act("/api/refresh");
    loadChannels(true);
    if (settings.section === "channel") loadChannelVideos("refresh");
  } else if (btn.dataset.action === "open-channel") {
    window.open(`https://www.youtube.com/channel/${encodeURIComponent(settings.channel.id)}`, "_blank");
  } else if (btn.dataset.action === "download-all") {
    act("/api/download-all");
  }
});
$(".subscribe").addEventListener("click", (e) => {
  setSubscribed(!e.currentTarget.classList.contains("subscribed"));
});
$(".load-more").addEventListener("click", () => {
  if (settings.section === "channel") loadChannelVideos("more");
  else act("/api/subscriptions/more");
});
$('[data-action="sort"]').addEventListener("change", (e) => setSort({ key: e.target.value }));

/* Static icons */

$('[data-action="open-channel"]').innerHTML = icon("youtube");
$('[data-action="download-all"]').innerHTML = icon("downloadAll");
$('[data-action="refresh"]').innerHTML = icon("refresh");
$('[data-view="grid"]').innerHTML = icon("grid");
$('[data-view="list"]').innerHTML = icon("list");
$('[data-action="close-player"]').innerHTML = icon("back");
$('[data-action="captions"]').innerHTML = icon("captions");
$('[data-action="transcript"]').innerHTML = icon("transcript");
applySpeed();

document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });
window.addEventListener("pagehide", () => {
  rememberPosition(true);
  navigator.sendBeacon("/api/bye");
});
render();
poll();
loadChannels();
if (settings.section === "channel") loadChannelVideos();
