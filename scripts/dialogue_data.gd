extends RefCounted
class_name DialogueData
## ============================================================================
##  剧情对话数据 —— 想改台词 / 加剧情，只动这一个文件里的变量即可，
##  不用碰引擎代码（对话框逻辑在 scripts/dialogue_box.gd）。
## ============================================================================
##
##  一段剧情 = 一串按顺序播放的台词；每条台词是一个字典：
##    who   : 说话人。留空 "" = 不显示名字（纯旁白 / 场景描述）。
##    text  : 台词正文。可写 {变量名} 占位符，播放时用 VARS 里的值替换。
##    speed : 可选，这一行的打字速度（字/秒），不写则用 DEFAULT_SPEED。
##
##  播放方式（在任意脚本里）：
##    Dialogue.play("示例·开场")                       # 用下面 SCRIPTS 里的名字
##    Dialogue.play("示例·开场", {"vars": {"player_name":"张三"}})   # 临时覆盖变量
##    Dialogue.play([{"who":"甲","text":"你好"}])       # 直接传一串台词
##    Dialogue.play("示例·开场", {"on_done": func(): print("放完了")})
##
##  打字速度、是否暂停游戏等也可在 opts 里传：pause / speed。

## 默认打字速度（字/秒）。
const DEFAULT_SPEED := 34.0

## 可被台词引用的变量：正文里写 {键名} 就会替换成这里的值。
## 改这里，或播放时用 opts.vars 临时覆盖，就能让同一套台词显示不同内容。
static var VARS := {
	"game_title": "全是神人",
	"mode": "正经模式",
	"player_name": "旅人",
	"place": "国道边",
}

## 剧情台词表。新增剧情 = 在 SCRIPTS 里加一个「名字」: [ {who,text}, ... ]。
const SCRIPTS := {
	"示例·开场": [
		{"who": "", "text": "—— {game_title} · {mode} ——"
		},
		{"who": "旁白", "text": "风从国道那头吹过来，卷着柴油和青草的味道。你在{place}停了脚。"},
		{"who": "???", "text": "你就是 {player_name}？听说你一路砍到了这里。"},
		{"who": "{player_name}", "text": "我只是想过点正经日子。"},
		{"who": "旁白", "text": "（这是占位台词。把 SCRIPTS 里的内容换成你自己的，就是正经模式的剧情了。）"},
	],
	"正经·开场": [
		{"who": "", "text": "欢迎来到我做的游戏"},
		{"who": "", "text": "这是正经模式，打雷霆boss请到雷霆模式"},
	],
}

## 按名字取一段剧情（不存在则返回空数组）。
static func get_lines(id: String) -> Array:
	return SCRIPTS.get(id, [])
