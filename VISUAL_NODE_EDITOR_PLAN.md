# План: визуальный node-based редактор диалогов для Dialogue Manager 4

Документ описывает пошаговый план создания визуального редактора диалогов на графах
(`GraphEdit` / `GraphNode`) для аддона **Dialogue Manager 4**, который уже подключён
в этом проекте. Редактор должен работать внутри редактора Godot, создавать диалоги
в виде связанных узлов и поддерживать весь заявленный функционал аддона, включая
локализацию.

> **Статус документа:** разделы 1–17 описывают исходный проектный замысел.
> Разделы **18–21** обновлены по фактической реализации: сигнатуры, чек-лист,
> текущий статус и changelog. Если проектный текст расходится с фактическим
> поведением, приоритет имеет раздел **20–21**.

---

## 1. Кратко

### Что делаем

- Новый режим **Graph** внутри существующей вкладки **Dialogue** (рядом с текстовым
  редактором), а не отдельный плагин и не отдельная вкладка.
- Диалог хранится в существующем текстовом формате `.dialogue`. Граф — это
  двунаправленное представление того же файла.
- Узлы графа: реплики, ответы, условия, `match`, `while`, мутации, переходы,
  случайные ветки, куски (`cue`), импорты, комментарии.
- Связи: последовательный поток, ветвление, переходы на `cue`, возвраты
  (`=><`), импорты, одновременные реплики.
- Полная поддержка возможностей аддона: условия, мутации, `match`/`while`,
  случайные и взвешенные строки, ответы с условиями, `cue`/`goto`/`=><`,
  импорты, теги, одновременные реплики, BBCode, статические ID, заметки
  переводчикам, имена персонажей, экспорт POT/CSV.
- Сохранение, компиляция, тестовый запуск, поиск, панель ошибок и локализация
  используют уже существующую инфраструктуру аддона.

> **Фактически:** реализованы режимы **Text** и **Graph** (без `Split`),
> кнопка **Arrange all nodes**, редактирование и добавление/удаление
> condition/match/random-кейсов, соединения с top-level узлами через
> автосоздание `cue`, отсоединение переходов, панель **Localization**
> и собственный layered layout. Подробности — в разделах 20–21.

### Что не делаем на первом этапе

- Не меняем формат `.dialogue` и не вводим второй источник правды.
- Не переписываем runtime и импортёр.
- Не делаем отдельный редактор сцен или отдельный формат ресурса графа.
- Не поддерживаем произвольные «спагетти»-связи, которые невозможно выразить
  текстом (см. ограничения в разделе 6.3).

### Ключевое допущение

**Текст `.dialogue` — единственный источник правды.** Граф читает текст,
показывает его структурой и вносит точечные правки обратно в текст. Позиции
узлов, зум и оформление хранятся в отдельном sidecar-файле и не влияют на runtime.

Это самый безопасный путь для существующего проекта: импортёр, runtime,
локализация, ручное редактирование, git и все существующие `.dialogue`-файлы
продолжают работать без изменений.

---

## 2. Аудит проекта: что уже есть и что переиспользуем

### 2.1. Ключевые файлы

| Файл | Роль | Как используем |
|---|---|---|
| `addons/dialogue_manager/plugin.gd` | `EditorPlugin`: главный экран «Dialogue», импорт/экспорт, инспектор, переводы, debugger | Добавляем graph-режим в существующий `main_view`, новых main screen не создаём |
| `addons/dialogue_manager/views/main_view.gd` | Текстовый редактор, буферы открытых файлов, компиляция, сохранение, тест | Расширяем: режимы Text/Graph, общий буфер, синхронизация |
| `addons/dialogue_manager/views/main_view.tscn` | UI главного экрана | Не менялся; `GraphView` и кнопка **Graph** создаются программно |
| `addons/dialogue_manager/compiler/compiler.gd` | `DMCompiler.compile_string(text, path)` | Основной источник структуры для построения графа |
| `addons/dialogue_manager/compiler/compilation.gd` | Парсер, дерево строк, `DMCompiledLine` | Используем `DMCompilerResult.lines`; source line восстанавливаем из line ID |
| `addons/dialogue_manager/compiler/compiled_line.gd` | Данные скомпилированной строки | Используем `type`, `next_id`, `responses`, `siblings`, `expression` и т.д. |
| `addons/dialogue_manager/import_plugin.gd` | Импорт `.dialogue` → `DialogueResource` | Не меняем; граф сохраняет текст, импортёр работает как раньше |
| `addons/dialogue_manager/dialogue_resource.gd` | Runtime-ресурс | Не меняем |
| `addons/dialogue_manager/dialogue_manager.gd` | Runtime | Не меняем |
| `addons/dialogue_manager/utilities/translations.gd` | Генерация статических ID, экспорт CSV | Переиспользуем в graph-панели локализации |
| `addons/dialogue_manager/editor_translation_parser_plugin.gd` | POT-парсер `.dialogue` | Не меняем; граф не должен ломать статические ID и заметки |
| `addons/dialogue_manager/settings.gd` | Настройки проекта | Добавляем настройки graph-режима |
| `addons/dialogue_manager/constants.gd` | Типы строк, коды ошибок | Используем для маппинга узлов и ошибок |
| `tests/` | Самописный тестовый раннер (`tests.tscn`) | Добавляем unit-тесты графа |

### 2.2. Что уже даёт компилятор

`DMCompiler.compile_string()` возвращает `DMCompilerResult`:

- `lines: Dictionary` — все скомпилированные строки по ID;
- `cues: Dictionary` — `cue -> line_id`;
- `first_cue: String`;
- `character_names: PackedStringArray`;
- `using_states: PackedStringArray`;
- `imported_paths: PackedStringArray`;
- `errors: Array[DMError]`.

`DMCompiledLine` уже содержит почти всё, что нужно графу:

- `type` — `dialogue`, `response`, `condition`, `while`, `match`, `when`,
  `mutation`, `goto`, `random`, `cue`, `import`, `using`, `comment`;
- `next_id` — следующий узел;
- `next_sibling_id` — следующий `elif`/`else`;
- `next_id_after` — точка слияния после блока;
- `responses` — ID ответов;
- `siblings` — ветки `match`/`random`;
- `expression` — условие/мутация;
- `is_snippet` — переход с возвратом (`=><`);
- `concurrent_lines` — одновременные реплики;
- `tags`, `static_id`, `notes`, `character`, `text`.

Этого достаточно, чтобы построить граф без повторного написания парсера.

### 2.3. Ограничения текущего кода

- `DMCompiledLine` не хранит номер исходной строки и сырой текст. Граф
  восстанавливает source line из line ID и сырых строк (см. 5.2).
- `when`-строки удаляются из `lines` после разбора `match`, поэтому их source
  line ищется сканированием сырых строк.
- Вложенные реплики (indented dialogue) компилятор склеивает в текст родительской
  строки. В графе они показываются как многострочный текст одной ноды.
- `DMCompilation` не менялся для source map; в `compiled_line.gd` добавлены
  только `next_id_after` для response/dialogue/random.
- В проекте уже есть предупреждения GDScript о нетипизированных объявлениях.
  Новый код пишем с типами, в стиле аддона (табы, `@tool`, `class_name DM...`).

---

## 3. Архитектурное решение

### 3.1. Сравнение вариантов

| Вариант | Плюсы | Минусы | Решение |
|---|---|---|---|
| **Text-first**: `.dialogue` — источник правды, граф — представление | Совместимость со всем аддоном, ручное редактирование, git, локализация, все синтаксисы | Сложный round-trip, стабильные ID, точечные патчи | **Рекомендуется** |
| **Graph-first**: отдельный `.dialoguegraph` — источник правды, `.dialogue` генерируется | Простые стабильные ID, проще undo/redo, канонический текст | Ломает ручное редактирование, дублирование, риск рассинхронизации, сложнее с существующими файлами | Возможен как второй режим позже |
| **Только чтение**: граф показывает текст, редактирование только в тексте | Минимум риска, быстро | Не решает задачу «создавать диалоги в виде nodes» | Как первый этап (read-only) |

### 3.2. Рекомендуемая схема

```
.dialogue (единственный источник правды)
    │
    │  DMCompiler.compile_string()
    ▼
DMCompilerResult (lines, cues, errors)
    │
    │  DMGraphBuilder
    ▼
DMGraphDocument (nodes, edges, source ranges)
    │
    │  DMGraphView (GraphEdit + GraphNode)
    ▼
пользователь редактирует граф
    │
    │  DMGraphSerializer (патчи в текст)
    ▼
.dialogue (обновлённый текст)
    │
    │  существующий DMImportPlugin
    ▼
DialogueResource (.tres) → runtime
```

Sidecar:

```
intro.dialogue
intro.dialogue.graph.json   ← только позиции, зум, группы, комментарии
```

Sidecar можно удалить без потери диалога: граф перестроится, узлы расположатся
автоматически.

### 3.3. Почему не отдельный main screen

`EditorPlugin` в Godot имеет один main screen на плагин. В проекте он уже занят
вкладкой **Dialogue**. Создавать второй плагин ради второй вкладки — лишняя
сложность: два плагина, два жизненных цикла, дублирование буферов и настроек.

Правильнее добавить в существующий `main_view` переключатель:

```
[ Graph ]
```

- **Text** — текущий редактор, без изменений (режим по умолчанию).
- **Graph** — граф на всё окно, активируется кнопкой **Graph** в toolbar.
- **Split** — проектное расширение на будущее (текст слева, граф справа);
  в текущей реализации не добавлен.

Оба фактических режима используют один и тот же буфер `open_buffers[path]`,
один процесс сохранения, одну компиляцию и одну панель ошибок.

---

## 4. Модель данных графа

### 4.1. Типы узлов

| Тип узла | Синтаксис в `.dialogue` | Порты | Свойства |
|---|---|---|---|
| `CUE` | `~ cue_name` | вход (переходы), выход (поток) | имя cue, позиция, комментарий |
| `DIALOGUE` | `Character: text` | вход, выход | персонаж, текст, теги, static ID, заметка, inline-мутации, одновременные реплики |
| `CHOICES` | группа `- response` | вход, N выходов ответов, выход «продолжить» | список ответов |
| `RESPONSE` | `- prompt [if ... /] => cue` | вход (от CHOICES), выход | текст, условие, static ID, теги, персонаж, переход |
| `CONDITION` | `if` / `elif` / `else` | вход, N выходов, выход «после» | список веток с выражениями |
| `MATCH` | `match expr` + `when` + `else` | вход, N выходов, выход «после» | выражение, кейсы |
| `WHILE` | `while expr` | вход, выход «тело», выход «после», обратная связь | условие |
| `MUTATION` | `$> expr`, `$>> expr`, `do`, `set` | вход, выход | выражение, блокирующая/неблокирующая |
| `JUMP` | `=> cue`, `=>< cue`, `=> END`, `=> END!` | вход, выход «переход», выход «возврат» | цель, тип перехода, выражение |
| `RANDOM` | `%`, `%2`, `% [if ...]` | вход, N выходов, выход «после» | ветки с весом и условием |
| `CONCURRENT` | `\| Character: text` | вход от DIALOGUE | персонаж, текст, теги |
| `COMMENT` | `# comment`, `## note` | — | текст, привязка к строке |
| `IMPORT` | `import "path" as alias` | — | путь, алиас, внешние cue |
| `USING` | `using State` | — | имя состояния |
| `NOTE` | graph-only | — | стикер-комментарий, не пишется в `.dialogue` |

### 4.2. Типы связей

