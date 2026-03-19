#!/usr/bin/env bash
# zapret2agent installer
# Usage: bash install.sh [--global]
#   --global  Register skills in ~/.claude/skills/ (symlinks)

set -euo pipefail

REPO_URL="https://github.com/howdeploy/Zapret2agent.git"
REPO_DIR="Zapret2agent"
SKILLS=(zapret-diagnose zapret-install zapret-config zapret-manage zapret-modes)

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Prerequisite checks ────────────────────────────────────
check_prerequisites() {
    local missing=()

    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v bash >/dev/null 2>&1 || missing+=("bash")

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing prerequisites: ${missing[*]}"
        echo "Install them and try again."
        exit 1
    fi
    ok "Prerequisites: git, bash"
}

# ── Detect AI agent ─────────────────────────────────────────
detect_agent() {
    local agents=()

    if command -v claude >/dev/null 2>&1; then
        agents+=("claude")
    fi
    if command -v codex >/dev/null 2>&1; then
        agents+=("codex")
    fi

    if [[ ${#agents[@]} -eq 0 ]]; then
        warn "No AI agent found (claude or codex)."
        echo ""
        echo "Install one of:"
        echo "  Claude Code: https://docs.anthropic.com/en/docs/claude-code/overview"
        echo "  Codex CLI:   https://github.com/openai/codex"
        echo ""
        echo "After installing, run the agent in the repo directory."
        return
    fi

    ok "Found: ${agents[*]}"

    if [[ ${#agents[@]} -eq 1 ]]; then
        AGENT="${agents[0]}"
    else
        echo ""
        echo "Multiple agents detected. Which one to use?"
        echo "  1) claude  — Claude Code (reads CLAUDE.md)"
        echo "  2) codex   — Codex CLI (reads AGENTS.md)"
        read -rp "Choice [1]: " choice
        case "${choice:-1}" in
            2) AGENT="codex" ;;
            *) AGENT="claude" ;;
        esac
    fi
}

# ── Clone repo ──────────────────────────────────────────────
clone_repo() {
    if [[ -d "$REPO_DIR" ]]; then
        if [[ -d "$REPO_DIR/.git" ]]; then
            info "Directory $REPO_DIR already exists. Pulling latest..."
            git -C "$REPO_DIR" pull --ff-only || warn "Pull failed. Using existing version."
            ok "Updated: $REPO_DIR"
            return
        else
            err "$REPO_DIR exists but is not a git repo."
            exit 1
        fi
    fi

    info "Cloning $REPO_URL..."
    git clone "$REPO_URL"
    ok "Cloned: $REPO_DIR"
}

# ── Global skill registration ──────────────────────────────
register_skills_global() {
    local skills_dir="$HOME/.claude/skills"
    local repo_abs
    repo_abs="$(cd "$REPO_DIR" && pwd)"

    mkdir -p "$skills_dir"

    local linked=0
    for skill in "${SKILLS[@]}"; do
        local target="$repo_abs/.claude/skills/$skill"
        local link="$skills_dir/$skill"

        if [[ -L "$link" ]]; then
            # Already a symlink — check if pointing to our repo
            local current_target
            current_target="$(readlink -f "$link")"
            if [[ "$current_target" == "$repo_abs/.claude/skills/$skill" ]]; then
                continue  # Already correct
            fi
            warn "$skill: symlink exists, points elsewhere ($current_target). Skipping."
            continue
        elif [[ -e "$link" ]]; then
            warn "$skill: already exists as regular file/dir. Skipping."
            continue
        fi

        ln -sf "$target" "$link"
        ((linked++))
    done

    if [[ $linked -gt 0 ]]; then
        ok "Registered $linked skill(s) globally in $skills_dir"
    else
        ok "All skills already registered globally"
    fi
    info "Claude Code can now manage zapret2 from any directory."
}

# ── Main ────────────────────────────────────────────────────
main() {
    local global_flag=false

    for arg in "$@"; do
        case "$arg" in
            --global) global_flag=true ;;
            --help|-h)
                echo "Usage: bash install.sh [--global]"
                echo ""
                echo "Clones zapret2agent and detects your AI agent (Claude Code / Codex)."
                echo ""
                echo "Options:"
                echo "  --global  Register skills in ~/.claude/skills/ as symlinks"
                echo "            so Claude Code can manage zapret2 from any directory"
                exit 0
                ;;
        esac
    done

    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║  zapret2agent installer                   ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    clone_repo
    detect_agent

    if [[ "$global_flag" == true ]]; then
        register_skills_global
    fi

    echo ""
    echo "────────────────────────────────────────────"
    echo ""
    ok "Ready!"
    echo ""
    echo "  cd $REPO_DIR"

    if [[ -n "${AGENT:-}" ]]; then
        echo "  $AGENT"
    else
        echo "  claude   # or: codex"
    fi

    echo ""

    if [[ "$global_flag" == false ]]; then
        info "Tip: run with --global to register skills globally:"
        echo "  bash install.sh --global"
        echo "  This lets Claude Code manage zapret2 from any directory."
    fi

    echo ""
}

main "$@"
