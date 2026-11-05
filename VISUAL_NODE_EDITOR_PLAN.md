# План: визуальный node-based редактор диалогов для Dialogue Manager 4

Документ описывает пошаговый план создания визуального редактора диалогов на графах
(`GraphEdit` / `GraphNode`) для аддона **Dialogue Manager 4**, который уже подключён
в этом проекте. Редактор должен работать внутри редактора Godot, создавать диалоги
в виде связанных узлов и поддерживать весь заявленный функционал аддона, включая
локализацию.

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

### Что не делаем на первом этапе

- Не меняем формат `.dialogue` и не вводим второй источник правды.
- Не переписываем runtime и импортёр.
- Не делаем отдельный редактор сцен или отдельный формат ресурса графа.
- Не поддерживаем произвольные «спагетти»-связи, которые невозможно выразить
  текстом (см. ограничения в разделе 7).

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
| `addons/dialogue_manager/views/main_view.gd` | Текстовый редактор, буферы открытых файлов, компиляция, сохранение, тест | Расширяем: режимы Text/Graph/Split, общий буфер, синхронизация |
| `addons/dialogue_manager/views/main_view.tscn` | UI главного экрана | Добавляем `GraphView`, переключатель режимов, панели |
| `addons/dialogue_manager/compiler/compiler.gd` | `DMCompiler.compile_string(text, path)` | Основной источник структуры для построения графа |
| `addons/dialogue_manager/compiler/compilation.gd` | Парсер, дерево строк, `DMCompiledLine` | Добавляем source map и, при необходимости, доступ к дереву |
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

- `DMCompiledLine` не хранит номер исходной строки и сырой текст. Для графа нужен
  **source map** (см. раздел 6.2).
- `when`-строки удаляются из `lines` после разбора `match`, поэтому для них нужен
  доступ к дереву `DMTreeLine` или к сырым строкам.
- Вложенные реплики (indented dialogue) компилятор склеивает в текст родительской
  строки. В графе их лучше показывать как многострочный текст одной ноды, а не
  как отдельные узлы.
- `DMCompilation` — compile-time класс, но он доступен как `class_name`. Для
  editor-only задач можно добавить безопасные поля, не влияя на runtime.
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
DMCompilerResult (lines, cues, errors, source map)
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
[ Text ] [ Graph ] [ Split ]
```

- **Text** — текущий редактор, без изменений.
- **Graph** — граф на всё окно.
- **Split** — текст слева, граф справа (полезно для отладки и обучения).

Все режимы используют один и тот же буфер `open_buffers[path]`, один процесс
сохранения, одну компиляцию и одну панель ошибок.

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

Правила генерации `stable_key`:

1. Если у строки есть `static_id` — `dialogue:<static_id>`.
2. Для `cue` — `cue:<name>`.
3. Для `response` — `response:<static_id или hash(prompt)>:<index>`.
4. Для `condition` — `condition:<hash(expression)>:<index>`.
5. Для `match` — `match:<hash(expression)>`.
6. Для `random` — `random:<hash(weight+condition)>:<index>`.
7. Для `jump` — `jump:<target>:<is_snippet>`.
8. Иначе — `type:<hash(raw_text + parent_stable_key)>`.

При перестроении графа узлы сопоставляются по `stable_key`. Если ключ не найден,
узел считается новым и получает позицию из auto-layout. Если ключ исчез — позиция
удаляется из sidecar (или хранится в «корзине» для undo).

> Важно: `stable_key` — эвристика. Для строк без static ID и с одинаковым текстом
> возможны коллизии. Поэтому в sidecar дополнительно храним `source_line` и
> `parent_key`, а при совпадении ключей уточняем по контексту.

### 4.5. Sidecar-файл

Путь: `<dialogue_path>.graph.json`, например
`res://dialogues/intro.dialogue.graph.json`.

```json
{
  "version": 1,
  "file": "res://dialogues/intro.dialogue",
  "view": {
    "zoom": 1.0,
    "scroll": [0, 0],
    "mode": "graph"
  },
  "nodes": {
    "cue:start": {
      "position": [120, 80],
      "size": [220, 90],
      "collapsed": false,
      "color": "#3b6ea5"
    },
    "dialogue:abc123": {
      "position": [120, 240],
      "size": [320, 140]
    }
  },
  "groups": [
    {
      "title": "Intro",
      "rect": [80, 40, 500, 400],
      "color": "#2d4a6b"
    }
  ],
  "settings": {
    "hide_sequential_edges": false,
    "compact_mode": false
  }
}
```

Sidecar:

- не импортируется Godot как ресурс (расширение `.json`, не `.dialogue`);
- перемещается вместе с `.dialogue` при `files_moved`;
- удаляется при `file_removed`;
- при конфликте версий — игнорируется, граф строится заново;
- не обязателен для работы: без него используется auto-layout.

---

## 5. Парсинг текста в граф

### 5.1. Общий алгоритм

