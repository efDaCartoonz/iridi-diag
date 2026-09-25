# Скрипты диагностики iRidi

Коллекция автономных инструментов для диагностики серверов, хранилища и облачного подключения iRidi. Скрипты для Linux написаны на переносимом POSIX `sh` и поддерживают прошивки HS Server на базе BusyBox. Скрипт для macOS поддерживает интерактивный запуск через Finder и CLI. Скрипты для Windows поддерживают встроенные версии Windows PowerShell в Windows 7, 10 и 11.

[English version](README.md) | [Руководство по мониторингу Bus77](BUS77_MONITORING_GUIDE_RU.md)

## Структура репозитория

- `scripts/linux` — Linux, Debian и прошивки на базе BusyBox;
- `scripts/macos` — macOS (интерактивный лаунчер и движок на POSIX sh);
- `scripts/windows` — Windows 7, Windows 10 и Windows 11.

### Windows

| Файл | Назначение |
| --- | --- |
| `run_iridi_cloud_windows.cmd` | Лаунчер для запуска двойным кликом с меню выбора продукта и автологированием |
| `check_iridi_cloud_windows_10_11.ps1` | Облачная диагностика для Windows 10/11 и Windows PowerShell 5.1 |
| `check_iridi_cloud_windows_7.ps1` | Облачная диагностика для Windows 7 и Windows PowerShell 2.0 или новее |

### macOS

| Файл | Назначение |
| --- | --- |
| `run_iridi_cloud_macos.command` | Лаунчер для запуска двойным кликом в Finder с меню выбора продукта и автологированием |
| `check_iridi_cloud_macos.sh` | Универсальный скрипт диагностики для macOS с поддержкой CLI-флагов и интерактивного режима |

### Linux и BusyBox

| Файл | Назначение |
| --- | --- |
| `check_i3knx.sh` | Проверка облачных ресурсов i3 KNX на прикладном уровне и сессии Cloud Gate |
| `check_bus77_home.sh` | Проверка облачных ресурсов Bus77 Home на прикладном уровне |
| `check_bus77_lite.sh` | Проверка облачных ресурсов Bus77 Lite на прикладном уровне |
| `check_iridi_pro_ru.sh` | Проверка iRidi Pro Cloud для региона RU |
| `check_iridi_pro_eu.sh` | Проверка iRidi Pro Cloud для региона EU |
| `check_iridi_pro_cn.sh` | Проверка iRidi Pro Cloud для региона CN |
| `check_emmc_health.sh` | Диагностика состояния eMMC, пути записи root, overlay и ошибок ядра |
| `check_can_bus.sh` | Инвентаризация устройств (HWID, модель, имя, прошивка/профиль) и состояние CAN-шины |
| `monitor_can_bus.sh` | Мониторинг сообщений Bus77 (отправитель -> получатель), команд, значений и сводка маршрутов |
| `scan_bus77_devices.sh` | Пассивный/активный опрос устройств Bus77 с выводом модели, HWID, прошивки и количества каналов |

## Цветовая индикация и коды возврата

В интерактивном выводе используются следующие цвета:

- зелёный — `[OK]` и `RESULT: PASS`;
- жёлтый — `[ATTENTION]` и `RESULT: WARN`;
- красный — `[NOT OK]` и `RESULT: FAIL`.

В Linux и macOS цвета включаются только при выводе в терминал. Для отключения установите переменную `NO_COLOR=1`. Файлы логов сохраняются в виде обычного текста без ANSI escape-последовательностей.

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

