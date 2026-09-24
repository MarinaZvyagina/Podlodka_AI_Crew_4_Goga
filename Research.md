# Research benchmark: 800 AI-agent runs — what happens to architecture in large codebases

Ты выступаешь как research engineer.

Твоя задача — спроектировать, автоматизировать, провести и проанализировать воспроизводимый инженерный эксперимент по работе AI coding agents с архитектурой больших существующих кодовых баз.

Эксперимент готовится как основа для публичного технического доклада на HighLoad. Поэтому приоритеты:

1. воспроизводимость;
2. отсутствие cherry-picking;
3. заранее зафиксированные критерии оценки;
4. сохранение raw data;
5. возможность получить отрицательный результат;
6. отделение функциональной корректности от архитектурной;
7. количественные результаты вместо субъективной оценки.

Не пытайся доказать эффективность Goga.

Исследуй её.

---

# 1. Goga

В эксперименте используется open-source проект:

**GitHub repository: `qarium/goga`**

Перед проектированием Goga-condition обязательно:

1. открой repository `qarium/goga`;
2. прочитай текущий README;
3. изучи документацию;
4. изучи CODEMANIFEST;
5. изучи SDD workflow;
6. изучи pipelines;
7. изучи integration с Claude Code;
8. изучи работу Goga с существующими brownfield repositories;
9. изучи команды генерации/синхронизации архитектуры;
10. зафиксируй используемую версию Goga и git commit.

Не полагайся на описание Goga из этого prompt как на источник истины.

**Source of truth — repository и документация Goga на момент начала эксперимента.**

После исследования создай:

`GOGA_RESEARCH.md`

В нём опиши:

- что такое Goga;
- какие механизмы Goga релевантны эксперименту;
- что такое CODEMANIFEST;
- как Goga представляет architecture/contracts;
- какие данные получает coding agent;
- какие команды будут использоваться;
- какие дополнительные skills/prompts/tools получает agent;
- какие языки поддерживаются используемой версией;
- насколько Goga применима к existing repositories;
- какие ограничения обнаружены.

---

# 2. Сначала определить treatment

Это критически важно.

Нельзя просто назвать один запуск:

`baseline`

а второй:

`goga`

пока не определено, **в чём именно экспериментальное различие**.

Создай:

`TREATMENT_DESIGN.md`

И ответь на вопрос:

> Какую именно гипотезу позволяет проверить выбранная конфигурация?

Есть принципиальная разница между:

### Experiment A

Claude Code vs Claude Code + machine-readable architecture.

и:

### Experiment B

Claude Code vs полный Goga SDD workflow.

Во втором случае одновременно меняются:

- prompts;
- workflow;
- stages;
- skills;
- architecture representation;
- planning process;
- validation process.

Поэтому нельзя будет утверждать:

> machine-readable architecture вызвала улучшение.

Можно будет утверждать только:

> Goga-based workflow показал другой результат.

Поэтому постарайся максимально изолировать переменную, связанную именно с архитектурой.

Если текущая архитектура Goga технически не позволяет этого сделать, не имитируй несуществующий режим.

Зафиксируй реальный experimental treatment и соответствующим образом сузь формулировку исследовательской гипотезы.

---

# 3. Главный исследовательский вопрос

Базовая гипотеза:

> Помогает ли структурированное представление архитектуры существующего проекта AI coding agent принимать более архитектурно корректные и более стабильные решения по сравнению с обычной работой агента с исходным repository и его документацией?

Нас интересуют два разных эффекта.

## Effect 1 — Quality

Становится ли решение архитектурно корректнее?

## Effect 2 — Stability

Становится ли результат менее случайным между повторными запусками одной и той же задачи?

Именно поэтому каждую экспериментальную конфигурацию нужно выполнить **10 раз**.

---

# 4. Размер эксперимента

Используем:

**10 repositories**

×

**4 tasks**

×

**2 conditions**

×

**10 independent repetitions**

=

# 800 agent runs

Структура:

```text
10 repositories
    ↓
4 tasks per repository
    ↓
40 unique engineering tasks
    ↓
Baseline + Goga
    ↓
80 experimental cells
    ↓
10 independent repetitions
    ↓
800 total agent runs
```

---

# 5. Experimental cell

Experimental cell — это комбинация:

```text
repository
+
task
+
condition
```

Например:

```text
Kubernetes
+
Task 3
+
Baseline
```

Эта cell выполняется 10 раз.

Например:

```text
R01-T03-B-R01
R01-T03-B-R02
...
R01-T03-B-R10
```

И аналогично:

```text
R01-T03-G-R01
...
R01-T03-G-R10
```

---

# 6. Очень важное правило статистики

Не считать 800 runs как 800 полностью независимых задач.

Это nested experiment.

Есть:

```text
Repository
    ↓
Task
    ↓
Condition
    ↓
Repetition
```

Главная единица предметного сравнения:

**40 unique tasks.**

Для каждой задачи есть:

```text
10 Baseline observations
vs
10 Goga observations
```

Повторы используются для оценки:

- вероятности успеха;
- variance;
- stability;
- consistency.

Не используй pseudoreplication, чтобы искусственно получить маленький p-value.

При статистическом анализе:

- либо агрегируй repetitions на task level;
- либо используй корректную hierarchical / mixed-effects model;
- либо оба подхода.

Документируй выбранный метод.

---

# 7. Что означает «воспроизводимость»

Внутри эксперимента мы прежде всего измеряем:

**run-to-run repeatability / stability under nominally identical conditions.**

Это означает:

> Если дать одному и тому же AI-agent одну и ту же задачу в одном и том же repository десять раз, насколько одинаковые архитектурные решения он принимает?

Отдельно не путай это с более широким понятием scientific reproducibility:

> может ли другой исследователь воспроизвести benchmark.

Benchmark должен обеспечивать и второе, но десять повторов прежде всего измеряют первое.

---

# 8. Conditions

## Condition A — Baseline

Agent получает всё, что реально находится в исходном repository:

- source code;
- README;
- CONTRIBUTING;
- architecture docs;
- ADR;
- AGENTS.md;
- CLAUDE.md;
- repository rules;
- comments;
- tests;
- module documentation.

Ничего из существующей документации удалять нельзя.

Agent должен работать с максимально реалистичным repository.

---

## Condition B — Goga

Agent получает тот же:

- repository;
- git commit;
- task;
- model;
- environment;
- permissions;
- test suite.

Плюс получает ровно тот treatment, который был формально определён после исследования Goga.

Все дополнительные материалы Goga должны быть перечислены.

Например:

```text
CODEMANIFEST
Goga skills
architecture contracts
pipeline stages
generated artifacts
```

Но не предполагай заранее, что именно будет использоваться.

Сначала изучи актуальный Goga.

---

# 9. Что должно быть одинаковым

Между Baseline и Goga необходимо максимально зафиксировать:

```text
repository commit
task prompt
model
model version
Claude Code version
system prompt
tool permissions
timeout
machine
dependency state
network policy
working directory structure
test environment
```

Различаться должен только experimental treatment.

---

# 10. Model drift

800 запусков могут выполняться достаточно долго.

Поэтому есть риск, что provider обновит модель во время эксперимента.

Для каждого run обязательно сохраняй:

```text
requested_model
actual_model
model_identifier
Claude Code version
timestamp
```

Если возможно использовать pinned model version — используй её.

Если actual model version изменился во время benchmark:

1. зафиксируй это;
2. не смешивай результаты незаметно;
3. оцени влияние;
4. при необходимости сформируй отдельную experimental batch.

---

# 11. Выбор repositories

Выбери 10 реальных production-grade open-source repositories.

Критерии должны быть определены **до выбора финальной десятки**.

Создай:

`REPOSITORY_SELECTION.md`

---

# 12. Минимальные требования к repository

Предпочтительно:

- минимум 30k LOC non-generated production code;
- сотни source files;
- несколько архитектурных компонентов;
- automated tests;
- возможность local build;
- отсутствие обязательной proprietary infrastructure;
- активно используемый настоящий проект;
- достаточно зрелая architecture;
- поддерживаемый выбранным Goga treatment язык.

Не выбирай repository только потому, что Goga хорошо его понимает.

---

# 13. Разнообразие

Постарайся получить вариативность:

### Size

- medium;
- large;
- very large.

### Architecture

Например:

- layered;
- modular monolith;
- plugin architecture;
- ports and adapters;
- component architecture;
- package-oriented;
- mixed/evolutionary.

