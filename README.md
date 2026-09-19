# Adobe Environment Toolkit

Кроссплатформенный набор сценариев для управления Adobe-средой на macOS и Windows:

- создать резервную копию пользовательских настроек, рабочих пространств и сторонних расширений;
- безопасно восстановить такую копию;
- остановить процессы Adobe и посмотреть план очистки;
- при явном подтверждении удалить остаточные файлы Adobe.

## Важно

Сначала создайте резервную копию. Полная очистка необратимо удаляет пути из
[`shared/cleaner-manifest.json`](shared/cleaner-manifest.json). Начинайте с
предпросмотра (`dry run`) и используйте полную очистку только на своей машине.

Для удаления приложений Adobe сначала предпочтительны штатные деинсталляторы
или официальный Adobe Creative Cloud Cleaner Tool. Этот репозиторий **не**
содержит и не распространяет приложение или DMG Adobe.

## Быстрый старт

### macOS

Дважды кликните `run-macos.command` и выберите действие.

Из Terminal:

```bash
./run-macos.command backup
./run-macos.command clean

# Всегда сначала проверьте список действий очистки
./macos/clean/AdobeCleaner.command --dry-run full
./macos/clean/AdobeCleaner.command kill

# Проверить и при необходимости исправить только устаревшие записи интерфейса
./macos/clean/AdobeCleaner.command diagnose
./macos/clean/AdobeCleaner.command --dry-run repair-ui
./macos/clean/AdobeCleaner.command repair-ui
```

Полная очистка запрашивает фразу `YES DELETE ADOBE` и права администратора для
системных путей. После удаления она также снимает устаревшие регистрации
удалённых Adobe-приложений из Launch Services: запись обрабатывается, только
если bundle отсутствует на диске и её Adobe-идентичность подтверждена bundle ID
или canonical ID. Поэтому учитываются и старые регистрации с внешних томов,
домашней директории или архивных папок, а живые приложения не снимаются лишь по
названию.

Cleaner также может сверить базу Launchpad текущего пользователя. Перед первой
записью создаётся и проверяется резервная копия этой базы с меткой времени; затем в одной SQLite
транзакции удаляются только подтверждённые orphan-записи. Adobe bundle ID
удаляется лишь при отсутствии живой регистрации. Не-Adobe запись удаляется лишь
если cleaner записал соответствующий bundle до его собственного удаления; в
остальных случаях она остаётся диагностической находкой. База Launchpad целиком
не сбрасывается: папки, порядок, страницы и несвязанные приложения сохраняются.
Dock перезапускается только после релевантного изменения.

`diagnose` ничего не меняет и показывает регистрации и записи, которые были бы
обработаны или намеренно сохранены. `--dry-run full` и `--dry-run repair-ui`
также не меняют Launch Services или Launchpad и показывают план, путь будущей
резервной копии и решение о перезапуске Dock. Если `lsregister`, `sqlite3`, база
Launchpad или ожидаемая схема недоступны, очистка не прерывается: сверка UI
пропускается с сообщением в логе. Поддерживается только схема, которую cleaner
сначала успешно проверяет; будущие версии macOS не предполагаются совместимыми
без такой проверки.

### Windows

Запустите `run-windows.cmd` и выберите действие, либо передайте команду:

```cmd
run-windows.cmd backup
run-windows.cmd restore "C:\path\to\backup"
run-windows.cmd clean
run-windows.cmd clean-preview
run-windows.cmd clean-full
```

`clean` только останавливает процессы и службы. `clean-preview` ничего не
удаляет. Для `clean-full` нужен запуск от имени администратора и подтверждение
в PowerShell.

## Резервное копирование и восстановление

Модуль backup сохраняет настройки Adobe, рабочие пространства, пользовательские
пресеты, сторонние плагины, ScriptUI Panels и CEP-расширения на macOS и Windows.
Он исключает кэши, логи и штатные компоненты Adobe, где это возможно.

Прямые точки запуска сохраняются:

- macOS: `macos/AdobeBackuper.command`;
- Windows: `windows/run-backup.cmd` и `windows/run-restore.cmd`.

Восстановление по умолчанию безопасное и не удаляет дополнительные файлы.

## Очистка

Сценарии очистки используют единый манифест
[`shared/cleaner-manifest.json`](shared/cleaner-manifest.json). В нём описаны
процессы, службы и пути для macOS и Windows. Изменяйте его осознанно: полная
очистка следует этому списку.

## Структура

```text
Adobe Environment Toolkit/
├── run-macos.command
├── run-windows.cmd
├── macos/
│   ├── AdobeBackuper.command
│   └── clean/
├── windows/
│   ├── adobe-backup.ps1
│   ├── run-backup.cmd
│   ├── run-restore.cmd
│   └── clean/
└── shared/
    └── cleaner-manifest.json
```

## Лицензия

MIT, см. [LICENSE](LICENSE).