Лаунчер определит установленную версию Windows PowerShell, выберет совместимый движок диагностики, отобразит ход проверки и оставит окно открытым после завершения. Результаты каждого запуска сохраняются в папке `logs\` рядом со скриптами с указанием продукта, региона и времени в имени файла.

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

Параметр `-Quality` запускает расширенное тестирование задержек, потерь пакетов, MTU и скорости скачивания. В интерактивном меню запуска также предусмотрен запрос на включение расширенной проверки качества.

Версия для Windows 7 использует встроенный компонент WinHTTP и принудительно включает TLS 1.2. Если операционная система не поддерживает TLS 1.2, скрипт сообщит об ошибке подключения.

---

## Облачная диагностика на macOS

Скачайте оба файла в одну папку, затем дважды кликните по `run_iridi_cloud_macos.command` в Finder.

```sh
mkdir -p ~/Desktop/iridi-diag-macos && cd ~/Desktop/iridi-diag-macos
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/run_iridi_cloud_macos.command"
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/check_iridi_cloud_macos.sh"
chmod +x run_iridi_cloud_macos.command check_iridi_cloud_macos.sh
open .
```

В открывшемся окне Finder дважды кликните по `run_iridi_cloud_macos.command`.
Выберите нужный продукт: i3 KNX, Bus77 Home, Bus77 Lite или iRidi Pro (RU / EU / CN).

Скрипт также можно запустить напрямую из Терминала с параметром `--product`:

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

Параметр `--quality` (или `-q`) запускает расширенный тест задержек, джиттера, потерь пакетов, пропускной способности, стабильности Cloud Gate и MTU. В интерактивном меню также запрашивается подтверждение на запуск расширенной проверки.

Каждый запуск автоматически записывает файл лога в папку `logs/` рядом со скриптом с именем продукта и временной меткой.

---

## Облачная диагностика на Linux

Проверка облака — это не просто ping хоста или проверка открытого порта. Каждый скрипт выполняет DNS-резолвинг и реальный HTTP(S) GET-запрос, читает тело ответа (payload) и выводит реальный IP-адрес, документированный IP-адрес, HTTP-статус, Content-Type, размер payload, время запроса и количество попыток. При сетевых сбоях без HTTP-ответа выполняется до трёх повторных попыток. Ответ `403` от защищённого хранилища также подтверждает доступность ресурса на прикладном уровне.

В терминале отображается прогресс выполнения, а для каждого запуска создаётся отдельный файл лога. Пример имени файла:

```text
cloud_bus77_home_SERVER_20260901_153000_1234.log
```

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

Стандартный режим выполняет экспресс-проверку (15–20 секунд). Если требуется выявить периодические обрывы связи, скачки задержек или нестабильность туннелей, запустите скрипт с флагом `--quality` (или `--deep` / `-q`):

```sh
sh check_bus77_home.sh --quality
sh check_iridi_pro_ru.sh --quality
```

В расширенном режиме выполняются 4 дополнительных теста стабильности:
1. **Задержка, джиттер и потери пакетов**: 10 последовательных проб HTTP/HTTPS с замером min/avg/max задержки, джиттера, скорости DNS-резолвинга и процента потерь пакетов.
2. **Пропускная способность скачивания**: реальная передача тестовых данных из регионального CDN/хранилища продукта с расчетом скорости (в КБ/с или МБ/с).
3. **Серийная стабильность Cloud Gate (TCP Burst)**: 3 последовательных рукопожатия TCP для проверки устойчивости брокера соединений при повторных подключениях.
4. **Path MTU и фрагментация кадров**: отправка ICMP-пакетов стандартного размера 1500 байт и туннельного размера 1400 байт с флагом Don't-Fragment (DF) для обнаружения MTU black holes (автоматически пропускается, если провайдер фильтрует ICMP).

---

## Общее состояние и информация о сервере (Health & Info)

Комплексный диагностический скрипт для Linux-контроллеров iRidi (HS Server, ProAV, UMC, KNX Home Server). Собирает аппаратные серийные номера, установленную редакцию сервера и версию прошивки, активные сетевые порты, температуры датчиков SoC/GPU, использование памяти, индикаторы износа eMMC (SMART) и состояние сетевых интерфейсов.

Скачивание и запуск:

```sh
cd /tmp
wget --no-check-certificate -O check_server_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_server_health.sh
sh check_server_health.sh
```

Собираемые метрики:
- **Идентификация оборудования**: серийный номер контроллера (`/oem/hal/ccinfo` / devicetree), серийный номер процессора, модель платы, версия ядра и ОС Buildroot, аптайм и Load Average.
- **Служба и прошивка iRidi**: редакция сервера (Bus77 Home, iRidi Pro, ProAV), установленная версия пакета `opkg`, размер и дата бинарника, статус процесса (PID, RAM, потоки) и открытые порты (8888, 8443, 30464, 65534 и др.).
- **Температуры и процессор**: термодатчики SoC/CPU и GPU в °C, количество ядер и текущая частота.
- **Оперативная память (RAM)**: общий объем, занято, свободно, доступно (в МБ и процентах).
- **Здоровье памяти eMMC (SMART)**: модель чипа (Samsung / SanDisk), индикаторы ресурса Type A/B, статус Pre-EOL, заполненность разделов (`/`, `/userdata`, `/oem`) и проверка ошибок ввода-вывода в логах ядра.
- **Сеть и CAN**: параметры интерфейса Ethernet (`eth0`), IP/MAC, скорость линка, шлюз, DNS и статус CAN-контроллера (`ERROR-ACTIVE` / `ERROR-PASSIVE`).

---

## Диагностика eMMC

Скачайте и запустите диагностику от имени `root`:

```sh
cd /tmp
wget --no-check-certificate -O check_emmc_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_emmc_health.sh
sh check_emmc_health.sh
```

Скрипт выполняет глубокую многоуровневую диагностику встроенного флеш-накопителя eMMC, оптимизированную для серверов iRidi:
- **Аппаратные SMART-метрики износа**: модель чипа, производитель (Samsung, SanDisk и др.), дата выпуска, серийный номер, `LIFE_TIME_ESTIMATION` (износ SLC-кэша и основной области памяти Type A/B с шагом 10%), статус `PRE_EOL_INFO`, регистры защиты от записи (`USER_WP`) и флаги sysfs.
- **Состояние разделов и Inodes**: проверка монтирования (`rw`), свободного места и исчерпания дескрипторов файлов (`df -i`) для всех ключевых разделов (`/`, `/userdata`, `/oem`).
- **Анализ логов ошибок хранилища**: глубокий поиск ошибок ввода-вывода (I/O error, buffer I/O error, timeout, EXT4-fs error) как в оперативной памяти ядра (`dmesg`), так и в энергонезависимом системном журнале (`/var/log/messages`).
- **Проверка целостности на нескольких разделах**: безопасная тестовая запись 1 МиБ со сбросом кэшей (`sync`), двойным чтением и сверкой CRC32 на разделах `/` и `/userdata` (где хранятся база данных SQLite и системные логи iRidium Server).
- **Бенчмарки пропускной способности и задержки БД**:
  - *Линейная скорость записи*: тест записи 10 МиБ с обязательным сбросом буферов (`conv=fsync`) для измерения реальной скорости записи контроллера (в МБ/с).
  - *Прямое блочное чтение*: чтение 50 МиБ напрямую с блочного устройства (`iflag=direct`) для оценки скорости чтения без расхода ресурса флеш-памяти (0% износа).
  - *Задержка транзакций SQLite 4K*: серия из 20 синхронных транзакций по 4 КБ с `fdatasync`, симулирующая нагрузку базы данных сервера автоматизации.
- **Безопасность для ресурса памяти**: суммарный объем тестовой записи за весь запуск не превышает ~10.1 МБ (< 0.00006% ресурса накопителя), тесты автоматически пропускаются при нехватке места (< 100 МБ), а временные файлы немедленно удаляются.

Для пассивного сбора информации без создания тестовых файлов используйте режим только для чтения:

```sh
sh check_emmc_health.sh --no-write
```

Скрипт никогда не пишет напрямую в системные блоки разметки, не запускает опасный `fsck` на лету и не перемонтирует ФС. Каждый запуск формирует отдельный лог-файл:

```text
emmc_diagnostic_SERVER_20260901_153000_1234.log
```


---

## Диагностика CAN/Bus77 на HSS и ProAV

Два автономных инструмента: скачивайте только тот файл, который вам нужен.
Никаких дополнительных скриптов, установки пакетов или переконфигурации интерфейсов не требуется, если на сервере уже доступны `ip`, `candump`, `cansend` и BusyBox awk.

### Инвентаризация устройств и состояние шины

```sh
cd /tmp
wget --no-check-certificate -O check_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_can_bus.sh &&
sh check_can_bus.sh
```

Диагностический скрипт (версия 2.3) выполняет:
- **Инвентаризацию модулей Bus77**: находит все ответившие устройства, выводит их LID, полный HWID, модель, имя устройства, версию прошивки, номер профиля (Firmware ID) и число каналов/тегов.
- **Диагностику CAN-контроллера**: проверяет состояние (`ERROR-ACTIVE`), битрейт, ошибки ядра (`rx_errors`, `tx_errors`, `dropped`), статус шлюза `iRidium Server` и делает 15-секундный срез реального трафика на линии.

#### Дополнительные режимы `check_can_bus.sh`:

```sh
# Мгновенный опрос устройств без ожидания 15-секундного замера трафика:
sh check_can_bus.sh --scan-only