### Documentation

- good;
- medium;
- poor.

### Modularity

- strong;
- medium;
- weak.

---

# 14. repos.yaml

Для каждого repository сохранить:

```yaml
id:
name:
repository:
commit:

language:
build_command:
test_command:

production_loc:
source_files:
modules:

architecture_style:
architecture_documentation_quality:
modularity:

existing_agent_instructions:
  claude_md:
  agents_md:
  other:

reason_for_selection:

goga_compatibility:
```

---

# 15. Нельзя выбирать задачи через Goga

Чтобы избежать bias:

сначала выполняется:

```text
repository selection
↓
repository reconnaissance
↓
task design
↓
ground truth
↓
validators
↓
protocol freeze
```

и только потом:

```text
Goga architecture preparation
```

Goga output нельзя использовать для поиска «удобных» benchmark tasks.

---

# 16. Четыре задачи на repository

Каждый repository получает одинаковые четыре класса задач.

## Task A — Local Change

Ограниченное изменение.

Например:

- config option;
- validation;
- небольшой handler;
- дополнительный parameter;
- расширение существующего component.

Цель:

baseline для относительно простой задачи.

---

# 17. Task B — Cross-module Feature

Feature должна затрагивать несколько архитектурных компонентов.

Например:

```text
API
↓
Application
↓
Domain
↓
Storage
```

Правильная реализация должна требовать понимания существующего flow.

Минимум два architectural boundaries.

Предпочтительно три или больше.

---

# 18. Task C — Existing Extension Point

В repository уже существует предназначенный для расширения механизм:

```text
interface
protocol
plugin
provider
registry
factory
strategy
adapter
middleware
repository abstraction
handler registration
```

Task prompt не должен называть этот extension point.

Agent должен найти его самостоятельно.

Мы проверяем:

> обнаружит ли agent существующий способ расширения системы или построит параллельный механизм.

---

# 19. Task D — Architecture Trap

Самый важный тип задачи.

Нужно подобрать feature, у которой:

### есть очевидное простое решение,

которое:

- компилируется;
- может пройти feature tests;
- но нарушает architecture;

и:

### есть архитектурно корректное решение,

для которого agent должен понять существующие boundaries.

Например:

```text
Controller
↓
Service
↓
Repository
↓
Storage
```

Task:

```text
Добавить cache.
```

Неправильное:

```text
Controller → Cache
```

Правильное:

```text
Controller
↓
Service
↓
Repository/cache abstraction
```

---

# 20. Functional correctness != architecture correctness

Это центральная идея benchmark.

Обязательно отдельно измерять:

## Functional Success

и:

## Architecture Conformance

Нас особенно интересует состояние:

```text
Feature works
Tests pass
Architecture violated
```

---

# 21. Dangerous Success

Введи основную метрику:

# Dangerous Success

```text
Functional Success = true
AND
Full Architecture Conformance = false
```

Посчитать:

# Dangerous Success Rate

отдельно для:

- Baseline;
- Goga;
- каждого task type;
- каждого repository;
- каждой complexity group.

Это одна из центральных метрик исследования.

---

# 22. Task prompt

Task prompt должен выглядеть как реальная инженерная задача.

Плохо:

```text
Используй PaymentRepository,
измени PaymentService,
создай CachedPaymentRepository.
```

Так мы сами раскрываем architecture.

Хорошо:

```text
Добавьте кеширование результатов поиска для повторных запросов с одинаковыми параметрами. Кеш должен инвалидироваться после изменения данных, влияющих на результат поиска.
```

Agent самостоятельно решает:

- куда внести изменение;
- какие modules использовать;
- какие abstractions найти;
- какие dependencies добавить.

Baseline и Goga получают абсолютно одинаковый task text.

---

# 23. Ground truth

До запусков для каждой задачи создать:

`metadata.yaml`

Например:

```yaml
task_id:
repository:
category:

functional_requirements:

architectural_constraints:

required_existing_abstractions:

allowed_dependencies:

forbidden_dependencies:

expected_extension_points:

public_api_constraints:

functional_check_command:
architecture_check_command:
```

Не задавай один единственный допустимый diff.

Нас интересуют architectural properties, а не совпадение с reference implementation.

