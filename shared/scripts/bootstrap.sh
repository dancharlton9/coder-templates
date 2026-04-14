#!/bin/bash
# bootstrap.sh — Run at the start of every workspace startup.
# Handles SSH known hosts, npm global path, and Claude Code installation.

# ── SSH / Git setup ───────────────────────────────────────────────────────────
mkdir -p ~/.ssh
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null

# ── npm global path (persistent across terminals) ─────────────────────────────
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
export PATH=~/.npm-global/bin:$PATH
grep -q '.npm-global/bin' ~/.bashrc 2>/dev/null || \
  echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc

# ── Claude Code ───────────────────────────────────────────────────────────────
if ! command -v claude &> /dev/null; then
  npm install -g @anthropic-ai/claude-code
fi