```
1. Прочитать текст файла.
2. Вызвать DMCompiler.compile_string(text, path) (editor-режим с source map).
3. Разобрать файловые строки: import, using, комментарии.
4. Построить source map: compiled_line_id -> диапазон исходных строк.
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

### 5.2. Source map

Нужно добавить в компилятор editor-only информацию. Минимальные изменения:

```gdscript
# compiler/compiled_line.gd
var source_line: int = -1       # 1-based номер строки в файле
var source_end_line: int = -1   # 1-based, для вложенных блоков
var raw_text: String = ""       # исходная строка без отступа
var parent_id: String = ""      # ID родительской строки
```

```gdscript
# compiler/compiler_result.gd
var tree: DMTreeLine = null          # editor-only, для when/комментариев
var source_lines: PackedStringArray = []
var imports: Array[Dictionary] = []  # { path, alias, line }
var comments: Array[Dictionary] = [] # { line, text, attached_to }
```

```gdscript
# compiler/compiler.gd
static func compile_string(text: String, path: String, for_editor: bool = false) -> DMCompilerResult:
    var compilation: DMCompilation = DMCompilation.new()
    compilation.collect_source_map = for_editor
    compilation.compile(text, path)
    ...
    if for_editor:
        result.tree = compilation.tree
        result.source_lines = text.split("\n")
        result.imports = compilation.imports
        result.comments = compilation.comments
    return result
```

В `DMCompilation`:

- `var collect_source_map: bool = false`;
- `var tree: DMTreeLine`;
- `var imports: Array[Dictionary] = []`;
- `var comments: Array[Dictionary] = []`;
- в `build_line_tree()` сохранять `tree = root`, заполнять `imports` и `comments`;
- в `parse_line_tree()` при `collect_source_map` проставлять `line.source_line`,
  `line.source_end_line`, `line.raw_text`, `line.parent_id`.

Для `when`-строк, которые удаляются из `lines`, данные берём из `tree`:
находим `DMTreeLine` с нужным `id` и берём `line_number`, `text`, `children`.

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

    var result: DMCompilerResult = DMCompiler.compile_string(text, path, true)
    doc.errors = result.errors
    doc.cues = result.cues
    doc.first_cue = result.first_cue
    doc.using_states = result.using_states
    doc.imports = result.imports

    _build_file_nodes(doc, result)
    _build_cue_nodes(doc, result)
    _build_line_nodes(doc, result)
    _build_edges(doc, result)
    _group_blocks(doc, result)
    _attach_source_ranges(doc, result)

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

1. **Последовательный поток** не рисуется пользователем вручную: он вычисляется
   из порядка строк. Пользователь может менять порядок перетаскиванием.
2. **Ветвление** создаётся только через порты `CHOICES`, `CONDITION`, `MATCH`,
   `RANDOM`. Нельзя просто протянуть линию от реплики к реплике в другой ветке.
3. **Переход** создаётся только на `CUE` (или `END`/`END!`). При протягивании
   линии на cue редактор вставляет `=> cue` или `=>< cue`.
4. **Межфайловый переход** — только на внешний cue из `import`.
5. Если пользователь пытается создать недопустимую связь, показываем tooltip
   и возвращаем линию назад.

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
│ [Text] [Graph] [Split]  intro.dialogue   [+ Add] [Auto] [Test] ... │
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
│ Errors (2) │ Cues │ Localization │ Outline                          │
└────────────────────────────────────────────────────────────────────┘
```

### 7.2. Toolbar

- переключатель `Text / Graph / Split`;
- имя файла и кнопка «показать в файловой системе»;
- `+ Add` — меню добавления узла (Dialogue, Response, Condition, Match,
  While, Mutation, Jump, Random, Comment);
- `Auto layout` — `GraphEdit.arrange_nodes()` или собственный layered layout;
- `Zoom` — `-`, `100%`, `+`, `Fit`;
- `Search` — поиск по тексту, персонажу, ID, тегам;
- `Test` — запуск с текущего cue/строки;
- `Save` / `Save all`;
- `Errors` — счётчик и переход к ошибке;
- `Localization` — панель переводов;
- `Settings` — настройки graph-режима.

### 7.3. Настройки `GraphEdit`

```gdscript
graph_edit.show_grid = true
graph_edit.snap_distance = 20
graph_edit.panning_scheme = GraphEdit.SCROLL_ZOOMS
graph_edit.zoom_min = 0.25
graph_edit.zoom_max = 2.0
graph_edit.minimap_enabled = true
graph_edit.right_disconnects = true
graph_edit.connection_lines_curvature = 0.5
graph_edit.connection_lines_thickness = 2.0
graph_edit.connection_lines_antialiased = true
```

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

### 7.5. Взаимодействие

- **Добавление**: правый клик по пустому месту → `Add node`; или `+ Add` в
  toolbar; или `Tab` на выбранном узле.
- **Соединение**: протянуть от выходного порта к входному. `GraphEdit` сам
  вызывает `connection_request`; мы валидируем и применяем патч.
