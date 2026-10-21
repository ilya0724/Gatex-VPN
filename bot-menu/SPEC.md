# GateX bot: new menu with banners and «Задания»

Approved by Ilya on 2026-10-21 («очень красиво» on `menu-mockup.png`).
Bot: NL `/root/vpn_bot` (aiogram 3.30.0, Python 3.12), service `vpn_bot`. All texts live in `i18n.py`.

## 0. Backup first

- `/root/gatex-menu-backup-20261021/orig/`: every file you touch plus `.env`.
- After the change: `diff -u orig/X X > /root/gatex-menu-backup-20261021/diff-X.patch` for each file.
- Rollback must be one command (copy orig back, remove new files, `systemctl restart vpn_bot`).

## 1. Banners

Download to `/root/vpn_bot/media/banners/`:

```
for k in main connect sub tasks ref info support pay blocked; do
  curl -fsSL -o /root/vpn_bot/media/banners/$k.jpg \
    https://raw.githubusercontent.com/ilya0724/Gatex-VPN/claude/project-thread-pg7pa9/bot-menu/banners/$k.jpg
done
```

1280x480 JPEG, about 70 KB each. Cache the Telegram `file_id` after the first upload (in memory is fine, Mongo if the bot already has a settings collection) so the bot does not re-upload on every tap.

The existing `start_banner.jpg` hook in main.py should point to `media/banners/main.jpg`.

## 2. Main menu

Photo `main.jpg` with an HTML caption:

```
⚡ Привет, <b>{first_name}</b>

🔒 Активна до <b>{dd.mm.yyyy}</b> · {days_left} дн.
📱 Устройства <b>{used}/{limit}</b>
```

- No panel user: `🔒 Подписки пока нет — пробный период после подписки на канал`.
- Expired: `🔒 Подписка закончилась <b>{date}</b>`.
- Date and device limit from the same sources the bot already uses (panel, mirrored in Mongo; device count from the bot's DB). Escape the name.

Keyboard (one button per row unless noted):

| Button | Action |
|---|---|
| 🔗 Подключиться | same as now (cabinet). `style="success"` if aiogram accepts it (Bot API 9.4); skip otherwise |
| 👤 Личный кабинет | the URL the current «⚡ Купить» opens (cabinet buy page); «Купить» itself goes away |
| ⭐ Задания | callback, new screen (section 4) |
| 🎁 Друзья · ℹ️ Информация | two in one row. Друзья = the existing Рефералы screen; Информация = existing screen |
| 💬 Поддержка · 📢 Новости | two in one row. Поддержка = current URL; Новости = https://t.me/gaatex_vpn |
| 🌐 Наш сайт | https://gatexx.ru (as now) |
| 🛠 Админ-панель | admin only, as now |

Do not touch the trial / channel gate / language flow on first /start.

## 3. Screen switching

Telegram cannot `edit_message_text` on a photo message. Add one helper, e.g. `show_screen(target, banner_key, text, kb)`:

- If the current message has a photo: `edit_message_media(InputMediaPhoto(media=<file_id or FSInputFile>, caption=text, parse_mode=HTML), reply_markup=kb)`.
- If it is a text message (old menus still in chats): delete it if possible and `send_photo` a new one.
- Ignore «message is not modified». On any other edit error fall back to sending a new photo.
- Caption limit is 1024 characters. If a screen's text is longer (Информация with tariffs may be), shorten the text or keep that one screen as a text message after the photo. Never let a long caption crash the handler.

Use it for every screen reachable from the main menu, and for «Назад» back to the main menu. Banner per screen: Информация → `info`, Друзья → `ref`, Задания → `tasks`, ban-vpn «Доступ ограничен» → `blocked`, any support/connect screens → `support` / `connect`.

## 4. «Задания» screen (new)

Caption (HTML):

```
<b>Задания</b>
Выполняйте и получайте дни подписки бесплатно.

<blockquote><b>✏️ Ник в Telegram · +7 дней</b>
Добавьте <code>GateX</code> или <code>@gatexvpn_bot</code> в имя или в «О себе» и нажмите «Проверить».
Уберёте ник, 7 дней снимутся.</blockquote>
Статус: {⏳ не выполнено | ✅ выполнено, +7 дней начислено}
```

Buttons: `✅ Проверить ник` (callback), `◀️ Назад`.

### Rules (decided by Ilya)

- Match: `first_name`, `last_name` or `bio` contains `gatex` (case-insensitive; this also covers `@gatexvpn_bot`). Read them with `bot.get_chat(user_id)` (ChatFullInfo has first_name, last_name, bio).
- Needs an existing panel user (trial or paid). Otherwise answer: «Сначала получите пробный период: подпишитесь на канал в начале бота». No pending days for this task.
- Not for people excluded by the ban-vpn list (same check referral.py uses).
- Grant +`NICK_BONUS_DAYS` (default 7): atomic flip `User.nick_bonus_active` False→True, then add days to panel expireAt and Mongo using the existing referral helper. Store `nick_bonus_granted_at`.
- Recheck: background task every `NICK_RECHECK_HOURS` (default 6) for users with `nick_bonus_active=True`, plus a check when such a user opens the main menu. If the nick is gone: atomic True→False, subtract the same days from panel expireAt and Mongo (new small helper next to the referral one; do not set a date earlier than now), store `nick_bonus_revoked_at`, message the user:
  «✏️ GateX пропал из вашего имени, поэтому бонус +7 дней снят. Подписка до {date}. Верните ник и нажмите «Проверить» в «Заданиях».»
- After a revoke the user may claim again (net zero days, so nothing to farm).
- If `get_chat` fails (user blocked the bot, network): skip, never revoke on an error.
- «Проверить ник» rate limit: once per 30 s per user.
- Success message in the caption/answer: «🎉 Ник найден — +7 дней. Подписка до {date}.» Not found: «Ник не найден. Добавьте GateX в имя или «О себе» и попробуйте через минуту.»
- `.env` / config: `NICK_BONUS_DAYS=7`, `NICK_RECHECK_HOURS=6`.
- Admin notification on each grant and revoke (one line, like referral notifications if they exist).

## 5. Друзья (referral screen)

Remove the old «💰 Заработано: … ₽» line. Text:

```
<b>Пригласите друга</b>
Друг заходит по вашей ссылке и подписывается на канал. Вы оба получаете +7 дней.

<blockquote>Ваша ссылка:
<code>{link}</code></blockquote>
👥 Приглашено: <b>{count}</b> · 🎁 Получено: <b>{days} дн.</b>
```

(`Получено` only if the bot already stores referral days given; otherwise drop that part.) Buttons: `📤 Поделиться ссылкой` → `https://t.me/share/url?url={link}&text=GateX VPN: +7 дней в подарок`, `◀️ Назад`.

## 6. Test, then restart

- `py_compile` on every changed file.
- Grant/revoke logic: unit test with a fake user / mocked panel call. Do not give or take days from real users while testing.
- `systemctl restart vpn_bot`, `journalctl -u vpn_bot -n 100` clean.
- Send the new main menu to ADMIN_ID only (Ilya) so he can look.

## 7. Report

Write to `C:\Users\ilyab\.ssh\MENU_REPORT.md`: changed files, new User fields, env vars, backup path, rollback command, test results, anything uncertain.
