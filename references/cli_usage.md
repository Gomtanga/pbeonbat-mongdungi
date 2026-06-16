# 로컬 Claude/Codex CLI 사용 가이드

이 파일은 `pbeonbat-mongdungi` 스킬에서 로컬 CLI를 실제로 호출해야 할 때 읽는다. 기본 워크플로우는 SKILL.md만으로 충분하다 — CLI 디테일이 필요해지면 여기로 온다.

---

## 0. 철학: CLI는 검증 파트너다

이 스킬이 CLI를 부르는 이유는 "대신 일하게 하려고"가 아니다. **내 추론을 보완하는 제2의 시니어 엔지니어**로 쓰려는 것이다. 핵심 원칙:

1. **CLI는 컨설팅만 한다.** 결과는 항상 사용자에게 보여주고, 실행은 내가 한다.
2. **읽기 전용이 기본.** 파일 변경 권한은 주지 않는다 (원칙 3: surgical change 위반 방지).
3. **빠르고 좁게.** 한 번에 하나의 구체적 질문만. 긴 프롬프트는 비용만 키운다.
4. **실패는 조용히 넘기지 않는다.** CLI가 응답하지 않으면 솔직히 말한다.

---

## 1. CLI 찾기

직접 경로를 하드코딩하지 마라. 항상 `detect_cli.sh`를 통해 동적으로 얻는다.

```bash
# 변수로 받기 (스크립트 안에서)
SKILL_DIR="${OPENCODE_SKILLS_DIR:-$HOME/.config/opencode/skills}/pbeonbat-mongdungi"
eval "$(bash "$SKILL_DIR/scripts/detect_cli.sh" --eval)"

# 이제 $CLAUDE_CLI, $CODEX_CLI 사용 가능
if [[ -n "$CLAUDE_CLI" ]]; then
    echo "Claude: $CLAUDE_CLI ($CLAUDE_VERSION)"
fi
```

```bash
# JSON으로 받기 (파이프라인에서)
bash detect_cli.sh --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['claude_cli'])"
```

```bash
# 존재 여부만 (exit code: 0=둘 다, 1=일부만, 2=둘 다 없음)
bash detect_cli.sh --check-only && echo "둘 다 있음"
```

**디텍션 실패 시**: 스킬은 계속 작동한다 — CLI 없이 내가 직접 검증한다. 사용자에게 "CLI를 못 찾아서 직접 검증합니다"라고 솔직히 알린다.

---

## 2. Claude Code CLI 호출

### 기본: non-interactive 질문 (`-p` / `--print`)

```bash
"$CLAUDE_CLI" -p "간결한 질문"
```

`-p` 모드는 대화형 세션을 열지 않고 한 번에 출력한다. 스크립트/자동화에 적합.
**참고**: `-p` 모드에서는 workspace trust 다이얼로그가 자동 스킵된다 — 신뢰하는 디렉토리에서만 쓸 것.

### 중요: 프롬프트는 항상 마지막 인자 또는 stdin

Claude CLI는 `--tools ""` 같은 빈 문자열 플래그 값을 prompt로 오인하는 모호함이 있다.
안전한 패턴:

- **플래그 전부 → 프롬프트 인자 순서** (`"$CLAUDE_CLI" -p --tools "" "질문"`). 순서가 바뀌면 에러.
- **또는 stdin으로 프롬프트 넘기기** (가장 안전):

```bash
echo "질문" | "$CLAUDE_CLI" -p --tools ""
# 또는 heredoc
"$CLAUDE_CLI" -p --tools "" <<EOF
긴 프롬프트도 이렇게 넘긴다.
EOF
```

### 읽기 전용 (권장)

파일을 변경하지 못하게 막는다. 안전 기본값. 두 가지 방식:

**방식 A — 도구를 아예 끄기 (순수 추론만, 가장 안전)**:

```bash
"$CLAUDE_CLI" -p --tools "" "질문"
# 또는 stdin
echo "질문" | "$CLAUDE_CLI" -p --tools ""
```

`--tools ""`는 모든 도구를 비활성화. CLI는 주어진 텍스트만 보고 답한다. 빠르고 안전하다.

**방식 B — 읽기 도구만 허용 (코드 리뷰/탐색용)**:

```bash
"$CLAUDE_CLI" -p --allowedTools "Read,Grep,Glob" "질문"
```

읽기 도구만 주면 안전하게 컨텍스트를 읽고 분석할 수 있다. Edit/Write/Bash는 빠진다.

### 디렉토리 컨텍스트 추가

특정 디렉토리를 읽을 수 있게 허용:

```bash
"$CLAUDE_CLI" -p \
    --add-dir "/path/to/project/src" \
    --allowedTools "Read,Grep,Glob" \
    "이 디렉토리의 auth 모듈을 리뷰해줘"
```

### 시스템 프롬프트 보강

Karpathy 원칙을 CLI에게도 주입하면 일관된 검증을 해준다:

