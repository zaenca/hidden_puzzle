# Hybrid Puzzle + Hidden Object — Архитектурный план

Godot 4.7.2 stable · GDScript · 2D · portrait · Android first
Статус: **предложение, ожидает согласования**. Код не пишется до утверждения.

---

## 1. Краткое понимание продукта

### Основной игровой цикл

```
Мета (карта района / магазин)
   → игрок видит текущую задачу («поставить вывеску»)
   → входит в гибридный уровень
        нарратив (2–3 реплики)
        → puzzle-фаза: собирает изображение сцены
        → бесшовное раскрытие: границы пазла исчезают, картинка становится сценой
        → hidden-object фаза: ищет 5–8 обычных + 1–3 сюжетных предмета
        → результат: валюта + quest items
   → возврат в мету с фокусом на ту же задачу
   → применение предмета: визуальное состояние объекта меняется
   → открывается следующая задача (иногда через cooldown)
```

### Отличие core от меты

| | Core (уровень) | Мета (район/магазин) |
|---|---|---|
| Что это | Замкнутая сессия 60–150 сек | Персистентное состояние мира |
| Знает про | `LevelDefinition` и ничего больше | Задачи, состояния, экономику, cooldown |
| Результат | `LevelResult` (данные, не побочные эффекты) | Изменение save-состояния и визуала |
| Живёт | Пока сцена уровня загружена | Всегда (в сейве) |

**Ключевое архитектурное правило:** core-слой не знает ни об экономике, ни о пекарне, ни о задачах. Он получает описание уровня и возвращает структуру результата. Всё остальное делает мета-слой. Это и есть главная защита от «двадцати контроллеров под двадцать уровней».

### Как puzzle и hidden object образуют один уровень

Они **не две сцены**. Это две фазы над одним и тем же визуальным корнем.

Фон, слои и hidden-object цели существуют в сцене с самого начала, просто неактивны и скрыты под слоем пазла. Части пазла — это не отдельные PNG, а полигоны с UV-координатами по **той же самой текстуре**. Когда установлена последняя часть:

1. шейдер швов гасит границы (0.4 с),
2. слой пазла целиком уходит в alpha 0 (0.3 с) — под ним пиксель-в-пиксель то же изображение,
3. камера делает лёгкий push-in, включается ambient-анимация слоёв,
4. HO-слой становится активным, всплывает панель искомых предметов.

Смены сцены нет, загрузки нет, «второй мини-игры» визуально не существует. Это то, что делает гибрид гибридом, а не склейкой.

### Что проверяет vertical slice

Ровно одну гипотезу: **что цикл `puzzle → hidden object → quest item → видимое изменение мира → новая задача` ощущается как одна игра, а не как две**. Всё, что не проверяет эту гипотезу, из первой версии исключается.

---

## 2. Предлагаемая архитектура

### Слои

```
┌─ Services (autoload, тонкие) ─────────────────────────────────┐
│  Game · SaveService · ContentDB · PlayerState · TimeService   │
│  CooldownService · EventBus                                    │
└───────────────────────────────────────────────────────────────┘
        ↑ читают/пишут                     ↓ сигналы
┌─ Domain (чистый GDScript, RefCounted, без нод) ───────────────┐
│  MetaService · TaskResolver · RewardResolver · SaveMigrator    │
│  LevelResult · Requirement/Cost/Effect evaluators              │
└───────────────────────────────────────────────────────────────┘
        ↑ вызовы                            ↓ данные
┌─ Presentation (сцены, инстансятся, НЕ синглтоны) ─────────────┐
│  MapScene · ShopScene · HybridLevel · PuzzleModule · HOPhase   │
│  UI-экраны, панели, оверлеи                                    │
└───────────────────────────────────────────────────────────────┘
```

### Runtime-системы и зоны ответственности

| Система | Тип | Отвечает за | Явно НЕ отвечает за |
|---|---|---|---|
| `Game` | autoload | FSM приложения, маршрутизация экранов, async-загрузка/выгрузка сцен, передача контекста между экранами | Игровую логику, экономику |
| `ContentDB` | autoload | Индекс контента (id → путь), ленивая загрузка `LevelDefinition`, `MetaActionDefinition`, `ItemDefinition`, кэш с ограничением | Состояние игрока |
| `PlayerState` | autoload | Кошелёк, инвентарь, quest items, бустеры, флаги. Единственная точка мутации. Эмитит `changed` | Правила выдачи (это `RewardResolver`) |
| `MetaService` | domain-объект, владеет `Game` | Состояния магазинов/комнат/задач, применение `LevelResult`, запуск meta actions, применение эффектов | Отрисовку |
| `CooldownService` | autoload | Активные cooldown, offline-восстановление, сокращение, мгновенное завершение | Что произойдёт по завершении (это эффекты meta action) |
| `SaveService` | autoload | Сериализация, версионирование, миграции, атомарная запись, обработка битого сейва | Что именно сохранять (собирает у провайдеров) |
| `TimeService` | autoload | Единый источник времени, детект отката часов | — |
| `EventBus` | autoload | Только крупные доменные события для UI | Внутриуровневую коммуникацию |
| `HybridLevelController` | сцена | FSM уровня, порядок фаз, сбор `LevelResult` | Правила пазла и HO |
| `PuzzleModule` (интерфейс) | сцена | Своя механика, свой прогресс, свои бустеры | Награды, мету |
| `HiddenObjectPhase` | сцена | Цели, попадания, подсказки, таймер | Награды, мету |
| `ShopView` | сцена | Отрисовка визуальных состояний, hotspot'ы задач, камера | Логику задач |

### Способы коммуникации

Три уровня, строго разделённые:

**1. Внутри одного экрана — прямые сигналы `child → parent`.**
`JigsawModule.solved` слушает `HybridLevelController`. `HOPhase.target_found` слушает он же. Никакого EventBus, никаких глобальных вызовов. Родитель знает детей, дети родителя — нет.

**2. Между экранами — данные, а не вызовы.**
Уровень не вызывает мету. Он завершается и отдаёт объект:

```gdscript
class_name LevelResult extends RefCounted
var level_id: StringName
var success: bool
var quest_items: Array[StringName]
var soft_currency: int
var stats: Dictionary        # time, hints_used, misses
var boosters_spent: Dictionary
```

`Game` получает результат, отдаёт `MetaService.apply_level_result(result)`, затем маршрутизирует на нужный экран. Уровень при этом можно запустить из дебаг-меню, из теста, из редактора — он полностью автономен.

**3. Глобальные события — только «широкие» уведомления для UI.**

Разрешённый список `EventBus` (осознанно короткий — он растёт бесконтрольно, если не ограничить):

```gdscript
signal currency_changed(id: StringName, value: int)
signal inventory_changed(id: StringName, value: int)
signal quest_item_granted(id: StringName)
signal task_state_changed(task_id: StringName, state: int)
signal cooldown_started(action_id: StringName)
signal cooldown_finished(action_id: StringName)
signal shop_visual_changed(shop_id: StringName, slot_id: StringName, state_id: StringName)
```

**Правило:** если у события ровно один слушатель и он структурно рядом — это прямой сигнал, не EventBus.

