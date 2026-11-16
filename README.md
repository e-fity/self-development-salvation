# 自我开发——拯救（Self-Development: Salvation）

2D 横版动作竖切片，Godot 4.7 / GL Compatibility，灰盒 M1（v0.2）。
可玩流程：标题页 → 关卡（4 只木桩 / 2 个检查点 / Boss「夜巡」）→ 结算页（S/A/B 评价）→ 重开或回标题。

## 目录结构

```
.
├─ game/                    # Godot 工程（用 Godot 打开这个目录）
│  ├─ project.godot
│  ├─ autoload/            # Data / Fx / Save / Settings / Audio 五个全局单例
│  ├─ data/                # player.json / enemies.json / boss.json（全部可调数值）
│  ├─ scenes/
│  │  ├─ player/           # player.tscn + player.gd + camera_shake.gd
│  │  ├─ enemies/          # enemy_dummy.* / boss.*
│  │  ├─ levels/           # level.tscn + level.gd（唯一关卡）
│  │  └─ ui/               # title / hud / pause_menu / settings_panel / tutorial / debug_panel / results
│  ├─ art/player/          # 正式立绘 idle.png（由 tools 生成）与 source 原图
│  ├─ audio/{bgm,sfx}/     # 占位 BGM / 20 个音效
│  └─ tests/               # 无界面冒烟测试 smoke_test.tscn
├─ docs/
│  ├─ prd/                 # 需求文档 v0.2、v0.1 评审建议、v0.2 总结
│  ├─ assets/              # 文档/评审用截图与标注图
│  ├─ 架构与逻辑说明.md
│  ├─ 代码审查报告.md
│  ├─ 工程规范.md
│  └─ 代码规约.md
├─ tools/
│  ├─ check.py             # 门禁：静态检查 + 可选 Godot 冒烟
│  ├─ docs/                # PRD / 评审 DOCX 生成、编辑器截图标注
│  ├─ assets/              # 立绘抠图、占位音效生成
│  └─ archive/             # 已执行的一次性 codemod（仅留档，不再运行）
├─ .githooks/pre-commit    # 提交前静态门禁（需 git config core.hooksPath .githooks）
└─ README.md
```

## 快速开始

环境：Godot **4.7.x**（工程 features 为 `"4.7"`；PRD 写的是 4.4，升级后未回写文档）。
本机可用 `D:\Godot\Godot_v4.7.2-stable_win64_console.exe`。

```powershell
$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"

# 1) 首次导入资源（生成 game/.godot 缓存，可随时删除重建）
& $godot --headless --path game --import

# 2) 启动游戏（从标题页开始）
& $godot --path game

# 或者用编辑器打开 game/project.godot 后按 F5
```

单独跑某个场景：

```powershell
& $godot --path game res://scenes/levels/level.tscn
& $godot --path game res://scenes/ui/title.tscn
```

## 操作

| 动作 | 键鼠 |
| --- | --- |
| 移动 | A / D |
| 跳跃（二段跳） | 空格 / W |
| 普攻（地面三连、空中两段） | 鼠标左键 / J |
| 闪避（前 3 帧无敌） | Shift / U |
| 橙闪突进（K，6 秒 CD） | K |
| 暂停 | Esc |
| 调试面板显隐 | F1 |

> `project.godot` 里还定义了 L（skill2）、I（ultimate）、E（interact）三个动作，但代码尚未实现，见 `docs/代码审查报告.md`。

## 自动化测试

冒烟测试不依赖画面与音频设备，覆盖 Data / Save / Results / Player / Enemy / Boss：

```powershell
$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$save  = "$PWD\_backup\test-save"
$env:SALVATION_SAVE_DIR = $save                                # 隔离存档，避免写真实 user://
& $godot --headless --path game res://tests/smoke_test.tscn
echo $LASTEXITCODE    # 0 = 全过，1 = 有失败项
```

当前基线：**54 项断言全部通过，退出码 0**。测试会先删掉并重建 `SALVATION_SAVE_DIR` 目录，顺带验证「目录不存在时自动创建」；若该路径不可写，Save 组会失败（属环境问题）。

