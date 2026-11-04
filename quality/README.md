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
