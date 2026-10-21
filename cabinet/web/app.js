/* GateX personal cabinet (Telegram Mini App). No build step, no framework.
 * Data: POST api/me with Telegram initData (see ../server/app.py).
 * Outside Telegram the page shows a gate screen, or demo data in preview builds. */
(function () {
  'use strict';

  // ------------------------------------------------------------ helpers
  const $ = (s, r = document) => r.querySelector(s);
  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ESC[c]);
  const DAY = 86400000;

  function plural(n, forms) {
    const a = Math.abs(n) % 100, b = a % 10;
    if (a > 10 && a < 20) return forms[2];
    if (b > 1 && b < 5) return forms[1];
    if (b === 1) return forms[0];
    return forms[2];
  }
  function fmtDate(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return '';
    return d.toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' }).replace(/\s?г\.?$/, '');
  }
  function money(n) {
    return Math.round(n).toLocaleString('ru-RU').replace(/\s/g, '\u00a0') + '\u00a0₽';
  }
  function fmtAgo(iso) {
    const t = new Date(iso).getTime();
    if (!t) return null;
    const m = Math.round((Date.now() - t) / 60000);
    if (m < 3) return 'сейчас в сети';
    if (m < 60) return m + ' ' + plural(m, ['минуту', 'минуты', 'минут']) + ' назад';
    const h = Math.round(m / 60);
    if (h < 24) return h + ' ' + plural(h, ['час', 'часа', 'часов']) + ' назад';
    const d = Math.round(h / 24);
    if (d === 1) return 'вчера';
    if (d < 30) return d + ' ' + plural(d, ['день', 'дня', 'дней']) + ' назад';
    return fmtDate(iso);
  }
  function store(key, val) {
    try {
      if (val === undefined) return localStorage.getItem(key);
      localStorage.setItem(key, val);
    } catch (e) { /* storage blocked */ }
    return null;
  }

  // ------------------------------------------------------------ icons
  const P = {
    home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    plug: '<path d="M9 2v5M15 2v5M6 7h12v4a6 6 0 0 1-12 0zM12 17v5"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.2a2.6 2.6 0 0 1 5 .8c0 1.7-2.5 2.3-2.5 4"/><path d="M12 17.5h.01"/>',
    copy: '<rect x="9" y="9" width="12" height="12" rx="2.5"/><path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    chevR: '<path d="m9 6 6 6-6 6"/>',
    chevL: '<path d="m15 6-6 6 6 6"/>',
    close: '<path d="M18 6 6 18M6 6l12 12"/>',
    download: '<path d="M12 3v12m0 0 5-5m-5 5-5-5M4 21h16"/>',
    qr: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><path d="M14 14h3v3h-3zM21 14v.01M14 21h.01M17.5 21H21v-3.5"/>',
    phone: '<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M11 18h2"/>',
    monitor: '<rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>',
    laptop: '<rect x="4" y="4" width="16" height="11" rx="1.5"/><path d="M2 19h20"/>',
    tv: '<rect x="2" y="7" width="20" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>',
    terminal: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="m7 9 3 3-3 3M13 15h4"/>',
    bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
    gift: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M5 12v9h14v-9M12 8v13M12 8s-1.5-5-4-5a2.5 2.5 0 0 0 0 5M12 8s1.5-5 4-5a2.5 2.5 0 0 1 0 5"/>',
    megaphone: '<path d="M3 11v3a1 1 0 0 0 1 1h3l6 4V6L7 10H4a1 1 0 0 0-1 1zM17 9a4 4 0 0 1 0 6"/>',
    send: '<path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/>',
    card: '<rect x="2" y="5" width="20" height="14" rx="2.5"/><path d="M2 10h20M6 15h4"/>',
    chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L3 21l1.9-6.4A8 8 0 1 1 21 12z"/><path d="M8.5 12h.01M12 12h.01M15.5 12h.01"/>',
    book: '<path d="M4 19.5V5a2.5 2.5 0 0 1 2.5-2.5H20v17H6.5A2.5 2.5 0 0 0 4 22a2.5 2.5 0 0 1 0-2.5"/><path d="M8 7h8M8 11h6"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    power: '<path d="M12 2v9"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/>',
    signal: '<path d="M2 20h.01M7 20v-4M12 20v-8M17 20V8M22 20V4"/>',
    spark: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M5.6 5.6l2.8 2.8M15.6 15.6l2.8 2.8M5.6 18.4l2.8-2.8M15.6 8.4l2.8-2.8"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5h.01"/>',
    refresh: '<path d="M20 11a8 8 0 0 0-14.9-3M4 4v4h4M4 13a8 8 0 0 0 14.9 3M20 20v-4h-4"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>'
  };
  // Outlined GX monogram from the brand kit (avatar/outline): G in the text
  // colour, X in the accent, so the status tone still recolours it.
  const GX_G = 'M512.0 242.0H717.52978515625Q714.1874389648438 237.40289306640625 710.5 233.0Q677.0 193.0 621.0 172.5Q565.0 152.0 492.0 152.0Q417.0 152.0 361.5 177.0Q306.0 202.0 276.0 252.0Q246.0 302.0 246.0 375.0Q246.0 447.0 274.0 495.5Q302.0 544.0 353.0 568.5Q404.0 593.0 474.0 593.0Q532.0 593.0 577.5 578.5Q623.0 564.0 653.5 536.5Q684.0 509.0 694.0 471.0H903.0Q887.0 558.0 832.0 624.0Q777.0 690.0 687.0 728.0Q597.0 766.0 473.0 766.0Q380.0 766.0 301.5 740.5Q223.0 715.0 163.5 665.0Q104.0 615.0 71.0 542.0Q38.0 469.0 38.0 375.0Q38.0 281.0 70.5 208.0Q103.0 135.0 161.5 85.0Q220.0 35.0 297.0 9.5Q374.0 -16.0 462.0 -16.0Q554.0 -16.0 623.5 11.0Q693.0 38.0 739.5 86.0Q746.5777587890625 93.30607604980469 753.1454467773438 100.92444610595703L763.0 0.0H910.0V388.0H512.0Z';
  const GX_X = 'M564.4285888671875 389.6925048828125 860.0 750.0H605.0L438.6498718261719 532.288330078125L270.0 750.0H11.0L308.06060791015625 389.7713317871094L-11.0 0.0H241.0L433.895263671875 248.2340850830078L626.0 0.0H881.0L564.4285888671875 389.6925048828125Z';
  const gx = (cls) => '<svg class="gx' + (cls ? ' ' + cls : '') + '" viewBox="28 -776 1874 802" aria-hidden="true"><g transform="scale(1 -1)">' +
    '<path class="gx-g" d="' + GX_G + '"/><g transform="translate(1011 0)"><path class="gx-x" d="' + GX_X + '"/></g></g></svg>';
  const ic = (name, cls) => '<svg class="icon' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" aria-hidden="true">' + (P[name] || '') + '</svg>';

  // ------------------------------------------------------------ platforms
  const HAPP = 'https://github.com/Happ-proxy/happ-desktop/releases/latest/download/';
  const PLATFORMS = {
    ios: {
      name: 'iPhone и iPad', label: 'iPhone', icon: 'phone', sub: 'iOS, iPadOS',
      stores: [
        { title: 'App Store', note: 'Apple ID из России', url: 'https://apps.apple.com/ru/app/happ-lite/id6799917773', main: true },
        { title: 'App Store', note: 'Apple ID другой страны', url: 'https://apps.apple.com/us/app/happ-proxy-utility/id6504287215' }
      ],
      install: 'Откройте App Store и установите Happ. Если у вас российский Apple ID, берите первую кнопку, если зарубежный, вторую.',
      allow: 'iPhone спросит «Разрешить добавление конфигураций VPN?». Нажмите «Разрешить» и подтвердите код-паролем или Face ID.'
    },
    android: {
      name: 'Android', label: 'Android', icon: 'phone', sub: 'телефоны и планшеты',
      stores: [
        { title: 'Google Play', note: 'обычная установка', url: 'https://play.google.com/store/apps/details?id=com.happproxy', main: true },
        { title: 'Скачать APK', note: 'если Google Play не открывается', url: 'https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk' }
      ],
      install: 'Установите Happ из Google Play. Если магазина нет или он не открывается, скачайте APK и разрешите браузеру установку приложений.',
      allow: 'Android покажет «Запрос на подключение». Нажмите «ОК», это разрешение для VPN.'
    },
    windows: {
      name: 'Windows', label: 'Windows', icon: 'monitor', sub: 'Windows 10 и 11',
      stores: [
        { title: 'Скачать для Windows', note: 'обычный компьютер (x64)', url: HAPP + 'setup-Happ.x64.exe', main: true },
        { title: 'Версия для ARM', note: 'Surface и ноутбуки на Snapdragon', url: HAPP + 'setup-Happ.arm64.exe' }
      ],
      install: 'Скачайте установщик и запустите его. Если появится синее окно SmartScreen, нажмите «Подробнее», затем «Выполнить в любом случае».',
      allow: 'Если Windows спросит разрешение на изменения, нажмите «Да».'
    },
    macos: {
      name: 'macOS', label: 'Mac', icon: 'laptop', sub: 'MacBook, iMac',
      stores: [
        { title: 'App Store', note: 'Apple ID из России', url: 'https://apps.apple.com/ru/app/happ-proxy-utility/id6783623643', main: true },
        { title: 'App Store', note: 'Apple ID другой страны', url: 'https://apps.apple.com/us/app/happ-proxy-utility/id6504287215' },
        { title: 'Скачать DMG', note: 'без App Store', url: HAPP + 'Happ.macOS.universal.dmg' }
      ],
      install: 'Установите Happ из App Store. Без App Store скачайте DMG и перетащите Happ в «Программы».',
      allow: 'macOS попросит разрешить добавление конфигурации VPN. Нажмите «Разрешить».'
    },
    linux: {
      name: 'Linux', label: 'Linux', icon: 'terminal', sub: 'Ubuntu, Fedora, Arch',
      stores: [
        { title: 'Пакет .deb', note: 'Ubuntu, Debian, Mint', url: HAPP + 'Happ.linux.x64.deb', main: true },
        { title: 'Пакет .rpm', note: 'Fedora, openSUSE', url: HAPP + 'Happ.linux.x64.rpm' }
      ],
      install: 'Скачайте пакет под ваш дистрибутив и установите его двойным кликом или через пакетный менеджер.',
      allow: 'Для режима VPN Happ может попросить пароль администратора.'
    },
    tv: {
      name: 'Телевизор', label: 'ТВ', icon: 'tv', sub: 'Android TV, Apple TV',
      stores: [
        { title: 'Google Play', note: 'Android TV, Google TV', url: 'https://play.google.com/store/apps/details?id=com.happproxy', main: true },
        { title: 'App Store', note: 'Apple TV', url: 'https://apps.apple.com/us/app/happ-proxy-utility-for-tv/id6748297274' }
      ],
      install: 'На телевизоре откройте магазин приложений, найдите Happ и установите. Кнопки ниже откроют страницу приложения, чтобы проверить название.',
      allow: 'Телевизор спросит разрешение на VPN. Подтвердите пультом.'
    }
  };
  const PLATFORM_ORDER = ['ios', 'android', 'windows', 'macos', 'linux', 'tv'];

  function detectPlatform() {
    const tp = state.tg && state.tg.platform;
    if (tp === 'ios') return 'ios';
    if (tp === 'android' || tp === 'android_x') return 'android';
    if (tp === 'macos') return 'macos';
    if (tp === 'tdesktop' || tp === 'unigram') {
      return /Mac/i.test(navigator.userAgent) ? 'macos' : /Linux/i.test(navigator.userAgent) ? 'linux' : 'windows';
    }
    const ua = navigator.userAgent;
    if (/iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) return 'ios';
    if (/Android/i.test(ua)) return /TV|AFT|BRAVIA/i.test(ua) ? 'tv' : 'android';
    if (/Windows/i.test(ua)) return 'windows';
    if (/Mac/i.test(ua)) return 'macos';
    if (/Linux|X11/i.test(ua)) return 'linux';
    return 'android';
  }

  // ------------------------------------------------------------ demo data
  const DEMO_SCENARIOS = {
    fresh: { label: 'Новый пользователь, пробный период', days: 3, trial: true, used: 0, connected: false, onboard: true, devices: 0 },
    active: { label: 'Активная подписка', days: 23, used: 18.6 * 1073741824, connected: true, devices: 2, tariff: { code: 'family', title: 'Семейный', bypass: true, devices: 7 } },
    expiring: { label: 'Заканчивается завтра, все места заняты', days: 1, used: 41.2 * 1073741824, limit: 50 * 1073741824, connected: true, devices: 3 },
    legacy: { label: 'Старый тариф, подписка активна', days: 40, used: 52.3 * 1073741824, connected: true, devices: 3 },
    expired: { label: 'Подписка закончилась', days: -4, used: 7.3 * 1073741824, connected: true, status: 'expired', devices: 1 },
    none: { label: 'Нет подписки', status: 'none' }
  };
  const DEMO_DEVICES = [
    { id: 'd1', platform: 'iOS', os_version: '18.1', model: 'iPhone15,2', app: 'Happ/3.6.2', seenMin: 12, addedDays: 20 },
    { id: 'd2', platform: 'Windows', os_version: '11', model: 'DESKTOP-K7Q2', app: 'Happ/1.9.0', seenMin: 3 * 1440, addedDays: 14 },
    { id: 'd3', platform: 'Android', os_version: '14', model: 'Redmi Note 12', app: 'Happ/3.5.0', seenMin: 26 * 1440, addedDays: 40 }
  ];
  // same numbers as server/plans.py; the live page gets them from api/me
  const DEMO_PLANS = {
    months: [{ months: 1, discount: 0 }, { months: 3, discount: 10 }, { months: 6, discount: 15 }, { months: 12, discount: 25 }],
    plans: [
      { code: 'eco', title: 'Эконом', base_devices: 2, device_steps: [2, 4, 6, 8],
        prices: { plain: { 1: 50, 3: 135, 6: 255, 12: 450 }, bypass: { 1: 100, 3: 270, 6: 510, 12: 900 } } },
      { code: 'family', title: 'Семейный', base_devices: 7, device_steps: [7, 14, 21],
        prices: { plain: { 1: 199, 3: 539, 6: 999, 12: 1790 }, bypass: { 1: 399, 3: 1079, 6: 1990, 12: 3590 } } }
    ]
  };
  function demoData(key) {
    const s = DEMO_SCENARIOS[key];
    const sub = s.status === 'none' ? { status: 'none' } : {
      status: s.status || 'active',
      expire_at: new Date(Date.now() + s.days * DAY + 3600000).toISOString(),
      is_trial: !!s.trial,
      used_bytes: s.used || 0,
      limit_bytes: s.limit || 0,
      device_limit: s.trial ? 2 : s.tariff ? s.tariff.devices : 3,
      online_at: s.connected ? new Date(Date.now() - 12 * 60000).toISOString() : null,
      first_connected_at: s.connected ? new Date(Date.now() - 20 * DAY).toISOString() : null,
      sub_url: 'https://r1.fast-cloude-cdn.online/s/demo-7fK2pQ',
      mirror_url: 'https://app.fast-cloude-cdn.online/demo-7fK2pQ'
    };
    return {
      user: { id: 700123456, first_name: 'Иван', last_name: '', username: 'ivan_demo', photo_url: '' },
      subscription: sub,
      devices: s.status === 'none' ? [] : DEMO_DEVICES.slice(0, s.devices || 0).map((d) => Object.assign({}, d, {
        seen_at: new Date(Date.now() - d.seenMin * 60000).toISOString(),
        added_at: new Date(Date.now() - d.addedDays * DAY).toISOString()
      })),
      links: { bot: 'https://t.me/gatexvpn_bot', buy: 'https://t.me/gatexvpn_bot', support: 'https://t.me/gatexvpn_support', channel: 'https://t.me/gaatex_vpn', referral: 'https://t.me/gatexvpn_bot' },
      price_from: null,
      tariff: s.tariff || (s.trial ? { code: 'trial', title: 'Пробный', bypass: true, devices: 2 } : null),
      plans: DEMO_PLANS
    };
  }

  // ------------------------------------------------------------ state
  const state = {
    tg: null,
    demo: false,
    demoKey: 'fresh',
    demoMenu: false,
    data: null,
    error: null,
    tab: 'home',
    platform: 'android',
    confirmDevice: null,
    ref: null, // {link, count, bonus_days} from api/referral
    busy: false,
    removed: null,
    sheet: null // {kind:'welcome'} | {kind:'wizard', platform, remote, step} | {kind:'devices', remote}
  };
  const root = () => $('#app');

  // ------------------------------------------------------------ Telegram glue
  function loadTelegram() {
    return new Promise((resolve) => {
      if (!/tgWebApp/.test(location.hash + location.search)) return resolve(null);
      const s = document.createElement('script');
      s.src = 'https://telegram.org/js/telegram-web-app.js';
      s.onload = () => resolve(window.Telegram && window.Telegram.WebApp && window.Telegram.WebApp.initData ? window.Telegram.WebApp : null);
      s.onerror = () => resolve(null);
      document.head.appendChild(s);
    });
  }
  function haptic(kind) {
    try {
      const h = state.tg && state.tg.HapticFeedback;
      if (!h) return;
      if (kind === 'ok') h.notificationOccurred('success');
      else h.impactOccurred(kind || 'light');
    } catch (e) { /* old client */ }
  }
  // White, black or green; until the person picks one, follow Telegram (light → white, dark → green).
  const THEMES = [['light', 'Белая'], ['black', 'Чёрная'], ['green', 'Зелёная']];
  function themeChoice() {
    const t = state.theme || store('gx_theme');
    return THEMES.some(([k]) => k === t) ? t : null;
  }
  function applyTheme() {
    const tg = state.tg;
    const auto = (tg && tg.colorScheme === 'light') || (!tg && window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'green';
    document.documentElement.setAttribute('data-theme', themeChoice() || auto);
    if (tg) {
      const bg = getComputedStyle(document.documentElement).getPropertyValue('--bg').trim();
      try { tg.setHeaderColor(bg); tg.setBackgroundColor(bg); if (tg.setBottomBarColor) tg.setBottomBarColor(bg); } catch (e) { /* old client */ }
    }
  }
  function cloudGet(key) {
    return new Promise((resolve) => {
      const cs = state.tg && state.tg.CloudStorage;
      if (!cs || !state.tg.isVersionAtLeast || !state.tg.isVersionAtLeast('6.9')) return resolve(null);
      try { cs.getItem(key, (err, v) => resolve(err ? null : v)); } catch (e) { resolve(null); }
    });
  }
  function cloudSet(key, val) {
    const cs = state.tg && state.tg.CloudStorage;
    if (!cs || !state.tg.isVersionAtLeast || !state.tg.isVersionAtLeast('6.9')) return;
    try { cs.setItem(key, val); } catch (e) { /* ignore */ }
  }
  function setTheme(t) {
    state.theme = t;
    store('gx_theme', t);
    cloudSet('gx_theme', t);
    applyTheme();
    haptic('light');
    render();
  }
  function themeBlock() {
    const cur = document.documentElement.getAttribute('data-theme');
    return '<h2 class="h-section">Оформление</h2><div class="seg three" role="radiogroup" aria-label="Тема">' +
      THEMES.map(([k, label]) => '<button role="radio" aria-checked="' + (cur === k) + '" data-act="theme" data-theme="' + k + '">' +
        '<i class="swatch ' + k + '"></i><b>' + label + '</b></button>').join('') + '</div>';
  }

  function syncBackButton() {
    const bb = state.tg && state.tg.BackButton;
    if (!bb) return;
    if (state.sheet) bb.show(); else bb.hide();
  }

  // links: real <a href> everywhere; inside Telegram we route clicks through the SDK
  function openUrl(url) {
    if (!url) return;
    const tg = state.tg;
    if (tg) {
      if (/^https:\/\/t\.me\//.test(url)) tg.openTelegramLink(url);
      else tg.openLink(url);
    } else {
      window.open(url, '_blank', 'noopener');
    }
  }
  function openInHapp(subUrl) {
    const deeplink = 'happ://add/' + subUrl;
    if (state.demo) {
      toast('В демо ссылка не откроется. В Telegram откроется Happ');
      return;
    }
    // Telegram only opens http(s); open.html hands the custom scheme to the OS.
    const bounce = new URL('open.html', location.href);
    bounce.hash = encodeURIComponent(deeplink);
    openUrl(bounce.toString());
  }
  function copy(text, okMsg) {
    const done = () => { toast(okMsg || 'Скопировано'); haptic('ok'); };
    const fallback = () => {
      const ta = document.createElement('textarea');
      ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      let ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      ta.remove();
      if (ok) done(); else toast('Не получилось скопировать. Выделите ссылку и скопируйте вручную');
    };
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback);
      else fallback();
    } catch (e) { fallback(); }
  }
  let toastTimer = 0;
  function toast(msg) {
    let t = $('#toast');
    if (!t) { t = document.createElement('div'); t.id = 'toast'; t.className = 'toast'; t.setAttribute('role', 'status'); document.body.appendChild(t); }
    t.textContent = msg; t.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
  }

  // ------------------------------------------------------------ subscription view-model
  function vm() {
    const d = state.data;
    const s = (d && d.subscription) || { status: 'none' };
    const exp = s.expire_at ? new Date(s.expire_at).getTime() : 0;
    const daysLeft = exp ? Math.ceil((exp - Date.now()) / DAY) : null;
    let tone = 'ok', title = 'Подписка активна', badge = null;
    if (s.status === 'none') { tone = 'off'; title = 'Подписки пока нет'; }
    else if (s.status === 'expired' || (daysLeft !== null && daysLeft <= 0)) { tone = 'off'; title = 'Подписка закончилась'; badge = { cls: 'danger', text: 'не активна' }; }
    else if (s.status === 'limited') { tone = 'warn'; title = 'Трафик закончился'; badge = { cls: 'warn', text: 'лимит исчерпан' }; }
    else if (s.status === 'disabled') { tone = 'off'; title = 'Подписка отключена'; badge = { cls: 'danger', text: 'отключена' }; }
    else if (daysLeft !== null && daysLeft <= 3) { tone = 'warn'; badge = { cls: 'warn', text: 'осталось ' + daysLeft + ' ' + plural(daysLeft, ['день', 'дня', 'дней']) }; }
    else if (daysLeft !== null) { badge = { cls: 'ok', text: 'ещё ' + daysLeft + ' ' + plural(daysLeft, ['день', 'дня', 'дней']) }; }
    const active = tone !== 'off' && s.status !== 'limited';
    return { s, exp, daysLeft, tone, title, badge, active, links: (d && d.links) || {}, price: d && d.price_from,
      newFlow: !!(d && d.plans), tariff: (d && d.tariff) || null };
  }

  // ------------------------------------------------------------ screens
  function header() {
    return '<header class="topbar"><div class="brand"><span>Gate<b>X</b></span></div></header>';
  }

  function homeScreen() {
    const v = vm(), s = v.s;
    let sub = '';
    if (s.status === 'none') sub = '<span>' + (v.newFlow ? 'Выберите тариф, и здесь появится всё для подключения' : 'Оформите подписку в боте, и здесь появится всё для подключения') + '</span>';
    else if (v.exp) {
      const word = v.exp > Date.now() ? 'до ' : 'закончилась ';
      sub = '<span class="num">' + word + esc(fmtDate(s.expire_at)) + '</span>' + (v.badge ? '<span class="pill ' + v.badge.cls + '">' + esc(v.badge.text) + '</span>' : '');
    }

    let html = header();
    html += '<section class="hero" aria-label="Статус подписки">' +
      '<div class="gate" data-tone="' + v.tone + '"><i class="ring r1"></i><i class="ring r2"></i><i class="ring r3"></i><div class="core">' + gx() + '</div></div>' +
      '<h1 class="hero-title">' + esc(v.title) + '</h1><div class="hero-sub">' + sub + '</div></section>';

    html += '<div class="dock">';
    if (s.status !== 'none') html += '<div class="stats">' + tariffStat(v) + devicesStat(s) + '</div>';

    if (v.active && !s.first_connected_at) {
      html += '<button class="callout" data-act="setup-here">' +
        '<span class="ico">' + ic('bolt') + '</span><span><b>Вы ещё не подключались</b><span>Покажем по шагам, это пара минут</span></span><span class="chev">' + ic('chevR') + '</span></button>';
    }

    const price = v.price ? '<span class="spacer"></span><span class="aside">' + esc(v.price) + '</span>' : '';
    if (v.newFlow) {
      html += '<button class="btn white split" data-act="plans">' + ic('card') + '<span>Купить подписку</span><span class="spacer"></span><span class="aside">от ' + money(minPrice()) + '/мес</span></button>';
      if (s.status !== 'none') html += '<button class="btn primary split" data-act="tab" data-tab="setup">' + ic('plug') + '<span>Установка и настройка</span><span class="spacer"></span>' + ic(PLATFORMS[state.platform].icon, 'sm') + '</button>';
    } else if (s.status === 'none') {
      html += '<a class="btn primary split" href="' + esc(v.links.buy) + '" data-link>' + ic('gift') + '<span>Получить доступ</span>' + price + '</a>';
    } else {
      const buyLabel = v.active ? 'Продлить подписку' : 'Возобновить подписку';
      html += '<a class="btn ' + (v.active && v.tone === 'ok' ? 'ghost' : 'primary') + ' split" href="' + esc(v.links.buy) + '" data-link>' + ic('card') + '<span>' + buyLabel + '</span>' + price + '</a>';
      html += '<button class="btn ' + (v.active && v.tone === 'ok' ? 'primary' : 'invert') + ' split" data-act="tab" data-tab="setup">' + ic('plug') + '<span>Установка и настройка</span><span class="spacer"></span>' + ic(PLATFORMS[state.platform].icon, 'sm') + '</button>';
    }
    return html + '</div>';
  }

  function tariffStat(v) {
    const t = v.tariff;
    const value = t ? t.title + (t.code !== 'trial' && t.bypass ? ' + БС' : '') : 'Прежний';
    const inner = '<span class="k">Тариф</span><span class="v">' + esc(value) + '</span>';
    return v.newFlow ? '<button class="stat tappable" data-act="plans">' + inner + '</button>' : '<div class="stat">' + inner + '</div>';
  }

  function devicesStat(s) {
    const list = state.data && state.data.devices;
    const n = Array.isArray(list) ? list.length : null;
    const full = n !== null && s.device_limit && n >= s.device_limit;
    const value = n === null ? (s.device_limit ? 'до ' + s.device_limit : 'список') : n + (s.device_limit ? ' из ' + s.device_limit : '');
    return '<button class="stat tappable" data-act="my-devices"><span class="k">Устройства</span><span class="v">' + esc(value) +
      (full ? ' <span class="pill warn" style="vertical-align:2px">все места заняты</span>' : '') + '</span></button>';
  }

  // Panel platform strings vary by client ("iOS", "android", "Windows_NT"...).
  function deviceKind(d) {
    const p = (d.platform + ' ' + d.model + ' ' + d.app).toLowerCase();
    if (/tv|aft|bravia|tizen|webos/.test(p)) return { icon: 'tv', name: 'Телевизор' };
    if (/ios|iphone|ipad/.test(p)) return { icon: 'phone', name: /ipad/.test(p) ? 'iPad' : 'iPhone' };
    if (/android/.test(p)) return { icon: 'phone', name: 'Android' };
    if (/mac|darwin/.test(p)) return { icon: 'laptop', name: 'Mac' };
    if (/win/.test(p)) return { icon: 'monitor', name: 'Windows' };
    if (/linux/.test(p)) return { icon: 'terminal', name: 'Linux' };
    return { icon: 'phone', name: d.platform || 'Устройство' };
  }

  const IPHONES = {
    '13,1': '12 mini', '13,2': '12', '13,3': '12 Pro', '13,4': '12 Pro Max',
    '14,4': '13 mini', '14,5': '13', '14,2': '13 Pro', '14,3': '13 Pro Max', '14,6': 'SE',
    '14,7': '14', '14,8': '14 Plus', '15,2': '14 Pro', '15,3': '14 Pro Max',
    '15,4': '15', '15,5': '15 Plus', '16,1': '15 Pro', '16,2': '15 Pro Max',
    '17,3': '16', '17,4': '16 Plus', '17,1': '16 Pro', '17,2': '16 Pro Max', '17,5': '16e'
  };
  // Clients report raw ids like "iPhone15,2" or a PC hostname; show something a person recognises.
  function deviceTitle(d, k) {
    const m = (d.model || '').trim();
    const ip = /^iPhone(\d+,\d+)$/.exec(m);
    if (ip) return 'iPhone' + (IPHONES[ip[1]] ? ' ' + IPHONES[ip[1]] : '');
    if (!m || /^(desktop|laptop|pc)-/i.test(m) || /^(iPad|Mac)\d/.test(m)) return k.name;
    return m;
  }

  function devicesBlock() {
    const s = vm().s;
    if (s.status === 'none') return '';
    const list = state.data.devices;
    const limit = s.device_limit;
    let html = '<h2 class="h-section" id="my-devices">Мои устройства' + (Array.isArray(list) ? ' · ' + list.length + (limit ? ' из ' + limit : '') : '') + '</h2>';
    if (!Array.isArray(list)) {
      return html + '<div class="hint">' + ic('info') + '<span>Список устройств сейчас не загрузился. Откройте кабинет чуть позже.</span></div>';
    }
    html += '<div class="list">';
    if (!list.length) {
      html += '<div class="row" style="cursor:default"><span class="ico">' + ic('phone') + '</span><span class="txt"><b>Пока пусто</b><span style="white-space:normal">Устройство появится здесь после первого подключения в Happ</span></span></div>';
    }
    list.forEach((d) => {
      const k = deviceKind(d);
      const title = deviceTitle(d, k);
      const os = d.os_version
        ? ({ iPhone: 'iOS', iPad: 'iPadOS', Mac: 'macOS' }[k.name] || k.name) + ' ' + d.os_version
        : (k.name !== title ? k.name : '');
      const meta = [os, (d.app || '').split('/')[0]].filter(Boolean).join(' · ');
      const seen = d.seen_at ? fmtAgo(d.seen_at) : null;
      const confirming = state.confirmDevice === d.id;
      html += '<div class="device-row' + (confirming ? ' confirming' : '') + '">' +
        '<span class="ico">' + ic(k.icon) + '</span>' +
        '<span class="txt"><b>' + esc(title) + '</b><span>' + esc(meta) + '</span>' + (seen ? '<span>Активность: ' + esc(seen) + '</span>' : '') + '</span>' +
        (confirming
          ? '<span class="confirm-note">Удалить? VPN на нём отключится сразу, и само оно не вернётся. На остальных устройствах после этого обновите подписку в Happ.</span>' +
            '<span class="confirm"><button class="btn small danger" data-act="device-delete" data-id="' + esc(d.id) + '"' + (state.busy ? ' disabled' : '') + '>' + (state.busy === true ? 'Удаляем…' : 'Удалить') + '</button><button class="btn small ghost" data-act="device-cancel">Нет</button></span>'
          : '<button class="iconbtn" aria-label="Удалить ' + esc(title) + '" data-act="device-ask" data-id="' + esc(d.id) + '">' + ic('close', 'sm') + '</button>') +
        '</div>';
    });
    html += '<button class="row" data-act="devices" data-remote="1">' + rowInner('qr', 'Подключить ещё устройство', limit && list.length >= limit ? 'Сначала удалите одно из старых' : 'Инструкция и QR-код') + '</button></div>';
    html += '<p class="muted note">Удалите устройство, которым больше не пользуетесь: место освободится для нового. Удалённое устройство отключается и само не вернётся, а остальным нужно обновить подписку в Happ.</p>';
    html += removedBlock();
    return html;
  }

  // Removed devices stay blocked until the user brings them back here.
  function removedBlock() {
    const list = state.removed;
    if (!Array.isArray(list) || !list.length) return '';
    let html = '<h2 class="h-section">Удалённые устройства · ' + list.length + '</h2><div class="list">';
    list.forEach((d) => {
      const k = deviceKind(d);
      const title = deviceTitle(d, k);
      const meta = [k.name !== title ? k.name : '', (d.app || '').split('/')[0], d.removed_at ? 'удалено ' + fmtDate(d.removed_at) : ''].filter(Boolean).join(' · ');
      const busy = state.busy === 'restore:' + d.id;
      html += '<div class="device-row removed"><span class="ico">' + ic(k.icon) + '</span>' +
        '<span class="txt"><b>' + esc(title) + '</b><span>' + esc(meta) + '</span></span>' +
        '<button class="btn small ghost" data-act="device-restore" data-id="' + esc(d.id) + '"' + (state.busy ? ' disabled' : '') + '>' + (busy ? 'Возвращаем…' : 'Вернуть') + '</button></div>';
    });
    html += '</div><p class="muted note">Вернули устройство? Обновите на нём подписку в Happ, и VPN снова заработает.</p>';
    return html;
  }

  function setupScreen() {
    const p = PLATFORMS[state.platform];
    const v = vm();
    let html = header();
    html += '<section class="setup-hero"><h1 class="h-display">Настройка на ' + esc(p.label === 'ТВ' ? 'телевизоре' : p.label) + '</h1>' +
      '<p class="lead">Три шага, пара минут. Мы подскажем, куда нажимать.</p></section>';
    html += '<div class="steps-mini">' +
      '<div class="s"><span class="n">1</span><div><b>Установить Happ</b><span>бесплатное приложение для VPN</span></div></div>' +
      '<div class="s"><span class="n">2</span><div><b>Добавить подписку</b><span>одной кнопкой, без ручного ввода</span></div></div>' +
      '<div class="s"><span class="n">3</span><div><b>Подключиться</b><span>нажать большую кнопку в Happ</span></div></div>' +
      '</div>';
    if (v.s.status === 'none') {
      html += '<div class="hint warn">' + ic('info') + '<span>Сначала нужна подписка: <b>оформите её в боте</b>, потом вернитесь сюда.</span></div>';
    }
    html += '<button class="btn primary" data-act="setup-here">' + ic(p.icon) + '<span>Начать настройку на этом устройстве</span></button>';
    html += '<button class="btn ghost" data-act="devices" data-remote="1">' + ic('qr') + '<span>Установить на другом устройстве</span></button>';
    html += '<div style="text-align:center"><button class="linkish" data-act="devices" data-remote="0">Это не ' + esc(p.label) + '? Выбрать устройство</button></div>';
    return html;
  }

  function profileScreen() {
    const d = state.data || {};
    const u = d.user || {};
    const v = vm(), s = v.s;
    const name = [u.first_name, u.last_name].filter(Boolean).join(' ') || (u.username ? '@' + u.username : 'Пользователь');
    const initials = name.replace('@', '').split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase();
    let html = header();
    html += '<div class="card"><div class="who"><div class="avatar">' + (u.photo_url ? '<img src="' + esc(u.photo_url) + '" alt="">' : esc(initials)) + '</div>' +
      '<div class="txt"><b>' + esc(name) + '</b>' + (u.username ? '<span class="muted">@' + esc(u.username) + '</span><br>' : '') +
      '<button class="idchip" data-act="copy" data-text="' + esc(u.id) + '" data-msg="ID скопирован">ID ' + esc(u.id) + ' ' + ic('copy', 'sm') + '</button></div></div></div>';
    html += devicesBlock();

    if (s.sub_url) {
      html += '<h2 class="h-section">Ваша подписка</h2><div class="card">' +
        '<p class="field-label">Ссылка для приложения</p>' + linkBox(s.sub_url) +
        (s.mirror_url ? '<p class="field-label">Резервная ссылка, если основная не открывается</p>' + linkBox(s.mirror_url) : '') +
        '<p class="muted" style="margin:0;font-size:13px">Никому не передавайте эти ссылки: по ним подключаются к вашей подписке.</p></div>';
    }

    html += referralBlock();

    html += themeBlock();

    html += '<h2 class="h-section">Аккаунт</h2><div class="list">' +
      (v.newFlow
        ? '<button class="row" data-act="plans">' + rowInner('card', 'Купить подписку', v.tariff && v.tariff.code !== 'trial' ? 'Сейчас: ' + tariffName(v.tariff) + ', ' + devWord(v.tariff.devices) : 'Тарифы, устройства, оплата по СБП') + '</button>'
        : rowLink(v.links.buy, 'card', 'Продлить подписку', 'Оплата картой или звёздами в боте')) +
      (v.links.channel ? rowLink(v.links.channel, 'megaphone', 'Канал GateX', 'Новости и статус серверов') : '') +
      '<button class="row" data-act="welcome">' + rowInner('book', 'Пройти обучение заново', 'Пошаговая настройка с начала') + '</button>' +
      '</div>';
    return html;
  }

  function referralBlock() {
    const r = state.ref;
    if (!r) return '';
    const days = r.bonus_days || 7;
    const share = 'https://t.me/share/url?url=' + encodeURIComponent(r.link) + '&text=' + encodeURIComponent('Пользуюсь GateX VPN, подключайся по моей ссылке');
    return '<h2 class="h-section">Пригласите друга</h2><div class="card accent">' +
      '<div class="ref-head"><span class="brand-mark">' + ic('gift') + '</span><span><b>+' + esc(days) + ' ' + plural(days, ['день', 'дня', 'дней']) + ' вам и другу</b>' +
      '<span>Друг приходит в бот по вашей ссылке, и когда он включает пробный период, вы оба получаете по ' + esc(days) + ' ' + plural(days, ['дню', 'дня', 'дней']) + ' подписки.</span></span></div>' +
      linkBox(r.link) +
      '<div class="btn-row"><button class="btn ghost small" data-act="copy" data-text="' + esc(r.link) + '" data-msg="Ссылка скопирована">' + ic('copy', 'sm') + '<span>Копировать</span></button>' +
      '<a class="btn primary small" href="' + esc(share) + '" data-link>' + ic('send', 'sm') + '<span>Поделиться</span></a></div>' +
      (r.count !== null && r.count !== undefined ? '<p class="muted" style="margin:0;font-size:13px">Приглашено друзей: <b style="color:var(--text)">' + esc(r.count) + '</b></p>' : '') +
      '</div>';
  }

  function helpScreen() {
    const v = vm();
    const limit = v.s.device_limit;
    let html = header();
    html += '<div class="card accent"><span class="brand-mark" style="width:44px;height:44px;border-radius:14px">' + ic('chat') + '</span>' +
      '<h1 class="h-display" style="font-size:22px">Нужна помощь?</h1>' +
      '<p class="lead">Ответы на частые вопросы ниже. Если не нашли свой, напишите нам, отвечаем живыми людьми.</p>' +
      '<a class="btn primary small" href="' + esc(v.links.support) + '" data-link>' + ic('send', 'sm') + '<span>Написать в поддержку</span></a></div>';

    const faq = [
      ['Не подключается. Что сделать?',
        '<p>1. Проверьте на главной, что подписка активна.</p><p>2. В Happ <b>обновите подписку</b>: потяните список серверов вниз или нажмите значок обновления.</p><p>3. Выберите <b>другой сервер</b> и подключитесь снова.</p><p>4. Не помогло? Напишите в поддержку, приложите скриншот Happ.</p>'],
      ['Интернет работает только для «разрешённых» сайтов',
        '<p>Так выглядят <b>белые списки</b>: ВК, Госуслуги и Яндекс открываются, остальное нет. Чаще всего это мобильный интернет.</p>' +
        (noBypass()
          ? '<p>В вашем тарифе нет обхода белых списков. Его можно включить: «Купить подписку», переключатель <b>«Обход белых списков»</b>.</p>'
          : '<p>Выберите в Happ сервер <span class="chip-server">🇵🇱 Обход БС</span> или <span class="chip-server">LTE ОСНОВНАЯ</span>. Они работают через российский адрес, который оператор пропускает.</p><p>Если подписка не добавляется в Happ, используйте <b>резервную ссылку</b> из профиля.</p>')],
      ['Сколько устройств можно подключить?',
        limit ? '<p>До <b>' + esc(limit) + ' ' + plural(limit, ['устройства', 'устройств', 'устройств']) + '</b> на одну подписку. Подключить ещё одно: вкладка «Настройка», кнопка «Установить на другом устройстве».</p>'
          : '<p>Подключить ещё одно устройство можно во вкладке «Настройка», кнопка «Установить на другом устройстве». Лимит устройств зависит от тарифа.</p>'],
      ['Работают ли банки и российские сайты?',
        '<p>Да. Российские сайты идут напрямую, мимо VPN, поэтому банки, Госуслуги и маркетплейсы открываются как обычно.</p>'],
      ['Медленно или постоянно отваливается',
        '<p>Попробуйте сервер в другой стране: обычно быстрее всего Нидерланды и Франция. Если связь рвётся в метро или при смене Wi-Fi на мобильный, включите в Happ автоподключение.</p>'],
      ['Как продлить подписку?',
        v.newFlow
          ? '<p>Нажмите «Купить подписку» на главной, выберите тариф, число устройств и срок. Оплата по СБП или криптовалютой. Ссылку в Happ менять не нужно, она та же.</p>'
          : '<p>Нажмите «Продлить подписку» на главной. Оплата в боте картой российского банка или звёздами Telegram. Ссылку в Happ менять не нужно, она та же.</p>']
    ];
    html += '<h2 class="h-section">Частые вопросы</h2><div class="faq">' +
      faq.map((f) => '<details><summary>' + esc(f[0]) + '<span class="chev">' + ic('chevR', 'sm') + '</span></summary><div class="a">' + f[1] + '</div></details>').join('') +
      '</div>';
    html += '<div class="list">' +
      '<button class="row" data-act="devices" data-remote="1">' + rowInner('qr', 'Установка на другом устройстве', 'Инструкция и QR-код') + '</button>' +
      '<button class="row" data-act="welcome">' + rowInner('book', 'Обучение с начала', 'Ещё раз пройти все шаги') + '</button>' +
      '</div>';
    return html;
  }

  function linkBox(url) {
    return '<div class="linkbox"><code>' + esc(url) + '</code><button class="iconbtn" aria-label="Скопировать ссылку" data-act="copy" data-text="' + esc(url) + '" data-msg="Ссылка скопирована">' + ic('copy', 'sm') + '</button></div>';
  }
  function rowInner(icon, title, sub) {
    return '<span class="ico">' + ic(icon) + '</span><span class="txt"><b>' + esc(title) + '</b><span>' + esc(sub) + '</span></span><span class="chev">' + ic('chevR', 'sm') + '</span>';
  }
  function rowLink(url, icon, title, sub) {
    return '<a class="row" href="' + esc(url) + '" data-link>' + rowInner(icon, title, sub) + '</a>';
  }

  function navBar() {
    const tabs = [['home', 'home', 'Главная'], ['setup', 'plug', 'Настройка'], ['profile', 'user', 'Профиль'], ['help', 'help', 'Помощь']];
    return '<nav class="nav" aria-label="Разделы"><div class="nav-inner">' + tabs.map((t) =>
      '<button class="tab" data-act="tab" data-tab="' + t[0] + '"' + (state.tab === t[0] ? ' aria-current="page"' : '') + '>' + ic(t[1]) + '<span>' + t[2] + '</span></button>').join('') +
      '</div></nav>';
  }

  // ------------------------------------------------------------ sheets
  function welcomeSheet() {
    const p = PLATFORMS[state.platform];
    const name = state.data && state.data.user && state.data.user.first_name;
    return '<div class="sheet-top"><span style="width:40px"></span><span class="title"></span><button class="iconbtn" aria-label="Закрыть" data-act="welcome-skip">' + ic('close', 'sm') + '</button></div>' +
      '<div class="step-body">' +
      '<div class="welcome-art"><div class="gate" data-tone="ok"><i class="ring r1"></i><i class="ring r2"></i><i class="ring r3"></i><div class="core">' + gx() + '</div></div></div>' +
      '<h1 class="h-display" style="text-align:center">' + (name ? esc(name) + ', добро пожаловать в GateX' : 'Добро пожаловать в GateX') + '</h1>' +
      '<p class="lead" style="text-align:center">Подключим VPN на ' + esc(p.label === 'ТВ' ? 'телевизоре' : p.label) + ' за три шага. По пути объясним каждую кнопку.</p>' +
      '<div class="steps-mini">' +
      '<div class="s"><span class="n">1</span><div><b>Ставим Happ</b><span>приложение, через которое работает VPN</span></div></div>' +
      '<div class="s"><span class="n">2</span><div><b>Добавляем подписку</b><span>одна кнопка, всё подставится само</span></div></div>' +
      '<div class="s"><span class="n">3</span><div><b>Включаем</b><span>и проверяем, что всё открывается</span></div></div>' +
      '</div></div>' +
      '<div class="sheet-foot"><button class="btn primary" data-act="setup-here">Начать настройку</button>' +
      '<button class="btn ghost small" data-act="welcome-skip">У меня уже всё работает</button></div>';
  }

  function devicesSheet() {
    const sh = state.sheet;
    return '<div class="sheet-top"><button class="iconbtn" aria-label="Назад" data-act="back">' + ic('chevL', 'sm') + '</button><span class="title">' + (sh.remote ? 'Другое устройство' : 'Выбор устройства') + '</span><span style="width:40px"></span></div>' +
      '<div class="step-body"><h1 class="h-display">' + (sh.remote ? 'Куда подключаем?' : 'Какое у вас устройство?') + '</h1>' +
      '<p class="lead">' + (sh.remote ? 'Выберите устройство. Покажем, что установить, и дадим QR-код, чтобы не набирать ссылку вручную.' : 'Мы определили устройство автоматически, но могли ошибиться. Выберите своё.') + '</p>' +
      '<div class="devices">' + PLATFORM_ORDER.map((k) => {
        const p = PLATFORMS[k];
        return '<button class="device' + (!sh.remote && k === state.platform ? ' current' : '') + '" data-act="pick-device" data-platform="' + k + '"><span class="ico">' + ic(p.icon) + '</span><b>' + esc(p.name) + '</b><span>' + esc(p.sub) + '</span></button>';
      }).join('') + '</div></div>';
  }

  // ------------------------------------------------------------ tariffs
  function catalog() { return (state.data && state.data.plans) || DEMO_PLANS; }
  function planOf(code) { return catalog().plans.find((p) => p.code === code) || catalog().plans[0]; }
  function planPrice(p, bypass, devices, months) {
    return p.prices[bypass ? 'bypass' : 'plain'][months] * (devices / p.base_devices);
  }
  function minPrice() { return Math.min.apply(null, catalog().plans.map((p) => planPrice(p, false, p.base_devices, 1))); }
  function devWord(n) { return n + ' ' + plural(n, ['устройство', 'устройства', 'устройств']); }
  function monthWord(n) { return n + ' ' + plural(n, ['месяц', 'месяца', 'месяцев']); }
  function tariffName(t) { return t.title + (t.code !== 'trial' && t.bypass ? ' + обход БС' : ''); }
  function noBypass() { const t = vm().tariff; return !!(t && !t.bypass); }

  function openPlans() {
    const t = vm().tariff;
    const cur = t && t.code !== 'trial' ? planOf(t.code) : null;
    const p = cur || planOf('family');
    state.sheet = {
      kind: 'plans', stage: 'pick',
      plan: p.code,
      bypass: t ? !!t.bypass : true,
      devices: cur && p.device_steps.indexOf(t.devices) >= 0 ? t.devices : p.base_devices,
      months: 1, method: 'sbp', busy: false
    };
    renderSheet();
  }

  function plansSheet() {
    const sh = state.sheet;
    if (sh.stage === 'pay') return payStage(sh);
    if (sh.stage === 'done') return paidStage(sh);
    const p = planOf(sh.plan);
    const total = planPrice(p, sh.bypass, sh.devices, sh.months);
    const full = planPrice(p, sh.bypass, sh.devices, 1) * sh.months;
    const bypassExtra = planPrice(p, true, sh.devices, 1) - planPrice(p, false, sh.devices, 1);
    const t = vm().tariff, s = vm().s;

    let html = '<div class="sheet-top"><button class="iconbtn" aria-label="Закрыть" data-act="close">' + ic('chevL', 'sm') + '</button><span class="title">Покупка подписки</span><span style="width:40px"></span></div>' +
      '<div class="step-body">' +
      '<h1 class="h-display">Выберите тариф</h1>' +
      '<p class="lead">Цена за весь срок, без автосписаний. Ссылка в Happ останется той же.</p>';

    html += '<div class="plans" role="radiogroup" aria-label="Тариф">' + catalog().plans.map((pl) => {
      const on = pl.code === sh.plan;
      const blurb = pl.code === 'family' ? 'Для всей семьи: телефоны, ноутбуки, ТВ' : 'Телефон и компьютер';
      return '<button class="plan" role="radio" aria-checked="' + on + '" data-act="plan-pick" data-plan="' + esc(pl.code) + '">' +
        '<span class="ico">' + ic(pl.code === 'family' ? 'home' : 'phone') + '</span>' +
        '<b>' + esc(pl.title) + '</b><span>' + esc(blurb) + '</span>' +
        '<span class="plan-meta">' + devWord(pl.base_devices) + '</span>' +
        '<span class="plan-price">' + money(planPrice(pl, sh.bypass, pl.base_devices, 1)) + '<small>/мес</small></span>' +
        '<i class="radio" aria-hidden="true"></i></button>';
    }).join('') + '</div>';

    html += '<button class="switch-row" role="switch" aria-checked="' + sh.bypass + '" data-act="plan-bypass">' +
      '<span class="ico">' + ic('signal') + '</span>' +
      '<span class="txt"><b>Обход белых списков</b><span>Нужен, если мобильный интернет пускает только на «разрешённые» сайты. Добавляет серверы LTE ОСНОВНАЯ.</span></span>' +
      '<span class="side"><span class="extra">+' + money(bypassExtra) + '/мес</span><i class="knob" aria-hidden="true"></i></span></button>';

    html += '<h2 class="h-section">Сколько устройств</h2><div class="chips dev-chips" role="radiogroup" aria-label="Устройства">' + p.device_steps.map((n) =>
      '<button class="chip" role="radio" aria-checked="' + (n === sh.devices) + '" data-act="plan-devices" data-n="' + n + '">' +
      '<span class="dev-ico">' + ic(n > p.base_devices * 2 ? 'tv' : n > p.base_devices ? 'laptop' : 'phone', 'sm') + '</span>' +
      '<b>' + n + '</b><span>' + plural(n, ['устройство', 'устройства', 'устройств']) + '</span>' +
      '<em>' + money(planPrice(p, sh.bypass, n, 1)) + '/мес</em></button>').join('') + '</div>';

    html += '<h2 class="h-section">Срок</h2><div class="chips" role="radiogroup" aria-label="Срок">' + catalog().months.map((m) => {
      const price = planPrice(p, sh.bypass, sh.devices, m.months);
      return '<button class="chip" role="radio" aria-checked="' + (m.months === sh.months) + '" data-act="plan-months" data-n="' + m.months + '">' +
        (m.discount ? '<span class="save">−' + m.discount + '%</span>' : '') +
        '<b>' + m.months + '</b><span>' + plural(m.months, ['месяц', 'месяца', 'месяцев']) + '</span>' +
        '<em>' + (m.months > 1 ? '≈' + money(price / m.months) + '/мес' : money(price)) + '</em></button>';
    }).join('') + '</div>';

    let note = '';
    if (!t && vm().active && s.expire_at) {
      note = 'Сейчас у вас прежний тариф, он работает без изменений до ' + fmtDate(s.expire_at) + '. Новый тариф включится после этой даты, оплаченные дни добавятся к ней.';
    } else if (t && t.code === sh.plan && !!t.bypass === sh.bypass && s.expire_at && vm().active) {
      note = 'Дни добавятся к текущей подписке, она действует до ' + fmtDate(s.expire_at) + '.';
    } else if (t && t.code !== 'trial' && vm().active) {
      note = 'Это смена тарифа: новый срок начнётся с оплаты, а оставшиеся дни текущего тарифа пересчитаем по стоимости и добавим.';
    }

    html += '<div class="summary">' +
      '<div class="sum-line"><span>' + esc(p.title) + (sh.bypass ? ' + обход БС' : '') + ' · ' + devWord(sh.devices) + ' · ' + monthWord(sh.months) + '</span></div>' +
      '<div class="sum-total"><span>Итого</span><b>' + money(total) + '</b></div>' +
      (full > total ? '<div class="sum-save">Экономия ' + money(full - total) + ' по сравнению с помесячной оплатой</div>' : '') +
      '</div>' +
      (note ? '<div class="hint">' + ic('info') + '<span>' + esc(note) + '</span></div>' : '');

    html += '<h2 class="h-section">Способ оплаты</h2><div class="seg" role="radiogroup" aria-label="Способ оплаты">' +
      [['sbp', 'СБП', 'в приложении банка'], ['crypto', 'Криптовалюта', 'USDT и другие']].map((m) =>
        '<button role="radio" aria-checked="' + (sh.method === m[0]) + '" data-act="plan-method" data-m="' + m[0] + '"><b>' + m[1] + '</b><span>' + m[2] + '</span></button>').join('') +
      '</div></div>';

    html += '<div class="sheet-foot"><button class="btn white" data-act="plan-pay"' + (sh.busy ? ' disabled' : '') + '>' +
      (sh.busy ? ic('refresh') + '<span>Создаём счёт…</span>' : ic('card') + '<span>Оплатить ' + money(total) + '</span>') + '</button></div>';
    return html;
  }

  function payStage(sh) {
    const pay = state.demo
      ? '<button class="btn white" data-act="plan-demo-paid">' + ic('card') + '<span>Перейти к оплате</span></button>'
      : '<a class="btn white" href="' + esc(sh.payUrl) + '" data-link data-paylink>' + ic('card') + '<span>Перейти к оплате</span></a>';
    return '<div class="sheet-top"><button class="iconbtn" aria-label="Назад" data-act="back">' + ic('chevL', 'sm') + '</button><span class="title">Оплата</span><span style="width:40px"></span></div>' +
      '<div class="step-body enter"><div class="step-art">' + ic('card') + '</div>' +
      '<h1 class="h-display">Счёт на ' + money(sh.amount) + ' готов</h1>' +
      '<p class="lead">Нажмите кнопку, откроется страница оплаты' + (sh.method === 'sbp' ? ' по СБП' : '') + '. После оплаты вернитесь сюда: подписка обновится сама.</p>' +
      '<ol class="orderlist"><li><span>Нажмите <b>«Перейти к оплате»</b>.</span></li><li><span>' + (sh.method === 'sbp' ? 'Выберите свой банк или отсканируйте QR-код и подтвердите платёж.' : 'Выберите монету и переведите сумму по реквизитам на странице.') + '</span></li><li><span>Вернитесь в кабинет и нажмите <b>«Я оплатил»</b>, если подписка не обновилась сама.</span></li></ol>' +
      '</div><div class="sheet-foot">' + pay +
      '<button class="btn ghost small" data-act="plan-check"' + (sh.busy ? ' disabled' : '') + '>' + (sh.busy ? 'Проверяем…' : 'Я оплатил, проверить') + '</button>' +
      '<button class="linkish" data-act="back">Изменить тариф</button></div>';
  }

  function paidStage(sh) {
    const v = vm();
    const p = planOf(sh.plan);
    // old-tariff users keep their tariff until it runs out; the new one starts then
    const later = !v.tariff && sh.switchAt && new Date(sh.switchAt).getTime() > Date.now();
    const what = later
      ? 'Тариф «' + p.title + (sh.bypass ? ' + обход БС' : '') + '», ' + devWord(sh.devices) + ', включится ' + fmtDate(sh.switchAt) + '. До этого всё работает как сейчас. '
      : (v.tariff ? tariffName(v.tariff) + ', ' + devWord(v.tariff.devices) + '. ' : '');
    return '<div class="sheet-top"><span style="width:40px"></span><span class="title"></span><button class="iconbtn" aria-label="Закрыть" data-act="close">' + ic('close', 'sm') + '</button></div>' +
      '<div class="step-body enter"><div class="welcome-art"><div class="gate" data-tone="ok"><i class="ring r1"></i><i class="ring r2"></i><i class="ring r3"></i><div class="core">' + ic('check') + '</div></div></div>' +
      '<h1 class="h-display" style="text-align:center">Оплата прошла</h1>' +
      '<p class="lead" style="text-align:center">' + esc(what) + (v.s.expire_at ? 'Подписка действует до ' + esc(fmtDate(v.s.expire_at)) + '.' : '') + '</p>' +
      '<div class="hint">' + ic('refresh') + '<span>Если Happ уже настроен, <b>обновите подписку</b> в нём, чтобы подтянулись серверы тарифа.</span></div>' +
      '</div><div class="sheet-foot"><button class="btn primary" data-act="close">Готово</button>' +
      (v.s.first_connected_at ? '' : '<button class="btn ghost small" data-act="setup-here">Настроить подключение</button>') + '</div>';
  }

  function subSnapshot() {
    const d = state.data || {};
    const s = d.subscription || {};
    return [s.status, s.expire_at, d.tariff && d.tariff.code, d.tariff && d.tariff.bypass, s.device_limit].join('|');
  }

  async function createPayment() {
    const sh = state.sheet;
    if (!sh || sh.busy) return;
    haptic('medium');
    if (state.demo) {
      sh.stage = 'pay'; sh.amount = planPrice(planOf(sh.plan), sh.bypass, sh.devices, sh.months);
      sh.switchAt = vm().active ? vm().s.expire_at : null;
      renderSheet(); return;
    }
    sh.busy = true; renderSheet();
    try {
      const res = await fetch(new URL('api/pay', location.href), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ initData: state.tg.initData, plan: sh.plan, bypass: sh.bypass, devices: sh.devices, months: sh.months, method: sh.method })
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok || !body.pay_url) throw new Error(body.error || String(res.status));
      sh.before = subSnapshot();
      sh.switchAt = vm().active ? vm().s.expire_at : null;
      sh.payUrl = body.pay_url; sh.amount = body.amount; sh.stage = 'pay';
      haptic('ok');
    } catch (e) {
      toast(e.message === 'unauthorized' ? 'Сессия устарела. Откройте кабинет из бота заново'
          : 'Не получилось создать счёт. Попробуйте ещё раз или напишите в поддержку');
    }
    sh.busy = false;
    if (state.sheet === sh) renderSheet();
  }

  async function checkPayment(quiet) {
    const sh = state.sheet;
    if (!sh || sh.kind !== 'plans' || sh.stage !== 'pay' || sh.busy) return;
    if (state.demo) return;
    sh.busy = true; if (!quiet) renderSheet();
    try {
      state.data = await fetchMe(true);
      if (subSnapshot() !== sh.before) { sh.stage = 'done'; haptic('ok'); render(); }
      else if (!quiet) toast('Оплата ещё не дошла. Подождите минуту и проверьте снова');
    } catch (e) {
      if (!quiet) toast('Не получилось проверить. Попробуйте ещё раз');
    }
    sh.busy = false;
    if (state.sheet === sh) renderSheet();
  }

  function wizardSheet() {
    const w = state.sheet;
    const p = PLATFORMS[w.platform];
    const s = vm().s;
    const title = 'Настройка · ' + p.label;
    let top = '<div class="sheet-top"><button class="iconbtn" aria-label="Назад" data-act="back">' + ic('chevL', 'sm') + '</button><span class="title">' + esc(title) + '</span><button class="iconbtn" aria-label="Закрыть" data-act="close">' + ic('close', 'sm') + '</button></div>';
    if (w.step < 3) top += '<div class="progress" aria-label="Шаг ' + (w.step + 1) + ' из 3">' + [0, 1, 2].map((i) => '<i class="' + (i <= w.step ? 'on' : '') + '"></i>').join('') + '</div>';

    let body = '', foot = '';
    if (w.step === 0) {
      body = '<span class="step-kicker">Шаг 1 из 3</span><h1 class="h-display">Установите Happ</h1>' +
        '<p class="lead">' + esc(p.install) + '</p>' +
        '<div class="store-list">' + p.stores.map((st) =>
          '<a class="btn ' + (st.main ? 'invert' : 'ghost') + ' split" href="' + esc(st.url) + '" data-link>' + ic('download') + '<span><span style="display:block">' + esc(st.title) + '</span><span class="note">' + esc(st.note) + '</span></span><span class="spacer"></span>' + ic('chevR', 'sm') + '</a>').join('') + '</div>' +
        (w.remote ? '<div class="hint">' + ic('info') + '<span>Ссылки откроются здесь. На ' + esc(p.label === 'ТВ' ? 'телевизоре' : 'другом устройстве') + ' найдите <b>Happ</b> в магазине приложений по названию.</span></div>'
          : '<div class="hint">' + ic('info') + '<span>Happ уже установлен? Просто нажмите <b>«Дальше»</b>.</span></div>');
      foot = '<button class="btn primary" data-act="next">Happ установлен, дальше</button>';
    } else if (w.step === 1) {
      if (s.status === 'none' || !s.sub_url) {
        body = '<span class="step-kicker">Шаг 2 из 3</span><h1 class="h-display">Нужна подписка</h1><p class="lead">Чтобы добавить VPN в Happ, сначала оформите подписку' + (vm().newFlow ? '' : ' или пробный период в боте') + '. Потом вернитесь сюда, мы продолжим с этого шага.</p>';
        foot = vm().newFlow
          ? '<button class="btn white" data-act="plans">' + ic('card') + '<span>Выбрать тариф</span></button>'
          : '<a class="btn primary" href="' + esc(vm().links.buy) + '" data-link>' + ic('gift') + '<span>Оформить в боте</span></a>';
      } else if (!w.remote) {
        body = '<span class="step-kicker">Шаг 2 из 3</span><h1 class="h-display">Добавьте подписку</h1>' +
          '<p class="lead">Нажмите кнопку: откроется Happ, и все серверы GateX появятся в нём сами.</p>' +
          '<div class="step-art">' + ic('link') + '</div>' +
          '<button class="btn primary" data-act="happ">' + ic('plug') + '<span>Добавить в Happ</span></button>' +
          '<details class="hint" style="display:block"><summary>' + ic('copy', 'sm') + '<span>Не открылось? Добавим вручную</span><span class="chev">' + ic('chevR', 'sm') + '</span></summary>' +
          '<ol class="orderlist" style="margin-top:12px"><li><span>Скопируйте ссылку ниже.</span></li><li><span>Откройте Happ и нажмите <b>«+»</b> вверху справа.</span></li><li><span>Выберите <b>вставку из буфера обмена</b>.</span></li></ol>' +
          '<div style="margin-top:12px">' + linkBox(s.sub_url) + '</div>' +
          (s.mirror_url ? '<p style="margin:12px 0 6px">Ссылка не добавляется или серверы не загружаются? Возьмите резервную:</p>' + linkBox(s.mirror_url) : '') +
          '</details>';
        foot = '<button class="btn ghost" data-act="next">Подписка добавлена, дальше</button>';
      } else {
        body = '<span class="step-kicker">Шаг 2 из 3</span><h1 class="h-display">Добавьте подписку</h1>' +
          '<p class="lead">' + (w.platform === 'tv' ? 'В Happ на телевизоре выберите добавление подписки по QR-коду или ссылке.' : 'Откройте Happ на том устройстве, нажмите <b>«+»</b> и отсканируйте этот код.') + '</p>' +
          '<div class="qr" role="img" aria-label="QR-код ссылки на подписку">' + qrSvg(s.sub_url) + '</div>' +
          linkBox(s.sub_url) +
          '<div class="btn-row"><button class="btn ghost small" data-act="copy" data-text="' + esc(s.sub_url) + '" data-msg="Ссылка скопирована">' + ic('copy', 'sm') + '<span>Копировать</span></button>' +
          '<a class="btn ghost small" href="' + esc('https://t.me/share/url?url=' + encodeURIComponent(s.sub_url) + '&text=' + encodeURIComponent('Ссылка на подписку GateX')) + '" data-link>' + ic('send', 'sm') + '<span>Себе в Telegram</span></a></div>' +
          '<div class="hint">' + ic('info') + '<span>Камеры нет? Отправьте ссылку себе в Telegram, откройте её на том устройстве и вставьте в Happ через <b>«+»</b>.</span></div>';
        foot = '<button class="btn primary" data-act="next">Подписка добавлена, дальше</button>';
      }
    } else if (w.step === 2) {
      body = '<span class="step-kicker">Шаг 3 из 3</span><h1 class="h-display">Включите VPN</h1>' +
        '<div class="step-art">' + ic('power') + '</div>' +
        '<ol class="orderlist"><li><span>Откройте <b>Happ</b>.</span></li><li><span>Нажмите <b>большую кнопку</b> в центре экрана. Сервер выбирается автоматически.</span></li><li><span>' + esc(p.allow) + '</span></li></ol>' +
        (noBypass()
          ? '<div class="hint">' + ic('signal') + '<span>Мобильный интернет пускает только на «разрешённые» сайты? Это белые списки. Обход можно добавить к тарифу: «Купить подписку», переключатель «Обход белых списков».</span></div>'
          : '<div class="hint warn">' + ic('signal') + '<span>Мобильный интернет пускает только на «разрешённые» сайты? Выберите в списке серверов <span class="chip-server">🇵🇱 Обход БС</span>.</span></div>');
      foot = '<button class="btn primary" data-act="next">Подключилось</button><button class="btn ghost small" data-act="tab-help">Не получается</button>';
    } else {
      body = '<div class="welcome-art"><div class="gate" data-tone="ok"><i class="ring r1"></i><i class="ring r2"></i><i class="ring r3"></i><div class="core">' + ic('check') + '</div></div></div>' +
        '<h1 class="h-display" style="text-align:center">Готово, вы под защитой</h1>' +
        '<p class="lead" style="text-align:center">Откройте любой сайт или приложение, чтобы проверить. Дальше Happ можно просто держать включённым.</p>' +
        '<div class="hint">' + ic('qr') + '<span>Хотите подключить ещё ноутбук или телевизор? Вкладка <b>«Настройка»</b>, кнопка <b>«Установить на другом устройстве»</b>.</span></div>';
      foot = '<button class="btn primary" data-act="finish">В личный кабинет</button>';
    }
    return top + '<div class="step-body enter">' + body + '</div><div class="sheet-foot">' + foot + '</div>';
  }

  function qrSvg(text) {
    if (typeof window.qrcode !== 'function') return '';
    const q = window.qrcode(0, 'M');
    q.addData(text); q.make();
    const n = q.getModuleCount();
    let d = '';
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (q.isDark(r, c)) d += 'M' + c + ' ' + r + 'h1v1h-1z';
    return '<svg viewBox="0 0 ' + n + ' ' + n + '" shape-rendering="crispEdges"><path style="fill:var(--qr-ink)" d="' + d + '"/></svg>';
  }

  // ------------------------------------------------------------ render
  function render() {
    const el = root();
    if (state.error) { el.innerHTML = errorScreen(); hideSplash(); return; }
    if (!state.data) { el.innerHTML = loadingScreen(); return; }
    hideSplash();
    const screens = { home: homeScreen, setup: setupScreen, profile: profileScreen, help: helpScreen };
    el.innerHTML = '<main class="app tab-' + state.tab + '">' + screens[state.tab]() + '</main>' + navBar() + demoBar();
    renderSheet();
  }
  let lastSheetKey = '';
  function renderSheet() {
    let sheet = $('#sheet');
    const sh = state.sheet;
    document.body.classList.toggle('has-sheet', !!sh);
    if (!sh) { if (sheet) sheet.remove(); lastSheetKey = ''; syncBackButton(); return; }
    if (!sheet) {
      sheet = document.createElement('div');
      sheet.id = 'sheet'; sheet.className = 'sheet enter';
      sheet.setAttribute('role', 'dialog'); sheet.setAttribute('aria-modal', 'true');
      document.body.appendChild(sheet);
    }
    const key = sh.kind + (sh.step || 0) + (sh.platform || '') + (sh.stage || '');
    const html = sh.kind === 'welcome' ? welcomeSheet() : sh.kind === 'devices' ? devicesSheet() : sh.kind === 'plans' ? plansSheet() : wizardSheet();
    sheet.innerHTML = '<div class="sheet-inner">' + html + '</div>';
    if (key !== lastSheetKey) sheet.scrollTop = 0;
    lastSheetKey = key;
    syncBackButton();
  }
  function loadingScreen() {
    return '<main class="app">' + header() + '<div class="center-screen"><div class="gate" data-tone="ok"><i class="ring r1"></i><i class="ring r2"></i><div class="core">' + gx('spin') + '</div></div><p class="muted">Загружаем кабинет…</p></div></main>';
  }
  function errorScreen() {
    const e = state.error;
    if (e === 'outside') {
      return '<main class="app">' + header() + '<div class="center-screen"><div class="gate" data-tone="off"><i class="ring r1"></i><i class="ring r2"></i><div class="core">' + gx() + '</div></div>' +
        '<h1 class="hero-title">Откройте кабинет в Telegram</h1><p class="lead">Личный кабинет работает внутри бота GateX: так мы узнаём, что это вы, без паролей.</p>' +
        '<a class="btn primary" href="https://t.me/gatexvpn_bot" style="max-width:320px">' + ic('send') + '<span>Открыть бота</span></a>' +
        '<button class="linkish" data-act="demo-start">Посмотреть, как выглядит кабинет</button></div></main>';
    }
    return '<main class="app">' + header() + '<div class="center-screen"><div class="gate" data-tone="warn"><i class="ring r1"></i><i class="ring r2"></i><div class="core">' + ic('refresh') + '</div></div>' +
      '<h1 class="hero-title">Не удалось загрузить данные</h1><p class="lead">' + (e === 'unauthorized' ? 'Сессия устарела. Закройте кабинет и откройте его снова из бота.' : 'Сервер не ответил. Проверьте интернет и попробуйте ещё раз.') + '</p>' +
      '<button class="btn primary" data-act="retry" style="max-width:320px">Повторить</button></div></main>';
  }
  function demoBar() {
    if (!state.demo) return '';
    return '<div class="demo-bar"><button data-act="demo-menu" aria-expanded="' + state.demoMenu + '">Демо-данные ▾</button>' +
      (state.demoMenu ? '<div class="demo-menu"><p>Пример, не настоящий пользователь</p>' + Object.keys(DEMO_SCENARIOS).map((k) =>
        '<button data-act="demo-set" data-key="' + k + '" aria-pressed="' + (state.demoKey === k) + '">' + esc(DEMO_SCENARIOS[k].label) + '</button>').join('') +
        '<button data-act="welcome">Показать обучение</button></div>' : '') + '</div>';
  }

  // ------------------------------------------------------------ actions
  function finishOnboarding() {
    store('gx_onboarded', '1');
    cloudSet('gx_onboarded', '1');
  }
  function openWizard(platform, remote) {
    state.sheet = { kind: 'wizard', platform, remote: !!remote, step: 0, prev: state.sheet };
    renderSheet();
  }
  function goBack() {
    const sh = state.sheet;
    if (!sh) return;
    if (sh.kind === 'wizard' && sh.step > 0 && sh.step < 3) { sh.step--; renderSheet(); return; }
    if (sh.kind === 'plans' && sh.stage === 'pay') { sh.stage = 'pick'; renderSheet(); return; }
    if (sh.kind === 'welcome') finishOnboarding();
    state.sheet = sh.prev || null;
    if (state.sheet && state.sheet.kind === 'wizard') state.sheet = null;
    renderSheet();
  }

  document.addEventListener('click', (ev) => {
    const a = ev.target.closest('a[data-link]');
    if (a && state.tg) { ev.preventDefault(); haptic(); openUrl(a.href); return; }
    const t = ev.target.closest('[data-act]');
    if (!t) return;
    const act = t.dataset.act;
    switch (act) {
      case 'tab':
        haptic('light');
        state.tab = t.dataset.tab; state.sheet = null;
        render(); window.scrollTo(0, 0); break;
      case 'tab-help':
        state.sheet = null; state.tab = 'help'; render(); window.scrollTo(0, 0); break;
      case 'setup-here':
        haptic('light');
        if (state.sheet && state.sheet.kind === 'welcome') finishOnboarding();
        state.sheet = null; openWizard(state.platform, false); break;
      case 'devices':
        haptic('light');
        state.sheet = { kind: 'devices', remote: t.dataset.remote === '1', prev: null }; renderSheet(); break;
      case 'pick-device': {
        const remote = state.sheet && state.sheet.remote;
        const devices = state.sheet;
        if (!remote) { state.platform = t.dataset.platform; store('gx_platform', state.platform); render(); }
        state.sheet = { kind: 'wizard', platform: t.dataset.platform, remote, step: 0, prev: devices };
        renderSheet(); break;
      }
      case 'next':
        haptic('light');
        state.sheet.step++; renderSheet();
        if (state.sheet.step === 3) haptic('ok');
        break;
      case 'back': goBack(); break;
      case 'close': state.sheet = null; renderSheet(); break;
      case 'finish':
        finishOnboarding(); state.sheet = null; state.tab = 'home'; render(); break;
      case 'welcome':
        state.demoMenu = false; state.sheet = { kind: 'welcome' }; render(); break;
      case 'welcome-skip':
        finishOnboarding(); state.sheet = null; renderSheet(); break;
      case 'happ':
        haptic('medium'); openInHapp(vm().s.sub_url); break;
      case 'copy':
        copy(t.dataset.text, t.dataset.msg); break;
      case 'my-devices':
        haptic('light');
        state.tab = 'profile'; state.confirmDevice = null; render();
        { const h = $('#my-devices'); if (h) window.scrollTo(0, h.getBoundingClientRect().top + window.scrollY - 56); }
        break;
      case 'device-ask':
        haptic('light'); state.confirmDevice = t.dataset.id; render(); break;
      case 'device-cancel':
        state.confirmDevice = null; render(); break;
      case 'device-delete':
        deleteDevice(t.dataset.id); break;
      case 'theme':
        setTheme(t.dataset.theme); break;
      case 'device-restore':
        restoreDevice(t.dataset.id); break;
      case 'plans':
        haptic('light'); openPlans(); break;
      case 'plan-pick': {
        const p = planOf(t.dataset.plan);
        if (state.sheet.plan !== p.code) { state.sheet.plan = p.code; state.sheet.devices = p.base_devices; }
        haptic('light'); renderSheet(); break;
      }
      case 'plan-bypass':
        state.sheet.bypass = !state.sheet.bypass; haptic('light'); renderSheet(); break;
      case 'plan-devices':
        state.sheet.devices = Number(t.dataset.n); haptic('light'); renderSheet(); break;
      case 'plan-months':
        state.sheet.months = Number(t.dataset.n); haptic('light'); renderSheet(); break;
      case 'plan-method':
        state.sheet.method = t.dataset.m; haptic('light'); renderSheet(); break;
      case 'plan-pay':
        createPayment(); break;
      case 'plan-check':
        checkPayment(false); break;
      case 'plan-demo-paid': {
        const sh = state.sheet, p = planOf(sh.plan), cur = state.data.subscription;
        const days = sh.months * 30 * DAY;
        if (!state.data.tariff && vm().active) {
          state.data.subscription = Object.assign({}, cur, { expire_at: new Date(new Date(cur.expire_at).getTime() + days).toISOString() });
        } else {
          state.data.tariff = { code: p.code, title: p.title, bypass: sh.bypass, devices: sh.devices };
          state.data.subscription = Object.assign({}, cur, { status: 'active', is_trial: false, device_limit: sh.devices,
            expire_at: new Date(Date.now() + days).toISOString() });
        }
        sh.stage = 'done'; haptic('ok'); render(); break;
      }
      case 'retry':
        state.error = null; state.data = null; render(); boot(); break;
      case 'demo-start':
        startDemo('fresh'); break;
      case 'demo-menu':
        state.demoMenu = !state.demoMenu; render(); break;
      case 'demo-set':
        state.demoMenu = false; startDemo(t.dataset.key); break;
    }
  });

  async function deleteDevice(id) {
    if (state.busy) return;
    state.busy = true; render();
    try {
      if (state.demo) {
        await new Promise((r) => setTimeout(r, 500));
        const gone = state.data.devices.find((d) => d.id === id);
        state.data.devices = state.data.devices.filter((d) => d.id !== id);
        if (gone) state.removed = [{ id: gone.id, platform: gone.platform, model: gone.model, app: gone.app, removed_at: new Date().toISOString() }].concat(state.removed || []);
      } else {
        const res = await fetch(new URL('api/devices/delete', location.href), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ initData: state.tg.initData, id })
        });
        if (!res.ok) throw new Error(String(res.status));
        state.data.devices = (await res.json()).devices;
        fetchRemoved();
      }
      haptic('ok'); toast('Устройство удалено. Обновите подписку в Happ на остальных устройствах');
    } catch (e) {
      toast('Не получилось удалить. Попробуйте ещё раз');
    }
    state.busy = false; state.confirmDevice = null; render();
  }

  async function restoreDevice(id) {
    if (state.busy) return;
    state.busy = 'restore:' + id; render();
    try {
      if (state.demo) {
        await new Promise((r) => setTimeout(r, 500));
        state.removed = state.removed.filter((d) => d.id !== id);
      } else {
        const res = await fetch(new URL('api/devices/restore', location.href), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ initData: state.tg.initData, id })
        });
        if (!res.ok) throw new Error(String(res.status));
        state.removed = (await res.json()).removed;
      }
      haptic('ok'); toast('Готово. Обновите подписку в Happ на этом устройстве');
    } catch (e) {
      toast('Не получилось вернуть. Попробуйте ещё раз');
    }
    state.busy = false; render();
  }

  async function fetchRemoved() {
    try {
      const res = await fetch(new URL('api/devices/removed', location.href), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ initData: state.tg.initData })
      });
      if (!res.ok) return;
      state.removed = (await res.json()).removed;
      if (state.tab === 'profile') render();
    } catch (e) { /* the section just stays hidden */ }
  }

  // ------------------------------------------------------------ boot
  function startDemo(key) {
    state.demo = true; state.demoKey = key; state.error = null;
    state.data = demoData(key);
    state.ref = { link: 'https://t.me/gatexvpn_bot?start=ref700123456', count: 2, bonus_days: 7 };
    state.tab = 'home';
    state.sheet = DEMO_SCENARIOS[key].onboard ? { kind: 'welcome' } : null;
    render();
  }

  async function fetchMe(fresh) {
    const res = await fetch(new URL('api/me', location.href), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ initData: state.tg.initData, fresh: !!fresh })
    });
    if (res.status === 401) throw new Error('unauthorized');
    if (!res.ok) throw new Error('server');
    return res.json();
  }

  async function fetchReferral() {
    try {
      const res = await fetch(new URL('api/referral', location.href), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ initData: state.tg.initData })
      });
      if (!res.ok) return;
      state.ref = await res.json();
      if (state.tab === 'profile') render();
    } catch (e) { /* the profile just shows no invite block */ }
  }

  async function boot() {
    if (!state.tg) {
      if (window.GATEX_PREVIEW) startDemo('fresh');
      else { state.error = 'outside'; render(); }
      return;
    }
    try {
      const [data, cloudFlag] = await Promise.all([fetchMe(), cloudGet('gx_onboarded')]);
      state.data = data;
      fetchReferral();
      fetchRemoved();
      const s = data.subscription || {};
      const onboarded = store('gx_onboarded') === '1' || cloudFlag === '1';
      if (!onboarded && (s.status === 'active' || s.status === 'none') && !s.first_connected_at) state.sheet = { kind: 'welcome' };
      render();
      // the bot's «Купить» button opens the cabinet with ?open=buy (or startapp=buy)
      const startParam = (state.tg.initDataUnsafe && state.tg.initDataUnsafe.start_param) || new URLSearchParams(location.search).get('open');
      if (startParam === 'buy' && vm().newFlow) openPlans();
    } catch (e) {
      state.error = e.message === 'unauthorized' ? 'unauthorized' : 'server';
      render();
    }
  }

  // Launch screen: rings open, G slides in, X turns into place; stays at
  // least SPLASH_MS so the animation plays even when data comes back fast.
  const SPLASH_MS = 1300;
  let splashAt = 0;
  function showSplash() {
    splashAt = Date.now();
    document.body.insertAdjacentHTML('beforeend', '<div class="splash" aria-hidden="true"><div class="splash-art">' +
      '<i class="ring r1"></i><i class="ring r2"></i><i class="ring r3"></i>' + gx() + '</div><div class="splash-word">Gate<b>X</b></div></div>');
  }
  function hideSplash() {
    const el = $('.splash');
    if (!el || el.classList.contains('out')) return;
    setTimeout(() => {
      el.classList.add('out');
      document.body.classList.add('entered');
      setTimeout(() => el.remove(), 450);
    }, Math.max(0, SPLASH_MS - (Date.now() - splashAt)));
  }

  async function init() {
    showSplash();
    state.tg = await loadTelegram();
    if (state.tg) {
      try { state.tg.ready(); state.tg.expand(); } catch (e) { /* ignore */ }
      // full screen on phones and desktop (Bot API 8.0); Telegram keeps its close/menu
      // buttons on top, the page pads around them via --tg-*-safe-area-inset-*
      try {
        const v = (x) => state.tg.isVersionAtLeast && state.tg.isVersionAtLeast(x);
        if (v('8.0') && !state.tg.isFullscreen) state.tg.requestFullscreen();
        if (v('7.7')) state.tg.disableVerticalSwipes();
      } catch (e) { /* old client */ }
      state.tg.onEvent && state.tg.onEvent('themeChanged', applyTheme);
      state.tg.BackButton && state.tg.BackButton.onClick(goBack);
      state.tg.onEvent && state.tg.onEvent('activated', () => checkPayment(true));
    }
    if (!themeChoice()) { const t = await cloudGet('gx_theme'); if (t) { state.theme = t; store('gx_theme', t); } }
    applyTheme();
    const saved = store('gx_platform');
    state.platform = PLATFORMS[saved] ? saved : detectPlatform();
    render();
    boot();
  }

  document.addEventListener('visibilitychange', () => { if (!document.hidden) checkPayment(true); });

  init();
})();
