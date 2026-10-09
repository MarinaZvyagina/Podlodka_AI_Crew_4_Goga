# architecture-agent-benchmark

Полный рабочий репозиторий исследования: протокол, 10 репозиториев-кандидатов, 40 задач с
валидаторами, 800+ реальных прогонов AI-агента и все расширения. Если вы попали сюда из доклада
и хотите понять суть за 2 минуты — смотрите [корневой README](../README.md). Этот файл —
навигация по самой структуре эксперимента для тех, кто хочет разобраться детально или повторить
эксперимент.

## С чего читать

1. **[`STATUS.md`](STATUS.md)** — живой журнал состояния эксперимента, самый актуальный документ
   в репозитории. Если какой-то другой файл противоречит `STATUS.md` по датам/числам — прав
   `STATUS.md`, он обновляется после каждого шага.
2. **[`EXPERIMENT_SUMMARY.ru.md`](EXPERIMENT_SUMMARY.ru.md)** / **[`.md`](EXPERIMENT_SUMMARY.md)**
   — повествовательный обзор всего исследования (написан в процессе расширенного этапа, числа по
   B″/C там устарели относительно `STATUS.md` — это нормально, зафиксировано как снэпшот).
3. **[`REPOSITORIES_AND_TASKS.md`](REPOSITORIES_AND_TASKS.md)** — человеческое описание всех 10
   репозиториев и всех 40 задач (что именно просили сделать агента), без обращения к скрытым
   эталонам.
4. **[`report/final_report.ru.md`](report/final_report.ru.md)** / **[`.md`](report/final_report.md)**
   — формальный финальный отчёт по первичному исследованию (Phase 14): вопрос исследования,
   методология, результаты, статистическая значимость, угрозы валидности.

## Протокол и дизайн эксперимента

| Файл | Что внутри |
|---|---|
| [`Research.md`](../Research.md) (в корне репозитория) | Исходный исследовательский журнал — как рождался дизайн эксперимента, вопрос за вопросом |
| [`GOGA_RESEARCH.md`](GOGA_RESEARCH.md) | Что такое Goga и её cell/CODEMANIFEST модель — необходимый контекст перед остальными документами |
| [`TREATMENT_DESIGN.md`](TREATMENT_DESIGN.md) | Дизайн первичного эксперимента (Condition A vs B) |
| [`TREATMENT_DESIGN_EXPERIMENT_B.md`](TREATMENT_DESIGN_EXPERIMENT_B.md) | Дизайн расширенных условий (B′, B″, C) |
| [`REPOSITORY_SELECTION.md`](REPOSITORY_SELECTION.md) | Критерии и процесс отбора 10 репозиториев |
| [`PROTOCOL.md`](PROTOCOL.md) | Замороженный протокол (`benchmark-v1`) — все 20+ разделов методологии, метрик, угроз валидности, поправок |
| [`repos.yaml`](repos.yaml) | Машиночитаемый профиль всех 10 репозиториев (язык, LOC, коммит, команды сборки/тестов) |
| [`experiment.yaml`](experiment.yaml) | Параметры прогона: модель, таймауты, бюджет, права, сид |

## Задачи и валидаторы

`tasks/R01` … `tasks/R10` — по 4 задачи на репозиторий:

- `task_[A-D].md` — реальный промпт, который получал агент.
- `metadata_[A-D].yaml` — скрытый эталон: правильное решение, критерии оценки, описание ловушки
  (для 40/40 задач; опубликован для воспроизводимости — если планируете прогонять эти же задачи
  заново вслепую, не открывайте эти файлы раньше времени).
- `validators/` — функциональные и архитектурные (≥3 на задачу) проверочные скрипты.
- `controls/` + `CONTROL_RESULTS.md` — позитивный/негативный контроль, подтверждающий, что
  валидаторы реально различают правильное решение от ловушки.
- `RECON_NOTES.md` — разведка реальной архитектуры репозитория до дизайна задач.

## Условия (conditions)