| Тип | Смысл | Отображение |
|---|---|---|
| `FLOW` | последовательный переход `next_id` | сплошная серая/синяя линия |
| `BRANCH` | ветка ответа, условия, `match`, `random` | цветная линия с подписью |
| `JUMP` | переход на `cue` | пунктирная линия |
| `RETURN` | возврат после `=><` | пунктирная линия с меткой «return» |
| `IMPORT` | ссылка на cue в другом файле | редкая пунктирная линия |
| `CONCURRENT` | одновременная реплика | короткая пунктирная связь |

### 4.3. Базовые классы

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_document.gd
@tool
class_name DMGraphDocument extends RefCounted

var path: String = ""
var text: String = ""
var nodes: Dictionary = {}          # String -> DMGraphNode
var edges: Array[DMGraphEdge] = []
var cues: Dictionary = {}           # cue -> node_id
var imports: Array[Dictionary] = []
var using_states: PackedStringArray = []
var errors: Array[DMError] = []
var source_lines: PackedStringArray = []
var first_cue: String = ""
```

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_node.gd
@tool
class_name DMGraphNode extends RefCounted

enum Kind {
    CUE, DIALOGUE, CHOICES, RESPONSE, CONDITION, MATCH, WHILE,
    MUTATION, JUMP, RANDOM, CONCURRENT, COMMENT, IMPORT, USING, NOTE
}

var id: String = ""
var kind: Kind = Kind.DIALOGUE
var stable_key: String = ""
var source_start: int = -1          # 0-based, включительно
var source_end: int = -1            # 0-based, включительно
var parent_id: String = ""
var children: PackedStringArray = []
var ports: Array[Dictionary] = []   # { name, kind, index, color }
var properties: Dictionary = {}     # character, text, condition, weight, ...
var position: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2.ZERO
var collapsed: bool = false
```

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_edge.gd
@tool
class_name DMGraphEdge extends RefCounted

enum Kind { FLOW, BRANCH, JUMP, RETURN, IMPORT, CONCURRENT }

var from_node: String = ""
var from_port: int = 0
var to_node: String = ""
var to_port: int = 0
var kind: Kind = Kind.FLOW
var label: String = ""
```

### 4.4. Стабильные ID

ID компилятора — это номера строк (`"12"`, `"12.1"`), они меняются при любой
вставке. Для sidecar и undo/redo нужны стабильные ключи.

Правила генерации `stable_key` (фактическая реализация):

1. Реплика со `static_id` — `dialogue:<static_id>`.
2. Реплика без `static_id` — `dialogue:<hash(character + ":" + text)>`.
3. Ответ со `static_id` — `response:<static_id>`.
4. Ответ без `static_id` — `response:<hash(text)>` (без source line, чтобы
   позиция не терялась при вставке строк выше).
5. `cue` — `cue:<name>`.
6. `condition` — `condition:<hash(expression)>`.
7. `match` — `match:<hash(condition)>`.
8. `while` — `while:<hash(condition)>`.
9. `mutation` — `mutation:<hash(mutation)>`.
10. `jump` — `jump:<hash(next_id)>:<is_snippet>`.
11. `random` — `random:<hash(siblings)>`.
12. `comment` — `comment:<hash(raw_text)>`.
13. `import` — `import:<path>`, `using` — `using:<state>`.
14. Иначе — `<type>:<source_start>`.

При перестроении графа узлы сопоставляются в таком порядке:

1. Точное совпадение `stable_key`.
2. Точное совпадение `source_start`.
3. Ближайший сохранённый узел того же `kind` (в пределах 8 строк).
4. Если ничего не найдено — узел считается новым и получает позицию из
   auto-layout (или колонку по source line, если часть позиций уже сохранена).

Sidecar хранит `position`, `size`, `collapsed`, `source_start` и `kind`.
Использованные записи помечаются, чтобы одна saved-позиция не применилась
к нескольким узлам.

### 4.5. Sidecar-файл

Путь: `<dialogue_path>.graph.json`, например
`res://dialogues/intro.dialogue.graph.json`.

```json
{
  "version": 1,
  "file": "res://dialogues/intro.dialogue",
  "nodes": {
    "cue:start": {
      "position": [120, 80],
      "size": [220, 90],
      "collapsed": false,
      "source_start": 0,
      "kind": 0
    },
    "dialogue:abc123": {
      "position": [120, 240],
      "size": [320, 140],
      "collapsed": false,
      "source_start": 1,
      "kind": 1
    }
  },
  "groups": [],
  "settings": {}
}
```

Sidecar:

- не импортируется Godot как ресурс (расширение `.json`, не `.dialogue`);
- перемещается вместе с `.dialogue` при `files_moved`;
- удаляется при `file_removed`;
- при конфликте версий — игнорируется, граф строится заново;
- не обязателен для работы: без него используется собственный layered layout;
- хранит `source_start` и `kind` для fallback-сопоставления позиций.

---

## 5. Парсинг текста в граф

### 5.1. Общий алгоритм

```
1. Прочитать текст файла.
2. Вызвать DMCompiler.compile_string(text, path).
3. Разобрать файловые строки: import, using, комментарии.
4. Восстановить source line из line ID и отступов (см. 5.2).
5. Создать узлы CUE для всех cues и first_cue.
6. Пройти скомпилированные строки в порядке исходника.
7. Сгруппировать:
   - цепочки if/elif/else в один CONDITION;
   - when/else внутри match в один MATCH;
   - группу response в один CHOICES + RESPONSE-порты;
   - группу % в один RANDOM;
   - concurrent_lines в CONCURRENT-узлы.
8. Создать рёбра из next_id, next_sibling_id, next_id_after,
   responses, siblings, concurrent_lines, is_snippet.
9. Привязать source_start/source_end.
10. Провалидировать и вернуть DMGraphDocument.
```

### 5.2. Source map (фактическая реализация)

Полноценный `for_editor` source map в компилятор **не добавлялся**. Вместо
этого `DMGraphBuilder` использует уже существующий `DMCompilerResult.lines`
и восстанавливает исходные строки сам:

- `DMCompilerResult.lines` — это `Dictionary` из `DMCompiledLine.to_data()`,
  ключи — line ID (`"0"`, `"1"`, `"12.1"`).
- `source_start` вычисляется из line ID: `id.split(".")[0].to_int()`.
- Inline-goto строки с ID вида `"12.1"` пропускаются как отдельные узлы;
  их `next_id_after` переносится на родительскую реплику/ответ.
- `source_end` вычисляется через `_find_block_end()` по отступам.
- `when`/`else`-строки не входят в `lines` (компилятор удаляет их после
  разбора `match`), поэтому их source line ищется сканированием сырых строк
  назад от первого дочернего узла (`_find_match_case_line()`).
- `%`-строки случайных веток ищутся сканированием сырых строк на том же
  отступе (`_find_random_branch_lines()`).
- `import`/`using` разбираются из сырых строк в `_extract_imports()` и
  `_build_file_nodes()`.
- Комментарии `#`/`##` приходят как `TYPE_COMMENT` и превращаются в
  `COMMENT`-узлы.

В `compiler/compiled_line.gd` были добавлены только недостающие поля
`next_id_after` для `TYPE_RESPONSE`, `TYPE_DIALOGUE` и `TYPE_RANDOM`, чтобы
граф мог строить продолжение после ответов, случайных групп и inline-goto.
Остальные типы уже сохраняли `next_id_after` в `to_data()`.

Для `match`-кейсов и random-веток в `DMGraphNode.properties` дополнительно
хранятся `source_line`, `block_end`, `raw_text` и `expression`/`condition_text`.
Это позволяет редактировать и удалять кейсы/ветки точечно, не перегенерируя
весь файл.

### 5.3. Маппинг конструкций

#### Реплика

```
Nathan: Hello! [#happy] [ID:GREETING]
```

→ `DIALOGUE`:

- `character = "Nathan"`;
- `text = "Hello!"`;
- `tags = ["happy"]`;
- `static_id = "GREETING"`;
- `notes` из `##`-строки выше;
- выход → `next_id`.

Вложенные строки:

```
Nathan: First line.
    Second line.
```

компилятор склеивает в `text` через `\n`. В графе показываем одно многострочное
поле `TextEdit`, а не отдельные узлы. Это сохраняет поведение runtime.

#### Ответы

```
Nathan: Choose.
- First
    Nathan: You chose first.
- Second => other_cue
```

→ `DIALOGUE` (Choose) → `CHOICES`:

- порт `First` → `DIALOGUE` (You chose first);
- порт `Second` → `JUMP` (other_cue);
- порт `Continue` → `next_id_after` (если есть продолжение после группы).

`CHOICES` создаётся, когда `next_id` реплики указывает на `TYPE_RESPONSE`.
`responses` первой response-строки содержит ID всех ответов.

#### Условия

```
if score > 10
    Nathan: High.
elif score > 5
    Nathan: Medium.
else
    Nathan: Low.
Nathan: After.
```

→ один `CONDITION` с тремя ветками:

- `if score > 10` → первая дочерняя строка;
- `elif score > 5` → вторая;
- `else` → третья;
- выход «после» → `next_id_after` (After).

Цепочка определяется по `next_sibling_id` у condition-строк.

#### Match

```
match SomeGlobal.mode
    when 1
        Nathan: One.
    when > 5
        Nathan: Many.
    else
        Nathan: Other.
```

→ `MATCH` с портами `when 1`, `when > 5`, `else`, `after`.
Данные кейсов — `line.siblings` (`condition`, `next_id`, `is_else`).

#### While

```
while count < 10
    Nathan: Still {{count}}.
    $> count += 1
Nathan: Done.
```

→ `WHILE`:

- выход `body` → первая дочерняя строка;
- выход `after` → `next_id_after`;
- обратная связь от последней строки тела к `WHILE` (компилятор ставит
  `next_id` последней строки в ID while-строки).

#### Случайные строки

```
% Nathan: One.
%2 Nathan: Two.
% [if SomeGlobal.flag] Nathan: Three.
```

→ `RANDOM` с тремя портами, подписи `1`, `2`, `if SomeGlobal.flag`.
Данные — `line.siblings` (`weight`, `condition`, `id`).

Блочные случайные строки:

```
%
    Nathan: Block A.
    Nathan: Still A.
% Nathan: Block B.
```

→ порт `Block A` ведёт на первую строку блока, порт `Block B` — на свою строку.

#### Переходы

```
=> other_cue
=>< snippets/banter
=> END
=> END!
=> {{SomeGlobal.next_cue}}
```

→ `JUMP`:

- `target = "other_cue"`, `is_snippet = false`;
- `target = "snippets/banter"`, `is_snippet = true`, выход `return` →
  `next_id_after`;
- `target = "END"` / `"END!"`;
- `target_expression` для `{{...}}` (динамический переход, предупреждение).

#### Импорты

```
import "res://snippets.dialogue" as snippets
```

→ `IMPORT` (файловый узел) + внешние cue-узлы `snippets/banter` (read-only).
Двойной клик по внешнему cue открывает импортированный файл на нужной строке
через `DMPlugin.open_file_at_cue()`.

#### Одновременные реплики

```
Nathan: Main line.
| Coco: Same time.
| Lilly: Also same time.
```

→ `DIALOGUE` + два `CONCURRENT`-узла, связанных пунктиром. В инспекторе —
редактируемый список. В тексте — строки с `| ` после основной.

#### Комментарии и заметки

- `# comment` — обычный комментарий, можно показать как `COMMENT`-узел или
  скрыть (настройка).
- `## note` — заметка переводчику, привязывается к следующей реплике/ответу.
  В графе — поле `Translator note` в инспекторе, не отдельный узел.
- `#region` / `#endregion` — можно показывать как `GraphFrame`-группы.

