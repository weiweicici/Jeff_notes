import '../models.dart';

class PathwaysContent {
  static const Map<PathwaysUnit, PathwaysUnitData> units = {
    PathwaysUnit.unit2: _unit2,
    PathwaysUnit.unit3: _unit3,
  };

  // ──────────────────────────────────────────────
  // Unit 2: It's In My DNA — 先天 vs 后天 (Nature vs Nurture)
  // ──────────────────────────────────────────────
  static const PathwaysUnitData _unit2 = PathwaysUnitData(
    theme: '''
本单元讨论**先天（nature）与后天（nurture）**对人的影响：
- **Nature（先天）**：DNA、遗传基因决定我们的身体特征和部分性格
- **Nurture（后天）**：成长环境、教育、文化塑造我们的行为和能力

### 核心模型：OCEAN 五大人格特质
| 特质 | 中文 | 先天影响比例 | 含义 |
|---|---|---|---|
| **O**penness | 开放性 | 57% | 好奇心、创造力、是否愿意尝试新事物 |
| **C**onscientiousness | 尽责性 | 49% | 自律、有条理、守计划 |
| **E**xtroversion | 外向性 | 54% | 社交活跃度 |
| **A**greeableness | 宜人性 | 42% | 友善、同情心、信任他人 |
| **N**euroticism | 神经质 | 48% | 容易焦虑、情绪敏感 |

### 关键问题
1. 性格是天生的还是后天培养的？→ 两者都有影响
2. 双胞胎基因相同 → 性格是否完全一样？→ 研究显示并不完全一样
3. 环境会不会改变性格？→ 会，性格可以随着年龄和环境变化
4. DNA 能否决定职业选择？→ 可能有影响，但不能完全决定

### 实用表达
- **say vs tell**: say + 内容（不加人）；tell + 人 + 内容
- **表达确定性**：I'm sure → I think → I'm not sure
''',
    reading: '''
## 📖 讲座：性格是天生的吗？(Is Personality Determined at Birth?)

DNA 是我们体内的化学物质，决定了我们的眼睛颜色、身高和头发颜色。但是 DNA 也决定我们的性格吗？关于这个问题，科学家们并不完全一致。

### 三个需要验证的推论
如果 DNA 决定性格，那么以下三点应该成立：

**推论1：同卵双胞胎应该有相同的性格**
→ 研究（1979-1999）显示：双胞胎有一些相同的性格特征，但不是全部。20% 的性格特征相同。

**推论2：性格不应随着年龄改变**
→ 但实际研究发现，性格会改变。例如，一个人可以随着年龄增长变得不那么害羞。

**推论3：来自有爱家庭的孩子不会做坏事**
→ 但事实上，环境（朋友、学校等）也会影响一个人的行为。

### 结论
每个人的性格是**独特**的。性格很可能**部分来自基因**，**部分来自成长环境**和我们在家庭和学校接触的一切。我们在谈论 DNA 时需要谨慎——我们不能说一个孩子因为 DNA 不适合而无法从事某个职业。

---

## 📖 遗传学简史 (Science 101: Genetics)

遗传学是研究身体特征和性格特征如何从一代传到下一代的科学。

- **孟德尔（Gregor Mendel, ~1865）**：发表了关于植物遗传的研究，发现不同基因影响特征的表达
- **人类基因组计划**：确定了人类基因序列中约 90% 的部分
- 我们每个人有 **20,000-25,000 个基因**
- 基因信息包含在我们的细胞中，结构叫染色体，以 DNA 形式携带

遗传学研究为医学带来了机会，如基因检测可以帮助人们活得更健康。

---

## 📖 对话：DNA 与职业选择 (DNA and Career Choice)

学生 Ayesha 与辅导员 Mr. Lee 讨论职业选择：

**主要观点：**
- DNA 测试不能决定你应该选择什么职业
- 有些研究表明人们在某些职业上可能有遗传优势，但这不能预测你是否会快乐
- 同卵双胞胎有时选择相同职业（研究显示：两个兄弟在同一家公司工作50年）
- 在语言方面有天赋的人，大脑工作方式可能不同
- 选择职业时应该考虑多种因素，而非仅仅 DNA
- 网上的 DNA 测试结果不能作为职业选择的依据
''',
    exercises: [
      '''
### Vocabulary — MEANING FROM CONTEXT
Match the questions with the answers. Focus on the words in blue.
1. What do you think about the change in the bus schedule?
2. Is it a good idea to separate children who don't behave well in class?
3. Why are scientists interested in fingerprints?
4. Are athletes naturally talented? Can anyone become skilled if they train enough?
5. I need to find someone to share my apartment. How do I choose a good roommate?

**Key vocabulary:** affect, separate, unique, adapt, cautious, circumstances, determine, exposed to, identical, investigate, skilled, trait
''',
      '''
### Listening — MAIN IDEAS
Watch or listen to the lecture about personality. Complete the summary with the words below:
cautious / change / circumstances / determine / exposed to / genetic / height / identical / loving / unique

DNA is a chemical in our bodies that gives us our 1\______ and hair color. But does DNA also 2\______ our personalities? ... If our DNA is responsible for our personalities, then 3\______ twins should have the same personalities; personality should not 4\______ as we get older; and children from 5\______ families should not do bad things as adults. However, we know these are not always true. The 6\______ we grow up in can affect our personalities. Everyone's personality is 7\______ and probably partly 8\______ and partly what we are 9\______ at home and at school. We need to be 10\______ when talking about DNA.
''',
      '''
### Grammar for Speaking — Say, Tell, Talk, Discuss

| 动词 | 搭配 | 例句 |
|---|---|---|
| **Say** | say + (that) + 内容 | He said (that) he was tired. |
| **Tell** | tell + 人 + about + 内容 | He told me about his research. |
|  | tell + 名词 | tell a story / tell a joke / tell the truth |
| **Talk** | talk about / talk to | She is talking about her trip. |
| **Discuss** | discuss + 名词 | We discussed the role of DNA. ❌ ~~discuss about~~ |

Correct the mistakes:
1. In my presentation, I'm going to **tell about** DNA. → **talk about**
2. I don't think he **said me** the truth. → **told me**
3. What are we going to **discuss about**? → **discuss**
4. Can you **say a joke**? → **tell a joke**
5. Linh **told that** she was sick. → **said that**
''',
      '''
### Speaking Skill — Express Degrees of Certainty
| 确定性 | 表达 |
|---|---|
| 最确定 | I'm **sure / positive** that's true. |
| 比较确定 | I'm **pretty sure** it's true. |
| 不确定 | I **think** it's true, but I could be wrong. |
| 很不确定 | I'm **not sure** about that. |
| 完全不确定 | I **really don't know** if that's true. |
''',
      '''
### Pronunciation — Final Consonants -t and -d
单词结尾的 -t 或 -d 后跟辅音时，常常不发音（这叫 elision）：
> I **didn't** know about that kind of testing.
> I **wanted** to **wait** for you, but I **had** to leave.
> We **thought** the question was **too hard** to answer.

Listen and underline where you hear elision:
1. It's time to **start** thinking about what you'd like to study.
2. Art is one of your **weakest** subjects.
3. I need to study and work in the art field.
''',
    ],
  );