- **Разрыв**: правый клик по связи → `Disconnect`; или `right_disconnects`.
- **Выбор**: клик, `Shift`+клик, рамка (встроенная в `GraphEdit`).
- **Перемещение**: drag; позиция сохраняется в sidecar.
- **Копирование/вставка**: `Ctrl+C` / `Ctrl+V`; внутри — текст блока.
- **Дублирование**: `Ctrl+D`.
- **Удаление**: `Delete`; с подтверждением, если есть дочерние узлы.
- **Undo/Redo**: `Ctrl+Z` / `Ctrl+Y` через `EditorUndoRedoManager`.
- **Контекстное меню**: `Test from here`, `Go to cue`, `Find references`,
  `Convert to text`, `Add comment`, `Collapse`.
- **Поиск**: `Ctrl+F`; подсветка найденных узлов, переход по `Enter`.
- **Zoom**: `Ctrl+wheel`, `+`/`-`, `Fit`.
- **Pan**: средняя кнопка мыши / `Space`+drag.
- **Auto layout**: кнопка `Auto`; после ручного перемещения позиции фиксируются.

### 7.6. Инспектор

Динамическая форма по типу узла. Поля:

- **Dialogue**: Character (ComboBox с автодополнением), Text (TextEdit),
  Tags (LineEdit), Static ID (LineEdit + кнопка Generate), Translator note
  (TextEdit), Inline mutations (список), Concurrent lines (список).
- **Response**: Prompt, Condition (LineEdit + валидация), Static ID, Tags,
  Character, Goto (ComboBox cue/END).
- **Condition**: список веток; для каждой — выражение, кнопка добавить/удалить;
  `else` без выражения.
- **Match**: выражение, список `when`/`else`.
- **While**: условие.
- **Mutation**: выражение, чекбокс «блокирующая» (`$>` vs `$>>`).
- **Jump**: target (ComboBox cue/END/END!/expression), тип (`=>`/`=><`).
- **Random**: список веток с весом и условием.
- **Cue**: имя, кнопка «сделать стартовым».
- **Import**: путь, алиас, список внешних cue.
- **Comment**: текст.

Валидация полей:

- пустой текст реплики — предупреждение;
- пустой `cue` — ошибка;
- дубликат `cue` — ошибка;
- неизвестный `cue` в переходе — ошибка;
- дубликат `static_id` — ошибка;
- пустое условие — ошибка;
- недопустимые символы в `cue` — ошибка.

### 7.7. Панели

- **Errors**: список `DMError` с номером строки и сообщением; клик — выбор узла.
- **Cues**: список cue; клик — центрирование; кнопка «добавить cue».
- **Localization**: таблица `static_id | text | character | notes | status`;
  фильтры `missing`, `duplicate`, `untranslated`; кнопки `Generate IDs`,
  `Export CSV`, `Export POT`.
- **Outline**: дерево `cue -> узлы`; клик — переход.
- **Search results**: список совпадений.

---

## 8. Интеграция с существующим плагином

### 8.1. Изменения в `plugin.gd`

Практически не нужны:

- `_has_main_screen()` остаётся `true`;
- `_get_plugin_name()` остаётся `"Dialogue"`;
- `_handles()` / `_edit()` остаются;
- `_apply_changes()` / `_get_unsaved_status()` / `_save_external_data()` остаются.

Добавить только:

- пункт меню `Dialogue -> Open graph` (опционально);
- настройку «открывать граф по умолчанию»;
- обработку `files_moved` / `file_removed` для sidecar (можно в `main_view`).

### 8.2. Изменения в `main_view.tscn`

Добавить:

- `ViewModeBar` — `HBoxContainer` с кнопками `Text`, `Graph`, `Split`;
- `GraphView` — инстанс `views/graph_view.tscn`;
- `GraphInspector` — внутри `GraphView`;
- `GraphBottomPanel` — `TabContainer` с `Errors`, `Cues`, `Localization`,
  `Outline`;
- `GraphToolbar` — внутри `GraphView`.

`Content` (HSplitContainer) можно оставить для текстового режима, а `GraphView`
показывать поверх/рядом в зависимости от режима.

### 8.3. Изменения в `main_view.gd`

Добавить:

```gdscript
enum ViewMode { TEXT, GRAPH, SPLIT }

var view_mode: ViewMode = ViewMode.TEXT

@onready var graph_view: DMGraphView = %GraphView
@onready var view_mode_bar: HBoxContainer = %ViewModeBar
```

В `_ready()`:

```gdscript
graph_view.text_changed.connect(_on_graph_text_changed)
graph_view.node_selected.connect(_on_graph_node_selected)
graph_view.test_requested.connect(_on_graph_test_requested)
graph_view.error_selected.connect(_on_graph_error_selected)
```

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
if not graph_view.is_dirty:
    graph_view.sync_from_text(new_content)
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

Правила:

1. **Текст → граф**: при изменении `code_edit.text` (пользователь печатает)
   граф перестраивается с debounce 150–250 мс. Курсор и скролл текста не трогаем.
2. **Граф → текст**: при изменении графа вызываем `apply_graph_text()`, который
   обновляет буфер и `code_edit.text`, сохраняя курсор/скролл.
3. **Защита от циклов**: флаг `is_syncing` в `graph_view` и `_is_applying_graph_text`
   в `main_view`. Пока флаг установлен, встречные сигналы игнорируются.
4. **Dirty state**: граф не хранит своё «грязное» состояние отдельно; источник
   правды — `open_buffers[path].text != pristine_text`. Это уже работает в
   `count_unsaved_files()` и `_get_unsaved_status()`.
