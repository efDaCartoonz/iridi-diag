# Скрипты диагностики iRidi

Коллекция автономных инструментов для диагностики серверов, хранилища, шины CAN/Bus77 и облачного подключения iRidi. Скрипты для Linux написаны на переносимом POSIX `sh` и поддерживают прошивки HS Server на базе BusyBox. Скрипт для macOS поддерживает интерактивный запуск через Finder и CLI. Скрипты для Windows поддерживают встроенные версии Windows PowerShell в Windows 7, 10 и 11.

[English version](README.md) | [Руководство по мониторингу Bus77](BUS77_MONITORING_GUIDE_RU.md)

---

## Структура репозитория

- `scripts/linux` — Linux, Debian и прошивки на базе BusyBox;
- `scripts/macos` — macOS (интерактивный лаунчер и движок на POSIX sh);
- `scripts/windows` — Windows 7, Windows 10 и Windows 11.

### Windows

| Файл | Назначение |
| --- | --- |
| `run_iridi_cloud_windows.cmd` | Лаунчер для запуска двойным кликом с меню выбора продукта и автологированием |
| `check_iridi_cloud_windows_10_11.ps1` | Облачная диагностика (v1.5) для Windows 10/11 и Windows PowerShell 5.1 / PowerShell 7+ |
| `check_iridi_cloud_windows_7.ps1` | Облачная диагностика (v1.5) для Windows 7 и Windows PowerShell 2.0 или новее |

### macOS

| Файл | Назначение |
| --- | --- |
| `run_iridi_cloud_macos.command` | Лаунчер для запуска двойным кликом в Finder с меню выбора продукта и автологированием |
| `check_iridi_cloud_macos.sh` | Универсальная диагностика облака (v1.5) для macOS с поддержкой CLI-флагов и меню |

### Linux и BusyBox

| Файл | Назначение |
| --- | --- |
| `collect_support_bundle.sh` | Архив для удалённой поддержки: фрагменты логов, сведения о проекте, аппаратные данные и наблюдение процесса/Ethernet |
| `monitor_server_runtime.sh` | Монитор процесса в CSV: CPU, RSS, потоки, FD, дисковый I/O |
| `check_ethernet.sh` | Линк Ethernet и прирост ошибок, потерь и изменений carrier |
| `capture_network.sh` | Ограниченный пассивный захват PCAP для Wireshark |
| `check_server_health.sh` | Полный аудит сервера 360° (v2.2): серийники, прошивка, RS-485, RTC/батарейка, Watchdog, проекты, SQLite, логи, память, eMMC SMART, порты |
| `check_serial_ports.sh` | Диагностика портов RS-485 / UART (v1.1): ошибки кадрирования (fe/oe/pe), скорость, блокировки процессов, режим полудуплекса |
| `check_i3knx.sh` | Проверка облачных ресурсов i3 KNX на прикладном уровне и сессии Cloud Gate (v1.5) |
| `check_bus77_home.sh` | Проверка облачных ресурсов Bus77 Home на прикладном уровне (v1.5) |
| `check_bus77_lite.sh` | Проверка облачных ресурсов Bus77 Lite на прикладном уровне (v1.5) |
| `check_iridi_pro_ru.sh` | Проверка iRidi Pro Cloud для региона RU (v1.5) |
| `check_iridi_pro_eu.sh` | Проверка iRidi Pro Cloud для региона EU (v1.5) |
| `check_iridi_pro_cn.sh` | Проверка iRidi Pro Cloud для региона CN (v1.5) |
| `check_emmc_health.sh` | Диагностика eMMC (v2.2): SMART, разделы, inodes, бенчмарки скорости и 4K задержки БД |
| `check_can_bus.sh` | Диагностика CAN/Bus77 (v2.4): здоровье контроллера, инвентаризация (`--scan-only`), экспорт JSON |
| `monitor_can_bus.sh` | **Расшифровщик и монитор Bus77 (v2.3)**: живое декодирование команд/переменных, Bus Load %, Top Talkers, Ping RTT |

---

## Архитектура Dual-Stream: Человекочитаемый экран и подробный лог

Все диагностические скрипты используют модель **двойного потока данных**:

1. **Экран терминала (Human UI):**
   - Лаконичный, визуально чистый дашборд.
   - Цветные статусы `[OK]`, `[ATTENTION]`, `[NOT OK]`.
   - Понятные метрики: время ответа в `ms`, статус HTTP, IP-адреса, скорость в `MB/s`, температура `°C`, износ eMMC в `%`.
   - Отсутствие промежуточного шума и сырых служебных дампов.
2. **Файл технического лога (Technical Log):**
   - Автоматически сохраняется в файл (`/tmp/` или `scripts/.../logs/`).
   - Содержит точные временные метки `[YYYY-MM-DD HH:MM:SS]` на каждую операцию.
   - Полные HTTP/HTTPS заголовки запросов и ответов (`dump-header`), сырые тела ответов при ошибках.
   - Полные дампы системных файлов (`/proc/cpuinfo`, `/proc/meminfo`, `/oem/hal/ccinfo`, `df -h`, `ss -tulpn`).
   - Сырые регистры eMMC (`ext_csd`, `cid`, `csd`, `life_time`, `pre_eol_info`).
   - Журналы ядра (`dmesg`), статистика интерфейсов и сырые дампы пакетов CAN (`candump -x -e`).
   - Лог не содержит escape-последовательностей цветов для удобства чтения в любом редакторе и парсинга.

---

## Цветовая индикация и коды возврата

В интерактивном выводе используются следующие цвета:

- зелёный — `[OK]` и `RESULT: PASS`;
- жёлтый — `[ATTENTION]` и `RESULT: WARN`;
- красный — `[NOT OK]` и `RESULT: FAIL`.

В Linux и macOS цвета включаются только при выводе в терминал. Для отключения установите переменную `NO_COLOR=1`.

Коды возврата (exit codes) согласованы во всех инструментах:

- `0` — `PASS`: все обязательные проверки успешно пройдены;
- `1` — `WARN`: основные проверки пройдены, но есть предупреждения, требующие внимания;
- `2` — `FAIL`: одна или несколько обязательных проверок провалены или скрипт не смог завершиться штатно.

---

## Облачная диагностика на Windows

Скачайте все три файла в одну папку и дважды кликните по `run_iridi_cloud_windows.cmd`.

**Windows 10/11 — скачать через curl.exe (встроен с Windows 10 версии 1803):**

```bat
mkdir "%USERPROFILE%\Desktop\iridi-diag-windows" && cd /d "%USERPROFILE%\Desktop\iridi-diag-windows"
curl.exe -fL -o run_iridi_cloud_windows.cmd         "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/run_iridi_cloud_windows.cmd"
curl.exe -fL -o check_iridi_cloud_windows_10_11.ps1 "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_10_11.ps1"
curl.exe -fL -o check_iridi_cloud_windows_7.ps1     "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_7.ps1"
run_iridi_cloud_windows.cmd
```

**Windows 7 — скачать через certutil.exe:**

```bat
mkdir "%USERPROFILE%\Desktop\iridi-diag-windows"
cd /d "%USERPROFILE%\Desktop\iridi-diag-windows"
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/run_iridi_cloud_windows.cmd"         run_iridi_cloud_windows.cmd
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_10_11.ps1"  check_iridi_cloud_windows_10_11.ps1
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_7.ps1"      check_iridi_cloud_windows_7.ps1
run_iridi_cloud_windows.cmd
```

Лаунчер определит установленную версию Windows PowerShell, выберет совместимый движок диагностики, отобразит ход проверки и оставит окно открытым после завершения. Результаты каждого запуска сохраняются в папке `logs\` рядом со скриптами.

PowerShell-скрипты можно запустить напрямую с параметром `-Product`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_iridi_cloud_windows_10_11.ps1 -Product bus77-home
```

Поддерживаемые параметры:

```powershell
-Product i3knx [-Quality]
-Product bus77-home [-Quality]
-Product bus77-lite [-Quality]
-Product iridi-pro -Region RU [-Quality]
-Product iridi-pro -Region EU [-Quality]
-Product iridi-pro -Region CN [-Quality]
```

Параметр `-Quality` запускает расширенное тестирование задержек, потерь пакетов, MTU и скорости скачивания.

---

## Облачная диагностика на macOS

Скачайте оба файла в одну папку, затем дважды кликните по `run_iridi_cloud_macos.command` в Finder:

