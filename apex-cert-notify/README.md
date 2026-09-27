# apex-cert-notify

[Русский](#русский) · [English](#english)

---

## Русский

Письма о сертификатах Let's Encrypt, которые выпускает и продлевает **nginx-module-acme** (официальный ACME-модуль
nginx.org). Модуль делает всё сам внутри nginx, но **никого ни о чём не уведомляет** — ни об успехе, ни об ошибке.
Этот скрипт закрывает пробел.

### Какие письма приходят
| Тема | Когда |
|---|---|
| `apex-cert-notify started` | самый первый запуск: список всех найденных сертификатов (проверка, что почта доходит) |
| `NEW: certificate issued for <имя>` | появился новый сертификат (новый сайт или изменился набор имён) |
| `OK: certificate renewed for <имя>` | сертификат продлён (сменился серийный номер) |
| `WARNING: certificate for <имя> not renewed` | прошло плановое время продления + запас, а сертификат всё ещё старый |
| `ERROR: ACME messages in nginx log` | в `/var/log/nginx/error.log` появились новые строки про ACME уровня warn/error |

В теме — короткое имя сервера (`[apex]`), в тексте — срок действия, плановое время продления, время будущей тревоги и серийник:
```
apex.example.com
  valid:   2026-09-27 10:14 UTC -> 2026-12-26 10:14 UTC
  planned renewal: 2026-11-26 10:14 UTC
  alert if not renewed by: 2026-11-29 10:14 UTC
  serial:  05A1...
```

### Главная идея: тревога никогда не раньше плановой замены
По исходникам модуля: сертификат сроком **больше 10 дней** (обычный, 90 дней) продлевается на **2/3 срока**
(на 60-й день), сертификат **10 дней и меньше** (профиль `shortlived`, ~6,5 дня — например, на IP-адрес) —
на **половине срока**. Скрипт считает эту точку сам по датам из сертификата и добавляет запас:
**+3 дня** для длинных и **+24 часа** для коротких. Пока запас не прошёл, WARNING не будет — даже если модуль
продлевает с небольшим опозданием (у него есть случайный разброс ~2% и повторы при сбоях).

### Требования
- nginx с `nginx-module-acme`, у издателей (`acme_issuer`) задан `state_path` в `/var/cache/nginx/acme-letsencrypt*`
  (или поправьте `CERT_GLOB` в начале скрипта);
- работающая локальная отправка почты и команда `mail` (например, Postfix + `s-nail`);
- `openssl`, `bash`, systemd.

Пример издателя в `nginx.conf` (блок `http`):
```nginx
acme_issuer letsencrypt {
    uri         https://acme-v02.api.letsencrypt.org/directory;
    contact     admin@example.com;
    state_path  /var/cache/nginx/acme-letsencrypt;
    accept_terms_of_service;
}
```

### Установка
```bash
install -m 755 apex-cert-notify.sh /usr/local/sbin/apex-cert-notify
install -m 644 apex-cert-notify.service apex-cert-notify.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now apex-cert-notify.timer
```
Первый запуск — вручную, чтобы сразу получить письмо `started`:
```bash
systemctl start apex-cert-notify.service
journalctl -u apex-cert-notify -n 20
systemctl list-timers apex-cert-notify.timer
```

### Настройки (переменные в начале скрипта)
| Переменная | По умолчанию | Смысл |
|---|---|---|
| `CERT_GLOB` | `/var/cache/nginx/acme-letsencrypt*/*.crt` | где модуль хранит сертификаты |
| `STATE_DIR` | `/var/lib/apex-cert-notify` | память скрипта между запусками |
| `NGINX_LOG` | `/var/log/nginx/error.log` | общий лог ошибок nginx (туда пишет модуль) |
| `MAILTO` | `root` | кому писать |
| `GRACE_LONG` / `GRACE_SHORT` | 3 дня / 24 часа | запас после плановой замены |

### Как устроено (разбор)
1. **`set -u`** — обращение к несуществующей переменной считается ошибкой: опечатка в имени не превратится молча в пустую строку.
2. **Список сертификатов.** Модуль кладёт файлы как `<первое имя>-<хэш>.crt`. `${base%-*}` отрезает хэш,
   чтобы в письме было понятное имя.
3. **Даты и серийник** — из самого сертификата: `openssl x509 -noout -startdate / -enddate / -serial`,
   переводятся в секунды (`date +%s`), дальше обычная арифметика `$(( ))`.
4. **Память.** Для каждого сертификата в `STATE_DIR` лежит файл с последним увиденным серийником.
   Серийник сменился → письмо OK. Файла не было → письмо NEW (кроме самого первого запуска, иначе пришло бы по письму на каждый сертификат).
5. **Лог nginx.** Скрипт запоминает, до какого байта дочитал лог (`nginx-error-log.offset`), и в следующий раз читает
   только новое (`tail -c +N`). Если файл стал меньше — значит, logrotate его сменил: сначала дочитывается хвост `error.log.1`.
   Из нового берутся строки со словом `acme` и уровнем warn/error/crit/alert/emerg.
6. **Запуск по расписанию** — systemd timer, а не cron:
   `OnCalendar=hourly` — раз в час; `RandomizedDelaySec=300` — случайная задержка до 5 минут;
   `Persistent=true` — если сервер был выключен во время запуска, скрипт выполнится сразу после включения.
   `Type=oneshot` у service — «выполнить и завершиться». Вывод и ошибки — в `journalctl -u apex-cert-notify`.