```bash
"$CLAUDE_CLI" -p \
    --append-system-prompt "당신은 시니어 엔지니어입니다. 다음 원칙으로 코드를 리뷰하세요: (1) 단순성 - 불필요한 추상화 의심, (2) 수술적 변경 - 인접 코드 건드림 의심, (3) 명시적 가정 - 숨은 가정 찾기. 3문장 이내로 핵심만 지적하세요." \
    "코드: $(cat path/to/file.py)"
```

### 프롬프트를 파일로 넘기기 (긴 프롬프트)

stdin이나 파일로 주면 아규먼트 폭발을 막는다:

```bash
"$CLAUDE_CLI" -p --allowedTools "Read" < prompt.txt
```

또는 heredoc:

```bash
"$CLAUDE_CLI" -p --allowedTools "Read" <<EOF
다음 diff를 리뷰해줘. 원칙 3 (surgical change) 위반 라인을 찾아.

$(git diff)
EOF
```

### 출력을 변수로 받기

```bash
result=$("$CLAUDE_CLI" -p --allowedTools "" "질문" 2>/dev/null)
echo "$result"
```

`2>/dev/null`은 진행 표시줄 같은 노이즈를 제거한다. 단, 에러도 사라지니 디버깅 시엔 빼라.

---

## 3. Codex CLI 호출

### 기본: non-interactive (`exec`)

```bash
"$CODEX_CLI" exec "간결한 질문"
```

`exec` 서브커맨드가 non-interactive 실행 모드다.

### 읽기 전용 (안전 기본)

```bash
"$CODEX_CLI" exec \
    --skip-git-repo-check \
    --sandbox read-only \
    "질문"
```

핵심 플래그:
- `--skip-git-repo-check` — git 레포 밖에서도 실행 (없으면 "Not inside a trusted directory" 에러).
- `--sandbox read-only` — 읽기 전용 샌드박스. 파일 변경 차단.
- `-C <dir>` / `--cd <dir>` — 작업 디렉토리 지정.
- `--add-dir <dir>` — 추가 쓰기 디렉토리 (필요할 때만).
- `-o <file>` / `--output-last-message <file>` — 마지막 메시지를 파일로. 파이핑 대신 유용.
- `--json` — JSONL 이벤트 스트림 (파싱 필요 시).

### 결과를 변수로 받기

```bash
result=$("$CODEX_CLI" exec --skip-git-repo-check --sandbox read-only "질문" 2>/dev/null)
echo "$result"
```

### Codex의 특성

- Claude보다 **가볍고 빠르다**는 평가. 단순 구현/빠른 질문에 적합.
- 반면 복잡한 다단계 추론이나 리뷰는 Claude가 일반적으로 우위.

**선택 휴리스틱**:
- "이 함수 구현해줘" / "이거 맞아?" → Codex
- "이 diff 리뷰해줘" / "두 접근 비교해줘" / "아키텍처 고민이야" → Claude
- 헷갈리면 Claude. 비용이 크게 차이 안 난다.

---

## 4. 호출 패턴 레시피

자주 쓰는 패턴. 스킬 본문에서 이 형태로 부르면 된다.

### 레시피 A: diff 리뷰 (원칙 3 검증)

구현을 끝낸 후, 내 diff가 surgical 원칙을 지켰는지 확인.

```bash
eval "$(bash detect_cli.sh --eval)"

"$CLAUDE_CLI" -p \
    --tools "" \
    --append-system-prompt "코드 리뷰어. 3문장 이내. 원칙 3(surgical changes) 위반 라인만 지적. 칭찬은 생략." \
    <<EOF
이 diff를 리뷰해줘. 사용자가 요청한 변경과 직접 관련 없는 라인이 있는지 찾아.

$(git diff)
EOF
```

### 레시피 B: 단순성 검증 (원칙 2)

내 구현이 과도하게 복잡한지 확인.

```bash
"$CLAUDE_CLI" -p \
    --allowedTools "Read,Grep,Glob" \
    --add-dir "$(pwd)/src" \
    "내가 방금 구현한 src/foo.ts를 봐. 단일 사용 코드를 추상화했거나, 불필요한 구성 가능성을 넣었는지 지적해. 3문장 이내."
```

### 레시피 C: 두 접근의 tradeoff

구현 전 방향 결정이 막혔을 때.

```bash
"$CLAUDE_CLI" -p \
    --tools "" \
    "A 방식: 마이크로서비스 분리. B 방식: 모놀리스 단일 파일. 요구사항: [간략 설명]. 어느 쪽이 적합한지, 왜 그런지 3문장으로."
```

### 레시피 D: 빠른 second opinion (Codex)

```bash
"$CODEX_CLI" exec \
    --skip-git-repo-check \
    --sandbox read-only \
    "이 함수는 입력이 비어 있을 때 None을 반환하는 게 맞아, 아니면 예외를 던지는 게 맞아? 컨텍스트: [한 줄]. 한 문장으로."
```