### 5.4. Псевдокод builder

```gdscript
@tool
class_name DMGraphBuilder extends RefCounted

static func build(text: String, path: String) -> DMGraphDocument:
    var doc: DMGraphDocument = DMGraphDocument.new()
    doc.path = path
    doc.text = text
    doc.source_lines = text.split("\n")

    var result: DMCompilerResult = DMCompiler.compile_string(text, path)
    doc.errors = result.errors
    doc.using_states = result.using_states
    doc.imports = _extract_imports(doc.source_lines)

    _build_file_nodes(doc, result)
    _build_cue_nodes(doc, result)
    _build_line_nodes(doc, result)
    _build_edges(doc, result)

    return doc
```

---

## 6. Сериализация графа в текст

### 6.1. Принцип точечных патчей

Не пересобираем весь файл из графа. Иначе потеряются:

- комментарии;
- пустые строки и форматирование;
- порядок несвязанных блоков;
- `#region`;
- ручные переносы;
- точные отступы.

Вместо этого каждая операция графа возвращает **патч**:

```gdscript
class_name DMGraphPatch extends RefCounted

var start_line: int = 0      # 0-based
var end_line: int = 0        # 0-based, включительно
var replacement: PackedStringArray = []
var description: String = ""
```

Патчи применяются снизу вверх, чтобы не сбить номера строк.

Для структурных изменений (добавить ветку, переместить блок) сериализуется
**наименьший общий блок**, содержащий изменения. Остальной файл не трогается.

### 6.2. Таблица операций

| Действие в графе | Изменение текста |
|---|---|
| Добавить реплику после узла | вставить `Character: text` с нужным отступом |
| Изменить текст/персонажа/теги/ID | заменить конкретную строку |
| Добавить ответ | вставить `- prompt [if ... /]` + дочерний блок |
| Удалить ответ | удалить строку ответа и его дочерний блок |
| Добавить ветку условия | вставить `if`/`elif`/`else` + дочерний блок |
| Добавить кейс `match` | вставить `when value` + дочерний блок |
| Добавить случайную ветку | вставить `%N [if ...]` + дочерний блок |
| Соединить с cue | вставить/заменить `=> cue` или `=>< cue` |
| Разорвать переход | удалить `=> ...` или заменить на `=> END` |
| Удалить узел | удалить диапазон строк, соединить предыдущий с следующим |
| Переместить узел внутри родителя | переставить строки |
| Переместить узел в другого родителя | создать cue + `=>` (или запретить) |
| Добавить одновременную реплику | вставить `\| Character: text` после основной |
| Добавить импорт | вставить `import "path" as alias` в начало |
| Добавить `using` | вставить `using State` в начало |
| Добавить комментарий | вставить `# ...` или `## ...` |

### 6.3. Ограничения связей

Граф не должен позволять связи, которые невозможно выразить текстом. Правила:

1. **Последовательный поток** вычисляется из порядка строк. Перетаскивание
   узла меняет только его позицию на холсте, но не порядок строк в файле.
2. **Ветвление** создаётся только через порты `CHOICES`, `CONDITION`, `MATCH`,
   `RANDOM`. Нельзя просто протянуть линию от реплики к реплике в другой ветке.
3. **Переход** создаётся на `CUE`, `END`/`END!` или на любой top-level узел.
   Если у целевого узла нет cue, редактор автоматически вставляет
   `~ goto_<id>` перед ним и ставит `=> goto_<id>` / `=>< goto_<id>`.
4. **Межфайловый переход** — только на внешний cue из `import`; такие связи
   отображаются как текст цели, но отдельный внешний узел не создаётся.
5. Если пользователь пытается создать недопустимую связь (например, на
   вложенный узел или branch-порт), показывается сообщение в status bar,
   а связь не создаётся.

Это ключевое ограничение, которое делает round-trip предсказуемым.

### 6.4. Канонический сериализатор блока

Для сложных операций используем канонический вид:

```gdscript
static func serialize_block(node: DMGraphNode, indent: int) -> PackedStringArray:
    var lines: PackedStringArray = []
    var prefix: String = "\t".repeat(indent)

    match node.kind:
        DMGraphNode.Kind.DIALOGUE:
            var text: String = node.properties.get("text", "")
            var character: String = node.properties.get("character", "")
            var line: String = text if character.is_empty() else "%s: %s" % [character, text]
            if node.properties.has("static_id"):
                line += " [ID:%s]" % node.properties.static_id
            lines.append(prefix + line)

        DMGraphNode.Kind.RESPONSE:
            var prompt: String = node.properties.get("text", "")
            var condition: String = node.properties.get("condition", "")
            if not condition.is_empty():
                prompt += " [if %s /]" % condition
            if node.properties.has("goto"):
                prompt += " => %s" % node.properties.goto
            lines.append(prefix + "- " + prompt)

        DMGraphNode.Kind.CONDITION:
            for i: int in node.properties.cases.size():
                var c: Dictionary = node.properties.cases[i]
                var keyword: String = "if" if i == 0 else ("elif" if not c.get("is_else", false) else "else")
                var header: String = keyword
                if not c.get("is_else", false):
                    header += " " + c.expression
                lines.append(prefix + header)
                lines.append_array(serialize_children(c.children, indent + 1))

        # ... остальные типы

    return lines
```

### 6.5. Round-trip-гарантии

Целевые свойства:

1. **Idempotence**: `text -> graph -> text` для файла без изменений даёт
   побайтово тот же текст (или, как минимум, семантически эквивалентный).
2. **Stability**: `graph -> text -> graph -> text` стабильно на втором проходе.
3. **Preservation**: комментарии, `#region`, пустые строки и статические ID
   вне изменённого блока не меняются.
4. **Semantic equivalence**: после сохранения `DMCompiler.compile_string()`
   даёт те же `cues`, `lines` (по смыслу) и отсутствие новых ошибок.

Для гарантии №1 вводим «режим без изменений»: если граф не редактировался,
сохраняем исходный текст как есть, не прогоняя через сериализатор.

---

## 7. UI/UX редактора

### 7.1. Компоновка

```
┌────────────────────────────────────────────────────────────────────┐
│ [Graph]  intro.dialogue  [Add] [Arrange all nodes] [Test] [Localization] │
├────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────┐ ┌───────────────────┐ │
│ │                                          │ │ Inspector         │ │
│ │              GraphEdit                   │ │ ┌───────────────┐ │ │
│ │   ┌────────┐      ┌────────────┐         │ │ │ Character     │ │ │
│ │   │ ~start │─────▶│ Nathan: Hi │         │ │ │ [Nathan    ▼] │ │ │
│ │   └────────┘      └─────┬──────┘         │ │ ├───────────────┤ │ │
│ │                         │                │ │ │ Text          │ │ │
│ │                   ┌─────▼──────┐         │ │ │ [Hello!      ]│ │ │
│ │                   │  Choices   │         │ │ ├───────────────┤ │ │
│ │                   └──┬───┬───┬─┘         │ │ │ Tags          │ │ │
│ │                      │   │   │           │ │ │ [happy]       │ │ │
│ │                 ...  │   │   │           │ │ ├───────────────┤ │ │
│ │                      ▼   ▼   ▼           │ │ │ ID [GREETING] │ │ │
│ │                                          │ │ └───────────────┘ │ │
│ └──────────────────────────────────────────┘ └───────────────────┘ │
├────────────────────────────────────────────────────────────────────┤
│ Errors (main view) │ Cues (main view) │ Localization (dialog)        │
└────────────────────────────────────────────────────────────────────┘
```

### 7.2. Toolbar (фактическая реализация)

В `main_view`:

- кнопка **Graph** — переключает Text/Graph;
- остальные кнопки текстового редактора остаются как были.

В `DMGraphView`:

- **Add** — меню добавления узла (Dialogue, Response, Cue, Jump, Mutation,
  Comment);
- **Arrange all nodes** — собственный layered layout для всех узлов;
- **Test** — запуск с текущего cue/строки;
- **Localization** — диалог локализации;
- status label для сообщений о недопустимых связях.

`Zoom`, `Search`, `Save`, `Errors`, `Settings` в graph-toolbar не дублируются:
они доступны в основной панели редактора. `Split`-режим не реализован.

### 7.3. Настройки `GraphEdit` (фактическая реализация)

```gdscript
graph_edit.show_grid = true
graph_edit.set_show_arrange_button(false)
graph_edit.snapping_enabled = true
graph_edit.snapping_distance = 20
graph_edit.panning_scheme = GraphEdit.SCROLL_ZOOMS
graph_edit.zoom_min = 0.25
graph_edit.zoom_max = 2.0
graph_edit.minimap_enabled = true
graph_edit.right_disconnects = true
graph_edit.connection_lines_curvature = 0.5
graph_edit.connection_lines_thickness = 2.0
graph_edit.connection_lines_antialiased = true
```

Встроенная arrange-кнопка `GraphEdit` скрыта, потому что она раскладывает
только выбранные узлы. Вместо неё используется **Arrange all nodes**.

### 7.4. Внешний вид узлов

| Тип | Цвет | Иконка | Заголовок | Тело |
|---|---|---|---|---|
| CUE | синий | `Marker2D` | `~ start` | имя cue, счётчик переходов |
| DIALOGUE | зелёный | `TextFile` | `Nathan` | текст (2–3 строки), теги, ID |
| CHOICES | оранжевый | `GuiOptionButton` | `Choices` | список ответов |
| RESPONSE | жёлтый | `ArrowRight` | `Response` | prompt, условие |
| CONDITION | фиолетовый | `Branch` | `if` | выражение, ветки |
| MATCH | фиолетовый | `MatchCase` | `match` | выражение, кейсы |
| WHILE | фиолетовый | `Loop` | `while` | условие |
| MUTATION | серый | `Script` | `$>` | выражение |
| JUMP | красный | `ArrowRight` | `=>` | цель, тип |
| RANDOM | бирюзовый | `RandomNumberGenerator` | `%` | ветки, веса |
| CONCURRENT | зелёный пунктир | `TextFile` | `\| Coco` | текст |
| COMMENT | серый | `Comment` | `#` | текст |
| IMPORT | синий | `Load` | `import` | путь, алиас |

Цвета берём из темы редактора (`EditorInterface.get_editor_theme()`), чтобы
работали светлая и тёмная темы. Для кастомных цветов — настройка.

> **Фактически:** иконки в узлах сейчас не используются. Заголовок и цвет
> задаются в `DMGraphNodeView._get_kind_title()` / `_get_kind_color()`.
> Тело узла — это строки с портами; для реплик/ответов с inline-goto
> дополнительно показывается `→ target` / `↩ target`.

### 7.5. Взаимодействие (фактическая реализация)

- **Добавление**: правый клик по пустому месту → контекстное меню; или
  **Add** в toolbar. Добавляются Dialogue, Response, Cue, Jump, Mutation,
  Comment.
- **Соединение**: протянуть от выходного порта к входному. Поддерживаются
  `cue`, `END`/`END!` и любой top-level узел (для него автоматически
  создаётся `cue`). Branch-порты и вложенные узлы не соединяются.
- **Разрыв**: правый клик по связи. Работает для `JUMP`, `RETURN` и
  основного `FLOW`-продолжения. Для branch/body-связей показывается
  сообщение.
- **Выбор**: клик, `Shift`+клик, рамка (встроенная в `GraphEdit`).
- **Перемещение**: drag; позиция сохраняется в sidecar.
- **Удаление**: `Delete`; удаляется выбранный узел/блок без отдельного
  подтверждения.