一键门禁（静态检查 + 可选 Godot 冒烟）：

```powershell
python tools/check.py          # Python / JSON / 文本卫生 / GDScript 基础检查
python tools/check.py --godot  # 追加冒烟测试与 level/title 场景
```

仓库自带 `.githooks/pre-commit`，启用后每次提交自动跑 `--fast`：`git config core.hooksPath .githooks`。

## 数值调参

所有战斗数值在 `game/data/*.json`，启动时由 `Data` 加载并与内置默认值深合并：

- `player.json`：移动/跳跃、三段普攻帧数据、跳攻、闪避、橙闪
- `enemies.json`：木桩血量/攻击距离/前摇/击飞阈值
- `boss.json`：Boss 血量、阶段阈值、三连斩/跳劈/召唤参数

改完 JSON 在调试器里执行 `Data.reload()` 即可热重载；M1 未实现「游戏中按 F5 自动重载」，不要在文档里承诺该快捷键。
格式固定为 2 空格缩进（见[代码规约](docs/代码规约.md) DATA-1/DATA-2）。字段缺失回落到 `game/autoload/game_data.gd` 里的 `DEFAULT_*`；类型不对（如把 `move` 写成数字）会告警并保留默认值，不会让角色脚本崩。默认表与 JSON 的重叠字段必须同值，冒烟测试会断言（规约 DATA-6）。

## 存档

- 默认路径：`%APPDATA%\Godot\app_userdata\salvation\save.json`，上一份为 `save.bak`
- 环境变量 `SALVATION_SAVE_DIR` 可把存档重定向到任意目录（自动化测试/沙箱用）；目录不存在时会自动创建
- 写档顺序：`save.tmp` → 旧档改名 `save.bak` → tmp 改名主档；任一步失败保留旧档，主档损坏时读 `save.bak`
- 存档字段：`version / gold / best_grade / best_time / clears / settings{bgm,sfx,shake,numbers,tutorial}`；字段类型异常按默认值丢弃，不会崩

## 工具链

需要 Python 3.10+ 与 `python-docx`、`Pillow`、`numpy`：

```powershell
python tools/docs/build_prd_v02.py         # 生成 docs/prd/游戏需求文档_v0.2.docx（可传输出路径）
python tools/docs/build_review_docx.py     # 生成 docs/prd/游戏需求文档_v0.1_评审与扩展建议.docx
python tools/docs/annotate_editor.py       # docs/assets/editor_source.png → editor_标注.png
python tools/assets/import_player_art.py   # 绿幕立绘 → game/art/player/idle.png
python tools/assets/make_sfx.py            # 重新生成 game/audio 下的占位 wav
```

所有脚本都用「脚本自身位置向上三层」定位仓库根目录，移动脚本目录时不需要改路径常量。

## 文档

- [架构与逻辑说明](docs/架构与逻辑说明.md)：启动链路、状态机、战斗结算、AI、关卡与 UI 数据流
- [代码审查报告](docs/代码审查报告.md)：按 P1/P2/P3 分级的问题清单、PRD 差异矩阵、修复建议
- [工程规范](docs/工程规范.md)：目录职责、文件归位、流程与测试要求
- [代码规约](docs/代码规约.md)：引用 Godot / PEP 8 / Google JSON / Conventional Commits 的代码级规则（MUST/SHOULD）
- [PRD v0.2 总结](docs/prd/游戏需求文档_v0.2_总结.md)：需求基线（Markdown 版）

## 已知限制

- 技能 L / I 只有输入映射与教学文案，没有实现；手柄、`strings.csv`、`export_presets.cfg` 均未落地。
- Boss 的 `combo.height` / `jump.height` 配置未生效（判定盒高度硬编码），见审查报告 P1-4。
- 关卡计时用墙钟，暂停时间会计入成绩，见审查报告 P1-5。
- 存档已实现 `save.bak` 回滚与目录自动创建；`fsync` 未实现（Godot `FileAccess` 不暴露），验收口径为「主档或 bak 至少一份可用」。
- 角色/敌人/UI 均为代码绘制的灰盒，无 AnimatedSprite2D 与动画资源。
