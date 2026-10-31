# Сайт GateX VPN

Одностраничный промо-сайт: `index.html`, без сборки и зависимостей (шрифты Google Fonts, всё остальное внутри файла).

Адрес: https://gatexx.ru (хостинг reg.ru). В корень сайта кладутся все файлы этой папки, кроме README.md: `index.html`, `.htaccess`, `robots.txt`, `sitemap.xml`, `og.png` (картинка для превью ссылки), `apple-touch-icon.png`, `favicon.ico`.

Редирект на HTTPS включается в панели хостинга (настройки сайта), не в `.htaccess`: за фронтовым nginx reg.ru Apache не видит HTTPS, и правило по `%{HTTPS}` зацикливается.

Цены в скрипте внизу страницы (`PRICES`) повторяют `plans.py` бота; при смене тарифов править оба места.

## Страницы-инструкции (SEO)

`tools/build_pages.py` собирает страницы `instrukcii/`, `vpn-belye-spiski/`, `vpn-krym/`, `happ-nastroika/`, `vpn-ne-rabotaet-na-mobilnom/`, а также `404.html`, `sitemap.xml` и общий стиль `assets/guide.css` (стили берутся из `index.html`). Тексты страниц лежат в самом скрипте. После правки: `python3 tools/build_pages.py`, затем залить изменённые файлы. Папку `tools/` на хостинг не класть.

Длина пробного периода в текстах задаётся константой `TRIAL` в скрипте, цены в таблице на странице про белые списки повторяют `PRICES` из `index.html`.