### Где оправданы синглтоны, где нет

**Оправданы** (единственный экземпляр по природе, нужны из любой точки, переживают смену сцен): `Game`, `SaveService`, `ContentDB`, `PlayerState`, `TimeService`, `CooldownService`, `EventBus`, позже `AudioService`, `Settings`.

**Категорически нет:** `LevelController`, `PuzzleModule`, `HOPhase`, `ShopView`, любые UI-панели, `MetaService`.
`MetaService` — не autoload намеренно: он должен быть создаваем в тестах с подставным `PlayerState`, чтобы правила задач можно было проверять headless без сцен.

Зависимости в презентационные сцены передаются **инъекцией через `setup()`**, а не глобальным доступом:

```gdscript
# HybridLevel
func setup(ctx: LevelContext) -> void:
    _definition = ctx.definition
    _boosters = ctx.booster_provider     # интерфейс, не PlayerState напрямую
    _rng_seed = ctx.seed
```

Это то, что позволит запустить любой уровень в изоляции и позже подключить level editor.

### Как не допустить сцепления core / hidden object / меты

Пять правил, которые надо соблюдать буквально:

1. В `res://core/**` **запрещён** `import`/обращение к `PlayerState`, `MetaService`, `CooldownService`. Проверяется грепом в CI-скрипте валидации.
2. Уровень получает `LevelDefinition` и `LevelContext`, отдаёт `LevelResult`. Других каналов нет.
3. Мета оперирует **строковыми идентификаторами** состояний, никогда — ссылками на ноды. В сейве нет ни одного `NodePath`.
4. `PuzzleModule` — контракт, а не класс-предок с логикой. Замена jigsaw на screws не должна трогать `HybridLevelController`.
5. HO-цели знают только свой `item_id`. Что такое `key_part_a` и зачем он нужен — знает только мета.

### Контракт puzzle-модуля

```gdscript
class_name PuzzleModule extends Node2D

signal solved()
signal progress_changed(done: int, total: int)
signal interaction(kind: StringName)      # для звука/аналитики

func setup(params: PuzzleParams, art: SceneArt, rng: RandomNumberGenerator) -> void
func begin() -> void
func apply_booster(booster_id: StringName) -> bool
func get_hint_target() -> Variant          # для универсального бустера
func serialize_state() -> Dictionary       # опциональный resume, не в MVP
```

Регистрация: `PuzzleRegistry` — словарь `module_id: StringName → PackedScene`, заполняется одним файлом-конфигом. Добавление screws позже = новая сцена + одна строка в реестре.

---

## 3. Структура Godot scenes и nodes

### Дерево каталогов

```
res://
├─ autoload/           game.gd, save_service.gd, content_db.gd, ...
├─ core/               ← не знает про мету и экономику
│  ├─ level/           hybrid_level.tscn/.gd, level_context.gd, level_result.gd
│  ├─ puzzle/
│  │  ├─ puzzle_module.gd            (контракт)
│  │  ├─ puzzle_registry.gd
│  │  └─ jigsaw/                     jigsaw_module.tscn, piece.tscn, jigsaw_geometry.gd
│  ├─ hidden_object/   ho_phase.tscn/.gd, ho_target_view.gd
│  └─ scene_view/      scene_view.tscn/.gd  (фон + слои, общий для фаз)
├─ meta/
│  ├─ map/             map_scene.tscn
│  ├─ shop/            shop_scene.tscn, state_slot.gd, task_hotspot.gd
│  └─ services/        meta_service.gd, task_resolver.gd, effects/
├─ data/               определения классов Resource
├─ content/
│  ├─ levels/          bakery_01.tres … bakery_20.tres
│  ├─ targets/         bakery_01_targets.tres
│  ├─ actions/         craft_storeroom_key.tres
│  ├─ items/           item_db.tres
│  └─ shops/           bakery.tres, bakery_visual.tscn
├─ ui/                 общие компоненты, safe_area.gd
├─ art/                bg/, layers/, items/, ui/
└─ tools/              ho_marker_tool.gd (@tool), validate_content.gd (headless)
```

### Scene tree гибридного уровня

```
HybridLevel (Node2D)                         [hybrid_level.gd — FSM уровня]
├─ CameraRig (Node2D)                        [camera_rig.gd — pan/zoom/clamp/push-in]
│  └─ Camera2D
├─ SceneView (Node2D)                        ← общий визуал ОБЕИХ фаз
│  ├─ Background (Sprite2D)
│  ├─ Layers (Node2D)                        доп. PNG-слои (свет, пар, тени)
│  └─ Targets (Node2D)                       Area2D, спавнятся из HOTargetSet
├─ PuzzleHost (Node2D)                       сюда инстансится PuzzleModule
├─ DragLayer (Node2D, z=100)                 перетаскиваемая часть поверх всего
├─ FX (Node2D)                               частицы находки, glow, seam-fade
└─ UI (CanvasLayer)
   └─ SafeArea (MarginContainer)             [safe_area.gd]
      ├─ TopBar                              прогресс фазы, валюта, пауза
      ├─ PhaseUI (Control)                   PuzzleTray ⇄ HOItemBar (переключение)
      ├─ BoosterBar
      └─ Overlays                            Narrative / Pause / Result
```

`SceneView` — ключевой узел. Он **один** и не пересоздаётся между фазами. `PuzzleHost` рисуется поверх него и в момент решения гаснет.

### Организация jigsaw parts

```
JigsawModule (Node2D)
├─ Board (Node2D)          пустой; слоты — данные (Array[Slot]), не ноды
├─ Pieces (Node2D)         N × Piece
└─ TrayAnchor (Marker2D)   зона раскладки в нижней трети экрана

Piece (Node2D)
├─ Poly (Polygon2D)        texture = общая текстура сцены, uv = вырез куска
├─ Outline (Line2D)        гаснет при reveal
└─ Hit (Area2D → CollisionPolygon2D)   тот же polygon, +padding для пальца
```

**Важное производственное решение:** части пазла **не рисуются художником**. `jigsaw_geometry.gd` генерирует сетку jigsaw-полигонов (кривые Безье замочков) по параметрам `cols × rows × seed`, а `Polygon2D` берёт UV с общей текстуры. Следствие:

- стоимость производства jigsaw-контента для нового уровня = **0** (нужен только фон, который и так нужен для HO),
- любое изображение мгновенно становится пазлом,
- масштабирование до 1000+ уровней по этой оси решено полностью.

Это прямо снимает риск «стоимость производства jigsaw layouts» из раздела 11.

### Размещение hidden-object targets

Цели живут в `HOTargetSet` (Resource) в **нормализованных координатах 0..1** относительно фона, а не в координатах сцены. Это делает их независимыми от разрешения PNG и от aspect ratio.

```gdscript
class_name HOTarget extends Resource
@export var id: StringName
@export var item_id: StringName                 # ключ в ItemDB (имя, иконка)
@export_enum("normal", "themed", "quest") var kind := "normal"
@export var shape: PackedVector2Array           # полигон, нормализованный
@export var layer: StringName = &"base"         # если предмет на скрытом слое
@export var reveal_after: StringName = &""      # опц. цепочка: сначала открыть ящик
@export var hint_zoom: float = 1.6
```