```sh
mkdir -p ~/Desktop/iridi-diag-macos && cd ~/Desktop/iridi-diag-macos
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/run_iridi_cloud_macos.command"
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/check_iridi_cloud_macos.sh"
chmod +x run_iridi_cloud_macos.command check_iridi_cloud_macos.sh
open .
```

Скрипт также можно запустить напрямую из Терминала:

```sh
sh check_iridi_cloud_macos.sh --product bus77-home
```

Поддерживаемые параметры командной строки:

```sh
sh check_iridi_cloud_macos.sh --product i3knx [--quality]
sh check_iridi_cloud_macos.sh --product bus77-home [--quality]
sh check_iridi_cloud_macos.sh --product bus77-lite [--quality]
sh check_iridi_cloud_macos.sh --product iridi-pro --region RU [--quality]
sh check_iridi_cloud_macos.sh --product iridi-pro --region EU [--quality]
sh check_iridi_cloud_macos.sh --product iridi-pro --region CN [--quality]
```

---

## Облачная диагностика на Linux

Скачивание и запуск скрипта через `wget`:

```sh
cd /tmp
wget --no-check-certificate -O check_bus77_home.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_bus77_home.sh
sh check_bus77_home.sh
```

Аналогично запускаются профили для других продуктов:

```sh
sh check_i3knx.sh
sh check_bus77_lite.sh
sh check_iridi_pro_ru.sh
sh check_iridi_pro_eu.sh
sh check_iridi_pro_cn.sh
```

Доступность Cloud Gate проверяется активным TCP-подключением к портам 9088 и 9089.

### Расширенная диагностика качества и стабильности (`--quality` / `--deep`)

Стандартный режим выполняет экспресс-проверку (10–15 секунд). Флаг `--quality` (или `-q`) включает расширенное тестирование:

```sh
sh check_bus77_home.sh --quality
sh check_iridi_pro_ru.sh --quality
```

В расширенном режиме выполняются:
1. **Задержка, джиттер и потери пакетов**: 10 последовательных проб HTTP/HTTPS с замером min/avg/max задержки, скорости DNS-резолвинга и процента потерь пакетов.
2. **Пропускная способность скачивания**: реальная передача тестовых данных из хранилища с расчетом скорости (в КБ/с или МБ/с).
3. **Серийная стабильность Cloud Gate (TCP Burst)**: 3 последовательных рукопожатия TCP для проверки брокера соединений.
4. **Path MTU и фрагментация кадров**: отправка ICMP-пакетов стандартного размера 1500 байт и туннельного размера 1400 байт с флагом Don't-Fragment (DF).

---

## Удалённая диагностика по SSH

Автономные Linux-скрипты на POSIX `sh` для BusyBox HSS. Для полного архива держите четыре файла рядом; без соседних мониторов сборщик создаёт частичный архив со статусом WARN. Пакеты не устанавливаются, службы не перезапускаются. Каждый запуск создаёт закрытый каталог `0700` в `/tmp` или существующем `--output-dir`: дашборд идёт в stdout, технический `audit.log` с метками времени — через FD 3. ANSI-коды не используются; поддерживается `NO_COLOR=1`. Коды возврата: 0 PASS, 1 WARN, 2 FAIL.

| Инструмент | Назначение | По умолчанию |
| --- | --- | --- |
| `collect_support_bundle.sh` | Ограниченные фрагменты серверных логов с эвристическим маскированием, сведения о проекте, RTC/eMMC/HAL, параллельное наблюдение процесса/Ethernet, проверенный tar.gz | 15с наблюдения; хвосты 3 логов по 128 КиБ; бюджет полезных данных 16 МиБ |
| `monitor_server_runtime.sh` | CPU, RSS, потоки, открытые FD и дисковый I/O процесса в CSV; обнаружение завершения и повторного использования PID | `iridium`, 60с, интервал 5с |
| `check_ethernet.sh` | Состояние линка, скорость/duplex, прирост ошибок, потерь и изменений carrier; дополнительные сведения ethtool | Физические проводные интерфейсы, 10с |
| `capture_network.sh` | Ограниченный пассивный захват tcpdump для Wireshark с проверкой PCAP | eth0, 30с, один кольцевой файл 8 десятичных МБ, snaplen 128, 100000 пакетов |

```sh
cd scripts/linux
sh collect_support_bundle.sh --duration 30
sh monitor_server_runtime.sh --duration 300 --interval 5
sh check_ethernet.sh --interface eth0 --duration 30
sh capture_network.sh --interface eth0 --host 192.168.1.50 --port 502 --duration 30 --max-mb 8
```