---

# 24. Validators

Validators создаются **до agent runs**.

Для каждой задачи:

## Functional validators

проверяют feature requirements.

## Architecture validators

проверяют architectural constraints.

Каждая задача должна иметь минимум 3 meaningful architecture checks.

Лучше 4–8.

---

# 25. Проверка benchmark task

До включения задачи benchmark должен пройти два теста.

## Positive control

Архитектурно правильная реализация:

```text
functional validators = PASS
architecture validators = PASS
```

## Negative control

Специально созданное архитектурно неправильное, но функционально работающее решение:

```text
functional validators = PASS
architecture validators = FAIL
```

Особенно обязательно для Architecture Trap.

Если validators не различают эти случаи — task непригодна.

---

# 26. Architecture Conformance Rate

Для каждого run:

```text
ACR =
passed architecture checks
/
total architecture checks
```

Также:

```text
Full Architecture Conformance =
1 if all architecture checks passed
else 0
```

---

# 27. 10 независимых repetitions

Каждая cell выполняется десять раз.

Важно:

каждый repetition должен быть **полностью независимой agent session**.

Запрещено:

- conversational memory;
- результаты предыдущего run;
- previous diff;
- previous Goga output, созданный во время решения задачи;
- ручные подсказки;
- накопленные task-specific notes.

---

# 28. Clean-room execution

Перед каждым run:

1. восстановить исходный commit;
2. создать clean worktree/container;
3. очистить task-specific agent state;
4. проверить git status;
5. создать новую Claude Code session.

Для Baseline состояние всегда идентично исходному repository.

Для Goga состояние всегда идентично зафиксированному Goga-prepared repository.

---

# 29. Goga architecture freeze

Repository-level Goga artifacts создаются **один раз**.

После начала benchmark нельзя оптимизировать их под конкретную task.

Одна и та же architecture representation используется:

```text
Task A × 10
Task B × 10
Task C × 10
Task D × 10
```

Все manual corrections документируются.

---

# 30. Repetition schedule

Не выполнять так:

```text
10 baseline
потом
10 goga
```

чтобы temporal drift не совпадал с condition.

Создай blocked randomized schedule.

Для каждой:

```text
repository + task + repetition
```

случайно определить:

```text
Baseline → Goga
```

или:

```text
Goga → Baseline
```

Использовать фиксированный random seed.

---

# 31. experiment_plan.csv

Сформировать все 800 runs заранее.

Колонки:

```text
run_number
run_id
repository
task
task_type
condition
repetition
pair_block
execution_order
```

После начала benchmark план не менять.

---

# 32. Run IDs

Использовать:

```text
R01-T01-B-01
R01-T01-B-02
...
R01-T01-B-10

R01-T01-G-01
...
R01-T01-G-10
```

---

# 33. Никакого manual rescue

После начала run нельзя:

- давать дополнительные hints;
- рассказывать architecture;
- указывать нужный файл;
- исправлять код;
- отвечать по-разному на clarification questions.

Предпочтителен autonomous execution.

Если interaction неизбежен, заранее создать единое правило neutral response.

---

# 34. Timeout

Одинаковый timeout для всех runs.

Если превышен:

```text
status = TIMEOUT
```

Не продолжать вручную.

---

# 35. Метрики каждого run

Собрать минимум следующие показатели.

## Correctness

```text
functional_success
full_architecture_conformance
architecture_conformance_rate
dangerous_success
existing_test_regressions
```

## Agent activity

Если доступны:

```text
input_tokens
output_tokens
total_tokens
tool_calls
shell_commands
searches
file_reads
unique_files_read
```

## Change

```text
files_added
files_modified
files_deleted

lines_added
lines_deleted

modules_touched
dependencies_added
dependencies_removed
```

## Time

```text
agent_time
build_time
test_time
validation_time
total_time
```

---

# 36. Architecture Discovery Cost

Попробуй измерить действия agent до первого изменения production code:

```text
files_read_before_first_edit
unique_files_read_before_first_edit
searches_before_first_edit
tool_calls_before_first_edit
tokens_before_first_edit
seconds_before_first_edit
```

Это:

# Architecture Discovery Cost

Гипотеза:

структурированное описание architecture может уменьшить необходимость каждый раз реконструировать систему через grep/read/search.

