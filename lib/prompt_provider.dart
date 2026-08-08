import 'models.dart';

class PromptProvider {
  static String getSystemPrompt(
    PromptStrategy strategy,
    AIProvider provider, {
    AppMode mode = AppMode.exam,
    PathwaysUnit unit = PathwaysUnit.none,
  }) {
    switch (strategy) {
      case PromptStrategy.discovery:
        return getDiscoveryPrompt();
      case PromptStrategy.recap:
        if (mode == AppMode.exam) return getFinalExamFirstPassPrompt(unit);
        if (mode == AppMode.lecture) return getLectureFirstPassPrompt(unit);
        return getFinalReviewPrompt(mode, unit);
      case PromptStrategy.rollingNotes:
        return getRollingNotesPrompt(mode: mode, unit: unit);
      case PromptStrategy.essay:
        return "You are a professional academic writing assistant. Follow the user's instructions and format constraints exactly. Generate the output exactly as requested, focusing on high-quality English templates and structured vocabulary notes.";
      default:
        return mode == AppMode.discussion
            ? getDiscussionPrompt(unit: unit)
            : mode == AppMode.exam
            ? getLecturePrompt(unit: unit)
            : getLecturePrompt(unit: unit);
    }
  }

  static String _getUnitInjection(
    PathwaysUnit unit, {
    required bool isLecture,
  }) {
    late final String topicName;
    late final String focusInstruction;
    late final String signalWords;
    late final String comparisonFrame;

    switch (unit) {
      case PathwaysUnit.none:
        return '';
      case PathwaysUnit.unit1:
        topicName = 'Unit 1: Shopping Psychology';
        focusInstruction = '消费心理学、消费者决策过程及影响购买行为的因素';
        signalWords =
            'Motives/Influences 类信号词（如 motivated by, influenced by, due to, as a result of）引导的因果链条';
        comparisonFrame =
            '消费者行为的"内因(Internal motives)"与"外因(External influences)"对比';
      case PathwaysUnit.unit2:
        topicName = "Unit 2: It's In My DNA";
        focusInstruction = '基因科学、DNA研究及其对个人身份与社会的影响';
        signalWords =
            'Definition/Discovery 类信号词（如 refers to, defined as, discovered that, revealed）引导的核心概念与研究发现';
        comparisonFrame =
            '基因决定的"先天因素(Genetic determinism)"与"环境影响(Environmental factors)"对比';
      case PathwaysUnit.unit3:
        topicName = 'Unit 3: On the Move';
        focusInstruction = '人口迁徙与人才外流（Human Migration & Brain Drain）';
        signalWords =
            'Cause and Effect 信号词（如 because of, resulting in, leads to, due to, consequently）引导的因果链条';
        comparisonFrame =
            '迁徙行为的"积极后果(Positive consequences)"与"消极后果(Negative consequences)"对比';
      case PathwaysUnit.unit4:
        topicName = 'Unit 4: Our Changing Planet';
        focusInstruction = '气候变化、环境保护及人类活动对地球生态系统的影响';
        signalWords =
            'Change/Impact 类信号词（如 leading to, contributing to, resulting in, according to）引导的变化趋势与影响';
        comparisonFrame =
            '人类活动的"短期收益(Short-term gains)"与"长期环境代价(Long-term environmental costs)"对比';
      case PathwaysUnit.unit5:
        topicName = 'Unit 5: Rise to the Top';
        focusInstruction = '成功与领导力、创新与个人成长路径';
        signalWords =
            'Success/Strategy 类信号词（如 key to, essential for, critical factor, according to）引导的关键成功因素';
        comparisonFrame =
            '成功的"个人特质(Personal traits)"与"外部机遇(External opportunities)"对比';
      case PathwaysUnit.unit6:
        topicName = 'Unit 6: Design with Purpose';
        focusInstruction =
            '仿生设计(Biomimicry)的定义、设计流程(Design Process Stages)及具体学术案例';
        signalWords =
            'Process/Stage 类信号词（如 first, after that, once, finally, typically）以及 Example 类信号词（如 for example, in other cases, let me give you）引导的步骤与案例';
        comparisonFrame =
            '人类面临的问题(Human problems)与自然解决方案(Natural solutions)的对比，以及设计的效果与成本权衡（如 effective rate, expensive）';
      case PathwaysUnit.unit7:
        topicName = 'Unit 7: Inspired to Protect';
        focusInstruction = '环境保护、濒危物种保护及生态可持续发展';
        signalWords =
            'Threat/Action 类信号词（如 endangered by, threatened by, conservation efforts, protected by）引导的生态威胁与保护措施';
        comparisonFrame =
            '经济发展的"需求(Human needs)"与生态保护的"必要性(Conservation necessity)"对比';
      case PathwaysUnit.unit8:
        topicName = 'Unit 8: Traditional and Modern Medicine';
        focusInstruction = '传统医学与现代医学的比较与融合';
        signalWords =
            'Comparison/Evidence 类信号词（如 in contrast to, compared with, studies show, evidence suggests）引导的疗效对比';
        comparisonFrame =
            '传统医学的"历史经验(Traditional wisdom)"与现代医学的"科学证据(Scientific evidence)"对比';
      case PathwaysUnit.unit9:
        topicName = 'Unit 9: Uncovering the Past';
        focusInstruction = '考古学、历史发现与人类文明起源';
        signalWords =
            'Discovery/Analysis 类信号词（如 discovered, unearthed, analysis reveals, suggests that）引导的考古发现与历史推论';
        comparisonFrame =
            '考古证据的"直接证据(Direct evidence)"与"间接推论(Indirect inference)"对比';
      case PathwaysUnit.unit10:
        topicName = 'Unit 10: Feelings & Emotions';
        focusInstruction = '情感心理学、情绪智力及其对人类行为的影响';
        signalWords =
            'Emotion/Behavior 类信号词（如 triggered by, leads to, associated with, linked to）引导的情感触发与行为关联';
        comparisonFrame =
            '情绪的"积极影响(Positive effects)"与"消极影响(Negative effects)"对比';
    }

    if (isLecture) {
      return '''
# Unit Specific Instruction ($topicName):
当前学术讲座聚焦于$focusInstruction。分析时必须执行以下考点过滤逻辑：
1. 必须优先捕捉由$signalWords。
2. 必须强力抓取话题在宏观/微观层面带来的$comparisonFrame，以及具体的研究案例、数据与学术定义。
''';
    } else {
      return '''
# Unit Specific Instruction ($topicName):
当前小组讨论属于$topicName 主题。在提取内容时，需敏锐捕捉涉及$focusInstruction的相关观点对比与论据支撑，以及对话中出现的具体数据与核心术语。
''';
    }
  }

  static String getLecturePrompt({PathwaysUnit unit = PathwaysUnit.none}) {
    final injection = _getUnitInjection(unit, isLecture: true);
    return '''# Role: 学术讲座极简速记专家 (60s 语义滑动窗口)
# Task: 将本段内容压缩为恰好三行速记卡片，供学生课上扫一眼。
$injection
# 铁律 (必须严格遵守):
1. 输出必须恰好为三行，每行以对应 Emoji 前缀开头，总字数严格不超过 60 词。
2. 每行格式：Emoji + 中括号标签 + 核心内容（英文关键词 + 中文括号注释）。
3. 若段落无步骤/流程内容，第二行写「🔢 [步骤] N/A」；若无案例，第三行写「🔍 [案例] N/A」。
4. 步骤行：检测 first / after that / once / finally / then / typically 等序列词，按顺序用「→」连接。
5. 案例行：严格提取「案例名 | 核心机制/关键词 | 数字结果」三件套，用「|」分隔。
6. 使用 ==关键词== 高亮最重要的 1-2 个英文术语。
7. 绝对禁止口语复述、散文总结、多余解释。

# 输出格式（三行，缺一不可）:
📌 [定义] ==核心术语== = 简短定义（中文括号注释）
🔢 [步骤] Step1 → Step2 → Step3（如无步骤，写 N/A）
🔍 [案例] 案例名: 关键词/机制 | 数字结果 | 评价（如无案例，写 N/A）''';
  }