Все инструменты принимают `--output-dir DIR` и `--help`. Дополнительные параметры:

- Сборщик: `--data-dir DIR`, `--log-count 0..10`, `--log-kib 1..1024`, `--max-mb 4..128` (бюджет полезных данных), `--duration 1..300`.
- Процесс: `--pid PID`, `--duration 1..3600`, `--interval 1..300`. `CPU ALL%` — общая занятость CPU контроллера (0–100%); колонки `CPU0%`, `CPU1%`, … показывают каждое ядро (0–100%). `PROC TOTAL%` — доля процесса от общего CPU-времени всех ядер; `PROC 1C%` сохраняет шкалу одного ядра и может превышать 100%. Занятость CPU исключает idle и iowait, guest-время повторно не учитывается. Значения усредняются за интервал; первый замер CPU, сброс счётчиков и смена набора ядер дают `n/a`.
  `RAM PROC%` — RSS процесса / MemTotal; `RAM ALL%` — (MemTotal − MemAvailable) / MemTotal, с учётом освобождаемого кэша. RSS включает общие страницы памяти; память процесса уже входит в системную загрузку. Без MemAvailable выводится `n/a`, а не оценка по MemFree. Все проценты CPU/ядер и ОЗУ показаны колонками в одной строке на замер, а также сохраняются в CSV и техническом логе. Рост RSS/FD сам по себе не доказывает утечку. Недоступные показатели обозначены `n/a`.
- Ethernet: `--interface IFACE|all`, `--duration 1..300`. Сброс/переполнение счётчиков, новые ошибки/потери, half duplex и изменение линка дают WARN. PASS относится к наблюдаемым счётчикам, а не к работе прикладного протокола.
- Захват: `--interface IFACE|any`, `--duration 1..3600`, `--max-mb 1..128`, `--snaplen 64..65535`, `--count 1..1000000`, `--host IP`, `--port 1..65535` либо `--filter 'BPF'`. Свой BPF не совмещается с host/port и заменяет исходный фильтр, исключающий TCP-порт 22. Кольцевой PCAP хранит последний трафик и может превысить порог размера на один пакет. Нет подходящего трафика — WARN; неверный фильтр, сбой захвата или нечитаемый PCAP — FAIL. Требуется `tcpdump`; promiscuous mode не включается.

Сборщик ищет `Logs/*.txt`, `Logs/*.log` и такие же файлы в `Documents/Logs`. В архив входят только выбранные поля XML и сведения процесса/журнала загрузки: полные конфигурации, лицензии, содержимое проектов и БД не копируются. Выбор проекта в конфигурации не объявляется независимым подтверждением его работы. PCAP запускается отдельно и автоматически в архив не добавляется. Маскирование строк с реквизитами эвристическое: перед передачей логов и PCAP требуется просмотр. Бюджет ограничивает собранный текст, а не все рабочие файлы; для временного tar также нужно свободное место. `tar` и `gzip` вызываются отдельно для прошивок без `tar -z`.

Для работы после закрытия SSH-сеанса:

```sh
run_dir=$(mktemp -d /tmp/iridi-session.XXXXXX)
nohup sh collect_support_bundle.sh --duration 60 --output-dir "$run_dir" >"$run_dir/progress.log" 2>&1 </dev/null &
```

Путь к архиву выводится в конце. Скачайте именно этот файл; старые SSH-серверы HSS могут требовать legacy SCP:

```sh
scp -O root@HOST:/tmp/iridi-support-bundle.XXXXXX/support-bundle.tar.gz .
```

## Общее состояние и аудит сервера 360° (Server Health v2.2)

Комплексный диагностический скрипт для Linux-контроллеров iRidi (HS Server, ProAV, UMC, KNX Home Server).

```sh
cd /tmp
wget --no-check-certificate -O check_server_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_server_health.sh
sh check_server_health.sh
```

#### Дополнительные режимы:

```sh
# Экспорт сводного отчета в структурированный JSON:
sh check_server_health.sh --json
```

