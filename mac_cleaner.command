#!/bin/bash
# Mac Junk Cleaner — macOS
# Remove .DS_Store, ._* (resource forks), __MACOSX e outros arquivos macOS
#
# PRIMEIRA VEZ: botao direito no arquivo → Abrir (passa pelo Gatekeeper)
# PROXIMAS VEZES: duplo clique normal

set -euo pipefail

# ── Selecionar pasta ──────────────────────────────────────────────────────────
FOLDER=$(osascript 2>/dev/null <<'APPLESCRIPT'
tell application "Finder"
    set selectedFolder to choose folder with prompt "Selecione a pasta para limpar arquivos macOS:"
    return POSIX path of selectedFolder
end tell
APPLESCRIPT
) || true

# Strip trailing slash
FOLDER="${FOLDER%/}"

if [[ -z "$FOLDER" ]]; then
    osascript -e 'display dialog "Nenhuma pasta selecionada." buttons {"OK"} default button "OK" with icon caution with title "Mac Junk Cleaner"' 2>/dev/null || true
    exit 0
fi

echo ""
echo "  Mac Junk Cleaner"
echo "  ────────────────────────────────────────"
echo "  Pasta: $FOLDER"
echo ""
echo "  Escaneando..."

# ── Scan ──────────────────────────────────────────────────────────────────────
DS_LIST=$(find "$FOLDER" -name ".DS_Store"       ! -type d 2>/dev/null || true)
RF_LIST=$(find "$FOLDER" -name "._*"             ! -type d 2>/dev/null || true)
MX_LIST=$(find "$FOLDER" -name "__MACOSX"        -type d   2>/dev/null || true)
SP_LIST=$(find "$FOLDER" -name ".Spotlight-V100" -type d   2>/dev/null || true)
TR_LIST=$(find "$FOLDER" -name ".Trashes"        -type d   2>/dev/null || true)

count_lines() { echo "$1" | grep -c . 2>/dev/null || echo 0; }

DS_COUNT=0; RF_COUNT=0; MX_COUNT=0; SP_COUNT=0; TR_COUNT=0
[[ -n "$DS_LIST" ]] && DS_COUNT=$(count_lines "$DS_LIST")
[[ -n "$RF_LIST" ]] && RF_COUNT=$(count_lines "$RF_LIST")
[[ -n "$MX_LIST" ]] && MX_COUNT=$(count_lines "$MX_LIST")
[[ -n "$SP_LIST" ]] && SP_COUNT=$(count_lines "$SP_LIST")
[[ -n "$TR_LIST" ]] && TR_COUNT=$(count_lines "$TR_LIST")

TOTAL=$((DS_COUNT + RF_COUNT + MX_COUNT + SP_COUNT + TR_COUNT))

echo "  Resultado:"
[[ $DS_COUNT -gt 0 ]] && echo "    .DS_Store         $DS_COUNT arquivo(s)"
[[ $RF_COUNT -gt 0 ]] && echo "    ._* (res. forks)  $RF_COUNT arquivo(s)"
[[ $MX_COUNT -gt 0 ]] && echo "    __MACOSX          $MX_COUNT pasta(s)"
[[ $SP_COUNT -gt 0 ]] && echo "    .Spotlight-V100   $SP_COUNT pasta(s)"
[[ $TR_COUNT -gt 0 ]] && echo "    .Trashes          $TR_COUNT pasta(s)"
echo "  ────────────────────────────────────────"
echo "  TOTAL: $TOTAL itens"
echo ""

# ── Pasta limpa ───────────────────────────────────────────────────────────────
if [[ $TOTAL -eq 0 ]]; then
    osascript 2>/dev/null <<APPLESCRIPT || true
display dialog "✅ Pasta limpa!

Nenhum arquivo macOS encontrado em:
$FOLDER" buttons {"OK"} default button "OK" with icon note with title "Mac Junk Cleaner"
APPLESCRIPT
    echo "  Pasta ja esta limpa. Nada a deletar."
    exit 0
fi