### Обслуживание
- **Удалили сайт или сменили имена** — модуль выпустит новый сертификат, а старый файл **останется** в `state_path`.
  Удалите старые `.crt/.key` оттуда и файл с тем же именем из `/var/lib/apex-cert-notify/`, иначе через ~2 месяца придёт WARNING про брошенный сертификат.
- **Начать с нуля:** удалить папку `/var/lib/apex-cert-notify` — следующий запуск снова пришлёт `started`.
- **Проверка без писем:** скопировать скрипт, заменить в копии `send()` на `echo` и `STATE_DIR` на временную папку, запустить `bash -x копия`.

---

## English

Mail notifications about Let's Encrypt certificates issued and renewed by **nginx-module-acme** (the official
nginx.org ACME module). The module does everything inside nginx but **notifies nobody** — neither on success nor on
failure. This script fills that gap.

### Mails
| Subject | When |
|---|---|
| `apex-cert-notify started` | very first run: list of all certificates found (also proves mail delivery works) |
| `NEW: certificate issued for <name>` | a new certificate appeared (new site or changed set of names) |
| `OK: certificate renewed for <name>` | a certificate was renewed (serial number changed) |
| `WARNING: certificate for <name> not renewed` | planned renewal time + grace has passed and the certificate is still the old one |
| `ERROR: ACME messages in nginx log` | new ACME lines of level warn/error appeared in `/var/log/nginx/error.log` |

The subject carries the short host name (`[apex]`); the body shows validity, planned renewal, alert time and serial
(see the example above).

### Key idea: never alert before the planned renewal
From the module source: a certificate valid **longer than 10 days** (regular, 90 days) is renewed at **2/3 of its
lifetime** (day 60); a certificate of **10 days or less** (`shortlived` profile, ~6.5 days, e.g. for an IP address) —
at **half** of its lifetime. The script computes that point from the certificate dates and adds grace:
**+3 days** for long certificates and **+24 hours** for short ones. Until the grace has passed there is no WARNING,
even if the module renews slightly late (it adds ~2% random jitter and retries on failures).

### Requirements
- nginx with `nginx-module-acme`, issuers (`acme_issuer`) with `state_path` under `/var/cache/nginx/acme-letsencrypt*`
  (or adjust `CERT_GLOB` at the top of the script) — see the `nginx.conf` example above;
- working local mail and the `mail` command (e.g. Postfix + `s-nail`);
- `openssl`, `bash`, systemd.

### Install
```bash
install -m 755 apex-cert-notify.sh /usr/local/sbin/apex-cert-notify
install -m 644 apex-cert-notify.service apex-cert-notify.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now apex-cert-notify.timer
```
Run it once by hand to get the `started` mail right away:
```bash
systemctl start apex-cert-notify.service
journalctl -u apex-cert-notify -n 20
systemctl list-timers apex-cert-notify.timer
```

### Settings (variables at the top of the script)
| Variable | Default | Meaning |
|---|---|---|
| `CERT_GLOB` | `/var/cache/nginx/acme-letsencrypt*/*.crt` | where the module stores certificates |
| `STATE_DIR` | `/var/lib/apex-cert-notify` | script memory between runs |
| `NGINX_LOG` | `/var/log/nginx/error.log` | main nginx error log (the module writes there) |
| `MAILTO` | `root` | recipient |
| `GRACE_LONG` / `GRACE_SHORT` | 3 days / 24 hours | grace after the planned renewal |

### How it works (walk-through)
1. **`set -u`** — using an unset variable is an error, so a typo never silently becomes an empty string.
2. **Certificate list.** The module names files `<first name>-<hash>.crt`; `${base%-*}` strips the hash for a readable name.
3. **Dates and serial** come from the certificate itself (`openssl x509 -noout -startdate / -enddate / -serial`),
   converted to seconds (`date +%s`), then plain `$(( ))` arithmetic.
4. **Memory.** For each certificate `STATE_DIR` holds a file with the last seen serial. Serial changed → OK mail.
   No file yet → NEW mail (except on the very first run, otherwise every certificate would send one).
5. **nginx log.** The script remembers the byte offset it has read up to (`nginx-error-log.offset`) and next time reads
   only new data (`tail -c +N`). If the file got smaller, logrotate replaced it — the tail of `error.log.1` is read first.
   Lines containing `acme` with level warn/error/crit/alert/emerg are reported.
6. **Scheduling** — a systemd timer instead of cron: `OnCalendar=hourly`; `RandomizedDelaySec=300` — random delay up
   to 5 minutes; `Persistent=true` — a run missed while the server was off happens right after boot.
   `Type=oneshot` — run and exit. Output and errors: `journalctl -u apex-cert-notify`.

### Maintenance
- **Removed a site or changed its names** — the module issues a new certificate, but the old file **stays** in
  `state_path`. Delete the old `.crt/.key` there and the file with the same name in `/var/lib/apex-cert-notify/`,
  otherwise in ~2 months you will get a WARNING about the abandoned certificate.
- **Start over:** delete `/var/lib/apex-cert-notify` — the next run sends `started` again.
- **Dry run without mail:** copy the script, replace `send()` with `echo` and `STATE_DIR` with a temp folder in the copy,
  run `bash -x copy`.