- **Undo/Redo**: `Ctrl+Z` / `Ctrl+Y` через `EditorUndoRedoManager`.
- **Контекстное меню**: Add dialogue/response/cue/jump/mutation/comment,
  Delete selected, а для Condition/Match/Random — Add elif/else,
  Add when/else, Add random branch.
- **Zoom**: `Ctrl+wheel`, `+`/`-` (встроенное поведение `GraphEdit`).
- **Pan**: средняя кнопка мыши / `Space`+drag.
- **Arrange all nodes**: кнопка в toolbar; раскладывает весь граф.
- **Копирование/вставка, дублирование, поиск по графу, Outline** —
  в текущей версии не реализованы.

### 7.6. Инспектор (фактическая реализация)

Динамическая форма по типу узла. Поля:

- **Dialogue**: Character (LineEdit), Text (TextEdit), Tags (LineEdit),
  Static ID (LineEdit), Goto (LineEdit), Jump and return (CheckBox),
  Translator note (read-only TextEdit), Apply.
- **Response**: Character, Prompt, Tags, Condition, Goto, Jump and return,
  Static ID, Translator note (read-only), Apply.
- **Condition**: существующие кейсы с LineEdit выражения; Remove case для
  кейсов после первого; Add elif; Add else (если `else` ещё нет); Apply.
- **Match**: существующие `when`/`else` кейсы; Remove case (если кейсов > 1);
  Add when; Add else (если `else` ещё нет); Apply.
- **While**: условие (LineEdit), Apply.
- **Mutation**: выражение, чекбокс «блокирующая» (`$>` vs `$>>`), Apply.
- **Jump**: target (LineEdit), Jump and return (CheckBox), Apply.
- **Random**: ветки с Weight и Condition (LineEdit); Remove branch (если
  веток > 1); Add branch; Apply.
- **Cue**: имя, Apply.
- **Comment**: текст, Apply.
- **Import/Using**: read-only, доступно удаление узла.
- **Concurrent/Choices/End**: read-only, доступно удаление (кроме End).

Валидация выполняется компилятором: ошибки подсвечивают узлы и показываются
в основной панели ошибок. Отдельной per-field валидации в инспекторе нет.

### 7.7. Панели (фактическая реализация)

- **Errors**: основная панель ошибок `main_view`; клик по ошибке
  устанавливает caret и выбирает соответствующий узел графа.
- **Cues**: основной `CueList`; клик переходит к cue и выбирает cue-узел.
- **Localization**: отдельный диалог с таблицей
  `Static ID | Text | Character | Notes | Status | Preview`;
  кнопки **Generate IDs**, **Export CSV**, **Refresh**; клик по строке
  выбирает узел. Фильтров и отдельной кнопки Export POT нет — POT
  обрабатывается существующей локализацией Godot.
- **Outline** и **Search results** в графе не реализованы.

---

## 8. Интеграция с существующим плагином

### 8.1. Изменения в `plugin.gd`

Практически не нужны:

- `_has_main_screen()` остаётся `true`;
- `_get_plugin_name()` остаётся `"Dialogue"`;
- `_handles()` / `_edit()` остаются;
- `_apply_changes()` / `_get_unsaved_status()` / `_save_external_data()` остаются.

Фактически добавлено только:

- в `_on_file_removed()` — `DMGraphSidecar.remove(file)`;
- остальная интеграция находится в `main_view.gd` (см. 8.3).

Пункт меню `Dialogue -> Open graph` и настройка «открывать граф по умолчанию»
не добавлялись.

### 8.2. Изменения в `main_view.tscn`

`main_view.tscn` **не менялся**. `GraphView` и кнопка **Graph** создаются
программно в `main_view.gd`:

- кнопка **Graph** добавляется в существующий `CodePanel/Toolbar`;
- `views/graph_view.tscn` инстанцируется и добавляется в `CodePanel` перед
  `ErrorsPanel`;
- инспектор и toolbar находятся внутри `GraphView`;
- отдельного `ViewModeBar`, `GraphBottomPanel` и `Outline` нет.

### 8.3. Изменения в `main_view.gd`

Фактически добавлены:

```gdscript
var graph_view: DMGraphView
var graph_toggle_button: Button
```

`_setup_graph_view()` создаёт кнопку **Graph**, инстанцирует
`views/graph_view.tscn`, добавляет его в `CodePanel` и подключает сигналы:

```gdscript
graph_view.text_changed.connect(_on_graph_text_changed)
graph_view.test_requested.connect(_on_graph_test_requested)
graph_view.error_selected.connect(_on_graph_error_selected)
```

`_on_graph_toggle_toggled(pressed)`:

- скрывает/показывает `CodeEdit`;
- скрывает `SearchAndReplace`;
- загружает документ в граф;
- вызывает `compile()` для подсветки ошибок.

`node_selected` не подключается; `ViewMode`/`Split` не реализованы.

В `open_file(path)` после загрузки текста:

```gdscript
graph_view.load_document(path, text)
```

В `_on_code_edit_text_changed()`:

```gdscript
if not graph_view.is_syncing:
    graph_view.sync_from_text(code_edit.text)
```

Новый метод:

```gdscript
func apply_graph_text(new_text: String, description: String = "Graph edit") -> void:
    if new_text == code_edit.text:
        return

    var old_text: String = code_edit.text
    var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
    undo_redo.create_action(description)
    undo_redo.add_do_method(self, "_set_buffer_text", current_file_path, new_text)
    undo_redo.add_undo_method(self, "_set_buffer_text", current_file_path, old_text)
    undo_redo.commit_action()


func _set_buffer_text(path: String, text: String) -> void:
    if not open_buffers.has(path):
        return

    open_buffers[path].text = text
    if path == current_file_path:
        var cursor: Vector2 = code_edit.get_cursor()
        var scroll: float = code_edit.scroll_vertical
        code_edit.text = text
        code_edit.set_cursor(cursor)
        code_edit.scroll_vertical = scroll
        _on_code_edit_text_changed()
```

В `compile()`:

```gdscript
graph_view.set_errors(result.errors)
```

В `go_to_cue()` / `go_to_line_number()`:

```gdscript
graph_view.select_cue(cue)
graph_view.select_line(line_number)
```

В `_on_cache_file_content_changed()`:

```gdscript
if is_instance_valid(graph_view) and graph_view.visible:
    graph_view.sync_from_text(new_content)
    compile()
```

В `_on_files_moved()`:

```gdscript
graph_view.move_sidecar(old_file, new_file_path)
```

В `_on_file_removed()`:

```gdscript
graph_view.remove_sidecar(file)
```

### 8.4. Синхронизация буферов

Правила (фактическая реализация):

1. **Текст → граф**: при изменении `code_edit.text` запускается существующий
   `ParseTimer` (1 секунда). В `_on_parse_timer_timeout()` граф сначала
   синхронизируется, затем вызывается `compile()`. Курсор и скролл текста
   не трогаются.
2. **Граф → текст**: при изменении графа вызывается `apply_graph_text()`,
   который обновляет буфер и `code_edit.text`, сохраняя курсор/скролл.
3. **Защита от циклов**: используется флаг `is_syncing` в `graph_view`.
   Пока он установлен, встречные `sync_from_text()` игнорируются.
4. **Dirty state**: граф не хранит своё «грязное» состояние отдельно; источник
   правды — `open_buffers[path].text != pristine_text`. Это работает в
   `count_unsaved_files()` и `_get_unsaved_status()`.
5. **Внешние изменения**: `_on_cache_file_content_changed()` обновляет
   `code_edit.text` и граф, если буфер не грязный, и вызывает `compile()`.
   Отдельного диалога-предупреждения при грязном буфере нет.

### 8.5. Сохранение

`save_file()` не меняется: он сохраняет `open_buffers[path].text`. Граф уже
записал свои изменения в этот буфер. После сохранения:

- `DMCache.mark_files_for_reimport([path])`;
- `EditorInterface.get_resource_filesystem().scan()`;
- sidecar сохраняется отдельно при перемещении узла (`_on_end_node_move()`)
  и при **Arrange all nodes**; при простом открытии файла sidecar не создаётся.

### 8.6. Тестовый запуск

`main_view.run_test_scene(from_key)` уже умеет запускать с cue или номера строки.

В графе кнопка **Test**:

- для `CUE` → `run_test_scene(cue_name)`;
- для остальных узлов → `run_test_scene(str(source_line))`;
- для `END`-узлов (`source_start < 0`) — ничего не делает.

### 8.7. Поиск и переходы

- `DMPlugin.show_find_in_dialogue()` открывает файл и выделяет текст.
  `go_to_line_number()` выбирает узел, содержащий эту строку.
- `go_to_cue()` выбирает cue-узел и центрирует его.
- Клик по ошибке в основной панели ошибок также выбирает узел графа.
- `Find references` для cue в текущей версии не реализован.

### 8.8. Undo/Redo

Используется `EditorUndoRedoManager`:

```gdscript
var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
undo_redo.create_action(description)
undo_redo.add_do_method(self, "_set_buffer_text", current_file_path, new_text)
undo_redo.add_undo_method(self, "_set_buffer_text", current_file_path, old_text)
undo_redo.commit_action()
```

Фактически хранится не патч, а полный старый и новый текст буфера.
`_set_buffer_text()` обновляет `open_buffers`, `code_edit.text`, запускает
перекомпиляцию и синхронизирует граф.

Undo-стек текстового редактора и графа раздельный: графовые изменения идут
через `EditorUndoRedoManager`, текстовый редактор использует свой встроенный
undo. Это осознанное ограничение текущей версии.

---

## 9. Поддержка функционала аддона

### 9.1. Матрица возможностей

| Возможность | Представление в графе | Редактирование | Валидация | Runtime |
|---|---|---|---|---|
| Реплики | `DIALOGUE` | текст, персонаж, теги, ID, goto, jump-and-return; заметка read-only | ошибки компилятора | без изменений |
| Ответы | `CHOICES` + `RESPONSE` | prompt, персонаж, теги, условие, goto, jump-and-return, ID | ошибки компилятора | без изменений |
| Условия `if/elif/else` | `CONDITION` | выражения существующих кейсов; add/remove кейсов | ошибки компилятора | без изменений |
| `match/when/else` | `MATCH` | выражения `when`; add/remove кейсов | ошибки компилятора | без изменений |
| `while` | `WHILE` | условие | ошибки компилятора | без изменений |
| Мутации `$>`, `$>>`, `do`, `set` | `MUTATION` | выражение, блокирующая | ошибки компилятора | без изменений |
| Случайные строки `%` | `RANDOM` | вес и условие веток; add/remove веток | ошибки компилятора | без изменений |
| `cue` | `CUE` | имя | ошибки компилятора | без изменений |
| `=>` / `=><` | `JUMP` | цель, тип | ошибки компилятора | без изменений |
| `=> END` / `=> END!` | `JUMP` | read-only | — | без изменений |
| Импорты | `IMPORT` + внешние cue | read-only, удаление узла | ошибки компилятора | без изменений |
| `using` | `USING` | read-only, удаление узла | ошибки компилятора | без изменений |
| Теги `[#tag]` | поле `Tags` | список в Dialogue/Response | — | без изменений |
| Одновременные реплики `\|` | `CONCURRENT` | read-only, удаление узла | ошибки компилятора | без изменений |
| Inline BBCode | поле `Text` | текст | — | без изменений |
| Inline-мутации | поле `Text` | текст (отдельного списка нет) | ошибки компилятора | без изменений |
| Статические ID `[ID:...]` | поле `Static ID` | текст; Generate IDs в Localization | дубликат/отсутствие — в панели | без изменений |
| Заметки `##` | поле `Translator note` | read-only; редактируются в тексте | — | без изменений |
| Имена персонажей | LineEdit | текст (без ComboBox/autocomplete) | — | без изменений |
| Выражения в тексте `{{...}}` | поле `Text` | текст | ошибки компилятора | без изменений |
| Динамические переходы `=> {{...}}` | `JUMP` | target как текст | ошибки компилятора | без изменений |
| Dialogue processor | — | — | не обрабатывается отдельно | без изменений |
| Тестовая сцена | кнопка `Test` | — | — | без изменений |
| Поиск | основная панель поиска | — | — | без изменений |
| Ошибки | основная панель + подсветка узлов | — | — | без изменений |
| POT/CSV | Localization dialog | Generate IDs, Export CSV | — | без изменений |
| C# | — | — | — | без изменений |