Идентификация прошивки включает `/timestamp` и отдельный `BUILD_ID` из `os-release`, если он доступен. Проверка RTC показывает модель микросхемы, сравнивает аппаратное время с системным UTC (допуск 60 секунд) и сообщает неизвестное состояние батареи, если драйвер не предоставляет её флаг. Совпадение часов не подтверждает сохранение времени без питания или точность относительно внешнего источника. Настройки часов не изменяются.

В режиме `--json` stdout содержит только объект сводки (`status`, `exit_code`, счётчики предупреждений/ошибок, идентификацию, прошивку, RTC и путь к логу); дашборд и технические сведения направляются в журнал аудита.

8 этапов комплексного аудита:
1. **[1/8] Идентификация оборудования**: серийный номер контроллера, серийный номер процессора, модель платы, версия ядра и ОС, аптайм и Load Average.
2. **[2/8] Периферия и аппаратные порты**: наличие портов RS-485 / UART, счетчики ошибок кадрирования и переполнения буфера (oe/fe/pe), аппаратные часы RTC (`/dev/rtc0`) и заряд батарейки, аппаратный Watchdog (`/dev/watchdog`), статус GPIO / сухих контактов.
3. **[3/8] Службы и рантайм iRidi**: редакция сервера (Bus77 Home, iRidi Pro, ProAV), статус процесса `iridium` (PID, RAM, потоки, открытые FD), детекция циклических перезапусков службы (`NRestarts`), статус MQTT-брокера (порт 1883) и активные сокеты.
4. **[4/8] Проекты, лицензии и базы данных**: аудит лицензии (`license.xml`, ServerID, лимиты панелей), список загруженных проектов (`.sirp` / `.rpz`), проверка целостности баз данных SQLite (`PRAGMA integrity_check;`, размер WAL-журналов), экспресс-сканирование последних логов сервера на фатальные сбои и JS-исключения.
5. **[5/8] Температуры и процессор**: термодатчики SoC/CPU в °C, топология ядер и частоты.
6. **[6/8] Оперативная память (RAM) и Swap**: общий объем, занято, свободно, доступно (в МБ и процентах), риск Out-Of-Memory.
7. **[7/8] Здоровье памяти eMMC (SMART)**: производитель чипа, износ SLC и MLC/TLC (LifeTime A/B), статус Pre-EOL, заполненность разделов (`/`, `/userdata`, `/oem`) и сканирование журнала ядра на ошибки ввода-вывода.
8. **[8/8] Сеть и коммуникации**: параметры интерфейсов Ethernet (`eth0`/`eth1`), скорость и дуплекс линка, статус CAN-контроллеров (`ERROR-ACTIVE` / `ERROR-PASSIVE` / `BUS-OFF`), пинг до шлюза по умолчанию и DNS-серверы.

---

## Диагностика портов RS-485 / Serial (`check_serial_ports.sh`)

Специализированный инструмент для диагностики последовательных интерфейсов и шины RS-485 на контроллерах iRidi:

```sh
cd /tmp
wget --no-check-certificate -O check_serial_ports.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_serial_ports.sh
sh check_serial_ports.sh
```

#### Дополнительные режимы и параметры:

```sh
# Проверка конкретного порта:
sh check_serial_ports.sh --port /dev/ttyS1

# Изменение длительности замера ошибок (в секундах, по умолчанию: 5):
sh check_serial_ports.sh --duration 10
```

- Автоматическое обнаружение всех физических портов UART (`/dev/ttyS*`, `/dev/ttyUSB*`, `/dev/ttyAMA*`, `/dev/ttymxc*`).
- Назначение RS-485, RS-232 и KNX определяется по `/oem/hal/*_port`. Симлинки разрешаются без чтения данных UART, дубли удаляются. Поддерживаются и обычные HAL-файлы с текстовым путём `/dev/...`.
- Проверка настроек и доступных счётчиков не подтверждает успешный обмен данными.
- Анализ аппаратных ошибок ядра: Framing Errors (`fe`), Buffer Overruns (`oe`), Parity Errors (`pe`), Breaks (`brk`).
- Проверка прав доступа, текущей скорости (Baudrate) и процессов, блокирующих порт (`fuser`).

---

## Диагностика памяти eMMC

Глубокая многоуровневая диагностика встроенного флеш-накопителя eMMC:

```sh
cd /tmp
wget --no-check-certificate -O check_emmc_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_emmc_health.sh
sh check_emmc_health.sh
```

