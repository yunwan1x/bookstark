package models

import (
	"errors"
	"strings"
)

// ErrSettingNotResettable 表示尝试重置一个不在 AI 默认值白名单中的 setting key。
var ErrSettingNotResettable = errors.New("该设置不支持重置为默认值")

// AIDefaults 返回所有 AI 提示词类设置项的内置默认值（system prompt / 快捷动作）。
// 这是 source of truth：BackfillAIDefaults 启动时把这些值写入 DB，让 admin 在设置页里
// 看到真实的默认文案；前端 JS 只保留极简 fallback。修改默认行为只需改这一份。
func AIDefaults() map[string]string {
	return map[string]string{
		// ---------------- 系统提示词 ----------------
		"ai_system_prompt_md":      "你是一个 Markdown 文档协作助手。回复使用 Markdown，简洁、信息密度高，不要寒暄。",
		"ai_system_prompt_html":    "你是一个 HTML 文档协作助手。回复直接给出可粘贴的 HTML 片段，不要包含解释。",
		"ai_system_prompt_drawing": "你是一个画板/白板协作助手。围绕当前画板内容提供结构、布局、流程图、草图和视觉表达建议。回复简洁、可直接执行；如果需要生成图形内容，优先给出可在画板中逐步绘制的元素、位置关系和标注说明。",

		// ---------------- 快捷动作 ----------------
		"ai_actions_selection": strings.Join([]string{
			"# 选中文本时编辑器 ✨ / bubble 菜单的快捷动作",
			"# 每行格式：标签 | 提示词；# 开头为注释，空行忽略",
			"改写 | 请改写以下选中的文本，保持原意但更通顺、更专业。直接给改写后的版本。",
			"扩写 | 请把选中文本扩写得更详细、更有信息量，保留原结构。直接给扩写后的版本。",
			"缩写 | 请把选中文本压缩到原长度的 1/3 左右，保留核心信息。",
			"翻译为英文 | 请把选中文本翻译为流畅自然的英文。",
			"续写 | 请基于选中文本的语气和上下文，续写一段（约 2-3 句话）。",
		}, "\n"),

		"ai_actions_html": strings.Join([]string{
			"# HTML 文档场景（无选区）。{subject} 占位符运行时替换为「当前章节」/「当前文章」/「主题」",
			"写整页 HTML | 请基于{subject}主题，输出一段可直接粘贴的完整 HTML 片段（含 <h1>/<p>/<ul> 等结构，不要 <html>/<body>/<head>），不要包含解释。",
			"写一段 HTML | 请输出一段 HTML 片段，主题：",
			"插入示例表格 | 请输出一个 <table> HTML 片段（含 thead/tbody，3 列 4 行示例数据），不要解释。",
			"插入卡片块 | 请输出一个语义化的 <section class=\"card\"> HTML 片段，包含标题、描述和操作按钮，主题：",
			"插入表单 | 请输出一个简单的 HTML <form> 片段，含 label/input/button，不要 <script>。",
		}, "\n"),

		"ai_actions_book": strings.Join([]string{
			"# 书籍章节场景（无选区）",
			"写本章初稿 | 请基于当前章节标题与所在书籍的上下文，写一篇约 800 字的章节初稿，使用 markdown，有合理的二级/三级小标题，不要重复章节标题。",
			"写本章引言 | 请为当前章节写一段 150-200 字的引言段落，引出本章核心问题，语气与同级章节保持一致。",
			"写本章小结 | 请为当前章节写一段 150 字左右的小结段落，提炼 3-5 个要点，使用列表形式。",
			"生成大纲 | 为当前章节生成一个 markdown 标题大纲，3-5 个二级标题，每个二级下再带 1-2 个三级，不要正文。",
			"写一段 | 基于当前章节主题，写一段 markdown 段落：",
		}, "\n"),

		"ai_actions_article": strings.Join([]string{
			"# 博客文章场景（无选区）",
			"写整篇文章 | 请基于文章标题与标签，写一篇约 1000 字的完整文章，使用 markdown，有合理的二级/三级小标题，不要重复文章标题。",
			"写引言 | 请为这篇文章写一段 150-200 字的开篇引言，吸引读者并引出主题。",
			"写结论 | 请为这篇文章写一段 150 字左右的结论段落，总结要点并给出行动建议。",
			"生成大纲 | 为这篇文章生成一个 markdown 标题大纲，3-5 个二级标题，每个二级下再带 1-2 个三级，不要正文。",
			"提炼要点 | 请基于标题与标签，列出本主题最值得讨论的 5-8 个核心要点，使用 markdown 列表。",
		}, "\n"),

		"ai_actions_note": strings.Join([]string{
			"# 笔记场景（笔记页 AI 快捷按钮）",
			"美化格式 | 美化这段笔记的 Markdown 格式：保留原意，整理标题、列表、引用、代码块和段落层级，让结构更清晰。只返回处理后的 Markdown。",
			"润色 | 润色这段笔记：保留事实和语气，改得更通顺、更简洁、更适合长期保存。只返回处理后的 Markdown。",
			"清单 | 把这段笔记整理成清晰的 checklist，保留必要背景和行动项。只返回 Markdown。",
			"摘要 | 提炼这段笔记的核心要点，按层级输出摘要和重点。只返回 Markdown。",
			"续写 | 基于这段笔记继续补写一小段，延续原来的语气和上下文。只返回要写入的 Markdown。",
			"翻译英文 | 把这段笔记翻译成自然流畅的英文，保留 Markdown 结构。只返回翻译后的 Markdown。",
		}, "\n"),

		"ai_actions_task": strings.Join([]string{
			"# 待办场景（待办页 AI 快捷按钮）",
			"整理待办 | 把这段内容整理成一个清晰、可执行的待办。要求：动词开头，保留关键约束，去掉废话，只返回待办内容。",
			"拆成子待办 | 把这件事拆成 3-7 个可执行子待办。每个子待办要具体、可完成、不要太宽泛。只返回 Markdown checklist。",
			"改成今日可做 | 把这件事压缩成今天可以完成的一小步。如果原任务太大，只保留最小可推进动作。只返回一个待办。",
			"生成验收标准 | 为当前待办生成 2-5 条完成验收标准。要求可判断、可检查。只返回 Markdown checklist。",
			"提取下一步 | 从当前内容里提炼出最应该马上做的下一步。只返回一个具体行动，不要解释。",
			"补全执行信息 | 根据当前待办补全执行要素：目标、下一步、可能阻塞、验收标准。用简洁 Markdown 输出。",
		}, "\n"),

		"ai_actions_empty": strings.Join([]string{
			"# 空场景（新建文档、未选中文本、无章节/文章上下文）",
			"生成大纲 | 为我即将写的内容生成一个 markdown 标题大纲，3-5 级，覆盖以下主题：",
			"写一段 | 写一段 markdown 段落，主题：",
		}, "\n"),
	}
}

// BackfillAIDefaults 把 AIDefaults() 里的默认 prompt 写入 DB 中"当前为空"的 AI 设置项。
// 启动时调用一次。
//
// 策略：逐 key 检查 DB 当前值，为空时才写入默认；不再依赖单一的 backfilled 标记。
// 这样未来给 AIDefaults 加新 key 时，老用户重启后也能自动 backfill 新 key（admin 仍能
// 看到默认文案），而 admin 已主动改过的 key 不会被覆盖。
func BackfillAIDefaults() error {
	defaults := AIDefaults()
	updates := map[string]string{}
	for k, v := range defaults {
		if v == "" {
			continue
		}
		if GetSetting(k) == "" {
			updates[k] = v
		}
	}
	if len(updates) == 0 {
		return nil
	}
	return BatchUpdateSettings(updates)
}

// ResetAISettingToDefault 把指定 key 重置为内置默认值。admin 在配置页点「重置默认」时调用。
// 仅允许 AIDefaults() 中列出的 key（白名单），防止越权重置其他设置。
func ResetAISettingToDefault(key string) error {
	defaults := AIDefaults()
	def, ok := defaults[key]
	if !ok {
		return ErrSettingNotResettable
	}
	return BatchUpdateSettings(map[string]string{key: def})
}