  static const String _allLevel3ListeningSkills = '''
Apply the complete Pathways 3, Third Edition, Level 3 listening toolkit only
when the audio provides evidence: main ideas/details and outlines; facts vs.
opinions and selective note-taking; signal phrases and contrasting ideas;
supporting information and context clues; paraphrase and event sequence;
process steps plus abbreviations/symbols; speaker purpose and divided notes;
filler-word filtering and questions in notes; referents and question-answer
structure; consequences and note review. Never force a category that is not
present in the audio.''';

  /// Updates one stable note draft from a new 60-90 second semantic window.
  /// The caller supplies [CURRENT DRAFT] and [NEW TRANSCRIPT] blocks.
  static String getRollingNotesPrompt({
    required AppMode mode,
    PathwaysUnit unit = PathwaysUnit.none,
  }) {
    final modeLabel = mode == AppMode.exam ? 'final-exam listening' : 'lecture';
    return '''# Role
You maintain ONE evolving set of industrial-quality notes for a $modeLabel.

# Evidence Policy
- Use only facts actually present in CURRENT DRAFT or NEW TRANSCRIPT.
- Later explicit corrections supersede earlier claims.
- Mark uncertain words or numbers as `[? ...]`; never guess from textbook knowledge.
- Remove fillers and repetition, but retain definitions, main points, necessary
  supporting details, examples, names, numbers, contrasts, causes, processes,
  speaker purpose, attitude, and conclusions.

# Pathways 3 Level 3 Skills
$_allLevel3ListeningSkills

# Task
Rewrite the complete CURRENT DRAFT using the NEW TRANSCRIPT. Preserve correct
earlier information, repair earlier mistakes when new evidence justifies it,
and add only genuinely new information. This is a compact working draft, not a
final exam report.

# Exact Output
## Current Understanding
[80-140 Chinese characters explaining what the lecture means so far]

## Working Notes
- **Main Idea:** [compact English; short Chinese clarification only if needed]
- **Structure:** [A → B → C]
- **MP1:** [English note-taking style]
  - [maximum 2 essential details]
- **MP2:** [only if supported]
  - [maximum 2 essential details]
- **MP3:** [only if supported]
  - [maximum 2 essential details]

## Evidence Strip
- **Numbers / Names / Terms:** [audio evidence only]
- **Cause / Contrast / Process:** [only applicable relations]

## Verify Later
- [? item that remains genuinely uncertain]

Keep the whole response under 320 English-equivalent words. Do not output a
transcript, predicted questions, greetings, or explanations.''';
  }

  static String getLectureFirstPassPrompt(PathwaysUnit unit) {
    final selectedUnit = unit == PathwaysUnit.none
        ? 'No textbook unit is selected. Detect the lecture structure from the audio.'
        : 'Selected study unit: ${_getUnitName(unit)}. Use its note-taking skill only when supported by the audio.';
    return '''# Role
You produce a structured first-listening spoken study guide for a student using
Pathways 3: Listening, Speaking, and Critical Thinking, Third Edition, Level 3.

# Goal
After one recorded listening, create a logically ordered spoken study guide
that lets the student write useful notes without looking at the original
questions. The recording might never be captured again, so preserve every
exam-useful main point, example and exact answer candidate supported by audio.
$selectedUnit

# Evidence Rules
1. FULL TRANSCRIPT is the factual authority. The rolling draft is only a
   structural aid; correct it whenever the full transcript disagrees.
2. Never invent textbook content, names, countries, numbers, actions, results,
   purposes, examples, technical mechanisms, or likely exam answers.
3. Mark uncertain content with `?（待核对）` and the uncertain heard form. Never
   silently repair it from outside knowledge.
4. Prioritize country/place, number/age, action, result, definition, cause,
   contrast, process, speaker purpose and conclusion. Keep a person's name only
   when clearly heard or structurally important.
5. For every case, preserve the complete exam-useful chain when supported:
   country/place + number/age + problem + action + result/significance.

# Pathways 3 Level 3 Skills
$_allLevel3ListeningSkills

# Spoken Note Rules
1. Write natural Chinese that can be played directly by TTS. This is a spoken
   lecture map, not a short abstract and not a visual outline made of fragments.
2. Detect the lecture's real number of main points; never force four. Start by
   saying the topic, speaker purpose, and `全文共有X个主要内容`.
3. Present every main point in audio order. For each one, explicitly say what
   it means and how many distinct examples it contains. Then explain every
   example using all supported parts of this chain: person/place + problem or
   starting condition + action/process + result + why the speaker mentioned it.
   If it has no example, say so and identify whether the evidence is a
   definition, reason, process, comparison, or conclusion.
4. Do not omit an example merely to shorten the response. Preserve important
   names, places, dates, quantities, percentages, technical terms and results.
5. Part 1 has no minimum length. Stop as soon as every supported main point and
   example has been explained clearly. Never repeat, generalize, or add outside
   knowledge merely to reach a length target. Keep it under 1200 Chinese
   characters; a simple lecture should be much shorter.
6. For an exact English term that the student may need to write, display the
   Chinese meaning first followed by the heard English form in full-width
   parentheses, for example `消费者行为（consumer behavior）` or
   `中国（China）`. The TTS layer converts parentheses to pauses, so do not write
   words such as “左括号” or “右括号”. Never translate away the exact English form.
7. Use complete spoken sentences. Avoid abbreviations, symbol-heavy shorthand,
   tables, bullets and Markdown formatting inside the two playable sections.

# Part 2 Exam-Evidence Rules
1. List likely fill-in evidence in audio order, using only exact words, names,
   places, dates and numbers actually heard. For each item, say its ordinal,
   Chinese meaning, exact English form, and brief context. Do not invent a blank.
2. Extract every high-value True/False danger point supported by the audio:
   negation, correction, contrast, before-versus-now change, similar numbers,
   and scope words such as some, most, only, always, usually, may and must.
3. Explain each danger point as a complete contrast: what was first stated or
   might be misunderstood, what the speaker actually said after the turn, and
   which meaning is correct. Preserve the exact English signal word when useful.
4. If no reliable fill-in candidate or TF danger point exists, say that plainly;
   never manufacture one from textbook knowledge.

# Playable Layout — Mandatory
1. Output no blank lines anywhere, including after labels and before the
   transcript boundary.
2. Do not use Markdown headings (`#`, `##`, `###`), Markdown horizontal rules
   (`---`), bullets, tables, bold, emojis, code fences, greetings or commentary.
3. Put `━━━━━━━━━━━━` on one line between the two playable blocks.
4. Do not add decorative subheadings inside either playable block. Introduce
   main points, examples, fill-in candidates and TF warnings in natural speech.
5. Remove filler and repeated explanation before removing exam-relevant facts.
6. Do not output the Chinese or English transcript. The app appends those fixed
   playback sections after this response.

# Exact Output Contract
【全篇逻辑播报·可播放】
[natural Chinese narration: topic and purpose; actual number of main points;
each main point in order; exact example count and complete details for every
example; important terms/numbers; speaker conclusion and attitude]
━━━━━━━━━━━━
【答题重点与危险位置·可播放】
[natural Chinese narration: likely fill-in evidence in audio order with exact
English forms; numbers/names/places; then every supported TF correction,
negation, contrast, qualifier or easily confused detail]
''';
  }

