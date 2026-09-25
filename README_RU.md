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
| `check_server_health.sh` | Общая сводка о сервере (v1.1): серийники, редакция и версия прошивки, порты, температуры, RAM и SMART |
| `check_i3knx.sh` | Проверка облачных ресурсов i3 KNX на прикладном уровне и сессии Cloud Gate (v1.5) |
| `check_bus77_home.sh` | Проверка облачных ресурсов Bus77 Home на прикладном уровне (v1.5) |
| `check_bus77_lite.sh` | Проверка облачных ресурсов Bus77 Lite на прикладном уровне (v1.5) |
| `check_iridi_pro_ru.sh` | Проверка iRidi Pro Cloud для региона RU (v1.5) |
| `check_iridi_pro_eu.sh` | Проверка iRidi Pro Cloud для региона EU (v1.5) |
| `check_iridi_pro_cn.sh` | Проверка iRidi Pro Cloud для региона CN (v1.5) |
| `check_emmc_health.sh` | Диагностика eMMC (v2.1): SMART, разделы, inodes, бенчмарки скорости и 4K задержки БД |
| `check_can_bus.sh` | Диагностика CAN/Bus77 (v2.3): здоровье контроллера, инвентаризация (`--scan-only`), экспорт JSON |
| `monitor_can_bus.sh` | **Расшифровщик и монитор Bus77 (v2.2)**: живое декодирование команд/переменных, Bus Load %, Top Talkers, Ping RTT |

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

## Общее состояние и информация о сервере (Server Health)

Комплексный диагностический скрипт для Linux-контроллеров iRidi (HS Server, ProAV, UMC, KNX Home Server).

```sh
cd /tmp
wget --no-check-certificate -O check_server_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_server_health.sh
sh check_server_health.sh
```

Собираемые метрики:
- **Идентификация оборудования**: серийный номер контроллера, серийный номер процессора, модель платы, версия ядра и ОС, аптайм и Load Average.
- **Служба и прошивка iRidi**: редакция сервера (Bus77 Home, iRidi Pro, ProAV), установленная версия пакета `opkg`, статус процесса (PID, RAM, потоки) и открытые порты (8888, 8443, 30464, 65534 и др.).
- **Температуры и процессор**: термодатчики SoC/CPU в °C, количество ядер и частота.
- **Оперативная память (RAM)**: общий объем, занято, свободно, доступно (в МБ и процентах).
- **Здоровье памяти eMMC (SMART)**: модель чипа, износ SLC и MLC/TLC, статус Pre-EOL, заполненность разделов (`/`, `/userdata`, `/oem`) и сканирование журнала ядра на ошибки ввода-вывода.
- **Сеть и CAN**: параметры интерфейса Ethernet (`eth0`), IP/MAC, скорость линка, шлюз, DNS и статус CAN-контроллера (`ERROR-ACTIVE` / `ERROR-PASSIVE`).

---

## Диагностика памяти eMMC

Глубокая многоуровневая диагностика встроенного флеш-накопителя eMMC:

```sh
cd /tmp
wget --no-check-certificate -O check_emmc_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_emmc_health.sh
sh check_emmc_health.sh
```

- **Аппаратные SMART-метрики износа**: производитель (Samsung, SanDisk и др.), дата выпуска, `LIFE_TIME_ESTIMATION` (Type A/B с шагом 10%), статус `PRE_EOL_INFO`, регистры защиты от записи (`USER_WP`).
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
# Мгновенный опрос устройств без ожидания 15-секундного замера трафика:
sh check_can_bus.sh --scan-only

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