На старте — минимальный `@tool` скрипт `ho_marker_tool.gd`: открывает фон в редакторе, позволяет кликами обвести цель, выбрать `item_id` из `ItemDB` и сохранить `.tres`. ~150 строк, окупается на третьем уровне. Полноценный level editor — только после проверки прототипа.

### Scene tree пекарни

Один универсальный `ShopScene.tscn` на **все** магазины. Визуал конкретного магазина — инстанс из `ShopDefinition.visual_scene`.

```
ShopScene (Node2D)                     [shop_view.gd]
├─ Camera2D                            pan/zoom с clamp по границам визуала
├─ VisualHost (Node2D)
│  └─ BakeryVisual (инстанс)
│     ├─ Background (Sprite2D)
│     ├─ Slots (Node2D)
│     │  ├─ facade_trash (StateSlot)   дети: dirty, cleaned
│     │  ├─ sign        (StateSlot)    дети: missing, broken, installed
│     │  ├─ door        (StateSlot)    дети: closed, open
│     │  ├─ showcase    (StateSlot)    дети: broken, repaired, filled
│     │  ├─ lights      (StateSlot)    дети: off, on
│     │  └─ crowd       (StateSlot)    дети: empty, visitors
│     └─ Ambient (Node2D)              частицы, птицы, свет
├─ Hotspots (Node2D)                   TaskHotspot × N (Area2D + иконка)
└─ UI (CanvasLayer)
   └─ SafeArea → TaskPanel / TopBar / MetaActionPanel / CooldownPanel
```

### Способ смены визуальных состояний

`StateSlot` — узел с `@export var slot_id: StringName`. Его дети — варианты состояния, **имя ноды = id состояния**. Активен ровно один.

```gdscript
func set_state(state_id: StringName, animate: bool) -> void
```

При смене: старый вариант fade-out, новый fade-in + scale-punch + опциональный `GPUParticles2D` из конфига. Копии пекарни под каждое состояние **не создаются** — запрет из спеки соблюдён структурно.

`ShopView` при входе читает `MetaService.get_shop_state("bakery").slots` (`Dictionary[StringName, StringName]`) и применяет всё разом без анимации. Анимация — только при изменении в рантайме.

### Возврат из уровня к конкретной meta action

```
HybridLevel.finish()
  → Game.on_level_finished(LevelResult)
  → MetaService.apply_level_result(result)
        · PlayerState.grant(rewards)
        · quest items → инвентарь
        · TaskResolver пересчитывает состояния задач
        · возвращает MetaFocus { shop_id, task_id, action_id, auto_open }
  → SaveService.save()
  → Game.goto(SHOP, {focus = focus})
  → ShopView.apply_focus(focus)
        · камера летит к hotspot задачи
        · открывается MetaActionPanel с кнопкой «Установить»
```

Никаких прямых ссылок: `MetaFocus` — это три строки. Если задача не найдена — фокус игнорируется, игрок просто попадает в магазин.

---

## 4. State machines

### 4.1 Приложение (`Game`)

```
BOOT → LOADING_SAVE → (MAP ⇄ SHOP) → NARRATIVE → LEVEL → LEVEL_RESULT → SHOP
                          ↑                                                │
                          └────────────────────────────────────────────────┘
```

| Переход | Условие |
|---|---|
| `BOOT → LOADING_SAVE` | автолоады готовы |
| `LOADING_SAVE → MAP` | сейв валиден или создан новый |
| `LOADING_SAVE → SHOP` | в сейве есть `last_shop` и туториал пройден |
| `SHOP → NARRATIVE` | игрок нажал «Играть» у доступной задачи, ресурсы списаны |
| `NARRATIVE → LEVEL` | нарратив показан или пропущен (или его нет) |
| `LEVEL → LEVEL_RESULT` | `success` или `failed` |
| `LEVEL_RESULT → SHOP` | награды применены и сохранены |

Переходы всегда через `Game.goto(state, payload)`. Прямых `change_scene_to_file` в коде экранов нет.

### 4.2 Гибридный уровень

```
INTRO → PUZZLE → REVEAL → HIDDEN_OBJECT → OUTRO → RESULT
   │                                        
   └──────────── PAUSED ⇄ (любое) ──────────┘
                     
PUZZLE / HIDDEN_OBJECT → FAILED (только если включён таймер)
```

| Состояние | Что происходит | Выход |
|---|---|---|
| `INTRO` | 2–3 реплики поверх затемнённой сцены | тап / автопропуск |
| `PUZZLE` | активен `PuzzleModule`, `SceneView.Targets` выключены, зум запрещён | сигнал `solved` |
| `REVEAL` | 0.9 с: гаснут швы → гаснет слой → push-in камеры → включаются Targets | по таймеру |
| `HIDDEN_OBJECT` | активна `HOPhase`, разрешён pan/zoom | все обязательные цели найдены |
| `OUTRO` | подлёт найденных quest items к иконке, короткая реплика | по таймеру |
| `RESULT` | сборка `LevelResult`, экран награды | подтверждение игрока |
| `FAILED` | предложение «продолжить» (бустер/mock hard currency) | retry / выход |

`REVEAL` — отдельное состояние намеренно: это самая важная секунда игры, у неё должен быть свой владелец, а не «хвост» пазла.

### 4.3 Puzzle-фаза (jigsaw)

```
IDLE → PICKED → DRAGGING → (SNAPPED | RETURNED) → IDLE → ... → SOLVED
```

- `PICKED` — палец опущен на часть, часть поднята в `DragLayer`, scale ×1.1.
- `DRAGGING` — следует за пальцем со сглаживанием; ближайший валидный слот в радиусе `snap_px` подсвечивается.
- `SNAPPED` — tween в слот, часть теряет интерактивность, `progress_changed`.
- `RETURNED` — возврат в лоток.
- `SOLVED` — все слоты заполнены → `solved`.

Бустер «автоустановка» = искусственный `SNAPPED` для случайной неустановленной части.

### 4.4 Hidden-object фаза

```
SEARCHING → FOUND_FEEDBACK → SEARCHING → ... → COMPLETE
    │
    └→ MISS_PENALTY → SEARCHING
    └→ HINTING → SEARCHING
```

- Попадание: точка тапа внутри полигона цели **или** ближе `touch_forgiveness_px`, если в радиусе ровно одна цель.
- `FOUND_FEEDBACK` (0.4 с): частицы, полёт иконки в панель, звук. Ввод не блокируется.
- `MISS_PENALTY`: короткий shake, минус время (если таймер включён), кулдаун 0.5 с против «прочёсывания» тапами.
- Quest-цели обязательны всегда; из `normal` требуется `required_normal`.

### 4.5 Meta task

```
LOCKED → AVAILABLE → IN_PROGRESS → READY_TO_APPLY → APPLYING → COMPLETED
                          ↑              │
                          └──────────────┘   (не хватило предметов после уровня)
```