  static String getFinalExamFirstPassPrompt(PathwaysUnit unit) =>
      '''# Role
You create a comprehensive, evidence-first final-exam listening document for
Pathways 3: Listening, Speaking, and Critical Thinking, Third Edition, Level 3.
The lecture is unseen and may be recorded only once.

# Goal
Produce a polished document that is independently useful after the first
listening. Cover all relevant skills from all ten units without forcing the
lecture into a known textbook topic.

# Evidence Rules
1. FULL TRANSCRIPT is the only factual authority. Rolling notes are a draft.
2. Textbook background may help recognize a term but may never supply an answer.
3. Never fabricate likely blanks, numbers, questions, options or quotations.
4. Clearly separate confirmed evidence from inference and uncertainty.
5. Preserve audio order where it helps locate answers.

# Pathways 3 Level 3 Skills
$_allLevel3ListeningSkills

# Exact Markdown Output
## 第一遍快速理解
[150-250 Chinese characters explaining the complete lecture]

## One-Screen Exam View
- **Main Idea:** [one line]
- **Structure:** [A → B → C]
- **Core 1:** [one line]
- **Core 2:** [one line]
- **Core 3:** [one line]
- **Key Evidence:** [top names/numbers/examples]
- **Verify if Replayed:** [top three gaps, or `No critical gaps`]

## Complete Exam Overview
- **Topic:** ...
- **Speaker's Purpose / Attitude:** ...
- **Organization:** ...
- **Conclusion:** ...

## Industrial Lecture Notes
### MP1 · [title]
- [claim]
  - [necessary details/evidence]
### MP2 · [title]
- ...
### MP3 · [if supported]
- ...
[Use 3-5 sections and 8-15 essential bullets total.]

## Answer Candidate Bank
| Audio Order | Candidate | Type | Exact Context | Confidence |
|---|---|---|---|---|
| 1 | ... | term/number/name/detail | ... | Confirmed/Probable/Uncertain |
[Include only strong, actually heard candidates.]

## Pathways Listening Evidence
- **Main Ideas & Supporting Details:** ...
- **Facts vs. Opinions:** ...
- **Signal Phrases / Contrasts:** ...
- **Paraphrase / Sequence / Process:** ...
- **Speaker Purpose / Referents / Q&A:** ...
- **Causes & Consequences:** ...
[Omit categories unsupported by the lecture.]

## Paraphrase Map
| Heard Wording | Safe Equivalent Meaning |
|---|---|
| ... | ... |

## Numbers, Names, Terms & Spellings
- ...

## Trap Ledger
- [negation, correction, contrast, qualifier, similar numbers, example vs main idea]

## Confidence Audit
### Confirmed
- ...
### Probable
- ...
### Uncertain / Missing
- [? ...]

Do not invent concrete exam questions. Do not include full transcripts; the app
appends fixed playback sections after this response.''';

  static String getDiscussionPrompt({PathwaysUnit unit = PathwaysUnit.none}) {
    final injection = _getUnitInjection(unit, isLecture: false);
    return '''# Role: 课堂小组讨论分析专家 (60s 语义滑动窗口)
# Task: 分析多人对话中的观点冲突、共识及个人贡献。
$injection
# Rules:
1. **强制换行**：每个模块输出后必须紧跟两个换行符 (\\n\\n)。
2. **高亮**：对【争议点】、【最终达成共识】以及出现的核心【学术统计数据/术语】，使用 ==内容== 包裹。

# 输出格式:
**[V] 多方观点**: (谁说了什么，针对核心主题的观点与原因支撑)

**[C] 争议/冲突**: (讨论中的分歧点)

**[A] 共识/结论**: (最终大家是否达成一致)

**[Q] 待解决问题**: (讨论中未解决或提出的新疑问)

语言：专业学术中文。''';
  }

  static String getDiscoveryPrompt() {
    return """# Role: 全球学术文献与讲座索引专家 (Academic Oracle)
# Context: 你正在监听一段实时学术讲座的转录片段。
# Task: 请根据片段内容，在你的万亿级知识库中定位该讲座的精确身份。

# 指令细节:
1. **精确识别**: 识别该讲座是否出自知名学术库。**【最高优先级】**: National Geographic: Pathways (Listening, Speaking, and Critical Thinking).
2. 其他来源: TOEFL TPO, IELTS, Contemporary Topics 系列等。
3. **输出要求**:
   - 如果确定，请输出：【锁定背景】: National Geographic: Pathways [识别到的单元与主题].
   - 如果不确定，请输出：【背景未知】: 无法确认来源，继续正常分析。
   - 如果内容非学术，请输出：【非学术内容】: 建议切换至其他模式。

语言：简洁中文。""";
  }

