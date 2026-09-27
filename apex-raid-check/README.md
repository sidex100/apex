# apex-raid-check

[Русский](#русский) · [English](#english)

---

## Русский

Письма при изменении состояния аппаратного RAID **Dell PERC** (H330, H730 и др. — контроллеры на базе LSI/Broadcom
MegaRAID) и его дисков. Раз в час скрипт снимает «снимок» состояния через утилиту Dell **perccli** и сравнивает с прошлым.

Зачем, если есть smartd? smartd смотрит **здоровье самих дисков** (SMART, температура, самотесты). Но если
контроллер выкинет диск из массива или RAID станет Degraded, smartd может промолчать. Этот скрипт следит за
**массивом и контроллером** — вместе они закрывают оба случая.

### Какие письма приходят
| Тема | Когда |
|---|---|
| `apex-raid-check started` | первый запуск: текущее состояние (проверка, что почта доходит) |
| `ALERT: RAID not optimal` | состояние изменилось и стало ненормальным |
| `ALERT (reminder): RAID still not optimal` | всё ещё ненормально — напоминание раз в 12 часов |
| `OK: RAID back to normal` | вернулось в норму (например, закончилась перестройка) |
| `INFO: RAID state lines changed` | что-то в снимке изменилось, но всё в норме |
| `INFO: disk non-medium errors grew` | счётчик non-medium errors диска вырос больше чем на 10 с прошлого отчёта |

### Что считается нормой
Снимок — три вида строк:
```
controller: Optimal
vd 0/0: RAID1 Optl
pd 32:0: SSD Onln
pd 32:1: SSD Onln
```
- **controller** должен быть `Optimal`;
- **vd** (виртуальный диск = массив) — `Optl` (optimal). Плохо: `Dgrd` (degraded — один диск выпал),
  `Pdgd` (partially degraded), `OfLn` (offline — массив недоступен);
- **pd** (физический диск) — `Onln` (в массиве). Плохо: `Rbld` (перестраивается), `Offln`, `UBad` (unconfigured bad),
  `Failed`, `UGood` (исправен, но не в массиве — например, новый диск ещё не добавлен).
Любое отклонение — ALERT. В письме — что именно изменилось (`<` было, `>` стало) и полный снимок.

### Non-medium errors — что это
Счётчик SAS-диска «ошибки, не связанные с поверхностью/флеш-памятью»: сбросы шины, таймауты, проблемы связи
с контроллером. Небольшие значения нормальны. Замечено: **каждая перезагрузка добавляет ~3 на диск**
(контроллер сбрасывает шину) — это безвредно. Поэтому письмо — только если счётчик вырос **больше чем на 10**
с момента последнего отчёта. Равномерный рост без перезагрузок — повод проверить контроллер, кабели, корзину (backplane).

### Требования
- контроллер Dell PERC и утилита **perccli** (скачивается с сайта Dell, ставится в `/opt/MegaRAID/perccli/perccli64`).
  У Broadcom та же утилита называется **storcli** (синтаксис тот же) — поменяйте путь в `PERCCLI`;
- `smartmontools` (`smartctl`) — для счётчика non-medium errors (диски за контроллером: `-d megaraid,N`);
- работающая отправка почты и команда `mail`; `bash`, systemd.
- Скрипт смотрит контроллер `/c0` (первый). Если их несколько — нужно доработать.

### Установка
```bash
install -m 755 apex-raid-check.sh /usr/local/sbin/apex-raid-check
install -m 644 apex-raid-check.service apex-raid-check.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now apex-raid-check.timer
systemctl start apex-raid-check.service
journalctl -u apex-raid-check -n 20
```
Полезные ручные команды:
```bash
/opt/MegaRAID/perccli/perccli64 /c0 show            # контроллер, массивы, диски — кратко
/opt/MegaRAID/perccli/perccli64 /c0/eall/sall show  # физические диски
smartctl --scan                                      # какие диски видит smartctl за контроллером
smartctl -x -d megaraid,0 /dev/bus/0                 # всё о диске 0
```

### Настройки (переменные в начале скрипта)
| Переменная | По умолчанию | Смысл |
|---|---|---|
| `PERCCLI` | `/opt/MegaRAID/perccli/perccli64` | путь к утилите |
| `STATE_DIR` | `/var/lib/apex-raid-check` | память между запусками |
| `MAILTO` | `root` | кому писать |
| `REMIND` | 12 часов | как часто напоминать, пока плохо |
| `NME_THRESHOLD` | 10 | на сколько должен вырасти счётчик non-medium errors для письма |

### Как устроено (разбор)
1. **`snapshot()`** вызывает perccli три раза и через `awk` оставляет только нужные колонки — получается короткий
   текст, который удобно сравнивать. Лишние поля (температура, размеры) в снимок специально не попадают:
   иначе письмо приходило бы на каждое колебание.
2. **Проверка нормы** — `grep`: нет ни одной строки `vd` → плохо (массив пропал); есть `controller` не `Optimal`,
   `vd` не `Optl`, `pd` не `Onln` → плохо. Результат — флаг `bad`.
3. **Сравнение с прошлым**: прошлый снимок лежит в `STATE_DIR/state`. Различия показывает `diff` — в письмо идут
   только изменённые строки. Отдельно запоминаются флаг `bad` и время последней тревоги (`last_alert`) для напоминаний.
4. **Non-medium errors**: для каждого диска хранится «база» (`nme-megaraid_N`) — значение на момент последнего отчёта.
   Если значение меньше базы (диск заменили) — база просто обновляется.
5. **Расписание** — systemd timer: раз в час, случайная задержка до 5 минут, пропущенный запуск выполняется после
   включения сервера (`Persistent=true`).

### Обслуживание
- Заменили диск / пересобрали массив — придут ALERT, потом OK; больше ничего делать не нужно.
- Начать с нуля: удалить `/var/lib/apex-raid-check`.
- Проверить, как выглядит снимок, без писем: `bash -c 'source <(sed -n "/^PERCCLI=/,/^}/p" /usr/local/sbin/apex-raid-check); snapshot'`.

---

## English

Mail notifications when the state of a **Dell PERC** hardware RAID (H330, H730, etc. — LSI/Broadcom MegaRAID based
controllers) or its disks changes. Every hour the script takes a "snapshot" via Dell's **perccli** tool and compares
it with the previous one.

Why, if there is smartd? smartd watches **disk health** (SMART, temperature, self-tests). But if the controller drops
a disk from the array or the RAID becomes Degraded, smartd may stay silent. This script watches **the array and the
controller** — together they cover both cases.

### Mails
| Subject | When |
|---|---|
| `apex-raid-check started` | first run: current state (also proves mail delivery works) |
| `ALERT: RAID not optimal` | state changed and is not normal |
| `ALERT (reminder): RAID still not optimal` | still not normal — reminder every 12 hours |
| `OK: RAID back to normal` | back to normal (e.g. rebuild finished) |
| `INFO: RAID state lines changed` | something in the snapshot changed, but everything is normal |
| `INFO: disk non-medium errors grew` | a disk's non-medium error count grew by more than 10 since the last report |

### What is normal
The snapshot has three kinds of lines (see the example above):
- **controller** must be `Optimal`;
- **vd** (virtual drive = the array) — `Optl`. Bad: `Dgrd` (degraded — a disk dropped out), `Pdgd` (partially degraded),
  `OfLn` (offline);
- **pd** (physical drive) — `Onln` (in the array). Bad: `Rbld` (rebuilding), `Offln`, `UBad`, `Failed`,
  `UGood` (healthy but not in an array — e.g. a new disk not added yet).
Any deviation is an ALERT. The mail shows what changed (`<` old, `>` new) and the full snapshot.

### Non-medium errors
A SAS disk counter of errors not related to the media: bus resets, timeouts, link problems with the controller.
Small values are normal. Observed: **every reboot adds ~3 per disk** (the controller resets the bus) — harmless.
So a mail is sent only if the counter grew **by more than 10** since the last report. Steady growth without reboots
means: check the controller, cables, backplane.

### Requirements
- a Dell PERC controller and **perccli** (download from Dell, installs to `/opt/MegaRAID/perccli/perccli64`).
  Broadcom's equivalent is **storcli** (same syntax) — change the `PERCCLI` path;
- `smartmontools` (`smartctl`) for the non-medium error counter (disks behind the controller: `-d megaraid,N`);
- working local mail and the `mail` command; `bash`, systemd.
- Only controller `/c0` (the first one) is checked.

### Install
```bash
install -m 755 apex-raid-check.sh /usr/local/sbin/apex-raid-check
install -m 644 apex-raid-check.service apex-raid-check.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now apex-raid-check.timer
systemctl start apex-raid-check.service
journalctl -u apex-raid-check -n 20
```
Useful manual commands — see the Russian section above.

### Settings (variables at the top of the script)
| Variable | Default | Meaning |
|---|---|---|
| `PERCCLI` | `/opt/MegaRAID/perccli/perccli64` | tool path |
| `STATE_DIR` | `/var/lib/apex-raid-check` | memory between runs |
| `MAILTO` | `root` | recipient |
| `REMIND` | 12 hours | reminder interval while the state is bad |
| `NME_THRESHOLD` | 10 | growth of the non-medium error count that triggers a mail |

### How it works (walk-through)
1. **`snapshot()`** calls perccli three times and keeps only the needed columns with `awk` — a short text that is easy
   to compare. Volatile fields (temperature, sizes) are deliberately left out, otherwise every fluctuation would send a mail.
2. **Normal check** with `grep`: no `vd` line at all → bad (array is gone); a `controller` not `Optimal`, a `vd` not
   `Optl` or a `pd` not `Onln` → bad. The result is the `bad` flag.
3. **Comparison**: the previous snapshot is in `STATE_DIR/state`; `diff` shows only changed lines. The `bad` flag and
   the last alert time (`last_alert`) are stored for reminders.
4. **Non-medium errors**: each disk has a "baseline" (`nme-megaraid_N`) — the value at the last report. If the value
   is lower than the baseline (disk replaced), the baseline is simply updated.
5. **Scheduling** — systemd timer: hourly, random delay up to 5 minutes, a missed run happens after boot (`Persistent=true`).

### Maintenance
- Replaced a disk / rebuilt the array — you get ALERT, then OK; nothing else to do.
- Start over: delete `/var/lib/apex-raid-check`.
- See the current snapshot without mail: `bash -c 'source <(sed -n "/^PERCCLI=/,/^}/p" /usr/local/sbin/apex-raid-check); snapshot'`.
