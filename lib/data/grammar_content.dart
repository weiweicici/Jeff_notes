import '../models.dart';

class GrammarContent {
  static const List<GrammarPart> parts = [
    GrammarPart(
      id: 'part_1',
      title: 'Part 1: 现在和过去时态 (Present & Past)',
      units: [
        GrammarUnit(
          id: 'unit_1',
          title: 'Unit 1: Simple Present & Present Progressive',
          outcomes:
              '''• Describe actions, states, and situations that happen regularly (描述经常发生的动作和状态)
• Describe actions that are happening now (描述正在发生的动作)
• Talk about unchanging facts and general truths (谈论不变的事实和普遍真理)''',
          chart: '''## SIMPLE PRESENT — 一般现在时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | They **live** in Mexico. / She **works** here. |
| **Negative** 否定句 | They **don't live** in Mexico. / She **doesn't work** here. |
| **Yes/No Question** 一般疑问句 | **Do** they live in Mexico? / **Does** she work here? |
| **Short Answer** 简短回答 | Yes, they **do**. / No, she **doesn't**. |
| **Wh- Question** 特殊疑问句 | Where **do** they live? / Who **teaches** that class? |

## PRESENT PROGRESSIVE — 现在进行时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | They **'re living** in Mexico now. / She **'s working** here today. |
| **Negative** 否定句 | They **aren't living** in Mexico now. / She **isn't working** here now. |
| **Yes/No Question** 一般疑问句 | **Are** they living in Mexico now? / **Is** she working here now? |
| **Short Answer** 简短回答 | Yes, they **are**. / No, she **isn't**. |
| **Wh- Question** 特殊疑问句 | Where **are** they living these days? / Who **'s** teaching that class now? |''',
          chineseGuide: '''## 🇨🇳 中文对比解析

### 一般现在时 (Simple Present) —— "我每天喝咖啡"

**什么时候用？**
1. **习惯/经常做的事** — "I **drink** coffee every morning."（我每天早上喝咖啡）
2. **客观事实/真理** — "Water **boils** at 100°C."（水在 100°C 沸腾）
3. **状态/感受** — "I **like** ice cream."（我喜欢冰淇淋）
4. **时刻表** — "The train **leaves** at 8 PM."（火车晚上 8 点开）

**和中文的区别：**
- 中文：动词不变，"我每天喝" / "他每天喝"
- 英文：第三人称单数加 **-s/-es**，"I drink" → "He **drinks**"

### 现在进行时 (Present Progressive) —— "我正在喝咖啡"

**什么时候用？**
1. **此刻正在发生** — "I **'m drinking** coffee **right now**."（我现在正在喝咖啡）
2. **现阶段在做（未必此刻）** — "She **'s studying** in Canada **these days**."（她这段时间在加拿大学习）
3. **变化趋势** — "The weather **is getting** warmer."（天气在变暖）
4. **计划好的将来** — "I **'m meeting** him tonight."（我今晚要见他——已安排好）

**和中文的区别：**
- 中文："正在" + 动词不变（我正在喝）
- 英文：**be (am/is/are) + 动词-ing**（I am drinking）

### 怎么选择？

| 场景 | 用哪个 | 例子 |
|---|---|---|
| 每天做的事 | Simple Present | I **eat** breakfast at 7. |
| 此刻正在做 | Present Progressive | I **'m eating** breakfast now. |
| 客观事实 | Simple Present | The sun **rises** in the east. |
| 近期变化 | Present Progressive | It **'s getting** colder. |
| 喜欢/想要（状态） | Simple Present | I **want** a coffee. |
| 非延续动词（know, believe） | Simple Present | I **know** the answer. |''',
          keyRules: '''## ⚡ Key Rules

### Simple Present
1. 第三人称单数 (he/she/it) 动词加 **-s** 或 **-es**
   - work → works / go → goes / study → studies
2. 否定句用 **do/does + not**，疑问句用 **do/does** 开头
   - He **doesn't** live here. / **Does** he live here?
3. 频率副词 (always, usually, sometimes, never) 放在动词前面
   - She **always** arrives on time.
   - 如果动词是 be，副词放在 be 后面：She **is always** happy.

### Present Progressive
1. 结构：**be (am/is/are) + 动词-ing**
2. 否定句在 be 后面加 **not**
3. 非延续动词 (non-action verbs) 一般不用于进行时
   - ❌ I am knowing → ✅ I know
   - ❌ She is wanting → ✅ She wants
   - 常见非延续动词：be, like, love, hate, want, need, know, believe, understand, seem''',
          commonMistakes: '''## ❌ 常犯错误

| ❌ 错误 | ✅ 正确 | 原因 |
|---|---|---|
| He **don't** live here. | He **doesn't** live here. | 第三人称单数用 doesn't，不是 don't |
| She **is work** now. | She **is working** now. | 进行时要加 -ing |
| Right now, I **look** for a key. | Right now, I **'m looking** for a key. | "此刻正在"用进行时 |
| A typical day **is beginning** at 6. | A typical day **begins** at 6. | 习惯性动作用一般现在时 |
| I **am wanting** to explain. | I **want** to explain. | want 是非延续动词，不用进行时 |''',
          vocabulary: '''## 📝 本节词汇

| 词汇 | 词性 | 意思 |
|---|---|---|
| adjustment | n. | 调整，适应 |
| provide | v. | 提供 |
| in style | phr. | 流行，时髦 |
| consist of | phr. | 由……组成 |
| respectful | adj. | 尊敬的，有礼貌的 |
| identity | n. | 身份 |
| confusion | n. | 困惑，混淆 |
| nickname | n. | 昵称，绰号 |
| patronymic | n. | 父名（来自父亲的名字）|
| disrespectful | adj. | 不尊重的 |''',
        ),
        GrammarUnit(
          id: 'unit_2',
          title: 'Unit 2: Simple Past & Past Progressive',
          outcomes:
              '''• Describe one past action interrupted by another (描述一个过去动作被另一个打断)
• Describe two past actions in progress at the same time (描述两个同时进行的过去动作)
• Show the order of events in a description (展示事件发生的先后顺序)
• Write about past events (描写过去的事件)''',
          chart: '''## SIMPLE PAST — 一般过去时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | Maria Sklodowska **studied** in Paris. |
| **Negative** 否定句 | Lois **didn't plan** to marry Clark at first. |
| **Yes/No Question** 一般疑问句 | **Did** he teach? |
| **Short Answer** 简短回答 | Yes, he **did**. / No, he **didn't**. |
| **Wh- Question** 特殊疑问句 | What **did** they do? / Who **worked** in their lab? |

## PAST PROGRESSIVE — 过去进行时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | She **was studying** in Paris in 1891. |
| **Negative** 否定句 | She **wasn't planning** to get married. |
| **Yes/No Question** 一般疑问句 | **Was** he teaching? |
| **Short Answer** 简短回答 | Yes, he **was**. / No, he **wasn't**. |
| **Wh- Question** 特殊疑问句 | What **were** they doing? |

## 连用：Simple Past + Past Progressive

| 结构 | 例句 | 意思 |
|---|---|---|
| Simple Past + Simple Past | She **painted** it when she **recovered**. | 先恢复，后画（两个顺序完成的动作）|
| Past Prog + Simple Past | She **met** him while she **was studying**. | 正在学习时遇到了他（打断）|
| Past Prog + Past Prog | She **was painting** while she **was recovering**. | 两个动作同时进行 |''',
          chineseGuide: '''## 🇨🇳 中文对比解析

### 一般过去时 (Simple Past) —— "我昨天喝了咖啡"

**什么时候用？**
1. **过去完成的动作** — "I **visited** my grandma yesterday."（我昨天看了外婆——看完了）
2. **过去的习惯** — "I **walked** to school every day when I was a kid."（我小时候每天走路去学校）
3. **过去的顺序事件** — "He **stood up**, **walked** to the door, and **left**."（他站起来，走到门口，离开了）

**和中文的区别：**
- 中文：动词不变，"我昨天喝咖啡"（靠"昨天"表达过去）
- 英文：**动词变过去式**（drink → drank, go → went, do → did）

### 过去进行时 (Past Progressive) —— "我昨天下午三点正在喝咖啡"

**什么时候用？**
1. **过去某一时刻正在做** — "At 3 PM yesterday, I **was drinking** coffee."（昨天下午三点我正在喝咖啡）
2. **背景动作（被另一个动作打断）** — "I **was sleeping** when the phone **rang**."（我正在睡觉，电话响了）
3. **两个同时进行的过去动作** — "While I **was cooking**, he **was watching** TV."（我在做饭的同时他在看电视）

**和中文的区别：**
- 中文："正在" + "当时"（我当时正在喝咖啡）
- 英文：**was/were + 动词-ing**

### Simple Past vs Past Progressive 怎么看？

| 场景 | 用哪个 | 例子 |
|---|---|---|
| 过去做完了 | Simple Past | I **ate** lunch at noon. |
| 过去正在做 | Past Progressive | I **was eating** when you called. |
| 两个顺序动作 | Simple Past + Simple Past | He **came** in and **sat** down. |
| 一个打断另一个 | Past Prog + Simple Past | I **was driving** when I **saw** the accident. |
| 两个同时进行 | Past Prog + Past Prog | She **was reading** while he **was writing**. |

**关键词提示：**
- **when** + 一般过去时（打断的那个动作）：I was sleeping **when** the phone rang.
- **while** + 过去进行时（持续的那个动作）：The phone rang **while** I was sleeping. |''',
          keyRules: '''## ⚡ Key Rules

### Simple Past
1. 规则动词加 **-ed**（work→worked, study→studied）
2. 不规则动词需单独记忆（go→went, meet→met, write→wrote）
3. 否定句用 **didn't + 动词原形**，疑问句用 **Did + 主语 + 动词原形**
4. 常见过去时间词：yesterday, last week, in 2014, ago

### Past Progressive
1. 结构：**was/were + 动词-ing**
2. 常用于设置故事背景（较长动作用进行时，打断的动作用一般过去时）
3. 非延续动词一般不用于过去进行时
   - ❌ I was knowing → ✅ I knew
   - ❌ She was wanting → ✅ She wanted

### when vs while
- **when** + 一般过去时（快动作/打断）：I was leaving **when** he arrived.
- **while** + 过去进行时（持续动作）：He arrived **while** I was leaving.
- 两个进行时之间可以用 when 或 while''',
          commonMistakes: '''## ❌ 常犯错误

| ❌ 错误 | ✅ 正确 | 原因 |
|---|---|---|
| I **was meeting** her in 2014. | I **met** her in 2014. | 已完成的过去动作不用进行时 |
| I **left** the airport when I first saw her. | I **was leaving** the airport when I first saw her. | "正在离开时遇见"用进行时 |
| **While** I got into a taxi, I fell. | **While** I **was getting** into a taxi, I fell. | while 后面的持续动作用进行时 |
| I fell, while I was getting into a taxi. | While I was getting into a taxi, I fell. | 时间状语从句在前时加逗号 |''',
          vocabulary: '''## 📝 本节词汇

| 词汇 | 词性 | 意思 |
|---|---|---|
| accomplish | v. | 完成，实现 |
| cover | v. | 报道；覆盖 |
| influential | adj. | 有影响力的 |
| pursue | v. | 追求；继续 |
| recover | v. | 恢复；康复 |
| research | n./v. | 研究 |
| propose | v. | 求婚；提议 |
| disguised | adj. | 伪装的 |
| mild-mannered | adj. | 温和的 |
| mural | n. | 壁画 |''',
        ),
        GrammarUnit(
          id: 'unit_3',
          title:
              'Unit 3: Simple Past, Present Perfect & Present Perfect Progressive',
          outcomes:
              '''• Show that something started in the past and was not completed (表示过去开始但未结束)
• Show that something happened at an indefinite time in the past (表示过去不确定的时间发生的事)
• Use for or since to show duration (用 for/since 表示持续时间)
• Distinguish between finished and unfinished actions (区分已完成和未完成的动作)''',
          chart: '''## SIMPLE PAST — 一般过去时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | I **moved** three months ago. |
| **Negative** 否定句 | She **didn't write** a blog post last night. |
| **Yes/No Question** 一般疑问句 | **Did** he cook dinner? |
| **Short Answer** 简短回答 | Yes, he **did**. / No, he **didn't**. |

## PRESENT PERFECT — 现在完成时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | I **'ve lived** here for three months. |
| **Negative** 否定句 | She **hasn't written** a new blog post. |
| **Yes/No Question** 一般疑问句 | **Has** he cooked dinner? |
| **Short Answer** 简短回答 | Yes, he **has**. / No, he **hasn't**. |

## PRESENT PERFECT PROGRESSIVE — 现在完成进行时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | I **'ve been living** here for three months. |
| **Negative** 否定句 | She **hasn't been writing** lately. |
| **Yes/No Question** 一般疑问句 | **Has** he been cooking? |
| **Short Answer** 简短回答 | Yes, he **has**. / No, he **hasn't**. |''',
          chineseGuide: '''## 🇨🇳 中文对比解析

### 一般过去时 (Simple Past) —— "我喝了（喝完了）"

**什么时候用？**
- 过去特定时间发生且已结束
- "I **drank** coffee this morning."（今天早上我喝了咖啡——现在是下午，喝完了）

### 现在完成时 (Present Perfect) —— "我喝过 / 我已经喝了"

**什么时候用？**
1. **经历/经验**（不问什么时候）— "I **'ve tried** sushi."（我吃过寿司——重点是有没有这个经历）
2. **已完成但结果影响现在** — "I **'ve lost** my keys."（我把钥匙丢了——现在找不到）
3. **持续到现在的状态**（for/since）— "I **'ve lived** here for 3 years."（我在这儿住了 3 年了——现在还住着）

### 现在完成进行时 (Present Perfect Progressive) —— "我一直在喝"

**什么时候用？**
1. **强调一直持续到现在的动作** — "I **'ve been waiting** for an hour."（我已经等了一个小时了——还在等）
2. **刚结束但仍能看到结果** — "You **'ve been crying**."（你哭过了——眼睛还红着）
3. **强调动作本身而非结果** — "I **'ve been reading** your book."（我一直在看你的书——还没看完）

### 三个时态的对比

| 场景 | 用哪个 | 例子 |
|---|---|---|
| 昨天/去年发生的 | Simple Past | I **moved** here last year. |
| 从过去持续到现在 | Present Perfect | I **'ve lived** here for a year. |
| 强调一直在进行 | Present Perfect Prog | I **'ve been living** here since 2023. |
| 有/没有这个经历 | Present Perfect | **Have** you **ever been** to Japan? |
| 什么时候去的？ | Simple Past | I **went** to Japan in 2019. |

### for vs since

**for + 时间段**（持续多久）
- for 3 years / for a week / for a long time

**since + 时间点**（从什么时候开始）
- since 2020 / since Monday / since I was a child

**中文里靠时间词区分，英文靠时态 + for/since 区分** |''',
          keyRules: '''## ⚡ Key Rules

### 三种时态的区分
1. **Simple Past**：过去特定时间发生并结束 → I **studied** in 2014.
2. **Present Perfect**：过去开始，可能持续到现在，或经验 → I **'ve studied** here for 2 years.
3. **Present Perfect Progressive**：强调一直持续 → I **'ve been studying** all morning.

### Present Perfect 关键词
- **ever / never**（经历）：Have you **ever** been? I have **never** seen it.
- **already / yet**（已完成）：I've **already** eaten. / Have you eaten **yet**?
- **just**（刚完成）：I've **just** finished.
- **lately / recently**（最近）：I've been busy **lately**.

### 常见误区
- ❌ I have started a Zumba class **two weeks ago**.
- ✅ I **started** a Zumba class two weeks ago.（有具体时间用 Simple Past）
- ❌ People did Zumba **since** 1986.
- ✅ People **have been doing** Zumba since 1986.（since 用完成时）''',
          commonMistakes: '''## ❌ 常犯错误

| ❌ 错误 | ✅ 正确 | 原因 |
|---|---|---|
| I've started a Zumba class **two weeks ago**. | I **started** a Zumba class two weeks ago. | 有具体过去时间用一般过去时 |
| People **did** Zumba **since** 1986. | People **have been doing** Zumba since 1986. | since 与完成时连用 |
| We've **been finishing** today's class. | We've **finished** today's class. | finish 是短期动作，不用完成进行时 |
| I've been knowing him for years. | I've **known** him for years. | know 是非延续动词 |
| I **baked** a lot of pies lately. | I **'ve baked** / **'ve been baking** a lot of pies lately. | lately 用完成时，不用一般过去时 |''',
          vocabulary: '''## 📝 本节词汇

| 词汇 | 词性 | 意思 |
|---|---|---|
| trend | n. | 趋势，潮流 |
| motivation | n. | 动机，动力 |
| alternative | n. | 替代选择 |
| passion | n. | 热情，热爱 |
| survive | v. | 幸存；生存 |
| experiment | v./n. | 实验；尝试 |
| discover | v. | 发现 |
| hobby | n. | 爱好 |
| blog | n. | 博客 |
| culinary | adj. | 烹饪的 |''',
        ),
        GrammarUnit(
          id: 'unit_4',
          title: 'Unit 4: Past Perfect & Past Perfect Progressive',
          outcomes:
              '''• Describe events that happened before a specific time in the past (描述在过去某个时间之前已经发生的事)
• Show the order of two past events (展示两个过去事件的先后顺序)
• Use adverbs like already, yet, ever, never with past tenses (使用 already/yet/ever/never 等副词)
• Write about someone's life and career (描写某人的生平事业)''',
          chart: '''## PAST PERFECT — 过去完成时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | He **had** already **arrived** by then. |
| **Negative** 否定句 | He **had not** **(hadn't) become** famous yet. |
| **Yes/No Question** 一般疑问句 | **Had** they **arrived** by then? |
| **Short Answer** 简短回答 | Yes, they **had**. / No, they **hadn't**. |
| **Wh- Question** 特殊疑问句 | How many concerts **had** he **given**? |

## PAST PERFECT PROGRESSIVE — 过去完成进行时

| 形式 | 例句 |
|---|---|
| **Affirmative** 肯定句 | He **had been playing** for years by then. |
| **Negative** 否定句 | He **hadn't been playing** long. |
| **Yes/No Question** 一般疑问句 | **Had** he **been playing** the violin? |
| **Short Answer** 简短回答 | Yes, he **had**. / No, he **hadn't**. |

## 时间关系对比

| 结构 | 例子 | 顺序 |
|---|---|---|
| Past Perfect + Simple Past | When I arrived, the concert **had started**. | 音乐会先开始，我后到 |
| Simple Past + Simple Past | When I arrived, the concert **started**. | 我先到，音乐会开始 |
| Past Perf Prog + Simple Past | He **had been conducting** for 12 years when he **moved**. | 指挥了 12 年才搬家 |''',
          chineseGuide: '''## 🇨🇳 中文对比解析

### 过去完成时 (Past Perfect) —— "我（当时）已经喝了"

**什么时候用？**
- 表示"过去的过去"——在过去的某个时间点之前已经发生并完成了
- "By the time I arrived, the concert **had started**."（我到的时候，音乐会已经开始了——音乐会开始先于我到）

**中文怎么表达？**
- 中文："已经" + "了"（我到的时候，音乐会**已经开始了**）
- 英文：**had + 过去分词**

### 过去完成进行时 (Past Perfect Progressive) —— "我（当时）一直在喝"

**什么时候用？**
1. **强调在过去某个时间之前一直在进行的动作** — "He **had been waiting** for an hour when she finally arrived."（在她到之前，他已经等了一个小时了）
2. **刚结束、能看到结果** — "She was out of breath. She **had been running**."（她喘不上气，她一直在跑）

**中文怎么表达？**
- 中文："（当时）一直在"（他**一直在等**，等了一个小时）
- 英文：**had been + 动词-ing**

### 过去时态的完整对比（四个时态）

| 时态 | 中文理解 | 例子 |
|---|---|---|
| Simple Past | "喝了"（过去某时喝了） | I **drank** coffee at 8 AM. |
| Past Progressive | "当时正在喝" | I **was drinking** coffee when you called. |
| Past Perfect | "（当时）已经喝了" | I **had drunk** coffee before you arrived. |
| Past Perf Prog | "（当时）一直在喝" | I **had been drinking** coffee all morning. |

### by 的用法

**by + 时间** = "到……时候为止"
- **By 2006**, he had gotten married.（到 2006 年为止，他已经结婚了）
- **By the time** I sat down, the concert had started.（等我坐下时，音乐会已经开始了）|''',
          keyRules: '''## ⚡ Key Rules

### Past Perfect
1. 结构：**had + 过去分词**（所有人称都用 had）
2. 表示"两个过去动作中，先发生的那个"
3. 关键词：**already, yet, ever, never, just, by, by the time**

### Past Perfect Progressive
1. 结构：**had been + 动词-ing**
2. 强调动作的持续，而非结果
3. 非延续动词不可用：❌ had been being → ✅ had been

### 什么情况下可以用 Simple Past 代替 Past Perfect？
- 当时间关系很清楚时（用了 before, after, as soon as 等）
- **After** he joined (or had joined) the program, he studied violin.
- **Before** he left, he seemed tired. |''',
          commonMistakes: '''## ❌ 常犯错误

| ❌ 错误 | ✅ 正确 | 原因 |
|---|---|---|
| By the time I arrived, the concert **started**. | By the time I arrived, the concert **had started**. | "音乐会先开始"用过去完成时 |
| Before he left, he **had been seeming** tired. | Before he left, he **had seemed** tired. | seem 是非延续动词，不用进行时 |
| I had decided to attend, **by the end of the evening**. | **By the end of the evening**, I had decided to attend. | by 短语放在句首更正式 |
| The concert had started, **by the time I sat down**. | **By the time I sat down**, the concert had started. | by the time 从句放前面 |''',
          vocabulary: '''## 📝 本节词汇

| 词汇 | 词性 | 意思 |
|---|---|---|
| conduct | v. | 指挥（乐队）|
| prodigy | n. | 天才，神童 |
| transform | v. | 转变，改变 |
| inspire | v. | 激励，鼓舞 |
| contract | n. | 合同 |
| ethnic | adj. | 民族的，种族的 |
| participate | v. | 参与 |
| debut | n. | 首次亮相，出道 |
| baton | n. | 指挥棒 |
        | enthusiastic | adj. | 热情的，热烈的 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_2',
      title: 'Part 2: 将来时态 (Future)',
      units: [
        GrammarUnit(
          id: 'unit_5',
          title: 'Unit 5: Future & Future Progressive',
          outcomes:
              '''• Discuss future facts, predictions, plans, and scheduled events (讨论将来事实、预测、计划和既定安排)
• Describe events that will be in progress at a specific time in the future (描述将来某个时间点正在进行的动作)
• Identify key details in a reading or recording (识别阅读或录音中的关键细节)
• Discuss life in the future (讨论未来的生活)
• Write about how one's school will be in the future (描写未来学校会是什么样子)''',
          chart: '''## FUTURE — 将来时

### Affirmative
| 形式 | 例句 |
|---|---|
| **be going to** | We **are going to take** the airship at 9:00. |
| **will** | We **will take** the airship at 9:00. |
| **present progressive** | We **are taking** the airship at 9:00. |
| **simple present** | The airship **leaves** at 9:00 a.m. |

### Negative
| 形式 | 例句 |
|---|---|
| **be going to** | We **are not going to take** the airship at 10:00. |
| **will** | We **will not take** the airship at 10:00. |
| **present progressive** | We **are not taking** the airship at 10:00. |
| **simple present** | We **don't take** the airship at 10:00. |

### Yes/No Questions
| 形式 | 例句 |
|---|---|
| **be going to** | **Is** she **going to take** the airship at 9:00? |
| **will** | **Will** she **take** the airship at 9:00? |
| **present progressive** | **Is** she **taking** the airship at 9:00? |
| **simple present** | **Does** she **take** the airship at 9:00? |

---

## FUTURE PROGRESSIVE — 将来进行时

| 形式 | 例句 |
|---|---|
| **Subject + be (not) going to/will (not) + be + -ing** | People **are going to be traveling** to Mars by 2050. |
|  | People **will be traveling** to Mars by 2050. |
| **肯定回答** | Yes, they **are/will**. |
| **否定回答** | No, they **'re not/won't**. |
| **Yes/No问句** | **Are** they **going to be traveling** to Mars? |
| | **Will** they **be traveling** to Mars? |
| **Wh-问句** | When **will** they **be traveling** to Mars? |''',
          chineseGuide: '''## 中文对比解析

### 四种将来表达方式的核心区别

| 表达方式 | 使用场景 | 中文理解 |
|---|---|---|
| **be going to** | ① 预测（有先兆）；② 已决定的计划 | "打算要…"、"看这架势要…" |
| **will** | ① 客观事实；② 现场决定；③ 承诺/提议；④ 正式书面语 | "将会…"（不带主观计划的） |
| **present progressive** | 已安排好、有明确时间的具体计划 | "已经安排好要…" |
| **simple present** | 按时刻表、日程必然发生的事 | "按计划/时刻表…" |

### 1. be going to vs. will — "打算要" 跟 "将会"
- **be going to** 用于说话前已经决定好的事，或当下看到迹象后做出的预测
  > I'm going to fly to Tokyo next week.（已经买了票）
  > Look! That robot is going to serve our coffee!（看到机器人过来了）
- **will** 用于说话时临时决定、承诺、提议，或客观的将来事实
  > A: The Robot Show opens next week. B: Sounds interesting. I think I'll go.（现场决定）
  > I'll drive you.（主动提议开车送你）
  > The sun will rise at 6:43 tomorrow.（客观天文事实）
- 正式书面语倾向用 **will**，口语倾向用 **be going to**

### 2. Present Progressive 表示将来 — "已经安排好了"
- 用于有明确时间、已经安排好的个人计划
  > I'm flying to Tokyo next week. I already have a ticket.
- 当主动词是 **go** 时，be going 比 be going to go 更常用
  > He's going home at 2:30.（比 He's going to go home... 更自然）

### 3. Simple Present 表示将来 — "按时刻表走"
- 用于交通工具时刻表、会议日程等固定安排
  > The airship leaves at 9:00 a.m.
  > The conference starts tomorrow morning. It lasts three days.
- 常用动词：begin, start, leave, arrive, last, end

### 4. Future Progressive — "将来某时正在…"
- 强调将来某个时间点动作正在进行
  > At this time tomorrow, I'll be flying to Tokyo.
- 用于礼貌地询问对方计划（比 will 更礼貌）
  > When will you be grading our tests, Professor Lee?
- 用于礼貌地请求帮忙
  > Will you be going by the post office tomorrow? I need some stamps.

### 5. Future Time Clause — "当…的时候，将会…"
- 主句用将来时，时间从句用一般现在时或现在进行时
  > I'll call you **when** the robot **finishes** the laundry.
  > I'll be enjoying dinner **while** he **is dusting**.
- ❌ 时间从句中不能用将来时
  > ~~I'll call you when the robot will finish the laundry.~~
- 时间从句在句首时用逗号，在主句后不用逗号
  > **When** the price drops, more people will buy robots.
  > More people will buy robots **when** the price drops.''',
          keyRules: '''## 核心规则

### 1️⃣ 将来时间的四种表达法
- **be going to**: 已决定的计划 + 有先兆的预测
- **will**: 客观事实 + 临时决定 + 承诺/提议
- **present progressive**: 已安排的将来计划
- **simple present**: 按时刻表发生的将来事件

### 2️⃣ Future Progressive 用法
- 表示将来某一时刻正在进行的动作：At this time tomorrow, I'll be flying to Tokyo.
- 礼貌询问计划：When will you be grading our tests?
- 礼貌请求：Will you be going by the post office?

### 3️⃣ Future Time Clause（将来时间从句）
- 主句用将来时（will / be going to / future progressive）
- 从句用一般现在时或现在进行时
- ❌ 从句不能用 will 或 be going to
- 从句在句首 → 加逗号；在主句后 → 不加逗号

### 4️⃣ Shall 的用法（美国英语）
- 主要用于提议和建议：Shall I pick you up? / Shall we take the bus?''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| You'll be surprised when you **will enter** a classroom. | You'll be surprised when you **enter** a classroom. | 时间从句用一般现在时，不用将来时 |
| I'll see many changes, **when** I return. | **When** I return, I'll see many changes. 或 I'll see many changes when I return. | 时间从句在主句前才加逗号，主句后不加逗号 |
| Look! That robot **will** serve our coffee! | Look! That robot **is going to** serve our coffee! | 有迹象的当下预测用 be going to，不用 will |
| He's **going to go** home. | He's **going** home.（更常用） | 主动词是 go 时，be going 比 be going to go 更自然 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| prediction | n. | 预测 |
| futurist | n. | 未来学家 |
| real estate | n. | 房地产 |
| innovative | adj. | 创新的 |
| creative | adj. | 创造性的 |
| vehicle | n. | 交通工具 |
| challenge | n. | 挑战 |
| opportunity | n. | 机会 |
| schedule | n. | 日程，时刻表 |
| proposal | n. | 提议，提案 |
| guarantee | v. | 保证 |
| progress | n. | 进展，进步 |''',
        ),
        GrammarUnit(
          id: 'unit_6',
          title: 'Unit 6: Future Perfect & Future Perfect Progressive',
          outcomes:
              '''• Describe events that will happen, or be in progress, before a specific time in the future (描述将来某时间之前会完成或持续进行的动作)
• Show the order of two future events using adverbs and expressions with **by** (用副词和 **by** 短语表示两个将来事件的顺序)
• Identify specific information in a business article and a conversation (识别商业文章和对话中的具体信息)
• Discuss future goals and aspirations (讨论将来的目标和志向)
• Write about a classmate's future goals (描写同学的将来目标)''',
          chart: '''## FUTURE PERFECT — 将来完成时

### Statements
| 主语 | Will (not) | Have + Past Participle |
|---|---|---|
| You/He/She/It/We/They | **will (not)** | **have finished** by next week. |

### Yes/No Questions
| Will | 主语 | Have + Past Participle |
|---|---|---|
| **Will** | you/she/they | **have finished** by next week? |

### Short Answers
| 肯定 | 否定 |
|---|---|
| Yes, she/they **will (have)**. | No, she/they **won't (have)**. |

### Wh- Questions
| Wh- Word | Will | 主语 | Have + Past Participle |
|---|---|---|---|
| How much | **will** | you/she/they | **have finished** by next week? |

---

## FUTURE PERFECT PROGRESSIVE — 将来完成进行时

### Statements
| 主语 | Will (not) | Have been + -ing |
|---|---|---|
| You/He/She/It/We/They | **will (not)** | **have been working** for a month. |

### Yes/No Questions
| Will | 主语 | Have been + -ing |
|---|---|---|
| **Will** | you/she/they | **have been working** for a month? |

### Wh- Questions
| Wh- Word | Will | 主语 | Have been + -ing |
|---|---|---|---|
| How long | **will** | you/she/they | **have been working** by then? |''',
          chineseGuide: '''## 中文对比解析

### Future Perfect — "到将来某时，已经…了"
- 强调将来某时间点之前某个动作**已经完成**，关注的是**结果**
- 常与 **by + 时间/事件** 连用
  > By next week, he **will have achieved** his goal.
  > She'll **have started** to sell her new product by May.
  > I'll **have been** in college for a year by then.

### Future Perfect Progressive — "到将来某时，已经一直在…"
- 强调将来某时间点之前某个动作**一直在持续**，关注的是**持续的过程**而非结果
- 动作可能在那个时间点前开始（可能在过去或将来开始）
  > By June next year, he'll **have been selling** computer software for several years.
  > By May, I'll **have been working** for six months.
- ❌ 不能用于非动作动词（状态动词）
  > ~~By June, we'll have been owning our business for five years.~~
  > ✅ By June, we'll **have owned** our business for five years.

### Future Perfect vs. Future Perfect Progressive
| 对比维度 | Future Perfect | Future Perfect Progressive |
|---|---|---|
| 关注点 | 完成（结果） | 持续（过程） |
| 例句 | He'll have saved \$200 by then. | He'll have been saving for two months. |
| 问的问题 | "完成了没有？" | "持续了多久？" |
| 与状态动词 | ✅ 可以 | ❌ 不可以 |

### Time Clause + 将来完成时
- 时间从句用一般现在时，主句用将来完成时
  > **By the time** we **graduate**, you **will have become** a famous inventor.
  > **When** I **finish** my degree, I'll **have been studying** here for four years.
- ❌ 从句不能用 will 或 be going to
  > ~~By the time I'll be twenty, I'll have started my company.~~

### 副词 already / yet 的用法
- **already** 放在 will 和 have 之间
  > I'll **already have finished** by then.
- **yet** 放在句末或 will 与 have 之间
  > I won't have gone to the supermarket **yet**.
  > I will **not yet have taken** the final exam.
- ❌ 副词不能放在主动词和直接宾语之间
  > ~~We will have compiled already our research~~''',
          keyRules: '''## 核心规则

### 1️⃣ Future Perfect 构成与用法
- 构成：**will have + 过去分词**
- 表示"到将来某时间已经做完某事"，关注完成的结果
- 常用 **by + 时间/事件**：By next week, he will have achieved his goal.

### 2️⃣ Future Perfect Progressive 构成与用法
- 构成：**will have been + 现在分词 (-ing)**
- 表示"到将来某时间已经持续做某事"，关注持续的过程
- ❌ 不能与状态动词（know, own, be, have 表拥有等）连用

### 3️⃣ Time Clause 用法
- 时间从句用**一般现在时**，主句用将来完成时
- By the time + 一般现在时从句，主句用 will have done

### 4️⃣ 副词位置
- already → will + already + have done
- yet → 句末 或 will not yet have done
- ❌ 副词不能插在主动词和宾语之间

### 5️⃣ 标点规则
- 时间从句/短语在句首时 + 逗号
- 主句在前时不用逗号''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| He will have **save** \$200 by then. | He will have **saved** \$200 by then. | 将来完成时用过去分词，不用原形 |
| He'll have been **worked** there for two months. | He'll have been **working** there for two months. | 将来完成进行时用 been + -ing，不用过去分词 |
| By the time the year **will be** over, he will have learned a lot. | By the time the year **is** over, he will have learned a lot. | 时间从句用一般现在时，不用将来时 |
| By June, we'll **have been owning** our business for five years. | By June, we'll **have owned** our business for five years. | 拥有（状态动词）不能用进行时态 |
| We will have completed **already** our research. | We will **already have completed** our research. | already 放在 will 和 have 之间，不放在宾语前 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| entrepreneur | n. | 企业家 |
| initiative | n. | 主动性，首创精神 |
| sponsor | n. | 赞助人 |
| affordable | adj. | 负担得起的 |
| convert | v. | 转换 |
| braille | n. | 盲文 |
| corporate | adj. | 公司的，企业的 |
| status | n. | 地位，状态 |
| meanwhile | adv. | 与此同时 |
| achievement | n. | 成就 |
| goal | n. | 目标 |
        | outcome | n. | 结果，成果 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_3',
      title: 'Part 3: 反义疑问句 & 补充表达 (Tag Questions & Additions)',
      units: [
        GrammarUnit(
          id: 'unit_7',
          title: 'Unit 7: Tag Questions — 反义疑问句',
          outcomes:
              '''• Use tag questions to check information or invite agreement（用反义疑问句核实信息或寻求认同）
• Match the tag with the statement's auxiliary verb and subject（让反问尾与陈述句的助动词、主语对应）
• Use positive statements with negative tags, and negative statements with positive tags（掌握正陈述配否定反问尾、否定陈述配肯定反问尾）''',
          chart: '''## TAG QUESTIONS — 反义疑问句

### 基本结构
| 陈述句 | 反问尾 |
|---|---|
| You're from Rio, | **aren't** you? |
| You're not from Rio, | **are** you? |

### With Auxiliary Verbs
| 陈述句 | 反问尾 |
|---|---|
| You're moving, | **aren't** you? |
| He's been here before, | **hasn't** he? |
| They can move tomorrow, | **can't** they? |
| You're not moving, | **are** you? |
| He hasn't been here, | **has** he? |

### With Do as Auxiliary
| 陈述句 | 反问尾 |
|---|---|
| He lives here, | **doesn't** he? |
| They moved last year, | **didn't** they? |
| He doesn't live here, | **does** he? |
| They didn't move, | **did** they? |''',
          chineseGuide: '''## 中文解析

### 反义疑问句 — “……，对吗？”
- 结构：陈述句 + 简短反问尾
- 陈述句肯定 → 反问尾否定 / 陈述句否定 → 反问尾肯定
  > You're Paul Logan, **aren't** you?
  > You're not from Cairo, **are** you?
- 反问尾的动词与陈述句保持一致（be/助动词/情态动词），陈述句无时用 do
  > You've lived here a long time, **haven't** you?
  > You come from London, **don't** you?
- 陈述句有 **never, rarely, seldom** 等否定副词时，反问尾用肯定
  > You've **never** been to Istanbul, **have** you?（不是 haven't you）

### 特殊注意事项
- **I am** 的否定反问用 **aren't I**（不是 amn't I）
  > I'm right, **aren't** I?
- 陈述句主语是名词 → 反问尾用对应代词
  > Tom works here, **doesn't he**?（不是 doesn't Tom）
- this/that → 反问尾用 **it**
  > That's a good idea, **isn't it**?
- there 作主语 → 反问尾也用 **there**
  > There are good schools here, **aren't there**?
  > There's a lot to do, **isn't there**?

### 语调区别
- 升调：真的想确认信息（期待对方回答）
- 降调：只是评论，期待对方同意
  > You're **not** moving, **are** you?↗（确认信息）
  > Seoul is interesting, **isn't** it?↘（评论求认同）''',
          keyRules: '''## 核心规则

### 反义疑问句
- 陈述肯定 + 反问否定 / 陈述否定 + 反问肯定
- 反问尾用陈述句中同样的 be/助动词/情态动词；没有则用 do
- 主语是名词 → 反问尾用代词（Tom → he）
- this/that → 反问尾用 it
- there → 反问尾用 there
- never, rarely, seldom 等否定副词 → 反问尾用肯定''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| The city is beautiful, **isn't the city**? | The city is beautiful, **isn't it**? | 反问尾不用名词，用代词 |
| You have been here since 2016, **aren't you**? | You have been here since 2016, **haven't you**? | 反问尾用与陈述句相同的助动词 |
| **Amn't** I right? | **Aren't** I right? | I 的反问尾用 aren't，不是 amn't |
| You've never been to Istanbul, **haven't you**? | You've never been to Istanbul, **have you**? | never 含否定义，反问用肯定 |
| That's a good idea, **isn't that**? | That's a good idea, **isn't it**? | that → 反问用 it |
| There are good schools here, **isn't there**? | There are good schools here, **aren't there**? | there 作主语 → 反问也用 there（复数用 aren't）|''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| negative | adj. | 否定的，消极的 |
| tag | n. | 附加疑问尾 |
| assumption | n. | 假设，假定 |
| contraction | n. | 缩略形式（如 isn't, don't）|
| originally | adv. | 原本，最初 |
| gorgeous | adj. | 极美的，华丽的 |
| constant | adj. | 持续的，不断的 |
| residential | adj. | 住宅的，居住的 |
| downtown | adv./adj. | 在市中心 |
| vacant | adj. | 空着的，空缺的 |
| supplied | v. | 提供，供应 |
| fascinating | adj. | 迷人的 |''',
        ),
        GrammarUnit(
          id: 'unit_8',
          title:
              'Unit 8: Additions & Responses (So, Too, Neither, Not Either, But)',
          outcomes:
              '''• Show similarity using **so, too, neither, or not either**, and show difference using **but**（用 so/too/neither/not either 表示相似，用 but 表示不同）
• Identify key details in an article on a scientific topic and in a conversation (识别科学文章和对话中的关键细节)
• Discuss similarities and differences between two people (讨论两个人的异同)
• Research a pair of twins and report findings (研究一对双胞胎并报告发现)
• Write about the similarities and differences between two people (描写两个人的异同)''',
          chart: '''## ADDITIONS — 补充表达

### SIMILARITY: So / Neither（倒装）
| 肯定陈述 | 补充（所以…也） |
|---|---|
| Amy **is** a twin, | and **so am I**. |
| She **has** traveled, | and **so have we**. |
| She **can** ski, | and **so can they**. |
| She **likes** dogs, | and **so does** Bill. |

| 否定陈述 | 补充（…也不） |
|---|---|
| Amy **isn't** a twin, | and **neither am I**. |
| She **hasn't** traveled, | and **neither have we**. |
| She **can't** ski, | and **neither can they**. |
| She **doesn't** like dogs, | and **neither does** Bill. |

### SIMILARITY: Too / Not Either（正常语序）
| 肯定陈述 | 补充 |
|---|---|
| Amy is a twin, | and I am **too**. |
| She has traveled, | and we have **too**. |
| She likes dogs, | and Bill does **too**. |

| 否定陈述 | 补充 |
|---|---|
| Amy isn't a twin, | and I'm **not either**. |
| She hasn't traveled, | and we **haven't either**. |
| She doesn't like dogs, | and Bill **doesn't either**. |

### DIFFERENCE: But
| 肯定 + 否定 | 肯定 + 否定 |
|---|---|
| Amy is a twin, | but I'm **not**. |
| She has traveled, | but we **haven't**. |
| She can ski, | but they **can't**. |
| She likes dogs, | but Bill **doesn't**. |

| 否定 + 肯定 | 否定 + 肯定 |
|---|---|
| Amy isn't a twin, | but I **am**. |
| She can't ski, | but they **can**. |
| She hasn't traveled, | but we **have**. |
| She doesn't like dogs, | but Bill **does**. |''',
          chineseGuide: '''## 中文对比解析

### 补充表达是什么
补充表达（Additions）用在陈述句之后，表**相似**（"也一样"）或**不同**（"但是"），避免重复。

---

### 1️⃣ 肯定相似：So（倒装）— 你 20 岁 → and so am I

| 陈述句 | 补充（and so + 动词 + 主语） |
|---|---|
| You **are** 20. | and **so am I**. |
| I **am** a twin. | and **so is** my sister. |
| She **has** traveled. | and **so has** he. |
| They **have** been there. | and **so have** we. |
| He **can** swim. | and **so can** she. |
| You **will** come. | and **so will** they. |
| She **likes** dogs. | and **so does** Bill. |
| They **went** home. | and **so did** we. |

> ❌ ~~and so I am~~（So 必须倒装，动词在主语前）

---

### 2️⃣ 肯定相似：Too（正常语序）— 你 20 岁 → and I am too

| 陈述句 | 补充（and + 主语 + 动词 + too） |
|---|---|
| You **are** 20. | and I **am too**. |
| She **has** traveled. | and we **have too**. |
| He **can** swim. | and she **can too**. |
| She **likes** dogs. | and Bill **does too**. |
| They **went** home. | and we **did too**. |

✅ 正常语序，too 放句末。

---

### 3️⃣ 否定相似：Neither（倒装）— 我不会游泳 → and neither can I

| 否定陈述句 | 补充（and neither + 动词 + 主语） |
|---|---|
| I **am not** ready. | and **neither is** she. |
| She **hasn't** been there. | and **neither have** we. |
| I **can't** swim. | and **neither can** I. |
| He **doesn't** smoke. | and **neither does** she. |
| They **didn't** go. | and **neither did** we. |

> ❌ ~~and neither she is~~（Neither 必须倒装）

---

### 4️⃣ 否定相似：Not Either（正常语序）— 他不会抽烟 → and she doesn't either

| 否定陈述句 | 补充（and + 主语 + 动词 + not + either） |
|---|---|
| I **am not** ready. | and she **isn't either**. |
| She **hasn't** been there. | and we **haven't either**. |
| I **can't** swim. | and I **can't either**. |
| He **doesn't** smoke. | and she **doesn't either**. |
| They **didn't** go. | and we **didn't either**. |

✅ 正常语序，either 放句末。

---

### 5️⃣ 不同：But — "但是…"

| 肯定陈述 → 否定补充 | 否定陈述 → 肯定补充 |
|---|---|
| Amy **is** a twin, but I'm **not**. | Amy **isn't** a twin, but I **am**. |
| She **can** ski, but they **can't**. | She **can't** ski, but they **can**. |
| She **likes** dogs, but Bill **doesn't**. | She **doesn't** like dogs, but Bill **does**. |
| She **has** traveled, but we **haven't**. | She **hasn't** traveled, but we **have**. |

---

### 6️⃣ 动词规则

看陈述句的动词类型，决定补充句用什么动词：

| 陈述句动词 | 补充句动词 | 例句 |
|---|---|---|
| **be** | 也用 be | I'm a twin, and so **is** my cousin. |
| **助动词/情态动词** | 用同样的词 | I can't drive, and **neither can** my twin. |
| **实义动词（无上述）** | **do/does/did** | Bill owns a dog, and **so does** Ed. |

**动词一致性陷阱**：补充句的动词跟**补充句的**主语一致，不是跟陈述句的：
> They've learned Spanish, and **so has she**.（has 跟 she 一致，不是跟 they）
> I wear a lot of jewelry, but my twin **doesn't**.（doesn't 跟 twin 一致）

---

### 7️⃣ As well（口语中替代 Too）

> Mark enjoys fishing, and Gerald does **as well**.
> Mark is a fan of old movies, and Gerald is **as well**.

---

### 8️⃣ 简短回应（对话中表示同意/不同意）

| A 说 | B 回应 |
|---|---|
| I like sports. | **So do I.** / I **do too.** / **Me too!**（口语）|
| I don't like sports. | **Neither do I.** / I **don't either.** / **Me neither.**（口语）|
| I wouldn't like to have a twin. | **(But) I would.** |''',
          keyRules: '''## 核心规则

### 1️⃣ So（肯定相似 + 倒装）
- So + 动词 + 主语：and so am I / so is he / so does she
- ❌ 不倒装：~~and so I am~~

### 2️⃣ Too（肯定相似 + 正常语序）
- 主语 + 动词 + too：I am too / he does too

### 3️⃣ Neither（否定相似 + 倒装）
- Neither + 动词 + 主语：and neither am I / neither does she
- ❌ 不倒装：~~and neither I am~~

### 4️⃣ Not Either（否定相似 + 正常语序）
- 主语 + 动词 + not + either：I'm not either / she doesn't either

### 5️⃣ But（不同）
- 肯定 + 否定：but I'm not / but she doesn't
- 否定 + 肯定：but I am / but she does

### 6️⃣ 动词选择
- 陈述有 be → 用 be
- 陈述有助动词/情态动词 → 用同样的词
- 陈述无上述 → 用 do/does/did
- 动词与补充句主语一致

### 7️⃣ As well（口语）
- 与 too 同义：does as well / is as well

### 8️⃣ 简短回应
- 肯定同意：So do I / I do too / Me too
- 否定同意：Neither do I / I don't either / Me neither
- 不同意：(But) I would / (But) I don't''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| Kim is 5'3", and **so Ann is**. | Kim is 5'3", and **so is Ann**. | so 和 neither 后必须倒装（动词 + 主语）|
| Kim has won several awards, but Ann **didn't**. | Kim has won several awards, but Ann **hasn't**. | 补充用与陈述相同的助动词 |
| I wear a lot of jewelry, but my twin **do not**. | I wear a lot of jewelry, but my twin **doesn't**. | 补充动词与补充主语一致（twin → doesn't）|
| They've learned Spanish, and **so have she**. | They've learned Spanish, and **so has she**. | has 与 she 一致，不是与 they |
| A: I like sports. B: **So I do.** | A: I like sports. B: **So do I.** | 简短回应也要倒装 |
| A: I don't like sports. B: **Me too.** | A: I don't like sports. B: **Me neither.** / **Neither do I.** | 否定回应用 Me neither，不是 Me too |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| addition | n. | 补充（表达）|
| similarity | n. | 相似之处 |
| identical | adj. | 完全相同的 |
| twin | n. | 双胞胎之一 |
| heredity | n. | 遗传 |
| environment | n. | 环境 |
| nurture | n. | 养育，后天培养 |
| genetics | n. | 遗传学 |
| factor | n. | 因素 |
| outgoing | adj. | 外向的 |
| reserved | adj. | 内向的，含蓄的 |
| complex | adj. | 复杂的 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_4',
      title:
          'Part 4: 动名词、不定式 & 使役动词、短语动词 (Gerunds, Infinitives, Causatives & Phrasal Verbs)',
      units: [
        GrammarUnit(
          id: 'unit_9',
          title: 'Unit 9: Gerunds & Infinitives',
          outcomes:
              '''• Discuss activities or make general statements using gerunds or infinitives (用动名词或不定式讨论活动、做一般性陈述)
• Explain the purpose of an action using an infinitive (用不定式解释一个动作的目的)
• Identify key details in a social science article and in a conversation (识别社会科学文章和对话中的关键细节)
• Discuss food and fast-food restaurants (讨论食物和快餐店)
• Write about the food at one's school, expressing one's opinion (描写学校的食物，表达个人观点)''',
          chart: '''## GERUNDS & INFINITIVES — 动名词与不定式

### Verb + Gerund
| 动词 | 例句 |
|---|---|
| **avoid, consider, discuss, dislike, enjoy, recommend, suggest** | My brother **avoids eating** fried food. |
|  | Many people **enjoy eating** fast food. |
| **go + gerund** | People eat fast food when they **go shopping**. |

### Verb + Infinitive
| 模式 | 例句 |
|---|---|
| verb + infinitive | They **agreed to cook** with less fat. |
| verb + object + infinitive | I **encouraged them to buy** the special. |
| verb + infinitive or verb + object + infinitive | I **wanted to try** that restaurant. / I **wanted** my sister **to try** it. |

### Verb + Gerund or Infinitive (Same Meaning)
| 动词 | 动名词 | 不定式 |
|---|---|---|
| **begin, continue, hate, love, start** | I **love cooking**. | I **love to cook**. |

### Verb + Gerund or Infinitive (Different Meaning)
| 动词 | 动名词含义 | 不定式含义 |
|---|---|---|
| **stop** | Stop eating pizza（不再吃）| Stop to eat pizza（停下来去吃）|
| **remember** | Remember meeting her（记得见过她）| Remember to meet her（记得要去见她）|
| **forget** | I never forgot eating there（没忘记在那里吃过）| I never forgot to eat lunch（从没忘记吃午饭）|

### Preposition/Phrasal Verb + Gerund
| 模式 | 例句 |
|---|---|
| **verb + preposition + gerund** | I don't **approve of eating** fast food every day. |
| **adjective + preposition + gerund** | We're **interested in trying** different foods. |
| **look forward to / be opposed to + gerund** | We **look forward to having** dinner with you. |

### Infinitive of Purpose
A: Why does he order fast food? B: **To save** time.

### Gerund as Subject / It + Infinitive
| 动名词主语 | It + 不定式 |
|---|---|
| **Cooking** is fun. | **It's fun to cook**. |''',
          chineseGuide: '''## 中文对比解析

### 1. 动名词 (Gerund = V-ing 作名词)
- 跟在某些动词后作宾语：**avoid, consider, enjoy, suggest, recommend** 等
  > I suggest **making** changes in the cafeteria food.
- 跟在介词后面（动词 + 介词 / 形容词 + 介词）
  > I read an article **about counting** calories.
  > We're **interested in trying** different foods.
- 特别注意：**look forward to, be opposed to, object to** 中的 to 是介词，后面跟动名词，不是不定式
  > I **look forward to having** dinner with you.（不是 ~~look forward to have~~）

### 2. 不定式 (Infinitive = to + 动词原形)
- 跟在某些动词后：**agree, decide, hope, want, need** 等
  > They **agreed to cook** with less fat.
- 跟在某些形容词后：**afraid, curious, eager, easy, glad, possible** 等
  > It's **easy for students to eat** fast food.
- 跟在某些名词后：**chance, decision, offer, reason, right, time** 等
  > She has the **right to eat** what she wants.
- **不定式表目的**：回答 Why 的问题
  > He does it **to save time**. → Why? **To lose weight.**

### 3. Stop / Remember / Forget 的关键区别
最容易错的一组词，同一个动词后跟动名词 vs 不定式，意思完全不同：
- **stop + doing** = 停下来不做了 / **stop + to do** = 停下来去做另一件事
- **remember + doing** = 记得做过 / **remember + to do** = 记得要去做
- **forget + doing** = 忘记做过 / **forget + to do** = 忘记要去做

### 4. 动名词作主语 vs It + 不定式
意思一样，只是结构不同：
> **Cooking** is fun. = **It's** fun **to cook**.

### 5. 平行结构（写作重点）
当两个以上动词跟在同一个动词后时，必须保持形式一致：
> I love **walking and doing** yoga.（两个都是动名词）
> I love **to walk and to do** yoga.（两个都是不定式）
> ❌ I love walking and **to do** yoga.（混用错误）''',
          keyRules: '''## 核心规则

### 1️⃣ 动词 + 动名词
- 常见动词：avoid, consider, discuss, dislike, enjoy, recommend, suggest, mind, practice, finish
- go + gerund：go shopping / swimming / fishing / skiing

### 2️⃣ 动词 + 不定式
- 三种模式：verb + inf / verb + object + inf / verb + 两者皆可
- 常见：agree, decide, hope, want, need, plan, expect, promise
- 不定式否定：**not + to + 动词原形**

### 3️⃣ 介词 + 动名词
- 介词后面**只能**跟动名词，不能跟不定式
- 含 to 的介词短语：look forward to, be opposed to, object to → 后面也用动名词

### 4️⃣ Stop / Remember / Forget
- 动名词 ≠ 不定式，含义完全不同
- 动名词：已做过的动作
- 不定式：未做的动作

### 5️⃣ 平行结构
- 并列动词必须保持同一种形式（都是动名词或都是不定式）
- 不能混用''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| I suggest **to make** changes. | I suggest **making** changes. | suggest 后跟动名词，不是不定式 |
| I object **to eat** so much. | I object **to eating** so much. | to 是介词，后跟动名词 |
| I ended up **to gain** weight. | I ended up **gaining** weight. | phrasal verb + gerund |
| Continue providing **and to serve**. | Continue providing **and serving**. | 平行结构，形式一致 |
| I love **walking and to do** yoga. | I love **walking and doing** yoga. | 不能混用动名词和不定式 |
| We look forward **to have** dinner. | We look forward **to having** dinner. | look forward to 的 to 是介词 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| gerund | n. | 动名词 |
| infinitive | n. | 不定式 |
| objection | n. | 反对，异议 |
| appeal | v. | 吸引，有吸引力 |
| consequence | n. | 后果 |
| convenience | n. | 便利，方便 |
| globe | n. | 全球 |
| reliability | n. | 可靠性 |
| nutrition | n. | 营养 |
| consume | v. | 消费，消耗 |
| obesity | n. | 肥胖 |
| parallel | adj. | 平行的；并列的 |''',
        ),
        GrammarUnit(
          id: 'unit_10',
          title: 'Unit 10: Make, Have, Let, Help & Get',
          outcomes:
              '''• Describe how someone forces, causes, persuades, or allows someone else to do things (描述某人强迫、促使、说服或允许他人做某事)
• Describe how someone makes things easier for someone else (描述某人如何让某事对他/她人更容易)
• Identify key information in an opinion article and in a conversation (识别观点文章和对话中的关键信息)
• Describe how someone has influenced one's life (描述某人如何影响了自己的生活)
• Write about keeping animals in captivity (描写圈养动物)''',
          chart: '''## MAKE, HAVE, LET, HELP & GET — 使役动词

| 动词 | 模式 | 含义 | 例句 |
|---|---|---|---|
| **Make** | make + object + **base form** | 强迫（无选择）| The trainer **made** the elephant **perform**. |
| **Have** | have + object + **base form** | 安排/让（有选择）| Some people **have** their pets **do** tricks. |
| **Let** | let + object + **base form** | 允许 | The teacher **let** us **leave** early. |
| **Help** | help + object + **base form** OR **infinitive** | 帮助（两种皆可）| She **helped** me **do** / **to do** the homework. |
| **Get** | get + object + **infinitive** | 说服（有选择）| Jan **got** her parents **to take** her to the zoo. |

### Make + Object + Adjective
| 结构 | 例句 |
|---|---|
| make + object + adjective | Cruel treatment of animals **makes** me **angry**. |''',
          chineseGuide: '''## 中文对比解析

这五个动词都表示"让/使别人做某事"，但**强制性递减**：

### 强迫 vs 允许 vs 说服

| 动词 | 强制程度 | 中文理解 |
|---|---|---|
| **Make** | ⭐⭐⭐ 无选择 | 强迫 / 迫使 → The trainer **made** the elephant perform. |
| **Get** | ⭐⭐ 有选择 | 说服 / 劝说 → Jan **got** her parents to take her. |
| **Have** | ⭐⭐ 有选择 | 安排 / 让 → The teacher **had** us do research. |
| **Let** | ⭐ 完全有选择 | 允许 → The teacher **let** us leave early. |
| **Help** | ⭐ 主动帮助 | 帮助（使更容易）→ She **helped** me (to) do the homework. |

### 结构关键区别
- **Make / Have / Let** → 后面跟**动词原形**（不带 to）
  > make the elephant **perform** / have them **leave** / let people **take photos**
  > ❌ ~~make the elephant to perform~~ / ~~let people to take photos~~
- **Get** → 后面跟**不定式**（带 to）
  > get a dolphin **to wear** a collar
  > ❌ ~~get a dolphin wear~~ / ~~get a dolphin wearing~~
- **Help** → 两种都可以：help me **do** / help me **to do**（含义相同）

### Make 的特殊用法
- make + 宾语 + **形容词**：表示"让…感到…"
  > Cruel treatment of animals **makes** me **angry**.（让我生气）
  > The monkeys always **make** me **laugh**.（让我笑）''',
          keyRules: '''## 核心规则

### 1️⃣ Make — 强迫（无选择）
- make + object + **base form**
- ❌ 不加 to

### 2️⃣ Have — 安排/让（有选择）
- have + object + **base form**
- ❌ 不加 to

### 3️⃣ Let — 允许
- let + object + **base form**
- ❌ 不加 to

### 4️⃣ Help — 帮助
- help + object + **base form** 或 **infinitive**（皆可）

### 5️⃣ Get — 说服（有选择）
- get + object + **infinitive**（带 to）
- ❌ 不能跟 base form

### 6️⃣ Make + Adjective
- make + object + adjective：The story made me sad.''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| Let people **to take** photos. | Let people **take** photos. | let 后跟动词原形，不加 to |
| Get a dolphin **wear** a collar. | Get a dolphin **to wear** a collar. | get 后必须跟不定式（带 to）|
| The trainer **made** the elephant **to perform**. | The trainer **made** the elephant **perform**. | make 后跟动词原形，不加 to |
| **Let** is always + base form |  | **Let** 和 **Make** 跟 **Have** 一样，后跟动词原形 |
| **Get** is always + infinitive |  | **Get** 是这五个中唯一必须跟不定式的 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| cause | v. | 导致，引起 |
| persuade | v. | 说服 |
| allow | v. | 允许 |
| force | v. | 强迫 |
| interact | v. | 互动，交流 |
| captivity | n. | 圈养，囚禁 |
| treatment | n. | 对待，待遇 |
| audience | n. | 观众 |
| trainer | n. | 训练师 |
| trick | n. | 把戏，技巧 |
| perform | v. | 表演 |
| assignment | n. | 作业，任务 |''',
        ),
        GrammarUnit(
          id: 'unit_11',
          title: 'Unit 11: Phrasal Verbs',
          outcomes:
              '''• Use phrasal verbs correctly in conversation and writing (在口语和写作中正确使用短语动词)
• Distinguish between separable, inseparable, and intransitive phrasal verbs (区分可分、不可分和不及物短语动词)
• Identify key details in an article about telemarketing (识别关于电话销售文章中的关键细节)
• Discuss junk mail and telephone sales tactics (讨论垃圾邮件和电话销售策略)
• Write about a telephone experience using phrasal verbs (用短语动词描写一次电话经历)''',
          chart: '''## PHRASAL VERBS — 短语动词

### Separable Transitive (可分及物)
| 短语动词 | 含义 | 例句 |
|---|---|---|
| **pick up** | 接起 / 学会 | She **picked up** the phone. / She **picked** the phone **up**. |
| **turn down** | 调低 / 拒绝 | Please **turn down** the radio. / Please **turn** it **down**. |
| **fill out** | 填写 | I **filled out** the form. / I **filled** it **out**. |
| **throw out** | 扔掉 | I **threw out** my junk mail. / I **threw** it **out**. |
| **write down** | 记下 | **Write down** the date. / **Write** it **down**. |

> ⚠️ 代词宾语**必须**放在动词和 particle 之间：pick **it** up（不是 pick up it）

### Inseparable Transitive (不可分及物)
| 短语动词 | 含义 | 例句 |
|---|---|---|
| **run into** | 偶然遇见 | I **ran into** Ed at work.（不是 ran Ed into）|
| **get over** | 克服 / 恢复 | He **got over** the illness. |
| **count on** | 依赖 | You can **count on** me. |
| **look after** | 照顾 | She **looks after** her grandmother. |
| **settle on** | 选定 | Think before you **settle on** it.（不是 settle it on）|

### Intransitive (不及物)
| 短语动词 | 含义 | 例句 |
|---|---|---|
| **catch on** | 流行 | The trend **caught on**. |
| **show up** | 出现 | He **showed up** late. |
| **sign up** | 注册 | She **signed up** last month. |
| **come in** | 进来 | Please **come in**. |
| **call back** | 回电 | He **called back** later. |

### Phrasal Verb + Preposition
| 短语动词 | 含义 | 例句 |
|---|---|---|
| **hang up on** | 挂断…的电话 | She **hung up on** the caller. |
| **come up with** | 想出 | They **came up with** this idea. |
| **put up with** | 忍受 | I can't **put up with** this noise. |
| **get along with** | 与…相处 | He **gets along with** everyone. |''',
          chineseGuide: '''## 中文对比解析

### 什么是 Phrasal Verb？
短语动词 = **动词 + particle（小品词）**。Particle 可以是 in, out, up, down, off, on 等。

> ⚠️ Particle 不等于介词（preposition）。Particle **改变动词的含义**，而介词不改变。
> - I **looked up** and saw a bird.（往上看了 → up 是副词/介词，没改变 look 的本意）
> - I **looked up** his number.（查找 → up 是 particle，改变了 look 的含义）

### 三类短语动词

**1. 可分及物 (Separable Transitive)**
- 名词宾语可以放在 particle 前或后
- 代词宾语**必须**放在中间
  > I **took off** my coat. = I **took** my coat **off**.
  > I **took it off**.（不能说 ~~took off it~~）

**2. 不可分及物 (Inseparable Transitive)**
- 名词和代词宾语都必须放在 particle 后面
  > I **ran into** Ed. / I **ran into** him.
  > ❌ ~~I ran Ed into.~~ / ~~I ran him into.~~

**3. 不及物 (Intransitive)**
- 不接宾语，verb + particle 始终不分开
  > The trend **caught on**. / Please **come in**.
  > ❌ ~~caught on the trend~~（不能说）

### 短语动词 vs 正式动词
短语动词多用于日常口语，正式场合用对应的单个动词：
- **less formal（口语）**: I **turned down** their offer.
- **more formal（书面）**: I **rejected** their offer.
- **less formal**: They **set up** Do Not Call lists.
- **more formal**: They **established** Do Not Call lists.

### 小心：同一个短语动词可能有多个含义
> Please **turn down** the radio.（调低音量）
> I **turn down** all telemarketing offers.（拒绝）
> We **handed in** our homework.（上交）
> The teacher **handed out** our next assignment.（分发）''',
          keyRules: '''## 核心规则

### 1️⃣ 可分及物 (Separable)
- 名词：pick up the phone / pick the phone up（两种皆可）
- 代词：pick **it** up（必须放中间）
- 长名词短语：不分开（~~filled the form from... out~~）

### 2️⃣ 不可分及物 (Inseparable)
- 名词和代词都放 particle 后
- run into him / look after her / count on me

### 3️⃣ 不及物 (Intransitive)
- 不接宾语，不分开
- show up / catch on / sign up

### 4️⃣ 正式 vs 非正式
- 口语：用短语动词（turn down）
- 正式：用单个动词（reject）

### 5️⃣ 短语动词 + 介词
- 有些短语动词包含两个小品词（up with, up on）
- 宾语始终在最后：come up with an idea''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| I **picked up it**. | I **picked it up**. | 代词宾语必须放在动词和 particle 中间 |
| I **ran him into** at work. | I **ran into him** at work. | 不可分短语动词的代词宾语放在 particle 后 |
| I **settle it on**. | I **settle on it**. | 不可分短语动词不能分开 |
| He **got yesterday back**. | He **got back** yesterday. | 不及物短语动词不能分开 |
| I turned **out** the radio. | I turned **down** the radio. | 用错 particle 会改变意思 |
| I **looked up** at the sky. | ← 这里的 up 是副词/介词，不是 particle | Particle 改变动词含义，介词不改变 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| phrasal verb | n. | 短语动词 |
| particle | n. | 小品词（up/down/off/on 等）|
| separable | adj. | 可分开的 |
| inseparable | adj. | 不可分开的 |
| transitive | adj. | 及物的 |
| intransitive | adj. | 不及物的 |
| telemarketing | n. | 电话销售 |
| hang up | v. | 挂断电话 |
| figure out | v. | 弄明白 |
| find out | v. | 查明，发现 |
| set up | v. | 建立，设立 |
| sign up | v. | 注册，报名 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_5',
      title: 'Part 5: 形容词从句 (Adjective Clauses)',
      units: [
        GrammarUnit(
          id: 'unit_12',
          title:
              'Unit 12: Adjective Clauses with Subject Relative Pronouns (who, which, that, whose)',
          outcomes:
              '''• Identify or give additional information about people, places, or things using adjective clauses with correct subject relative pronouns (用正确的主语关系代词识别或补充人/物/地点的信息)
• Identify personality types in a psychology article and in a conversation (识别心理学文章和对话中的人格类型)
• Take a personality quiz and discuss the results (做人格测试并讨论结果)
• Write about the qualities of a good friend (描写好朋友的品质)''',
          chart: '''## ADJECTIVE CLAUSES WITH SUBJECT RELATIVE PRONOUNS

### After the Main Clause
| 名词/代词 | 关系代词 | 动词 | 功能 |
|---|---|---|---|
| a book | **that / which** | discusses... | 指物 |
| an introvert | **that / who** | needs... | 指人 |
| a friend | **whose** personality | is... | 所属关系 |

### Inside the Main Clause
| 名词 | 从句 | 主句剩余 |
|---|---|---|
| The book **that/which** | discusses personality | is by Rubin. |
| Someone **who** | needs time alone | may be an introvert. |
| Ana, **whose** personality | is like mine, | loves parties. |

### Subject Relative Pronouns
| 指代 | 关系代词 | 正式程度 |
|---|---|---|
| People | **who** / **that** | who 更正式, that 更口语化 |
| Places/Things | **which** / **that** | which 更正式, that 更口语化 |
| Possession | **whose** + noun | 人/物皆可用 |

### Identifying vs Nonidentifying
| 类型 | 功能 | 逗号 | 可用 that? | 例句 |
|---|---|---|---|---|
| **Identifying** | 必要信息，用于识别 | 无逗号 | ✅ 可用 | My friend **who lives in Chicago** visits me. |
| **Nonidentifying** | 额外补充信息，非必要 | ⚠️ 加逗号 | ❌ 不可用 | Bill Gates, **who is a well-known introvert**, founded Microsoft. |

### 动词一致性
- 关系代词作主语时，动词与先行词一致：Ben is my friend who **lives** in Boston.
- whose + noun 作主语时，动词与 whose 后的名词一致：Ed is a man whose friends **are** like family. (friends → are)''',
          chineseGuide: '''## 中文对比解析

### 什么是形容词从句？
形容词从句 = 关系代词（who/which/that/whose）引导的从句，跟在名词后面，用来**识别**或**补充说明**这个名词。

> I have a classmate **who is an extrovert**.
> 我有个同学，他性格外向。（从句 who is an extrovert 补充说明是什么样同学）

### 关系代词的选择
| 先行词 | 关系代词 | 例子 |
|---|---|---|
| 人 | **who / that** | I have a friend **who/that** loves spending time alone. |
| 物/地点 | **which / that** | There's a meeting **which/that** starts at 10:00. |
| 所属关系 | **whose** | My friend has a son **whose** name is Max. |

- 口语中 **that** 用得最多，是中性非正式选择
- 正式文体倾向用 **who**（人）和 **which**（物）
- **whose** 不仅用于人，也可用于物：I work at a company **whose** offices are in London.

### Identifying vs Nonidentifying — 有无逗号，意思完全不同

| 有逗号吗？ | 功能 | 含义 |
|---|---|---|
| My friends **who are extroverts** love parties. | 无逗号 = 必要识别 | 朋友中有外向的，其中那些外向的爱派对 |
| My friends **, who are extroverts,** love parties. | 有逗号 = 补充说明 | 所有朋友都外向，他们都爱派对 |

写作规则：
- **Identifying**（无逗号）：不分开，紧跟在名词后
- **Nonidentifying**（有逗号）：不可以用 that，人用 who，物用 which

### 容易犯的错
- ❌ 关系代词和主语代词重复：Scott is someone who **he** enjoys parties.
- ❌ 漏掉关系代词：Sarah is another person **~~has fun~~** at parties.（缺 who）
- ❌ 非识别性从句用 that：~~Ed, that introduced us at the party, called me.~~ → who
- ❌ 从句与名词分离：~~My friend seldom calls me who lives in Berlin.~~（who lives... 得紧跟 friend）

### 动词一致性
关系代词作主语时，动词的数取决于**先行词**（被修饰的名词）：
> Ben is my friend who **lives** in Boston.（单数 friend → lives）
> Al and Ed are my friends who **live** in Boston.（复数 friends → live）''',
          keyRules: '''## 核心规则

### 1️⃣ 主语关系代词
- 人：who / that
- 物/地方：which / that
- 所属：whose + noun

### 2️⃣ Identifying 从句
- 必要信息，无逗号
- 可用 that
- 不能省略关系代词（因为它是主语）

### 3️⃣ Nonidentifying 从句
- 补充信息，加逗号
- ❌ 不可用 that（用 who 或 which）
- 口语中停顿（PAUSE）代替逗号

### 4️⃣ 动词一致性
- 关系代词作主语 → 动词与先行词一致
- whose + noun 作主语 → 动词与 whose 后的名词一致

### 5️⃣ 常见禁忌
- ❌ 不重复主语代词（who he）
- ❌ 不省略主语关系代词
- ❌ 不让从句远离先行词''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| Scott is someone who **he** enjoys parties. | Scott is someone who enjoys parties. | 关系代词和主语代词不重复 |
| Sarah is another person **has fun** at parties. | Sarah is another person **who** has fun at parties. | 不能省略主语关系代词 |
| Ed, **that** introduced us, called me. | Ed, **who** introduced us, called me. | 非识别性从句不用 that |
| My friend seldom calls me who lives in Berlin. | My friend who lives in Berlin seldom calls me. | 从句紧跟在所修饰名词后 |
| Ed is a man whose friends **is** like family. | Ed is a man whose friends **are** like family. | whose + noun 作主语，动词与其一致 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| adjective clause | n. | 形容词从句 |
| relative pronoun | n. | 关系代词 |
| identify | v. | 识别 |
| introvert | n. | 内向的人 |
| extrovert | n. | 外向的人 |
| personality | n. | 人格，个性 |
| quality | n. | 品质 |
| relationship | n. | 关系 |
| additional | adj. | 额外的，附加的 |
| essential | adj. | 必要的 |
| modify | v. | 修饰 |''',
        ),
        GrammarUnit(
          id: 'unit_13',
          title:
              'Unit 13: Adjective Clauses with Object Relative Pronouns & Where/When',
          outcomes:
              '''• Identify or give additional information about people, places, or things using adjective clauses with correct object relative pronouns and where/when (用正确的宾语关系代词及 where/when 识别或补充信息)
• Identify key details in an online book review and in a conversation (识别在线书评和对话中的关键细节)
• Describe your hometown or city (描述你的家乡或城市)
• Write about a memorable place in a person's life (描写人一生中难忘的地方)''',
          chart: '''## ADJECTIVE CLAUSES WITH OBJECT RELATIVE PRONOUNS

### Object Relative Pronouns (whom, who, that, which)
| 主句 | 形容词从句 | 说明 |
|---|---|---|
| He read the book | **(that/which)** I read. | 物→宾语，可省略 |
| She is someone | **(who/whom)** I respect. | 人→宾语，可省略 |
| That is the author | **whose** book I read. | 所属，不可省略 |

### 宾语关系代词的特点
- 关系代词在从句中作**宾语**（不是主语）
- **可以省略**（在非正式/口语中）：The book **(that)** I read is great.
- 人用 **whom**（正式）/ **who**（口语）/ **that** / 省略
- 物用 **which** / **that** / 省略

### Where / When
| 先行词 | 关系词 | 例句 |
|---|---|---|
| Place | **where** | She loves the city **where** she grew up. |
| Time | **(when)** | They cried the day **(when)** they left. |

### 介词 + Whom / Which
| 正式 | 较口语化 |
|---|---|
| He's the writer **for whom** I work. | He's the writer **(whom)** I work **for**. |
| The essay **about which** we talked | The essay **(which)** we talked **about** |''',
          chineseGuide: '''## 中文对比解析

### 主语关系代词 vs 宾语关系代词
上一课学的是**主语关系代词**（who/which/that 在从句中作主语）：
> I have a friend **who lives in Boston**.（who 是 lives 的主语）

本课学的是**宾语关系代词**（whom/who/that/which 在从句中作宾语）：
> She's the woman **(whom)** I admire.（whom 是 admire 的宾语 → 我钦佩她）

### 关键区别：宾语关系代词**可以省略**
> The book **(that/which)** I read is great. → The book **~~that~~** I read is great.
> She's someone **(who/whom)** I respect. → She's someone **~~whom~~** I respect.
这是因为主语不能省（否则从句缺主语），但宾语可以省。

### Whom — 什么时候用？
- **whom** 是正式英语，日常口语很少用
- 正式写作/考试中用 whom → The candidate **whom** we hired...
- 日常口语用 who/that 或直接省略 → The person **(who)** I met...
- 介词紧跟 whom 时必须用 whom：**For whom** do you work?（正式）

### Where / When 代替关系代词
- **where** 代替 in which / at which → the city **where** she grew up
- **when** 代替 on which → the day **when** they left
- when 在非正式口语中可省略：the day **(when)** they left

### 介词位置
- **正式**：介词 + whom/which → He's the writer **for whom** I work.
- **口语**：whom 可省，介词放句末 → He's the writer **~~whom~~** I work **for**.

### ⚠️ 不要重复宾语代词
> ❌ She's someone whom I admire **her**.
> ✅ She's someone **(whom)** I admire.''',
          keyRules: '''## 核心规则

### 1️⃣ 宾语关系代词
- 人：whom（正式）/ who（口语）/ that / 省略
- 物：which / that / 省略
- 所属：whose（不可省略）

### 2️⃣ 能否省略？
- 主语关系代词：❌ 不能省略
- 宾语关系代词：✅ 可以省略（口语中常省略）

### 3️⃣ Where / When
- where = in/at which（地点）
- when = on/in which（时间，可省略）

### 4️⃣ 介词位置
- 正式：介词 + whom/which
- 口语：介词放句末，whom/which 可省略

### 5️⃣ 不重复代词
- ❌ ~~the person whom I admire him~~ → the person (whom) I admire''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| She's someone whom I admire **her**. | She's someone **(whom)** I admire. | 不重复宾语代词 |
| The book which I read it is great. | The book **(which)** I read is great. | 不重复宾语 |
| He's the writer **whom** I work **for whom**. | He's the writer **(whom)** I work for. | 介词放句末时不重复 whom |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| object relative pronoun | n. | 宾语关系代词 |
| omit | v. | 省略 |
| respect | v. | 尊敬 |
| admire | v. | 钦佩，欣赏 |
| immigrant | n. | 移民 |
| childhood | n. | 童年 |
| neighborhood | n. | 社区，邻居 |
| memorable | adj. | 难忘的 |
| identify | v. | 识别 |
| additional | adj. | 额外的 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_6',
      title: 'Part 6: 情态动词 (Modals & Similar Expressions)',
      units: [
        GrammarUnit(
          id: 'unit_14',
          title: 'Unit 14: Modals & Similar Expressions',
          outcomes:
              '''• Express ability, possibility, advice, necessity, prohibition, conclusions, or future possibility with a range of modals (用情态动词表达能力、可能性、建议、必要性、禁止、结论和将来可能性)
• Identify key information in a social science article (识别社会科学文章中的关键信息)
• Discuss social networking, giving opinions (讨论社交网络并表达观点)
• Write a blog entry about one's plans for the near future (写一篇关于近期计划的博客)''',
          chart: '''## MODALS — 情态动词总览

### 能力 / 可能性 — Can / Could / Be able to
| 时态 | 形式 | 例句 |
|---|---|---|
| 现在 | can / be able to | She **can** speak French. |
| 过去 | could / was able to | Before lessons, she **could** speak French. |
| 将来 | will be able to | She'll **be able to** register tomorrow. |

### 建议 — Should / Ought to / Had better
| 情态动词 | 语气强度 | 例句 |
|---|---|---|
| **should** | 一般建议（最常用）| You **should** watch Survivor tonight. |
| **ought to** | 一般建议（不太常用）| Terri **ought to** watch it, too. |
| **had better** | 紧急建议（否则有坏结果）| You'd **better** spend less time online. |
| **had better not** | 否定建议（同等级）| You'd **better not** stay up too late. |

### 必要性 — Have to / Have got to / Must
| 情态动词 | 特点 | 例句 |
|---|---|---|
| **have to** | 客观需要 | I **have to** get a new email address. |
| **have got to** | 口语、强烈感情 | You've **got to** see this cartoon! |
| **must** | 权力者强调 / 书面指引 | You **must** be 13+ to join. |
| **don't have to** | 不必要（≠ must not）| You **don't have to** reply. |

### 禁止 — Must not / Can't
- **must not**：绝对不能
- **can't**：不允许

### 结论 — May / Might / Could / Must / Can't
| 确定性 | 情态动词 | 含义 |
|---|---|---|
| 不确定 | **may / might / could** | 可能（有可能但不肯定）|
| 几乎确定 | **must / have to** | 一定是 |
| 不可能 | **can't** | 不可能是 |

### 将来可能性 — May / Might / Could
| 例句 |
|---|
| I **may** join. / Sean **might** join, too. |
| It **could** be the best site. |''',
          chineseGuide: '''## 中文对比解析

### 情态动词的核心特点
- 情态动词只有**一种形式**，第三人称单数不加 -s
  > She **might** post photos.（不是 ~~mights~~ / ~~might to post~~）
- 所有情态动词后面跟**动词原形**
  > You **should study** this weekend.（不是 ~~should studies~~）

### 建议的三级强度
- **should**：一般建议（最常用）→ You should watch this movie.
- **ought to**：同 should，较少用 → You ought to watch it, too.
- **had better**：紧急建议（不做会出问题）→ You'd better study or you'll fail.
- 否定建议：**shouldn't** / **had better not**

### Don't have to ≠ Must not
- **don't have to** = 不必（没这个必要，但不是禁止）
  > I **don't have to** work on Monday. It's a holiday.
- **must not** = 绝对不能（禁止）
  > You **must not** give anyone your password.

### 表达结论的确定性程度
从最不确定到最确定：
> might → may → could → must → can't
> 可能（不太确定）→ 可能（一般）→ 可能（较确定）→ 一定是 → 不可能是

### Can vs Be able to
- **can** 在日常表达能力时更常见
- **be able to** 可用于各种时态（will be able to, have been able to）

### Must 的使用场景
- 口语中带权力色彩：You **must** go to bed right now!（妈妈对孩子说）
- 书面语：You **must** be at least 13 to join.（网站指引）''',
          keyRules: '''## 核心规则

### 1️⃣ 情态动词形式
- 不加 -s，后面跟动词原形
- 只有一种形式，不随人称变化

### 2️⃣ 主要功能
- 能力：can / could / be able to
- 建议：should / ought to / had better
- 必要：have to / have got to / must
- 禁止：must not / can't
- 结论：may / might / could / must / can't
- 将来可能：may / might / could

### 3️⃣ Don't have to ≠ Must not
- don't have to = 不必
- must not = 禁止

### 4️⃣ Had better
- 用于紧急建议（不做会出问题）
- 否定：had better not''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| She **should studies** this weekend. | She **should study** this weekend. | 情态动词后跟动词原形，不加 -s |
| You **must not work** on Monday. | You **don't have to** work on Monday. | must not = 禁止；don't have to = 不必 |
| She **might to post** photos. | She **might post** photos. | 情态动词后面不加 to |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| modal | n. | 情态动词 |
| ability | n. | 能力 |
| possibility | n. | 可能性 |
| necessity | n. | 必要性 |
| prohibition | n. | 禁止 |
| conclusion | n. | 结论 |
| advice | n. | 建议 |
| urgent | adj. | 紧急的 |
| register | v. | 注册 |
| password | n. | 密码 |''',
        ),
        GrammarUnit(
          id: 'unit_15',
          title:
              'Unit 15: Advisability in the Past (Should Have, Could Have, Might Have)',
          outcomes:
              '''• Express past advisability, regret, or criticism with past modals (用过去情态动词表达过去的可取做法、后悔或批评)
• Identify people's opinions in a psychology article (识别心理学文章中人们的观点)
• Discuss past situations and decide what people should or should not have done (讨论过去的情况，判断别人应该或不应该做什么)
• Write about a past problem and what one should or should not have done (描写一个过去的问题及该怎么做)''',
          chart: '''## ADVISABILITY IN THE PAST — 过去本该如何

| 情态动词 | 含义 | 例句 |
|---|---|---|
| **should have + 过去分词**（最常用）| 过去应该做的事（但没做）| I **should have applied** to college. |
| **ought to have + 过去分词**（较少用）| 同上 | He **ought to have studied** more. |
| **could have + 过去分词** | 过去本可以做的事（但没做）| We **could have gone** to a better school. |
| **might have + 过去分词** | 过去可能应该做的事 | He **might have asked** for help. |

| 否定形式 | 含义 | 例句 |
|---|---|---|
| **should not have / shouldn't have** | 过去不该做的事（做了）| He **shouldn't have gone** to the party. |
| **ought not to have**（很少用）| 同上 | He **ought not to have left** so late. |

| 问句 | 例句 |
|---|---|
| Yes/No 问句 | **Should** he **have told** her? |
| Wh- 问句 | When **should** he **have told** her? |
| 简短回答 | Yes, he **should have**. / No, he **shouldn't have**. |

> ⚠️ 简短回答必须说 **should have**，不能只说 ~~Yes, he should.~~''',
          chineseGuide: '''## 中文对比解析

### 过去情态动词的核心用法
表达对过去事情的**后悔**或**批评**，通常翻译为"本应该…"、"本可以…"。

### 人称不同，语气不同

| 主语 | 语气 | 例句 |
|---|---|---|
| **I / we** | 后悔（对自己）| I **should have applied** to college.（我后悔没申请）|
| **you / she / he / they** | 批评（对别人）| You **could have called** us. We waited for hours.（你应该打电话的）|

### Should have — 最常用
> I **should have gone** sooner.（我本该早点去）
> ❌ ~~I should have **went** sooner.~~

### Could have — "本可以"
表示过去有机会做但没做，语气弱于 should have：
> We **could have gone** to a much better school.

### 否定形式 — 注意特殊限制
- **shouldn't have** = 本不该做（做了）
- ❌ **couldn't have** ≠ 过去不该做 → 意思是"不可能"
  > He **couldn't have arrived** late.（他不可能迟到——表示不可能）
- ❌ **might not have** ≠ 过去不该做 → 意思是"可能没"
  > He **might not have arrived** late.（他可能没迟到——表示可能没）

### 缩略形式
口语中常用：should've / could've / might've（读作 shoulda / coulda / mighta）''',
          keyRules: '''## 核心规则

### 1️⃣ 形式
- should / ought to / could / might + **have + 过去分词**
- ❌ 后面不跟动词原形或一般过去时

### 2️⃣ 含义
- I/We → 后悔
- You/He/She/They → 批评

### 3️⃣ 否定
- ✅ shouldn't have / ought not to have
- ❌ couldn't have（表不可能）
- ❌ might not have（表可能没）

### 4️⃣ 简短回答
- 必须用 **should have**
- ❌ 不能说 Yes, he should.（缺 have）''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| I **should have went** sooner. | I **should have gone** sooner. | 用过去分词，不用一般过去式 |
| He **couldn't have arrived** late.（想表达"不该迟到"）| He **shouldn't have arrived** late. | couldn't have ≠ 不该；表示"不可能" |
| A: Should we have sent it? B: Yes, we **should**. | Yes, we **should have**. | 简短回答必须保留 have |
| He **might not have** arrived.（想表达"不该迟到"）| He **shouldn't have arrived** late. | might not have = 可能没，不是"不该" |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| advisability | n. | 可取性，明智 |
| regret | n./v. | 后悔，遗憾 |
| criticism | n. | 批评 |
| applied | v. | 申请（过去分词）|
| opportunity | n. | 机会 |
| choice | n. | 选择 |
| mistake | n. | 错误 |
| blame | v. | 责备 |''',
        ),
        GrammarUnit(
          id: 'unit_16',
          title:
              'Unit 16: Speculations About the Past (May Have, Might Have, Could Have, Must Have)',
          outcomes:
              '''• Speculate about past events, expressing possible or probable conclusions (推测过去事件，表达可能或很可能得出的结论)
• Draw conclusions based on the information in an article about archaeology (根据考古文章中的信息得出结论)
• Identify key details in a conversation and draw conclusions (识别对话中的关键细节并得出结论)
• Discuss ancient objects and historical facts, and speculate about them (讨论古代物品和历史事实并进行推测)
• Write about an unsolved mystery (描写一个未解之谜)''',
          chart: '''## SPECULATIONS ABOUT THE PAST — 过去推测

### 可能性结论（不确定）
| 情态动词 | 确定性 | 例句 |
|---|---|---|
| **may have + 过去分词** | 可能（一般）| He **may have been** a hunter. |
| **may not have** | 可能不 | He **may not have felt** safe. |
| **might have** | 可能（不太确定）| He **might have expected** trouble. |
| **could have** | 可能（较确定）| He **could have known** his killer. |

### 大概率结论（几乎确定）
| 情态动词 | 确定性 | 例句 |
|---|---|---|
| **must have + 过去分词** | 一定是 | Someone **must have removed** it. |
| **must not have** | 一定不 | He **must not have wanted** evidence. |
| **had to have + 过去分词** | 一定是（较正式）| Someone **had to have taken** it out. |
| **couldn't have + 过去分词** | 不可能是 | He **couldn't have survived** the injury. |

### 问句结构
| 问句类型 | 结构 | 例句 |
|---|---|---|
| Yes/No | **Could** + 主语 + **have** + 过去分词？| **Could** he **have known** his killer? |
| Wh- | Wh- + **could** + 主语 + **have** + 过去分词？| Who **could have killed** him? |
| 简短回答 | 主语 + **may/might/could/must/had to have** | He **must have**. |''',
          chineseGuide: '''## 中文对比解析

### 过去推测 — "可能…了" vs "一定是…了"

| 程度 | 情态动词 | 中文翻译 | 肯定程度 |
|---|---|---|---|
| 不确定 | **may have** | 可能…了 | ~50% |
| 不确定 | **might have** | 也许…了 | ~40% |
| 不确定 | **could have** | 可能…了 | ~60% |
| 几乎确定 | **must have** | 一定是…了 | ~95% |
| 几乎确定 | **had to have** | 肯定是…了（正式）| ~95% |
| 不可能 | **couldn't have** | 不可能是…了 | ~0% |

### 举例：关于冰人（The Iceman）的推测
事实：冰人随身带了一把刀。
- **推测（不确定）**：He **may have been** a hunter.（他可能是个猎人）
- **推测（确定）**：Someone **must have removed** the arrow.（一定有人取走了箭）
- **否定（不确定）**：He **may not have felt** safe in the mountains.（他可能在山上觉得不安全）
- **不可能**：He **couldn't have survived** the injury.（他不可能在受伤后活下来）

### 与 Unit 14 / Unit 15 的区别
- Unit 14：现在/将来的推测 → He **must be** a hunter.
- Unit 15：过去建议/后悔 → He **should have brought** a weapon.
- Unit 16：过去推测 → He **must have been** a hunter.（根据事实判断他过去一定是）

### 口语发音
在日常口语中，could have / may have / might have 常读作 "could of / may of / might of" 或 "coulda / mighta"：
> It **could have** been a tool. → 读作 "could of" 或 "coulda"
> It **might have** been a knife. → 读作 "might of" 或 "mighta"
> ❌ 但写作时不能写 of，必须是 have''',
          keyRules: '''## 核心规则

### 1️⃣ 可能性结论（不确定）
- may / might / could + have + 过去分词
- may not / might not + have + 过去分词
- ❌ could not have ≠ 可能没；→ 是"不可能"

### 2️⃣ 大概率结论（几乎确定）
- must + have + 过去分词 — 一定
- must not + have + 过去分词 — 一定不
- had to + have + 过去分词 — 肯定（正式）
- couldn't + have + 过去分词 — 不可能

### 3️⃣ 区别
- may/might have = 可能（不确定）
- must have = 一定（几乎确定）
- couldn't have = 不可能（100%否定）''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| They **might have been** shocked...（想表达"一定很震惊"）| They **must have been** shocked. | 几乎确定用 must have，不用 might have |
| The police **didn't have to have** realized... | The police **may not have** realized... | 过去否定推测用 may not have，不用 didn't have to have |
| You **might not have** seen her...（想表达"不可能"）| You **couldn't have** seen her. | 不可能用 couldn't have |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| speculation | n. | 推测 |
| conclusion | n. | 结论 |
| probable | adj. | 很可能的 |
| impossible | adj. | 不可能的 |
| mystery | n. | 谜 |
| evidence | n. | 证据 |
| survive | v. | 幸存 |
| injury | n. | 受伤，伤害 |
| remove | v. | 移除 |
| archaeology | n. | 考古学 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_7',
      title: 'Part 7: 被动语态 (Passive)',
      units: [
        GrammarUnit(
          id: 'unit_17',
          title: 'Unit 17: Passive Overview — 被动语态概览',
          outcomes: '''## Passive Overview
**主动：** 关注"谁做"（执行者）
**被动：** 关注"被做"（承受者）

**结构：** be + 过去分词（be 随时态变化）''',
          chart: '''## Passive — 结构

| 时态 | 主动 | 被动 |
|---|---|---|
| 一般现在 | Someone **buys** it. | It **is bought**. |
| 一般过去 | Someone **published** it. | It **was published**. |
| 现在完成 | They **have reached** it. | It **has been reached**. |
| 现在进行 | People **are reading** it. | It **is being read**. |
| 过去进行 | People **were reading** it. | It **was being read**. |
| 将来 | They **will publish** it. | It **will be published**. |

| 主语 | be (not) | 过去分词 | (by + sb) |
|---|---|---|---|
| It | **is** | **bought** | by millions. |
| It | **was not** | **published** | |
| Their goal | **has been** | **reached** | |''',
          chineseGuide: '''## Passive — 中文解析

**主动 vs 被动 — 关注点不同**
- 主动关注**谁做的**：Millions of people read the magazine.
- 被动关注**被做了什么**：The magazine is read by millions.

**何时用被动？**
1. 执行者不重要/不清楚 → My wallet **was stolen**.
2. 想让承受者成为焦点 → Einstein **is known** worldwide.
3. 学术/正式写作 → The experiment **was conducted** in 2020.

**By + 执行者**
只有执行者是新信息时才加 by，否则省略。''',
          keyRules: '''## 核心规则

- **结构**：be + 过去分词（be 随时态变化）
- **何时用被动**：执行者不明确 / 想突出承受者 / 学术写作
- **By 短语**：只有执行者是新信息时才加
- **各时态被动**：完成时 → been done / 进行时 → being done / 将来时 → will be done''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| The book **wrote** in 1888. | The book **was written** in 1888. | 被动用 be + 过去分词 |
| It **is wrote** by millions. | It **is written** by millions. | write 的过去分词是 written |
| The car **was been** repaired. | The car **was repaired**. | 不要同时用 was + been |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|---|---|
| passive | n./adj. | 被动（的）|
| agent | n. | 执行者，施动者 |
| action | n. | 动作 |
| focus | n. | 焦点，重点 |''',
        ),
        GrammarUnit(
          id: 'unit_18',
          title: 'Unit 18: Passive with Modals — 带情态动词的被动',
          outcomes: '''## Passive with Modals
**结构：** 情态动词 + be + 过去分词

用被动情态动词表达：必须 / 应该 / 能够 / 将会 / 可能被做''',
          chart: '''## Passive with Modals — 结构

| 功能 | 结构 | 例句 |
|---|---|---|
| 必须 | must be done | The rules **must be followed**. |
| 应该 | should / ought to be done | This **should be solved** now. |
| 能够 | can be done | It **can be found** online. |
| 将会 | will be done | It **will be delivered** tomorrow. |
| 可能 | might be done | It **might be delayed**. |
| 最好 | had better be done | You **had better be registered**. |
| 必须（have to）| have to be done | It **has to be finished** today. |''',
          chineseGuide: '''## Passive with Modals — 中文解析

**结构：情态动词 + be + 过去分词**
> Active: You **must follow** the rules.
> Passive: The rules **must be followed**.

**否定**
- should not / must not / can't + be done
- doesn't have to be done（不必）

**问句**
- 情态动词提前：**Must** it be done today?
- Have to 用 do 提问：**Does** it have to be done?''',
          keyRules: '''## 核心规则

- **结构**：情态动词 + **be** + 过去分词
- **Must** 否定回答用 needn't / don't have to
- **Had better**：had better + be + 过去分词（否定：had better not be done）
- **Have to** 用 do 协助提问''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| It **must done** today. | It **must be done** today. | 漏了 be |
| They **should finished** by now. | It **should be finished** by now. | 被动必须用 be + 过去分词 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|---|---|
| modal | n. | 情态动词 |
| certainty | n. | 确定性 |
| possibility | n. | 可能性 |
| necessity | n. | 必要性 |''',
        ),
        GrammarUnit(
          id: 'unit_19',
          title: 'Unit 19: Passive Causative — 被动使役',
          outcomes: '''## Passive Causative
**让别人帮你做某事**

**结构：** have / get + 宾语 + 过去分词''',
          chart: '''## Passive Causative — 结构

| 结构 | 含义 | 例句 |
|---|---|---|
| have + 宾语 + 过去分词 | 让别人做（中性）| I **had** my hair **cut**. |
| get + 宾语 + 过去分词 | 让别人做（口语）| I **got** my car **fixed**. |

| 时态 | have | get |
|---|---|---|
| 一般现在 | She **has** her hair **cut** monthly. | She **gets** her hair **cut** monthly. |
| 一般过去 | I **had** my car **repaired**. | I **got** my car **repaired**. |
| 现在进行 | She **is having** her house **painted**. | She **is getting** her house **painted**. |
| 将来 | She **will have** her hair **done**. | She **will get** her hair **done**. |
| 现在完成 | She **has had** her hair **cut**. | She **has gotten** her hair **cut**. |''',
          chineseGuide: '''## Passive Causative — 中文解析

**基本含义："让别人做"**
> I **had my hair cut**. = 让理发师剪的（不是自己剪）
> I **got my car fixed**. = 让修理工修的（不是自己修）

**Have vs Get 语气区别**
- **have**：中性陈述事实
- **get**：口语化，"设法完成"

**vs 普通使役（Unit 10）**
- Unit 10: **have + 人 + do** → I had the mechanic fix my car.（让某人做）
- Unit 19: **have + 物 + done** → I had my car fixed.（让某事被做）''',
          keyRules: '''## 核心规则

- **结构**：have / get + 宾语 + 过去分词
- **含义**：让别人帮你做某事
- **Have**：中性 / **Get**：口语化
- **vs Unit 10**：have + 人 + do（让某人做）vs have + 物 + done（让某事被做）''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| I **had cut my hair**. | I **had my hair cut**. | had cut = 自己剪的；had hair cut = 让别人剪的 |
| I **got repaired my car**. | I **got my car repaired**. | 宾语要放在过去分词前面 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|---|---|
| causative | adj. | 使役的 |
| service | n. | 服务 |
| repair | v./n. | 修理 |
| professional | n. | 专业人士 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_8',
      title: 'Part 8: 条件句 (Conditional Sentences)',
      units: [
        GrammarUnit(
          id: 'unit_20',
          title: 'Unit 20: Present Real Conditional Sentences — 现在真实条件句',
          outcomes: '''## Present Real Conditional Sentences
**If / when + 一般现在时，主句 + 一般现在时**
描述经常发生的事实、习惯、规则或自然结果。

**Eg.** If people exercise regularly, they feel better.''',
          chart: '''## Present Real Conditional — 结构

| If 从句 | 结果从句 | 含义 |
|---|---|---|
| If / when + 一般现在时 | 一般现在时 | 经常发生的真实结果 |

**Eg.**
> If people exercise regularly, they feel better.
> If water reaches 0°C, it freezes.
> When I have time, I call my family.''',
          chineseGuide: '''## Present Real Conditional — 中文解析

表示现在或平时真实、反复发生的条件和结果，不是在假设不可能的事。

- if / when 从句和主句通常都用一般现在时。
- 常用于规则、习惯、科学事实和一般建议。
- 不用 would；也不用过去式 were。

> If people exercise regularly, they feel better.
> 如果人们经常锻炼，他们感觉会更好。''',
          keyRules: '''## 核心规则

- 结构：**If / when + 一般现在时，主句 + 一般现在时**
- 用于事实、规律、习惯、说明和真实结果。
- if 从句里不用 will；整个句子不使用 would。''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| If people exercise, they **will feel** better. | If people exercise, they **feel** better. | 现在真实条件句主句也用一般现在时 |
| If water **will reach** 0°C, it freezes. | If water **reaches** 0°C, it freezes. | if 从句不用 will |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|---|
| conditional | adj. | 条件的 |
| real condition | n. | 真实条件 |
| result | n. | 结果 |
| regularly | adv. | 经常地 |''',
        ),
        GrammarUnit(
          id: 'unit_21',
          title: 'Unit 21: Future Real Conditional Sentences — 将来真实条件句',
          outcomes: '''## Future Real Conditional Sentences
**If + 一般现在时，will / can / may + 动词原形**
描述将来可能发生的真实条件和结果。

**Eg.** If it rains tomorrow, we will stay home.''',
          chart: '''## Future Real Conditional — 结构

| If 从句 | 结果从句 | 含义 |
|---|---|---|
| If + 一般现在时 | will / can / may + 动词原形 | 将来可能发生的真实结果 |

**Eg.**
> If it rains tomorrow, we will stay home.
> If you study tonight, you can take the test tomorrow.
> If she calls, I may tell her.''',
          chineseGuide: '''## Future Real Conditional — 中文解析

表示将来有可能发生的真实情况。

- if 从句虽然说未来，仍使用一般现在时。
- 结果从句可以用 will、can、may 等情态动词。
- 不用 would，也不用过去式 were。

> If it rains tomorrow, we will stay home.
> 如果明天下雨，我们就待在家。''',
          keyRules: '''## 核心规则

- If 从句：**一般现在时**，不用 will。
- 结果从句：**will / can / may + 动词原形**。
- 含义：将来真实、可能发生的条件。''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| If it **will rain** tomorrow, we will stay home. | If it **rains** tomorrow, we will stay home. | if 从句不用 will |
| If I **were** free tomorrow, I will come. | If I **am** free tomorrow, I will come. | 真实条件句不用 were |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|---|
| future | n./adj. | 将来（的）|
| likely | adj. | 可能的 |
| result | n. | 结果 |''',
        ),
        GrammarUnit(
          id: 'unit_22',
          title:
              'Unit 22: Present & Future Unreal Conditional Sentences — 现在与将来非真实条件句',
          outcomes: '''## Present & Future Unreal Conditional Sentences
**If + 一般过去时，would / could + 动词原形**
表达与现在或将来事实相反的假设。

**Eg.** If I were you, I would wait.''',
          chart: '''## Present & Future Unreal Conditional — 结构

| If 从句 | 结果从句 | 含义 |
|---|---|---|
| If + 一般过去时 | would / could + 动词原形 | 与现在或将来事实相反 |

**Eg.**
> If I were you, I would wait.
> If it were warmer, we could go out.
> If she knew the answer, she would tell us.''',
          chineseGuide: '''## Present & Future Unreal Conditional — 中文解析

表示与现在或将来事实相反的假设。

- if 从句用一般过去时；be 动词考试中统一使用 **were**。
- 结果从句用 would / could + 动词原形。
- 不表达过去遗憾；过去非真实条件句不属于这次考试范围。

> If I were you, I would wait.
> 如果我是你，我会等。（事实：我不是你）''',
          keyRules: '''## 核心规则

- If 从句：**一般过去时**。
- 结果从句：**would / could + 动词原形**。
- be 动词一律优先用 **were**。
- if 从句不用 would。''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| If I **was** you, I would wait. | If I **were** you, I would wait. | 虚拟语气中考试优先用 were |
| If I **would have** time, I would help. | If I **had** time, I would help. | if 从句用过去时，不用 would |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|---|
| unreal | adj. | 虚拟的，不真实的 |
| hypothetical | adj. | 假设的 |
| imagine | v. | 想象 |''',
        ),
        GrammarUnit(
          id: 'unit_23',
          title: 'Unit 23: I Wish — 愿望与遗憾',
          outcomes: '''## I Wish

### 1️⃣ 希望改变现在现状
**wish + 过去式（be动词 → were）**

**Eg.** I wish I were in Alberta.
**Eg.** I wish I lived nearby.

### 2️⃣ 后悔过去发生的事
**wish + had done**

**Eg.** I wish I had left earlier.''',
          chart: '''## I Wish — 结构

| 结构 | 含义 | 例句 |
|---|---|---|
| wish + 过去式 | 希望改变现在现状 | I wish I **lived** nearby. |
| wish + were | be 动词固定用 were | I wish I **were** in Alberta. |
| wish + had done | 后悔过去发生的事 | I wish I **had left** earlier. |''',
          chineseGuide: '''## I Wish — 中文解析

### 1️⃣ 希望改变现在现状
**wish + 过去式**（be 动词 → **were**）

表达对**现在**情况的愿望，与事实相反。

> I wish I were in Alberta.
> 我真希望我现在在阿尔伯塔。（事实：我不在）

> I wish I lived nearby.
> 我真希望我住得近。（事实：我住得远）

### 2️⃣ 后悔过去发生的事
**wish + had done**

表达对**过去**事情的后悔。

> I wish I had left earlier.
> 我真希望我当时早点走。（事实：我走晚了）''',
          keyRules: '''## 核心规则

- **希望改变现在**：wish + **过去式**（be → were）
- **后悔过去**：wish + **had done**''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| I wish I **am** in Alberta. | I wish I **were** in Alberta. | wish 后跟过去时（虚拟）|
| I wish I **was** there. | I wish I **were** there. | be 动词一律用 were |
| I wish I **have left** earlier. | I wish I **had left** earlier. | 后悔过去用 had + 过去分词 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|---|
| wish | n./v. | 愿望，希望 |
| regret | n./v. | 后悔 |
| hopefully | adv. | 有希望地 |''',
        ),
      ],
    ),
    GrammarPart(
      id: 'part_9',
      title: 'Part 9: 间接引语 & 嵌入问句 (Indirect Speech & Embedded Questions)',
      units: [
        GrammarUnit(
          id: 'unit_24',
          title: 'Unit 24: Direct & Indirect Speech (Say, Tell, Ask)',
          outcomes:
              '''• Report what others said, using direct or indirect speech (用直接或间接引语转述他人说的话)
• Identify key information in a social science article (识别社会科学文章中的关键信息)
• Discuss lying and telling the truth (讨论说谎与说实话)
• Discuss and interpret literary quotes and international proverbs (讨论并诠释文学作品中的引语和国际谚语)
• Write about a past conversation, reporting what was said (转述一段过去的对话)''',
          chart: '''## DIRECT & INDIRECT SPEECH — 直接引语与间接引语

### Direct Speech（直接引语）
| 引语 | 报告动词 | 说话者 |
|---|---|---|
| "The check is in the mail," | **said** | he. |
| "Your hair looks great," | he **told** | Ann. |
| "The traffic was bad," | he **said** | (to her). |

### Indirect Speech（间接引语/转述）
| 主语 | 报告动词 | 宾语 | (that) | 转述内容 |
|---|---|---|---|---|
| He | **said** | | (that) | the check **was** in the mail. |
| He | **told** | the bank | (that) | the check **was** in the mail. |
| Ann | **said** | | (that) | her hair **looked** great. |

### 时态变化规则（backshift）
| 直接引语 | 间接引语 |
|---|---|
| Simple Present → "I **work**." | Simple Past → He said he **worked**. |
| Present Progressive → "I **am working**." | Past Progressive → He said he **was working**. |
| Simple Past → "I **worked**." | Past Perfect → He said he **had worked**. |
| Present Perfect → "I **have worked**." | Past Perfect → He said he **had worked**. |
| will → "I **will** go." | would → He said he **would** go. |
| can → "I **can** do it." | could → He said he **could** do it. |
| must → "I **must** go." | had to → He said he **had to** go. |''',
          chineseGuide: '''## 中文对比解析

### 直接引语 vs 间接引语
- **直接引语**：原话不动，加引号 → "I always pay on time," he said.
- **间接引语**：用自己的话转述，不加引号 → He said (that) he always paid on time.

### Say vs Tell
- **say** + (that) + 内容：He **said** (that) he was tired. ❌ 不说 ~~He said me...~~
- **tell** + 人 + (that) + 内容：He **told** me (that) he was tired. ✅ 必须要有间接宾语

### 时态回退（backshift）
转述时，如果报告动词是过去时（said / told），引语的时态一般要往**前推一格**：
> "I **work**." → He said he **worked**.
> "I **am working**." → He said he **was working**.
> "I **worked**." → He said he **had worked**.
> "I **will go**." → He said he **would go**.

### That 可以省略
> He said **(that)** he always paid on time.（口语常省略 that）

### 不用引号
间接引语**不加**引号：~~He said that, "he had to work."~~

### 时态回退的例外 — 什么情况下不用回退
如果报告动词是过去时，但转述的内容**仍然成立**，可以不必回退：
> "I live in Seoul." → **She said she lives in Seoul.**（她仍然住在那）
> "The sun rises in the east." → **He said the sun rises in the east.**（客观真理）

如果转述的话是**刚刚说的**，也可以不回退：
> **Ann just said** she **is** tired.（刚说的，现在还累）
> ❌ 但她如果是昨天说的，一般要回退：Ann said she **was** tired.

### 代词变化（pronoun changes）
转述时，要根据转述者的视角调整代词：
> "I work here." → **She** said **she** worked there.（I → she）
> "You are late," he told me. → He told **me** that **I** was late.（you → me）
> "We saw him," they said. → **They** said **they** had seen him.（we → they）

### 简单现在时报告动词 — 不用回退
如果报告动词是简单现在时（says / tells），时态保持不变：
> He **says** he **has** to work today.（现在时，不用回退）
> Ann **tells** me she **is** tired.（现在时，不用回退）''',
          keyRules: '''## 核心规则

### 1️⃣ Say vs Tell
- say + (that) + 内容（不加人）
- tell + 人 + (that) + 内容（必须加人）
- say + to + 人（较正式）：He said to Ann that...

### 2️⃣ 时态回退（backshift）
- 报告动词是过去时 → 引语时态往前推一格
- 现在→过去 / 过去→过去完成 / will→would

### 3️⃣ 时态不回退的例外
- 转述内容仍然成立：She said she **lives** in Seoul.
- 客观真理：He said the sun **rises** in the east.
- 报告动词是现在时：He **says** he has to work.

### 4️⃣ 代词变化
- 转述时调整人称代词（I → she, you → me 等）

### 5️⃣ 不加引号
- 间接引语不用引号
- 可以用 that 连接（可省略）''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| He **said me** that he was tired. | He **told me** that he was tired. | say 不加间接宾语（人）|
| He told that he was tired. | He **said** (that) he was tired. / He **told me** (that) he was tired. | tell 必须加人 |
| She said that, "she had to work." | She said that she had to work. | 间接引语不加引号 |
| "I work here," she said. → She said she **work** here. | She said she **worked** there. | 时态要回退（work→worked），here→there |
| "You are late," he told me. → He told me that **you** were late. | He told me that **I** was late. | 代词要转述者视角调整 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| direct speech | n. | 直接引语 |
| indirect speech | n. | 间接引语 |
| reported speech | n. | 转述引语 |
| quotation marks | n. | 引号 |
| reporting verb | n. | 报告动词 |
| tense shift | n. | 时态回退 |
| backshift | n. | 时态后退 |
| proverb | n. | 谚语 |''',
        ),
        GrammarUnit(
          id: 'unit_25',
          title:
              'Unit 25: Indirect Speech with Tense Changes & Time-Word Changes',
          outcomes:
              '''• Report other people's statements using indirect speech with necessary tense and time-word changes (用时态和时间词变化转述他人的话)
• Match quotations with speakers (将引语与说话者匹配)
• Identify specific information in a conversation (识别对话中的具体信息)
• Discuss extreme weather events and report other people's statements (讨论极端天气并转述他人的话)
• Write about an extreme weather event, reporting another person's experience (描写极端天气事件并转述他人经历)''',
          chart: '''## TIME-WORD CHANGES — 时间词变化

| 直接引语 | 间接引语 |
|---|---|
| **today** | **that day** |
| **now** | **then / at that moment** |
| **yesterday** | **the day before / the previous day** |
| **tomorrow** | **the next day / the following day** |
| **last week** | **the week before / the previous week** |
| **next week** | **the week after / the following week** |
| **ago** | **before / earlier** |
| **here** | **there** |
| **this** (book) | **that** (book) |

### 例句对比
| 直接引语 | 间接引语 |
|---|---|
| "I'm working **today**." | He said he was working **that day**. |
| "I saw him **yesterday**." | She said she had seen him **the day before**. |
| "I'll call you **tomorrow**." | He said he would call me **the next day**. |
| "I lost it **two days ago**." | He said he had lost it **two days before**. |
| "I live **here**." | She said she lived **there**. |''',
          chineseGuide: '''## 中文对比解析

### 时间词变化规则
转述时，时间词需要根据**说话时间 vs 转述时间**做出调整：

| 原来的词 | 转述时改为 | 逻辑 |
|---|---|---|
| today | that day | "今天"相对于转述时变成"那天" |
| now | then / at that moment | "现在"变成"当时" |
| yesterday | the day before | "昨天"变成"前一天" |
| tomorrow | the next day | "明天"变成"第二天" |
| last week | the week before | "上周"变成"前一周" |
| next week | the following week | "下周"变成"后一周" |
| ago | before / earlier | "……前"变成"之前" |
| here | there | "这里"变成"那里" |

### 规则的核心逻辑
转述的时间已经变了，所以时间词要跟着调整：
> 周一：Sam说 "I'll call you **tomorrow**."
> 周三：我转述 → Sam said he would call me **the next day**.（即周二）
> 如果用 "tomorrow" 听起来像是周三，就错了。

### 如果转述时间很近，可以不变
如果刚说完就转述，时间词也可以不调整：
> A: "I'm busy **today**."
> B: He said he's busy **today**.（还在同一天）''',
          keyRules: '''## 核心规则

### 1️⃣ 时间词变化
- today → that day
- yesterday → the day before
- tomorrow → the next day
- now → then
- ago → before
- here → there

### 2️⃣ 逻辑
- 转述时的时间点变了
- 时间词要相应调整以保持正确的时间关系

### 3️⃣ 灵活处理
- 如果同一天/同一语境转述，时间词也可以不变''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| He said he was working **today**. | He said he was working **that day**. | "今天"在转述时已变成"那天" |
| She said she had seen him **yesterday**. | She said she had seen him **the day before**. | "昨天"在转述时已变成"前一天" |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| extreme weather | n. | 极端天气 |
| time expression | n. | 时间表达 |
| adjust | v. | 调整 |
| perspective | n. | 视角，角度 |''',
        ),
        GrammarUnit(
          id: 'unit_26',
          title:
              'Unit 26: Indirect Instructions, Commands, Advice, Requests & Invitations',
          outcomes:
              '''• Report other people's instructions, commands, advice, requests, and invitations (转述他人的指示、命令、建议、请求和邀请)
• Identify specific information in an interview transcript (识别采访记录中的具体信息)
• Identify medical advice reported in a conversation (识别对话中转述的医疗建议)
• Discuss health issues and possible home remedies (讨论健康问题和家庭疗法)
• Report how someone followed instructions (转述某人如何按照指示行事)
• Write about a health problem and the health advice one received (描写健康问题和收到的建议)''',
          chart: '''## INDIRECT INSTRUCTIONS & COMMANDS — 转述指令和命令

### Tell + Person + To + Verb
| 直接 | 间接 |
|---|---|
| "Sit down." | He **told** me **to sit** down. |
| "Don't move." | The doctor **told** me **not to move**. |

### Ask + Person + To + Verb（请求）
| "Please help me." | She **asked** me **to help** her. |
|---|---|
| "Please don't go." | She **asked** me **not to go**. |

### Advise / Encourage / Invite / Warn + Person + To + Verb
| 直接 | 间接 |
|---|---|
| "You should see a doctor." | He **advised** me **to see** a doctor. |
| "Try this medicine." | The pharmacist **recommended trying** this medicine. |
| "Come to my party." | She **invited** me **to come** to her party. |
| "Don't touch that!" | He **warned** me **not to touch** that. |

### Suggest / Recommend + Gerund
| "You should try yoga." | She **suggested trying** yoga. |
|---|---|
| "Try drinking tea." | He **recommended drinking** tea. |

### Offer + Infinitive
| "I'll help you." | He **offered to help** me. |''',
          chineseGuide: '''## 中文对比解析

### 转述指令和请求的核心结构
**动词 + 人 + to + 动词原形**：
> "Sit down." → He **told** me **to sit** down.
> "Please help me." → She **asked** me **to help** her.
> "Don't move." → He **told** me **not to move**.
> "Please don't go." → She **asked** me **not to go**.

### 各个报告动词的转述模式

| 功能 | 报告动词 | 模式 | 例句 |
|---|---|---|---|
| 命令 | **tell** | tell + person + to do | He told me to sit down. |
| 请求 | **ask** | ask + person + to do | She asked me to help. |
| 建议 | **advise** | advise + person + to do | He advised me to rest. |
| 推荐 | **suggest** | suggest + (person) + **doing** | She suggested trying yoga. |
| 推荐 | **recommend** | recommend + (person) + **doing** | He recommended drinking tea. |
| 邀请 | **invite** | invite + person + to do | She invited me to come. |
| 警告 | **warn** | warn + person + not to do | He warned me not to touch. |
| 提出 | **offer** | offer + to do | He offered to help me. |

### 关键区别
- **tell / ask / advise / invite / warn** → 都要加上动作的**对象**（人）
- **suggest / recommend** → 后面跟**动名词**（-ing），不加人
  > She **suggested trying** yoga.（不是 ~~suggested me to try~~）
- **offer** → 后面跟**不定式**（不加人）
  > He **offered to help** me.（不是 ~~offered me to help~~）''',
          keyRules: '''## 核心规则

### 1️⃣ 指令/命令
- **tell + person + (not) to** → He told me to sit / not to move

### 2️⃣ 请求
- **ask + person + (not) to** → She asked me to help / not to go

### 3️⃣ 建议/推荐
- **advise + person + to** → He advised me to rest
- **suggest / recommend + doing** → 🚫 不加人 + to ; ✅ She suggested trying yoga

### 4️⃣ 邀请/警告
- **invite + person + to** → She invited me to come
- **warn + person + not to** → He warned me not to touch

### 5️⃣ 提出帮助
- **offer + to do** → 🚫 不加人''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| She **suggested me to try** yoga. | She **suggested trying** yoga. | suggest 不加人 + to；用动名词 |
| He **offered me to help**. | He **offered to help** me. | offer 不加人，直接跟不定式 |
| He **told** that I should sit. | He **told** me **to sit**. | tell 后加人 + to do，更简洁 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| instruction | n. | 指示 |
| command | n. | 命令 |
| request | n. | 请求 |
| invitation | n. | 邀请 |
| advice | n. | 建议 |
| remedy | n. | 疗法，补救 |''',
        ),
        GrammarUnit(
          id: 'unit_27',
          title: 'Unit 27: Indirect Questions',
          outcomes:
              '''• Report other people's questions using indirect speech (用间接引语转述他人的问题)
• Identify specific information in a business article (识别商业文章中的具体信息)
• Role-play and discuss a job interview (角色扮演并讨论求职面试)
• Complete a questionnaire about work values and report conversations (完成关于工作价值观的问卷并转述对话)
• Write a report on a job interview (写一份求职面试报告)''',
          chart: '''## INDIRECT QUESTIONS — 间接问句

### Wh- Questions
| 直接问句 | 间接问句 |
|---|---|
| "Where **is** the bank?" | He asked where the bank **was**. |
| "When **does** the store **open**?" | She asked when the store **opened**. |
| "Why **did** you **leave**?" | He asked why I **had left**. |
| "What **are** you **doing**?" | She asked what I **was doing**. |

### Yes/No Questions（用 if / whether）
| 直接问句 | 间接问句 |
|---|---|
| "**Do** you **like** it?" | He asked **if** I **liked** it. |
| "**Is** she **coming**?" | She asked **whether** she **was coming**. |
| "**Have** you **seen** him?" | He asked **if** I **had seen** him. |

### 直接问句 vs 间接问句的结构差异
|  | 直接问句 | 间接问句 |
|---|---|---|
| 语序 | **倒装**（疑问句语序）| **陈述句语序**（主语 + 动词）|
| 助动词 do | 需要 | **去掉** do / does / did |
| 时态 | 照原样 | 时态回退 |
| 标点 | 问号 | **句号** |
| Wh-词 | 保留 | 保留 |
| Yes/No | 问号 | **if / whether** + 陈述句 |''',
          chineseGuide: '''## 中文对比解析

### 间接问句的核心规则

**1. 语序变为陈述句语序**
间接问句**不再是问句结构**，而是陈述句语序（主语 + 动词）：
> 直接：Where **is** the bank?（be + 主语）
> 间接：He asked where the bank **was**.（主语 + be）

**2. 去掉 do / does / did**
> 直接：When **does** the store **open**?
> 间接：She asked when the store **opened**.
> （does 去掉，open 变成 opened，时态回退）

**3. Yes/No 问句用 if / whether**
> 直接："**Do** you like it?"
> 间接：He asked **if** I liked it.
> ❌ ~~He asked did I like it.~~

**4. 问号→句号**
间接问句结尾用**句号**，不是问号：
> He asked where the bank was.
> ❌ ~~He asked where the bank was?~~

**5. Whether vs If**
- **if**：更口语化
- **whether**：正式文体，或表示"是否"（有选择意味）
- **whether or not**：固定搭配

### 时态回退仍然适用
> "Where **do** you **live**?" → He asked where I **lived**.
> "Why **did** you **leave**?" → He asked why I **had left**.
> "**Are** you **coming**?" → She asked **if** I **was coming**.''',
          keyRules: '''## 核心规则

### 1️⃣ Wh- 间接问句
- 保留 wh- 词
- **陈述句语序**（主语 + 动词）
- 去掉 do / does / did
- 时态回退
- 句号结尾

### 2️⃣ Yes/No 间接问句
- 用 **if** / **whether** 引导
- 陈述句语序
- 时态回退
- 句号结尾

### 3️⃣ 不要犯的错误
- ❌ 倒装语序（is he → he was）
- ❌ 保留 do（did I → I had）
- ❌ 用问号（用句号）''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| He asked where **was the bank**. | He asked where the bank **was**. | 间接问句用陈述句语序 |
| She asked **did I like** it. | She asked **if I liked** it. | Yes/No 间接问句用 if，不倒装 |
| He asked why I **left**. | He asked why I **had left**. | 时态回退：过去→过去完成 |
| She asked what I **am** doing. | She asked what I **was doing**. | 时态回退：现在进行→过去进行 |
| He asked where the bank was**?** | He asked where the bank was**.** | 间接问句用句号 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| indirect question | n. | 间接问句 |
| word order | n. | 词序，语序 |
| interview | n. | 面试，采访 |
| questionnaire | n. | 问卷 |
| report | n./v. | 报告 |''',
        ),
        GrammarUnit(
          id: 'unit_28',
          title: 'Unit 28: Embedded Questions',
          outcomes:
              '''• Ask for information or express something you don't know, using embedded questions (用嵌入问句询问信息或表达不知道的事)
• Extract key information from an interview transcript (从采访记录中提取关键信息)
• Identify and discuss details in a call-in radio show (识别并讨论电台热线节目中的细节)
• Discuss tipping around the world, giving opinions (讨论世界各地的给小费习惯，表达观点)
• Write opinions about tipping customs (写一篇关于给小费习惯的观点文章)''',
          chart: '''## EMBEDDED QUESTIONS — 嵌入问句

| 主句（不知道）| Wh- / if | 陈述句语序 |
|---|---|---|
| I don't know | **where** | the bank **is**. |
| I'm not sure | **what** | she **wants**. |
| Can you tell me | **how much** | it **costs**? |
| I wonder | **if** | he **is** coming. |
| Do you know | **whether** | she **has** arrived? |

### 嵌入问句 vs 直接问句
| 直接问句 | 嵌入问句 |
|---|---|
| Where **is** the bank? | I don't know where the bank **is**. |
| What **does** she **want**? | I'm not sure what she **wants**. |
| **Is** he coming? | I wonder **if** he **is coming**. |
| **Did** she arrive? | Do you know **whether** she **arrived**? |

### 常见引导句
| 引导句 | 含义 |
|---|---|
| **I don't know**... | 我不知道 |
| **I'm not sure**... | 我不确定 |
| **I wonder**... | 我想知道 |
| **Can you tell me**...? | 你能告诉我……吗？|
| **Do you know**...? | 你知道……吗？|
| **Could you explain**...? | 你能解释……吗？|''',
          chineseGuide: '''## 中文对比解析

### 嵌入问句 — "我不知道…" / "你能告诉我…吗？"

嵌入问句是把问句**嵌入**到另一个句子中，通常跟在"我不知道"、"我不确定"、"你能告诉我"等表达后面。

### 结构与间接问句相同

嵌入问句的语法规则跟间接问句完全一样：
1. **陈述句语序**（主语 + 动词）
2. **去掉 do / does / did**
3. **Wh- 词保留**
4. **Yes/No 问句用 if / whether**

> 直接：**Where is** the bank?
> 嵌入：I don't know **where the bank is**.
> ❌ ~~I don't know where is the bank.~~

> 直接：**Does** she **want** this?
> 嵌入：I'm not sure **if** she **wants** this.
> ❌ ~~I'm not sure does she want this.~~

### 嵌入问句 vs 间接问句的区别

|  | 间接问句 | 嵌入问句 |
|---|---|---|
| 主句动词 | asked / wanted to know | **I don't know / I'm not sure / I wonder / Can you tell me...?** |
| 用途 | 转述别人的问题 | 表达自己不知道或请求信息 |
| 语气 | 转述（过去） | 现在时、不确定、礼貌请求 |

### 礼貌用法
嵌入问句常用来使请求更礼貌：
> **Can you tell me** where the bank is?（比 Where is the bank? 更礼貌）''',
          keyRules: '''## 核心规则

### 1️⃣ 结构 = 引导句 + 嵌入问句
- 引导句：I don't know / I'm not sure / I wonder / Can you tell me...
- 嵌入问句：wh-词 / if + 陈述句语序

### 2️⃣ 语序
- 陈述句语序（主语 + 动词）
- 去掉 do / does / did
- Yes/No 用 if / whether

### 3️⃣ 用法
- 表达不知道 → I don't know where it is.
- 不确定 → I'm not sure if he's coming.
- 礼貌请求 → Can you tell me how much it costs?

### 4️⃣ 与间接问句区别
- 间接问句：转述（过去时）
- 嵌入问句：表达不知道（现在时）或礼貌请求''',
          commonMistakes: '''## 常见错误

| ❌ 错误 | ✅ 正确 | 说明 |
|---|---|---|
| I don't know **where is** the bank. | I don't know **where the bank is**. | 嵌入问句用陈述句语序 |
| I'm not sure **does she want** this. | I'm not sure **if she wants** this. | 去掉 do，用 if 连接 |
| Can you tell me **how much does it cost**? | Can you tell me **how much it costs**? | 去掉 does，主语在前 |''',
          vocabulary: '''| 词汇 | 词性 | 中文 |
|---|---|---|
| embedded question | n. | 嵌入问句 |
| polite | adj. | 礼貌的 |
| request | n. | 请求 |
| unsure | adj. | 不确定的 |
| wonder | v. | 想知道 |
| tipping | n. | 给小费 |''',
        ),
      ],
    ),
  ];
}