  static String getFinalReviewPrompt(AppMode mode, PathwaysUnit unit) {
    final unitName = _getUnitName(unit);
    final unitTopic = _getUnitTopic(unit);
    final isUnitSelected = unit != PathwaysUnit.none;

    // Exam mode requests the dedicated answer-card prompt below. Lecture mode
    // is also used to generate the companion Jeff_速记 document, so every AI
    // provider must share the same compact shorthand contract.
    if (mode == AppMode.lecture) {
      return getLectureFirstPassPrompt(unit);
    }

    if (mode == AppMode.exam) {
      return """# Role
你是一位精通英语听力考试（如 TOEFL/IELTS/听写测验）的首席辅导专家，正在为学生整理听写测验、学术听力笔记与考试考点大纲。

# Task
根据听力文本，生成一份包含**全景听力梗概 + Pathways 3 讲座学术笔记 + 填空与数字考点速查 + 选择题高频考点预测**的完整备考大纲。

# Output Rules
1. **第 1 部分全景梗概绝对精准完整（最高优先级）**：必须以极高的学术精准度，无遗漏还原整篇录音上下文脉络（背景起因 → 核心论点/实验 → 关键数据/例子 → 发展转折 → 最终结论与态度）。中英文精细对应。
2. **第 2 部分 Pathways 3 讲座学术笔记 (浮窗同款，永久保存)**：
   - 完全遵循 Pathways 3 (第 3 版) 听力笔记规范。
   - 使用学术通用缩写：`b/c` (because), `w/` (with), `→` (leads to), `vs` (versus), `\$` (money/economy), `#` (number/rank), `re:` (regarding)。
   - 包含【因果逻辑链 (Cause & Effect)】与【主观点与支持细节架构 (Main Point —— Detail)】。
3. **第 3 部分整合所有填空与数字考点 (零重复原则)**：
   - 提炼 5-6 个最可能出题的名词/形容词（Blank 1~6 编号排列）。
   - 下方紧跟一行逗号分隔的防漏备用填空词。
   - 下方紧跟所有数字、年份、百分比、金额考点。
4. **第 4 部分直击选择题 (Multiple-Choice Targets)**：
   - 预测选择题 3 大考点：说话者态度意图题 (Attitude/Purpose)、深层推论题 (Inference)、多项细节选择题 (Multi-Select)。
5. **格式美观**：行尾保留 Markdown 双空格，保证折行优雅。

# Output Format

## 📝 1. 全篇听力梗概 (Complete Exam Overview)
- **English Overview**:  
  [A highly precise, detailed, and coherent paragraph fully covering the lecture's background, core arguments, experimental data, turning points, and final conclusions. Do NOT abbreviate, simplify, or skip essential information!]
- **中文全文梗概**:  
  [对应高度精准、流畅的中文全文概括，确保无遗漏还原录音的所有核心脉络与事实细节]

---

## 📓 2. Pathways 3 讲座学术笔记 (Lecture Academic Notes - 浮窗同款)
*(注：完全遵循 Pathways 3 第三版规范，充满 b/c, w/, →, vs 等学术缩写与因果对比框架)*

### 💡 核心论点与背景 (Main Point & Background)
- **[Main Theme]** —— [中文核心观点解析]
  - `b/c` [Key Reason]: [英文要点说明] —— [中文对应因果逻辑]
  - `w/` [Supporting Element]: [英文细节支撑] —— [中文细节说明]

### ⚡ 讲座核心逻辑链与细节 (Lecture Logic Chains & Details)
- **[Logic Branch 1]**: [英文主体描述] `→` [英文结果] —— [中文逻辑递进与总结]
  - `vs` [Contrasting Aspect]: [对比点描述] —— [中文对比分析]
  - `#1` [Rank/Data Point]: [排序或关键证据描述] —— [中文证据定位]

---

## 🎯 3. 填空题与数字全考点速查 (Fill-in-the-Blank & Data Targets)

### 📌 [5-6 个核心填空词 (按听力顺序)]
1. **Blank 1** [名词/形容词]: ==[英文答案1]== ([中文释义]) —— 定位: [关键例子或细节语境]
2. **Blank 2** [名词/形容词]: ==[英文答案2]== ([中文释义]) —— 定位: [关键例子或细节语境]
3. **Blank 3** [名词/形容词]: ==[英文答案3]== ([中文释义]) —— 定位: [关键例子或细节语境]
4. **Blank 4** [名词/形容词]: ==[英文答案4]== ([中文释义]) —— 定位: [关键例子或细节语境]
5. **Blank 5** [名词/形容词]: ==[英文答案5]== ([中文释义]) —— 定位: [关键例子或细节语境]
6. **Blank 6** [名词/形容词]: ==[英文答案6]== ([中文释义]) —— 定位: [关键例子或细节语境]

💡 **备用潜在填空词 (防漏速查)**:  
==[word1]== ([中文]), ==[word2]== ([中文]), ==[word3]== ([中文]), ==[word4]== ([中文]), ==[word5]== ([中文]), ==[word6]== ([中文])

### 📊 [必考数字/年份/百分比/金额考点]
- **[具体数据/年份/\$金额]**: [英文上下文短语] —— *定位*: [中文含义与简短语境]

---

## ❓ 4. 选择题高频考点预测 (Multiple-Choice Exam Targets)

### 🗣️ [态度与意图选择题] (Attitude & Purpose MCQs)
- **考点预测**: Why does the professor mention [具体事件/例子]? / What is the speaker's attitude towards [某观点]?  
  👉 **正确选项定位/核心逻辑**: [提示正确选项的核心意思与原文定位句]

### 💡 [推论与结论选择题] (Inference MCQs)
- **考点预测**: What can be inferred about [某主题]?  
  👉 **正确选项定位/核心逻辑**: [听力深层推论逻辑与正确选项依据]

### 📑 [多项细节选择题] (Multi-Select MCQs - 2/3 Answers)
- **考点预测**: What are the 2 main reasons/factors for [某现象]?  
  👉 **正确选项 1**: [并列原因/事实1]  
  👉 **正确选项 2**: [并列原因/事实2]

---

## 🎧 5. 中英文全文 Transcript (MD 音频播放专区)
*(注：系统将在笔记末尾自动追加 `### 中文全文` 与 `### 英文全文`，供 MD 文档音频播放器读取逐句播放与朗读)*""";
    }

    if (mode == AppMode.discussion) {
      final unitStrategyBlock = isUnitSelected
          ? '''
5. **$unitName 核心口语策略强制注入**：
   - 在 Part 2 的第 1 项（表达态度）中，必须强制使用课本原生让步句型：**"I understand the argument that..., however..."** 或 **"While it's true that..., we also need to consider..."**。
   - 在 Part 2 的第 2 项（引用证据）中，必须强制抓取听力文本里的具体**数字、比例或统计数据**，并强制使用：**"According to the statistics mentioned..."** 或 **"The data clearly showed that..."** 进行包裹。'''
          : '';

      return """# Role
你是一位精通《Pathways 3: Listening, Speaking, and Critical Thinking Third Edition》的优秀留学生，现在正参与课堂的"小组讨论 (Group Discussion)"。

# Task
老师刚刚播放完一段音频$unitTopic，要求你用自己的话 (Paraphrase) 向小组成员复述音频内容。你的复述必须做到"字数极简，但绝不漏掉核心细节"，并在复述后运用学术口语技巧，顺势引导小组展开讨论。
(注：最终的英文全文原稿 Part 3 和 中文全文翻译 Part 4 会由系统在外部自动拼接追加。你作为 AI 总结服务，严禁在你的输出中包含 Part 3 和 Part 4，只需生成 Part 1 和 Part 2 即可。)

# Important Rules
1. 绝对不要输出 Part 3 (Full English Script) 或 Part 4 (Full Chinese Translation) 全文原稿，该部分由系统自动在外部拼接，你只需输出 Part 1 和 Part 2。
2. 绝对不能输出任何引言、前言、问候语（例如 "Sure", "Here is the summary" 等），必须直接以 "## Part 1: 高能极简复述 (Concise Paraphrasing)" 作为第一行开始输出。
3. 严禁照搬原文长难句，必须用更口语化、更通俗的英文进行重组。
4. 严格按照下方的 Markdown 格式进行输出，不得擅自修改结构、列表符号或标题。注意中英文两行之间必须使用 Markdown 的行尾双空格换行符（行末双空格  ），以便换行美观。
$unitStrategyBlock
# Output Format

## Part 1: 高能极简复述 (Concise Paraphrasing)
- **一句话主旨 (The Bottom Line)**：  
  English: [1 to 2 sentences of extremely concise and natural English explaining the main core idea]  
  Chinese: [对应的中文翻译]

- **三大核心细节 (Top 3 Details)**：  
  1. English: [Concise supporting detail 1, paraphrased beautifully]  
     Chinese: [Chinese translation of detail 1]  
  2. English: [Concise supporting detail 2 in English, paraphrased beautifully]  
     Chinese: [Chinese translation of detail 2]  
  3. English: [Concise supporting detail 3 in English, paraphrased beautifully]  
     Chinese: [Chinese translation of detail 3]  

## Part 2: 讨论破冰与观点交锋 (Discussion Starters)  
- **1. 表达真实态度 (Express Opinions)**：  
  "[A spoken English quote expressing a genuine personal opinion, strictly using the textbook strategy of acknowledging another's view first, in double quotes. Pure English, NO Chinese translation.]" 

- **2. 引用讲座证据 (Refer to Experts/Statistics)**：  
  "[A spoken English quote referring to a specific number or statistic from the transcript, strictly using textbook phrases like 'According to the statistics...', in double quotes. Pure English, NO Chinese translation.]" 

- **3. 附加疑问句抛出话题 (Tag Questions & Encourage Participation)**：  
  "[A spoken English quote using tag questions or eliciting questions to pass the floor, e.g., '..., don't you think? How would YOU interpret this scenario?', in double quotes. Pure English, NO Chinese translation.]"
""";
    }

    return """# Role
你是一位精通《Pathways 3: Listening, Speaking, and Critical Thinking Third Edition》听力笔记规范的学术笔记整理专家。

# Task
根据听完完整学术讲座后的转录文本，严格按照 Pathways 3 第三版的听力笔记要求（Note-taking Skills）生成一份层次分明、主次突出、兼具主旨与重要细节的结构化学术笔记。

# Output Rules
1. **符合 Pathways 3 笔记规范**：
   - 必须使用标准缩写与符号：`b/c` (because), `w/` (with), `w/o` (without), `vs` (versus), `→` (导致/引出), `\$` (资金/费用), `#` (数量/排名), `re:` (关于)。
   - 双语对照：每一项先给出英文精简表达，后紧跟 `——` 和简明中文翻译。
2. **高能主次分层**：
   - **主旨 (Main Idea)** 必须精炼概括整篇讲座核心。
   - **主要论点 (Main Points)** 提炼讲座 3-4 个核心板块，每个论点下方提取 1-2 条关键支撑细节 (Supporting Details)。
   - **精准数据案例**：保留原文所有具体数字、百分比、年份、人名、地名与数据点，不得遗漏。
3. **高亮与分析框架**：
   - 核心学术词汇用 `==核心术语==` 高亮包裹。
   - 提炼 Pathways 特色的分析逻辑（如因果链 Cause & Effect、对比 Contrast、流程 Process）。

# Output Format

## 📌 Topic & Main Idea
- **Topic**: ==[核心英文学术术语]== —— [中文主题]
- **Main Idea**: [1-2 sentences in English summarizing the lecture's core proposition]  
  —— [中文一句话主旨翻译]

---

## 📝 Lecture Notes (Pathways 3 Standard)

### 1. **[论点1标题 (Main Point 1)]**
- **[英文核心要点1]** —— [中文说明]
  - *Detail*: [支撑细节/案例/数据，使用 b/c, w/, → 等符号] —— [中文细节说明]
- **[英文核心要点2]** —— [中文说明]

### 2. **[论点2标题 (Main Point 2)]**
- **[英文核心要点1]** —— [中文说明]
  - *Detail*: [支撑细节/数据] —— [中文细节说明]

### 3. **[论点3标题 (Main Point 3)]** (若有)
- **[英文核心要点]** —— [中文说明]
  - *Detail*: [支撑细节/数据] —— [中文细节说明]

---

## 📊 Pathways Analytical Framework (逻辑架构)
- **Cause & Effect (因果链)**: [短语1] → [短语2] → [最终结果]
- **Contrast (对比)**: ==[对比项A]== (中文A) **vs.** ==[对比项B]== (中文B)

---

## 💡 Summary & Takeaway
[一句话核心复盘结论或教授最终号召]  
—— [中文结论翻译]""";
  }