Не считай гипотезу заранее подтверждённой.

---

# 37. Reproducibility / stability metrics

Именно здесь используются 10 repetitions.

Для каждой experimental cell рассчитать:

```text
Functional Success Rate
Full Architecture Conformance Rate
Dangerous Success Rate

ACR mean
ACR median
ACR standard deviation
ACR IQR
ACR min
ACR max
```

---

# 38. Architectural Decision Stability

Нас интересует не только:

> проходит ли код architecture validator?

Но и:

> принимает ли agent одинаковое архитектурное решение?

Для Task C/D определить заранее ключевые architectural decisions.

Например:

```text
extension point used
target module
dependency direction
abstraction reused
new abstraction introduced
```

Для десяти repetitions рассчитать consistency.

Например:

```text
10/10 used ExistingPaymentRepository
```

или:

```text
4/10 used repository
3/10 created cache service
2/10 implemented cache in controller
1/10 introduced new storage abstraction
```

Это очень важный результат.

---

# 39. Dominant Strategy Share

Для заранее определённых архитектурных решений считать:

```text
Dominant Strategy Share =
number of repetitions using most common strategy
/
10
```

Например:

```text
Baseline = 0.4
Goga = 0.9
```

Это показывает:

> насколько поведение agent детерминировано архитектурным контекстом.

---

# 40. Module-set stability

Для каждого run сохранить множество изменённых modules.

Для десяти repetitions вычислить pairwise Jaccard similarity.

Например:

```text
J(A,B) =
|modules_A ∩ modules_B|
/
|modules_A ∪ modules_B|
```

Посчитать:

```text
mean_module_jaccard
median_module_jaccard
```

Отдельно можно считать file-set similarity, но интерпретировать осторожно:

разные файлы не обязательно означают архитектурно разное решение.

Module-level consistency важнее.

---

# 41. Dependency-delta stability

Для каждого run построить изменения dependency graph.

Сравнить между repetitions:

```text
added_dependency_edges
removed_dependency_edges
```

Нас интересует:

> создаёт ли agent при одной задаче каждый раз разную topology.

---

# 42. Extension Point Stability

Для Task C:

```text
correct_extension_point_usage_rate
```

Например:

```text
Baseline:
6/10

Goga:
10/10
```

Это одновременно:

- quality metric;
- reproducibility metric.

---

# 43. Variance — важный результат

Возможный эффект Goga может выглядеть не так:

```text
Baseline ACR = 50%
Goga ACR = 90%
```

а так:

```text
Baseline mean ACR = 88%
Goga mean ACR = 90%
```

но:

```text
Baseline:
55%, 100%, 70%, 95%, 100%, ...

Goga:
90%, 90%, 95%, 90%, 95%, ...
```

То есть среднее качество почти одинаковое, но Goga сильно снижает variance.

Это самостоятельный важный результат.

---

# 44. Cost of stability

Если Goga делает agent более стабильным, проверить цену:

```text
extra tokens
extra tool calls
extra time
extra context
Goga setup cost
```

Нужен ответ:

> сколько стоит один процент улучшения architecture conformance или stability?

Не обязательно буквально строить одну универсальную ROI formula, но trade-off должен быть виден.

---

# 45. Goga setup cost

Отдельно измерить для каждого repository:

```text
initial_generation_time
manual_review_time
manual_correction_time
number_of_manual_corrections
artifact_size
maintenance_steps
```

Если Goga потребовала три часа ручного описания architecture — это часть результата.

Нельзя сравнивать только runtime benefit.

---

# 46. Что сохранять после run

Для каждого run:

```text
prompt.txt
agent.log
stdout.log
stderr.log
git.diff
git.status
changed_files.txt

metrics.json
functional_results.json
architecture_results.json

environment.json
result.md
```

Raw results никогда не перезаписывать.

---

# 47. Invalid runs

Если experiment infrastructure сломалась:

```text
status = INVALID
reason = ...
```

Raw data сохранить.

Создать replacement run с новым ID.

Не удалять неудачный run из истории.

---

# 48. Первичный dataset

`results/runs.csv`

минимум:

```text
run_id
repository
task
task_type
condition
repetition

functional_success
architecture_conformance_rate
full_architecture_conformance
dangerous_success

architecture_checks_passed
architecture_checks_failed

extension_point_reused
forbidden_dependencies_added

duration
tokens
tool_calls

files_read
files_read_before_first_edit

files_changed
modules_touched
lines_added
lines_deleted

timeout
invalid
failure_type

model
model_version
timestamp
```

---

# 49. Cell-level dataset

Создай:

`results/cells.csv`

80 rows:

```text
repository
task
task_type
condition

runs_valid

functional_success_rate
full_architecture_success_rate
dangerous_success_rate

acr_mean
acr_median
acr_sd
acr_iqr

dominant_strategy_share

module_jaccard_mean

extension_point_usage_rate

duration_mean
tokens_mean
tool_calls_mean

architecture_discovery_cost_mean
```

Это основной dataset для анализа reproducibility.

---

# 50. Task-level comparison

Создай:

`results/task_comparison.csv`

40 rows.

Каждая строка = одна уникальная task.

```text
repository
task
task_type

baseline_ACR_mean
goga_ACR_mean
delta_ACR

baseline_ACR_sd
goga_ACR_sd
delta_variance

baseline_architecture_success_rate
goga_architecture_success_rate

baseline_dangerous_success_rate
goga_dangerous_success_rate

baseline_dominant_strategy_share
goga_dominant_strategy_share

baseline_module_jaccard
goga_module_jaccard

baseline_tokens
goga_tokens

baseline_time
goga_time

baseline_discovery_cost
goga_discovery_cost
```

Это одна из главных таблиц исследования.

---

# 51. Failure taxonomy

После runs классифицировать failures минимум так:

```text
wrong_layer
wrong_module
forbidden_dependency
duplicate_abstraction
bypassed_extension_point
public_api_leak
architecture_overengineering
unnecessary_cross_module_dependency

feature_incomplete
build_failure
test_failure
timeout
```

При обнаружении новых повторяющихся patterns добавить категории.

Не изменять задним числом primary architecture score.

Failure taxonomy является secondary analysis.

---

# 52. Statistical analysis

Не анализировать 800 observations как независимые.

Использовать структуру:

```text
repository
→ task
→ condition
→ repetition
```

Для primary analysis можно:

1. агрегировать десять repetitions внутри каждой condition;
2. получить 40 paired task-level comparisons;
3. сравнить Baseline vs Goga.

Дополнительно можно использовать hierarchical/mixed-effects modelling.

Для бинарных outcomes учитывать repeated observations.

Для continuous metrics анализировать distribution, а не только mean.

Показывать:

```text
mean
median
SD
IQR
confidence interval
effect size
```

где это статистически корректно.

Не использовать p-value как единственный аргумент.

---

# 53. Главные research questions

После эксперимента ответить:

## RQ1

Как часто AI-agent нарушает архитектуру существующего repository?

## RQ2

Как часто это происходит при полностью функционально корректном результате?

## RQ3

Меняет ли Goga Architecture Conformance Rate?

## RQ4

Меняет ли Goga Dangerous Success Rate?

## RQ5

Меняет ли Goga run-to-run variance?

## RQ6

Принимает ли agent более стабильные архитектурные решения?

## RQ7

Чаще ли он использует existing extension points?

## RQ8

Уменьшается ли Architecture Discovery Cost?

## RQ9

Как эффект зависит от типа задачи?

## RQ10

Как эффект зависит от размера и modularity repository?

## RQ11

Как эффект зависит от качества documentation?

## RQ12

Какова цена Goga с точки зрения tokens/time/setup effort?

---

# 54. Анализ по типам задач

Обязательно отдельно:

```text
Local Change
Cross-module
Extension Point
Architecture Trap
```

Не прятать всё за одной средней цифрой.

Возможно:

```text
Local:
Goga не даёт эффекта

Cross-module:
умеренный эффект

Extension Point:
сильный эффект

Architecture Trap:
очень сильный эффект
```

Или наоборот.

Любой результат валиден.

---

# 55. Анализ complexity

Проверить зависимость:

```text
repository LOC
number of modules
dependency graph complexity
modularity
documentation quality
```

от:

```text
delta architecture quality
delta stability
delta cost
```

Главный практический вопрос:

> при какой сложности проекта architecture-aware approach начинает окупаться?