| Переход | Условие |
|---|---|
| `LOCKED → AVAILABLE` | выполнены `unlock_requirements` (задачи/уровни/флаги) |
| `AVAILABLE → IN_PROGRESS` | пройден хотя бы один связанный уровень |
| `IN_PROGRESS → READY_TO_APPLY` | собраны все `required_items` и хватает `costs` |
| `READY_TO_APPLY → APPLYING` | игрок нажал кнопку; списаны costs; если `duration_sec > 0` — запущен cooldown |
| `APPLYING → COMPLETED` | cooldown = 0 и игрок забрал результат → применены `effects` |

**Инвариант:** в каждый момент у игрока должна быть ≥1 задача в `AVAILABLE`/`IN_PROGRESS`. `TaskResolver` проверяет это после каждого пересчёта и логирует ошибку контента, если инвариант нарушен, — так «мёртвый» cooldown ловится на этапе разработки, а не в проде.

### 4.6 Cooldown

```
INACTIVE → RUNNING → READY → CLAIMED
              │
              ├→ reduce(sec)      прохождение уровня
              └→ finish_now()     mock rewarded ad / mock hard currency
```

Состояние `READY` отделено от `CLAIMED` намеренно: эффекты применяются только когда игрок вернулся и увидел это. Иначе игрок пропускает главную награду цикла — визуальное изменение мира.

### 4.7 Магазин и комната

```
Магазин:  LOCKED → DISCOVERED → IN_RESTORATION → RESTORED → OPERATING
Комната:  LOCKED → DISCOVERED → IN_RESTORATION → RESTORED
```

Комната переходит в `RESTORED`, когда все её задачи `COMPLETED`. Магазин — когда все комнаты `RESTORED`; `OPERATING` добавляет ambient-состояния (люди, свет, витрина полная) и открывает следующий магазин на карте.

---

## 5. Data model

### Выбор подхода к контенту: Resources + JSON

**Рекомендация: гибрид с чётким разделением.**

| Что | Формат | Почему |
|---|---|---|
| Контент (уровни, цели, действия, предметы, магазины) | **Godot Resources (`.tres`)** | типизация, inspector, прямые ссылки на `Texture2D`/`PackedScene`, автодополнение, валидация на этапе загрузки, редактируется дизайнером без внешних инструментов |
| Сейв игрока | **JSON** | прозрачен и дебажится, тривиально мигрируется, не ломается при переименовании классов, не исполняет код при загрузке |
| Индекс контента | **JSON** (генерируемый) | лёгкий, читается на старте целиком, `.tres` грузятся лениво по нему |

**Плюсы Resources для контента:** дизайнер правит уровень в редакторе Godot без внешнего пайплайна; ссылка на текстуру ломается на этапе импорта, а не в рантайме; наследование (`PuzzleParams` → `JigsawParams`) даёт типизированные параметры модулей.

**Минус Resources и как он лечится:** `.tres` тянут за собой ресурсы по ссылкам, поэтому загрузить каталог из 1000 уровней = загрузить 1000 фонов. Лечение — **индекс**: `content/level_index.json` содержит только `{id, path, shop, task, order, difficulty}`. Он и грузится на старте; сам `LevelDefinition` — только для текущего уровня. Второй минус — плохой merge в git; для команды >2 человек это станет проблемой, тогда добавляется экспорт в JSON. Сейчас не нужно.

**Почему сейв не Resource:** `ResourceLoader` на пользовательском файле — вектор исполнения кода и жёсткая привязка к именам классов. Переименование скрипта ломает сейвы всех игроков. JSON от этого свободен.

### 5.1 Определения (классы Resource)

```gdscript
class_name LevelDefinition extends Resource
@export var id: StringName
@export var shop_id: StringName
@export var task_id: StringName                  # к какой meta task относится
@export var order: int                           # позиция в цепочке
@export var difficulty: int = 1
@export var narrative: NarrativeDefinition       # может быть null
@export var art: SceneArt
@export var puzzle: PuzzleParams                 # полиморфный (JigsawParams, ...)
@export var hidden_object: HOConfig
@export var rewards: RewardTable
@export var quest_grants: Array[StringName]      # item_id, выдаются при success

class_name SceneArt extends Resource
@export var background: Texture2D
@export var layers: Array[SceneLayer]            # id, texture, offset, parallax, ambient
@export var reference_size: Vector2i             # для нормализации координат

class_name PuzzleParams extends Resource         # базовый
@export var module_id: StringName = &"jigsaw"

class_name JigsawParams extends PuzzleParams
@export var cols: int = 3
@export var rows: int = 4
@export var seed: int = 0
@export var tab_ratio: float = 0.22
@export var snap_distance_px: float = 56.0
@export var shuffle_tray: bool = true

class_name HOConfig extends Resource
@export var target_set: HOTargetSet
@export var required_normal: int = 6
@export var time_limit_sec: float = 0.0          # 0 = без таймера
@export var miss_penalty_sec: float = 0.0
@export var allow_zoom: bool = true

class_name ItemDefinition extends Resource
@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export_enum("normal", "themed", "quest", "material") var kind := "normal"
@export var stackable: bool = true

class_name MetaActionDefinition extends Resource
@export var id: StringName
@export var title: String
@export var description: String
@export var requirements: Array[Requirement]
@export var costs: Array[Cost]
@export var duration_sec: int = 0
@export var reduce_per_level_sec: int = 0
@export var speedup_hard_cost: int = 0
@export var allow_ad_speedup: bool = false
@export var effects: Array[MetaEffect]

class_name Requirement extends Resource          # наследники:
#   ItemRequirement { item_id, amount }
#   TaskRequirement { task_id, state }
#   LevelRequirement { level_id }
#   FlagRequirement { flag }

class_name Cost extends Resource
@export var currency_or_item: StringName
@export var amount: int

class_name MetaEffect extends Resource           # наследники:
#   SetVisualStateEffect { shop_id, slot_id, state_id }
#   GrantEffect { id, amount }
#   ConsumeEffect { item_id, amount }
#   UnlockTaskEffect { task_id }
#   UnlockLevelsEffect { level_ids }
#   SetShopStateEffect { shop_id, state }
#   NarrativeEffect { dialog_id }

class_name MetaTaskDefinition extends Resource
@export var id: StringName
@export var shop_id: StringName
@export var room_id: StringName
@export var title: String
@export var unlock_requirements: Array[Requirement]
@export var level_ids: Array[StringName]
@export var action_id: StringName
@export var hotspot_id: StringName               # к какому hotspot летит камера

class_name ShopDefinition extends Resource
@export var id: StringName
@export var display_name: String
@export var visual_scene: PackedScene
@export var rooms: Array[RoomDefinition]
@export var default_slots: Dictionary            # slot_id → state_id
@export var map_position: Vector2
```

### 5.2 Конкретный пример: определение гибридного уровня

`content/levels/bakery_04.tres` (в текстовом виде для читаемости):