### 9.2. Что важно не сломать

- **Импортёр** `DMImportPlugin` читает `.dialogue` и компилирует. Граф пишет
  только текст, поэтому импортёр не меняется.
- **Runtime** `DialogueResource` / `DialogueManager` не меняются.
- **POT-парсер** `DMTranslationParserPlugin` читает `.dialogue`. Граф должен
  сохранять `[ID:...]`, `##`-заметки и имена персонажей.
- **CSV-экспорт** `DMTranslationUtilities.export_all_translations_to_csv()`
  читает `.dialogue`. Граф не должен менять структуру строк без необходимости.
- **Тестовая сцена** `test_scene.tscn` использует `run_key` и
  `run_resource_path`. Граф вызывает тот же `run_test_scene()`.
- **Настройки** `DMSettings` — добавляем новые ключи, не меняя существующие.

---

## 10. Локализация

### 10.1. Что уже есть

- Статические ID `[ID:KEY]` на репликах и ответах.
- Заметки переводчикам `##`.
- Имена персонажей в списке переводимых строк (настройка).
- POT-экспорт через `DMTranslationParserPlugin`.
- CSV-экспорт через `DMTranslationUtilities`.
- Настройки `USE_STATIC_IDS_AS_TRANSLATION_KEYS`,
  `MISSING_TRANSLATIONS_ARE_ERRORS`,
  `INCLUDE_CHARACTERS_IN_TRANSLATABLE_STRINGS_LIST`.

### 10.2. Что добавляет граф (фактическая реализация)

- Поле `Static ID` в инспекторе реплики/ответа.
- Диалог **Localization**:
  - таблица строк: `Static ID`, `Text`, `Character`, `Notes`, `Status`,
    `Preview`;
  - статус: `OK`, `Missing ID`, `Duplicate ID`;
  - `Preview` через `TranslationServer.translate(static_id)`; если перевод
    не загружен — `(not translated)`;
  - переход к узлу по клику;
  - кнопка **Generate IDs** — вызывает
    `DMTranslationUtilities.generate_static_line_ids_for_text()` для текущего
    текста файла;
  - кнопка **Export CSV** — открывает существующий CSV-диалог аддона;
  - кнопка **Refresh**.
- Подсветка узлов: только ошибки компилятора (красный `modulate`).
  Отдельной жёлтой/красной/серой подсветки по статусу ID нет — статус
  показывается в таблице локализации.
- Отдельной кнопки **Export POT** нет: POT обрабатывается существующей
  локализацией Godot, а `.dialogue`-файлы уже добавляются в
  `translations_pot_files` плагином.

### 10.3. Правила сохранения (фактическая реализация)

- При изменении текста реплики `[ID:...]` сохраняется: сериализатор берёт
  `static_id` из свойств узла и записывает его обратно.
- `##`-заметка находится на строке выше и не затрагивается при правке
  реплики/ответа.
- При изменении текста с существующим ID диалог не предлагается; ID
  сохраняется, пока пользователь не изменит поле `Static ID`.
- При удалении узла с ID отдельного предупреждения нет.
- Дублирование узлов и вставка из другого файла в текущей версии не
  реализованы, поэтому проверка конфликтов ID при этих операциях не
  выполняется.

### 10.4. Локализация самого редактора

Строки UI графа пока **не добавлены** в `l10n/*.po`; подписи кнопок и
инспектора сейчас английские и заданы прямо в `graph_view.gd` /
`dialogue_graph_node_view.gd`. Для полноценной локализации редактора нужно
вынести их в `DMConstants.translate(&"graph....")` и добавить ключи в
`en.po`, `es.po`, `uk.po`, `zh.po`, `zh_TW.po`.

---

## 11. Валидация и ошибки

### 11.1. Ошибки компилятора

`DMCompilerResult.errors` — массив `DMError` с `line_number`, `column_number`,
`error`. Маппим `line_number` на узел:

Фактическая реализация:

```gdscript
func set_errors(errors: Array[DMError]) -> void:
    last_errors = errors
    if document != null:
        document.errors = errors
    _apply_errors()

func _apply_errors() -> void:
    for node_id: String in node_views:
        var view: DMGraphNodeView = node_views[node_id]
        var graph_node: DMGraphNode = document.get_node(node_id)
        var has_error: bool = false
        for error: DMError in last_errors:
            var source_line: int = error.line_number - 1
            if graph_node.source_start <= source_line and source_line <= graph_node.source_end:
                has_error = true
                break
        view.set_error_state(has_error)
```

Визуально:

- узел с ошибкой получает красный `modulate`;
- tooltip `Has errors`;
- клик по ошибке в основной панели ошибок выбирает узел графа;
- отдельной иконки ошибки и фокуса на конкретном поле нет.

### 11.2. Графовые предупреждения

В текущей версии отображаются **только ошибки компилятора**. Перечисленные
ниже проверки — план на будущее, отдельного graph-validator нет:

- недостижимый узел;
- пустая ветка;
- осиротевший cue;
- цикл без выхода;
- динамический переход;
- импорт без использования;
- слишком большой граф.

Дубликаты/отсутствие static ID видны в панели **Localization** как
`Duplicate ID` / `Missing ID`.

### 11.3. Панель ошибок

Используется существующая панель ошибок `main_view`:

- список `DMError` с номером строки и сообщением;
- клик по ошибке ставит caret в текстовом редакторе и выбирает узел графа;
- отдельных фильтров, кнопки `Recompile` и счётчика в graph-toolbar нет.

---

## 12. Производительность

### 12.1. Целевые показатели

| Размер файла | Узлов | Время построения | Время перестроения |
|---|---|---|---|
| 50 строк | ~30 | < 50 мс | < 30 мс |
| 200 строк | ~120 | < 150 мс | < 80 мс |
| 500 строк | ~300 | < 400 мс | < 200 мс |
| 1000 строк | ~600 | < 1 с | < 500 мс |

### 12.2. Меры (фактическая реализация)

- **Debounce** — существующий `ParseTimer` (1 секунда) для текстовых
  изменений; граф синхронизируется в `_on_parse_timer_timeout()`.
- **Полная перестройка графа** при каждом изменении текста. Инкрементального
  обновления и кэша `text_hash` пока нет.
- **Собственный layered layout** вместо `GraphEdit.arrange_nodes()`.
- **Sidecar** читается при открытии/синхронизации и сохраняется при
  перемещении узла или **Arrange all nodes**.
- **`is_building`** предотвращает сохранение sidecar во время авто-раскладки.
- **`is_syncing`** предотвращает рекурсивную синхронизацию текста и графа.
- **Compact mode, Focus mode, отключение minimap, ленивая загрузка,
  инкрементальный undo** — не реализованы.

---

## 13. Тестирование

### 13.1. Unit-тесты (фактическая реализация)

Добавлены в `tests/`:

- `test_graph_builder.gd`:
  - `builds basic dialogue`;
  - `builds responses`;
  - `builds conditions`;
  - `builds match`;
  - `builds while`;
  - `builds random`;
  - `builds concurrent lines`;
  - `builds imports`.
- `test_graph_serializer.gd`:
  - `sets dialogue properties`;
  - `sets response properties`;
  - `renames cue and updates jumps`;
  - `sets jump target`;
  - `adds dialogue after`;
  - `adds response after`;
  - `deletes node`;
  - `sets condition cases`;
  - `sets match cases`;
  - `sets while expression`;
  - `sets random branches`;
  - `clears inline goto`;
  - `adds cue before`;
  - `adds condition case`;
  - `removes condition case`;
  - `adds match case`;
  - `removes match case`;
  - `adds random branch`;
  - `removes random branch`;
  - `round trip without changes`.

Отдельных `test_graph_roundtrip.gd` и `test_graph_validation.gd` нет:
round-trip проверяется внутри serializer-тестов, а graph-validator не
реализован.

### 13.2. Интеграционные тесты

Автоматизированных интеграционных тестов нет. Проверялось smoke-скриптами:

- открытие `.dialogue` и построение графа;
- построение инспектора для всех типов узлов;
- соединение с top-level узлом и обратное соединение;
- соединение из ответа;
- отсоединение;
- добавление/удаление condition/match/random-кейсов;
- панель локализации и preview;
- запуск editor без script errors/warnings.

### 13.3. Ручная тест-матрица

Фактически проверено:

- Godot **4.7.2**, Windows, headless editor;
- `tests/main.dialogue`, `tests/snippets.dialogue`, `test.dialogue`;
- сложный диалог с condition/match/while/random/concurrent/import.

Не проверялось в этой сессии:

- Godot 4.6;
- Linux/macOS;
- светлая/тёмная тема в интерактивном режиме;
- C#-проект;
- высокий DPI;
- большой файл 500+ строк.

### 13.4. Критерии приёмки

- [x] Граф открывается для `.dialogue` без script errors.
- [x] Все основные типы строк отображаются узлами.
- [x] Изменения в графе сохраняются в текст и компилируются.
- [x] `text -> graph -> text` не меняет файл, если граф не редактировали
      (проверено на простом диалоге).
- [x] Условия, `match`, `while`, `random`, ответы, переходы, импорты,
      одновременные реплики поддерживаются.
- [x] Статические ID и заметки сохраняются.
- [x] CSV-экспорт доступен; POT — через существующую локализацию Godot.
- [x] Тестовый запуск работает с узла.
- [x] Undo/Redo работает через `EditorUndoRedoManager`.
- [x] Ошибки компилятора подсвечиваются на узлах.
- [x] Граф не ломает существующий текстовый редактор.
- [ ] Производительность на больших файлах не измерялась.

---

## 14. Пошаговый план реализации

### Этап 0. Подготовка (0.5–1 день)

1. Создать ветку `feature/visual-graph-editor`.
2. Зафиксировать решение: text-first, sidecar, интеграция в `main_view`.
3. Собрать корпус `.dialogue`-файлов для round-trip-тестов.
4. Добавить пустые классы/файлы и настройки, чтобы не ломать сборку.
5. Проверить, что проект открывается в Godot 4.6/4.7.

**Результат:** структура папок, настройки, тестовый корпус.

### Этап 1. Модель и source ranges (2–3 дня)

1. Создать `graph/dialogue_graph_document.gd`, `dialogue_graph_node.gd`,
   `dialogue_graph_edge.gd`, `dialogue_graph_sidecar.gd`.
2. Добавить `next_id_after` в `to_data()` для response/dialogue/random.
3. Восстанавливать source line из line ID и сырых строк.
4. Написать `DMGraphBuilder` (без UI).
5. Unit-тесты на построение.

**Результат:** текст → `DMGraphDocument` с узлами, рёбрами и source ranges.

### Этап 2. Read-only граф (2–3 дня)

1. Создать `views/graph_view.tscn` и `graph_view.gd`.
2. Добавить `GraphEdit` и `DMGraphNodeView`.
3. Отрисовать узлы и связи.
4. Добавить собственный layered layout (`_arrange_graph`).
5. Добавить кнопку **Graph** в `main_view`.
6. Синхронизировать открытие файла и выбор узла.
7. Sidecar: чтение/запись позиций.