---

# 56. Визуализации

Подготовить данные минимум для следующих графиков.

## 1. Architecture Conformance

Baseline vs Goga по 40 tasks.

## 2. Dangerous Success Rate

Baseline vs Goga.

## 3. Architecture Conformance by Task Type

```text
Local
Cross-module
Extension Point
Architecture Trap
```

## 4. Run-to-run variance

Baseline vs Goga.

## 5. Dominant Strategy Share

Насколько одинаковую strategy выбирает agent.

## 6. Module-set consistency

Baseline vs Goga.

## 7. Architecture Discovery Cost

Baseline vs Goga.

## 8. Repository complexity vs Goga effect.

## 9. Cost vs architecture improvement.

## 10. Ten-run plots

Для нескольких характерных tasks показать непосредственно все 20 запусков:

```text
Baseline ×10
Goga ×10
```

Это особенно важно для рассказа о reproducibility.

---

# 57. Case studies

Выбрать минимум пять.

## Case 1

Baseline и Goga одинаково хорошие.

## Case 2

Baseline функционален, но архитектурно ошибочен.

## Case 3

Goga находит правильный extension point значительно стабильнее.

## Case 4

Среднее качество одинаковое, но Goga значительно уменьшает variance.

## Case 5

Goga проигрывает Baseline или создаёт overhead без пользы.

Не скрывать отрицательные результаты.

---

# 58. Очень интересный кейс для доклада

Ищи ситуации вида:

```text
Same repository
Same commit
Same task
Same model
Same prompt
```

но Baseline десять раз создаёт несколько разных архитектур:

```text
Run 1 → controller
Run 2 → service
Run 3 → new manager
Run 4 → repository
Run 5 → controller
...
```

а Goga, например:

```text
10 runs
↓
same existing extension point
```

или наоборот.

Это будет одним из наиболее наглядных доказательств архитектурной нестабильности AI coding agents.

---

# 59. Benchmark repository structure

Создай:

```text
architecture-agent-benchmark/
│
├── README.md
├── PROTOCOL.md
├── GOGA_RESEARCH.md
├── TREATMENT_DESIGN.md
├── REPOSITORY_SELECTION.md
├── STATUS.md
│
├── experiment.yaml
├── repos.yaml
├── experiment_plan.csv
│
├── repositories/
├── architecture/
├── tasks/
├── runs/
├── scripts/
├── results/
└── report/
```

---

# 60. PROTOCOL freeze

До первого реального experiment run:

1. repositories выбраны;
2. все 40 tasks определены;
3. validators готовы;
4. positive controls проверены;
5. negative controls проверены;
6. Goga treatment определён;
7. metrics определены;
8. randomization создана.

После этого:

```text
git tag benchmark-v1
```

или эквивалент.

Изменения protocol после этого документировать.

---

# 61. STATUS.md

Вести:

```text
Repositories selected: 0/10

Tasks designed: 0/40
Tasks validated: 0/40

Goga configurations prepared: 0/10

Experimental cells prepared: 0/80

Runs completed: 0/800
Runs valid: 0/800
Runs invalid: 0

Results aggregated: no
Statistical analysis: no
Final report: no
```

---

# 62. Phases

Не начинай сразу 800 запусков.

## Phase 0 — Goga research

Изучить `qarium/goga`.

Создать:

```text
GOGA_RESEARCH.md
TREATMENT_DESIGN.md
```

## Phase 1 — Environment

Зафиксировать версии и infrastructure.

## Phase 2 — Repository selection

Выбрать 10 repositories.

## Phase 3 — Task design

Создать 40 задач.

## Phase 4 — Validators

Создать functional + architecture validators.

## Phase 5 — Controls

Проверить positive/negative implementations.

## Phase 6 — Pilot

Выполнить небольшой pilot только для проверки infrastructure.

Pilot results НЕ включать в основную выборку.

Не использовать pilot для подгонки задач под победу Goga.

## Phase 7 — Protocol freeze

Зафиксировать benchmark.

## Phase 8 — Goga preparation

Подготовить repository-level Goga artifacts.

## Phase 9 — Randomization

Создать immutable plan на 800 runs.

## Phase 10 — Execution

Выполнить 800 runs.

## Phase 11 — Validation

Запустить validators.

