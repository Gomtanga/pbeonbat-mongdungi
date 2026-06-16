#!/usr/bin/env bash
# detect_cli.sh — 편백나무 몽둥이 스킬용 CLI 디텍션 래퍼
#
# 로컬에 설치된 Claude Code CLI와 Codex CLI를 찾아 경로와 버전을 출력한다.
# SKILL.md에서는 이 스크립트를 source-equivalent 방식으로 호출해 동적 경로를 얻는다.
#
# 사용법:
#   bash detect_cli.sh                # 사람이 읽기 쉬운 형태로 출력
#   bash detect_cli.sh --eval         # eval "$(bash detect_cli.sh --eval)" 로 쓰면 변수가 export 됨
#   bash detect_cli.sh --json         # JSON 형태 출력 (다른 스크립트에서 파싱하기 좋음)
#   bash detect_cli.sh --check-only   # 발견 여부만 exit code로 (0: 둘 다 있음, 1: 일부만, 2: 둘 다 없음)
#
# 탐색 순서 (각 CLI):
#   1. PATH에 이미 있는지 (claude / codex)
#   2. npm 글로벌 (npm prefix -g)/bin
#   3. ~/.local/bin
#   4. Homebrew (/opt/homebrew/bin, /usr/local/bin)
#   5. Claude.app 번들 내부 (claude-code 버전 디렉토리에서 가장 최신)
#   6. Codex.app 번들 내부 (Codex.app/Contents/Resources/codex)
#   7. bun 글로벌 (~/.bun/bin)
#   8. ~/.claude/skills 하위의 CLI 실행파일 (skill 설치 경로)
#
# 새 경로가 발견되면 이 스크립트에 추가한다.

set -uo pipefail

# --- 색상 (사람 읽기 모드에서만 사용)
if [[ -t 1 ]]; then
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
else
    GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi

# --- 결과 변수
CLAUDE_CLI=""
CLAUDE_VERSION=""
CODEX_CLI=""
CODEX_VERSION=""

# --- 헬퍼: 파일이 실행 가능한지 확인
is_executable() {
    [[ -f "$1" && -x "$1" ]]
}

# --- 헬퍼: 버전 문자열 추출. macOS엔 timeout이 기본 없고 gtimeout(GNU coreutils)만 있을 수 있어 폴백.
get_version() {
    local bin="$1"
    local ver=""

    local timeout_cmd=""
    if command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 5"
    elif command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 5"
    fi

    # shellcheck disable=SC2086
    ver=$($timeout_cmd "$bin" --version 2>/dev/null | head -1 | tr -d '\n')
    if [[ -z "$ver" ]]; then
        ver=$("$bin" --version 2>/dev/null | head -1 | tr -d '\n')
    fi
    echo "$ver"
}

# --- Claude CLI 탐색
find_claude() {
    # 1. PATH
    local p
    p=$(command -v claude 2>/dev/null)
    if [[ -n "$p" ]] && is_executable "$p"; then
        CLAUDE_CLI="$p"
        return
    fi

    # 2. npm 글로벌
    local npm_prefix
    npm_prefix=$(npm prefix -g 2>/dev/null)
    if [[ -n "$npm_prefix" && -x "$npm_prefix/bin/claude" ]]; then
        CLAUDE_CLI="$npm_prefix/bin/claude"
        return
    fi

    # 3. ~/.local/bin
    if is_executable "$HOME/.local/bin/claude"; then
        CLAUDE_CLI="$HOME/.local/bin/claude"
        return
    fi

    # 4. Homebrew
    for brew in /opt/homebrew/bin/claude /usr/local/bin/claude; do
        if is_executable "$brew"; then
            CLAUDE_CLI="$brew"
            return
        fi
    done

    # 5. Claude.app 내부 claude-code (최신 버전 디렉토리)
    local claude_code_base="$HOME/Library/Application Support/Claude-3p/claude-code"
    if [[ -d "$claude_code_base" ]]; then
        # 가장 높은 버전 디렉토리 선택
        local latest
        latest=$(ls -1 "$claude_code_base" 2>/dev/null | sort -V | tail -1)
        if [[ -n "$latest" ]]; then
            local candidate="$claude_code_base/$latest/claude.app/Contents/MacOS/claude"
            if is_executable "$candidate"; then
                CLAUDE_CLI="$candidate"
                return
            fi
        fi
    fi

    # 6. 구버전 위치들 (Claude.app Resources)
    local legacy="/Applications/Claude.app/Contents/Resources/claude"
    if is_executable "$legacy"; then
        CLAUDE_CLI="$legacy"
        return
    fi

    # 7. bun
    if is_executable "$HOME/.bun/bin/claude"; then
        CLAUDE_CLI="$HOME/.bun/bin/claude"
        return
    fi
}

