#!/usr/bin/env bash
# Installs every tool from the "Claude video / repo" carousel in one go.
#
#   bash tools/install-all.sh                 # everything below
#   bash tools/install-all.sh --skip-whisper  # skip openai-whisper (pulls PyTorch, ~1-3 GB)
#   bash tools/install-all.sh --with-game-studios   # also clone Claude-Code-Game-Studios as a new project
#
# Needs: git, python3 + pip, node + npm, ffmpeg. The Claude Code CLI (`claude`)
# is used for plugins when present; otherwise plugins come from .claude/settings.json.
set -uo pipefail

SKIP_WHISPER=0
WITH_GAME_STUDIOS=0
for a in "$@"; do
  case "$a" in
    --skip-whisper) SKIP_WHISPER=1 ;;
    --with-game-studios) WITH_GAME_STUDIOS=1 ;;
    -h|--help) sed -n 2,10p "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

SKILLS_DIR="$HOME/.claude/skills"
SRC_DIR="${CLAUDE_TOOLS_SRC:-$HOME/.claude-tools-src}"
mkdir -p "$SKILLS_DIR" "$SRC_DIR"

ok=(); fail=()
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
run()  { local name="$1"; shift; if "$@"; then ok+=("$name"); else fail+=("$name"); fi; }

# clone_or_update <owner/repo> <dest>
clone_or_update() {
  if [ -d "$2/.git" ]; then git -C "$2" pull -q --ff-only
  else git clone -q --depth 1 "https://github.com/$1.git" "$2"; fi
}

# --- 1. Command-line tools -------------------------------------------------
step "yt-dlp (video downloader)"
run yt-dlp python3 -m pip install -q -U yt-dlp

if [ "$SKIP_WHISPER" = 0 ]; then
  step "openai-whisper (speech to text)"
  # CPU-only PyTorch is far smaller; fall back to the default index if that host is unreachable.
  python3 -m pip install -q torch --index-url https://download.pytorch.org/whl/cpu 2>/dev/null \
    || echo "   (CPU PyTorch index unreachable, using default PyPI torch)"
  run openai-whisper python3 -m pip install -q -U openai-whisper
fi

step "faster-whisper (lighter transcriber used by claude-shorts)"
run faster-whisper python3 -m pip install -q -U faster-whisper

step "HyperFrames CLI (HTML/CSS -> video)"
run hyperframes npm install -g --silent hyperframes

# --- 2. Claude Code plugins (marketplaces) ---------------------------------
# marketplace-repo | marketplace-name | plugins...
PLUGINS=(
  "anthropics/skills|anthropic-agent-skills|document-skills example-skills claude-api"
  "thedotmack/claude-mem|thedotmack|claude-mem"
  "upstash/context7|context7-marketplace|context7"
  "kajisho5/ffmpeg-skill|ffmpeg-skill|ffmpeg-skill"
  "heygen-com/hyperframes|hyperframes|hyperframes"
)
if command -v claude >/dev/null 2>&1; then
  for entry in "${PLUGINS[@]}"; do
    IFS='|' read -r repo market plugins <<<"$entry"
    step "Claude plugin marketplace: $repo"
    claude plugin marketplace add "$repo" >/dev/null 2>&1 || true
    for p in $plugins; do
      run "plugin:$p" claude plugin install "$p@$market" --scope user
    done
  done
else
  echo "claude CLI not found: plugins will be offered from .claude/settings.json when you open this repo."
fi

# --- 3. Skills installed by copying into ~/.claude/skills -------------------
step "claude-shorts (long video -> vertical Shorts)"
run claude-shorts bash -c "
  clone_dir='$SRC_DIR/claude-shorts'
  if [ -d \"\$clone_dir/.git\" ]; then git -C \"\$clone_dir\" pull -q --ff-only; else git clone -q --depth 1 https://github.com/AgriciDaniel/claude-shorts.git \"\$clone_dir\"; fi
  bash \"\$clone_dir/install.sh\" >/dev/null && python3 -m pip install -q -r \"\$clone_dir/requirements.txt\"
"

step "ghost-editor (raw talking-head footage -> polished reel)"
run ghost-editor clone_or_update kurbaitaev/ghost-editor "$SKILLS_DIR/ghost-editor"
# Its full asset setup (fonts, SFX, Whisper model) lives in docs/INSTALL.md; ask Claude
# "follow ~/.claude/skills/ghost-editor/docs/INSTALL.md" on the machine where you edit.

step "MotionClone (rebuild a reference video as an editable HyperFrames project)"
run MotionClone clone_or_update blixvip/MotionClone "$SRC_DIR/MotionClone"

# --- 4. Optional / reference --------------------------------------------------
if [ "$WITH_GAME_STUDIOS" = 1 ]; then
  step "Claude-Code-Game-Studios (template project: 49 agents, 74 skills)"
  run game-studios clone_or_update Donchitos/Claude-Code-Game-Studios "$HOME/claude-game-studios"
fi

step "awesome-claude-code (reference list)"
run awesome-claude-code clone_or_update hesreallyhim/awesome-claude-code "$SRC_DIR/awesome-claude-code"

# --- Summary ---------------------------------------------------------------
printf '\n\033[1;32mInstalled (%d):\033[0m %s\n' "${#ok[@]}" "${ok[*]:-}"
if [ "${#fail[@]}" -gt 0 ]; then
  printf '\033[1;31mFailed (%d):\033[0m %s\n' "${#fail[@]}" "${fail[*]}"
  exit 1
fi
