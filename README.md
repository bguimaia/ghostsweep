# Mac Junk Cleaner

Remove `.DS_Store`, `._*` (resource forks) e `__MACOSX` de qualquer pasta — no Windows e no macOS.

Zero dependências. Sem instalar nada.

---

## Windows

Cole no PowerShell e pressione Enter:

```powershell
irm "https://raw.githubusercontent.com/bguimaia/mac-junk-cleaner/main/mac_cleaner.ps1" | iex
```

Ou faça download de `Limpar Mac Junk.bat` e dê duplo clique.

## macOS

```bash
curl -fsSL "https://raw.githubusercontent.com/bguimaia/mac-junk-cleaner/main/mac_cleaner.command" | bash
```

Ou baixe `mac_cleaner.command`, dê `chmod +x` e duplo clique no Finder (primeira vez: botão direito → Abrir).

---

## O que remove

| Arquivo | Descrição |
|---------|-----------|
| `.DS_Store` | Metadados de pasta do macOS |
| `._ARQUIVO` | Resource forks — aparecem como arquivos corrompidos no Windows |
| `__MACOSX/` | Pasta fantasma criada ao descompactar zips no macOS |
| `.Spotlight-V100` | Índice de busca do Spotlight |
| `.Trashes` | Lixeira de drives externos |