- **Аппаратные SMART-метрики износа**: производитель (Samsung, SanDisk и др.), дата выпуска, `LIFE_TIME_ESTIMATION` (Type A/B с шагом 10%), статус `PRE_EOL_INFO`, регистры защиты от записи (`USER_WP`).
- **Параметры шины eMMC**: фактическая частота, ширина и режим из debugfs `ios` выбранного MMC-хоста; CID/CSD и сообщения загрузки MMC сохраняются в технический журнал. При недоступном debugfs скрипт не монтирует его. Отсутствующие или неподдерживаемые показатели износа не дают вердикт о нормальном состоянии памяти.
- **Состояние разделов и Inodes**: проверка монтирования (`rw`), свободного места и исчерпания дескрипторов файлов (`df -i`) для всех ключевых разделов (`/`, `/userdata`, `/oem`).
- **Анализ логов ошибок хранилища**: глубокий поиск ошибок ввода-вывода (`dmesg` и `/var/log/messages`).
- **Проверка целостности на нескольких разделах**: безопасная тестовая запись 1 МиБ со сбросом кэшей (`sync`), двойным чтением и сверкой CRC32 на разделах `/` и `/userdata`.
- **Бенчмарки скорости и задержки**:
  - *Линейная запись*: тест записи 10 МиБ с `conv=fsync` для измерения реальной скорости записи (в МБ/с).
  - *Прямое блочное чтение*: чтение 50 МиБ с блочного устройства (`iflag=direct`) без износа флеш-памяти.
  - *Задержка транзакций SQLite 4K*: серия из 20 синхронных транзакций по 4 КБ с `fdatasync`.

Для пассивного сбора информации без записи файлов:

```sh
sh check_emmc_health.sh --no-write
```

---

## Диагностика и мониторинг CAN / Bus77 на HSS и ProAV