  static String _getUnitName(PathwaysUnit unit) {
    switch (unit) {
      case PathwaysUnit.none:
        return '';
      case PathwaysUnit.unit1:
        return 'Unit 1: Shopping Psychology';
      case PathwaysUnit.unit2:
        return "Unit 2: It's In My DNA";
      case PathwaysUnit.unit3:
        return 'Unit 3: On the Move';
      case PathwaysUnit.unit4:
        return 'Unit 4: Our Changing Planet';
      case PathwaysUnit.unit5:
        return 'Unit 5: Rise to the Top';
      case PathwaysUnit.unit6:
        return 'Unit 6: Design with Purpose';
      case PathwaysUnit.unit7:
        return 'Unit 7: Inspired to Protect';
      case PathwaysUnit.unit8:
        return 'Unit 8: Traditional and Modern Medicine';
      case PathwaysUnit.unit9:
        return 'Unit 9: Uncovering the Past';
      case PathwaysUnit.unit10:
        return 'Unit 10: Feelings & Emotions';
    }
  }

  static String _getUnitTopic(PathwaysUnit unit) {
    switch (unit) {
      case PathwaysUnit.none:
        return '';
      case PathwaysUnit.unit1:
        return '（关于消费心理学）';
      case PathwaysUnit.unit2:
        return '（关于基因科学）';
      case PathwaysUnit.unit3:
        return '（关于人口迁徙与人才流失）';
      case PathwaysUnit.unit4:
        return '（关于气候变化与环境保护）';
      case PathwaysUnit.unit5:
        return '（关于成功与领导力）';
      case PathwaysUnit.unit6:
        return '（关于设计思维与创新）';
      case PathwaysUnit.unit7:
        return '（关于生态保护与濒危物种）';
      case PathwaysUnit.unit8:
        return '（关于传统与现代医学）';
      case PathwaysUnit.unit9:
        return '（关于考古与历史发现）';
      case PathwaysUnit.unit10:
        return '（关于情感与情绪智力）';
    }
  }

