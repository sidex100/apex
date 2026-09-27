# apex — служебные скрипты хостинга / hosting helper scripts

[Русский](#русский) · [English](#english)

---

## Русский

Небольшие скрипты, написанные для личного хостинга на **AlmaLinux 9** без панели управления.
Выложены открыто — для разбора, как документация и для всех, кому пригодится.

### Сервер, для которого это сделано
- AlmaLinux 9, SELinux, firewalld, всё управление — по SSH.
- **nginx** (nginx.org) — единственный веб-сервер; сертификаты Let's Encrypt выпускает сам nginx
  модулем **nginx-module-acme** (в том числе сертификаты на IP-адрес, профиль `shortlived`).
- Почта — только отправка: Postfix (localhost) + OpenDKIM; письма `root` уходят на личный ящик.
- Железо: Dell PERC H330 (LSI SAS3008), RAID1 из двух SAS SSD.

### Что внутри
| Папка | Где работает | Что делает |
|---|---|---|
| [`apex-cert-notify/`](apex-cert-notify/) | сервер (bash + systemd timer) | Письма о сертификатах nginx-module-acme: новый, продлён, не продлился вовремя, ошибки ACME в логе. У модуля своих уведомлений нет. |
| [`apex-raid-check/`](apex-raid-check/) | сервер (bash + systemd timer) | Письма при изменении состояния RAID Dell PERC и дисков (perccli + smartctl). |
| [`apex-ps1/`](apex-ps1/) | ПК с Windows (PowerShell) | Выполнить команду на сервере по SSH и записать команду и вывод в журнал Markdown. |

В каждой папке — свой README: что делает скрипт, как устроен внутри (построчный разбор), как установить и проверить.

### Общие правила этих скриптов
- Имена с префиксом `apex-`: так их сразу видно среди системных.
- Скрипт — `/usr/local/sbin/apex-<имя>`, запуск — `/etc/systemd/system/apex-<имя>.{service,timer}`,
  состояние между запусками — `/var/lib/apex-<имя>/`.
- Только ASCII и переводы строк LF (Linux). Файл с CRLF bash не выполнит — за этим следит `.gitattributes`.
- Письма уходят на `root` командой `mail`; куда дальше — решает `/etc/aliases` (у нас — на личный ящик).
- Первый запуск присылает письмо «started» со списком того, что скрипт видит, — это и есть проверка, что почта доходит.

### Как скачать
- Один файл: откройте его на GitHub → кнопка **Raw** → сохранить; или на сервере:
  `curl -O https://raw.githubusercontent.com/sidex100/apex/main/apex-cert-notify/apex-cert-notify.sh`
- Весь репозиторий: `git clone https://github.com/sidex100/apex.git`

### Лицензия
[MIT](LICENSE) — используйте, меняйте, распространяйте; сохраните упоминание автора. Без гарантий:
перед установкой прочитайте скрипт — он короткий.

---

## English

Small scripts written for a personal hosting server on **AlmaLinux 9** without a control panel.
Published openly — to study, as documentation, and for anyone who finds them useful.

### The server they were made for
- AlmaLinux 9, SELinux, firewalld, everything managed over SSH.
- **nginx** (nginx.org) is the only web server; Let's Encrypt certificates are issued by nginx itself via
  **nginx-module-acme** (including IP address certificates, `shortlived` profile).
- Mail is send-only: Postfix (localhost) + OpenDKIM; mail for `root` is forwarded to a personal mailbox.
- Hardware: Dell PERC H330 (LSI SAS3008), RAID1 of two SAS SSDs.

### Contents
| Folder | Runs on | What it does |
|---|---|---|
| [`apex-cert-notify/`](apex-cert-notify/) | server (bash + systemd timer) | Mail about nginx-module-acme certificates: new, renewed, not renewed in time, ACME errors in the log. The module has no notifications of its own. |
| [`apex-raid-check/`](apex-raid-check/) | server (bash + systemd timer) | Mail when Dell PERC RAID or disk state changes (perccli + smartctl). |
| [`apex-ps1/`](apex-ps1/) | Windows PC (PowerShell) | Run a command on the server over SSH and append the command and its output to a Markdown journal. |

Each folder has its own README: what the script does, how it works inside (walk-through), how to install and test it.

### Common conventions
- Names start with `apex-` so they stand out among system files.
- Script — `/usr/local/sbin/apex-<name>`, scheduling — `/etc/systemd/system/apex-<name>.{service,timer}`,
  state between runs — `/var/lib/apex-<name>/`.
- ASCII only, LF line endings (Linux). bash will not run a file with CRLF — `.gitattributes` takes care of that.
- Mail goes to `root` via the `mail` command; `/etc/aliases` decides where it ends up.
- The first run sends a "started" mail listing what the script sees — this also proves that mail delivery works.

### Download
- One file: open it on GitHub → **Raw** → save; or on the server:
  `curl -O https://raw.githubusercontent.com/sidex100/apex/main/apex-cert-notify/apex-cert-notify.sh`
- Whole repository: `git clone https://github.com/sidex100/apex.git`

### License
[MIT](LICENSE) — use, modify, share; keep the copyright notice. No warranty: read a script before
installing it — they are short.
