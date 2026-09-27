# apex.ps1

[Русский](#русский) · [English](#english)

---

## Русский

PowerShell-скрипт для Windows: выполняет команду на сервере по SSH и **дописывает команду и её вывод в журнал**
`server-log.md` (Markdown). Так у каждого действия на сервере остаётся след: когда, зачем, что выполнили, что ответил сервер.

У нас им пользуется ассистент (Claude Code) для проверок «только чтение», а всё, что меняет сервер, человек
выполняет сам в своей SSH-сессии. Журнал — общий.

### Пример
```powershell
.\tools\apex.ps1 -Cmd "systemctl is-active nginx; nginx -v" -Why "check nginx"
```
В `server-log.md` появится:
````markdown
## 2026-09-27 23:19:43
**Зачем:** check nginx
```
[root@apex]# systemctl is-active nginx; nginx -v
active
nginx version: nginx/1.30.5
```
exit code: 0
````
Тот же текст выводится на экран. Код выхода скрипта = код выхода команды на сервере.

### Требования
- Windows 10/11, **Windows PowerShell 5.1** (встроен) или PowerShell 7;
- встроенный клиент OpenSSH (`ssh`) и вход **по ключу** на сервер. В `%USERPROFILE%\.ssh\config` — короткое имя `apex`:
  ```
  Host apex
      HostName 203.0.113.10
      User root
      IdentityFile ~/.ssh/hosting_ed25519
      IdentitiesOnly yes
  ```
- на сервере — `bash`, `sed`, `tr` (есть везде).

Куда класть: скрипт ищет журнал **на уровень выше своей папки** (`..\server-log.md`). У нас раскладка такая:
```
hosting\
  server-log.md
  tools\apex.ps1
```

### Как устроено (разбор)
1. **Команда уходит через stdin, а не аргументом `ssh`.** Windows PowerShell 5.1 портит вложенные кавычки при
   передаче аргументов внешним программам — команды с `"` и `'` приходили на сервер искалеченными.
   Через stdin текст доходит как есть, а на сервере его выполняет `bash -s`.
2. **На сервере текст чистится:** `sed '1s/^\xEF\xBB\xBF//'` убирает BOM, который PowerShell 5.1 ставит в начало
   потока, `tr -d '\r'` убирает CR из виндовых переводов строк. Без этого bash видел бы мусор в первой команде.
3. **`$OutputEncoding` = UTF-8 без BOM** — чтобы кириллица и спецсимволы в команде не превратились в `?`.
4. **`-o BatchMode=yes`** — никаких вопросов пароля: нет ключа → сразу ошибка, а не зависание.
   **`-o ConnectTimeout=10`** — сервер недоступен → ошибка через 10 секунд.
5. **`2>&1`** — ошибки сервера тоже попадают в журнал, вместе с обычным выводом.
6. Сам файл — UTF-8 **с BOM**: без BOM Windows PowerShell 5.1 читает скрипт в кодировке ANSI и ломает кириллицу в комментариях.

### Осторожно
Скрипт ничего не спрашивает — выполняет переданную команду сразу, от того пользователя, что в `~/.ssh/config`
(у нас root). Журнал может содержать всё, что вывела команда, — не выкладывайте его публично
(поэтому `server-log.md` в `.gitignore`).

---

## English

A Windows PowerShell script: runs a command on the server over SSH and **appends the command and its output to a
journal** `server-log.md` (Markdown). Every action on the server leaves a trace: when, why, what was run, what the
server answered.

In our setup the assistant (Claude Code) uses it for read-only checks; anything that changes the server is run by a
human in their own SSH session. The journal is shared.

### Example
```powershell
.\tools\apex.ps1 -Cmd "systemctl is-active nginx; nginx -v" -Why "check nginx"
```
appends a timestamped block with the reason, the command, its output and the exit code (see the example above).
The same text is printed to the console. The script's exit code is the remote command's exit code.

### Requirements
- Windows 10/11, **Windows PowerShell 5.1** (built in) or PowerShell 7;
- the built-in OpenSSH client (`ssh`) and **key-based** login; a short host name `apex` in
  `%USERPROFILE%\.ssh\config` (see the example above);
- `bash`, `sed`, `tr` on the server (available everywhere).

The journal is looked up **one level above the script folder** (`..\server-log.md`).

### How it works (walk-through)
1. **The command is sent via stdin, not as an `ssh` argument.** Windows PowerShell 5.1 mangles nested quotes when
   passing arguments to external programs. Via stdin the text arrives intact and `bash -s` runs it on the server.
2. **The text is cleaned on the server:** `sed '1s/^\xEF\xBB\xBF//'` removes the BOM that PowerShell 5.1 prepends to
   the stream, `tr -d '\r'` removes CR from Windows line endings.
3. **`$OutputEncoding` = UTF-8 without BOM**, so non-ASCII characters in the command do not turn into `?`.
4. **`-o BatchMode=yes`** — never prompts for a password: no key → immediate error instead of hanging.
   **`-o ConnectTimeout=10`** — server unreachable → error after 10 seconds.
5. **`2>&1`** — remote errors go to the journal together with normal output.
6. The file itself is UTF-8 **with BOM**: without it Windows PowerShell 5.1 reads the script as ANSI and breaks
   non-ASCII comments.

### Caution
The script asks nothing — it runs the given command immediately as the user from `~/.ssh/config` (root in our case).
The journal may contain anything the commands printed — do not publish it (that is why `server-log.md` is in `.gitignore`).