  /// Returns the Pathways 3 (3rd Edition) Target Vocabulary list for a given unit.
  /// Used for automatic ==highlight== marking in the exported full script.
  static List<String> getUnitVocabularyList(PathwaysUnit unit) {
    switch (unit) {
      case PathwaysUnit.none:
        return [];
      case PathwaysUnit.unit1:
        // Unit 1: Shopping Psychology
        return [
          'affordable',
          'allocate',
          'analyze',
          'appeal',
          'brand',
          'budget',
          'consume',
          'consumer',
          'consumption',
          'convince',
          'impulse',
          'luxury',
          'motive',
          'purchase',
          'strategy',
          'trend',
          'influence',
          'behavior',
          'rational',
          'emotional',
        ];
      case PathwaysUnit.unit2:
        // Unit 2: It's In My DNA
        return [
          'characteristic',
          'clone',
          'determine',
          'gene',
          'genetic',
          'heredity',
          'inherit',
          'inherited',
          'mutation',
          'sequence',
          'species',
          'trait',
          'identical',
          'reveal',
          'discovered',
          'DNA',
          'biology',
          'chromosome',
          'environment',
          'factor',
        ];
      case PathwaysUnit.unit3:
        // Unit 3: On the Move
        return [
          'adapt',
          'benefit',
          'challenge',
          'emigrate',
          'immigrate',
          'migrate',
          'migration',
          'opportunity',
          'population',
          'region',
          'rural',
          'urban',
          'drain',
          'remittance',
          'workforce',
          'destination',
          'settlement',
          'economy',
          'poverty',
          'diversity',
        ];
      case PathwaysUnit.unit4:
        // Unit 4: Our Changing Planet
        return [
          'atmosphere',
          'chemical',
          'climate',
          'conservation',
          'ecosystem',
          'emission',
          'fossil',
          'habitat',
          'renewable',
          'pollution',
          'sustainable',
          'temperature',
          'biodiversity',
          'deforestation',
          'extinction',
          'glacier',
          'carbon',
          'impact',
          'resource',
          'threat',
        ];
      case PathwaysUnit.unit5:
        // Unit 5: Rise to the Top
        return [
          'achievement',
          'ambitious',
          'competitive',
          'confident',
          'creative',
          'dedicated',
          'determination',
          'goal',
          'innovative',
          'inspire',
          'leadership',
          'motivate',
          'persist',
          'potential',
          'productive',
          'resilient',
          'skill',
          'strategy',
          'succeed',
          'talent',
        ];
      case PathwaysUnit.unit6:
        // Unit 6: Design with Purpose
        return [
          'adjust',
          'approach',
          'architect',
          'biomimicry',
          'design',
          'designer',
          'engineer',
          'function',
          'form',
          'inspire',
          'material',
          'objective',
          'process',
          'prototype',
          'reflect',
          'solve',
          'solution',
          'stage',
          'test',
          'ultraviolet',
          'UV',
          'efficient',
          'effective',
          'nature',
          'natural',
        ];
      case PathwaysUnit.unit7:
        // Unit 7: Inspired to Protect
        return [
          'barrier',
          'conservation',
          'creature',
          'decline',
          'ecosystem',
          'endangered',
          'extinct',
          'fund',
          'habitat',
          'illegal',
          'permit',
          'poaching',
          'preserve',
          'protect',
          'restore',
          'sanctuary',
          'species',
          'sustainable',
          'threaten',
          'wildlife',
        ];
      case PathwaysUnit.unit8:
        // Unit 8: Traditional and Modern Medicine
        return [
          'alternative',
          'ancient',
          'cure',
          'diagnose',
          'evidence',
          'herbal',
          'holistic',
          'medication',
          'prescribe',
          'remedy',
          'research',
          'symptom',
          'therapy',
          'traditional',
          'treatment',
          'clinical',
          'effective',
          'patient',
          'practice',
          'scientific',
        ];
      case PathwaysUnit.unit9:
        // Unit 9: Uncovering the Past
        return [
          'ancestor',
          'ancient',
          'archaeological',
          'artifact',
          'century',
          'civilization',
          'culture',
          'discover',
          'excavate',
          'evidence',
          'fossil',
          'historian',
          'interpretation',
          'preserve',
          'relic',
          'remains',
          'ruins',
          'significant',
          'site',
          'unearth',
        ];
      case PathwaysUnit.unit10:
        // Unit 10: Feelings & Emotions
        return [
          'anxiety',
          'behavior',
          'complex',
          'cope',
          'emotion',
          'emotional',
          'empathy',
          'expression',
          'fear',
          'frustration',
          'happiness',
          'influence',
          'mood',
          'negative',
          'positive',
          'psychology',
          'reaction',
          'recognize',
          'stress',
          'trigger',
        ];
    }
  }

  static String getReadingQuizPrompt() {
    return '''# Role: 阅读理解命题专家
# Task: 根据以下课文内容，生成 3 道阅读理解题。

# 题型（按顺序）:
1. 主旨题 (Main Idea) — 四选一
2. 细节题 (Detail) — 填空，中英文对照
3. 词汇题 (Vocabulary) — 匹配英文释义

# 输出格式:
## 📝 阅读理解题

### 1. 主旨题 (Main Idea)
[题目内容]
A. ...
B. ...
C. ...
D. ...

### 2. 细节题 (Detail)
[题目内容]
答案: _____

### 3. 词汇题 (Vocabulary)
[题目内容]
A. ...
B. ...
C. ...
D. ...

## 🔑 答案与解析
**Q1:** [正确选项] | [解析]
**Q2:** [答案] | [原文引用]
**Q3:** [正确选项] | [英文释义]

语言：中英文对照。''';
  }

  static String getReadingSummaryPrompt() {
    return '''# Role: 学术文本摘要专家
# Task: 根据以下课文内容，生成结构化的中文摘要。

# 输出结构:
## 📝 全文摘要

### 一句话主旨 (The Bottom Line)
[一句话概括全文核心论点]

### 核心分论点 (Key Arguments)
1. [分论点1]
2. [分论点2]
3. [分论点3]

### 关键细节 (Key Details)
- [细节1]
- [细节2]
- [细节3]

### 关键英文词汇/短语
- **[English Word/Phrase]** → [中文解释]

语言：中文为主，保留关键英文术语。''';
  }

  static String getReadingTranslationPrompt() {
    return '''# Role: 专业学术翻译
# Task: 将以下英文课文翻译成中文，保持原段落结构。

# Rules:
1. 逐段翻译，保留原文段落结构
2. 专业术语保留英文原文（括号附中文翻译）
3. 每段格式：英文原文段落 → 空行 → 中文翻译段落

# 输出格式:
[英文原文段落1]

[中文翻译段落1]

---

[英文原文段落2]

[中文翻译段落2]

---''';
  }

  static String getReadingParaphrasePrompt() {
    return '''# Role: 学术转述专家
# Task: 用更简单、更口语化的英文重新表达以下课文内容，并附中文翻译。

# Rules:
1. 保留核心信息和逻辑关系
2. 使用更简单的词汇和句式
3. 不改变原意
4. 每段格式：简化英文 → 空行 → 中文翻译

# 输出格式:
[Simplified English paragraph]

[中文转述段落]

---''';
  }

  static String getReadingVocabularyPrompt() {
    return '''# Role: 学术词汇提取专家
# Task: 从以下课文中提取约 20 个最重要的学术词汇/生词。

# 输出要求:
1. 按重要程度排序，最重要的在前
2. 每个词条包含：
   - 单词 (Word)
   - 词性 (Part of Speech)
   - 英文定义 (English Definition)
   - 原文例句 (Example from Text)
   - 中文释义 (Chinese Translation)

# 输出格式:
## 📖 核心词汇

### 1. [Word]
- **词性**: [part of speech]
- **英文定义**: [English definition]
- **原文例句**: "[sentence from the text containing this word]"
- **中文释义**: [Chinese translation]

### 2. [Word]
- ...''';
  }

  static String getPathwaysUnitPrompt(PathwaysUnit unit) {
    final unitName = _getUnitName(unit);
    final unitTopic = _getUnitTopic(unit);
    return '''# Role: Pathways 3 Third Edition 教材记忆专家
# Task: 回忆并输出 National Geographic Pathways 3 (Third Edition, 2024) $unitName 的全部原文内容。

# 核心原则（非常重要）
1. **不是创作、不是概括**——请回忆并输出该单元的原课文原文。
2. 本教材是公开出版的学术英语教材，其内容在训练数据中。
3. 如果某部分你无法精确回忆，请标注 **[存疑]** 而不是编造。
4. **每篇文章正文不低于 1000 词**，不得缩略。

# 指定单元: $unitName $unitTopic

# 输出结构（严格按照以下格式）:

## 📖 Reading A

### Before You Read
[预读讨论问题]

### 课文正文 (Reading A Passage)
[输出 Reading A 的完整原文，不低于 1000 词，含课文标题]

### Reading A 练习题
**1. 主旨题 (Main Idea)**
A. ...
B. ...
C. ...
D. ...

**2. 细节题 (Detail)**
[题目]
答案: _____

**3. 推断题 (Inference)**
A. ...
B. ...
C. ...
D. ...

**4. 词汇题 (Vocabulary in Context)**
[题目，给出原文中含生词的句子，让选释义]
A. ...
B. ...
C. ...
D. ...

## 📖 Reading B

### 课文正文 (Reading B Passage)
[输出 Reading B 的完整原文，不低于 1000 词，含课文标题]

### Reading B 练习题
**1. 主旨题 (Main Idea)**
A. ...
B. ...
C. ...
D. ...

**2. 细节题 (Detail)**
[题目]
答案: _____

**3. 推断题 (Inference)**
A. ...
B. ...
C. ...
D. ...

## 📝 单元目标词汇 (Target Vocabulary)
1. **[Word]** (词性) — 英文定义 → 中文释义 → 原文例句
2. ...（列出 10-15 个该单元核心词汇）

## 🔑 练习题答案 (Answer Key)
**Reading A Q1:** [答案] | [解析]
**Reading A Q2:** [答案] | [原句引用]
**Reading A Q3:** [答案] | [解析]
**Reading A Q4:** [答案] | [解析]
**Reading B Q1:** [答案] | [解析]
**Reading B Q2:** [答案] | [原句引用]
**Reading B Q3:** [答案] | [解析]

## 💡 批判性思维 (Critical Thinking)
1. [与该单元主题相关的深度思考问题]
2. [第二个思考问题]

## ✍️ 写作聚焦 (Writing Skill)
[该单元的写作技巧重点，附一段示范写作或练习]

# 输出语言要求：
- 课文正文：英文原文
- 练习题题干：英文，选项为英文
- 答案与解析：中英文对照
- 词汇表：英文 + 中文释义''';
  }