**Результат:** можно открыть диалог и посмотреть его графом.

### Этап 3. Редактирование ядра (4–6 дней)

1. Инспектор для `DIALOGUE`, `RESPONSE`, `CUE`, `JUMP`.
2. Изменение текста/персонажа/тегов/ID.
3. Добавление/удаление реплик и ответов.
4. Переходы на cue.
5. `DMGraphSerializer` с точечными текстовыми операциями.
6. Синхронизация граф → текст → компиляция.
7. Undo/Redo.
8. Тесты round-trip.

**Результат:** можно создавать и редактировать простые диалоги.

### Этап 4. Продвинутые узлы (5–7 дней)

1. `CONDITION` с `if/elif/else`.
2. `MATCH` с `when/else`.
3. `WHILE` с телом и обратной связью.
4. `RANDOM` с весами и условиями.
5. `MUTATION`.
6. `CONCURRENT`.
7. `IMPORT` и внешние cue.
8. `USING`.
9. Валидация и предупреждения.

**Результат:** поддержан весь синтаксис аддона.

### Этап 5. Локализация и ошибки (3–4 дня)

1. Панель `Localization`.
2. Генерация ID.
3. Подсветка missing/duplicate.
4. Предпросмотр перевода.
5. Экспорт CSV/POT.
6. Маппинг ошибок компилятора на узлы.
7. Панель ошибок и переходы.

**Результат:** локализация работает из графа.

### Этап 6. Полировка (частично)

Реализовано:

- [x] Контекстное меню (Add, Delete, Add elif/else, Add when/else,
      Add random branch).
- [x] Multi-select средствами `GraphEdit`.
- [x] Темизация через цвета узлов и портов.
- [x] **Arrange all nodes**.
- [x] Панель **Localization**.

Не реализовано:

- [ ] Copy/Paste/Duplicate.
- [ ] Поиск по графу.
- [ ] Группы/фреймы.
- [ ] Комментарии-стикеры.
- [ ] Compact/Focus mode.
- [ ] Настройки graph-режима.
- [ ] Локализация UI графа.

**Результат:** базовый повседневный инструмент; часть полировки — в плане.

### Этап 7. Тестирование и документация (3–4 дня)

1. Полный прогон unit/integration.
2. Ручная тест-матрица.
3. Производительность.
4. Документация `docs/Visual_Editor.md`.
5. Обновление README.
6. Скриншоты/GIF.
7. Ревью и merge.

**Результат:** готовый к использованию редактор.

### Ориентировочные сроки

| Этап | Дни |
|---|---|
| 0. Подготовка | 0.5–1 |
| 1. Модель и source ranges | 2–3 |
| 2. Read-only граф | 2–3 |
| 3. Редактирование ядра | 4–6 |
| 4. Продвинутые узлы | 5–7 |
| 5. Локализация и ошибки | 3–4 |
| 6. Полировка | 4–5 |
| 7. Тестирование и документация | 3–4 |
| **Итого** | **~24–33 дня** |

Для одного разработчика — примерно 5–7 недель с учётом ревью и непредвиденных
задач. MVP (этапы 0–3) — около 2–3 недель.

> Оценки выше — исходные проектные. Фактическая реализация выполнена в рамках
> текущей сессии; фактический объём и коммиты см. в разделе 21.

---

## 15. Риски и меры

| Риск | Вероятность | Влияние | Мера |
|---|---|---|---|
| Round-trip теряет комментарии/форматирование | Высокая | Высокое | Точечные патчи, «режим без изменений», тесты на корпусе |
| Нестабильные ID узлов | Высокая | Среднее | `stable_key` + source line + parent key, sidecar с версией |
| Производительность `GraphEdit` на больших файлах | Средняя | Среднее | Compact/Focus mode, debounce, лимиты, предупреждения |
| Невозможные в тексте связи | Средняя | Высокое | Ограничения связей, валидация, snap-back |
| Конфликт с dialogue processor | Низкая | Среднее | Предупреждение, граф работает с raw-текстом |
| Два undo-стека (текст и граф) | Средняя | Среднее | Документировать; позже унифицировать |
| Изменения API Godot 4.6/4.7 | Средняя | Среднее | Абстракция над `GraphEdit`, тесты на обеих версиях |
| Потеря статических ID при редактировании | Средняя | Высокое | Явные правила сохранения ID, тесты |
| Конфликты sidecar в git | Низкая | Низкое | Sidecar опционален, версия формата, merge-стратегия |
| Сложность поддержки всех синтаксисов | Высокая | Высокое | Поэтапный план, MVP, тесты на каждый синтаксис |

---

## 16. Решённые вопросы

Вопросы из исходного плана закрыты фактической реализацией:

1. **Источник правды.** `.dialogue` остаётся текстом; graph-first не вводился.
2. **Режим интеграции.** Text/Graph в существующей вкладке **Dialogue**;
   `Split` не реализован.
3. **MVP.** Реализованы и ядро, и продвинутые узлы: condition/match/while/
   random, ответы, переходы, импорты, concurrent, локализация.
4. **Sidecar.** Хранится рядом с файлом: `<file>.dialogue.graph.json`.
5. **Auto-layout.** Используется собственный layered layout; встроенная
   arrange-кнопка `GraphEdit` скрыта.
6. **Ограничения связей.** Основные flow-узлы можно соединять с любым
   top-level узлом через автосоздание `cue`; branch-порты остаются
   текстовыми ветками.
7. **Локализация.** Панель **Localization** и preview через
   `TranslationServer.translate()` реализованы.
8. **C#.** Отдельной работы не требуется: граф editor-only и работает с
   текстом.

Все вопросы закрыты фактической реализацией: text-first, Text/Graph,
sidecar рядом с файлом, собственный layered layout, соединения через
автосоздание cue, панель локализации с preview.

---

## 17. Приложения

### A. Пример диалога и соответствующего графа

```dialogue
~ start
Nathan: Hello! [#happy] [ID:GREETING]
Nathan: How are you?
- Good
    Nathan: Great!
- Bad [if player.health < 10 /]
    Nathan: Oh no.
- Leave => END
Nathan: Anyway...
=> END
```

Граф:

```
[CUE ~start]
    │
    ▼
[DIALOGUE Nathan: Hello!]
    │
    ▼
[DIALOGUE Nathan: How are you?]
    │
    ▼
[CHOICES]
    ├── Good ──────▶ [DIALOGUE Nathan: Great!] ──┐
    ├── Bad (if) ──▶ [DIALOGUE Nathan: Oh no.] ──┤
    └── Leave ─────▶ [JUMP => END]               │
                                                  ▼
                                        [DIALOGUE Nathan: Anyway...]
                                                  │
                                                  ▼
                                            [JUMP => END]
```

### B. Пример sidecar

См. раздел 4.5.

### C. Полезные API Godot

- `GraphEdit`: `connect_node()`, `disconnect_node()`, `get_connection_list()`,
  `connection_request`, `disconnection_request`, `node_selected`,
  `popup_request`, `delete_nodes_request`, `begin_node_move`, `end_node_move`,
  `set_show_arrange_button(false)`, `set_connection_activity()`,
  `minimap_enabled`, `snapping_enabled`, `snapping_distance`, `zoom`,
  `scroll_offset`.
- `GraphNode`: `set_slot()`, `title`, `position_offset`, `size`, `resizable`,
  `draggable`, `selectable`, `get_input_port_count()`,
  `get_output_port_count()`.
- `GraphElement`: используется для фильтрации детей `GraphEdit` при очистке
  (не удалять внутренний connection layer).
- `EditorUndoRedoManager`: `create_action()`, `add_do_method()`,
  `add_undo_method()`, `commit_action()`.
- `GraphElement`: базовый класс для кастомных элементов.
- `GraphFrame`: визуальные группы.
- `EditorUndoRedoManager`: `create_action()`, `add_do_method()`,
  `add_undo_method()`, `commit_action()`.
- `EditorInterface`: `get_editor_undo_redo()`, `get_editor_theme()`,
  `get_resource_filesystem()`, `edit_resource()`, `set_main_screen_editor()`.
- `DMPlugin`: `open_file()`, `open_file_at_cue()`, `open_file_at_line()`,
  `show_find_in_dialogue()`.

### D. Ссылки на файлы проекта

- `addons/dialogue_manager/plugin.gd`
- `addons/dialogue_manager/views/main_view.gd`
- `addons/dialogue_manager/views/main_view.tscn`
- `addons/dialogue_manager/compiler/compiler.gd`
- `addons/dialogue_manager/compiler/compilation.gd`
- `addons/dialogue_manager/compiler/compiled_line.gd`
- `addons/dialogue_manager/compiler/compiler_result.gd`
- `addons/dialogue_manager/import_plugin.gd`
- `addons/dialogue_manager/dialogue_resource.gd`
- `addons/dialogue_manager/utilities/translations.gd`
- `addons/dialogue_manager/editor_translation_parser_plugin.gd`
- `addons/dialogue_manager/settings.gd`
- `addons/dialogue_manager/constants.gd`
- `tests/` — тестовый раннер и примеры диалогов
- `docs/Basic_Dialogue.md`, `docs/Conditions_Mutations.md`,
  `docs/Translations.md`, `docs/State.md`, `docs/Nodes.md`,
  `docs/Using_Dialogue.md`

---

## 18. Конкретные сигнатуры классов

Ниже — рабочие сигнатуры, по которым будет писаться код. Все классы editor-only,
`@tool`, с префиксом `DM`, в стиле аддона.

### 18.1. Модель

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_node.gd
@tool
class_name DMGraphNode extends RefCounted

enum Kind {
    CUE, DIALOGUE, CHOICES, RESPONSE, CONDITION, MATCH, WHILE,
    MUTATION, JUMP, RANDOM, CONCURRENT, COMMENT, IMPORT, USING, NOTE
}

var id: String = ""
var kind: Kind = Kind.DIALOGUE
var stable_key: String = ""
var source_start: int = -1          # 0-based, включительно
var source_end: int = -1            # 0-based, включительно
var indent: int = 0
var parent_id: String = ""
var children: PackedStringArray = []
var ports: Array[Dictionary] = []   # { name, kind, color }
var properties: Dictionary = {}
var position: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2.ZERO
var collapsed: bool = false

func _init(initial_id: String = "", initial_kind: Kind = Kind.DIALOGUE) -> void
func get_property(key: String, default: Variant = null) -> Variant
func set_property(key: String, value: Variant) -> void
func add_port(port_name: String, port_kind: String, color: Color = Color.WHITE) -> int
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> DMGraphNode
```

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_edge.gd
@tool
class_name DMGraphEdge extends RefCounted

enum Kind { FLOW, BRANCH, JUMP, RETURN, IMPORT, CONCURRENT }

var from_node: String = ""
var from_port: int = 0
var to_node: String = ""
var to_port: int = 0
var kind: Kind = Kind.FLOW
var label: String = ""

func _init(
    initial_from_node: String = "",
    initial_from_port: int = 0,
    initial_to_node: String = "",
    initial_to_port: int = 0,
    initial_kind: Kind = Kind.FLOW,
    initial_label: String = ""
) -> void
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> DMGraphEdge
```

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_document.gd
@tool
class_name DMGraphDocument extends RefCounted

var path: String = ""
var text: String = ""
var nodes: Dictionary = {}          # String -> DMGraphNode
var edges: Array[DMGraphEdge] = []
var cues: Dictionary = {}           # cue -> node_id
var line_nodes: Dictionary = {}     # compiled line id -> node id
var response_groups: Dictionary = {} # first response id -> choices node id
var first_cue: String = ""
var imports: Array[Dictionary] = []
var using_states: PackedStringArray = []
var errors: Array[DMError] = []
var source_lines: PackedStringArray = []