```
LevelDefinition
  id            = "bakery_04"
  shop_id       = "bakery"
  task_id       = "task_install_sign"
  order         = 4
  difficulty    = 1
  narrative     = NarrativeDefinition("dlg_sign_intro")
  art           = SceneArt
      background      = res://art/bg/bakery_sign_closeup.png
      reference_size  = (1080, 1440)
      layers          = [ SceneLayer("dust", dust.png, parallax 0.02),
                          SceneLayer("sun",  sunrays.png, ambient fade-loop) ]
  puzzle        = JigsawParams
      module_id     = "jigsaw"
      cols = 3, rows = 4, seed = 40401
      tab_ratio = 0.22, snap_distance_px = 56
  hidden_object = HOConfig
      target_set        = res://content/targets/bakery_04_targets.tres
      required_normal   = 6
      time_limit_sec    = 0
      allow_zoom        = true
  rewards       = RewardTable { coins = 60, xp = 10 }
  quest_grants  = [ "sign_letter_b", "sign_bracket" ]
```

`content/targets/bakery_04_targets.tres`:

```
HOTargetSet.targets = [
  HOTarget { id="t01" item_id="nail"          kind=normal shape=[(0.21,0.62),(0.26,0.62),(0.26,0.68),(0.21,0.68)] }
  HOTarget { id="t02" item_id="screwdriver"   kind=normal shape=[...] }
  HOTarget { id="t03" item_id="rag"           kind=normal shape=[...] }
  HOTarget { id="t04" item_id="paint_can"     kind=normal shape=[...] }
  HOTarget { id="t05" item_id="ladder_step"   kind=normal shape=[...] }
  HOTarget { id="t06" item_id="lightbulb"     kind=themed shape=[...] }
  HOTarget { id="t07" item_id="wire"          kind=normal shape=[...] }
  HOTarget { id="q01" item_id="sign_letter_b" kind=quest  shape=[...] hint_zoom=1.8 }
  HOTarget { id="q02" item_id="sign_bracket"  kind=quest  shape=[...] reveal_after="t03" }
]
```

Обратите внимание: `bakery_04` содержит **ноль строк кода**. Двадцать уровней — двадцать таких файлов и ни одного контроллера.

### 5.3 Конкретный пример: meta action изготовления ключа

`content/actions/craft_storeroom_key.tres`:

```
MetaActionDefinition
  id                   = "craft_storeroom_key"
  title                = "Изготовить ключ от кладовой"
  description          = "Мастер сделает ключ по чертежу. Это займёт время."
  requirements = [
      ItemRequirement { item_id = "key_part_a",  amount = 1 }
      ItemRequirement { item_id = "key_part_b",  amount = 1 }
      ItemRequirement { item_id = "key_blank",   amount = 1 }
      ItemRequirement { item_id = "lock_number", amount = 1 }
  ]
  costs = [ Cost { currency_or_item = "coins", amount = 250 } ]
  duration_sec         = 3600
  reduce_per_level_sec = 600          # каждый пройденный core level −10 мин
  speedup_hard_cost    = 40           # mock hard currency
  allow_ad_speedup     = true         # mock rewarded ad, −15 мин
  effects = [
      ConsumeEffect       { item_id="key_part_a" amount=1 }
      ConsumeEffect       { item_id="key_part_b" amount=1 }
      ConsumeEffect       { item_id="key_blank"  amount=1 }
      GrantEffect         { id="storeroom_key"   amount=1 }
      UnlockTaskEffect    { task_id="task_open_storeroom" }
      SetVisualStateEffect{ shop_id="bakery" slot_id="storeroom_door" state_id="unlocked" }
      NarrativeEffect     { dialog_id="dlg_key_ready" }
  ]
```

Пока действие в cooldown, `TaskResolver` гарантирует наличие параллельной задачи (`task_decorate_hall`, уровни 13–14) — это и есть реализация требования «игрок не теряет возможность играть».

### 5.4 Сейв: структура и пример активного cooldown

```json
{
  "version": 3,
  "created_at": 1755990000,
  "saved_at": 1756001234,
  "player": {
    "coins": 1420,
    "hard": 55,
    "materials": { "metal_scrap": 4 },
    "lives": 5,
    "lives_refill_at": 0,
    "xp": 340
  },
  "inventory": {
    "quest": { "key_part_a": 1, "key_blank": 1, "lock_number": 1 },
    "boosters": { "universal_hint": 3, "extra_time": 1 }
  },
  "progress": {
    "current_level": "bakery_13",
    "completed_levels": ["bakery_01", "...", "bakery_12"],
    "levels_completed_total": 12,
    "flags": { "tutorial_done": true, "met_mayor": true }
  },
  "shops": {
    "bakery": {
      "state": "in_restoration",
      "slots": {
        "facade_trash": "cleaned",
        "sign": "installed",
        "door": "open",
        "showcase": "repaired",
        "lights": "on",
        "storeroom_door": "locked"
      },
      "rooms": { "hall": "in_restoration", "storeroom": "locked" },
      "tasks": {
        "task_clear_facade": "completed",
        "task_install_sign": "completed",
        "task_craft_key":    "applying",
        "task_decorate_hall":"in_progress"
      }
    }
  },
  "cooldowns": {
    "craft_storeroom_key": {
      "started_at":  1755998000,
      "ends_at":     1756001600,
      "total_sec":   3600,
      "reduced_sec": 600,
      "source_task": "task_craft_key",
      "claimed":     false
    }
  }
}
```

Ни одного `NodePath`, ни одной ссылки на сцену — только идентификаторы. Это выполняет требование «не связывать save data с прямыми ссылками на scene nodes».

---

## 6. Content pipeline

### Как добавляется новый уровень

1. **Подключить изображение.** Положить `bg/<level>.png` в `art/bg/`. Импорт-пресет для фонов уже настроен (VRAM-сжатие, mipmaps off, filter on). Слои — опционально, в `art/layers/`.
2. **Создать puzzle layout.** Ничего не рисовать. Создать `JigsawParams`, указать `cols/rows/seed`. Кнопка «Preview» в инструменте показывает нарезку поверх фона; если замок попал на важную деталь — сменить `seed`.
3. **Расставить hidden-object targets.** Открыть `tools/ho_marker_tool.tscn`, выбрать фон, обвести цели, выбрать `item_id` из `ItemDB`, сохранить `HOTargetSet`.
4. **Выбрать quest targets.** Тем же инструментом пометить 1–3 цели как `kind = quest` и заполнить `quest_grants` уровня теми же `item_id` (валидатор проверит совпадение).
5. **Настроить rewards.** `RewardTable` — из шаблона под `difficulty`; ручные правки только там, где нужно.
6. **Связать уровень с meta action.** Указать `task_id`; в `MetaTaskDefinition.level_ids` добавить уровень; в `MetaActionDefinition.requirements` — предметы, которые он выдаёт.
7. **Проверить валидность.** Запустить валидатор.

Ни один шаг не требует написания кода. Это и есть проверка на то, что архитектура data-driven.

### Валидатор

`tools/validate_content.gd`, запускается из редактора и headless:

```bash
godot --headless --path . --script res://tools/validate_content.gd
```

Проверки:

- уникальность всех `id` (уровни, цели, действия, задачи, предметы);
- каждый `item_id` в `HOTarget` существует в `ItemDB`;
- каждый `quest_grants` уровня действительно присутствует как `kind=quest` цель;
- каждый quest item **потребляется** хотя бы одним `MetaActionDefinition.requirements` — иначе это мусор в инвентаре;
- каждая `MetaTaskDefinition` имеет ≥1 уровень и валидный `action_id` и `hotspot_id`;
- все `SetVisualStateEffect` ссылаются на существующие `slot_id` и `state_id` в визуальной сцене магазина;
- `required_normal ≤` количество целей `kind=normal`;
- все полигоны целей внутри `[0,1]` и площадь ≥ минимального touch-размера при базовом зуме;
- цепочка `order` уровней внутри магазина без дыр и дублей;
- **проверка «мёртвого» прогресса**: симуляция линейного прохождения — на каждом шаге есть ≥1 доступная задача; в момент старта каждого cooldown есть ≥1 параллельная.

Последняя проверка предотвращает самый дорогой класс контент-багов и стоит примерно 80 строк.

### Инструменты: сейчас и потом

**Сейчас (в MVP):**
- `ho_marker_tool` — разметка целей (без него разметка руками нежизнеспособна уже на пятом уровне);
- jigsaw preview (кнопка в том же инструменте);
- `validate_content` — headless-валидатор;
- debug-меню: запуск любого уровня по id, выдача валюты/предметов, сброс сейва, перемотка cooldown.

**Только после проверки прототипа:**
- полноценный in-game level editor;
- балансировочные таблицы и импорт из CSV/Sheets;
- автогенерация HO-целей по слоям PSD;
- превью-рендер уровня в атлас для сторе-скриншотов;
- система A/B-конфигов.

---

## 7. Save и cooldown

### Когда сохранять

| Момент | Почему |
|---|---|
| Завершение уровня (после применения наград) | главная точка потери прогресса |
| Применение meta action / старт cooldown | игрок потратил ресурсы |
| Claim результата cooldown | применены эффекты |
| Покупка/трата (в т.ч. mock) | деньги |
| `NOTIFICATION_APPLICATION_PAUSED` / `WM_GO_BACKGROUND` | Android может убить процесс без предупреждения |
| `NOTIFICATION_WM_CLOSE_REQUEST` | выход |

**Не** сохранять: по таймеру, каждый кадр, внутри уровня по каждой найденной цели. Незавершённый уровень при крэше теряется — это осознанное допущение прототипа (mid-level resume добавляется позже через `PuzzleModule.serialize_state()`, контракт для этого уже есть).

### Версионирование и миграции

```gdscript
const CURRENT_VERSION := 3
const MIGRATIONS := {
    1: "_migrate_1_to_2",
    2: "_migrate_2_to_3",
}
```

Загрузка: читаем `version`, прогоняем цепочку миграций по возрастанию, пишем результат обратно. Миграция — чистая функция `Dictionary → Dictionary`, покрывается юнит-тестом на зафиксированном примере старого сейва. Если `version > CURRENT_VERSION` (откат версии приложения) — сейв не трогаем, показываем предупреждение и работаем в read-only, чтобы не уничтожить прогресс.

### Хранение quest items и валют

Всё в `PlayerState` как плоские словари `StringName → int`. Нет отдельных классов под каждую валюту — валюта это `id` + `amount`, а её смысл описан в `ItemDefinition`/`CurrencyDefinition`. Добавление новой валюты = запись в контенте, ноль изменений в коде сейва.

### Хранение состояния пекарни

`shops[shop_id].slots` — словарь `slot_id → state_id`. Ничего больше. Восстановление: `ShopView` применяет словарь к `StateSlot`-узлам по именам. Если в сейве есть `slot_id`, которого нет в визуальной сцене (контент изменился между версиями) — запись игнорируется с предупреждением, игра не падает. Обратный случай (в сцене есть слот, которого нет в сейве) — берётся `ShopDefinition.default_slots`.

### Восстановление cooldown после закрытия приложения

Хранится **абсолютный `ends_at`** (unix), а не оставшееся время. При старте `CooldownService.restore()`:

```
remaining = ends_at - now
remaining <= 0  → состояние READY, ждём claim игроком
remaining >  0  → RUNNING, локальный таймер только для отображения
```

Никакого «тика» в фоне не нужно — время само идёт.

**Защита от перевода часов (минимальная, честная для прототипа):** дополнительно храним `last_seen_at`. Если `now < last_seen_at - 60` — часы отмотали назад; сдвигаем `ends_at` на ту же дельту, чтобы отмотка не давала выигрыша. Перевод часов **вперёд** в прототипе не блокируется — это допущение, честно фиксируем; корректное решение требует серверного времени и выходит за рамки offline-прототипа.

### Повреждённый сейв

1. Атомарная запись: пишем в `user://save.tmp`, `flush`, затем `rename` поверх `user://save.json`. Прерывание записи не разрушает предыдущий сейв.
2. Перед перезаписью прошлый файл копируется в `user://save.bak`.
3. Загрузка: `save.json` → при ошибке парсинга/валидации → `save.bak` → при ошибке → новый сейв + пометка `recovered: true` в логе.
4. Валидация после парсинга: наличие `version`, тип корневого объекта, отсутствие отрицательных валют.

### Что допустимо оставить без защиты в прототипе

- шифрование и подпись сейва (сейв редактируется руками — это удобно для тестирования);
- античит и серверная валидация;
- облачные сохранения;
- защита от перевода часов вперёд;
- mid-level resume.

Всё перечисленное добавляется без изменения архитектуры: точка входа одна — `SaveService`.

---

## 8. Mobile concerns

### Ввод

- Обработка через `InputEventScreenTouch` / `InputEventScreenDrag`. `Input.emulate_mouse_from_touch = false`, `emulate_touch_from_mouse = true` — мышь на ПК автоматически превращается в touch, и в коде существует **только один** путь ввода. Это снимает целый класс расхождений «на ПК работает, на телефоне нет».
- Никакого hover-зависимого UI. Подсветка слота в jigsaw появляется во время drag, а не при наведении.
- Multitouch: в MVP один активный drag (по `event.index` первого касания); pinch-zoom обрабатывается отдельно и только в HO-фазе.

### Drag jigsaw parts

- Палец перекрывает часть → при захвате часть смещается вверх на ~60 px и увеличивается ×1.1, чтобы оставаться видимой.
- Захват: `Area2D` с полигоном + расширение на `max(0, 48px - размер части)`.
- Снап: ближайший свободный слот в радиусе `snap_distance_px` (в экранных пикселях, не в мировых — иначе на разных плотностях ощущается по-разному).
- При отпускании вне слота — плавный возврат в лоток, без наказания.
- Сетка не мельче 3×4 в начале и не мельче ~4×6 в поздних уровнях: минимальная сторона части ≥ 110 px при базовом зуме.

### Tap hidden objects

- Порог различения tap/drag: смещение < 12 px и время < 300 мс.
- `touch_forgiveness_px ≈ 24`: если тап не попал в полигон, но ровно одна цель в радиусе — засчитываем.
- Мелкие цели: минимальная эффективная площадь попадания расширяется до 44×44 px независимо от полигона (валидатор предупреждает, если цель меньше).

### Camera zoom / pan