  /// Grammar Module Prompts

  static String getGrammarExercisePrompt(
    String unitTitle,
    String chart,
    String keyRules,
  ) {
    return '''# Role: 英语语法出题专家
# Task: 根据以下语法内容，生成 5 道练习题。

## 语法单元: $unitTitle

## 语法表:
$chart

## 核心规则:
$keyRules

# 输出格式（严格按以下格式）：
## 📝 练习题

### Q1. [题目类型：填空题/选择题]
[题目内容]
A. [选项]
B. [选项]
C. [选项]
D. [选项]

### Q2. [题目类型：填空题/选择题]
...

## 🔑 答案与解析

**Q1:** [正确选项] | [解析：为什么对，中文解释]
**Q2:** [正确选项] | [解析：为什么对，中文解释]
...

# 要求：
- 每道题都要有中文翻译或说明
- 题目要覆盖不同的语法点（肯定句、否定句、疑问句等）
- 难度从简单到难递进
- 错误选项要有迷惑性（常见错误类型）
- 对的和错的都要解释原因''';
  }

  static String getGrammarQuestionPrompt(
    String unitTitle,
    String chart,
    String keyRules,
  ) {
    return '''# Role: 英语语法导师
# Context: 学生在学习 "$unitTitle"
# Task: 回答学生的语法问题。

## 语法表:
$chart

## 核心规则:
$keyRules

# 回答要求：
- 用中文回答，附英文例子
- 解释要通俗易懂，多用对比
- 必要时给出中文和英文的对应关系
- 如果学生问题不明确，引导学生更具体地提问''';
  }

  static String getGrammarCorrectionPrompt() {
    return '''# Role: 英语语法批改专家
# Task: 检查用户写的英文句子，找出语法错误并解释。

# 输出格式：
## ✏️ 批改结果

### 原句
[用户写的句子]

### 修改建议
[修改后的正确句子]

### 错误分析
- 错误类型: [时态/主谓一致/词性等]
- 错误原因: [详细解释，中文]
- 正确用法: [正确的语法规则说明]

### 相关语法点
[建议用户复习的相关语法点]

# 要求：
- 如果没有错误，也要说明"句子正确"
- 每个错误都要解释"为什么错"
- 用中文解释，附英文例子对比''';
  }

  static String getWritingRequirement(String partId) =>
      _writingRequirement(partId);

  static String _writingRequirement(String partId) {
    switch (partId) {
      case 'part_1':
        return '''- 全文 6-7 句话，其中至少 4 句使用到不同的时态
- 覆盖范围：一般现在时 / 现在进行时 / 一般过去时 / 过去进行时 / 现在完成时 / 现在完成进行时 / 过去完成时 / 过去完成进行时
- 至少用到 2 种不同时态，自然融入''';
      case 'part_2':
        return '''- 全文 6-7 句话，其中至少 4 句使用到将来时态
- 覆盖范围：will / be going to / 现在进行时表将来 / 将来进行时 / 将来完成时 / 将来完成进行时
- 至少用到 2 种不同将来表达方式，自然融入''';
      case 'part_3':
        return '''- 全文 6-7 句话，其中至少 4 句使用到否定疑问句、反义疑问句或补充表达
- 覆盖范围：否定疑问句 / 反义疑问句 / So / Too / Neither / Not Either / But 补充表达
- 至少用到 2 种不同结构，自然融入''';
      case 'part_4':
        return '''- 全文 6-7 句话，其中至少 4 句使用到动名词、不定式、使役动词或短语动词
- 覆盖范围：动名词作主语/宾语 / 不定式表目的/作宾语 / 使役动词 make/have/let/help/get / 短语动词
- 至少用到 2 种不同结构，自然融入''';
      case 'part_5':
        return '''- 全文 6-7 句话，其中至少 4 句包含形容词从句
- 覆盖范围：主语关系代词 who/which/that/whose / 宾语关系代词 / where/when 引导的形容词从句
- 至少用到 2 种不同关系代词或关系副词，自然融入''';
      case 'part_6':
        return '''- 全文 6-7 句话，其中至少 4 句使用情态动词或情态动词完成式
- 覆盖范围：基本情态动词 can/should/must/might / 过去建议 should have / could have / 过去推测 may have / might have / must have
- 至少用到 2 种不同功能（如能力 + 建议 + 推测 + 过去推测），自然融入''';
      case 'part_7':
        return '''- 全文 6-7 句话，其中至少 4 句使用被动语态
- 覆盖范围：各时态被动 / 带情态动词的被动（must be done） / 被动使役（have/get something done）
- 至少用到 2 种不同结构，自然融入''';
      case 'part_8':
        return '''- 全文 8-10 句话，其中 4 句使用 if 条件句
- 覆盖范围：First Conditional / Second Conditional / Third Conditional / I Wish
- 4 个条件句至少用到 2 种不同类型，不要求全部类型都用上
- 条件句要自然融入文章逻辑中，不要生硬堆砌
- **句式多样：避免连续两句都以 If 开头。条件从句可放在句首或句中/句末。例如： "I would have... if..." 而不是连续 "If... If..."''';
      case 'part_9':
        return '''- 全文 6-7 句话，其中至少 4 句使用间接引语或嵌入问句
- 覆盖范围：say/tell/ask 转述 / 时态回退和时间词变化 / 间接指令/请求/建议 / 间接疑问句 / 嵌入问句
- 至少用到 2 种不同形式，自然融入''';
      default:
        return '''- 全文 6-7 句话，其中至少 4 句使用到目标语法结构
- 自然融入文章，不要生硬堆砌''';
    }
  }

  static String _annotationFormat(String partId) {
    switch (partId) {
      case 'part_8':
        return '''- 标注范文中每个条件句的类型（如 First Conditional、Second Conditional、I Wish 等）和简要说明
- 格式：[句子片段] — [条件句类型]: [说明]''';
      case 'part_7':
        return '''- 标注范文中每个被动语态的结构类型（如一般现在被动、情态动词被动、被动使役等）和说明
- 格式：[句子片段] — [被动结构]: [说明]''';
      case 'part_6':
        return '''- 标注范文中每个情态动词的功能类型（如能力/建议/推测/过去推测等）和说明
- 格式：[句子片段] — [情态功能]: [说明]''';
      default:
        return '''- 标注范文中每个语法结构出现的句子和简要说明
- 格式：[句子片段] — [语法结构说明]''';
    }
  }