# ── Confirmacao ───────────────────────────────────────────────────────────────
BREAKDOWN=""
[[ $DS_COUNT -gt 0 ]] && BREAKDOWN+="• .DS_Store: $DS_COUNT\n"
[[ $RF_COUNT -gt 0 ]] && BREAKDOWN+="• ._* (resource forks): $RF_COUNT\n"
[[ $MX_COUNT -gt 0 ]] && BREAKDOWN+="• __MACOSX: $MX_COUNT pasta(s)\n"
[[ $SP_COUNT -gt 0 ]] && BREAKDOWN+="• .Spotlight-V100: $SP_COUNT\n"
[[ $TR_COUNT -gt 0 ]] && BREAKDOWN+="• .Trashes: $TR_COUNT\n"

CONFIRM=$(osascript 2>/dev/null <<APPLESCRIPT || echo "cancel"
set msg to "Encontrados $TOTAL itens para deletar em:
$FOLDER

$(printf "$BREAKDOWN")
Esta acao nao pode ser desfeita."
display dialog msg buttons {"Cancelar", "Deletar tudo"} default button "Cancelar" cancel button "Cancelar" with icon caution with title "Mac Junk Cleaner"
return "ok"
APPLESCRIPT
)

if [[ "$CONFIRM" != "ok" ]]; then
    echo "  Cancelado pelo usuario."
    exit 0
fi

# ── Deletar ───────────────────────────────────────────────────────────────────
echo "  Deletando..."
DELETED=0
ERRORS=0

delete_file() {
    if rm -f "$1" 2>/dev/null; then
        ((DELETED++))
    else
        ((ERRORS++))
    fi
}

delete_dir() {
    if rm -rf "$1" 2>/dev/null; then
        ((DELETED++))
    else
        ((ERRORS++))
    fi
}

# .DS_Store
if [[ -n "$DS_LIST" ]]; then
    while IFS= read -r f; do
        [[ -n "$f" ]] && delete_file "$f"
        echo "    ✓ $(basename "$f")"
    done <<< "$DS_LIST"
fi

# ._* resource forks
if [[ -n "$RF_LIST" ]]; then
    while IFS= read -r f; do
        [[ -n "$f" ]] && delete_file "$f"
        echo "    ✓ $(basename "$f")"
    done <<< "$RF_LIST"
fi

# __MACOSX (pasta inteira)
if [[ -n "$MX_LIST" ]]; then
    while IFS= read -r d; do
        [[ -n "$d" ]] && delete_dir "$d"
        echo "    ✓ __MACOSX/"
    done <<< "$MX_LIST"
fi

# .Spotlight-V100
if [[ -n "$SP_LIST" ]]; then
    while IFS= read -r d; do
        [[ -n "$d" ]] && delete_dir "$d"
        echo "    ✓ .Spotlight-V100/"
    done <<< "$SP_LIST"
fi

# .Trashes
if [[ -n "$TR_LIST" ]]; then
    while IFS= read -r d; do
        [[ -n "$d" ]] && delete_dir "$d"
        echo "    ✓ .Trashes/"
    done <<< "$TR_LIST"
fi

echo ""
echo "  ────────────────────────────────────────"

# ── Resultado ─────────────────────────────────────────────────────────────────
if [[ $ERRORS -eq 0 ]]; then
    echo "  ✅ $DELETED itens deletados com sucesso."
    osascript 2>/dev/null <<APPLESCRIPT || true
display dialog "✅ $DELETED itens deletados com sucesso!

Pasta limpa:
$FOLDER" buttons {"OK"} default button "OK" with icon note with title "Mac Junk Cleaner"
APPLESCRIPT
else
    echo "  ⚠️  $DELETED deletados · $ERRORS erros (permissao negada?)"
    osascript 2>/dev/null <<APPLESCRIPT || true
display dialog "$DELETED itens deletados.
$ERRORS erros (permissao negada?).

Pasta: $FOLDER" buttons {"OK"} default button "OK" with icon caution with title "Mac Junk Cleaner"
APPLESCRIPT
fi

echo ""