- `CameraRig` с `zoom ∈ [1.0, 2.5]`, pan с clamp по границам фона, инерция + rubber-band на границах.
- В puzzle-фазе камера зафиксирована (иначе зум конфликтует с drag).
- В HO-фазе — pinch и drag двумя пальцами; одним пальцем — только tap, чтобы не «терять» тапы при попытке скролла.
- Подсказка делает `tween` камеры к цели с `hint_zoom`.

### Portrait scaling, safe areas, aspect ratios

- Базовое разрешение `1080×1920`, `stretch_mode = canvas_items`, `stretch_aspect = expand`.
- Диапазон поддержки 9:16 … 9:22 (от планшетоподобных до узких флагманов).
- Фоны рисуются с **запасом ~12% по вертикали**, который может быть обрезан на широких экранах; вся значимая композиция и все HO-цели — внутри safe-зоны. Валидатор проверяет, что полигоны целей лежат в безопасном прямоугольнике.
- `SafeAreaContainer` (`safe_area.gd`) читает `DisplayServer.get_display_safe_area()` и выставляет margins; весь UI — его потомок. Игровое поле под вырезом может быть, интерактивные элементы — нет.

### Управление памятью PNG

- Фоны: max 1440×2560, импорт `VRAM Compressed` (ASTC/ETC2 на Android), mipmaps off, `Detect 3D` off.
- Иконки предметов и UI: атласы, `Lossless`.
- **Не** держать в памяти больше одного уровня и одного магазина. `Game` выгружает предыдущий экран до инстанса следующего, между ними — короткий loading-оверлей.
- Загрузка `LevelDefinition` и его текстур — через `ResourceLoader.load_threaded_request/get_status` с прогресс-баром; каталог уровней целиком не грузится никогда (см. индекс в §5).
- `ContentDB` держит LRU-кэш на N последних определений (N=3), остальное освобождается по refcount.

### Производительность

Цель — 60 FPS на среднем Android (условно Snapdragon 6-го класса, 4 ГБ).

- Никаких `_process` на десятках нод: части пазла статичны вне drag; HO-цели — `Area2D` без обработки кадров.
- Tween вместо `AnimationPlayer` для простых переходов; `AnimationPlayer` — только для ambient-циклов.
- Частицы: `GPUParticles2D`, лимит 64 на эффект, не более 3 одновременных.
- Один общий шейдер для reveal-эффекта швов; постэффекты — на `CanvasLayer`, не на каждом спрайте.
- Профилирование на реальном устройстве с M1 — не откладывать до конца.

---

## 9. MVP scope (vertical slice)

### Границы

**Уровни 1–5** по контент-плану: район → фасад → крупный план фасада → вывеска → входная дверь.

Что обязательно есть:

| Требование | Реализация в слайсе |
|---|---|
| Карта района | статичная PNG-карта, пекарня + 2 заблокированных здания «серым» |
| Пекарня | один `ShopScene` + `BakeryVisual` с 4 `StateSlot` |
| Короткий нарратив | 3 диалога по 2–3 реплики, текст из `NarrativeDefinition` |
| Несколько визуальных состояний | `facade_trash: dirty→cleaned`, `sign: missing→installed`, `door: closed→open`, `lights: off→on` |
| ≥5 последовательных гибридных уровней | 5 `.tres`, ноль контроллеров |
| puzzle → hidden object в одной сцене | `SceneView` + reveal-переход |
| Выдача ключевого предмета | `sign_letter_b`, `sign_bracket`, `door_handle`, `oil`, `old_key` |
| Применение предмета в мете | 4 meta action c мгновенными эффектами |
| Один cooldown | `install_sign` — 10 мин (в слайсе перенесён с уровня 12, см. допущение) |
| Локальное сохранение | JSON v1 + миграции + `.bak` |
| Mock hard-currency ускорение | кнопка «−40 гемов» и «посмотреть рекламу» → `MockAdService` мгновенно возвращает success |
| Placeholder art | генерируемые цветные фоны + силуэты предметов, если финального арта нет |

**Допущение (требует подтверждения):** cooldown переносится с изготовления ключа (уровень 12) на установку вывески (уровень 4), потому что иначе первая проверка cooldown-механики окажется за пределами слайса. Параллельная задача во время cooldown — «расчистка витрины снаружи» (уровень 5). Если это ломает нарратив — вернём cooldown на место и расширим слайс до 6 уровней.

### Что намеренно НЕ делать в первой версии

| Не делать | Почему |
|---|---|
| Lives / энергия | гейтит тестирование и не проверяет основную гипотезу |
| Второй puzzle-модуль (screws, bubbles) | контракт есть, реализация не нужна; спека это прямо запрещает |
| Второй магазин | архитектура шаблонная, второй магазин ничего не докажет |
| Реальные ads / IAP / analytics / backend | только mock-интерфейсы |
| Сундуки, ежедневки, ивенты, лидерборды | не проверяют цикл |
| Больше одного бустера | универсальный (авто-часть / подсветка предмета) закрывает обе фазы |
| Полноценный level editor | только маркер целей и валидатор |
| Локализация | тексты в одном `.tres`, вынести позже без переписывания |
| Mid-level resume | контракт в `PuzzleModule` есть, реализация позже |
| Звук и полировка | после подтверждения ощущения цикла |
| Финальный баланс | цифры — заглушки, помечены в одном месте |

---

## 10. Milestone plan

Правило: **никакого «сначала framework, потом первый запуск»**. Игра запускается с M1 и остаётся запускаемой всегда.

### M0 — Скелет проекта (0.5–1 день)

Настройка проекта (portrait, stretch, input map), автолоады-заглушки, `Game` FSM с тремя пустыми экранами, debug-меню.

*Checklist:* приложение запускается на Android; переключение Map → Shop → Level работает; debug-меню открывается.

### M1 — Полный цикл на хардкоде (2–3 дня) ⬅ главный milestone

Один уровень, всё захардкожено: jigsaw 3×4 по одному PNG → reveal → HO с 5 целями → выдача `sign_letter_b` → возврат в пекарню → один `StateSlot` меняет состояние.

*Checklist:* цикл `puzzle → hidden object → quest item → meta change` проходится **целиком** на устройстве; reveal-переход не выглядит как смена сцены; на этом этапе принимается решение «идём дальше / переделываем ощущение».

### M2 — Data-driven core (2 дня)

`LevelDefinition`, `SceneArt`, `JigsawParams`, `HOTargetSet`, `ContentDB` + индекс, `PuzzleRegistry`. Хардкод M1 удаляется. Три уровня из данных.

*Checklist:* новый уровень добавляется без единой строки кода; уровень запускается по id из debug-меню; в `core/` нет упоминаний `PlayerState`/`MetaService`.

### M3 — Save / Load (1–1.5 дня)

`SaveService` (JSON, атомарная запись, `.bak`, версия, миграции), `PlayerState`, точки сохранения.

*Checklist:* прогресс переживает kill процесса; битый JSON не крашит игру и восстанавливается из `.bak`; миграция v1→v2 покрыта тестом.

### M4 — Мета-слой (3 дня)

`MetaService`, `TaskResolver`, `MetaActionDefinition`, эффекты, `StateSlot`, `ShopView` с hotspot'ами, карта района, `MetaFocus` и возврат из уровня в задачу.