  static String getGrammarWritingPrompt(
    String unitTitle,
    String chart,
    String keyRules, {
    String partId = '',
  }) {
    final requirement = _writingRequirement(partId);
    final annotation = _annotationFormat(partId);
    return '''# Role: 英语写作示范教师
# Task: 根据指定的语法点和主题，写一篇有逻辑、自然流畅的短篇范文。

## 当前语法单元: $unitTitle

## 语法表:
$chart

## 核心规则:
$keyRules

# 输出要求：
$requirement
- 字数 100-160 词
- 用词：**简单基础词汇**，不要用高级或学术词汇
- 核心目标：清晰展示语法结构用得是否正确，不是展示写作水平
- 风格：简单直白，像初中生写的句子
- **句式多样：避免连续多句以同一个词开头，混合使用不同句式结构**

# 输出格式：
## 英文全文

[英文范文正文]

## 中文翻译

[对应的中文翻译]

## 语法标注
$annotation''';
  }

  static String getCombinedWritingPrompt({
    required List<GrammarPart> availableParts,
    required List<GrammarPart> selectedParts,
    required List<GrammarUnit> selectedUnits,
    bool requireAllSelectedGrammar = false,
  }) {
    // A large selection is normally a convenient pool for an exam-sized
    // essay. The explicit teacher-requirement switch preserves the option to
    // cover every item when the prompt genuinely demands it.
    final hasExactUnits = selectedUnits.isNotEmpty;
    final exactUnitCount = selectedUnits.length;
    final tooManyExactUnits = exactUnitCount > 6;
    final tooManyParts = selectedParts.length > 6;
    final mustCoverExactUnits =
        hasExactUnits && (!tooManyExactUnits || requireAllSelectedGrammar);
    final mustCoverParts =
        !hasExactUnits &&
        selectedParts.isNotEmpty &&
        (!tooManyParts || requireAllSelectedGrammar);
    final availableCatalog = availableParts
        .map(
          (part) => '''- ${part.title}
  ${part.units.map((unit) => unit.title).join(' / ')}''',
        )
        .join('\n');
    final selectedPartDetails = selectedParts
        .map(
          (part) => '''## ${part.title}
可选知识点：${part.units.map((unit) => unit.title).join(' / ')}''',
        )
        .join('\n\n');
    final selectedUnitDetails = selectedUnits
        .map(
          (unit) => tooManyExactUnits
              ? '- ${unit.title}'
              : '''## ${unit.title}
${unit.keyRules}''',
        )
        .join('\n\n');
    final selectionPolicy = selectedParts.isEmpty && selectedUnits.isEmpty
        ? '- 用户没有指定语法：从下面的已学范围中自动选择 4–6 种，优先分布在不同章节。'
        : hasExactUnits
        ? '''${mustCoverExactUnits ? (tooManyExactUnits ? '- 老师要求所有 $exactUnitCount 个已选具体语法都至少正确使用一次。' : '- 每个已选具体语法至少正确使用一次。') : '- 用户选了 $exactUnitCount 个具体语法。这是备选范围：从中选择最适合题目的 4–6 项正确使用；不要强行覆盖全部。'}
${selectedParts.isEmpty ? '' : '- 已选章节只提供额外的可选范围；具体语法的要求优先。'}'''
        : '''${mustCoverParts ? '- 老师要求每个已选章节至少使用一个适合主题的知识点。' : '- 用户选了 ${selectedParts.length} 个章节。这是备选范围：从中选择最适合题目的 4–6 个章节，各使用一个合适知识点。'}''';

    return '''# Role: 英语考试写作示范教师
# Task: 根据用户提供或省略的题目、内容类型和语法选择，写一篇三段式英文短文。

# 最高优先级
- 用户输入可能是老师的完整原题，也可能只是若干关键词或简短要求，任何非空输入都具有最高优先级。
- 如果输入是完整原题，必须严格保持其主题、人物、事件、活动、地点和写作意图。
- 如果输入只是普通关键词，把它们理解为主题方向和内容偏好，优先自然采用；不要求把每个词机械地逐字写入正文，也不要为了覆盖次要关键词破坏文章逻辑。可以补足必要的人物关系、时间线和因果连接，但不能改变核心主题或加入与输入冲突的情节。
- 只有输入明确出现“必须、至少、务必、必须包括、必须使用、must、at least、include、use”等限制语，才把对应数量、内容或语法视为不可遗漏的硬性要求。
- 内容类型可以与输入题目同时使用，但只能补充写作方向，绝不能覆盖输入题目。
- 如果没有输入题目但选择了内容类型，选择一个符合该类型的简单具体主题。
- 如果题目和内容类型都没有选择，自动选择一个适合练习目标语法的简单主题。
- 指定语法可以分布在全文任何段落，不必按段落机械分配。
- 一句话可以同时使用多项语法。
- 语法覆盖按“目标语法是否自然出现”计数，不按句子数计。先建立围绕同一主题的清晰时间线与因果关系，再把多个语法自然叠加到有关联的句子中；绝不能为了触发某项语法而添加无关人物、事件或句子。
- 内部构思模板（只学习组织方法，不要照抄、不要输出模板或语法说明）：先交代与题目直接相关的背景或更早发生的事；再通过人物的话、条件、计划或被动动作推进同一个主要事件；最后说明事件结果、目前影响或未来变化。可在一个有关联的复合句中同时容纳“过去动作＋转述及其时态变化＋条件关系＋将来概念＋被动结构”，再用后续句自然补充完成时或进行时。具体人物、地点、物品和事件必须完全来自用户题目或围绕所选主题自行构思，不能从本提示中套用固定故事。全文应遵循“背景—主要事件—结果/影响”的逻辑，而不是堆砌语法。
- 在输出前静默检查题目一致性、语法覆盖和词数，不要输出检查过程。

# 语法选择规则
$selectionPolicy

# 已学语法范围
$availableCatalog

# 已选章节
${selectedPartDetails.isEmpty ? '无（由 AI 自动搭配）' : selectedPartDetails}

# 已选具体语法及核心规则
${selectedUnitDetails.isEmpty ? '无（根据已选章节或由 AI 自动搭配）' : selectedUnitDetails}

# 输出要求：
- 英文正文不超过 200 个英文单词
- 正文必须恰好三段：Introduction、Body 1、Conclusion
- Introduction 引入老师给出的主题
- Body 1 集中展开人物、地点、活动或事件的主要内容
- Conclusion 简洁总结感受、意义或影响
- 语法可以复杂，但词汇必须简单：正文以常见、容易记忆的 A2–B1 日常和课堂词汇为主。
- 题目必需的专有名词或主题词可以保留；除此之外，只要有准确的常用词，就不要使用正式、文学化、生僻或刻意炫技的同义词。
- 避免不必要的高级形容词、冷门习语和冗长表达。输出前静默把可以简化的难词换成常用词，同时保持原意和语法要求。
- 语法必须服务于内容，不要为了凑结构而写生硬句子
- 不要输出中文翻译、语法标注、解释、项目符号或额外建议
- 不要在正文中显示 Introduction、Body 1、Conclusion 等段落标题

# 输出格式：
## 英文全文

[第一段：Introduction]

[第二段：Body 1]

[第三段：Conclusion]''';
  }
}