5. **Внешние изменения**: если файл изменился на диске и буфер не грязный,
   обновляем и текст, и граф. Если грязный — показываем предупреждение.

### 8.5. Сохранение

`save_file()` не меняется: он сохраняет `open_buffers[path].text`. Граф уже
записал свои изменения в этот буфер. После сохранения:

- `DMCache.mark_files_for_reimport([path])`;
- `EditorInterface.get_resource_filesystem().scan()`;
- sidecar сохраняется отдельно (если включён).

### 8.6. Тестовый запуск

`main_view.run_test_scene(from_key)` уже умеет запускать с cue или номера строки.

В графе:

- `Test from here` для `CUE` → `run_test_scene(cue_name)`;
- для остальных узлов → `run_test_scene(str(source_line))`;
- для `JUMP` → `run_test_scene(target)`, если target — cue.

### 8.7. Поиск и переходы

- `DMPlugin.show_find_in_dialogue()` уже открывает файл и выделяет текст.
  Граф должен обработать `go_to_line_number()` и выбрать узел, содержащий
  эту строку.
- `go_to_cue()` выбирает cue-узел и центрирует его.
- `Find references` для cue: найти все `JUMP`-узлы с этой целью.

### 8.8. Undo/Redo

Используем `EditorUndoRedoManager`:

```gdscript
var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
undo_redo.create_action("Add dialogue node")
undo_redo.add_do_method(self, "_apply_patch", patch)
undo_redo.add_undo_method(self, "_revert_patch", patch)
undo_redo.commit_action()
```

Для графовых операций патч содержит `start_line`, `end_line`, `replacement`.
Undo применяет обратный патч. Для перемещения узлов — сохраняем старую и новую
позиции.

Не смешиваем undo-стек текстового редактора и графа: все изменения графа идут
через `EditorUndoRedoManager`, а текстовый редактор продолжает использовать свой
встроенный undo. Это может привести к двум стекам; документируем поведение.
Альтернатива — все изменения (и текстовые, и графовые) проводить через
`EditorUndoRedoManager`, но это большой рефакторинг. Для MVP достаточно
раздельных стеков с предупреждением в документации.

---

## 9. Поддержка функционала аддона

### 9.1. Матрица возможностей

| Возможность | Представление в графе | Редактирование | Валидация | Runtime |
|---|---|---|---|---|
| Реплики | `DIALOGUE` | текст, персонаж, теги, ID, заметка | пустой текст, дубликат ID | без изменений |
| Ответы | `CHOICES` + `RESPONSE` | prompt, условие, переход, ID, теги | пустой prompt, неизвестный cue | без изменений |
| Условия `if/elif/else` | `CONDITION` | ветки, выражения | пустое условие, недостижимая ветка | без изменений |
| `match/when/else` | `MATCH` | выражение, кейсы | пустой кейс, нет `else` (предупреждение) | без изменений |
| `while` | `WHILE` | условие, тело | цикл без выхода (предупреждение) | без изменений |
| Мутации `$>`, `$>>`, `do`, `set` | `MUTATION` | выражение, блокирующая | пустое выражение | без изменений |
| Случайные строки `%` | `RANDOM` | ветки, вес, условие | вес <= 0, пустая ветка | без изменений |
| `cue` | `CUE` | имя, стартовый cue | пустое имя, дубликат, недопустимые символы | без изменений |
| `=>` / `=><` | `JUMP` | цель, тип | неизвестный cue, динамический переход | без изменений |
| `=> END` / `=> END!` | `JUMP` | тип | — | без изменений |
| Импорты | `IMPORT` + внешние cue | путь, алиас | циклический импорт, отсутствующий файл | без изменений |
| `using` | `USING` | имя состояния | неизвестный autoload | без изменений |
| Теги `[#tag]` | поле `Tags` | список | — | без изменений |
| Одновременные реплики `\|` | `CONCURRENT` | список | нет основной реплики | без изменений |
| Inline BBCode | поле `Text` | текст | — | без изменений |
| Inline-мутации | поле `Inline mutations` | список | — | без изменений |
| Статические ID `[ID:...]` | поле `Static ID` | текст + Generate | дубликат, отсутствует (настройка) | без изменений |
| Заметки `##` | поле `Translator note` | текст | — | без изменений |
| Имена персонажей | ComboBox | выбор/добавление | — | без изменений |
| Выражения в тексте `{{...}}` | поле `Text` | текст | ошибки парсера | без изменений |
| Динамические переходы `=> {{...}}` | `JUMP` | выражение | предупреждение | без изменений |
| Dialogue processor | — | — | предупреждение о возможном несоответствии | без изменений |
| Тестовая сцена | кнопка `Test` | — | — | без изменений |
| Поиск | панель поиска | — | — | без изменений |
| Ошибки | панель ошибок | — | — | без изменений |
| POT/CSV | панель локализации | — | — | без изменений |
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

### 10.2. Что добавляет граф