  // ──────────────────────────────────────────────
  // Unit 3: On the Move — 城市化 (Urbanization)
  // ──────────────────────────────────────────────
  static const PathwaysUnitData _unit3 = PathwaysUnitData(
    theme: '''
本单元讨论**城市化（urbanization）** — 为什么越来越多的人搬到城市，城市化的利弊。

### 核心问题：城市化是好事还是坏事？
**正方观点（支持城市化）：**
- 城市让资源和信息更集中，提高效率
- 城市居民人均碳排放更低（公共交通、高密度住宅）
- 城市化与经济发展密切相关——首尔的成功案例

**反方观点（反对城市化）：**
- 污染、贫民窟、交通拥堵
- 城市无序扩张（urban sprawl）导致更多能源消耗
- 管理不善的城市化带来更多问题

### 关键概念
- **Push factors（推力）**: 战争、贫困、自然灾害等促使人们离开家乡
- **Pull factors（拉力）**: 更好的工作、教育、医疗、自由吸引人们前往城市
- **Urban sprawl（城市扩张）**: 城市不断向外扩展，占用更多土地
- **Density（密度）**: 城市高密度居住反而可能更环保
''',
    reading: '''
## 📖 Reading A: Living on an Urban Planet

Consider this: In 1800, less than three percent of the world's population lived in cities, but by 2050, this could increase to over 66 percent. The trend is clear—humans have become an urban species.

### CITIES AS SOLUTIONS?
In the 19th and early 20th centuries, many people viewed cities as crowded, dirty, unhealthy places. However, recent decades have seen a change in attitudes. Many experts now believe big cities might help solve the problem of Earth's growing population.

**Edward Glaeser** (Harvard economist): Cities are "the absence of space between people." This closeness reduces the cost of transporting goods, people, and ideas, and allows people to be more productive. A perfect example is the trading floor of the New York Stock Exchange—employees share information in one open, crowded space. "They value knowledge over space," he says.

**Stewart Brand** (environmentalist): Living in cities has a smaller environmental impact. Cities allow half of the world's population to live on about four percent of the land. City roads and power lines are shorter, apartments use less energy, and people walk or use public transportation more. Cities produce fewer greenhouse gas emissions per person than suburbs.

**David Satterthwaite**: Rapid growth itself is not the problem. The larger issue is how to manage the growth.

### SEOUL'S SUCCESS STORY
Since the 1960s, Seoul's population has increased from under 3 million to around 10 million. South Korea went from being one of the world's poorest countries to being richer than many European countries. The government invested in companies like Samsung and Hyundai. A major factor was the large number of people who came to Seoul to work.

"You can't understand urbanization in isolation from economic development," says economist Kyung-Hwan Kim.

### MANAGING URBANIZATION
Today, urban planners focus on **urban sprawl**—the way big cities spread out. When incomes rise, people buy more space and move to suburbs, leading to more energy use and pollution.

Professor **Shlomo Angel**: Rising incomes and cheaper transportation are two main reasons for urban sprawl. Today, planners want to bring people back to downtown areas and make suburbs denser—creating walkable town centers, high-rise apartments, and more public transportation. "It would be a lot better for the planet" if people are "in dense cities built around the elevator rather than in sprawling areas built around the car."

Good planning means looking decades ahead—reserving land for parks and public transport before the city grows over it.

---

## 📖 Reading B: A City Up Against the Wall

The disastrous flood of November 12, 2019, in Venice started as a gentle flow at 6 a.m. Two hours later, the water stopped at about a meter above normal. Residents began to relax—but that was just the beginning.

At 4 p.m., alarms went off. Within an hour, the ancient squares and narrow walkways had vanished under fierce waves. "It was a colossal wave, something we'd never seen before. A tsunami," says Marco Malafonte.

At 8 p.m., the water reached just under two meters—85 percent of the city underwater. It was the second highest flood tide ever recorded.

### Il Mose per Venezia
As sea levels rise, floods have become the new normal. Over the last century, 25 high tides in Venice have been 1.5 meters or higher. More than half have happened since December 2009.

Venetian officials spent billions on **Moses**—a series of moveable walls to block high waters. The system has 78 hollow barriers that are filled with water and hidden on the sea floor. When a high tide is expected, water is pumped out and the barriers float to the top.

Each barrier is 20 meters wide, 20-30 meters tall. The barriers can be operated independently, allowing ships to pass. It takes 32 minutes to raise them.

Moses first went into action on October 3, 2020, and Venice remained dry. Over the following 20 months, the gates lifted 33 more times.

### The Price of Safety
Moses has cost around €8 billion—far more than expected. It's expensive to use and requires a lot of labor. It also doesn't protect lower-lying areas like Piazza San Marco. Additionally, Moses may be a danger to the salt marshes—when the tide is blocked, it cannot "feed" the lagoon with sediment that helps plants grow.
''',
    exercises: [
      '''
### Reading A — BUILD VOCABULARY
The words and phrases in blue are used in the reading passage. Match each word/phrase to its definition:
suburb / urban / low-income / flexible / productive / aspect / traffic congestion / concentration / peak hours / spread out / dense / urbanization

1. (n) a part or side of something
2. (v) to cover a huge area
3. (n) money that a person earns
4. (adj) able to achieve a significant amount
5. (n) a huge amount of something in one place
6. (n) areas outside of a large city
7. (adj) having a large amount close together
8. (adj) relating to a city
''',
      '''
### Reading A — SUMMARIZE
Check (✓) four sentences to complete the summary:
☐ Urbanization has benefits like easy exchange of ideas and reduction of environmental impact.
☐ Seoul experienced many problems as a result of rapid population growth.
☐ Seoul's development is an example of how urbanization can bring positive impacts.
☐ Urban planners today are concerned with managing the expansion of large cities.
☐ Many people in the US moved out of cities in the second half of the 20th century.
☐ Careful long-term planning is key to growing cities for the world's future population.
''',
      '''
### Reading A — UNDERSTAND MAIN IDEAS
Match each paragraph with its main idea:
1. Paragraph B (Cities as solutions) → ___
2. Paragraph C (Glaeser) → ___
3. Paragraph D (Brand) → ___
4. Paragraphs F-G (Seoul) → ___
5. Paragraph K (Planning) → ___

a. Urbanization is better for the environment.
b. By reducing distance, cities bring positive benefits.
c. Proper urban planning can bring positive results.
d. Recently, attitudes toward cities have become more positive.
e. Well-managed urbanization helped a poor country develop rapidly.
''',
      '''
### Reading A — IDENTIFY PROS AND CONS
1. According to Glaeser, what are two benefits of living in cities?
2. According to Brand, what is one benefit of dense cities?
3. What is the main challenge related to urbanization?
4. What are urban planners mainly focusing on today?
''',
      '''
### Reading B — BUILD VOCABULARY
Complete sentences with: temporarily / separate / resident / partially / occasional / lower / fierce / construction / canal / barrier

1. You need to be ready for storms if you're a(n) ___ of a city on the water.
2. Cities near the sea may need a(n) ___ to ___ the water from the land.
3. A wide range of people are employed in the ___ industry.
4. During bad storms, some buildings need to close ___ or completely.
5. Venice is famous for its ___.
6. Floods used to be a(n) ___ problem, but now they happen frequently.
''',
      '''
### Reading B — SCAN FOR DETAILS
Complete with no more than two words or a number:
1. At first, the flood of 2019 was just a ___.
2. In the past 100 years, ___ acque alte have been at least 1.5 meters high.
3. Moses has 78 ___ that can block the tide.
4. One way Moses is innovative is that the barriers can be used ___.
5. So far, Moses has cost about €___.
''',
      '''
### Reading B — ANALYZE LEVELS OF CERTAINTY
Label as **C** (certain), **L** (less certain), or **P** (possible):
1. ___ The system **seems to be working**.
2. ___ Sea levels **may** have risen another 1.5 meters.
3. ___ Venice remained dry, **proving** the project worked.
4. ___ Moses **may be** a danger to the salt marshes.
''',
      '''
### Writing — LANGUAGE FOR WRITING
Choose the correct options:
1. People **moved / have moved** to Seoul during the 1950s.
2. The government **invested / has invested** in local companies in the 1950s.
3. Life **improved / has improved** for South Koreans during the past few decades.
4. Construction on Moses **started / has started** in 1987.
5. Engineers **used / have used** the barriers every year since 2020.

**Writing Skill — Introductory Paragraph:**
- **Hook**: 趣味问题、惊人事实、场景描写
- **Thesis statement**: 点明文章主旨，位于段尾

**Writing Skill — Concluding Paragraph:**
- 总结句（改写中心论点）+ 收尾思考（预测/提问）
''',
    ],
  );
}