| Условие | Что получает агент | Где результаты |
|---|---|---|
| **A — Baseline** | репозиторий как есть, ничего не добавлено | `results/analysis_set.csv`, `results/cells.csv` |
| **B — Goga** | + замороженный лес `CODEMANIFEST` (92 файла, 9 524 строки) | `results/analysis_set.csv`, `results/cells.csv` |
| **B′ — Full Workflow** | + живой CLI `goga`/скиллы, использование опционально | `runs_experiment_b/`, `results/runs_experiment_b.csv` |
| **B″ — Forced Workflow** | то же, но использование явно предписано промптом | `runs_experiment_b2/`, `results/runs_experiment_b2.csv` |
| **C — Native Architecture** | репозиторий реально реструктурирован под cell-модель | `architecture_v2/`, `runs_experiment_c/`, `results/runs_experiment_c.csv` |
| **D — Interactive Pipeline** | человек в контуре, настоящий `development.yml` пайплайн Goga, n=1 на задачу | `results/CONDITION_D_INTERACTIVE_PIPELINE.md` |

`architecture/` — замороженный лес CODEMANIFEST для условия B (Phase 8).
`architecture_v2/` — реальная реструктуризация кода для условия C, по репозиторию: `RESTRUCTURE_REPORT.md` + `CYCLE_FIXES.md`.

## Результаты и анализ

| Файл | Что внутри |
|---|---|
| [`results/analysis_set.csv`](results/analysis_set.csv), [`results/cells.csv`](results/cells.csv) | Замороженные данные первичных 800 прогонов (сырые + агрегированные по cell) |
| [`results/PHASE13_STATISTICAL_ANALYSIS.md`](results/PHASE13_STATISTICAL_ANALYSIS.md) | Формальная проверка значимости первичного результата (Wilcoxon, GEE, bootstrap CI) |
| [`results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md`](results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md) | То же для условий B″ и C против Baseline |
| [`results/CONDITION_D_INTERACTIVE_PIPELINE.md`](results/CONDITION_D_INTERACTIVE_PIPELINE.md) | Качественный разбор всех 28 задач Condition D по стадиям пайплайна |
| [`results/VALIDATION_REPORT.md`](results/VALIDATION_REPORT.md), [`results/METRICS_COVERAGE.md`](results/METRICS_COVERAGE.md) | Проверка целостности данных, покрытие метрик |
| `runs/`, `runs_experiment_b/`, `runs_experiment_b2/`, `runs_experiment_c/` | Полные сырые артефакты каждого прогона: `agent.log`, `git.diff`, `metrics.json`, `functional_results.json`, `architecture_results.json` |

## Как повторить эксперимент

1. `repos.yaml` фиксирует точный коммит каждого из 10 репозиториев — склонировать их отдельно
   (это не часть данного репозитория, только метаданные).
2. `experiment.yaml` + `PROTOCOL.md` §10 описывают clean-room запуск: изолированный git worktree
   на прогон, фиксированная модель/таймаут/бюджет.
3. `scripts/execute_run.py` (+ `run_batch*.sh`, `run_batch_for_repos.sh` для параллельного запуска
   по непересекающимся наборам репозиториев) — реальный харнесс, которым выполнялись все прогоны.
4. `tasks/R0X/validators/*.sh` — функциональные и архитектурные проверки, которые скорят любой
   полученный diff.
5. `scripts/statistical_analysis.py` — воспроизводит все числа из `PHASE13_STATISTICAL_ANALYSIS.md`
   детерминированно (фиксированный `numpy.random.seed(42)`) из `results/analysis_set.csv` и
   `results/cells.csv`.

## Дисклеймеры, которые стоит знать перед чтением результатов

- Первичная метрика (**Dangerous Success Rate** = функционально работает, но архитектурно
  неверно) — композитная; её "плоский" результат может прятать значимые противоположно
  направленные сдвиги в компонентах (см. `results/PHASE13_STATISTICAL_ANALYSIS.md` §5).
- Условия B′/B″/C/D **никогда не объединяются** с первичным результатом A vs B — это отдельные,
  более смешанные эксперименты (`TREATMENT_DESIGN_EXPERIMENT_B.md` §3).
- R08 (Signal-Android) и R10 (Signal-iOS) принадлежат одной организации и лицензии — известная,
  раскрытая угроза валидности, не устранялась.
- Полный список раскрытых инцидентов (потеря данных при реструктуризации, нехватка диска,
  контаминация промежуточного контекста) и как они были устранены — в `STATUS.md`.
