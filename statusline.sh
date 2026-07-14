#!/usr/bin/env bash
# Claude Code Status Line — 多家 AI 訂閱額度儀表板
# 顯示 Claude / Codex (ChatGPT) / Grok 的模型與額度狀態。
# 安裝方式見 README.md。無任何外部依賴（只需 jq、curl）。

input=$(cat)

# ── ANSI color helpers ────────────────────────────────────────────────────────
RED=$'\e[31m'
YELLOW=$'\e[33m'
GREEN=$'\e[32m'
ORANGE=$'\e[38;5;208m'
CYAN=$'\e[36m'
MAGENTA=$'\e[35m'
DIM=$'\e[2m'
BOLD=$'\e[1m'
RESET=$'\e[0m'

# ── Model & context ───────────────────────────────────────────────────────────
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
ctx_size=$(echo "$input" | jq -r '
  .context_window.context_window_size
  | if . >= 1000000 then "\(. / 1000000 | floor)M"
    elif . >= 1000 then "\(. / 1000 | floor)K"
    else tostring
    end
')
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# ── Context 漸層色進度條 ───────────────────────────────────────────────────────
# 顏色：0-50% 綠，50-70% 黃，70-85% 橘，85%+ 紅
build_progress_bar() {
  local pct="${1:-0}"
  local pct_int
  pct_int=$(printf "%.0f" "$pct")
  local bar_width=20
  local filled=$(( pct_int * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  local empty=$(( bar_width - filled ))

  local color
  if [ "$pct_int" -ge 85 ]; then
    color="$RED"
  elif [ "$pct_int" -ge 70 ]; then
    color="$ORANGE"
  elif [ "$pct_int" -ge 50 ]; then
    color="$YELLOW"
  else
    color="$GREEN"
  fi

  local bar_filled=""
  local bar_empty=""
  local i
  for (( i=0; i<filled; i++ )); do bar_filled+="█"; done
  for (( i=0; i<empty; i++ )); do bar_empty+="░"; done

  printf "${color}[${bar_filled}${DIM}${bar_empty}${RESET}${color}]${RESET} ${color}${pct_int}%%${RESET}"
}

if [ -n "$ctx_used" ]; then
  ctx_bar=$(build_progress_bar "$ctx_used")
else
  ctx_bar="${DIM}[░░░░░░░░░░░░░░░░░░░░] –${RESET}"
fi

# ── Git info ──────────────────────────────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')

git_branch_str=""
git_diff_str=""

if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
               || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

  staged_stat=$(git -C "$cwd" diff --no-lock-index --cached --numstat 2>/dev/null \
                | awk '{a+=$1; d+=$2} END {print a+0, d+0}')
  staged_added=$(echo "$staged_stat" | cut -d' ' -f1)
  staged_deleted=$(echo "$staged_stat" | cut -d' ' -f2)

  unstaged_stat=$(git -C "$cwd" diff --no-lock-index --numstat 2>/dev/null \
                  | awk '{a+=$1; d+=$2} END {print a+0, d+0}')
  unstaged_added=$(echo "$unstaged_stat" | cut -d' ' -f1)
  unstaged_deleted=$(echo "$unstaged_stat" | cut -d' ' -f2)

  total_added=$(( ${staged_added:-0} + ${unstaged_added:-0} ))
  total_deleted=$(( ${staged_deleted:-0} + ${unstaged_deleted:-0} ))

  has_untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | head -1)

  dirty=""
  { [ "$total_added" -gt 0 ] || [ "$total_deleted" -gt 0 ] || [ -n "$has_untracked" ]; } \
    && dirty="${YELLOW}*${RESET}"

  git_branch_str="${MAGENTA}${git_branch}${RESET}${dirty}"

  if [ "$total_added" -gt 0 ] || [ "$total_deleted" -gt 0 ]; then
    git_diff_str="${GREEN}+${total_added}${RESET}/${RED}-${total_deleted}${RESET}"
  fi
fi

# ── 專案名稱 ──────────────────────────────────────────────────────────────────
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // ""')
if [ -n "$project_dir" ]; then
  project_name=$(basename "$project_dir")
else
  project_name=""
fi

# ── 最後訊息時間（選裝：由 UserPromptSubmit hook 寫入，見 README）────────────
session_id=$(echo "$input" | jq -r '.session_id // empty')
last_msg_time=""
if [ -n "$session_id" ]; then
  ts_file="/tmp/claude-last-prompt-${session_id}.txt"
  if [ -f "$ts_file" ]; then
    last_msg_time=$(cat "$ts_file" 2>/dev/null)
  fi
fi

# ── Line 1：模型 | context 進度條 ────────────────────────────────────────────
# STATUSLINE_PREFIX：可選的行首裝飾（如 emoji），在 settings.json 的 command 裡設定
line1="${BOLD}${STATUSLINE_PREFIX:-}${model} ${DIM}(${ctx_size})${RESET} ${DIM}|${RESET} ${ctx_bar}"

# ── Line 2：專案 | git 分支 + 髒標記 | 增刪行 | 時間 ────────────────────────
line2_parts=()
[ -n "$project_name" ] && line2_parts+=("${CYAN}${project_name}${RESET}")
[ -n "$git_branch_str" ] && line2_parts+=("${git_branch_str}")
[ -n "$git_diff_str" ] && line2_parts+=("${git_diff_str}")

if [ -n "$last_msg_time" ]; then
  line2_parts+=("${DIM}最後: ${last_msg_time}${RESET}")
else
  now=$(date +%H:%M)
  line2_parts+=("${DIM}${now}${RESET}")
fi

line2=$(printf '%s' "${line2_parts[0]}")
for part in "${line2_parts[@]:1}"; do
  line2="${line2} ${DIM}|${RESET} ${part}"
done

# ── AI 額度區塊：Claude / Codex / Grok ───────────────────────────────────────
build_dots() {
  local pct="${1:-0}"
  local pct_int
  pct_int=$(printf "%.0f" "$pct")
  local width=10
  local filled=$(( pct_int * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$(( width - filled ))

  local color
  if [ "$pct_int" -ge 85 ]; then color="$RED"
  elif [ "$pct_int" -ge 70 ]; then color="$ORANGE"
  elif [ "$pct_int" -ge 50 ]; then color="$YELLOW"
  else color="$GREEN"
  fi

  local filled_str="" empty_str="" i
  for (( i=0; i<filled; i++ )); do filled_str+="█"; done
  for (( i=0; i<empty; i++ )); do empty_str+="░"; done

  printf "%s%s%s%s%s %s%3d%%%s" "$color" "$filled_str" "$DIM" "$empty_str" "$RESET" "$color" "$pct_int" "$RESET"
}

# epoch → "↺1h05m" / "↺3d4h" / "↺45m"；輸入非正整數則空字串
fmt_reset() {
  local reset_ts="${1:-0}"
  case "$reset_ts" in ''|*[!0-9]*) return ;; esac
  local secs_left=$(( reset_ts - $(date +%s) ))
  [ "$secs_left" -le 0 ] && return
  local mins_left=$(( secs_left / 60 )) hrs_left=$(( secs_left / 3600 )) days_left=$(( secs_left / 86400 ))
  if [ "$days_left" -gt 0 ]; then
    printf "↺%dd%dh" "$days_left" $(( (secs_left % 86400) / 3600 ))
  elif [ "$hrs_left" -gt 0 ]; then
    printf "↺%dh%02dm" "$hrs_left" $(( mins_left % 60 ))
  else
    printf "↺%dm" "$mins_left"
  fi
}

# model slug → 顯示名："gpt-5.6-sol" → "GPT 5.6 Sol"、"grok-4.5" → "Grok 4.5"
pretty_model() {
  echo "$1" | awk -F- '{for(i=1;i<=NF;i++){w=$i; if(w=="gpt")w="GPT"; else w=toupper(substr(w,1,1)) substr(w,2); printf "%s%s", w, (i<NF?" ":"")}}'
}

quota_row() {
  local label="$1" pct="$2" reset_ts="$3"
  [ -z "$pct" ] && return
  local rst
  rst=$(fmt_reset "$reset_ts")
  printf '  %-8s %s %s%s%s\n' "$label" "$(build_dots "$pct")" "$DIM" "$rst" "$RESET"
}

quota_lines=""

# ── Claude：直接讀 statusline JSON 帶的 rate_limits ──────────────────────────
claude_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
claude_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
claude_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
claude_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
if [ -n "$claude_5h" ] || [ -n "$claude_7d" ]; then
  quota_lines="${quota_lines}${BOLD}Claude${RESET} ${DIM}(${model})${RESET}\n"
  quota_lines="${quota_lines}$(quota_row current "$claude_5h" "$claude_5h_reset")\n"
  quota_lines="${quota_lines}$(quota_row weekly "$claude_7d" "$claude_7d_reset")\n"
fi

# ── Codex (ChatGPT 訂閱)：自動偵測 ~/.codex 與 ~/.codex-*（多帳號）──────────
# 額度來源 chatgpt.com/backend-api/wham/usage，/tmp 快取 5 分鐘。
# curl --max-time 3、非 200 保留舊快取，statusline 絕不因網路問題卡住。
# 視窗標籤由 limit_window_seconds 推導（OpenAI 2026-07 取消 5H 後 primary 為 7 天）
CODEX_TTL=300
win_label() { [ "${1:-0}" -ge 518400 ] && echo weekly || echo current; }

seen_accts=" "
for chome in "$HOME/.codex" "$HOME"/.codex-*; do
  [ -f "$chome/auth.json" ] || continue
  # 同一個 ChatGPT 帳號登入多個 CODEX_HOME 時只顯示一次（額度是同一池）
  aid=$(jq -r '.tokens.account_id // empty' "$chome/auth.json")
  case "$seen_accts" in *" $aid "*) continue ;; esac
  seen_accts="${seen_accts}${aid} "
  suffix="${chome##*/.codex}"     # "" 或 "-a"
  suffix="${suffix#-}"            # "" 或 "a"
  label="Codex${suffix:+ ${suffix}}"
  cache="/tmp/codex-usage-${suffix:-default}.json"

  # 快取過期才打 API；token 過期（401）時沿用舊快取，跑任一 codex 指令會刷新 token
  age=99999
  [ -f "$cache" ] && age=$(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache") ))
  if [ "$age" -ge "$CODEX_TTL" ]; then
    token=$(jq -r '.tokens.access_token // empty' "$chome/auth.json")
    acct_id=$(jq -r '.tokens.account_id // empty' "$chome/auth.json")
    if [ -n "$token" ]; then
      http=$(curl -s -o "$cache.tmp" -w "%{http_code}" --max-time 3 \
        -H "Authorization: Bearer $token" -H "chatgpt-account-id: $acct_id" \
        "https://chatgpt.com/backend-api/wham/usage" 2>/dev/null)
      if [ "$http" = "200" ]; then mv "$cache.tmp" "$cache"; else rm -f "$cache.tmp"; fi
    fi
  fi
  [ -f "$cache" ] || continue

  # model：config.toml 有 pin 就用它，否則取最新 session rollout 記錄的實際值
  sess=$(ls -t "$chome/sessions/"*/*/*/*.jsonl 2>/dev/null | head -1)
  cmodel=$(grep -m1 '^model *=' "$chome/config.toml" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
  [ -z "$cmodel" ] && [ -n "$sess" ] && cmodel=$(grep -m1 -o '"model":"[^"]*"' "$sess" | head -1 | cut -d'"' -f4)
  [ -n "$cmodel" ] && cmodel=$(pretty_model "$cmodel")
  # effort：config 的 model_reasoning_effort 或 session 記錄；都沒有（CLI 預設）就不顯示
  ceff=$(grep -m1 '^model_reasoning_effort' "$chome/config.toml" 2>/dev/null | sed -E 's/.*"([a-z]+)".*/\1/')
  [ -z "$ceff" ] && [ -n "$sess" ] && ceff=$(grep -m1 -o '"reasoning_effort":"[a-z]*"' "$sess" | cut -d'"' -f4)
  [ -n "$ceff" ] && ceff=$(echo "$ceff" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

  p5=$(jq -r '.rate_limit.primary_window.used_percent // empty' "$cache")
  r5=$(jq -r '.rate_limit.primary_window.reset_at // empty' "$cache")
  w5=$(jq -r '.rate_limit.primary_window.limit_window_seconds // 0' "$cache")
  p7=$(jq -r '.rate_limit.secondary_window.used_percent // empty' "$cache")
  r7=$(jq -r '.rate_limit.secondary_window.reset_at // empty' "$cache")
  w7=$(jq -r '.rate_limit.secondary_window.limit_window_seconds // 0' "$cache")
  [ -z "$p5" ] && continue
  quota_lines="${quota_lines}${BOLD}${label}${RESET}${cmodel:+ ${DIM}(${cmodel})${RESET}}${ceff:+ ${ceff}}\n"
  quota_lines="${quota_lines}$(quota_row "$(win_label "$w5")" "$p5" "$r5")\n"
  [ -n "$p7" ] && quota_lines="${quota_lines}$(quota_row "$(win_label "$w7")" "$p7" "$r7")\n"
done

# ── Grok：無公開用量 API，僅在有安裝 grok CLI 時顯示登入狀態 ─────────────────
if [ -d "$HOME/.grok" ]; then
  gmodel=$(jq -r '.models | keys_unsorted[0] // empty' "$HOME/.grok/models_cache.json" 2>/dev/null)
  [ -n "$gmodel" ] && gmodel=$(pretty_model "$gmodel")
  if [ -f "$HOME/.grok/auth.json" ]; then
    quota_lines="${quota_lines}${BOLD}Grok${RESET}${gmodel:+ ${DIM}(${gmodel})${RESET}}  ${GREEN}✓ 已登入${RESET} ${DIM}· 無額度資訊${RESET}\n"
  else
    quota_lines="${quota_lines}${BOLD}Grok${RESET}    ${DIM}⚠ 未登入${RESET}\n"
  fi
fi

# ── Output ────────────────────────────────────────────────────────────────────
printf '%s\n%s\n' "$line1" "$line2"
[ -n "$quota_lines" ] && printf '%b' "$quota_lines"