# Экспорт паспорта найденных устройств в JSON-формат:
sh check_can_bus.sh --scan-only --json

# Пассивный режим без активных запросов Search/DeviceInfo:
sh check_can_bus.sh --passive
```


### Кто, кому и что отправляет (Мониторинг, анализ нагрузки и Ping)

Подробные пояснения по полям, экспериментам с кнопками/нагрузками, примерам сообщений и ограничениям интерпретации читайте в [Руководстве по мониторингу Bus77](BUS77_MONITORING_GUIDE_RU.md).

```sh
cd /tmp
wget --no-check-certificate -O monitor_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/monitor_can_bus.sh &&
sh monitor_can_bus.sh
```

Монитор (версия 2.2) выполняет:
1. **Проверку конфликтов адресов (LID Conflict Detection)**: выявляет дублирование Logical ID между разными физическими модулями.
2. **Декодирование трафика в реальном времени**: собирает кадры CAN в пакеты Bus77 и расшифровывает команды, теги, каналы и переменные с подстановкой названий моделей.
3. **Расчет нагрузки шины (Bus Load %)**: замеряет средний FPS (кадров/с) и процент утилизации пропускной способности CAN-шины (с предупреждением при > 60%).
4. **Рейтинг активности устройств (Top Talkers)**: сводная таблица самых активных отправителей трафика для быстрого поиска «спамящих» датчиков или зацикленных сценариев.

```text
TIME     CAN   RX/TX  SENDER -> RECEIVER | REQUEST/RESPONSE COMMAND | DETAILS
12:34:56 can0  TX     SERVER/GW(LID 70) -> ALL (broadcast) | REQUEST SetVariable tid=none | variable=316 value=32
12:34:56 can0  RX     LID 11 FS-V-M-IL-S-IR-BIC [C6AF] -> ALL (broadcast) | REQUEST SetVariable tid=none | variable=315 value=true
```

### Дополнительные режимы монитора:

```sh
# 1. Проверка отклика и задержки конкретного устройства (Ping RTT в мс):
sh monitor_can_bus.sh --ping 2 --count 5

