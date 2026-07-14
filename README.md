# claude-code-statusline

Claude Code 的多家 AI 訂閱額度儀表板 statusline。在終端底部一眼看到 **Claude / Codex (ChatGPT) / Grok** 的模型、額度用量與重置倒數。

```
Fable 5 (1M) | [█░░░░░░░░░░░░░░░░░░░] 4%
my-project | main* | +12/-3 | 14:28
Claude (Fable 5)
  current  ████░░░░░░  42% ↺4h12m
  weekly   ░░░░░░░░░░   2% ↺6d23h
Codex (GPT 5.5) High
  weekly   ██░░░░░░░░  25% ↺5d17h
Grok (Grok 4.5)  ✓ 已登入 · 無額度資訊
```

## 功能

- **Claude**：current（5 小時）與 weekly（7 天）額度、重置倒數——直接讀 Claude Code 傳給 statusline 的 JSON，零額外請求
- **Codex**：ChatGPT 訂閱額度（讀取 ChatGPT 網站目前使用的**未公開** usage 後端端點，可能隨服務更新變更；/tmp 快取 5 分鐘）；自動偵測 `~/.codex` 與 `~/.codex-*` 多帳號；顯示實際使用的 model 與 reasoning effort（有 pin 才顯示 effort）；額度視窗標籤由 API 回傳的視窗秒數自動推導
- **Grok**：xAI 沒有公開用量 API，只顯示登入狀態與預設 model；沒裝 grok CLI 就整段不顯示
- 進度條四階警示色：<50% 綠 / 50–69% 黃 / 70–84% 橘 / ≥85% 紅
- git 分支、增刪行數、專案名稱
- 網路慢或斷線不會卡 statusline（curl 3 秒上限、沿用舊快取）

## 需求

- macOS 或 Linux、bash、`jq`、`curl`
- Claude Code（statusline 資料來源）
- 選配：Codex CLI（ChatGPT 訂閱登入）、Grok CLI

## 安裝

```bash
mkdir -p ~/.claude
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/ryanjao/claude-code-statusline/v1.1/statusline.sh
chmod +x ~/.claude/statusline.sh
```

在 `~/.claude/settings.json` 加上（`refreshInterval` 讓時鐘與重置倒數在閒置時每 60 秒也會更新）：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "refreshInterval": 60
  }
}
```

重開 Claude Code 即生效。

### 選配：顯示「最後訊息時間」

預設第二行顯示當前時間。想改成「最後送出訊息的時間」，在 `~/.claude/settings.json` 加一個 UserPromptSubmit hook。注意 session id 要從 hook 的 **stdin JSON** 取（不是環境變數）：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sid=$(jq -r .session_id); [ -n \"$sid\" ] && date +%H:%M > \"/tmp/claude-last-prompt-${sid}.txt\""
          }
        ]
      }
    ]
  }
}
```

## 隱私說明

- 腳本只讀本機檔案（`~/.codex*/auth.json`、`~/.grok/`）與官方 usage API，**不傳送任何資料到第三方**
- Codex 額度快取寫在 `/tmp/codex-usage-*.json`，只含用量百分比，不含 token
- Codex token 過期時（401）statusline 會沿用舊快取；跑任一 codex 指令即自動刷新 token

## License

MIT
