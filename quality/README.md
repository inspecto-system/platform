# Общие конфигурации качества кода

Канонические конфигурации линтеров для всех репозиториев (CODE_QUALITY.md §3).

| Каталог | Используется в | Как применяется |
|---|---|---|
| `go/.golangci.yml` | media-service, report-service | Копия в корне репозитория; CI (`go.yml`) падает при расхождении с этим файлом |

Конфигурации Checkstyle, PMD и SpotBugs живут в `core-service` (единственный Java-репозиторий), правила ktlint и detekt — в `android`, ESLint и Prettier — в `web`, ruff и mypy — в `ml`: у каждого языка один репозиторий-владелец, поэтому копий нет.

## Переиспользуемые CI-workflow

| Workflow | Назначение | Подключение |
|---|---|---|
| `.github/workflows/java-gradle.yml` | Сборка, Spotless, Checkstyle, PMD, SpotBugs, тесты, JaCoCo | `uses: inspecto-system/platform/.github/workflows/java-gradle.yml@main` |
| `.github/workflows/go.yml` | golangci-lint, сборка, тесты с `-race`, порог покрытия, govulncheck | `uses: inspecto-system/platform/.github/workflows/go.yml@main` |
| `.github/workflows/security.yml` | Gitleaks, Dependency Review, CodeQL | `uses: inspecto-system/platform/.github/workflows/security.yml@main` |

Workflow для Android, Web и Python добавляются вместе с каркасами этих компонентов (T-304, T-501, T-601).

Вызывающий workflow должен выдать права не меньше тех, что запрашивает переиспользуемый: `contents: write` для `java-gradle.yml` (отправка графа зависимостей), `security-events: write` для `security.yml` (CodeQL), иначе запуск завершается ошибкой `startup_failure`.

Каждый вызывающий workflow задаёт `concurrency` с `cancel-in-progress: true`: новый коммит в ветку отменяет устаревшие запуски и не занимает очередь GitHub Actions. CodeQL — самая долгая проверка — запускается при слиянии в `main` и еженедельно, а не на каждый коммит PR; Gitleaks и Dependency Review выполняются на каждом PR.