# --- Codex CLI 탐색
find_codex() {
    # 1. PATH
    local p
    p=$(command -v codex 2>/dev/null)
    if [[ -n "$p" ]] && is_executable "$p"; then
        CODEX_CLI="$p"
        return
    fi

    # 2. npm 글로벌
    local npm_prefix
    npm_prefix=$(npm prefix -g 2>/dev/null)
    if [[ -n "$npm_prefix" && -x "$npm_prefix/bin/codex" ]]; then
        CODEX_CLI="$npm_prefix/bin/codex"
        return
    fi

    # 3. ~/.local/bin
    if is_executable "$HOME/.local/bin/codex"; then
        CODEX_CLI="$HOME/.local/bin/codex"
        return
    fi

    # 4. Homebrew
    for brew in /opt/homebrew/bin/codex /usr/local/bin/codex; do
        if is_executable "$brew"; then
            CODEX_CLI="$brew"
            return
        fi
    done

    # 5. Codex.app 번들 내부
    local candidate="/Applications/Codex.app/Contents/Resources/codex"
    if is_executable "$candidate"; then
        CODEX_CLI="$candidate"
        return
    fi

    # 6. bun
    if is_executable "$HOME/.bun/bin/codex"; then
        CODEX_CLI="$HOME/.bun/bin/codex"
        return
    fi
}

# --- 메인 로직 실행
find_claude
find_codex

# --- 버전 가져오기 (있을 경우만)
if [[ -n "$CLAUDE_CLI" ]]; then
    CLAUDE_VERSION=$(get_version "$CLAUDE_CLI" "claude")
fi
if [[ -n "$CODEX_CLI" ]]; then
    CODEX_VERSION=$(get_version "$CODEX_CLI" "codex")
fi

# --- 출력 모드 처리
mode="${1:-default}"

case "$mode" in
    --eval)
        # eval "$(bash detect_cli.sh --eval)" 용
        echo "export CLAUDE_CLI=$(printf '%q' "$CLAUDE_CLI")"
        echo "export CLAUDE_VERSION=$(printf '%q' "$CLAUDE_VERSION")"
        echo "export CODEX_CLI=$(printf '%q' "$CODEX_CLI")"
        echo "export CODEX_VERSION=$(printf '%q' "$CODEX_VERSION")"
        ;;
    --json)
        # cat <<EOF 보다 printf 가 안전
        printf '{"claude_cli":%s,"claude_version":%s,"codex_cli":%s,"codex_version":%s}\n' \
            "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$CLAUDE_CLI" 2>/dev/null || echo '""')" \
            "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$CLAUDE_VERSION" 2>/dev/null || echo '""')" \
            "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$CODEX_CLI" 2>/dev/null || echo '""')" \
            "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$CODEX_VERSION" 2>/dev/null || echo '""')"
        ;;
    --check-only)
        if [[ -n "$CLAUDE_CLI" && -n "$CODEX_CLI" ]]; then
            exit 0
        elif [[ -n "$CLAUDE_CLI" || -n "$CODEX_CLI" ]]; then
            exit 1
        else
            exit 2
        fi
        ;;
    *)
        # 사람 읽기 모드
        echo "${GREEN}[편백나무 몽둥이] CLI 디텍션 결과${RESET}"
        echo ""
        if [[ -n "$CLAUDE_CLI" ]]; then
            echo "  ${GREEN}✓ Claude Code CLI${RESET}"
            echo "    ${DIM}경로:${RESET} $CLAUDE_CLI"
            echo "    ${DIM}버전:${RESET} ${CLAUDE_VERSION:-알 수 없음}"
        else
            echo "  ${RED}✗ Claude Code CLI${RESET} ${DIM}(발견 안 됨)${RESET}"
        fi
        echo ""
        if [[ -n "$CODEX_CLI" ]]; then
            echo "  ${GREEN}✓ Codex CLI${RESET}"
            echo "    ${DIM}경로:${RESET} $CODEX_CLI"
            echo "    ${DIM}버전:${RESET} ${CODEX_VERSION:-알 수 없음}"
        else
            echo "  ${RED}✗ Codex CLI${RESET} ${DIM}(발견 안 됨)${RESET}"
        fi
        echo ""
        if [[ -z "$CLAUDE_CLI" && -z "$CODEX_CLI" ]]; then
            echo "  ${YELLOW}설치 가이드:${RESET}"
            echo "    Claude Code: ${DIM}npm install -g @anthropic-ai/claude-code${RESET}"
            echo "    Codex:       ${DIM}npm install -g @openai/codex${RESET}"
            echo "               또는 Codex.app / Claude.app 설치 후 이 스크립트 재실행"
        fi
        ;;
esac