func get_node(node_id: String) -> DMGraphNode
func add_node(node: DMGraphNode) -> void
func remove_node(node_id: String) -> void
func add_edge(edge: DMGraphEdge) -> void
func get_edges_from(node_id: String) -> Array[DMGraphEdge]
func get_edges_to(node_id: String) -> Array[DMGraphEdge]
func find_node_for_line(line_number: int) -> DMGraphNode
func find_cue_node(cue: String) -> DMGraphNode
func to_dict() -> Dictionary
```

### 18.2. Построение и сериализация

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_builder.gd
@tool
class_name DMGraphBuilder extends RefCounted

static func build(text: String, path: String) -> DMGraphDocument
static func _extract_imports(lines: PackedStringArray) -> Array[Dictionary]
static func _build_file_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _build_cue_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _find_cue_line(lines: PackedStringArray, cue: String) -> int
static func _build_line_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _make_dialogue_node(...) -> DMGraphNode
static func _make_response_node(...) -> DMGraphNode
static func _make_choices_node(...) -> DMGraphNode
static func _make_condition_node(...) -> DMGraphNode
static func _make_match_node(...) -> DMGraphNode
static func _find_match_case_line(doc, case, source_start, source_end) -> int
static func _extract_when_expression(raw_line: String) -> String
static func _make_while_node(...) -> DMGraphNode
static func _make_mutation_node(...) -> DMGraphNode
static func _make_jump_node(...) -> DMGraphNode
static func _make_random_node(...) -> DMGraphNode
static func _find_random_branch_lines(doc, source_start, indent) -> Array[int]
static func _extract_random_condition(raw_line: String) -> String
static func _make_concurrent_node(...) -> DMGraphNode
static func _build_edges(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _add_end_nodes(doc: DMGraphDocument) -> void
static func _get_flow_port(node: DMGraphNode) -> int
static func _get_return_port(node: DMGraphNode) -> int
static func _add_flow(doc, node, line_id, port = 0) -> void
static func _add_branch(doc, node, port, line_id) -> void
static func _add_branch_to_node(doc, node, port, target_node_id) -> void
static func _add_jump(doc, node, target) -> void
static func _add_return(doc, node, line_id) -> void
static func _target_node_id(doc, line_id) -> String
static func _cue_target_node_id(doc, target) -> String
static func _add_edge_if_missing(doc, edge) -> void
static func _source_line_for_id(line_id: String) -> int
static func _find_block_end(lines, start_line, indent) -> int
static func _indent_count(line: String) -> int
static func _stable_key(line: Dictionary, _index: int) -> String
static func _extract_goto(raw_line: String) -> String
static func _extract_condition(raw_line: String) -> String
static func _extract_mutation(raw_line: String) -> String
```

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_serializer.gd
@tool
class_name DMGraphSerializer extends RefCounted

static func set_dialogue_properties(text, node, properties) -> String
static func set_response_properties(text, node, properties) -> String
static func set_cue_name(text, node, new_name) -> String
static func set_jump_target(text, node, target, is_snippet) -> String
static func set_inline_goto(text, node, target, is_snippet) -> String
static func clear_inline_goto(text, node) -> String
static func set_mutation_expression(text, node, expression, is_blocking) -> String
static func set_comment_text(text, node, comment) -> String
static func set_condition_cases(text, node, cases) -> String
static func set_match_cases(text, node, cases) -> String
static func set_while_expression(text, node, expression) -> String
static func set_random_branches(text, node, branches) -> String
static func add_condition_case(text, node, expression, is_else) -> String
static func remove_condition_case(text, node, case_index) -> String
static func add_match_case(text, node, expression, is_else) -> String
static func remove_match_case(text, node, case_index) -> String
static func add_random_branch(text, node, weight, condition) -> String
static func remove_random_branch(text, node, branch_index) -> String
static func add_dialogue_after(text, node, character, dialogue) -> String
static func add_response_after(text, node, prompt) -> String
static func add_cue(text, cue) -> String
static func add_cue_before(text, node, cue) -> String
static func add_jump_after(text, node, target, is_snippet) -> String
static func add_mutation_after(text, node, expression, is_blocking) -> String
static func add_comment_after(text, node, comment) -> String
static func delete_node(text, node) -> String
static func replace_lines(text, start_line, end_line, replacement) -> String
static func insert_lines(text, at, new_lines) -> String
static func delete_lines(text, start_line, end_line) -> String
static func _line_indent(line) -> String
static func _format_dialogue_line(character, dialogue, tags, static_id, goto = "", goto_is_snippet = false) -> String
static func _format_response_line(prompt, condition, goto, static_id, goto_is_snippet = false, character = "", tags = []) -> String
static func _format_weight(weight: float) -> String
static func _clean_expression(expression: String) -> String
static func _random_branch_content(raw_text: String) -> String
```

### 18.3. Sidecar

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_sidecar.gd
@tool
class_name DMGraphSidecar extends RefCounted

const VERSION: int = 1

static func get_path(dialogue_path: String) -> String
static func load_for(dialogue_path: String) -> Dictionary
static func save_for(dialogue_path: String, document: DMGraphDocument) -> void
static func move(old_path: String, new_path: String) -> void
static func remove(path: String) -> void
static func apply_to_document(document: DMGraphDocument, data: Dictionary) -> void
static func collect_from_document(document: DMGraphDocument) -> Dictionary
```

### 18.4. View

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_node_view.gd
@tool
class_name DMGraphNodeView extends GraphNode

var graph_node: DMGraphNode
var document: DMGraphDocument

func setup(node: DMGraphNode, doc: DMGraphDocument) -> void
func refresh() -> void
func set_error_state(has_error: bool) -> void
func get_port_slot_offset() -> int
func _add_goto_label(node: DMGraphNode) -> void
func _add_plain_label(text: String) -> void
func _add_port_row(text: String, has_input: bool, has_output: bool, color: Color) -> HBoxContainer
func _get_kind_color(kind: DMGraphNode.Kind) -> Color
func _get_kind_title(kind: DMGraphNode.Kind) -> String
static func _short(text: String, max_length: int = 80) -> String
static func safe_name(id: String) -> String
```

```gdscript
# addons/dialogue_manager/views/graph_view.gd
@tool
class_name DMGraphView extends Control

signal text_changed(new_text: String, description: String)
signal test_requested(from_key: String)
signal error_selected(line_number: int)
signal node_selected(node: DMGraphNode)

var document: DMGraphDocument
var is_syncing: bool = false
var is_dirty: bool = false
var is_building: bool = false
var current_path: String = ""

var graph_edit: GraphEdit
var inspector: VBoxContainer
var status_label: Label
var node_views: Dictionary = {}
var selected_node: DMGraphNode
var inspector_fields: Dictionary = {}
var last_errors: Array[DMError] = []

func _ready() -> void
func load_document(path: String, text: String) -> void
func clear_document() -> void
func sync_from_text(text: String) -> void
func rebuild() -> void
func set_errors(errors: Array[DMError]) -> void
func _apply_errors() -> void
func select_node(node_id: String) -> void
func select_cue(cue: String) -> void
func select_line(line_number: int) -> void
func move_sidecar(old_path: String, new_path: String) -> void
func remove_sidecar(path: String) -> void
func _build_ui() -> void
func _build_graph() -> void
func _arrange_graph() -> void
func _build_inspector() -> void
func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void
func _apply_connection_to_target(from_graph_node, target, cue_to_insert, target_node) -> void
func _cue_for_node(target_node: DMGraphNode) -> Dictionary
func _sanitize_cue_name(value: String) -> String
func _find_node_by_stable_key(doc, stable_key, source_start_hint = -1) -> DMGraphNode
func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void
func _on_node_selected(node: Node) -> void
func _on_node_deselected(node: Node) -> void
func _on_popup_request(at_position: Vector2) -> void
func _cases_have_else(node: DMGraphNode) -> bool
func _on_popup_menu_id_pressed(id: int) -> void
func _on_delete_selected_pressed() -> void
func _on_delete_nodes_request(nodes: Array) -> void
func _on_end_node_move() -> void
func _on_add_node_pressed(kind: int) -> void
func _on_add_condition_case_pressed(is_else: bool) -> void
func _on_remove_condition_case_pressed(index: int) -> void
func _on_add_match_case_pressed(is_else: bool) -> void
func _on_remove_match_case_pressed(index: int) -> void
func _on_add_random_branch_pressed() -> void
func _on_remove_random_branch_pressed(index: int) -> void
func _on_apply_inspector_pressed() -> void
func _on_auto_layout_pressed() -> void
func _on_test_pressed() -> void
func _open_localization_panel() -> void
func _build_localization_rows(tree: Tree) -> void
func _on_localization_item_selected(tree: Tree) -> void
func _apply_text(new_text: String, description: String) -> void
func _save_layout() -> void
func _parse_tags(text: String) -> PackedStringArray
func _node_id_from_name(node_name: String) -> String
func _set_status(message: String) -> void
```

### 18.5. Интеграция в `main_view.gd`

```gdscript
var graph_view: DMGraphView
var graph_toggle_button: Button

