class_name LevelContext
extends RefCounted
## Всё, что уровню нужно снаружи. Инъекция вместо глобального доступа —
## поэтому уровень запускается из debug-меню, из headless-теста и позже
## из level editor без изменений.

var definition: LevelDefinition
var items: Dictionary = {}      ## item_id -> ItemDefinition (для панели поиска)
var replay: bool = false
var boosters_available: int = 0
var booster_id: String = "booster_hint"
## Показать обучающий ход рукой. Решает мета («игрок ещё не прошёл ни одного
## уровня»), а не сам уровень: core про прогресс игрока не знает.
var show_drag_hint: bool = false
## Показать обучающий тап по искомому предмету в фазе поиска. Отдельно от
## show_drag_hint: тащить и искать — разные жесты, и учить им надо в разные
## моменты. Иначе единственное, что игроку показали, — это перетаскивание,
## а находить предметы он должен нажатием.
var show_tap_hint: bool = false