# 2. Фильтрация живого потока по номеру устройства (LID):
sh monitor_can_bus.sh --lid 11 --duration 30

# 3. Фильтрация по типу команды (например, только изменения переменных):
sh monitor_can_bus.sh --cmd SetVariable --duration 60

# 4. Отображение сырых CAN-кадров параллельно с декодированными пакетами:
sh monitor_can_bus.sh --raw --duration 15

# 5. Пассивный режим без активных запросов инвентаризации:
sh monitor_can_bus.sh --passive --duration 60
```


Оба инструмента по умолчанию используют все обнаруженные интерфейсы SocketCAN. Параметр `--duration` задаёт время наблюдения, а не поиска. `--passive` отключает все исходящие диагностические запросы (идентификация устройств и профили считываться не будут).

По умолчанию обнаружение отправляет только один запрос System Search и один Device Info на каждый найденный LID. Скрипт никогда не меняет адреса, каналы, прошивки или настройки CAN. В список попадают только ответившие устройства. Не запускайте несколько диагностик или сканеров одновременно: обнаружение использует CAN ID `0xFFFE` и LID `254`, и скрипт завершит работу, если этот идентификатор будет замечен в начальной выборке трафика. Скрытые конфликты адресов не исключены.

Скрипт `scan_bus77_devices.sh` сохранён как опциональный инструмент только для инвентаризации для обратной совместимости; ни один из основных инструментов не требует его наличия.
Справка по протоколу: [официальный BUS77 SDK](https://github.com/iRidium-Mobile/BUS77-SDK).