*Checklist:* 4 задачи проходятся последовательно; каждая даёт видимое изменение; после уровня камера сама приводит к нужной задаче; в сейве нет `NodePath`.

### M5 — Cooldown и mock-монетизация (1.5 дня)

`CooldownService`, offline-восстановление, сокращение за уровни, `MockAdService` и `MockPurchaseService`, панель cooldown, инвариант параллельной задачи.

*Checklist:* cooldown корректен после часа в закрытом приложении; сокращение за уровень работает; mock-ускорение завершает мгновенно; во время cooldown всегда есть чем заняться.

### M6 — Контент и инструменты (2–3 дня)

`ho_marker_tool`, `validate_content`, наполнение уровней 1–5 финальным или полу-финальным артом, универсальный бустер, экран нарратива.

*Checklist:* валидатор проходит без ошибок; разметка нового уровня занимает < 20 минут; бустер работает в обеих фазах.

### M7 — Mobile polish и сборка (2 дня)

Safe area, aspect-диапазон, импорт-пресеты и сжатие текстур, профилирование, loading-переходы, export-пресет Android, keystore.

*Checklist:* 60 FPS на тестовом устройстве; корректно на 9:16 и 9:21; ничего не под вырезом; размер APK и пиковая память измерены и записаны.

Итого ориентировочно **12–16 рабочих дней** до играбельного слайса. Оценка без финального арта.

---

## 11. Риски и спорные решения

### Не выглядит ли core как две склеенные мини-игры

**Самый серьёзный риск проекта.** Меры:

- одна `SceneView` на обе фазы, ни одной смены сцены, ни одного загрузочного экрана внутри уровня;
- `REVEAL` — отдельное состояние FSM со своим бюджетом на полировку (~0.9 с), а не «хвост» пазла;
- нарративная связка: пазл мотивирован сюжетно («разгляди, что там за досками»), а не как абстрактная задача;
- 1–2 HO-цели **видны на частях пазла** до сборки — игрок замечает их заранее, и фазы связываются в голове игрока, а не только в коде;
- проверка на живых людях уже на M1; если не читается как одно целое — переделывать переход, а не добавлять контент.

### Стоимость производства hidden-object контента

Основная статья расходов проекта. Меры:

- переиспользуемая библиотека предметов (одна иконка `nail` работает на 30 уровнях);
- 2–3 разных `HOTargetSet` на одном фоне для разных уровней/сложностей — фон дорогой, разметка дешёвая;
- разметка через инструмент (минуты вместо часов);
- слоистые сцены: добавление одного слоя меняет сцену без перерисовки фона.

### Стоимость производства jigsaw layouts

**Устранена архитектурно.** Части генерируются кодом (`cols × rows × seed`), UV берётся с общего фона, отдельные PNG не нужны. Стоимость нового пазла = 0.

### Риск чрезмерно сложной архитектуры

Меры:

- правило трёх: абстракция вводится на третьем реальном использовании, не раньше;
- `PuzzleModule` — единственная абстракция, введённая заранее, и только потому, что спека прямо требует сменяемости модулей;
- `MetaEffect` начинается с 4 типов, не с универсального scripting-языка;
- на M1 хардкод разрешён и даже предписан — обобщается только то, что дожило до M2.

### Риск хардкода

Меры:

- запрет per-level скриптов; вся уникальность — в данных;
- валидатор в CI;
- грепом проверяется, что `core/` не ссылается на мету;
- уровень должен запускаться из debug-меню в изоляции — если не запускается, значит появилась скрытая зависимость.

### Масштабирование до тысяч уровней

Узкие места и решения: каталог контента → лёгкий индекс + ленивая загрузка; память → один уровень за раз; UI списка уровней → генерируется из индекса, никогда не хардкодится; сейв → `completed_levels` как массив id (при 1000+ уровней перейдёт в битовую маску по `order` — миграция v→v+1, архитектурно готово); merge-конфликты `.tres` → при росте команды экспорт контента в JSON.

### Удобство работы с PNG-слоями

Риск: расхождение между слоями фона и координатами целей. Меры: единый `reference_size` в `SceneArt`, все координаты нормализованы, слои позиционируются относительно фона, а не экрана; валидатор проверяет размеры слоёв против `reference_size`.

### Необходимость будущего editor tooling

Признаём: при 100+ уровнях внутренний редактор обязателен. Готовимся к нему, не строя его: контракт `setup(ctx)` позволяет запускать уровень из редактора; данные полностью декларативны; валидатор — прообраз редакторского линтера. Решение о постройке редактора принимается после ~20 уровней, когда станет ясна реальная стоимость разметки.

---

## 12. Вопросы перед реализацией

Только то, что действительно меняет архитектуру или границы слайса.

1. **Есть ли провал уровня?** Таймер в HO-фазе и/или лимит ошибок — да или нет? Это определяет состояние `FAILED`, механику «продолжить за валюту», смысл бустеров «доп. время» и «защита от ошибки», и вообще необходимость lives. Если ответа нет — MVP-допущение: **провала нет, таймера нет**, уровень всегда завершается успехом; это самая безопасная база для проверки ощущения цикла.

2. **Lives / энергия на вход в уровень — в слайсе или после?** Влияет на гейтинг прогресса и на то, что игрок делает во время cooldown. Допущение по умолчанию: **не в слайсе**.

3. **Можно ли переигрывать пройденные уровни?** Это единственный источник ресурсов, когда все задачи упёрлись в cooldown. Влияет на структуру сейва и на экономику. Допущение: **да, повтор доступен, награда снижена** (нужно подтвердить).

4. **Согласен ли перенос cooldown с уровня 12 на уровень 4 в слайсе?** Иначе первый cooldown окажется за границей vertical slice, и требование «один cooldown в MVP» не выполнится без расширения до 12 уровней.

5. **Какой арт есть сейчас?** Есть ли готовые PNG для уровней 1–5, или слайс строится на placeholder'ах? Это меняет порядок M6/M7 и то, начинается ли разметка целей параллельно с кодом.

6. **Одна картинка на сцену или фон + отдельные слои?** Если сцены слоистые с самого начала — jigsaw должен собирать композит (нужен `SubViewport` для запекания), и это влияет на память и на M1. Допущение: **в слайсе jigsaw собирает только фон**, слои включаются в момент reveal.

---

## Итог

- **Архитектура:** три слоя (тонкие сервисы-автолоады → доменная логика без нод → сцены с инъекцией зависимостей); core физически не знает про мету; связь между ними — `LevelDefinition` внутрь и `LevelResult` наружу.
- **Данные:** контент — Godot Resources с лёгким JSON-индексом; сейв — версионируемый JSON с миграциями и атомарной записью.
- **Vertical slice:** уровни 1–5 пекарни, 4 визуальных состояния, один cooldown, mock-монетизация, локальный сейв, один бустер.
- **План:** M0…M7, ~12–16 рабочих дней, полный цикл доказывается на M1 (2–3 день), а не в конце.
- **Открытые вопросы:** шесть, из них блокирующих нет — по каждому предложено безопасное MVP-допущение.