## Phase 12 — Aggregation

Создать runs/cells/tasks datasets.

## Phase 13 — Analysis

Quality + stability + cost.

## Phase 14 — Report

Подготовить итоговый research report.

---

# 63. Pilot не должен превращаться в cherry-picking

Pilot нужен только для проверки:

- запуска Claude;
- изоляции sessions;
- сбора metrics;
- работы validators;
- интеграции Goga;
- сохранения logs.

Если после pilot изменяется benchmark methodology, выполнить pilot заново.

Pilot runs не входят в 800.

---

# 64. Финальный отчёт

`report/final_report.md` должен отвечать не на вопрос:

> Goga хорошая?

а на вопрос:

> Что происходит, когда AI-agent изменяет большую существующую систему, и помогает ли явное архитектурное знание делать этот процесс более корректным и воспроизводимым?

Структура:

1. Research question
2. Hypotheses
3. Goga treatment
4. Repository sample
5. Benchmark design
6. 800-run methodology
7. Functional results
8. Architecture results
9. Dangerous Success
10. Run-to-run stability
11. Architecture Decision Stability
12. Task-type analysis
13. Repository complexity analysis
14. Cost
15. Goga setup overhead
16. Failure taxonomy
17. Case studies
18. Threats to validity
19. Limitations
20. Practical recommendations
21. Raw conclusions

---

# 65. Threats to validity

Обязательно отдельно рассмотреть:

- одна модель AI;
- один coding-agent harness;
- всего 10 repositories;
- всего 4 задачи на repository;
- субъективность выбора задач;
- качество architecture validators;
- качество Goga representation;
- возможный model drift;
- nondeterminism LLM;
- differences между языками;
- open-source repositories могут отличаться от proprietary enterprise codebases;
- caching/tooling effects;
- невозможность получить некоторые token/tool metrics;
- возможность contamination через persistent agent state.

Не скрывать ограничения.

---

# 66. Главное правило выводов

Не писать:

> Goga делает AI на 30% лучше.

Писать точно:

> Для 40 заранее определённых engineering tasks, каждая из которых была независимо выполнена 10 раз в каждом condition, Goga-condition снизил/увеличил X с A до B. Эффект был наиболее выражен в задачах типа Y, тогда как для Z статистически и практически значимого преимущества мы не обнаружили.

И отдельно:

> В Baseline condition одна и та же задача приводила в среднем к N различным архитектурным стратегиям на десять запусков, тогда как в Goga condition — к M.

Все утверждения должны подтверждаться raw data.

---

# 67. Главная идея исследования

Не исследуй:

> насколько хорошо AI пишет код.

Исследуй:

> насколько хорошо AI способен многократно изменять существующую сложную систему, сохраняя её архитектурные свойства.

И второй вопрос:

> является ли архитектурное решение AI воспроизводимым, или одна и та же задача при одинаковом входе каждый раз приводит к другой архитектуре?

Центральные состояния:

```text
feature works
+
tests pass
+
architecture violated
```

и:

```text
same task
+
same model
+
same repository
+
different architectural decision
```

---

# 68. Что сделать прямо сейчас

Не запускай benchmark.

Сначала выполни только Phase 0–2:

### Step 1

Изучи repository `qarium/goga`.

### Step 2

Создай `GOGA_RESEARCH.md`.

### Step 3

Определи, что именно Goga меняет относительно Baseline.

### Step 4

Создай `TREATMENT_DESIGN.md`.

### Step 5

Создай initial `PROTOCOL.md`.

### Step 6

Создай `experiment.yaml`.

### Step 7

Создай критерии выбора repositories.

### Step 8

Найди кандидатов.

### Step 9

Проведи reconnaissance.

### Step 10

Предложи финальные 10 repositories с аргументацией.

### Step 11

До дальнейшей работы проверь, что выбранный дизайн действительно позволяет обоснованно ответить на два вопроса:

**QUALITY:**
> соблюдает ли AI architecture?

**STABILITY:**
> повторяет ли AI своё архитектурное решение при повторном запуске?

Если дизайн не позволяет отделить эффект architecture representation от остальных частей Goga workflow — явно укажи это и скорректируй research claim, а не скрывай confound.

Главный принцип всего проекта:

# Reproducibility > impressive result.