func _setup_graph_view() -> void
func _on_graph_toggle_toggled(pressed: bool) -> void
func _on_graph_text_changed(new_text: String, description: String) -> void
func _on_graph_test_requested(from_key: String) -> void
func _on_graph_error_selected(line_number: int) -> void
func apply_graph_text(new_text: String, description: String = "Graph edit") -> void
func _set_buffer_text(path: String, text: String) -> void
```

---

## 19. Рабочий пошаговый план (чек-лист, выполнен)

### Шаг 1. Каркас графа

- [x] `graph/dialogue_graph_node.gd`
- [x] `graph/dialogue_graph_edge.gd`
- [x] `graph/dialogue_graph_document.gd`
- [x] `graph/dialogue_graph_sidecar.gd`
- [x] Коммит: `Add graph data model, builder, serializer, and sidecar`

### Шаг 2. Построение графа

- [x] `graph/dialogue_graph_builder.gd`
- [x] Узлы для `cue`, `dialogue`, `response`, `choices`, `condition`, `match`,
      `while`, `mutation`, `jump`, `random`, `concurrent`, `comment`, `import`,
      `using`, `end`.
- [x] Рёбра `FLOW`, `BRANCH`, `JUMP`, `RETURN`, `CONCURRENT`.
- [x] Source ranges, `stable_key`, `block_end` для кейсов/веток.
- [x] Коммит: `Build graph from compiled dialogue`

### Шаг 3. Сериализация

- [x] `graph/dialogue_graph_serializer.gd`
- [x] Изменение реплик, ответов, cue, переходов, мутаций, комментариев.
- [x] Добавление/удаление узлов.
- [x] `replace_lines()`, `insert_lines()`, `delete_lines()`.
- [x] Редактирование condition/match/while/random.
- [x] Добавление/удаление condition/match/random-кейсов и веток.
- [x] `add_cue_before()`, `clear_inline_goto()`.
- [x] Коммит: `Serialize graph edits back to dialogue text`

### Шаг 4. View

- [x] `graph/dialogue_graph_node_view.gd`
- [x] `views/graph_view.gd`
- [x] `views/graph_view.tscn`
- [x] `GraphEdit`, порты, связи, инспектор, toolbar.
- [x] Sidecar layout.
- [x] Собственный layered layout (`_arrange_graph`).
- [x] Кнопка **Arrange all nodes**; встроенная arrange-кнопка скрыта.
- [x] Коммит: `Add graph view`

### Шаг 5. Интеграция

- [x] `main_view.gd`: `_setup_graph_view()`, режим Text/Graph.
- [x] Синхронизация текста и графа.
- [x] `apply_graph_text()` + `EditorUndoRedoManager`.
- [x] Ошибки, тест, переходы к cue/строке.
- [x] `files_moved` / `file_removed` для sidecar.
- [x] Коммит: `Integrate graph view into dialogue editor`

### Шаг 6. Проверка и документация

- [x] `tests/test_graph_builder.gd`
- [x] `tests/test_graph_serializer.gd`
- [x] Round-trip-тест внутри serializer-тестов.
- [x] Обновить `VISUAL_NODE_EDITOR_PLAN.md` фактическим статусом.
- [x] Коммит: `Add graph editor tests and docs`

### Шаг 7. Дополнительно реализовано

- [x] Соединение с любым top-level узлом через автосоздание `cue`.
- [x] Отсоединение `JUMP`/`RETURN`/основного `FLOW`.
- [x] Редактирование inline-goto (`=>` / `=><`) в инспекторе.
- [x] Панель **Localization** с Generate IDs, Export CSV, Refresh, Preview.
- [x] Контекстное меню: Add elif/else, Add when/else, Add random branch.
- [x] Улучшенное сопоставление позиций sidecar.
- [x] Коммиты: `Implement advanced graph editing...`,
      `Add and remove condition, match, and random branches...`,
      `Add case and branch actions to the graph context menu`,
      `Replace the built-in arrange action with arrange all nodes`.

---

## 20. Статус реализации

Реализовано в текущей версии:

- [x] Модель графа: `DMGraphNode`, `DMGraphEdge`, `DMGraphDocument`.
- [x] Построение графа из скомпилированного диалога: `DMGraphBuilder`.
- [x] Узлы `cue`, `dialogue`, `response`, `choices`, `condition`, `match`,
      `while`, `mutation`, `jump`, `random`, `concurrent`, `comment`, `import`,
      `using`, `end`.
- [x] Связи `FLOW`, `BRANCH`, `JUMP`, `RETURN`, `CONCURRENT`.
- [x] Обратная запись в текст: `DMGraphSerializer`.
- [x] Sidecar `.dialogue.graph.json` для позиций узлов.
- [x] `GraphEdit`-представление: `DMGraphView`, `DMGraphNodeView`.
- [x] Вкладка **Graph** внутри существующей вкладки **Dialogue**.
- [x] Синхронизация текста и графа.
- [x] Undo/Redo через `EditorUndoRedoManager`.
- [x] Редактирование реплик, ответов, cue, переходов, мутаций, комментариев.
- [x] Добавление/удаление узлов через контекстное меню и панель инструментов.
- [x] Подсветка ошибок компилятора на узлах.
- [x] Тестовый запуск с выбранного узла.
- [x] Переходы из панели ошибок и списка cue к узлам.
- [x] Обработка `files_moved` / `file_removed` для sidecar.
- [x] Unit-тесты `tests/test_graph_builder.gd`,
      `tests/test_graph_serializer.gd`.
- [x] Редактирование условий, `match`, `while`, весов и условий случайных
      веток в инспекторе.
- [x] Добавление и удаление кейсов `if/elif/else`, `when`/`else` и случайных
      веток прямо из инспектора и контекстного меню узла.
- [x] Редактирование типа inline-перехода (`=>` / `=><`) для реплик и ответов.
- [x] Соединение с любым top-level узлом через автоматическое создание cue.
- [x] Отсоединение переходов, возвратов и основного продолжения.
- [x] Собственный layered layout без предупреждений о циклах.
- [x] Кнопка **Arrange all nodes**; встроенная arrange-кнопка `GraphEdit`
      скрыта.
- [x] Улучшенное сопоставление позиций узлов (stable key / source line / тип).
- [x] Панель **Localization** с генерацией ID, экспортом CSV и preview.
- [x] Контекстное меню: Add elif/else, Add when/else, Add random branch.
- [x] Добавление/удаление кейсов и веток из инспектора и контекстного меню.

Ограничения текущей версии:

- Ветвление по-прежнему создаётся через порты ответов/условий/`match`/
  случайных веток. Произвольное соединение с branch-портом не поддерживается:
  для основных flow-узлов соединение с любым top-level узлом создаёт
  cue и переход, а branch-порты остаются текстовыми ветками.
- Отсоединение поддерживается для переходов, возвратов и основного
  продолжения. Отсоединение branch/body-связей пока не поддерживается.
- Новые кейсы/ветки создаются с placeholder-содержимым
  `Nathan: New branch` и выражением по умолчанию; их нужно отредактировать
  после добавления.
- Автоматическая раскладка использует простой layered layout, а не полный
  Sugiyama; для очень больших графов она может быть неоптимальной.
- Позиции узлов сопоставляются по `stable_key`, source line и ближайшему
  узлу того же типа; при больших структурных правках позиция может
  потеряться.
- Панель локализации показывает статические ID, текст, персонажа, заметки,
  статус (OK / Missing ID / Duplicate ID) и preview через
  `TranslationServer.translate()`. Если перевод не загружен в редакторе,
  preview показывает `(not translated)`.
- `Split`-режим, копирование/вставка, дублирование, поиск по графу и
  `Outline` не реализованы.
- UI графа пока не локализован: подписи кнопок и инспектора английские.
- Отдельной кнопки Export POT нет; POT обрабатывается существующей
  локализацией Godot.

Как открыть:

1. Открыть любой `.dialogue`-файл во вкладке **Dialogue**.
2. Нажать кнопку **Graph** на панели инструментов.
3. Выбрать узел, чтобы открыть инспектор справа.
4. Правый клик по пустому месту — добавить узел или удалить выбранный.
5. Кнопка **Test** запускает тестовую сцену с выбранного cue/строки.
6. Перетаскивание узла сохраняет его позицию в
   `<file>.dialogue.graph.json`.

---

## 21. Changelog реализации

### 21.1. Добавленные файлы

- `addons/dialogue_manager/graph/dialogue_graph_node.gd`
- `addons/dialogue_manager/graph/dialogue_graph_edge.gd`
- `addons/dialogue_manager/graph/dialogue_graph_document.gd`
- `addons/dialogue_manager/graph/dialogue_graph_builder.gd`
- `addons/dialogue_manager/graph/dialogue_graph_serializer.gd`
- `addons/dialogue_manager/graph/dialogue_graph_sidecar.gd`
- `addons/dialogue_manager/graph/dialogue_graph_node_view.gd`
- `addons/dialogue_manager/views/graph_view.gd`
- `addons/dialogue_manager/views/graph_view.tscn`
- `tests/test_graph_builder.gd`
- `tests/test_graph_serializer.gd`
- сгенерированные Godot `.uid`-файлы для перечисленных скриптов.

### 21.2. Изменённые файлы

- `addons/dialogue_manager/views/main_view.gd`:
  - `_setup_graph_view()`;
  - кнопка **Graph**;
  - `_on_graph_toggle_toggled()`;
  - `apply_graph_text()` / `_set_buffer_text()`;
  - синхронизация в `_on_parse_timer_timeout()`;
  - `graph_view.set_errors()` в `compile()`;
  - `select_cue()` / `select_line()` в переходах;
  - sidecar в `_on_files_moved()`;
  - выбор узла из панели ошибок.
- `addons/dialogue_manager/plugin.gd`:
  - `DMGraphSidecar.remove(file)` в `_on_file_removed()`.
- `addons/dialogue_manager/compiler/compiled_line.gd`:
  - `next_id_after` в `to_data()` для `TYPE_RESPONSE`, `TYPE_DIALOGUE`,
    `TYPE_RANDOM`.
- `VISUAL_NODE_EDITOR_PLAN.md` — обновлён по фактической реализации.

### 21.3. Реализованная функциональность

- Модель графа и sidecar.
- Построение графа из `.dialogue`:
  - cue, dialogue, response, choices, condition, match, while, mutation,
    jump, random, concurrent, comment, import, using, end.
- Связи `FLOW`, `BRANCH`, `JUMP`, `RETURN`, `CONCURRENT`.
- Редактирование:
  - реплики, ответы, cue, jump, mutation, comment;
  - condition/match/while/random;
  - inline-goto (`=>` / `=><`);
  - добавление/удаление condition/match/random-кейсов и веток.
- Соединения:
  - с cue и END;
  - с любым top-level узлом через автосоздание cue;
  - отсоединение jump/return/основного flow.
- UI:
  - `GraphEdit` + `GraphNode`;
  - инспектор;
  - контекстное меню;
  - **Arrange all nodes**;
  - **Localization** dialog;
  - подсветка ошибок;
  - тестовый запуск.
- Интеграция:
  - Text/Graph;
  - общий буфер;
  - undo/redo;
  - sidecar move/remove;
  - переходы из ошибок и cue.
- Локализация:
  - Static ID;
  - заметки;
  - статус Missing/Duplicate;
  - preview;
  - Generate IDs;
  - Export CSV.

### 21.4. Коммиты

- `e5c11c8` — Document graph editor class signatures and implementation checklist
- `be58918` — Add graph data model, builder, serializer, and sidecar
- `4e99f21` — Add graph view and integrate it into the dialogue editor
- `3064db0` — Add graph editor tests and fix response/comment flow handling
- `a692833` — Improve graph editor editing, sidebar layout, and error sync
- `a03f165` — Fix graph editor runtime errors and add Godot-generated UIDs
- `4ae51dd` — Add remaining generated UIDs for graph editor
- `512be7a` — Color return ports differently in the graph view
- `7294b1c` — Document current graph editor implementation status
- `0748813` — Implement advanced graph editing, connections, custom layout, and localization panel
- `1812f44` — Prevent connecting from the return port in the graph view
- `9ffada5` — Add translation preview column to the graph localization panel
- `fcc2196` — Add and remove condition, match, and random branches from the graph inspector
- `878d97d` — Add case and branch actions to the graph context menu
- `ed63fce` — Document add/remove actions in the graph inspector and context menu
- `48b9f56` — Replace the built-in arrange action with arrange all nodes

### 21.5. Проверка

- Godot **4.7.2**, Windows, headless editor:
  - editor запускается без script errors/warnings;
  - graph-тесты проходят;
  - smoke-тесты: построение графа, инспектор для всех типов узлов,
    соединения/отсоединение, add/remove кейсов, localization panel.
- Полный прогон тестов проекта по-прежнему содержит старые падения
  C#-тестов (`CSharpStaticState`), не связанные с графом.

### 21.6. Что осталось

- Branch/body-отсоединение.
- `Split`-режим.
- Копирование/вставка/дублирование/поиск по графу/Outline.
- Полная локализация UI графа.
- Инкрементальное обновление и оптимизация больших графов.
- Автоматизированные интеграционные тесты.

---

## 22. Итог

Реализованный путь:

1. `.dialogue` остаётся единственным источником правды.
2. Graph-режим добавлен в существующую вкладку **Dialogue**.
3. Реализованы модель, builder, serializer, view, интеграция, продвинутые
   узлы и локализация.
4. Для построения используется `DMCompiler` + line ID/raw lines; отдельный
   `for_editor` source map не добавлялся.
5. Обратная запись — точечные текстовые операции (`replace_lines`,
   `insert_lines`, `delete_lines`).
6. Sidecar хранит только layout и fallback-данные для позиций.
7. Переиспользованы существующие сохранение, компиляция, тесты, ошибки и
   локализация.

Итог: визуальный node-based редактор работает прямо в проекте, не ломает
существующий аддон и поддерживает заявленный функционал, включая локализацию.