### 레시피 E: 버그 재현 가설

재현이 안 되는 버그.

```bash
"$CLAUDE_CLI" -p \
    --allowedTools "Read,Grep,Glob" \
    --add-dir "$(pwd)" \
    <<EOF
에러: [메시지]
파일: path/to/module.py
이 버그의 가능한 원인 3개를 가설로 제시해. 각각 어떻게 검증할 수 있는지도.
EOF
```

### 레시피 F: Codex로 파일 컨텍스트와 함께 질문

디렉토리를 지정해서 읽게 하려면:

```bash
"$CODEX_CLI" exec \
    --skip-git-repo-check \
    --sandbox read-only \
    -C "$(pwd)" \
    "src/auth.py에서 토큰 검증 로직을 읽고, 가장 의심되는 보안 이슈 하나를 지적해. 2문장."
```

---

## 5. 안전 규칙 (다시 한번)

1. **절대 CLI가 파일을 쓰게 두지 마라.** `--allowedTools ""` 또는 읽기 전용 도구만.
2. **CLI 결과를 사용자에게 보여줘라.** "Claude CLI가 이렇게 말했어" 형태로. 블라인드 적용 금지.
3. **CLI 실패를 숨기지 마라.** timeout, 에러, 빈 응답 — 솔직하게 보고.
4. **비용을 의식해라.** 한 줄 질문에 30초 CLI 호출은 낭비. 진짜 가치 있는 검증에만.

---

## 6. 실패 처리

### CLI가 응답하지 않을 때

```bash
result=$(timeout 30 "$CLAUDE_CLI" -p "질문" 2>/dev/null)
if [[ -z "$result" ]]; then
    echo "CLI 응답 없음. 직접 검증합니다."
    # fallback: 내가 직접 검증
fi
```

### CLI가 로그인되어 있지 않을 때

Claude Code CLI는 자체 인증을 쓴다 (Anthropic 계정 또는 API 키). Codex도 마찬가지.
둘 중 하나가 "Not logged in" / "auth" 에러를 띄우면:

1. 사용자에게 솔직히 알린다: "Claude CLI가 로그인되어 있지 않아 호출을 건너뛰어요."
2. fallback으로 내가 직접 검증을 진행한다.
3. (선택) 설치/로그인 방법 안내: `claude /login` 또는 `codex login`.

**절대**: 인증 에러를 무시하거나 숨기지 마라. CLI를 쓸 수 없다는 건 사용자가 알아야 할 정보다.

### CLI가 설치되지 않았을 때

`detect_cli.sh`가 빈 값을 반환하면, 스킬은 CLI 없이 작동한다:

```bash
eval "$(bash detect_cli.sh --eval)"
if [[ -z "$CLAUDE_CLI" ]]; then
    # CLI 없음 — 스킬 본문의 원칙들로만 검증
    echo "로컬 Claude CLI가 없어 직접 검증합니다."
fi
```

사용자에게 "설치하면 더 강력한 검증이 가능하다" 정도로만 안내. 강요하지 마라.

---

## 7. 성능/비용 휴리스틱

| 작업 유형 | 추천 CLI | 예상 소요 | 비용 |
|---|---|---|---|
| 빠른 1문장 확인 | Codex `exec` | 3-10초 | 낮음 |
| 함수 1개 구현 제안 | Codex `exec` | 5-20초 | 낮음 |
| Diff 리뷰 | Claude `-p` | 10-30초 | 중간 |
| 아키텍처 트레이드오프 | Claude `-p` | 15-45초 | 중간~높음 |
| 전체 파일 리팩토링 설계 | Claude `-p` + `--add-dir` | 30-90초 | 높음 |

**비용 절감 팁**:
- 프롬프트는 좁고 구체적으로. "도와줘"보다 "이 5줄에서 N+1 쿼리 찾아줘".
- `--append-system-prompt`로 출력 길이를 제한 ("3문장 이내").
- 읽기 도구만 줘서 불필요한 탐색을 막는다.

---

## 8. 워크플로우 통합 체크리스트

실제 작업에서 CLI를 언제 끼워넣을지 요약.

- [ ] **Phase 0 (생각)**: 두 접근이 갈리면 → Claude에게 tradeoff 질문
- [ ] **Phase 1 (구현)**: 가능하면 CLI 안 부름. 혼자 해결이 보통 더 빠름
- [ ] **Phase 2 (검증)**: diff가 20줄 이상이면 → Claude에게 원칙 3 위반 검사
- [ ] **Phase 2**: 복잡한 로직이면 → Codex에게 빠른 second opinion
- [ ] **Phase 3 (보고)**: CLI 결과를 사용자에게 투명하게 공유

이 체크리스트를 습관화하면, CLI는 과용되지도 부족하지도 않게 쓰인다.