- Поле `Static ID` в инспекторе реплики/ответа.
- Кнопка `Generate ID` для выбранного узла (использует
  `DMTranslationUtilities.generate_static_line_ids_for_text()` на уровне файла
  или генерирует ключ по тем же правилам).
- Кнопка `Generate all IDs` для файла/проекта.
- Панель `Localization`:
  - таблица строк: `static_id`, `text`, `character`, `notes`, `status`;
  - фильтры `missing`, `duplicate`, `untranslated`;
  - переход к узлу по клику;
  - предпросмотр перевода `tr(static_id)` для текущей локали редактора.
- Подсветка узлов:
  - без ID — жёлтая рамка (если настройка требует ID);
  - дубликат ID — красная рамка;
  - перевод отсутствует — серая иконка.
- Кнопки `Export CSV` и `Export POT` (переиспользуют существующие диалоги).

### 10.3. Правила сохранения

- При изменении текста реплики **не удалять** `[ID:...]` и `##`-заметку.
- При изменении текста с существующим ID предлагать оставить ID (по умолчанию)
  или сгенерировать новый.
- При удалении узла с ID — предупреждать, что перевод осиротеет.
- При дублировании узла с ID — автоматически генерировать новый ID или
  предупреждать о дубликате.
- При вставке узла из другого файла — проверять конфликт ID через
  `DMCache.known_static_ids`.

### 10.4. Локализация самого редактора

Строки UI графа добавляем в `addons/dialogue_manager/l10n/en.po` и, по
возможности, в `es.po`, `uk.po`, `zh.po`, `zh_TW.po`. Используем
`DMConstants.translate(&"graph....")`.

Пример ключей:

```
graph.view.text = Text
graph.view.graph = Graph
graph.view.split = Split
graph.add_node = Add node
graph.auto_layout = Auto layout
graph.test_from_here = Test from here
graph.localization.title = Localization
graph.errors.title = Errors
```

---

## 11. Валидация и ошибки

### 11.1. Ошибки компилятора

`DMCompilerResult.errors` — массив `DMError` с `line_number`, `column_number`,
`error`. Маппим `line_number` на узел:

```gdscript
func set_errors(errors: Array[DMError]) -> void:
    for node: DMGraphNode in document.nodes.values():
        node.properties["errors"] = []

    for error: DMError in errors:
        var node: DMGraphNode = find_node_for_line(error.line_number)
        if node != null:
            node.properties["errors"].append(error)
            update_node_badge(node)
```

Визуально:

- красная рамка узла;
- иконка `Error` в заголовке;
- tooltip с `DMConstants.get_error_message(error.error)`;
- клик по ошибке в панели — выбор узла и фокус на проблемном поле.

### 11.2. Графовые предупреждения

Дополнительно к компилятору:

- **Недостижимый узел**: нет входящих `FLOW`/`BRANCH`/`JUMP`, и это не `CUE`.
- **Пустая ветка**: у `CONDITION`/`MATCH`/`RANDOM`/`RESPONSE` нет дочерних строк.
- **Осиротевший cue**: нет входящих переходов и это не `first_cue`.
- **Цикл без выхода**: цикл в графе, не являющийся `WHILE`.
- **Динамический переход**: `next_id_expression` не проверяется компилятором.
- **Дубликат ID**: уже есть в компиляторе, но показываем и в графе.
- **Отсутствующий ID**: если `MISSING_TRANSLATIONS_ARE_ERRORS`.
- **Импорт без использования**: `import`, на cue которого нет переходов.
- **Одновременная реплика без основной**: компилятор уже ловит.
- **Слишком большой граф**: > 300 узлов — предупреждение о производительности.

### 11.3. Панель ошибок

- Группировка по файлу.
- Фильтры `Errors` / `Warnings`.
- Клик — переход к узлу.
- Кнопка `Recompile`.
- Счётчик в toolbar.

---

## 12. Производительность

### 12.1. Целевые показатели

| Размер файла | Узлов | Время построения | Время перестроения |
|---|---|---|---|
| 50 строк | ~30 | < 50 мс | < 30 мс |
| 200 строк | ~120 | < 150 мс | < 80 мс |
| 500 строк | ~300 | < 400 мс | < 200 мс |
| 1000 строк | ~600 | < 1 с | < 500 мс |

### 12.2. Меры

- **Debounce** 150–250 мс для текстовых изменений.
- **Инкрементальное обновление**: если изменился только текст одного узла,
  не перестраивать весь граф; обновить `properties` и перерисовать узел.
- **Кэш компиляции**: хранить `DMCompilerResult` и `text_hash`; если хэш не
  изменился, не компилировать.
- **Compact mode**: последовательные реплики можно схлопывать в один узел
  «Sequence» с раскрытием. Это уменьшает количество `GraphNode`.
- **Focus mode**: показывать только подграф выбранного cue; остальное скрыто.
- **Отключение minimap** при > 500 узлах.
- **`set_process(false)`** когда вкладка не видима.
- **Ленивая загрузка sidecar**: читать только при открытии файла.
- **Ограничение истории undo**: не хранить полные копии текста для каждого
  изменения; хранить патчи.

---

## 13. Тестирование

### 13.1. Unit-тесты

Добавить в `tests/`:

- `test_graph_builder.gd`:
  - построение узлов для каждого типа строки;
  - корректные `next_id`/`responses`/`siblings`;
  - группировка `if/elif/else`, `match`, `random`, `responses`;
  - `cue` и `first_cue`;
  - импорты и внешние cue;
  - одновременные реплики;
  - source map.
- `test_graph_serializer.gd`:
  - каждая операция даёт ожидаемый текст;
  - отступы;
  - сохранение комментариев и ID;
  - удаление/вставка/перемещение.
- `test_graph_roundtrip.gd`:
  - `text -> graph -> text` для всех `.dialogue` в `tests/`;
  - идемпотентность;
  - отсутствие новых ошибок компиляции.
- `test_graph_validation.gd`:
  - недостижимые узлы;
  - пустые ветки;
  - дубликаты ID;
  - неизвестные cue.

### 13.2. Интеграционные тесты

- Открыть `.dialogue`, переключиться в Graph, изменить текст, сохранить,
  проверить импорт и runtime.
- Undo/Redo для добавления/удаления/перемещения.
- Внешнее изменение файла.
- Перемещение/удаление файла и sidecar.
- Генерация ID и экспорт CSV/POT.
- Тестовый запуск с узла.
- Поиск и переход к ошибке.

### 13.3. Ручной тест-матрица

- Godot 4.6 и 4.7.
- Windows / Linux / macOS.
- Светлая и тёмная тема.
- GDScript-проект и C#-проект.
- Высокий DPI.
- Файлы: `tests/main.dialogue`, `tests/snippets.dialogue`, примеры из docs.
- Большой файл (500+ строк).

### 13.4. Критерии приёмки

- [ ] Граф открывается для любого `.dialogue` без ошибок.
- [ ] Все типы строк отображаются корректными узлами.
- [ ] Изменения в графе сохраняются в текст и компилируются без новых ошибок.
- [ ] `text -> graph -> text` не меняет файл, если граф не редактировали.
- [ ] Условия, `match`, `while`, `random`, ответы, переходы, импорты,
      одновременные реплики поддерживаются.
- [ ] Статические ID и заметки сохраняются.
- [ ] POT/CSV экспорт работает.
- [ ] Тестовый запуск работает с узла.
- [ ] Undo/Redo работает.
- [ ] Ошибки компилятора подсвечиваются на узлах.
- [ ] Граф не ломает существующий текстовый редактор.
- [ ] Производительность в пределах целевых показателей.

---

## 14. Пошаговый план реализации

### Этап 0. Подготовка (0.5–1 день)

1. Создать ветку `feature/visual-graph-editor`.
2. Зафиксировать решение: text-first, sidecar, интеграция в `main_view`.
3. Собрать корпус `.dialogue`-файлов для round-trip-тестов.
4. Добавить пустые классы/файлы и настройки, чтобы не ломать сборку.
5. Проверить, что проект открывается в Godot 4.6/4.7.

**Результат:** структура папок, настройки, тестовый корпус.

### Этап 1. Модель и source map (2–3 дня)

1. Создать `graph/dialogue_graph_document.gd`, `dialogue_graph_node.gd`,
   `dialogue_graph_edge.gd`, `dialogue_graph_patch.gd`.
2. Добавить editor-only поля в `DMCompiledLine` и `DMCompilerResult`.
3. Добавить `collect_source_map` в `DMCompilation`.
4. Заполнить `source_line`, `source_end_line`, `raw_text`, `parent_id`.
5. Экспортировать `tree`, `imports`, `comments`.
6. Написать `DMGraphBuilder` (без UI).
7. Unit-тесты на построение.

**Результат:** текст → `DMGraphDocument` с узлами, рёбрами и source map.

### Этап 2. Read-only граф (2–3 дня)

1. Создать `views/graph_view.tscn` и `graph_view.gd`.
2. Добавить `GraphEdit` и базовые `GraphNode`-сцены.
3. Отрисовать узлы и связи.
4. Добавить auto-layout (`GraphEdit.arrange_nodes()`).
5. Добавить переключатель Text/Graph в `main_view`.
6. Синхронизировать открытие файла и выбор узла.
7. Sidecar: чтение/запись позиций.

**Результат:** можно открыть диалог и посмотреть его графом.

### Этап 3. Редактирование ядра (4–6 дней)

1. Инспектор для `DIALOGUE`, `RESPONSE`, `CUE`, `JUMP`.
2. Изменение текста/персонажа/тегов/ID.
3. Добавление/удаление реплик и ответов.
4. Переходы на cue.
5. `DMGraphSerializer` с патчами.
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

### Этап 6. Полировка (4–5 дней)

1. Copy/Paste/Duplicate.
2. Multi-select.
3. Контекстное меню.
4. Поиск по графу.
5. Группы/фреймы.
6. Комментарии-стикеры.
7. Compact/Focus mode.
8. Настройки graph-режима.
9. Темизация.
10. Локализация UI.

**Результат:** удобный повседневный инструмент.

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
| 1. Модель и source map | 2–3 |
| 2. Read-only граф | 2–3 |
| 3. Редактирование ядра | 4–6 |
| 4. Продвинутые узлы | 5–7 |
| 5. Локализация и ошибки | 3–4 |
| 6. Полировка | 4–5 |
| 7. Тестирование и документация | 3–4 |
| **Итого** | **~24–33 дня** |

