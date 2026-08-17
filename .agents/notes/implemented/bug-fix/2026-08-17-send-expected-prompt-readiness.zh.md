# Agent Note: 由 send 声明的 `expectedPrompt` 恢复精确 PTY 就绪

Status: implemented

[English](2026-08-17-send-expected-prompt-readiness.md) | 中文

## Problem

`tool-bash-persistent` 在 spawn 后立即通过一条初始化 send 把 `PS1` 换成私有提示符 `__DSH_PERSISTENT_BASH_PROMPT__ `，而 `terminal-bash` 把精确提示符就绪钉死在它自己的受控提示符 `dsh> ` 上。对该工具而言，私有 OSC 标记之后的可打印尾部永远不会匹配，精确就绪路径因此从不触发，每条快速命令都改走 `idleSilenceMs + handoffGraceMs`（默认配置下 3.5 秒）的静默回退。会话的第一次 `bash` 调用要付两次回退代价：提示符赋值 send 一次，命令本身一次。

## Decision

`TerminalSendRequest` 新增可选字段 `expectedPrompt`：改变 `PS1` 的 send 预期就绪时匹配的提示符文本。`LocalPtySession` 用活跃 send 声明的文本做标记后尾部比较，未声明时回落到受控提示符，并在 send 清理时复位到受控提示符。`tool-bash-persistent` 在初始化 send 和每条命令 send 上声明它的 `SHELL_PROMPT`，由改变提示符的一层通知后端；`initialize()` 不做声明，启动就绪仍匹配 spawn 时的 `PS1`。

## Alternatives considered

- **把后端常量改成工具的提示符**（流传的补丁写法）：把通用后端耦合到某个消费方的私有提示符，并改变所有其他 `shell` 类型会话（包括交互式 `tool-terminal` 终端）可见的提示符。
- **去掉工具的 `PS1` 覆盖、复用 `dsh> `**：削弱工具的输出处理——`stripPrompt`、`promptCompleted` 和截断 scrollback 的 `replaceAll` 路径会匹配一个命令输出很可能包含的五字符字符串；nonce 标记设计以独特提示符为前提。
- **在回退结算后动态学习提示符**：调用方本就静态知道这个事实，该方案却换成一个输入（回显输入、迟到标记）不可靠的变更状态机。
- **在各个 cordis.yml 里配置后端字段**：把一个包的私有常量复制进每个预设，配置漂移会静默重新引入回退。

## Consequences

经过 `tool-bash-persistent` 的快速 `bash` 命令重新走精确就绪——约一个轮询间隔，而不是 3.5 秒静默回退——包括初始化 send。该字段是可选的，注册表原样转发请求，其他发送方与后端不受影响。契约按 send 生效：改变 `PS1` 的消费方必须在之后的每条 send 上声明提示符；未声明的 send 仍回退到静默就绪，而不会按过期提示符错误结算。
