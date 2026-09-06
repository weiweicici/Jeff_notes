# 邮箱云账号连接与验证

本功能连接的是 Supabase 云笔记账号，不是 Apple ID、Sideloadly 签名账号或 AI API Key。
原始录音仍保存在录音设备本地；本流程不会新增原始音频云备份。

## 首次连接顺序

1. 先保留 iPad 上能看到旧云笔记的 App 和数据，不卸载、不清空。
2. 打开主页设置的云账号面板，检查是否仍有有效匿名云账号。
3. 若有，在该 iPad 上选择“绑定当前云账号”，填写自己的邮箱并完成邮箱验证。绑定必须保持原云用户 ID 不变，不能用新建账号代替。
4. 在 iPhone 上选择“登录已有邮箱”，使用刚绑定的同一个邮箱。此入口禁止自动注册新账号。
5. 阅读并确认本机待同步笔记将上传到所登录账号，再提交邮件验证码。
6. 对照两台设备面板中的云账号 ID，并检查一条新测试笔记的云端回执及 iPad 可见性。

若 iPad 也没有有效云会话，旧列表可能包含本地缓存，不能据此认定仍能绑定原云账号。
此时停止绑定，保留两台设备本地文件，再核实原云身份。不要新建空账号或修改旧行的 `user_id`。

若手机已经显示另一个有效云账号，本版不会直接替换它；应先核实两边数据归属。
邮箱填错且尚未提交验证码时可以取消请求。开始验证后，失败或超时会继续暂停上传；重启不会绕过保护，需完成原邮箱验证。
请使用邮件中的数字验证码；本版不会通过点击链接自动切换 App 内的云身份。

## Supabase 后台前置条件

客户端代码不能证明这些设置已完成；需要项目管理员检查。不要在聊天或诊断日志中粘贴服务密钥、登录令牌或验证码。

- Email provider 已启用。开发时只读 `/auth/v1/settings` 确认该项目 `external.email = true`、`mailer_autoconfirm = false`；没有发送真实邮件。
- 要将匿名用户转换为邮箱用户，启用项目的 **manual identity linking**。本次客户端开发不自动修改此开关。
- 邮件模板 **Magic Link**（已有邮箱登录）与 **Change Email Address**（绑定邮箱）需要显示 OTP：`{{ .Token }}`。
- 可在原模板中加入下列片段，保留模板已有内容和品牌信息：

```html
<p>Jeff Notes 验证码：</p>
<p style="font-size:24px;letter-spacing:4px">{{ .Token }}</p>
<p>请回到 Jeff Notes 输入验证码。不要把验证码发送给他人。</p>
```

- 验证邮件投递权限、SMTP/收件人限制和发送频率。收到请求成功的响应不等于邮件一定送达；不要不断重发。
- 如果邮件只有确认链接而没有验证码，先调整对应模板；不要把完整登录链接或令牌贴入聊天。
- 保持 archives 的按用户隔离策略，不要为了同步关闭 RLS 或允许跨用户读取。
- 云上传需要已有 `archives(user_id, session_id)` 唯一约束与对应字段。本地存在 `20260731_session_id_upsert.sql`，不等于已确认线上迁移状态；本次没有执行数据库迁移。

参考：[匿名账号绑定](https://supabase.com/docs/guides/auth/auth-anonymous)、[邮件模板](https://supabase.com/docs/guides/auth/auth-email-templates)、[Flutter OTP 登录](https://supabase.com/docs/reference/dart/auth-signinwithotp)。

## 必须区分的验证证据

- Fake adapter / 本地回归测试：证明错误码、身份检查、状态机与数据保护逻辑，不证明实际发信或跨设备成功。
- Release 构建、IPA 检查：证明可编译及打包结构，不证明已安装或已上云。
- 真实验收：iPad 绑定前后用户 ID 不变；iPhone 验证后 ID 与 iPad 相同；本机测试笔记收到匹配云回执，且 iPad 刷新后可见；原有云笔记仍在。

本流程不删除本地文件，不自动迁移旧云账号的数据，不自动覆盖其他账号的数据。