Для одного разработчика — примерно 5–7 недель с учётом ревью и непредвиденных
задач. MVP (этапы 0–3) — около 2–3 недель.

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

## 16. Открытые вопросы

Перед началом реализации стоит подтвердить:

1. **Источник правды.** Оставляем `.dialogue` текстом (рекомендуется) или
   хотим graph-first с отдельным `.dialoguegraph`?
2. **Режим интеграции.** Text/Graph/Split в существующей вкладке (рекомендуется)
   или отдельная вкладка/плагин?
3. **MVP.** Начинаем с read-only графа и простых реплик/ответов/переходов
   (рекомендуется) или сразу делаем все синтаксисы?
4. **Sidecar.** Храним `.dialogue.graph.json` рядом с файлом (рекомендуется) или
   в `user://` (только локально, не шарится в git)?
5. **Auto-layout.** Достаточно `GraphEdit.arrange_nodes()` или нужен
   собственный layered layout?
6. **Ограничения связей.** Согласны, что произвольные связи запрещены и
   переходы делаются только на cue (рекомендуется)?
7. **Локализация.** Нужен ли предпросмотр перевода в графе и панель
   `Localization` в MVP?
8. **C#.** Нужно ли что-то отдельное для C#-проектов? (Граф editor-only,
   скорее всего нет.)

Если ответы не уточнены, план предполагает рекомендованные варианты:
text-first, Text/Graph/Split, MVP с этапов 0–3, sidecar рядом с файлом,
`arrange_nodes()`, запрет произвольных связей, панель локализации в этапе 5.

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
  `arrange_nodes()`, `set_connection_activity()`, `minimap_enabled`,
  `snap_distance`, `zoom`, `scroll_offset`.
- `GraphNode`: `set_slot()`, `title`, `position_offset`, `size`, `resizable`,
  `draggable`, `selectable`.
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

## 19. Конкретные сигнатуры классов

Ниже — рабочие сигнатуры, по которым будет писаться код. Все классы editor-only,
`@tool`, с префиксом `DM`, в стиле аддона.

### 19.1. Модель

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

### 19.2. Построение и сериализация

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_builder.gd
@tool
class_name DMGraphBuilder extends RefCounted