Два специализированных инструмента для работы с шиной CAN и протоколом Bus77.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ИНСТРУМЕНТЫ ДЛЯ BUS77 / CAN                     │
├───────────────────────────────────┬────────────────────────────────────┤
│         check_can_bus.sh          │         monitor_can_bus.sh         │
│  (Диагностика и Инвентаризация)   │  (Расшифровщик и Монитор трафика)  │
├───────────────────────────────────┼────────────────────────────────────┤
│ • Статус контроллера (can0/can1)  │ • Декодирование пакетов Bus77      │
│ • Быстрый поиск устройств (Search)│ • Расшифровка команд и переменных  │
│ • Чтение моделей, серийников и ПО │ • Подстановка имен и типов модулей │
│ • 15-сек замер счетчиков ошибок   │ • Расчет нагрузки шины (Bus Load %)│
│ • Экспорт паспорта сети в JSON    │ • Топ отправителей (Top Talkers)   │
│ • Проверка состояния шлюза iRidi  │ • Замер отклика устройств (Ping RTT│
└───────────────────────────────────┴────────────────────────────────────┘
```

---

### 1. Инвентаризация устройств и состояние контроллера (`check_can_bus.sh`)

Скрипт проверяет состояние SocketCAN, отправляет безопасные read-only запросы System Search (`0x03`) и Device Info (`0x04`), формируя паспорт подключенных устройств.

```sh
cd /tmp
wget --no-check-certificate -O check_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_can_bus.sh
sh check_can_bus.sh
```

#### Дополнительные режимы `check_can_bus.sh`:

```sh
# Выбор конкретного интерфейса CAN (по умолчанию: all):
sh check_can_bus.sh --interface can0

# Мгновенный опрос устройств без ожидания 15-секундного замера трафика:
sh check_can_bus.sh --scan-only  # или --inventory

# Экспорт найденных устройств в структурированный JSON:
sh check_can_bus.sh --scan-only --json

# Пассивный режим без отправки кадров в шину:
sh check_can_bus.sh --passive
```

---

### 2. Расшифровщик протокола Bus77 и монитор живого трафика (`monitor_can_bus.sh`)

Автономный анализатор протокола Bus77 (версия 2.2). Превращает сырые 8-байтовые CAN-кадры в понятные сообщения автоматизации в реальном времени.

```sh
cd /tmp
wget --no-check-certificate -O monitor_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/monitor_can_bus.sh
sh monitor_can_bus.sh
```

#### Ключевые возможности расшифровщика:

1. **Автоматическая сборка мультифреймов**: соединяет составные пакеты протокола Bus77 (Start / Middle / End frames) и валидирует контрольную сумму CRC16.
2. **Декодирование команд в реальном времени**:
   - `SetVariable` (`0x05`) — изменение переменных, диммирование, включение реле, смена состояний.
   - `GetVariable` (`0x06`) — чтение текущих значений тегов/каналов.
   - `System Search` (`0x03`) и `Device Info` (`0x04`) — широковещательный опрос и паспорта устройств.
   - `SendEvent`, `Subscribe` / `Unsubscribe`.
3. **Подстановка имен модулей**: вместо абстрактных hex-адресов подставляет человекочитаемые названия (например, `B77-DIM-4CH`, `B77-REL-8CH`, `FS-V-M-IL-S-IR-BIC`).
4. **Детекция конфликтов адресов (LID Conflict Detection)**: мгновенно выявляет дублирование Logical ID между разными физическими модулями.
5. **Расчет нагрузки шины (Bus Load %)**: измеряет плотность потока в кадрах в секунду (FPS) и процент утилизации канала 125 кбит/с (с предупреждением при превышении 60%).
6. **Рейтинг Top Talkers**: итоговая таблица самых активных устройств в шине для быстрого поиска «спамящих» датчиков, дребезга контактов или бесконечных циклических сценариев.

#### Пример декодированного потока на экране:

```text
TIME     CAN   DIR  ОТПРАВИТЕЛЬ -> ПОЛУЧАТЕЛЬ          | КОМАНДА / СТАТУС     | ДЕТАЛИЗАЦИЯ
12:34:56 can0  TX   SERVER/GW(LID 70) -> ALL           | REQUEST SetVariable  | variable=316 value=32
12:34:56 can0  RX   LID 11 (B77-DIM-4CH) -> ALL        | REQUEST SetVariable  | variable=315 value=true
12:34:57 can0  RX   LID 03 (B77-SENSOR-T) -> SERVER    | RESPONSE GetVariable | tag=1 (Temperature) value=23.5°C
```

#### Дополнительные режимы и фильтры монитора:

```sh
# 1. Замер времени отклика устройства (Ping RTT в мс с расчетом потерь):
sh monitor_can_bus.sh --ping 2 --count 5

# 2. Фильтрация живого потока по конкретному модулю (LID):
sh monitor_can_bus.sh --lid 11 --duration 30

# 3. Фильтрация по типу команды (например, только изменения переменных SetVariable):
sh monitor_can_bus.sh --cmd SetVariable --duration 60

# 4. Отображение сырых HEX-байт CAN-кадра параллельно с расшифровкой:
sh monitor_can_bus.sh --raw --duration 15

# 5. Полностью пассивный мониторинг без предварительного опроса инвентаря:
sh monitor_can_bus.sh --passive --duration 60
```

Подробные примеры, разбор сообщений, сценарии поиска плавающих неполадок и руководство по анализу читайте в [Руководстве по мониторингу Bus77](BUS77_MONITORING_GUIDE_RU.md).

## Регрессионные проверки аппаратной диагностики

```sh
python3 -m unittest discover -s tests -v
```

Локальные фикстуры проверяют неизвестную/разряженную батарею RTC и сдвиг UTC, сведения о прошивке, HAL-симлинки и специальные файлы, выбор eMMC-хоста, экранирование JSON, CRC и типы значений Bus77. Время Bus77 декодируется по SDK с независимыми словами даты и времени, включая только дату или только время. Тип 13 остаётся зарезервированным/неподдерживаемым; 64-битные значения выводятся исходными байтами без потери точности. Top Talkers считает декодированные пакеты Bus77; частота CAN-кадров и оценка загрузки шины показаны отдельно. Конфликты LID и коллизии `var_id` — разные события; этот монитор не заявляет обнаружение коллизий `var_id`.

Для проверки на контроллере используйте `--no-write` у eMMC и `--passive` у CAN-монитора. PASS в режиме eMMC без записи относится только к выполненным проверкам; целостность записи и производительность остаются непроверенными.

Интеграционные фикстуры удалённых инструментов также проверяют завершение и прерывание процесса, ошибки/сброс счётчиков Ethernet, частичный и полный архив, tar без `-z`, маскирование реквизитов, обработку BPF, пустой захват и проверку PCAP.