static func build(text: String, path: String) -> DMGraphDocument
static func _build_file_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _build_cue_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _build_line_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _build_edges(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _group_conditions(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _group_matches(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _group_random(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _group_responses(doc: DMGraphDocument, result: DMCompilerResult) -> void
static func _source_line_for_id(line_id: String) -> int
static func _find_block_end(lines: PackedStringArray, start_line: int, indent: int) -> int
static func _indent_count(line: String) -> int
static func _stable_key(line: Dictionary, index: int) -> String
static func _add_edge_if_missing(doc: DMGraphDocument, edge: DMGraphEdge) -> void
```

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_serializer.gd
@tool
class_name DMGraphSerializer extends RefCounted

static func set_dialogue_properties(text: String, node: DMGraphNode, properties: Dictionary) -> String
static func set_response_properties(text: String, node: DMGraphNode, properties: Dictionary) -> String
static func set_cue_name(text: String, node: DMGraphNode, new_name: String) -> String
static func set_jump_target(text: String, node: DMGraphNode, target: String, is_snippet: bool) -> String
static func set_mutation_expression(text: String, node: DMGraphNode, expression: String, is_blocking: bool) -> String
static func add_dialogue_after(text: String, node: DMGraphNode, character: String, dialogue: String) -> String
static func add_response_after(text: String, node: DMGraphNode, prompt: String) -> String
static func add_cue(text: String, cue: String) -> String
static func delete_node(text: String, node: DMGraphNode) -> String
static func replace_lines(text: String, start_line: int, end_line: int, replacement: PackedStringArray) -> String
static func _line_indent(line: String) -> String
static func _format_dialogue_line(character: String, dialogue: String, tags: PackedStringArray, static_id: String) -> String
static func _format_response_line(prompt: String, condition: String, goto: String, static_id: String) -> String
```

### 19.3. Sidecar

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

### 19.4. View

```gdscript
# addons/dialogue_manager/graph/dialogue_graph_node_view.gd
@tool
class_name DMGraphNodeView extends GraphNode

var graph_node: DMGraphNode
var document: DMGraphDocument

func setup(node: DMGraphNode, doc: DMGraphDocument) -> void
func refresh() -> void
func set_error_state(has_error: bool) -> void
func _add_port_row(text: String, has_input: bool, has_output: bool, color: Color) -> HBoxContainer
func _get_kind_color(kind: DMGraphNode.Kind) -> Color
func _get_kind_title(kind: DMGraphNode.Kind) -> String
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
var current_path: String = ""

var graph_edit: GraphEdit
var inspector: VBoxContainer
var node_views: Dictionary = {}
var selected_node: DMGraphNode

func _ready() -> void
func load_document(path: String, text: String) -> void
func clear_document() -> void
func sync_from_text(text: String) -> void
func rebuild() -> void
func set_errors(errors: Array[DMError]) -> void
func select_node(node_id: String) -> void
func select_cue(cue: String) -> void
func select_line(line_number: int) -> void
func move_sidecar(old_path: String, new_path: String) -> void
func remove_sidecar(path: String) -> void
func _build_ui() -> void
func _build_graph() -> void
func _build_inspector() -> void
func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void
func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void
func _on_node_selected(node: Node) -> void
func _on_popup_request(at_position: Vector2) -> void
func _on_delete_nodes_request(nodes: Array[StringName]) -> void
func _on_end_node_move() -> void
func _on_add_node_pressed(kind: int) -> void
func _on_apply_inspector_pressed() -> void
func _on_test_pressed() -> void
func _apply_text(new_text: String, description: String) -> void
func _save_layout() -> void
```

### 19.5. Интеграция в `main_view.gd`

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

## 20. Рабочий пошаговый план (чек-лист)

Этот чек-лист — то, по чему идёт реализация. Каждый пункт заканчивается
рабочим состоянием и коммитом.

### Шаг 1. Каркас графа

- [ ] `graph/dialogue_graph_node.gd`
- [ ] `graph/dialogue_graph_edge.gd`
- [ ] `graph/dialogue_graph_document.gd`
- [ ] `graph/dialogue_graph_sidecar.gd`
- [ ] Коммит: `Add graph data model`

### Шаг 2. Построение графа

- [ ] `graph/dialogue_graph_builder.gd`
- [ ] Узлы для `cue`, `dialogue`, `response`, `choices`, `condition`, `match`,
      `while`, `mutation`, `jump`, `random`, `concurrent`, `import`, `using`.
- [ ] Рёбра `FLOW`, `BRANCH`, `JUMP`, `RETURN`, `CONCURRENT`.
- [ ] Source ranges и `stable_key`.
- [ ] Коммит: `Build graph from compiled dialogue`

### Шаг 3. Сериализация

- [ ] `graph/dialogue_graph_serializer.gd`
- [ ] Изменение реплик, ответов, cue, переходов, мутаций.
- [ ] Добавление/удаление узлов.
- [ ] `replace_lines()` и сохранение отступов.
- [ ] Коммит: `Serialize graph edits back to dialogue text`

### Шаг 4. View

- [ ] `graph/dialogue_graph_node_view.gd`
- [ ] `views/graph_view.gd`
- [ ] `views/graph_view.tscn`
- [ ] `GraphEdit`, порты, связи, инспектор, toolbar.
- [ ] Sidecar layout.
- [ ] Коммит: `Add graph view`

### Шаг 5. Интеграция

- [ ] `main_view.gd`: `_setup_graph_view()`, режим Text/Graph.
- [ ] Синхронизация текста и графа.
- [ ] `apply_graph_text()` + `EditorUndoRedoManager`.
- [ ] Ошибки, тест, переходы к cue/строке.
- [ ] `files_moved` / `file_removed` для sidecar.
- [ ] Коммит: `Integrate graph view into dialogue editor`

### Шаг 6. Проверка и документация

- [ ] `tests/test_graph_builder.gd`
- [ ] `tests/test_graph_serializer.gd`
- [ ] `tests/test_graph_roundtrip.gd`
- [ ] Обновить `VISUAL_NODE_EDITOR_PLAN.md` фактическим статусом.
- [ ] Коммит: `Add graph editor tests and docs`

---

## 21. Статус реализации

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
      веток прямо из инспектора.
- [x] Редактирование типа inline-перехода (`=>` / `=><`) для реплик и ответов.
- [x] Соединение с любым top-level узлом через автоматическое создание cue.
- [x] Отсоединение переходов, возвратов и основного продолжения.
- [x] Собственный layered layout без предупреждений о циклах.
- [x] Улучшенное сопоставление позиций узлов (stable key / source line / тип).
- [x] Панель **Localization** с генерацией ID, экспортом CSV и preview.

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

Как открыть:

1. Открыть любой `.dialogue`-файл во вкладке **Dialogue**.
2. Нажать кнопку **Graph** на панели инструментов.
3. Выбрать узел, чтобы открыть инспектор справа.
4. Правый клик по пустому месту — добавить узел или удалить выбранный.
5. Кнопка **Test** запускает тестовую сцену с выбранного cue/строки.
6. Перетаскивание узла сохраняет его позицию в
   `<file>.dialogue.graph.json`.

---

## 18. Итог

Рекомендуемый путь:

1. Оставить `.dialogue` единственным источником правды.
2. Добавить graph-режим в существующую вкладку **Dialogue**.
3. Сначала сделать read-only граф, затем редактирование ядра, затем все
   продвинутые синтаксисы.
4. Использовать `DMCompiler` + source map для построения графа.
5. Использовать точечные текстовые патчи для обратной записи.
6. Хранить только layout в sidecar.
7. Переиспользовать существующие сохранение, компиляцию, тесты, ошибки и
   локализацию.

Такой подход даёт визуальный node-based редактор, который работает прямо в
проекте, не ломает существующий аддон и поддерживает весь заявленный функционал,
включая локализацию.
